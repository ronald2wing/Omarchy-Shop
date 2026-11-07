# Shop::Json: reading JSON Shop did not write (CLI output, package.json, backup meta) without trusting its shape: bounded parses to an object or nil, and the one nil-safe dig.

module Shop
  module Json
    # The deepest nesting a parse accepts unless the caller asks for less.
    MAX_NESTING = 64

    module_function

    # Hash#dig for JSON from outside: walks `keys` only while the current
    # value is a Hash, else nil. Valid JSON of the wrong shape (a string
    # where an object belongs) must never raise TypeError/NoMethodError;
    # callers decide whether nil is malformed (bad_response) or ignorable.
    # Use it in place of every `.dig` on parsed CLI output.
    def dig(obj, *keys)
      keys.reduce(obj) { |value, key| value.is_a?(Hash) ? value[key] : (return nil) }
    end

    # The JSON object `text` holds, or nil (not JSON, nested deeper than
    # `max_nesting`, or valid JSON that is not an object).
    def object(text, max_nesting: MAX_NESTING)
      value = JSON.parse(text.to_s, max_nesting: max_nesting)
      value.is_a?(Hash) ? value : nil
    rescue JSON::ParserError, EncodingError, ArgumentError, TypeError
      nil
    end

    # The JSON object in the first `max_bytes` of the file at `path`, or nil
    # (unreadable, truncated, foreign or not an object). The caller checks
    # what kind of file it is first.
    def read_object(path, max_bytes:, max_nesting:)
      # File.read with a length is nil at EOF: an empty file parses as "".
      object(File.read(path, max_bytes), max_nesting: max_nesting)
    rescue SystemCallError, IOError
      nil
    end
  end
end
