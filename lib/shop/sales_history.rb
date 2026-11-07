# Shop::SalesHistory: the completed periods (yesterday, last 7/14/30 days with the window before, last 12 months, lifetime) from the History query's ShopifyQL tables.

module Shop
  module SalesHistory
    DAY_RE = /\A\d{4}-\d{2}-\d{2}\z/
    MONTH_RE = /\A\d{4}-\d{2}\z/
    # [period id, first day back, last day back, the previous window's first and last day back].
    DAY_WINDOWS = [
      ['last7d', 7, 1, 14, 8],
      ['last14d', 14, 1, 28, 15],
      ['last30d', 30, 1, 60, 31]
    ].freeze

    module_function

    # Derive the completed periods from the five ShopifyQL tables of
    # Queries::HISTORY; `local_date` is the store-local today ("YYYY-MM-DD"),
    # whose daily bucket is dropped. Every figure ends yesterday.
    def derive(data, local_date)
      days = Days.new(by_day(Sales.table(data, 'salesDaily')), by_day(Sales.table(data, 'sessionsDaily')),
                      Date.iso8601(local_date))
      sales_monthly = Sales.table(data, 'salesMonthly')
      sessions_monthly = Sales.table(data, 'sessionsMonthly')
      lifetime_rows = Sales.table(data, 'lifetime')

      result = { 'yesterday' => summary(days.window(1, 1), days.window(2, 2), buckets: false) }
      DAY_WINDOWS.each do |id, from, to, prev_from, prev_to|
        result[id] = summary(days.window(from, to), days.window(prev_from, prev_to), buckets: true)
      end
      result['last12m'] = last12m(sales_monthly, sessions_monthly, days.today)
      life = lifetime_rows.first || {}
      result['lifetime'] = { 'sales' => Sales.cents_of(life.fetch('total_sales', 0)),
                             'orders' => Sales.count(life.fetch('orders', 0)) }
      result
    end

    # The daily rows by their "YYYY-MM-DD" day.
    def by_day(rows)
      rows.each_with_object({}) do |row, h|
        day = row['day'].to_s[0, 10]
        Sales.malformed!("bad day: #{Text.quote(day)}") unless day.match?(DAY_RE)
        h[day] = row
      end
    end

    # One period from its window and the window before it; with `buckets`,
    # one {date, sales, sessions} per day.
    def summary(window, previous, buckets:)
      out = { 'sales' => window['sales'], 'orders' => window['orders'], 'traffic' => window['traffic'],
              'previous' => { 'sales' => previous['sales'], 'orders' => previous['orders'], 'traffic' => previous['traffic'] } }
      if buckets
        out['buckets'] = window['days'].map do |d|
          { 'date' => d['date'], 'sales' => Sales.cents(d['sales']), 'sessions' => d['traffic']['sessions'] }
        end
      end
      out
    end

    # The daily series around a store-local today.
    Days = Struct.new(:sales, :sessions, :today) do
      # The figures of one date; a day missing from a series is zero.
      def stats(date)
        key = date.iso8601
        s = sales[key]
        t = sessions[key]
        { 'date' => key,
          'sales' => s ? Sales.money(s['total_sales']) : 0.0,
          'orders' => s ? Sales.count(s['orders']) : 0,
          'traffic' => t ? Sales.traffic_from(t) : Sales.empty_traffic }
      end

      # The days from `from_days_ago` to `to_days_ago` (inclusive, oldest
      # first) and their totals.
      def window(from_days_ago, to_days_ago)
        days = (to_days_ago..from_days_ago).to_a.reverse.map { |n| stats(today - n) }
        { 'days' => days,
          'sales' => Sales.cents(days.sum { |d| d['sales'] }),
          'orders' => days.sum { |d| d['orders'] },
          'traffic' => days.reduce(Sales.empty_traffic) { |acc, d| Sales.add_traffic(acc, d['traffic']) } }
      end
    end

    # The monthly window is SINCE -365d UNTIL yesterday, i.e. today-365
    # through today-1 inclusive (store-local): a month is `partial` when
    # the window starts or ends inside it, decided by date (a whole month on
    # the 1st, a leap February) and by month key, so a missing leading
    # month never moves the flag.
    def last12m(sales_rows, session_rows, today)
      sessions = session_rows.to_h { |r| [month_key(r), Sales.traffic_from(r)] }
      months = sales_rows.map { |r| month_key(r) } | sessions.keys
      months.sort!
      sales = sales_rows.to_h { |r| [month_key(r), r] }
      start = today - 365
      first_key = start.strftime('%Y-%m')
      last_key = (today - 1).strftime('%Y-%m')
      buckets = months.map do |m|
        s = sales[m]
        { 'month' => m,
          'sales' => s ? Sales.cents_of(s['total_sales']) : 0.0,
          'sessions' => (sessions[m] || Sales.empty_traffic)['sessions'],
          'partial' => (m == first_key && start.day != 1) || (m == last_key && today.day != 1) }
      end
      traffic = months.reduce(Sales.empty_traffic) { |acc, m| Sales.add_traffic(acc, sessions[m]) }
      { 'sales' => Sales.cents(buckets.sum { |b| b['sales'] }), 'orders' => months.sum { |m| sales[m] ? Sales.count(sales[m]['orders']) : 0 },
        'traffic' => traffic, 'buckets' => buckets }
    end

    # The "YYYY-MM" of a monthly row.
    def month_key(row)
      m = row['month'].to_s[0, 7]
      Sales.malformed!("bad month: #{Text.quote(m)}") unless m.match?(MONTH_RE)
      m
    end
  end
end
