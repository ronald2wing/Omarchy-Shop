import QtQuick
import "../../js/banner.mjs" as Banner
import "../../js/bar.mjs" as Bar
import "../../js/config.mjs" as Config
import "../../js/confirm.mjs" as Confirm
import "../../js/copy.mjs" as Copy
import "../../js/dates.mjs" as Dates
import "../../js/errors.mjs" as Errors
import "../../js/format.mjs" as Format
import "../../js/hourly.mjs" as Hourly
import "../../js/keymap.mjs" as Keymap
import "../../js/metrics.mjs" as Metrics
import "../../js/os.mjs" as Os
import "../../js/preflight.mjs" as Preflight
import "../../js/sales.mjs" as Sales
import "../../js/schedule.mjs" as Schedule
import "../../js/snapshot.mjs" as Snapshot
import "../../js/text.mjs" as TextUtil
import "../../js/themejob.mjs" as ThemeJob
import "../../js/themes.mjs" as Themes
import "../../js/timing.mjs" as Timing
import "../../js/urls.mjs" as Urls

// Loads every js/*.mjs in the real QML engine (its JS subset, not Node)
// and runs each module once; prints JS_MODULES_OK only when every check
// passed. Runs under the plain qml runtime.
// Run alone: tests/run tests/qml/js_modules_smoke.qml
Item {
  id: root

  // A JS object emitted through a `var` signal parameter comes back with its
  // arrays as sequence wrappers (Array.isArray false); Os.plain restores them.
  signal relay(var value)
  property var relayed: null
  onRelay: (value) => root.relayed = value

  Smoke {
    id: smoke
    name: "JS_MODULES"
    interval: 0
    steps: [
      function() {
        const now = 1762520400000
        const cfg = Config.normalizeConfig('{"version":2,"stores":[{"domain":"acme.myshopify.com","label":"Acme","theme":null},{"label":"x"}]}')
        smoke.check(cfg.error === null && cfg.config.stores.length === 1 && cfg.invalidStores.length === 1, "normalizeConfig")
        smoke.check(Config.normalizeConfig('{"stores":[]}').error.code === "config_unsupported", "v1 refused")
        smoke.check(Config.normalizeDomain("https://Acme.myshopify.com/admin") === "acme.myshopify.com", "normalizeDomain")
        smoke.check(Config.normalizeDomain("аlpha") === null, "lookalike refused")
        smoke.check(Config.cleanLabel("bad‮name") === null, "label control chars")
        smoke.check(Config.cleanLabel("a b") === null, "label line separator")
        smoke.check(ThemeJob.liveFlags(true, false).join(" ") === "--allow-live", "liveFlags split")
        smoke.check(ThemeJob.jobCommand("restore", "a.myshopify.com", { backupId: "1-2", allowLive: true, confirmLive: true }).args.join(" ") === "--store=a.myshopify.com --backup=1-2 --allow-live --confirm-live", "jobCommand")
        smoke.check(Timing.deadlineMs("fetch-sales", "today") === 30000 && Timing.cap("discover-stores") === 2097152 && Timing.deadlineMs("preview-theme") === 0, "timing")
        smoke.check(Config.TIMEZONE_RE.test("America/Argentina/Buenos_Aires") && !Config.TIMEZONE_RE.test("a b"), "TIMEZONE_RE")
        const patched = Config.applyStorePatch(cfg.config, "acme.myshopify.com", { theme: { folder: "~/t", allowLive: true } }, "/home/u", { allowThemeKeys: true })
        smoke.check(patched.config.stores[0].theme.folder === "/home/u/t" && patched.config.stores[0].theme.allowLive === false, "applyStorePatch")
        const added = Config.addStore(cfg.config, "beta", "")
        smoke.check(added.domain === "beta.myshopify.com" && added.showInBar && added.config.stores[1].label === "beta", "addStore")
        let full = Config.emptyConfig()
        for (let i = 0; i < 50; i++) full = Config.addStore(full, "s" + i, "").config
        smoke.check(Config.addStore(full, "more", "").error.code === "too_many_stores", "too_many_stores")
        const text = Config.serializeConfig(Config.moveStore(added.config, "beta.myshopify.com", 0).config, '{"version":2,"x":1,"stores":[{"label":"x"}]}')
        smoke.check(JSON.parse(text).x === 1 && JSON.parse(text).stores.length === 3, "serializeConfig")
        smoke.check(Config.applySettingsPatch(cfg.config, { pollSeconds: 5 }).config.pollSeconds === 30, "applySettingsPatch")
        smoke.check(Config.parsePatch('{"label":"A"}').value.label === "A" && Config.parsePatch("[1]").error.code === "invalid_patch", "parsePatch")
        smoke.check(Config.addStore(cfg.config, "beta", null, [{ domain: "beta.myshopify.com", name: "Beta" }]).label === "Beta", "addStore: the discovered name")
        smoke.check(Config.findStore(cfg.config, "acme.myshopify.com").label === "Acme" && Config.sameThemeLink(null, { folder: "", target: "live" }), "findStore / sameThemeLink")

        smoke.check(TextUtil.scrubControl(" a​b\t", 80) === "a b", "scrubControl")
        smoke.check(TextUtil.shortCodes(["Acme Apparel", "Épicerie Zoé"]).join() === "AA,EZ", "shortCodes")
        smoke.check(TextUtil.shortCodes(["Acme Apparel", "Alpha Audio"]).join(",") === "AA,AA2", "shortCodes")
        smoke.check(TextUtil.subdomainLabel("acme.myshopify.com") === "acme", "subdomainLabel")
        smoke.check(Errors.cliMissing("node").error.missing === "node" && Errors.storeBusy("push").error.code === "store_busy" && Errors.isRateLimit("rate_limited"), "errors")

        smoke.check(Format.isNum(1) && !Format.isNum(NaN), "isNum")
        smoke.check(Format.money(1284.5, "USD") === "$1,284.50", "money")
        smoke.check(Format.money(1284.5, "USD", { compact: true }) === "$1.3k", "money compact")
        smoke.check(Format.money(812, "CHF") === "CHF 812.00", "money unknown currency")
        smoke.check(ThemeJob.resultDetails({ ok: true, partial: true, warnings: [{ kind: "issue", path: "a.liquid", message: "bad" }, { kind: "symlink", path: "b" }] }).join("|") === "a.liquid: bad|symlink b", "result details")
        smoke.check(ThemeJob.resultTone({ ok: true, partial: true, warnings: [] }) === "warn", "result tone")
        var res = ThemeJob.resultOf({ action: "push", name: "Dawn" }, { ok: false, error: { code: "terminated" }, writeStarted: true, backupId: "1762500000-1" }, { canceled: true, nowMs: 1762520400000 })
        smoke.check(ThemeJob.resultText(res, {}) === "Stopped. Files on Dawn may have changed: check the theme." && ThemeJob.keptText(res, 1762520400000).indexOf("Backup kept") === 0, "result text / kept text")
        smoke.check(Format.percent(0.016) === "1.6%" && Format.trendText({ direction: "down", pct: -2.46 }) === "▼ 2.5%" && Format.trendGlyph("down") === "▼", "percent")
        smoke.check(Format.dayLabel("2025-11-03") === "Mon 3 Nov" && Format.monthLabel("2025-12") === "Dec 2025", "dates")
        smoke.check(Format.clockLocal(new Date(2025, 0, 1, 8, 5).getTime()) === "08:05", "clockLocal")
        const at = new Date(2025, 10, 6, 11, 35).getTime()
        smoke.check(Format.backupWhen(at, new Date(2025, 10, 6, 18, 0).getTime()) === "Today 11:35", "backupWhen today")
        smoke.check(Format.backupWhen(at, new Date(2025, 10, 20, 9, 0).getTime()) === "Thu 6 Nov, 11:35", "backupWhen day")
        smoke.check(Format.bytes(4718123) === "4.5 MB" && Format.count(1234567) === "1,234,567", "bytes/count")
        smoke.check(Format.timeAgo(now - 60000, now) === "1 min ago" && Format.elapsed(42000) === "0:42", "timeAgo")
        smoke.check(Format.homeRelative("/home/u/x", "/home/u") === "~/x", "homeRelative")

        smoke.check(Os.utf8ByteLength("aé€💡") === 10 && Os.fileUrlToPath("file:///a%20b") === "/a b", "os")
        smoke.check(Os.exitToError(124, 0).code === "timeout" && Os.exitToError(0, Os.SIGTERM).code === "terminated", "exitToError")
        smoke.check(Urls.isSafeOpenUrl("http://127.0.0.1:9292/", "acme.myshopify.com", "/home/u") && !Urls.isSafeOpenUrl("https://acme.myshopify.com.evil.tld/admin", "acme.myshopify.com", "/home/u"), "urls")
        smoke.check(Urls.isSafeOpenUrl(Urls.configFileUrl("/home/u"), "", "/home/u"), "config file url")
        smoke.check(Urls.adminUrl("acme.myshopify.com") === "https://acme.myshopify.com/admin", "adminUrl")

        smoke.check(Schedule.nextDelayMs("rate_limited", 2, () => 0) === 120000 && Schedule.nextDelayMs("signed_out", 1) === 60000, "nextDelayMs")
        smoke.check(Schedule.storeLocalDate(now, -300) === "2025-11-07" && Dates.previousDate("2024-03-01") === "2024-02-29" && Dates.parseYmd("2024-03-01").month === 3, "dates")
        const start = Date.UTC(2025, 10, 7, 5, 0) // store-local midnight at UTC-5
        smoke.check(Schedule.historyDue({}, now, "2025-11-07"), "due rules")
        smoke.check(!Schedule.historyDue({ historyFetchedAt: start + 1800000, historyLocalDate: "2025-11-07", utcOffsetMinutes: -300 }, start + 3600000, "2025-11-07"), "no hourly history")
        smoke.check(Schedule.historyDue({ historyFetchedAt: start + 1800000, historyLocalDate: "2025-11-07", utcOffsetMinutes: -300 }, start + 22200000, "2025-11-07"), "backfill at +6h10")
        smoke.check(Schedule.historyStale({ historyFetchedAt: now - 7 * 3600000 }, now), "historyStale")
        smoke.check(Schedule.liveEligible({ showInBar: true }, { alerts: { notify: false } }, false), "liveEligible")
        const entry = Schedule.entryAfter(Schedule.freshEntry(), "today", { ok: false, error: { code: "timeout" } }, now, 60000, false, () => 0)
        smoke.check(entry.failures.today === 1 && entry.backoffUntil.today === now + 60000 && Schedule.clearBackoff(entry).failures.today === 0, "entryAfter / clearBackoff")
        smoke.check(Schedule.effectiveLocalDate({ localDate: "2025-11-07", dayEndsAt: now + 1 }, now) === "2025-11-07", "effectiveLocalDate")

        const today = { ok: true, fetchedAt: now, currency: "USD", timezone: "America/Toronto", localDate: "2025-11-07", utcOffsetMinutes: -300, dayEndsAt: 1762578000000,
          today: { sales: 812, orders: 21, truncated: false, latestOrder: { id: "gid://shopify/Order/1" }, traffic: { sessions: 1621, cartAdds: 123, reachedCheckout: 30, completed: 8 } } }
        const yesterday = { ok: true, fetchedAt: now, yesterday: { date: "2025-11-06", startEpoch: 1762405200, endEpoch: 1762491600,
          orderPoints: [[1762405300000, 100], [1762430000000, 50.5]], salesHourly: [{ hour: 0, sales: 100 }, { hour: 9, sales: -20 }],
          trafficHourly: [{ hour: 0, sessions: 40, cartAdds: 3, reachedCheckout: 1, completed: 0 }] } }
        const fold = (s, r, range) => Sales.applyFetchResult(s, r, { range: range, withTraffic: true, nowMs: now, pollSeconds: 60 }).record
        let st = fold(Sales.emptyRecord(), yesterday, "yesterday")
        smoke.check(st.sales.yesterdayHourly.length === 24 && st.sales.yesterdayHourly[9].sales === -20 && st.sales.yesterdayHourly[6].sales === 0, "yesterday chart from salesHourly")
        st = fold(st, today, "today")
        smoke.check(st.sales.today.baseline.sales === 150.5 && st.sales.today.baseline.orders === 2, "baseline")
        st = fold(st, { ok: true, fetchedAt: now, localDate: "2025-11-07", history: { last7d: { sales: 10, orders: 1, traffic: null, previous: { sales: 5, orders: 1, traffic: null }, buckets: [] } } }, "history")
        const rec = JSON.parse(JSON.stringify(Sales.cacheRecord(st)))
        smoke.check(Sales.fromCache(rec).sales.history.last7d.sales === 10 && Sales.CACHE_VERSION === 5, "cache round trip")
        const det = Sales.applyFetchResult(Object.assign(Sales.emptyRecord(), { lastSeen: { orderCount: 20, latestOrderId: "x", localDate: "2025-11-07", at: now - 1000 } }), today, { range: "today", withTraffic: true, nowMs: now, pollSeconds: 60 })
        smoke.check(det.newOrders === 1 && det.record.sales.newOrderAt === now, "the new-order rule")
        const fr = Sales.applyFetchResult(Sales.emptyRecord(), today, { domain: "acme.myshopify.com", range: "today", withTraffic: true, nowMs: now, pollSeconds: 60 })
        smoke.check(fr.record.sales.today.orders === 21 && fr.cache && fr.newOrders === 0, "applyFetchResult")
        smoke.check(Sales.applyGrantResult(fold(st, { ok: false, error: { code: "sales_access_required" } }, "today"), { ok: true }).salesAccess === "granted", "applyGrantResult")
        smoke.check(Hourly.hourlyBuckets({ startEpoch: 1762405200, endEpoch: 1762491600, orderPoints: [[1762405300000, 5]] }, null)[0].sales === 5, "hourlyBuckets")
        smoke.check(Hourly.todayBaseline(yesterday.yesterday, now) !== undefined, "todayBaseline")
        const stores = [{ domain: "acme.myshopify.com", label: "Acme", showInBar: true, theme: { folder: "/home/u/t", target: "live", allowLive: true } }]
        const info = { themes: Themes.reduceThemes(Themes.emptyThemes(), { ok: true, themes: [{ id: "1", name: "Dawn", role: "live" }] }, 1), folder: Themes.emptyFolder(), backups: Themes.emptyThemeState().backups }
        const parts = { cli: { status: "ready" }, account: { status: "signed_in" }, settings: { pollSeconds: 60 },
          stores: [{ cfg: stores[0], sales: st, info: info }] }
        const build = Snapshot.buildSnapshot(parts, null)
        const snap = build.snapshot
        smoke.check(snap.stores["acme.myshopify.com"].sales.today.orders === 21, "buildSnapshot")
        smoke.check(snap.pins.cli === Snapshot.CLI_PIN && snap.pins.node === Snapshot.NODE_PIN, "pins")
        // Memo-backed identity in this engine.
        const again = Snapshot.buildSnapshot(parts, build).snapshot
        smoke.check(again.stores["acme.myshopify.com"] === snap.stores["acme.myshopify.com"], "store identity kept")
        smoke.check(Snapshot.statusSummary(snap, "2.0.0").stores[0].trend.direction === "up", "statusSummary")
        smoke.check(Snapshot.initialSnapshot().cli.status === "unknown", "initialSnapshot")
        smoke.check(fold(st, { ok: false, error: { code: "sales_access_required" } }, "today").salesAccess === "required", "a fetch failure needing access")
        const store = snap.stores["acme.myshopify.com"]
        smoke.check(Snapshot.targetTheme(store).name === "Dawn" && Snapshot.targetTheme(store).live, "targetTheme")
        smoke.check(Snapshot.storeOf(snap, "acme.myshopify.com") === store && Snapshot.storeOf(snap, "nope") === null, "storeOf")
        smoke.check(Snapshot.themeState(store).themes.items.length === 1 && Snapshot.themeState(null) === null, "themeState")
        smoke.check(!Snapshot.salesFailed(store) && !Snapshot.salesRateLimited(store), "sales predicates")
        smoke.check(Snapshot.salesFailed({ sales: { status: "error", error: { code: "cli_failed" } } }) && Snapshot.salesRateLimited({ sales: { error: { code: "rate_limited" } } }), "sales predicates (failing)")
        smoke.check(Copy.themeName({ id: "", name: "", live: true }) === "Live theme" && Preflight.checkThemeAction(Preflight.factsOf({ cli: { status: "missing" } }, null), "push").error.code === "cli_missing"
          && Preflight.beforeDialog(Preflight.factsOf({ cli: { status: "ready" } }, store), "pull") === null, "themeName / checkThemeAction / beforeDialog")
        smoke.check(Snapshot.figuresBlocked({ account: { status: "signed_out" } }, store) === false && Snapshot.accountBlock({ cli: { status: "installing" } }) === "installing", "figuresBlocked / accountBlock")
        smoke.check(Themes.backupById(Snapshot.themeState(store), "x") === null && Themes.restoreIsLive(Snapshot.themeState(store), "x") === false && Themes.folderState(Snapshot.themeState(store), "/nope") === "unknown" && Themes.targetOf(store.theme, Snapshot.themeState(store)).name === "Dawn", "themes selectors")
        smoke.check(Bar.barModel(snap, ["acme.myshopify.com"], ["acme.myshopify.com"], false, now).showStores === true, "barModel")
        smoke.check(Format.trendText({ direction: "up", pct: 18.2 }) === "▲ 18%" && Format.trendText(null) === "", "trendText")
        smoke.check(TextUtil.fillTemplate("{a}-{b}", { a: 1, b: null }) === "1-", "fillTemplate")
        smoke.check(Config.cleanRemoteLabel("Acme\u0007 Apparel") === "Acme Apparel" && Themes.EPOCH_RE.test("1762500000") && Themes.parseBackupId("1762500000-1").themeId === "1", "cleanRemoteLabel / EPOCH_RE / parseBackupId")
        smoke.check(Errors.tooManyStores(50).error.message === "Shop keeps at most 50 stores" && Errors.error("x", "m").code === "x", "errors builders")
        smoke.check(Urls.configFileUrl("/home/u") === "file:///home/u" + Urls.CONFIG_REL, "CONFIG_REL")

        smoke.check(Metrics.periodView(store, "today").salesTrend.direction === "up", "periodView today")
        smoke.check(Metrics.periodView(store, "last7d").salesTrend.pct === 100, "periodView 7d")
        const k = Metrics.kpi(store, "today", 4)
        smoke.check(k.format === "percent" && k.label === "kpi.conversion" && Math.abs(k.value - 8 / 1621) < 1e-12, "kpi")
        smoke.check(Metrics.KPI_SLOTS.length === 8, "8 KPI slots")
        smoke.check(Metrics.kpi({ sales: { today: { sales: 0, orders: 0, traffic: { sessions: 10, conversion: 0.1 } } } }, "today", 4).value === null, "rates without counts is null")
        smoke.check(Errors.fromHelper({ code: "", message: "m", reason: "r", retryAfter: 3 }, "today").code === "cli_failed", "cleanError")
        smoke.check(Metrics.periodTotals(snap, ["acme.myshopify.com"], "today").byCurrency[0].sales === 812, "periodTotals")
        smoke.check(Metrics.isStale(now - 166000, now, 60) === true, "isStale")
        smoke.check(Metrics.trend(100.4, 100).direction === "flat", "trend")

        const spec = Confirm.confirmSpec({ action: "push", domain: "acme.myshopify.com" }, store, "/home/u", { pins: snap.pins, nowMs: now })
        smoke.check(spec.live && spec.title === "Push to the live theme?" && spec.facts[0].value === "~/t (also AGENTS.md and DESIGN.md, if present)", "confirmSpec push")
        const install = Confirm.confirmSpec({ action: "installCli" }, null, "/home/u", { pins: snap.pins, installs: "~/m", nowMs: now })
        smoke.check(install.commands.length === 2 && install.facts[1].value === Snapshot.CLI_PIN, "confirmSpec install")
        const b = Banner.bannerFor(Object.assign({}, snap, { cli: { status: "missing", missing: "cli" } }), now, null)
        smoke.check(b.id === "cliMissing" && b.actions[0].id === "install", "bannerFor")
        smoke.check(Banner.bannerFor(snap, now, null) === null, "no banner")
        smoke.check(Banner.bannerFor(Object.assign({}, snap, { configWriteError: { code: "config_write_failed", message: "disk" } }), now, null).body === "Couldn't save config.json: disk", "banner errorOf")
        smoke.check(Copy.t("count.orders.one") === "1 order" && Copy.ordersText(3) === "3 orders" && Copy.errorOf({ code: "store_busy", action: "pull" }) === "Wait for the pull to finish" && Copy.errorOf({ code: "folder_unusable", action: "push", state: "empty" }) === "Can't push an empty folder: pull a theme into it first" && Copy.t("no.such") === "no.such", "copy")
        smoke.check(Copy.folderWarning({ folder: { status: "ok", requested: "/f", exists: true, safe: true, themeShaped: false, empty: false } }, "/f") === Copy.t("error.not_a_theme_folder") && Copy.themeTargetOptions(null, "123").length === 2 && Copy.updatedText(0, now) === "not updated yet", "copy helpers")
        const km = Keymap.store({ linked: true, figuresShown: true })
        smoke.check(Keymap.footerText(km, { canGoBack: true }) === "h/l period · p push · u pull · b backups · Esc back" && Keymap.rowForKey(km, "p").id === "push" && Keymap.sheetRows(km, "panel")[0][1] === "Refresh store", "keymap")

        root.relay({ list: [1, 2] })
        smoke.check(root.relayed && Array.isArray(Os.plain(root.relayed).list) && Os.plain(root.relayed).list.length === 2, "Os.plain after a var signal")
        smoke.check(Os.plain(undefined) === null, "Os.plain(undefined)")
      }
    ]
  }
}
