# Shop::Account: the CLI account session, probed with `store list --json`, and the account object helpers report.

module Shop
  module Account
    LOGOUT_ARGS = %w[auth logout --no-input].freeze
    private_constant :LOGOUT_ARGS

    module_function

    # The account session from `store list --json` (CI): exit 0 with rows =
    # signed_in; "organization ID is required" = multi_org (signed in on a
    # multi-org account); a sign-in message = signed_out; anything else,
    # including an empty list with a notice, is unknown. Returns [status,
    # error] where error is the Failure behind an unknown status (nil
    # otherwise). Stops propagate; a timeout is unknown (the error is the
    # timeout). `strict:` raises that error instead (network, rate limit,
    # bad response, timeout...), for callers that must not act on a guess
    # (sign-in).
    def probe(located, deadline:, strict: false)
      answer = begin
        Shopify.call(located, Stores::LIST_ARGS, deadline: deadline)
      rescue Failure => e
        raise if e.code == 'terminated'

        e
      end
      status = status_of(answer)
      return [status, nil] unless status == 'unknown'

      error = unknown_error(answer)
      raise error if strict

      ['unknown', error]
    end

    # The one mapping of a `store list --json` answer to a session status:
    # `answer` is the parsed body (exit 0) or the Failure the call raised.
    # Rows -> signed_in; an empty list with a notice -> unknown (the CLI said
    # something it could not list); a body that is no listing -> unknown;
    # multi_org -> multi_org (signed in, several organizations); signed_out
    # -> signed_out; any other failure -> unknown. Never raises. probe and
    # discover-stores both read it.
    def status_of(answer)
      return %w[multi_org signed_out].include?(answer.code) ? answer.code : 'unknown' if answer.is_a?(Failure)

      rows, = Stores.from_store_list(answer)
      rows.empty? && answer['notice'].is_a?(String) ? 'unknown' : 'signed_in'
    rescue Failure
      'unknown'
    end

    # The Failure behind an unknown answer: the call's own, the listing's
    # bad_response, or the notice the CLI printed instead of rows.
    def unknown_error(answer)
      return answer if answer.is_a?(Failure)

      Stores.from_store_list(answer)
      Failure.new('cli_failed', Text.clean(answer['notice']))
    rescue Failure => e
      e
    end

    # The status Shop shows: multi_org is a signed-in account with several
    # organizations.
    def public_status(status)
      status == 'multi_org' ? 'signed_in' : status
    end

    # `auth logout`: empties the CLI's session store.
    def log_out!(located, deadline:)
      Shopify.call(located, LOGOUT_ARGS, deadline: deadline, json: false)
    end

    # The `account` object of check-account and sign-in:
    # {status: signed_in|signed_out|unknown, error}.
    def object(status, error = nil)
      { 'status' => public_status(status), 'error' => error&.to_error }
    end
  end
end
