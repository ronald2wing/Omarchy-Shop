# Shop::Stores: the CLI's store, session and organization listings (their argv and parsing) and merging them into one deduped, naturally sorted list.

module Shop
  module Stores
    MAX_DISCOVERED = 500
    # The listings, all JSON and CI: the account's stores (also the session
    # probe), the store-auth sessions, and a multi-org account's
    # organizations (each then listed with org_store_list_args).
    LIST_ARGS = %w[store list --json --no-input].freeze
    AUTH_LIST_ARGS = %w[store auth list --json --no-input].freeze
    ORG_LIST_ARGS = %w[organization list --json --no-input].freeze

    module_function

    # The scopes a session holds, with the ones its write scopes imply: the
    # pinned CLI merges a new grant into the scopes a store already has and
    # drops a requested read_X that a held write_X implies (its Wn()), and
    # checks scopes through expandImpliedStoreAuthScopes (write_X -> read_X,
    # unauthenticated_write_X -> unauthenticated_read_X). Same rule here.
    def implied_scopes(scopes)
      granted = Array(scopes).map(&:to_s)
      granted | granted.filter_map { |s| (m = s.match(/\A(unauthenticated_)?write_(.+)\z/)) && "#{m[1]}read_#{m[2]}" }
    end

    # The domains with a sales-access session, from `store auth list --json`
    # ({"sessions":[{"store","scopes":[...]}]}): sessions holding both scopes
    # (directly or through a write scope).
    def from_auth_sessions(body)
      sessions = body['sessions']
      raise Failure.new('bad_response', 'store auth list: no sessions array') unless sessions.is_a?(Array)

      sessions.filter_map do |s|
        next unless s.is_a?(Hash)

        domain = Validate.normalize_domain(s['store'])
        scopes = s['scopes']
        next unless domain
        next if scopes.is_a?(Array) && !(SCOPES.split(',') - implied_scopes(scopes)).empty?

        domain
      end.uniq
    end

    # [rows, truncated] from `store list --json` ({"stores":[{"store","name"}],
    # "notice"?: "…"}): rows are [{domain, name}]; the listing is truncated
    # when the CLI says so outright or prints a notice next to the rows it
    # did return.
    def from_store_list(body)
      stores = body['stores']
      raise Failure.new('bad_response', 'store list: no stores array') unless stores.is_a?(Array)

      rows = stores.filter_map do |s|
        next unless s.is_a?(Hash)

        domain = Validate.normalize_domain(s['store'])
        domain && { 'domain' => domain, 'name' => Validate.label(s['name']) }
      end
      truncated = body['truncated'] == true || (body['notice'].is_a?(String) && !rows.empty?)
      [rows, truncated]
    end

    # The stores of one organization (an id from org_ids).
    def org_store_list_args(org_id)
      ['store', 'list', "--organization-id=#{org_id}", '--json', '--no-input']
    end

    # Organization ids with at least one shop, from `organization list --json`.
    def org_ids(body)
      orgs = body['organizations']
      raise Failure.new('bad_response', 'organization list: no organizations array') unless orgs.is_a?(Array)

      orgs.filter_map do |o|
        next unless o.is_a?(Hash)

        id = o['id'].to_s
        count = o['shopCount']
        next unless Validate.org_id?(id)
        next if count.is_a?(Integer) && count <= 0

        id
      end.uniq
    end

    def subdomain_label(domain)
      domain.delete_suffix(Validate::DOMAIN_SUFFIX)
    end

    # Merge the domains with a store-auth session, the account's store rows
    # and the looked-up names into [{domain, name}], deduped by domain,
    # names cleaned (the subdomain when no name is known), natural sort by
    # name then domain, capped at MAX_DISCOVERED. Returns [stores, truncated].
    def merge(session_domains:, rows:, names:)
      by_domain = {}
      rows.each do |row|
        entry = (by_domain[row['domain']] ||= { 'domain' => row['domain'], 'name' => nil })
        entry['name'] ||= row['name']
      end
      session_domains.each { |domain| by_domain[domain] ||= { 'domain' => domain, 'name' => nil } }
      by_domain.each_value do |entry|
        entry['name'] ||= Validate.label(names[entry['domain']]) || subdomain_label(entry['domain'])
      end
      sorted = by_domain.values.sort do |a, b|
        c = Text.natural_compare(a['name'], b['name'])
        c.zero? ? a['domain'] <=> b['domain'] : c
      end
      [sorted.first(MAX_DISCOVERED), sorted.size > MAX_DISCOVERED]
    end
  end
end
