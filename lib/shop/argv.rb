# Shop::Argv: the helpers' long-flag grammar (--name=value, --name value, switches), strict UTF-8; usage errors raise invalid_argument via Validate.reject!.

module Shop
  module Argv
    module_function

    # Long flags only, as `--name=value` or `--name value`; `values` and
    # `switches` name them without the dashes, `required` the values that
    # must be given. `--help` anywhere prints the usage and exits 0. An
    # unknown flag, a stray argument, a repeated flag, a missing value, a
    # known flag given as a value, a switch given a value, a required flag
    # left out or an argument that is not valid UTF-8 raises
    # `invalid_argument`. Returns {name => value or true}.
    def parse(argv, values: [], switches: [], required: [], usage:)
      argv = argv.map { |a| utf8!(a) }
      if argv.include?('--help')
        $stdout.write(usage.end_with?("\n") ? usage : "#{usage}\n")
        $stdout.flush
        exit 0
      end

      known = (values + switches).map { |n| "--#{n}" }
      options = {}
      i = 0
      while i < argv.length
        arg = argv[i]
        Validate.reject!("unexpected argument: #{Text.quote(arg)}") unless arg.start_with?('--')
        name, inline = arg[2..].split('=', 2)
        Validate.reject!("repeated flag: --#{name}") if options.key?(name)
        if values.include?(name)
          value = inline
          if value.nil?
            i += 1
            value = argv[i]
          end
          if value.nil? || value.empty? || known.include?(value.split('=', 2).first)
            Validate.reject!("missing value for --#{name}")
          end
          options[name] = value
        elsif switches.include?(name)
          Validate.reject!("--#{name} takes no value") unless inline.nil?
          options[name] = true
        else
          Validate.reject!("unknown flag: #{Text.quote("--#{name}")}")
        end
        i += 1
      end
      required.each { |name| Validate.reject!("missing --#{name}") unless options.key?(name) }
      options
    end

    # argv arrives in the locale's encoding (binary under LANG=C); every
    # argument is read as UTF-8 and must be valid.
    def utf8!(arg)
      s = Text.as_utf8(arg)
      Validate.reject!('argument is not valid UTF-8') unless s.valid_encoding?
      s
    end
  end
end
