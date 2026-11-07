pragma ComponentBehavior: Bound
import QtQuick
import "../js/os.mjs" as Os
import "../js/sales.mjs" as Sales

// Each store's sales record (js/sales.mjs): warmed from cache.json at
// startup, updated by fetch-sales and grant results, and written back to
// the cache (CacheStore) when what it keeps changed. SalesScheduler
// decides when to fetch; this holds what came back.
Item {
  id: root

  // Set once prepare-state has succeeded; cache writes wait for it.
  property bool prepared: false
  required property string home
  // The poll interval the new-order rule measures gaps against.
  property int pollSeconds: 60
  // cache.json has been read (or found missing).
  readonly property bool loaded: cache.loaded
  // Bumped on every record change.
  readonly property int revision: internal.revision
  // domain -> record, for the snapshot builder (records are replaced, never
  // mutated).
  readonly property var records: internal.records

  // The store's record, or an empty one.
  function record(domain) {
    return internal.records[domain] || Sales.emptyRecord()
  }

  // Starts a store's record from its cache.json entry (the scheduler reads
  // its warm-start clock and fetch times from the record).
  function warm(domain) {
    internal.set(domain, Sales.fromCache(cache.entry(domain)))
  }

  // A finished fetch-sales run (SalesScheduler.fetched). -> { newOrders,
  // errorCode } (Sales.applyFetchResult), or null for a result that names
  // another store.
  function applyFetch(domain, range, result, withTraffic) {
    // The result crossed a `var` signal argument; arrays inside it
    // (buckets, yesterday orders) only become arrays again via Os.plain.
    const r = Os.plain(result)
    const out = Sales.applyFetchResult(root.record(domain), r, {
      domain: domain, range: range, withTraffic: withTraffic, nowMs: Date.now(), pollSeconds: root.pollSeconds
    })
    if (!out) return null
    internal.set(domain, out.record)
    if (out.cache) cache.put(domain, Sales.cacheRecord(out.record))
    return { newOrders: out.newOrders, errorCode: out.errorCode }
  }

  // A finished grant (SalesAccess.finished: {ok, name, origin} or {ok, error}).
  function applyGrant(domain, result) {
    internal.set(domain, Sales.applyGrantResult(root.record(domain), result))
  }

  // A store left the config: its record and cache entry go.
  function forget(domain) {
    delete internal.records[domain]
    cache.forget(domain)
    internal.revision++
  }

  // Drops the cache entries of stores not in `domains`.
  function retain(domains) {
    cache.retain(domains)
  }

  QtObject {
    id: internal
    property var records: Object.create(null)
    property int revision: 0

    function set(domain, record) {
      internal.records[domain] = record
      internal.revision++
    }
  }

  CacheStore {
    id: cache
    prepared: root.prepared
    home: root.home
  }
}
