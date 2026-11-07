// The bar widget's rules: which pills show, the account-state pill, the
// total pill's state and tooltip. Pure; BarWidget.qml binds barModel's
// fields and draws. The text comes from js/copy.mjs.
import { bannerFor } from "./banner.mjs"
import { errorOf, ordersText, t } from "./copy.mjs"
import { BAR_INITIALS, BAR_PILLS } from "./config.mjs"
import { money } from "./format.mjs"
import { awaitingFigures, periodTotals } from "./metrics.mjs"
import { accountBlock, figuresBlocked, needsAccess, salesFailed, salesRateLimited } from "./snapshot.mjs"

// An account-state pill: "󰒚 <text>" in a tone, opening `view`.
function pill(textKey, tone, tooltip, view) {
  return { text: "󰒚 " + t(textKey), tone: tone, tooltip: tooltip, view: view }
}

function storesOf(snapshot, domains) {
  const stores = snapshot && snapshot.stores ? snapshot.stores : {}
  const out = []
  for (let i = 0; i < domains.length; i++) if (stores[domains[i]]) out.push(stores[domains[i]])
  return out
}

// Some store (in order) shows today's figures: one the account state does
// not mute (Snapshot.figuresBlocked, the rule Home's rows use) with a
// today figure.
export function anyFigures(snapshot, storeOrder) {
  const list = storesOf(snapshot, storeOrder)
  for (let i = 0; i < list.length; i++) {
    const s = list[i]
    if (figuresBlocked(snapshot, s)) continue
    if (s.sales && s.sales.today && typeof s.sales.today.sales === "number") return true
  }
  return false
}

// The one pill that stands in for every store while nothing can load
// ({text, tone, tooltip, view}) or null. It reads the raw account state
// (Snapshot.accountBlock), never the banner, so a dismissable banner
// above it cannot hide it. Signed out (or signing in) takes the bar only
// while no store shows figures: a store with its own sales access keeps
// working, so its pill stays and the panel's banner carries the state.
export function accountPill(snapshot, storeOrder) {
  const s = snapshot
  if (!s) return null
  const cli = s.cli || {}
  const block = accountBlock(s)
  if (block === "config") return pill("bar.configError", "error", t("banner.configError.title"), "home")
  if (block === "state") return pill("bar.stateError", "error", errorOf(s.stateError), "home")
  if (block === "cli") {
    const failed = cli.status === "install_failed"
    return pill("bar.installCli", failed ? "error" : "warn", failed ? t("banner.installFailed.title") : t("error.cli_missing"), "home")
  }
  if (block === "installing") return pill("bar.installing", "info", t("banner.installing.title"), "home")
  const figures = anyFigures(s, storeOrder)
  if (block === "signedOut" && !figures) return pill("status.signedOut", "warn", t("banner.signedOut.title"), "home")
  if (block === "signingIn" && !figures) return pill("bar.signingIn", "info", t("banner.signingIn.title"), "home")
  if (storeOrder.length === 0 || figures) return null
  // A failed account check (Account retries it by itself) says so rather
  // than "Checking…", which is only for a check that is running.
  if (cli.status === "unknown" && cli.error) return pill("bar.cliError", "error", errorOf(cli.error), "settings")
  if (cli.status === "checking" || cli.status === "unknown") return pill("status.checking", "info", t("status.checking"), "home")
  return null
}

// One store's line in the total/icon tooltip: its figure, or why there is
// none ("…" only while Metrics.awaitingFigures says it is on its way).
export function storeLine(s) {
  if (needsAccess(s.salesAccess)) return t("error.sales_access_required")
  const today = s.sales && s.sales.today ? s.sales.today : null
  const figure = today && typeof today.sales === "number" ? money(today.sales, s.currency) + " · " + ordersText(today.orders) : ""
  if (salesFailed(s)) {
    const err = "󰀨 " + errorOf(s.sales.error)
    return figure !== "" ? figure + " · " + err : err
  }
  return figure !== "" ? figure : (awaitingFigures(s.sales) ? "…" : "—")
}

// snapshot; storeOrder (service.storeOrder); barDomains (the bar-visible
// domains, in order); vertical (the bar is vertical); nowMs (the banner's
// stale clock). -> { autoTotal, showStores, singleDisplay, accountPill,
// totals, limited, totalProblem, totalLoading, totalTooltipLines,
// latestNewOrderAt, dotTone }. On a vertical bar the panel's banner (display
// only) lends the tooltip its title and the icon its dot.
export function barModel(snapshot, storeOrder, barDomains, vertical, nowMs) {
  const order = storeOrder || []
  const shown = barDomains || []
  const banner = snapshot ? bannerFor(snapshot, nowMs, "") : null
  const bannerTone = banner ? String(banner.tone) : ""
  const display = snapshot && snapshot.settings && snapshot.settings.bar ? String(snapshot.settings.bar.display || "stores") : "stores"
  const autoTotal = display === "stores" && shown.length > BAR_PILLS
  const account = accountPill(snapshot, order)
  const showStores = !vertical && !account && display === "stores" && shown.length > 0 && !autoTotal
  const singleDisplay = vertical ? "icon" : (display === "total" || autoTotal ? "total" : (display === "stores" ? "icon" : display))
  const totalDomains = autoTotal ? shown : order
  const counted = storesOf(snapshot, totalDomains)
  let limited = false
  let problem = false
  let loading = false
  const lines = []
  for (let i = 0; i < counted.length; i++) {
    const s = counted[i]
    // Some counted store is rate limited: the total pill mutes.
    if (salesRateLimited(s)) limited = true
    // Needs access or failed: the total pill's glyph.
    if (needsAccess(s.salesAccess) || salesFailed(s)) problem = true
    // Still loading its figures (the one "…" rule; a store waiting for
    // access has none on the way).
    if (!needsAccess(s.salesAccess) && awaitingFigures(s.sales)) loading = true
    lines.push(String(s.label) + " — " + storeLine(s))
  }
  // Under the banner title on a vertical bar, or above the rate-limit note.
  if (banner && vertical) lines.unshift(String(banner.title))
  else if (limited) lines.push(t("error.rate_limited"))
  let latest = 0
  const all = storesOf(snapshot, order)
  for (let k = 0; k < all.length; k++) {
    const at = all[k].sales ? Number(all[k].sales.newOrderAt) || 0 : 0
    if (at > latest) latest = at
  }
  return {
    autoTotal: autoTotal,
    showStores: showStores,
    // The store pills show initials, not labels.
    initials: showStores && shown.length >= BAR_INITIALS,
    singleDisplay: singleDisplay,
    accountPill: account,
    totals: snapshot && totalDomains.length > 0 ? periodTotals(snapshot, totalDomains, "today") : null,
    limited: limited,
    totalProblem: problem,
    totalLoading: loading,
    totalTooltipLines: lines,
    latestNewOrderAt: latest,
    dotTone: vertical && (bannerTone === "warn" || bannerTone === "error") ? bannerTone : ""
  }
}
