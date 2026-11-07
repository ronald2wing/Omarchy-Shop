// The panel banner: account, CLI and limit states appear only here, in a
// fixed priority, so store rows never repeat them. Pure; the text comes
// from js/copy.mjs.
import { errorOf, t } from "./copy.mjs"
import { clockLocal } from "./format.mjs"
import { isStale } from "./metrics.mjs"
import { needsAccess, salesRateLimited } from "./snapshot.mjs"
import { asClause } from "./text.mjs"

// Stale this long (or longer) is a warning; before that, information.
const STALE_WARN_MS = 10 * 60000

function banner(id, tone, title, body, actions, busy) {
  return { id: id, tone: tone, title: title, body: body, actions: actions, busy: !!busy }
}

function action(id, label) {
  return { id: id, label: label }
}

// Priority: config error › write failed › install failed › CLI missing ›
// installing › CLI check failed › session expired › signed out › signing in › rate limited ›
// stale. dismissedWriteError is the JSON of the write error the user
// dismissed. -> { id, tone, title, body, actions: [{id, label}], busy }
// or null.
export function bannerFor(snapshot, nowMs, dismissedWriteError) {
  const s = snapshot || {}
  if (s.stateError) return banner("stateError", "error", errorOf(s.stateError), "", [])
  if (s.configError) {
    const ce = s.configError
    const body = ce.code === "config_unsupported" ? errorOf(ce) : t("banner.configError.body", { message: asClause(ce.message) })
    return banner("configError", "error", t("banner.configError.title"), body, [action("openConfig", t("home.openFile")), action("resetConfig", t("settings.resetConfig"))])
  }
  if (s.configWriteError && JSON.stringify(s.configWriteError) !== dismissedWriteError)
    return banner("configWriteError", "error", t("banner.configWriteError.title"), errorOf(s.configWriteError), [action("dismissWriteError", t("action.dismiss"))])

  const cli = s.cli || {}
  if (cli.status === "install_failed")
    return banner("installFailed", "error", t("banner.installFailed.title"), errorOf(cli.error), [action("install", t("action.retry"))])
  if (cli.status === "missing") {
    const missing = t(cli.missing === "node" ? "banner.missing.node" : "banner.missing.cli", { node: s.pins.node, cli: s.pins.cli })
    return banner("cliMissing", "warn", t("error.cli_missing"),
      t("banner.cliMissing.body", { miseInstalls: cli.installs, missing: missing }),
      [action("install", t("action.install"))])
  }
  if (cli.status === "installing")
    return banner("installing", "info", t("banner.installing.title"), t("banner.installing.body"), [action("cancelInstall", t("action.cancel"))], true)
  // The CLI check itself failed (check-account timed out or crashed):
  // sales stay paused until it passes, so say why and offer the re-check
  // (it also retries itself, after 30 s to 5 min).
  if (cli.status === "unknown" && cli.error)
    return banner("cliCheckFailed", "warn", t("banner.cliCheckFailed.title"), errorOf(cli.error), [action("retryCheck", t("action.retry"))])

  const stores = s.stores || {}
  const domains = Object.keys(stores)
  for (let i = 0; i < domains.length; i++) {
    const st = stores[domains[i]]
    const lr = st && st.themeState ? st.themeState.lastResult : null
    if (lr && lr.error && lr.error.code === "theme_session_expired")
      return banner("sessionExpired", "warn", t("banner.sessionExpired.title"), t("error.theme_session_expired"), [action("resignIn", t("banner.sessionExpired.action"))])
  }

  const account = s.account || {}
  if (account.status === "signed_out")
    return banner("signedOut", "warn", t("banner.signedOut.title"), t("banner.signedOut.body"), [action("signIn", t("action.signIn"))])
  if (account.status === "signing_in")
    return banner("signingIn", "info", t("banner.signingIn.title"), "", [action("cancelSignIn", t("action.cancel"))], true)

  for (let k = 0; k < domains.length; k++) {
    const sk = stores[domains[k]]
    if (salesRateLimited(sk)) {
      const retryAt = Number(sk.sales.retryAt || 0)
      return banner("rateLimited", "info", t("error.rate_limited"), retryAt > 0 ? t("banner.rateLimited.body", { time: clockLocal(retryAt) }) : "", [])
    }
  }

  // Every eligible store (fetched before, not loading, not waiting on
  // access) is stale: one line with the oldest age.
  const poll = s.settings && s.settings.pollSeconds ? s.settings.pollSeconds : 60
  let eligible = 0
  let staleCount = 0
  let oldest = 0
  for (let j = 0; j < domains.length; j++) {
    const sj = stores[domains[j]]
    if (!sj || !sj.sales || sj.sales.pending || sj.sales.paused || needsAccess(sj.salesAccess)) continue
    const at = sj.sales.fetchedAt ? Number(sj.sales.fetchedAt.today) || 0 : 0
    if (at <= 0) continue
    eligible++
    if (isStale(at, nowMs, poll)) {
      staleCount++
      if (oldest === 0 || at < oldest) oldest = at
    }
  }
  if (eligible > 0 && staleCount === eligible && oldest > 0) {
    const age = nowMs - oldest
    return banner("stale", age >= STALE_WARN_MS ? "warn" : "info", t("banner.stale.title", { minutes: Math.max(1, Math.round(age / 60000)) }), "", [])
  }
  return null
}
