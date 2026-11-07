# Shop::Signals: trap-safe TERM/INT/HUP handling (self-pipe only) and the registry of live child process groups.

module Shop
  module Signals
    SIGNALS = %w[TERM INT HUP].freeze
    # Bytes read from the self-pipe per drain step.
    DRAIN_CHUNK = 64
    # The longest Signals.sleep waits between two looks for a lost parent
    # (a signal wakes it at once through the self-pipe).
    SLEEP_POLL = 0.1
    @pending = nil
    @reader = nil
    @writer = nil
    @pgids = [].freeze
    @ppid = nil

    class << self
      attr_reader :reader

      # A trap only records the signal and writes one byte to the self-pipe;
      # nothing else runs in trap context. The supervisor loop selects on the
      # reader, so a signal wakes it immediately.
      def install!
        @reader, @writer = IO.pipe
        @ppid = Process.ppid
        SIGNALS.each do |sig|
          trap(sig) do
            @pending ||= sig
            @writer.write_nonblock('x', exception: false)
          end
        end
        # Net: any group still registered at exit (an exception between spawn
        # and reap) is killed. Command unregisters right after a group is
        # gone, so this never hits a reused pgid.
        at_exit { kill_registered! }
      end

      def parent_lost?
        !@ppid.nil? && Process.ppid != @ppid
      end

      # Raise `terminated` when a signal arrived or the parent went away.
      def check!
        return unless stop_requested?

        why = @pending ? "received SIG#{@pending}" : 'parent process exited'
        raise Failure.new('terminated', why)
      end

      def stop_requested?
        drain
        !@pending.nil? || parent_lost?
      end

      # Sleep `seconds`, but raise `terminated` as soon as a signal arrives
      # or the parent goes away (Signals.check!).
      def sleep(seconds)
        until_at = Deadline.now + seconds
        loop do
          check!
          left = until_at - Deadline.now
          return if left <= 0

          wait = [left, SLEEP_POLL].min
          @reader ? IO.select([@reader], nil, nil, wait) : Kernel.sleep(wait)
        end
      end

      def drain
        return unless @reader

        loop { break if @reader.read_nonblock(DRAIN_CHUNK, exception: false).is_a?(Symbol) }
      rescue IOError
        nil
      end

      # Copy-on-write so the at_exit net always sees a consistent array.
      def register(pgid)
        @pgids = (@pgids + [pgid]).freeze
      end

      def unregister(pgid)
        @pgids = (@pgids - [pgid]).freeze
      end

      # Test hook: the leak check in test_command.rb reads it.
      def registered
        @pgids
      end

      def kill_registered!
        @pgids.each do |pgid|
          Process.kill(:KILL, -pgid)
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
