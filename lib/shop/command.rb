# Shop::Command: the single-threaded supervisor every child runs under (one IO.select loop stepping Shop::Child state machines).

module Shop
  module Command
    Result = Data.define(:exit_code, :stdout, :stderr_tail, :timed_out, :overflowed)

    # The longest the select loop sleeps between steps.
    TICK = 0.1

    module_function

    # Run one child to completion. See run_all for the spec keys.
    def run(argv, env:, deadline:, max_stdout:, stdout_mode: nil, cli: false, on_tick: nil, extra_io: {})
      spec = { argv: argv, env: env, deadline: deadline, max_stdout: max_stdout, cli: cli }
      spec[:stdout_mode] = stdout_mode if stdout_mode
      run_all([spec], concurrency: 1, on_tick: on_tick, extra_io: extra_io).first
    end

    # Run `specs` (hashes: argv, env, deadline, max_stdout, [stdout_mode],
    # [cli]: a Shopify CLI call, which names the code of a failed spawn)
    # with at most `concurrency` alive at once; stdout past
    # max_stdout kills the child unless stdout_mode is :tail, which keeps the
    # last bytes. All run inside the optional `overall` Deadline. Returns
    # Results in spec order. `on_done(index, result)` fires as each finishes;
    # `on_tick(children)` fires every tick; `extra_io` maps readable IOs to
    # callbacks.
    #
    # A signal or the loss of the parent stops every child (TERM, grace,
    # KILL, reap) and then raises `terminated`.
    def run_all(specs, concurrency:, overall: nil, on_done: nil, on_tick: nil, extra_io: {})
      queue = specs.each_with_index.map { |spec, i| Child.new(i, spec) }
      results = Array.new(specs.size)
      active = []
      stopping = false
      begin
        loop do
          if !stopping && Signals.stop_requested?
            stopping = true
            active.each { |child| child.stop!(:request) }
            queue.clear
          end
          if overall&.expired?
            active.each { |child| child.stop!(:timeout) }
            queue.each { |child| results[child.index] = never_started }
            queue.clear
          end
          while !stopping && active.size < concurrency && !queue.empty?
            child = queue.shift
            child.spec[:deadline] = overall.cap(child.spec.fetch(:deadline)) if overall
            child.start!
            active << child
          end
          break if active.empty? && queue.empty?

          pump(active, extra_io, active.map(&:wait_hint).min)
          # A child whose pipes just hit EOF goes running -> draining -> done
          # in one pass instead of sleeping a tick between the steps.
          loop { break unless active.map(&:advance).any? }
          active.select(&:done?).each do |child|
            active.delete(child)
            results[child.index] = child.result
            on_done&.call(child.index, child.result)
          end
          on_tick&.call(active) unless active.empty?
        end
      ensure
        active.each(&:force_kill!)
      end
      Signals.check! if stopping
      results
    end

    # The Result of a queued child the overall deadline cut before it started.
    def never_started
      Result.new(exit_code: nil, stdout: '', stderr_tail: '', timed_out: true, overflowed: false)
    end

    # Wait up to `timeout` for any child pipe, extra IO or the signal pipe,
    # and hand what is readable to its owner.
    def pump(children, extra_io, timeout)
      owners = {}
      children.each { |child| child.readers.each { |io| owners[io] = child } }
      ios = owners.keys + extra_io.keys
      ios << Signals.reader if Signals.reader
      ready, = IO.select(ios, nil, nil, timeout)
      (ready || []).each do |io|
        if (child = owners[io])
          child.read_from(io)
        elsif extra_io.key?(io)
          extra_io[io].call(io)
        end
      end
    end
  end
end
