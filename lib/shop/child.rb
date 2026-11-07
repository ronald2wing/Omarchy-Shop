# Shop::Child: one supervised child process (setpriv pdeathsig, own process group, deadline, TERM->KILL, reap, byte caps) stepped by Shop::Command.

module Shop
  # States: :new -> :running -> (:draining | :terminating) -> :done.
  class Child
    KILL_GRACE = 3.0
    # After the leader exits on its own: how long the group may keep the
    # pipes open before it is killed.
    DRAIN = 3.0
    READ_CHUNK = 64 * KIB
    MAX_STDERR = 64 * KIB
    # Once a running leader has closed its pipes it is exiting, but /proc may
    # not show the zombie yet: the loop polls this often for this long
    # instead of sleeping a whole Command::TICK.
    EXIT_POLL = 0.005
    EXIT_POLL_WINDOW = 1.0
    # The most READ_CHUNK reads that collect what a dead group left in a pipe.
    DRAIN_READS = 64

    # The TERM -> KILL grace (the `kill_grace:` test override shortens it).
    def self.kill_grace
      value = Shop.overrides[:kill_grace]
      value.is_a?(Numeric) ? value : KILL_GRACE
    end

    attr_reader :index, :spec, :result

    def initialize(index, spec)
      @index = index
      @spec = spec
      @state = :new
      @stdout = String.new(encoding: Encoding::BINARY)
      @stderr = String.new(encoding: Encoding::BINARY)
      @flags = { timed_out: false, overflowed: false }
      @group_empty = false
    end

    # Spawn the child. A spawn that fails (no setpriv, no run dir) is
    # `cli_failed` for a CLI call (spec cli: true) and `tool_failed` for
    # anything else, so a missing tool is never blamed on the Shopify CLI.
    def start!
      @out, out_w = IO.pipe
      @err, err_w = IO.pipe
      argv = [Tools.path(:setpriv), '--pdeathsig', 'KILL', '--', *@spec.fetch(:argv)]
      program = File.basename(@spec.fetch(:argv).first.to_s)
      begin
        @pid = Process.spawn(@spec.fetch(:env), *argv,
                             pgroup: true, unsetenv_others: true, close_others: true,
                             in: File::NULL, out: out_w, err: err_w, chdir: Paths.run_dir)
      rescue SystemCallError => e
        [@out, @err].each { |io| io&.close }
        code = @spec[:cli] ? 'cli_failed' : 'tool_failed'
        raise Failure.new(code, "could not start #{program}: #{Text.os_error(e)}")
      end
      Signals.register(@pid)
      @deadline_at = Deadline.now + @spec.fetch(:deadline)
      @state = :running
    ensure
      out_w&.close
      err_w&.close
    end

    # The child leads its own group, so the group id is its pid.
    def pgid = @pid

    def readers
      [@out, @err].compact
    end

    def pipes_closed?
      @out.nil? && @err.nil?
    end

    def done? = @state == :done

    # How long the select loop may sleep for this child: 0 when the next
    # advance finishes it (draining with the pipes closed, or past kill_at);
    # EXIT_POLL while a running leader has just closed its pipes (sleeping a
    # whole tick there would add TICK to every short call); else TICK.
    def wait_hint
      return 0 if (@state == :draining && pipes_closed?) || (@state == :terminating && Deadline.now >= @kill_at)
      return EXIT_POLL if @state == :running && pipes_closed? && Deadline.now - @pipes_closed_at < EXIT_POLL_WINDOW

      Command::TICK
    end

    # Read whatever `io` has; EOF closes it.
    def read_from(io)
      data = io.read_nonblock(READ_CHUNK, exception: false)
      return if data == :wait_readable

      if data.nil?
        close_reader(io)
      else
        append(io, data)
      end
    rescue IOError, SystemCallError
      close_reader(io)
    end

    # Ask the group to stop: TERM now, KILL after the grace period.
    def stop!(reason)
      # Only a running child can time out: one whose leader already exited
      # (draining) keeps its real outcome when an overall deadline expires
      # while its pipes drain.
      return if reason == :timeout && @state != :running

      case reason
      when :timeout then @flags[:timed_out] = true
      when :overflow then @flags[:overflowed] = true
      end
      # Any other reason (:request) sets no flag; a repeat call is a no-op once past :running.
      return unless @state == :running

      ProcessGroup.signal(pgid, :TERM)
      @kill_at = Deadline.now + Child.kill_grace
      @state = :terminating
    end

    # One step of the state machine; returns true when the state changed.
    def advance
      before = @state
      now = Deadline.now
      case @state
      when :running
        if now >= @deadline_at
          stop!(:timeout)
        elsif ProcessGroup.exited?(@pid)
          # The leader is a zombie (not reaped, so its pid and the pgid
          # cannot be reused): TERM what is left of the group, then let the
          # pipes drain.
          ProcessGroup.signal(pgid, :TERM)
          @drain_until = now + DRAIN
          @state = :draining
        end
      when :draining
        finish! if pipes_closed? || now >= @drain_until
      when :terminating
        if now >= @kill_at
          finish!
        elsif ProcessGroup.exited?(@pid)
          @group_empty = ProcessGroup.members(pgid, except: @pid).empty?
          finish! if @group_empty
        end
      end
      @state != before
    end

    # Last resort when the supervisor itself is unwinding on an exception.
    def force_kill!
      return if @state == :done || @state == :new

      ProcessGroup.signal(pgid, :KILL)
      begin
        Process.waitpid(@pid)
      rescue Errno::ECHILD
        nil
      end
      ProcessGroup.wait_gone(pgid)
      Signals.unregister(pgid)
      @state = :done
    end

    private

    def close_reader(io)
      io.close unless io.closed?
      @out = nil if io.equal?(@out)
      @err = nil if io.equal?(@err)
      @pipes_closed_at ||= Deadline.now if pipes_closed?
    end

    def append(io, data)
      io.equal?(@out) ? append_stdout(data) : append_stderr(data)
    end

    def append_stdout(data)
      max = @spec.fetch(:max_stdout)
      if @spec[:stdout_mode] == :tail
        @stdout = keep_tail(@stdout, data, max)
      elsif @state == :running || @state == :draining
        room = max - @stdout.bytesize
        if data.bytesize > room
          @stdout << data.byteslice(0, [room, 0].max)
          stop!(:overflow)
        else
          @stdout << data
        end
      end
    end

    def append_stderr(data)
      @stderr = keep_tail(@stderr, data, MAX_STDERR)
    end

    # `buf` + `data`, cut to its last `max` bytes.
    def keep_tail(buf, data, max)
      buf << data
      buf.bytesize > max ? buf.byteslice(buf.bytesize - max, max) : buf
    end

    # KILL the group, then reap the leader, then wait for the group to be
    # gone (skipped when the last advance already saw it empty), then
    # unregister. The group is always signalled before the leader is
    # reaped (the PID-reuse guard).
    def finish!
      ProcessGroup.signal(pgid, :KILL)
      status = begin
        Process.waitpid2(@pid)&.last
      rescue Errno::ECHILD
        nil
      end
      ProcessGroup.wait_gone(pgid) unless @group_empty
      Signals.unregister(pgid)
      drain_remaining
      readers.each { |io| close_reader(io) }
      @state = :done
      @result = Command::Result.new(
        exit_code: ProcessGroup.exit_code(status),
        stdout: Text.scrub(@stdout),
        stderr_tail: Text.scrub(@stderr),
        timed_out: @flags[:timed_out],
        overflowed: @flags[:overflowed]
      )
    end

    # Whatever is still buffered in the pipes once the group is dead.
    def drain_remaining
      readers.each do |io|
        DRAIN_READS.times do
          data = io.read_nonblock(READ_CHUNK, exception: false)
          break if data == :wait_readable || data.nil?

          append(io, data)
        end
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
