# Shop::Validate: the authoritative scalar checks (domain, theme target, ids, timezone, cursor, role, label).

module Shop
  module Validate
    # One DNS label (the store's subdomain): 1-63 chars, no leading or trailing hyphen.
    DNS_LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/
    # Every store domain Shop accepts ends in this.
    DOMAIN_SUFFIX = '.myshopify.com'
    DOMAIN    = /\A#{DNS_LABEL}#{Regexp.escape(DOMAIN_SUFFIX)}\z/
    THEME_ID  = /\A[1-9]\d{0,19}\z/
    EPOCH     = /\A[1-9]\d{9}\z/
    BACKUP_ID = /\A[1-9]\d{9}-[1-9]\d{0,19}\z/
    ORG_ID    = /\A\d{1,20}\z/
    # Mirrors TIMEZONE_RE in js/config.mjs: 1-4 segments of at most 64 chars.
    TZ        = %r{\A[A-Za-z0-9_+\-]{1,64}(?:/[A-Za-z0-9_+\-]{1,64}){0,3}\z}
    CURSOR    = %r{\A[A-Za-z0-9+/=_\-]{1,1024}\z}
    ORDER_GID = %r{\Agid://shopify/Order/\d{1,20}\z}
    ROLE      = /\A[a-z_]{1,32}\z/
    LABEL_MAX = 80
    ZONEINFO = '/usr/share/zoneinfo'

    module_function

    def reject!(message)
      raise Failure.new('invalid_argument', message)
    end

    # Accepts "acme" or "acme.myshopify.com"; returns the canonical domain or nil.
    def normalize_domain(input)
      s = Text.scrub(input.to_s).downcase
      s = "#{s}#{DOMAIN_SUFFIX}" if s.match?(/\A#{DNS_LABEL}\z/)
      s.match?(DOMAIN) ? s : nil
    end

    def domain!(input)
      normalize_domain(input) || reject!("not a #{DOMAIN_SUFFIX} domain: #{Text.quote(input)}")
    end

    # A push or pull target: "live" or a numeric theme id.
    def target!(input)
      s = input.to_s
      s == 'live' || theme_id?(s) ? s : reject!("target must be live or a numeric theme id: #{Text.quote(s)}")
    end

    def theme_id?(value) = value.to_s.match?(THEME_ID)
    def epoch?(value) = value.to_s.match?(EPOCH)
    def backup_id?(value) = value.to_s.match?(BACKUP_ID)
    def org_id?(value) = value.to_s.match?(ORG_ID)
    def cursor?(value) = value.is_a?(String) && value.match?(CURSOR)

    def backup_id!(value)
      backup_id?(value) ? value.to_s : reject!("not a backup id: #{Text.quote(value)}")
    end

    # A theme role as the CLI reports it, else "unknown".
    def role(value)
      s = value.to_s
      s.match?(ROLE) ? s : 'unknown'
    end

    # A zone name that resolves to a file under /usr/share/zoneinfo, else "UTC".
    def timezone(value)
      s = value.to_s
      return 'UTC' unless s.match?(TZ)

      real = File.realpath(File.join(ZONEINFO, s))
      real.start_with?("#{File.realpath(ZONEINFO)}/") && File.file?(real) ? s : 'UTC'
    rescue SystemCallError
      'UTC'
    end

    def timezone!(value)
      tz = timezone(value)
      reject!("unknown timezone: #{Text.quote(value)}") if tz == 'UTC' && value.to_s != 'UTC'
      tz
    end

    # A display string from Shopify: cleaned, 1..80 chars, else nil.
    def label(value)
      return nil unless value.is_a?(String)

      s = Text.clean(value, LABEL_MAX)
      s.empty? ? nil : s
    end
  end
end
