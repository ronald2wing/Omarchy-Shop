# Shop::Sales: parsing `store execute` payloads (ShopifyQL rows keyed by column name, order pages, strict amounts) into today's and yesterday's figures.

module Shop
  module Sales
    TRAFFIC_COLUMNS = {
      'sessions' => 'sessions',
      'sessions_with_cart_additions' => 'cartAdds',
      'sessions_that_reached_checkout' => 'reachedCheckout',
      'sessions_that_completed_checkout' => 'completed'
    }.freeze
    # The page cap of every paged range, from the timing table (its rows
    # for today and yesterday state the same cap; test_sales checks that).
    MAX_PAGES = TIMING.fetch('fetch-sales today').fetch(:pages)
    # The most [ms, amount] order points a range emits (today's and
    # yesterday's hourly charts); MAX_PAGES pages of 250 never exceed it.
    MAX_ORDER_POINTS = 10_000
    # Amounts and counts are decimal strings (or numbers): never hex,
    # exponents or underscores, which Float() would accept.
    AMOUNT_RE = /\A-?\d+(?:\.\d+)?\z/
    COUNT_RE = /\A-?\d+(?:\.0+)?\z/

    module_function

    def malformed!(message)
      raise Failure.new('bad_response', message)
    end

    # The rows of a shopifyqlQuery field as hashes keyed by column name. With
    # required: false, a missing field, parse errors or no table give nil.
    def table(data, field, required: true)
      problem, rows = table_rows(data[field])
      return rows if problem.nil?
      return nil unless required

      malformed!("#{field}: #{problem}")
    end

    # [problem or nil, rows].
    def table_rows(node)
      return ['missing', nil] unless node.is_a?(Hash)

      errors = node['parseErrors']
      return [Text.clean(errors.first.to_s, 120), nil] if errors.is_a?(Array) && !errors.empty?

      rows = node['tableData'].is_a?(Hash) ? node['tableData']['rows'] : nil
      return ['no rows', nil] unless rows.is_a?(Array)

      names = Array(node['tableData']['columns']).filter_map { |c| c['name'] if c.is_a?(Hash) }
      out = rows.map do |row|
        case row
        when Hash then row
        when Array then names.zip(row).to_h
        else return ['row is not an object', nil]
        end
      end
      [nil, out]
    end

    # A money amount as a Float; strings must be plain decimals.
    def money(value)
      amount(value).to_f
    end

    # A money amount as an exact Rational.
    def amount(value)
      return Rational(value) if value.is_a?(Integer)
      return Rational(value.to_s) if value.is_a?(Float) && value.finite?

      s = value.to_s
      malformed!("not an amount: #{Text.quote(s)}") unless s.match?(AMOUNT_RE)
      Rational(s)
    end

    # A count as an Integer; strings must be plain decimals (a whole number,
    # or one with a zero fraction).
    def count(value)
      return value if value.is_a?(Integer)
      return value.round if value.is_a?(Float) && value.finite?

      s = value.to_s
      malformed!("not a count: #{Text.quote(s)}") unless s.match?(COUNT_RE)
      s.to_f.round
    end

    # A number rounded to cents, as a Float.
    def cents(value)
      value.to_r.round(2).to_f
    end

    # A money amount (Shop's strict form, see `amount`) rounded to cents,
    # exactly: "4.095" is 4.1, where a Float detour would give 4.09.
    def cents_of(value)
      cents(amount(value))
    end

    # Exact sum of order amounts, rounded to cents; a sum outside the float
    # range is malformed.
    def sum_amounts(nodes)
      total = nodes.sum(Rational(0)) { |node| order_amount(node) }
      f = cents(total)
      malformed!('sum is not finite') unless f.finite?
      f
    end

    # [nodes, has_next, cursor] of an orders connection.
    def page(data)
      conn = data['page']
      malformed!('page: missing') unless conn.is_a?(Hash) && conn['nodes'].is_a?(Array)
      info = conn['pageInfo'].is_a?(Hash) ? conn['pageInfo'] : {}
      has_next = info['hasNextPage'] == true
      cursor = info['endCursor']
      malformed!('page: bad cursor') if has_next && !Validate.cursor?(cursor)
      [conn['nodes'], has_next, cursor]
    end

    def order_amount(node)
      malformed!('order node is not an object') unless node.is_a?(Hash)
      amount(Json.dig(node, 'totalPriceSet', 'shopMoney', 'amount'))
    end

    # [[epoch ms, amount in cents-rounded float]] per order node, the hourly
    # charts' input, capped at MAX_ORDER_POINTS. order_amount checks the node
    # is an object before createdAt is read.
    def order_points(nodes)
      nodes.first(MAX_ORDER_POINTS).map do |n|
        amount = cents(order_amount(n))
        [ms(n['createdAt']), amount]
      end
    end

    def ms(iso)
      Time.iso8601(iso.to_s).to_i * 1000
    rescue ArgumentError
      malformed!('bad createdAt')
    end

    def latest_order(data)
      malformed!('latest: missing') unless data['latest'].is_a?(Hash)
      nodes = data['latest']['nodes']
      malformed!('latest: missing') unless nodes.is_a?(Array)
      node = nodes.first
      return nil if node.nil?

      malformed!('latest: order id') unless node.is_a?(Hash) && node['id'].to_s.match?(Validate::ORDER_GID)
      items = Json.dig(node, 'lineItems', 'nodes')
      first = items.is_a?(Array) ? items.first : nil
      {
        'id' => node['id'],
        'number' => Text.clean(node['name'].to_s, 20),
        'total' => cents(order_amount(node)),
        'itemCount' => node['subtotalLineItemsQuantity'].nil? ? nil : count(node['subtotalLineItemsQuantity']),
        'firstItem' => first.is_a?(Hash) ? Validate.label(first['title'].to_s) : nil
      }
    end

    def order_count(data)
      malformed!('ordersCount: missing') unless data['count'].is_a?(Hash)
      value = data['count']['count']
      malformed!('ordersCount: missing') if value.nil?
      count(value)
    end

    # The four session counts from one row.
    def traffic_from(row)
      TRAFFIC_COLUMNS.to_h { |col, key| [key, row.key?(col) ? count(row[col]) : 0] }
    end

    def empty_traffic
      TRAFFIC_COLUMNS.values.to_h { |k| [k, 0] }
    end

    def add_traffic(a, b)
      return a if b.nil?

      a.to_h { |k, v| [k, v + b.fetch(k, 0)] }
    end

    def shop_meta(data)
      shop = data['shop']
      malformed!('shop: missing') unless shop.is_a?(Hash)
      currency = shop['currencyCode'].to_s
      malformed!('shop: currency') unless currency.match?(/\A[A-Z]{3}\z/)
      [currency, Validate.timezone(shop['ianaTimezone'])]
    end

    # Hourly traffic for one store day as [{hour, sessions, ...}], or nil
    # when the hourly series is unavailable. `hour` is the number of whole
    # hours since `start` (the day's store-local midnight, the payload's
    # startEpoch), not the wall-clock hour: ShopifyQL returns UTC instants, and on a DST
    # day the wall clock repeats or skips an hour while the JS side weights
    # and bins by elapsed time. On other days the two are equal. Rows outside
    # 0...25 (a 25-hour fall-back day) are dropped.
    def traffic_hourly(data, start)
      hourly_rows(data, 'trafficHourly', start) { |row| traffic_from(row) }
    end

    # Yesterday's hourly Analytics sales as [{hour, sales}] (hours
    # as in `traffic_hourly`), or nil when the series is unavailable. `sales` is
    # total_sales, net of returns booked in that hour, so it can be
    # negative; the hours add up to the history's daily total_sales.
    def sales_hourly(data, start)
      hourly_rows(data, 'salesHourly', start) do |row|
        { 'sales' => cents_of(row.fetch('total_sales', 0)) }
      end
    end

    def hourly_rows(data, field, start)
      rows = table(data, field, required: false)
      return nil if rows.nil?

      rows.filter_map do |row|
        hour = row['hour'].to_s
        index = if hour.match?(/\A\d{1,2}\z/)
                  hour.to_i
                else
                  ((Time.iso8601(hour) - start) / 3600).floor
                end
        next unless index.between?(0, 24)

        { 'hour' => index }.merge(yield(row))
      rescue ArgumentError
        malformed!("#{field}: bad hour")
      end
    end

    # The `today` object of fetch-sales: `data` is the first page's payload
    # (TODAY or TODAY_WITH_TRAFFIC), `nodes` every order fetched, `start`
    # the store-local midnight. traffic and trafficHourly are nil without
    # traffic (or when Analytics has no row for it).
    def today(data, nodes, start, with_traffic:)
      traffic = nil
      hourly = nil
      if with_traffic
        rows = table(data, 'traffic', required: false)
        traffic = rows && traffic_from(rows.first || {})
        hourly = traffic_hourly(data, start)
      end
      { 'sales' => sum_amounts(nodes), 'orders' => order_count(data), 'latestOrder' => latest_order(data),
        'traffic' => traffic, 'startEpoch' => start.to_i, 'orderPoints' => order_points(nodes),
        'trafficHourly' => hourly }
    end

    # The `yesterday` object of fetch-sales: `data` is the first page's
    # payload (YESTERDAY), `nodes` every order fetched, `start` and `stop`
    # yesterday's and today's store-local midnights, `date` yesterday's
    # store-local date.
    def yesterday(data, nodes, date:, start:, stop:)
      { 'date' => date, 'startEpoch' => start.to_i, 'endEpoch' => stop.to_i, 'orderPoints' => order_points(nodes),
        'salesHourly' => sales_hourly(data, start), 'trafficHourly' => traffic_hourly(data, start) }
    end
  end
end
