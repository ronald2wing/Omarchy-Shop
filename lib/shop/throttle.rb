# Shop::Throttle: the Admin API's cost budget (GraphQL and ShopifyQL extensions), how long to back off when throttled, and the wait between pages.

module Shop
  module Throttle
    # Seconds to back off when nothing in the response says how long.
    DEFAULT_RETRY_AFTER = 60
    MAX_RETRY_AFTER = 3600
    # The longest wait between two pages for the GraphQL budget to restore.
    MAX_PAGE_WAIT = 5

    module_function

    # The cost/throttle extensions of a response in a compact form:
    # {"graphql":{available,restoreRate,requested},"shopifyql":{resetAt(ms)}},
    # or nil.
    def budget(ext)
      return nil unless ext.is_a?(Hash)

      out = {}
      if (cost = ext['cost']).is_a?(Hash)
        t = cost['throttleStatus'].is_a?(Hash) ? cost['throttleStatus'] : {}
        out['graphql'] = { 'available' => number(t['currentlyAvailable']), 'restoreRate' => number(t['restoreRate']),
                           'requested' => number(cost['requestedQueryCost']) }
      end
      if (q = ext['shopifyqlCost']).is_a?(Hash)
        reset = begin
          Time.iso8601(q['windowResetAt'].to_s).to_i * 1000
        rescue ArgumentError
          nil
        end
        out['shopifyql'] = { 'resetAt' => reset }
      end
      out.empty? ? nil : out
    end

    # A retryAfter the response states outright (seconds), from the body's
    # extensions, the error details or a GraphQL error's extensions; nil
    # when none does. `errors` are the GraphQL error objects.
    def explicit_retry_after(body, errors)
      values = [Json.dig(body, 'extensions', 'retryAfter'), Json.dig(body, 'error', 'details', 'retryAfter')] +
               errors.map { |e| Json.dig(e, 'extensions', 'retryAfter') }
      values.find { |v| v.is_a?(Numeric) && v.positive? }
    end

    # Whole seconds until the budget recovers (1..3600): an explicit
    # retryAfter, else the response extensions (GraphQL cost restore rate,
    # ShopifyQL window reset), else DEFAULT_RETRY_AFTER.
    def retry_after(body)
      errors = Array(body['errors']) + Array(Json.dig(body, 'error', 'details', 'errors'))
      explicit = explicit_retry_after(body, errors.select { |e| e.is_a?(Hash) })
      return explicit.ceil.clamp(1, MAX_RETRY_AFTER) if explicit

      budget = budget(body['extensions'] || Json.dig(body, 'error', 'details', 'extensions'))
      candidates = []
      if (g = Json.dig(budget, 'graphql')) && g['restoreRate'].to_f.positive? && g['requested']
        candidates << ((g['requested'].to_f - g['available'].to_f) / g['restoreRate'].to_f).ceil
      end
      if (q = Json.dig(budget, 'shopifyql')) && q['resetAt']
        candidates << ((q['resetAt'] / 1000.0) - Shop.now.to_f).ceil
      end
      (candidates.select(&:positive?).max || DEFAULT_RETRY_AFTER).clamp(1, MAX_RETRY_AFTER)
    end

    # Seconds (at most MAX_PAGE_WAIT) until the GraphQL budget (a `budget`
    # result) can cover two more queries of the last one's cost, or nil when
    # it already can (or says too little to tell).
    def page_wait(budget)
      g = Json.dig(budget, 'graphql')
      return nil unless g && g['requested'] && g['available'] && g['restoreRate'].to_f.positive?

      needed = 2 * g['requested'].to_f
      return nil if g['available'].to_f >= needed

      [(needed - g['available'].to_f) / g['restoreRate'].to_f, MAX_PAGE_WAIT].min
    end

    def number(value)
      value.is_a?(Numeric) ? value : nil
    end
  end
end
