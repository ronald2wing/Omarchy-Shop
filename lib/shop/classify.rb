# Shop::Classify: the one mapping from a finished CLI call to a Shop error code, read from the CLI's own JSON error body only (never stderr).

module Shop
  module Classify
    # A store's stored app authentication is absent or can no longer be used
    # (each with a "store auth" next step), or the account may not use the
    # CLI on that store: only that store needs `grant-sales-access` again.
    # Never on a theme command: the pinned CLI's theme commands take their Admin
    # token by exchanging the account session, not from `store auth`, so a
    # grant cannot fix them; they fall through to `cli_failed` with the
    # CLI's own sentence.
    SALES_ACCESS_RE = Regexp.union(
      /No stored app authentication found/i,
      /Stored app authentication for \S+ is no longer valid/i,
      /Token refresh (?:failed|returned an invalid response) for/i,
      /No refresh token stored for/i,
      /preview store \S+ has likely been claimed/i,
      /You are not authorized to use the CLI to develop in the provided store/i,
      /You don't have the necessary permissions to perform this action/i
    )
    MULTI_ORG_RE = /An organization ID is required/i
    RATE_LIMITED_RE = /Too Many Requests/i
    # The account session is absent or expired. Whole CLI phrases only: the
    # pinned CLI under CI fails a logged-out command with "Authorization is
    # required to continue, but the current environment does not support
    # interactive prompts." The BusinessPlatform 401 is the account-level
    # API's generic HTTP failure for an expired session (seen live on `store
    # list`); the same text for the Admin API is about the store.
    SIGNED_OUT_RE = Regexp.union(
      /Error validating auth session/i,
      /We've cleared the current session/i,
      /\bAuthorization is required to continue\b/i,
      /\blog in to Shopify\b/i,
      /\bYou are not logged in\b/i,
      /\bNo authenticated account found\b/i,
      /\bDevice authorization failed\b/i,
      /\bBusinessPlatform GraphQL API responded unsuccessfully with the HTTP status 401\b/i
    )
    THEME_SESSION_RE = /Admin GraphQL API responded unsuccessfully with the HTTP status 40[13]\b/i
    STORE_UNAVAILABLE_RE = /is currently unavailable/i
    SERVER_ERROR_RE = /returned a server error|\bHTTP status 5\d\d\b/i
    SERVER_RETRY_AFTER = 60
    THROTTLED_CODES = %w[THROTTLED 429].freeze

    module_function

    # Raise the classified failure for a finished CLI call, or return its
    # parsed JSON object (nil when stdout is not one).
    # Order: timeout, overflow, a JSON error body, a 'partial' result body
    # (exit 1 is expected), then any non-zero exit as `cli_failed`. stderr
    # is never classified; it only feeds `details`. `theme:` says the call
    # was a theme command (an Admin API 401/403 there is the theme session).
    def check!(result, theme:)
      raise Failure.new('timeout', 'CLI call timed out') if result.timed_out
      raise Failure.new('output_too_large', 'CLI output over its cap') if result.overflowed

      body = Json.object(result.stdout)
      if (found = failure(result, body, theme: theme))
        raise found
      end

      # The pinned CLI's `theme push` with rejected files prints its JSON
      # result with status 'partial' and exits 1; that is a result, not a
      # failure.
      return body if result.exit_code == 1 && body && !body.key?('error') && body['status'] == 'partial'
      return body if result.exit_code&.zero?

      details = Text.details(result.stderr_tail)
      message = details.last || (result.exit_code ? "exit status #{result.exit_code}" : 'ended without an exit status')
      raise Failure.new('cli_failed', message, details: details)
    end

    # The Failure for a parsed JSON error body (the pinned CLI's
    # {"error":{"type","message","tryMessage"?,"nextSteps"?,"details"?:
    # {"errors":[GraphQL errors]}}} or a bare GraphQL {"errors":[…]}), or
    # nil when the body is not an error.
    def failure(result, body, theme:)
      return nil unless body

      err = body['error'].is_a?(Hash) ? body['error'] : nil
      gql = body['errors'].is_a?(Array) ? body['errors'] : []
      return nil unless err || (!gql.empty? && !body['data'].is_a?(Hash))

      errors = gql + (err && err['details'].is_a?(Hash) ? Array(err['details']['errors']) : [])
      errors = errors.select { |e| e.is_a?(Hash) }
      codes = errors.filter_map { |e| Json.dig(e, 'extensions', 'code')&.to_s&.upcase }
      own = err ? own_text(err) : ''
      shown = shown_message(err, errors)

      code, extra = body_code(body, codes, errors, theme: theme) || message_code(own, theme: theme)
      return failure_for(code, extra, shown, result, body) if code
      return nil if result.exit_code&.zero? && err.nil?

      Failure.new('cli_failed', issue_summary(err) || shown, details: body_details(err) + Text.details(result.stderr_tail))
    end

    # The per-file issues of a failed push (error.details.issues, the
    # same {filePath, message} rows a partial push reports), as
    # Themes.issues rows.
    def issues_of(err)
      Themes.issues(Json.dig(err, 'details', 'issues'))
    end

    # The message of a push the CLI rejected with per-file issues: the first
    # issue as "path: message" (the cause, which the CLI's own "could not be
    # pushed" sentence omits), plus " (+N more)"; nil without issues. The
    # CLI's sentence and every issue line stay in `details`.
    def issue_summary(err)
      issues = issues_of(err)
      return nil if issues.empty?

      more = Themes.issue_count(Json.dig(err, 'details', 'issues')) - 1
      first = Themes.issue_line(issues.first)
      more.positive? ? "#{first} (+#{more} more)" : first
    end

    # [code, extra] read from the structured parts (GraphQL extensions
    # codes, the app_errors category and an explicit retryAfter), or nil.
    # Checked before any message text. Access denied is
    # sales_access_required only off a theme command (see SALES_ACCESS_RE).
    def body_code(body, codes, errors, theme:)
      categories = Array(Json.dig(body, 'extensions', 'app_errors', 'errors')).filter_map { |e| e['category'].to_s.downcase if e.is_a?(Hash) }
      return ['sales_access_required', {}] if !theme && (codes.include?('ACCESS_DENIED') || categories.include?('access_denied'))
      return ['rate_limited', {}] if (codes & THROTTLED_CODES).any? || Throttle.explicit_retry_after(body, errors)

      nil
    end

    # [code, extra] read from the CLI's own message and tryMessage, most
    # specific first, or nil (the first matching row wins; a non-theme
    # Admin API 401/403 stops there with nil). `multi_org` is internal
    # (signed in, several organizations). A server error is `cli_failed`
    # with a fixed retryAfter; rate_limited's retryAfter is read from the
    # body by failure_for.
    def message_code(text, theme:)
      return ['sales_access_required', {}] if !theme && text.match?(SALES_ACCESS_RE)

      case text
      when MULTI_ORG_RE then ['multi_org', {}]
      when RATE_LIMITED_RE then ['rate_limited', {}]
      when SIGNED_OUT_RE then ['signed_out', {}]
      when THEME_SESSION_RE then theme ? ['theme_session_expired', {}] : nil
      when STORE_UNAVAILABLE_RE then ['store_unavailable', {}]
      when SERVER_ERROR_RE then ['cli_failed', { retryAfter: SERVER_RETRY_AFTER }]
      end
    end

    # The CLI's own words, the only text message_code reads: the message,
    # plus tryMessage unless it is GraphQL text in disguise. For a "GraphQL
    # operation failed." body the pinned CLI copies the raw GraphQL error
    # list into tryMessage (and details.errors), so a store-side message
    # containing "Too Many Requests" or "log in to Shopify" would otherwise
    # classify the account session; GraphQL errors classify only through
    # extensions.code / app_errors (body_code).
    def own_text(err)
      message = err['message'].to_s
      try = err['tryMessage'].to_s
      return message if try.empty? || graphql_wrapper?(message) || json_dump?(try)

      "#{message}\n#{try}"
    end

    def graphql_wrapper?(message)
      message.match?(/\AGraphQL operation failed/i)
    end

    # True when `text` is a serialised JSON value (an error dump, never a
    # sentence the CLI wrote for the user).
    def json_dump?(text)
      return false unless text.lstrip.start_with?('{', '[')

      JSON.parse(text, max_nesting: Json::MAX_NESTING)
      true
    rescue JSON::ParserError
      false
    end

    def shown_message(err, errors)
      main = err ? err['message'].to_s : Json.dig(errors.first, 'message').to_s
      first_gql = Json.dig(errors.first, 'message')
      shown = first_gql && graphql_wrapper?(main) ? first_gql.to_s : main
      shown.strip.empty? ? 'no error message' : shown
    end

    def failure_for(code, extra, message, result, body)
      extra = extra.merge(retryAfter: Throttle.retry_after(body)) if code == 'rate_limited'
      Failure.new(code, message, details: Text.details(result.stderr_tail), **extra)
    end

    # The failure lines of a JSON error body: a failed push's per-file
    # issues first (details.issues, the only thing that helps fix the
    # folder), then the message, the GraphQL errors' messages (one line
    # each, in place of the JSON dump the CLI puts in tryMessage), the
    # tryMessage when it is prose, and the next steps.
    def body_details(err)
      return [] unless err

      issue_lines = issues_of(err).first(Text::DETAILS_MAX).map { |row| Themes.issue_line(row) }
      gql = Array(Json.dig(err, 'details', 'errors')).filter_map { |e| e['message'] if e.is_a?(Hash) }
      try = err['tryMessage'].to_s
      try = '' if json_dump?(try)
      lines = [err['message'], *gql, try, *Array(err['nextSteps'])].map { |l| Text.clean(l.to_s) }
      (issue_lines + lines).reject(&:empty?).uniq.first(Text::DETAILS_MAX)
    end
  end
end
