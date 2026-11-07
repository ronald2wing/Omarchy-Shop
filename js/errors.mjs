// Error objects: the one normaliser for a helper's error, and the
// service-level refusals, one builder per code, so Service.qml, the models
// and config.mjs never repeat a literal. Messages are for scripts reading
// the IPC JSON; the UI renders `error.<code>` from Copy.
import { isNum } from "./format.mjs"

// The bare { code, message, ...extra } object (what config.mjs returns
// beside its config and what the stores keep as configError and the like).
export function error(code, message, extra) {
  const out = { code: code, message: message || "" }
  Object.assign(out, extra)
  return out
}

// A helper's error as Shop keeps it: { code, message } plus reason,
// retryAfter, missing ("node" | "cli") when present, and range
// (today|history|yesterday) when given (helpers clean and cap message and
// reason). A missing or empty code reads as cli_failed.
export function fromHelper(e, range) {
  const src = e && typeof e === "object" ? e : {}
  const code = typeof src.code === "string" && src.code !== "" ? src.code : "cli_failed"
  const out = { code: code, message: typeof src.message === "string" ? src.message : "" }
  if (typeof src.reason === "string") out.reason = src.reason
  if (isNum(src.retryAfter)) out.retryAfter = src.retryAfter
  if (src.missing === "node" || src.missing === "cli") out.missing = src.missing
  if (range) out.range = range
  return out
}

// Shopify is limiting requests (rate_limited, always with retryAfter): a
// state that retries by itself, never a failure shown in red.
export function isRateLimit(code) {
  return code === "rate_limited"
}

// ---- the success results of the service API ---------------------------------

// { ok: true }: done.
export function ok() {
  return { ok: true }
}

// { ok: true, started: true }: the work was started; its outcome arrives
// in the snapshot.
export function started() {
  return { ok: true, started: true }
}

// The refusal result: { ok: false, error }.
function fail(code, message, extra) {
  return { ok: false, error: error(code, message, extra) }
}

export function unknownStore() {
  return fail("unknown_store", "That store isn't in Shop")
}

// A store lookup while config.json can't be used (configError: the
// ConfigStore's {code: config_invalid|config_unsupported, non-empty
// message}): the store list is unknown, not empty.
export function configInvalid(configError) {
  return fail(configError.code, configError.message)
}

// missing: "node" | "cli" | null
export function cliMissing(missing) {
  return fail("cli_missing", "Shopify CLI isn't installed", missing ? { missing: missing } : null)
}

export function cliChecking() {
  return fail("cli_checking", "Still checking the Shopify CLI")
}

export function cliInstalling() {
  return fail("cli_installing", "The Shopify CLI is installing")
}

// The work holding one store: action "push" | "pull" | "restore" (a theme
// job), "preview" or "grant" (a sales-access grant); blocked (optional):
// the push, pull or restore a starting or ready preview is in the way of
// (stop it first).
export function storeBusy(action, blocked) {
  const extra = { action: action }
  if (blocked) extra.blocked = blocked
  return fail("store_busy", "Another action is running for this store", extra)
}

// Sign-in, sign-out or Reset config while a theme job or preview (what
// "job" | "preview") runs on any store, or Reset config during a grant
// ("access"): the same store_busy code, marked `anyStore` (the work may
// be on any store, so it names no action) so the panel names the wait.
export function anyStoreBusy(what) {
  return fail("store_busy", "Wait for the running theme action to finish", { what: what, anyStore: true })
}

export function accountBusy(message) {
  return fail("account_busy", message || "Shop is busy with your Shopify account")
}

export function confirmOpen() {
  return fail("confirm_open", "Answer the open confirmation first")
}

export function configBusy(message) {
  return fail("config_busy", message)
}

export function configUnavailable(message) {
  return fail("config_unavailable", message || "Shop is still loading")
}

export function configWriteFailed(message) {
  return fail("config_write_failed", message)
}

export function recentlyDeclined() {
  return fail("recently_declined", "You just declined this; try again in a moment")
}

export function noPending() {
  return fail("no_pending", "That confirmation expired")
}

// A refresh within two seconds of the last one.
export function rateLimitedLocally() {
  return fail("rate_limited_locally", "Just refreshed")
}

export function noThemeFolder() {
  return fail("no_theme_folder", "Link a theme folder first")
}

// The last inspection of the store's theme folder rules out `action`
// (push | pull | preview), as the helper's own folder check would: state is
// Themes.folderState's missing, unsafe, notTheme, error or (push, preview)
// empty.
export function folderUnusable(action, state) {
  return fail("folder_unusable", "The theme folder can't be used for this " + action, { action: action, state: state })
}

// A store whose sales fetches wait for a new grant (the scheduler
// suspended it on sales_access_required).
export function salesAccessRequired() {
  return fail("sales_access_required", "Grant sales access to this store first")
}

export function liveNotAllowed() {
  return fail("live_not_allowed", "Changes to the live theme are off for this store")
}

// A backup id that is not <epoch>-<themeId> (refused before spawning).
export function invalidBackupId() {
  return fail("invalid_argument", "Not a backup id")
}

export function invalidDomain() {
  return fail("invalid_domain", "Enter a .myshopify.com address")
}

export function duplicateStore() {
  return fail("duplicate_store", "That store is already added")
}

// max: config.mjs's MAX_STORES (config.mjs owns the cap; passing it keeps this
// module free of a config import).
export function tooManyStores(max) {
  return fail("too_many_stores", "Shop keeps at most " + max + " stores")
}

// message: what was wrong with the patch ("patch must be an object", ...).
export function invalidPatch(message) {
  return fail("invalid_patch", message)
}

// ---- HelperProcess: a helper that ended without a usable result line -------

// No JSON result, a result without an error code, or ok with a non-zero exit.
export function badResponse(message) {
  return fail("bad_response", message)
}

// The QML deadline (the helper's own plus 5 s) passed and it was killed.
export function timeout(message) {
  return fail("timeout", message)
}

// Killed by a signal before it printed a result.
export function terminated(message) {
  return fail("terminated", message)
}

// More stdout than the helper's cap.
export function outputTooLarge(message) {
  return fail("output_too_large", message)
}

// The process never started.
export function failedToStart(message) {
  return fail("failed_to_start", message)
}

// ---- ConfigStore ----

// A config change whose transform threw (a bug, not a refused patch:
// refusals come back as the transform's {error}). The panel shows
// error.default with the message.
export function internalError(message) {
  return fail("internal_error", message)
}
