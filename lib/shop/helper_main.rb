# Shop::HelperMain: the body every helper runs in (env scrub, test overrides, umask, signals, argv, the overall deadline, state dirs) and the one-JSON-line emitter.

module Shop
  module HelperMain
    # The cap on a line until the helper's TIMING row is known (a usage
    # error of a helper whose row depends on its argv).
    DEFAULT_STDOUT_CAP = 1 * MIB

    @stdout_cap = DEFAULT_STDOUT_CAP
    @overall = nil
    @line_fields = {}

    class << self
      # The byte cap on each line this helper prints (its TIMING row's cap).
      attr_accessor :stdout_cap
      # The helper's overall Deadline (its TIMING row's H), nil outside a
      # helper (unit tests).
      attr_reader :overall
    end

    module_function

    # The body of every helper: scrub the interpreter env, apply test
    # overrides, umask 077, trap-safe signals, start the overall deadline,
    # parse argv (Argv.parse; `required` names the value flags that must be
    # given), prepare the state dirs, run the block with (options, overall)
    # and emit its result (a Hash) as the one stdout line; a Failure becomes
    # the failure line and its exit status.
    #
    # `helper` names the TIMING row whose deadline H and output cap apply,
    # or is a lambda that picks the row from the parsed options (fetch-sales:
    # one row per range); a usage error then still fails under the default
    # cap. `last_event` ('done' or 'exited') makes the failure line that
    # streamer's last event. `line_fields` declares the top-level fields
    # every line this helper prints carries (success, failure, a stop, an
    # internal error or the output_too_large line alike), with their
    # starting values, until set_line_fields! changes them; a success's own
    # value of a field wins (the theme writers' writeStarted, backupId,
    # folderCopy: Shop::ThemeJob sets them).
    def main(argv, overrides = {}, helper:, usage:, values: [], switches: [], required: [], last_event: nil, prepare: true, line_fields: {})
      scrub_interpreter_env!
      @line_fields = line_fields.dup
      @last_event = last_event
      Shop.override!(overrides)
      File.umask(0o077)
      Signals.install!
      start!(helper) unless helper.respond_to?(:call)
      options = Argv.parse(argv, values: values, switches: switches, required: required, usage: usage)
      start!(helper.call(options)) if helper.respond_to?(:call)
      Paths.prepare! if prepare
      result = yield options, @overall
      exit 1 if emit(result.merge(@line_fields.reject { |key, _| result.key?(key) })) == :replaced
      exit 0
    rescue Failure => e
      emit(failure_line(e))
      exit e.exit_code
    rescue SignalException
      emit(failure_line(Failure.new('terminated', 'interrupted')))
      exit 143
    rescue StandardError => e
      emit(failure_line(Failure.new('internal_error', "unexpected #{e.class}: #{Text.os_error(e)}")))
      exit 1
    end

    # Take TIMING row `row`: its output cap, and the overall deadline from now.
    def start!(row)
      HelperMain.stdout_cap = TIMING.fetch(row).fetch(:cap)
      @overall = Deadline.new(Shop.seconds(:helper, row))
    end

    # `seconds`, but no more than what is left of the overall deadline (all
    # of it outside a helper).
    def overall_cap(seconds)
      @overall ? @overall.cap(seconds) : seconds
    end

    # Set line fields of whatever line this helper prints from now on (only
    # the ones main declared: a field no helper declared stays off).
    def set_line_fields!(fields)
      fields.each { |key, value| @line_fields[key] = value if @line_fields.key?(key) }
    end

    # Remove the Ruby/Bundler variables that could inject code or load
    # paths into later loads and any child process. The hardened shebang is
    # the real control; children also get allowlisted envs (Shop::Env).
    def scrub_interpreter_env!
      %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH].each { |key| ENV.delete(key) }
      ENV.delete_if { |key, _| key.start_with?('BUNDLE_') }
    end

    # Write one JSON line. A closed reader (EPIPE) never aborts the helper:
    # it still reaps its children and exits with its intended code. Returns
    # :replaced when the line was over the cap and the output_too_large
    # failure line (with the line fields) went out instead (the caller must
    # then exit 1), else nil.
    def emit(obj)
      line = "#{JSON.generate(utf8_strings(obj))}\n"
      status = nil
      if line.bytesize > stdout_cap
        too_large = { 'ok' => false, 'error' => { 'code' => 'output_too_large', 'message' => 'helper output over its cap' } }
        line = "#{JSON.generate(utf8_strings(too_large.merge(@line_fields)))}\n"
        status = :replaced
      end
      begin
        $stdout.write(line)
        $stdout.flush
      rescue Errno::EPIPE, IOError
        return status
      end
      status
    end

    # `obj` with every String that is not valid UTF-8 scrubbed (Text.scrub),
    # so a filesystem- or CLI-derived string (a realpath, a refused entry's
    # name) never turns a helper result into a JSON::GeneratorError.
    def utf8_strings(obj)
      case obj
      when String then obj.encoding == Encoding::UTF_8 && obj.valid_encoding? ? obj : Text.scrub(obj)
      when Hash then obj.to_h { |k, v| [utf8_strings(k), utf8_strings(v)] }
      when Array then obj.map { |v| utf8_strings(v) }
      else obj
      end
    end

    # The failure line: {ok: false, error, details?} plus the line fields,
    # or for a streamer its last event {event, ok: false, error} (no
    # details: a stream's last line stays small).
    def failure_line(failure)
      line = { 'ok' => false, 'error' => failure.to_error }
      if @last_event
        line = { 'event' => @last_event }.merge(line)
      elsif failure.details
        line['details'] = failure.details
      end
      line.merge!(@line_fields)
    end
  end
end
