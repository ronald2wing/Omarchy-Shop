# Shop::Failure: the one exception a helper fails with, carrying an error code and the extra fields of the failure line.

module Shop
  # Raised anywhere below a helper's main; HelperMain.main turns it into the
  # one failure line and the exit status. `extra` lands inside `error`
  # (reason, missing, retryAfter); `details` is a top-level list of cleaned
  # diagnostic lines (theme helpers only). Other top-level fields of the line
  # (writeStarted, backupId, folderCopy) are HelperMain's line fields.
  class Failure < StandardError
    attr_reader :code, :extra, :details

    def initialize(code, message, details: nil, **extra)
      @code = code
      @extra = extra
      @details = details.nil? || details.empty? ? nil : details
      super(message)
    end

    # Shell convention: a timeout exits 124 (Os.exitToError reads it when a
    # stream's final line is lost), a stop 143; every other failure exits 1.
    def exit_code
      { 'timeout' => 124, 'terminated' => 143 }.fetch(@code, 1)
    end

    def to_error
      { 'code' => @code, 'message' => Text.clean(message) }
        .merge(@extra.transform_keys(&:to_s))
    end
  end
end
