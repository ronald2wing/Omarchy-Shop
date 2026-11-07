// The service snapshot: its shape (CONTRIBUTING "Service snapshot"), the
// builder Service publishes through, and the selectors views read it with.
import { emptyConfig } from "./config.mjs"
import { isRateLimit } from "./errors.mjs"
import { trend } from "./metrics.mjs"
import { emptyRecord } from "./sales.mjs"
import { emptyBackups, emptyFolder, emptyPreview, emptyThemes, targetOf } from "./themes.mjs"

// The pinned runtime (CONTRIBUTING "Pins"): the snapshot carries them as
// `pins` so Copy never hard-codes a version.
export const CLI_PIN = "5.0.1"
export const NODE_PIN = "26.13.0"
const PINS = { cli: CLI_PIN, node: NODE_PIN }

export function emptyDiscovery() {
  return { status: "idle", stores: [], truncated: false, finishedAt: 0, error: null }
}

// ---- selectors over a snapshot store ---------------------------------------

// A store whose sales access Shopify asked for, or whose browser grant is
// under way: no figures can load until it finishes.
export function needsAccess(access) {
  return access === "required" || access === "granting"
}

// snapshot.stores is keyed by domain; null for a store that is not there.
export function storeOf(snapshot, domain) {
  return snapshot && snapshot.stores ? (snapshot.stores[domain] || null) : null
}

// The store's theme state (ThemeInfo + ThemeJobs + Previews), or null.
export function themeState(store) {
  return store && store.themeState ? store.themeState : null
}

// Sales failed for a reason the store row shows in red. Rate limiting is a
// banner-level state: the figures stay and nothing is red.
export function salesFailed(store) {
  const sales = store && store.sales ? store.sales : null
  return !!sales && sales.status === "error" && !!sales.error && !isRateLimit(sales.error.code)
}

// Shopify is limiting requests for this store (the retry time is in
// sales.retryAt).
export function salesRateLimited(store) {
  const sales = store && store.sales ? store.sales : null
  return !!sales && !!sales.error && isRateLimit(sales.error.code)
}

// The theme the store's folder pushes to and pulls from: { id, name, live }
// (Themes.targetOf over the store's config theme and themeState).
export function targetTheme(store) {
  return targetOf(store ? store.theme : null, themeState(store))
}

// The account-level state that keeps figures from loading, from the raw
// snapshot fields (never from which banner shows: a dismissable banner can
// sit above it): "state" (prepare-state failed), "config" (config.json
// unreadable), "cli" (missing or its install failed), "installing",
// "signedOut", "signingIn", or "".
export function accountBlock(snapshot) {
  const s = snapshot || {}
  if (s.stateError) return "state"
  if (s.configError) return "config"
  const cli = s.cli ? s.cli.status : ""
  if (cli === "missing" || cli === "install_failed") return "cli"
  if (cli === "installing") return "installing"
  const acc = s.account ? s.account.status : ""
  if (acc === "signed_out") return "signedOut"
  if (acc === "signing_in") return "signingIn"
  return ""
}

// The store shows no figures because of the account-level state: every
// block mutes every store, except that signed out (or signing in) mutes
// only the stores without their own sales access (a granted store keeps
// fetching through its store session). Home's rows, the store view and
// the bar all read this.
export function figuresBlocked(snapshot, store) {
  const b = accountBlock(snapshot)
  if (b === "") return false
  if (b === "signedOut" || b === "signingIn") return !store || store.salesAccess !== "granted"
  return true
}

// ---- snapshot --------------------------------------------------------------

// The record for a store nothing has fetched yet: one shared object, so a
// store without state keeps its identity across builds (never mutated;
// buildStore copies what it changes).
const NO_STATE = emptyRecord()
const NO_PART = {}

function sameInputs(a, b) {
  if (!a || a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

// part: one entry of parts.stores (see buildSnapshot).
function buildStore(part, paused) {
  const st = part.sales || NO_STATE
  const sales = Object.assign({}, st.sales)
  const pending = !!part.pending
  sales.pending = pending
  sales.retryAt = part.retryAt || 0
  // Nothing will be fetched (CLI missing, not started): views show "—"
  // instead of a loading "…" that never finishes.
  sales.paused = paused
  if (sales.status === "idle" && pending) sales.status = "loading"
  const cfg = part.cfg
  const i = part.info || NO_PART
  const j = part.job || NO_PART
  return {
    domain: cfg.domain, label: cfg.label, showInBar: cfg.showInBar, theme: cfg.theme,
    currency: st.currency,
    salesAccess: part.granting ? "granting" : st.salesAccess,
    salesAccessError: st.salesAccessError,
    sales: sales,
    themeState: {
      themes: i.themes || emptyThemes(),
      folder: i.folder || emptyFolder(),
      backups: i.backups || emptyBackups(),
      job: j.job || null,
      lastResult: j.lastResult || null,
      preview: part.preview || emptyPreview()
    }
  }
}

// parts: { configError, configWriteError, stateError, invalidStores, cli,
// account, alertTools, pendingConfirm, themesBusy, granting, discovery,
// settings, salesPaused (nothing will be fetched), stores: [{ cfg (the
// valid config entry, in order), sales (its SalesData record), info
// (ThemeInfo state), job (ThemeJobs state), preview (Previews state),
// pending, granting, retryAt }] }. previousBuild: the last result, whose
// store objects are reused when their inputs are unchanged (bindings on
// other stores then do not re-evaluate for one store's tick), or null.
// -> { snapshot, memo } (memo: the inputs per domain, for the next build;
// never a WeakMap: QV4 (Qt 6.12) segfaults in sameValueZero on a WeakMap
// lookup once a collected key is in the table).
export function buildSnapshot(parts, previousBuild) {
  const out = {
    configError: parts.configError || null,
    configWriteError: parts.configWriteError || null,
    stateError: parts.stateError || null,
    invalidStores: parts.invalidStores || [],
    cli: parts.cli,
    account: parts.account,
    alertTools: parts.alertTools,
    pendingConfirm: parts.pendingConfirm || null,
    themesBusy: parts.themesBusy === "job" || parts.themesBusy === "preview" ? parts.themesBusy : "",
    granting: parts.granting === true,
    discovery: parts.discovery || emptyDiscovery(),
    settings: parts.settings,
    pins: PINS,
    stores: {}
  }
  const stores = parts.stores || []
  const paused = parts.salesPaused === true
  const prevStores = previousBuild && previousBuild.snapshot ? previousBuild.snapshot.stores : null
  const prevMemo = previousBuild && previousBuild.memo ? previousBuild.memo : null
  const memo = Object.create(null)
  for (let i = 0; i < stores.length; i++) {
    const part = stores[i]
    const d = part.cfg.domain
    const inputs = [part.cfg, part.sales || NO_STATE, part.info || null, part.job || null, part.preview || null,
      !!part.pending, !!part.granting, part.retryAt || 0, paused]
    memo[d] = inputs
    const prev = prevStores ? prevStores[d] : null
    out.stores[d] = prev && prevMemo && sameInputs(prevMemo[d], inputs) ? prev : buildStore(part, paused)
  }
  return { snapshot: out, memo: memo }
}

// The snapshot before the service has published anything.
export function initialSnapshot() {
  const c = emptyConfig()
  return buildSnapshot({
    cli: { status: "unknown", missing: null, installs: null, error: null },
    account: { status: "unknown", error: null },
    alertTools: { notify: null, sound: null },
    settings: { pollSeconds: c.pollSeconds, alerts: c.alerts, bar: c.bar },
    stores: []
  }, null).snapshot
}

// The status() read API for scripts: the snapshot's stores, in config
// order (buildSnapshot adds them in that order).
export function statusSummary(snapshot, version) {
  const list = []
  const domains = Object.keys(snapshot.stores)
  for (let i = 0; i < domains.length; i++) {
    const s = snapshot.stores[domains[i]]
    const t = s.sales.today
    list.push({
      domain: s.domain, label: s.label, salesAccess: s.salesAccess, salesStatus: s.sales.status,
      error: s.sales.error ? { code: s.sales.error.code, message: s.sales.error.message } : null,
      currency: s.currency || null,
      today: { sales: t ? t.sales : null, orders: t ? t.orders : null, fetchedAt: s.sales.fetchedAt.today || null },
      trend: t && t.baseline ? trend(t.sales, t.baseline.sales) : null
    })
  }
  return { ok: true, version: version, cli: snapshot.cli, account: snapshot.account, pins: snapshot.pins, stores: list }
}
