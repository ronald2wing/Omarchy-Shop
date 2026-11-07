pragma ComponentBehavior: Bound
import QtQuick
import "../js/config.mjs" as Config
import "../js/errors.mjs" as Errors
import "../js/metrics.mjs" as Metrics
import "../js/schedule.mjs" as Schedule

// When each store's sales are fetched: one re-arming Timer, a priority queue
// (user > today > yesterday > history) run two at a time, dedup by
// domain:range, and per-range backoff. The history (completed periods) is
// never on a fixed timer: see js/schedule.mjs historyDue.
Item {
  id: root

  // Valid config stores, in order.
  property var stores: []
  // ConfigStore.settings: pollSeconds and alerts.notify are read.
  required property var settings
  // SalesData: each store's record holds the store clock and the history
  // and yesterday fetch times the schedule reads (record(domain)).
  required property var salesData
  property bool panelOpen: false
  // False while the CLI is missing or startup has not finished: nothing is
  // queued then.
  property bool enabled: false
  // Bumped whenever the set of queued or running domains changes.
  readonly property int pendingRevision: internal.pendingRevision

  // A fetch-sales run finished. range: today|history|yesterday; result is
  // the helper's object (ok or not).
  signal fetched(string domain, string range, var result, bool withTraffic)

  // Stagger the first history/yesterday fetches 20 s apart per store, after
  // the first today round. A history older than 6 h is fetched again now.
  function startup() {
    const now = Date.now()
    for (let i = 0; i < root.stores.length; i++) {
      const d = root.stores[i].domain
      const e = internal.entry(d)
      e.notBefore = now + 5000 + 20000 * i
      if (Schedule.historyStale(internal.clock(d), now)) e.forceHistory = true
    }
    internal.tick()
  }

  // A user refresh: clear backoff and queue today (with traffic) at user
  // priority; the history keeps its own cadence (refreshHistory is the
  // panel's call for a period that has none yet). lift also ends a
  // sales_access_required suspension (one store's refresh; the global one
  // leaves them).
  function refresh(domains, lift) {
    for (let i = 0; i < domains.length; i++) {
      const e = internal.entry(domains[i])
      if (lift) e.suspended = false
      if (e.suspended || !root.enabled) continue
      const cleared = Schedule.clearBackoff(e)
      cleared.notBefore = 0
      internal.entries[domains[i]] = cleared
      internal.enqueue(domains[i], "today", true, true)
    }
    internal.runNext()
    internal.rearm()
  }

  // One history fetch now, at user priority: Home asks for it when the
  // chosen period has no figures for a store. -> null, or why it can't run:
  // the scheduler has not started (config or state still loading; the CLI
  // is the caller's check), or the store waits for a new sales-access
  // grant.
  function refreshHistory(domain) {
    if (!root.enabled) return Errors.configUnavailable()
    const e = internal.entry(domain)
    if (e.suspended) return Errors.salesAccessRequired()
    internal.entries[domain] = Schedule.clearBackoff(e, ["history"])
    internal.enqueue(domain, "history", true, false)
    internal.runNext()
    return null
  }

  // A newly added (or newly granted) store: today and history.
  function addStore(domain) {
    if (!root.enabled) return
    const e = internal.entry(domain)
    e.suspended = false
    e.notBefore = 0
    internal.enqueue(domain, "today", false, true)
    internal.enqueue(domain, "history", false, false)
    internal.runNext()
    internal.rearm()
  }

  function queueToday(domain, withTraffic) {
    if (!root.enabled) return
    const e = internal.entry(domain)
    if (e.suspended || Date.now() < e.backoffUntil.today) return
    internal.enqueue(domain, "today", false, withTraffic && !e.dropTraffic)
    internal.runNext()
  }

  function queueHistory(domain) {
    if (!root.enabled) return
    const e = internal.entry(domain)
    if (e.suspended || Date.now() < e.backoffUntil.history) return
    internal.enqueue(domain, "history", false, false)
    internal.runNext()
  }

  // The panel opened a store's view: its history when stale, and today
  // with traffic when the traffic is.
  function storeViewed(domain) {
    if (Schedule.historyStale({ historyFetchedAt: root.salesData.record(domain).sales.fetchedAt.history }, Date.now())) root.queueHistory(domain)
    if (root.trafficStale(domain)) root.queueToday(domain, true)
  }

  // True when the store's traffic was never fetched or is older than
  // trafficMaxAgeMs, so the next today fetch should include it.
  function trafficStale(domain) {
    const e = internal.entries[domain]
    const age = e && e.lastTrafficAt ? Date.now() - e.lastTrafficAt : -1
    return age < 0 || age > internal.trafficMaxAgeMs
  }

  // When a failing today fetch will be retried (ms), or 0.
  function retryAt(domain) {
    const e = internal.entries[domain]
    return e && e.failures.today > 0 && !e.suspended ? e.backoffUntil.today : 0
  }

  function isPending(domain) {
    return internal.queue.some(j => j.domain === domain)
        || Object.keys(internal.runningJobs).some(k => internal.runningJobs[k].job.domain === domain)
  }

  // Cancel everything for a domain and drop its timing.
  function forget(domain) {
    internal.queue = internal.queue.filter(j => j.domain !== domain)
    const keys = Object.keys(internal.runningJobs)
    for (let i = 0; i < keys.length; i++) {
      const r = internal.runningJobs[keys[i]]
      if (r.job.domain !== domain) continue
      r.proc.cancel()
      r.proc.destroy()
      delete internal.runningJobs[keys[i]]
    }
    delete internal.entries[domain]
    internal.bump()
    internal.runNext()
  }

  onEnabledChanged: internal.tick()
  // A panel opened: every store whose today figures aren't fresh is
  // fetched now (after the tick, which queues the ones already due).
  onPanelOpenChanged: {
    internal.tick()
    if (root.panelOpen) internal.queueStaleToday()
  }
  // A store missing from `stores` keeps its entry and running jobs: the list
  // empties while config.json is briefly unreadable, and dropping entries
  // then would lose backoff, suspension and staggering. The owner calls
  // forget(domain) when a valid config removes a store.
  onStoresChanged: internal.tick()
  onSettingsChanged: {
    const pollMs = internal.pollMs()
    const keys = Object.keys(internal.entries)
    for (let i = 0; i < keys.length; i++) {
      const e = internal.entries[keys[i]]
      if (e.lastTodayAt && e.failures.today === 0) e.todayDueAt = e.lastTodayAt + pollMs
    }
    internal.tick()
  }

  QtObject {
    id: internal
    readonly property var priorities: ({ user: 0, today: 1, yesterday: 2, history: 3 })
    readonly property int concurrency: 2
    readonly property int trafficMaxAgeMs: 55000
    property var entries: Object.create(null)
    property var queue: []
    property var runningJobs: Object.create(null)
    property int seq: 0
    property int pendingRevision: 0

    function pollMs() {
      return root.settings.pollSeconds * 1000
    }

    function entry(domain) {
      let e = internal.entries[domain]
      if (!e) {
        e = Schedule.freshEntry()
        internal.entries[domain] = e
      }
      return e
    }

    function queueStaleToday() {
      const now = Date.now()
      for (let i = 0; i < root.stores.length; i++) {
        const d = root.stores[i].domain
        const at = root.salesData.record(d).sales.fetchedAt.today
        if (at > 0 && !Metrics.isStale(at, now, root.settings.pollSeconds)) continue
        root.queueToday(d, root.trafficStale(d))
      }
    }

    // The store clock and fetch times from the store's SalesData record, in
    // the entry shape js/schedule.mjs reads. SalesData applies a result
    // before done() re-arms: fetched() is emitted first.
    function clock(domain) {
      const rec = root.salesData.record(domain)
      const y = rec.yesterday
      return {
        timezone: rec.timezone, utcOffsetMinutes: rec.utcOffsetMinutes, dayEndsAt: rec.dayEndsAt, localDate: rec.localDate,
        historyFetchedAt: rec.sales.fetchedAt.history, historyLocalDate: rec.historyLocalDate,
        yesterdayDate: y ? y.date : "", yesterdayFetchedAt: y ? y.fetchedAt : 0
      }
    }

    function bump() {
      internal.pendingRevision++
    }

    function enqueue(domain, range, user, withTraffic) {
      const key = domain + ":" + range
      if (internal.runningJobs[key]) return
      for (let i = 0; i < internal.queue.length; i++) {
        const j = internal.queue[i]
        if (j.key !== key) continue
        if (user) { j.user = true; j.priority = internal.priorities.user }
        if (withTraffic) j.withTraffic = true
        internal.sortQueue()
        return
      }
      if (range === "today") internal.entry(domain).todayTicks++
      internal.queue.push({ key: key, domain: domain, range: range, user: !!user, withTraffic: !!withTraffic, priority: user ? internal.priorities.user : internal.priorities[range], seq: internal.seq++ })
      internal.sortQueue()
      internal.bump()
    }

    function sortQueue() {
      internal.queue.sort((a, b) => a.priority !== b.priority ? a.priority - b.priority : a.seq - b.seq)
    }

    // Config.TIMEZONE_RE caps each segment at 64; the whole name is capped
    // too so argv stays short.
    function validTimezone(tz) {
      return typeof tz === "string" && tz.length <= 64 && Config.TIMEZONE_RE.test(tz)
    }

    function runNext() {
      while (Object.keys(internal.runningJobs).length < internal.concurrency && internal.queue.length > 0) {
        const job = internal.queue.shift()
        const tz = internal.clock(job.domain).timezone
        const args = ["--store=" + job.domain, "--range=" + job.range]
        if (job.range !== "history" && internal.validTimezone(tz)) args.push("--timezone=" + tz)
        if (job.range === "today" && job.withTraffic) args.push("--with-traffic")
        const proc = procComponent.createObject(root, { range: job.range })
        internal.runningJobs[job.key] = { job: job, proc: proc }
        proc.finished.connect(r => internal.done(job, proc, r))
        proc.run(args)
      }
    }

    function done(job, proc, r) {
      delete internal.runningJobs[job.key]
      proc.destroy()
      internal.entries[job.domain] = Schedule.entryAfter(internal.entries[job.domain], job.range, r, Date.now(), internal.pollMs(), job.withTraffic)
      internal.bump()
      root.fetched(job.domain, job.range, r, job.withTraffic)
      internal.runNext()
      internal.rearm()
    }

    function queuedOrRunning(key) {
      if (internal.runningJobs[key]) return true
      for (let i = 0; i < internal.queue.length; i++) if (internal.queue[i].key === key) return true
      return false
    }

    function tick() {
      if (!root.enabled) { tickTimer.stop(); return }
      const now = Date.now()
      for (let i = 0; i < root.stores.length; i++) {
        const store = root.stores[i]
        const d = store.domain
        const e = internal.entry(d)
        if (e.suspended) continue
        const c = internal.clock(d)
        const eligible = Schedule.liveEligible(store, root.settings, root.panelOpen)
        const rolled = Schedule.dayRolledOver(c, now)
        // Past the store's midnight, refetch today once to learn the new day.
        if (eligible && rolled && e.lastTodayAt < c.dayEndsAt && e.todayDueAt > now && now >= e.backoffUntil.today) e.todayDueAt = now
        if (eligible && now >= e.todayDueAt && now >= e.backoffUntil.today && !internal.queuedOrRunning(d + ":today")) {
          const withTraffic = !e.dropTraffic && root.trafficStale(d) && (e.todayTicks % 5 === 0 || root.panelOpen)
          internal.enqueue(d, "today", false, withTraffic)
        }
        if (now < e.notBefore) continue
        const localDate = Schedule.effectiveLocalDate(c, now)
        if (now >= e.backoffUntil.history && (e.forceHistory || Schedule.historyDue(c, now, localDate))) {
          internal.enqueue(d, "history", false, false)
        }
        if (eligible && c.localDate && now >= e.backoffUntil.yesterday && Schedule.yesterdayDue(c, now)) {
          internal.enqueue(d, "yesterday", false, false)
        }
      }
      internal.runNext()
      internal.rearm()
    }

    function rearm() {
      if (!root.enabled) { tickTimer.stop(); return }
      const now = Date.now()
      let next = now + 3600000
      for (let i = 0; i < root.stores.length; i++) {
        const store = root.stores[i]
        const e = internal.entries[store.domain]
        if (!e || e.suspended) continue
        const eligible = Schedule.liveEligible(store, root.settings, root.panelOpen)
        if (eligible) next = Math.min(next, Math.max(e.todayDueAt, e.backoffUntil.today))
        if (e.notBefore > now) next = Math.min(next, e.notBefore)
        if (e.backoffUntil.history > now) next = Math.min(next, e.backoffUntil.history)
        if (e.backoffUntil.yesterday > now) next = Math.min(next, e.backoffUntil.yesterday)
        const c = internal.clock(store.domain)
        if (c.dayEndsAt > now) next = Math.min(next, c.dayEndsAt + 1000)
        const localDate = Schedule.effectiveLocalDate(c, now)
        if (!e.forceHistory && c.historyFetchedAt && localDate) next = Math.min(next, Schedule.historyNextAt(c, now, localDate))
      }
      tickTimer.interval = Math.max(1000, next - now)
      tickTimer.restart()
    }
  }

  Timer {
    id: tickTimer
    repeat: false
    onTriggered: internal.tick()
  }

  Component {
    id: procComponent
    HelperProcess {
      helper: "fetch-sales"
    }
  }
}
