# Shop::StoreClock: store-local day boundaries, UTC offset and next midnight for an IANA zone.

module Shop
  module StoreClock
    module_function

    # Run the block with ENV['TZ'] = tz; always restored.
    def with_tz(tz)
      saved = ENV.fetch('TZ', nil)
      ENV['TZ'] = tz
      yield
    ensure
      saved.nil? ? ENV.delete('TZ') : ENV['TZ'] = saved
    end

    # {today_start, yesterday_start (Time, UTC; yesterday ends at today_start),
    #  local_date, yesterday_date ("YYYY-MM-DD"), utc_offset_minutes, day_ends_at_ms}.
    # Steps by Date so DST days keep their real length.
    def boundaries(tz)
      now = Shop.now
      with_tz(tz) do
        local = Time.at(now.to_r).localtime
        today = Date.new(local.year, local.month, local.day)
        yesterday = today - 1
        tomorrow = today + 1
        today_start = Time.local(today.year, today.month, today.day)
        yesterday_start = Time.local(yesterday.year, yesterday.month, yesterday.day)
        next_start = Time.local(tomorrow.year, tomorrow.month, tomorrow.day)
        {
          today_start: today_start.utc, yesterday_start: yesterday_start.utc,
          local_date: today.iso8601, yesterday_date: yesterday.iso8601,
          utc_offset_minutes: local.utc_offset / 60, day_ends_at_ms: next_start.to_i * 1000
        }
      end
    end

    def iso(time)
      time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end
  end
end
