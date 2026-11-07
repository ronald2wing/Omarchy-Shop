// Config v2 (~/.config/shop/config.json): parse, validate, patch, serialize.
// Pure functions; every mutation returns a new config and never touches the
// input. Files without "version": 2 are refused, never migrated.
import * as Errors from "./errors.mjs"
import { isNum } from "./format.mjs"
import { plain } from "./os.mjs"
import { CONTROL_RE, scrubControl, subdomainLabel } from "./text.mjs"

export const DOMAIN_RE = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.myshopify\.com$/
const THEME_TARGET_RE = /^(?:live|[1-9]\d{0,19})$/
// Mirrors Ruby Validate::TZ: up to four IANA path segments of 64 chars.
export const TIMEZONE_RE = /^[A-Za-z0-9_+\-]{1,64}(?:\/[A-Za-z0-9_+\-]{1,64}){0,3}$/
const MAX_STORES = 50

// The bar draws at most this many store pills before it folds them into
// one total; a new store shows in the bar only while fewer are shown.
export const BAR_PILLS = 5
// From this many pills on, each one shortens its label to the store's
// initials (BarWidget's pill codes) so they fit beside the shell's own.
export const BAR_INITIALS = 4

const POLL_MIN = 30
const POLL_MAX = 3600
const POLL_DEFAULT = 60
const BAR_DISPLAYS = ["stores", "total", "icon"]
const KNOWN_TOP = ["version", "pollSeconds", "alerts", "bar", "stores"]

// config.mjs returns bare error objects beside the config; the service
// wraps them. invalid_patch carries what was wrong with the patch.
function patchError(message) {
  return Errors.invalidPatch(message).error
}

// A refused mutation: the config unchanged, and the bare error.
function refused(config, error) {
  return { config: config, error: error }
}

function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

// A patch as the panel sends it: the text of a JSON object, at most 8 KiB.
// -> { value } or { error } (invalid_patch).
export function parsePatch(json) {
  if (typeof json !== "string" || json.length > 8192) return { error: patchError("patch must be a JSON string") }
  try {
    const v = JSON.parse(json)
    if (!isPlainObject(v)) return { error: patchError("patch must be a JSON object") }
    return { value: v }
  } catch (e) {
    return { error: patchError("patch is not valid JSON") }
  }
}

// "acme", "Acme.myshopify.com", "https://acme.myshopify.com/admin/themes"
// -> "acme.myshopify.com"; anything else -> null.
export function normalizeDomain(input) {
  if (typeof input !== "string") return null
  let s = input.trim().toLowerCase()
  if (s.length === 0 || s.length > 300) return null
  if (s.startsWith("https://")) s = s.substring(8)
  else if (s.startsWith("http://")) s = s.substring(7)
  const slash = s.indexOf("/")
  if (slash !== -1) {
    const path = s.substring(slash)
    if (path !== "/" && path !== "/admin" && !path.startsWith("/admin/")) return null
    s = s.substring(0, slash)
  }
  if (/^[a-z0-9-]+$/.test(s)) s = s + ".myshopify.com"
  return DOMAIN_RE.test(s) ? s : null
}

export function cleanLabel(input) {
  if (typeof input !== "string") return null
  const s = input.trim().replace(/ {2,}/g, " ")
  if (s.length < 1 || s.length > 80) return null
  if (CONTROL_RE.test(s)) return null
  return s
}

// A label from a remote source (store names from discovery and access
// grants): control characters scrubbed and cut to 80 before cleanLabel.
export function cleanRemoteLabel(raw) {
  return cleanLabel(scrubControl(raw, 80))
}

// The label a new store gets: the given one (as cleanLabel keeps it), else
// the name discovery found for it (discovered: [{domain, name}]), else its
// subdomain.
function newStoreLabel(domain, label, discovered) {
  const given = label === undefined || label === null ? null : cleanLabel(String(label))
  if (given !== null) return given
  const rows = discovered || []
  for (let i = 0; i < rows.length; i++) if (rows[i].domain === domain && rows[i].name) return rows[i].name
  return subdomainLabel(domain)
}

function clampPollSeconds(n) {
  const v = typeof n === "number" ? n : parseFloat(n)
  if (!isFinite(v)) return POLL_DEFAULT
  return Math.min(POLL_MAX, Math.max(POLL_MIN, Math.round(v)))
}

export function emptyConfig() {
  return { version: 2, pollSeconds: POLL_DEFAULT, alerts: { notify: true, sound: true }, bar: { display: "stores" }, stores: [] }
}

function isAbsoluteFolder(f) {
  return f === "" || (f.charAt(0) === "/" && !CONTROL_RE.test(f) && f.length <= 4096)
}

function normalizeTheme(t) {
  if (t === null || t === undefined) return { theme: null }
  if (!isPlainObject(t)) return { problem: "invalid theme" }
  const folder = t.folder === undefined || t.folder === null ? "" : t.folder
  if (typeof folder !== "string" || !isAbsoluteFolder(folder)) return { problem: "invalid theme folder" }
  const target = t.target === undefined || t.target === null ? "live" : String(t.target)
  if (!THEME_TARGET_RE.test(target)) return { problem: "invalid theme target" }
  if (t.allowLive !== undefined && typeof t.allowLive !== "boolean") return { problem: "invalid allowLive" }
  return { theme: { folder: folder, target: target, allowLive: t.allowLive === true } }
}

// One raw store entry -> { store } or { problem, domain }.
function normalizeStore(raw, seen) {
  if (!isPlainObject(raw)) return { problem: "not an object", domain: null }
  if (typeof raw.domain !== "string" || raw.domain.length === 0) return { problem: "missing domain", domain: null }
  const domain = normalizeDomain(raw.domain)
  if (domain === null || domain !== raw.domain) return { problem: "invalid domain", domain: null }
  if (seen[domain]) return { problem: "duplicate domain", domain: domain }
  const label = cleanLabel(raw.label)
  if (label === null) return { problem: "invalid label", domain: domain }
  if (raw.showInBar !== undefined && typeof raw.showInBar !== "boolean") return { problem: "invalid showInBar", domain: domain }
  const t = normalizeTheme(raw.theme)
  if (t.problem) return { problem: t.problem, domain: domain }
  return { store: { domain: domain, label: label, showInBar: raw.showInBar !== false, theme: t.theme } }
}

function parseRaw(raw) {
  if (raw === null || raw === undefined) return { value: null }
  if (typeof raw !== "string") return { value: raw }
  // A present but blank file is an editor mid-save (truncate, then write)
  // or a mistake; never the same as a missing file.
  if (raw.trim().length === 0) return { error: Errors.error("config_invalid", "config.json is empty") }
  try { return { value: JSON.parse(raw) } } catch (e) { return { error: Errors.error("config_invalid", "config.json is not valid JSON") } }
}

// raw: the file text (or a parsed object, or null for a missing file).
// -> { config, invalidStores, error }. On error, config is an empty v2
// config that the caller must not write over the file.
export function normalizeConfig(raw) {
  const parsed = parseRaw(raw)
  if (parsed.error) return { config: emptyConfig(), invalidStores: [], error: parsed.error }
  const v = parsed.value
  if (v === null) return { config: emptyConfig(), invalidStores: [], error: null }
  if (!isPlainObject(v)) return { config: emptyConfig(), invalidStores: [], error: Errors.error("config_invalid", "config.json must be a JSON object") }
  if (v.version !== 2) {
    return { config: emptyConfig(), invalidStores: [], error: Errors.error("config_unsupported", "This config.json is from a different Shop version.") }
  }
  if (v.stores !== undefined && !Array.isArray(v.stores)) {
    return { config: emptyConfig(), invalidStores: [], error: Errors.error("config_invalid", "\"stores\" must be a list") }
  }
  const config = emptyConfig()
  if (v.pollSeconds !== undefined) config.pollSeconds = clampPollSeconds(v.pollSeconds)
  if (isPlainObject(v.alerts)) {
    if (typeof v.alerts.notify === "boolean") config.alerts.notify = v.alerts.notify
    if (typeof v.alerts.sound === "boolean") config.alerts.sound = v.alerts.sound
  }
  if (isPlainObject(v.bar) && BAR_DISPLAYS.includes(v.bar.display)) config.bar.display = v.bar.display
  const invalidStores = []
  const seen = Object.create(null)
  const list = v.stores || []
  for (let i = 0; i < list.length; i++) {
    const r = normalizeStore(list[i], seen)
    if (r.store) {
      seen[r.store.domain] = true
      config.stores.push(r.store)
    } else {
      invalidStores.push({ index: i, domain: r.domain, problem: r.problem })
    }
  }
  return { config: config, invalidStores: invalidStores, error: null }
}

function findIndex(config, domain) {
  for (let i = 0; i < config.stores.length; i++) if (config.stores[i].domain === domain) return i
  return -1
}

// The config entry for `domain`, or null.
export function findStore(config, domain) {
  const i = findIndex(config, domain)
  return i === -1 ? null : config.stores[i]
}

// Two store `theme` values (or null) name the same folder and target.
// allowLive is not part of the link.
export function sameThemeLink(a, b) {
  const x = a || { folder: "", target: "live" }
  const y = b || { folder: "", target: "live" }
  return x.folder === y.folder && x.target === y.target
}

// patch: { label?, showInBar?, theme? (only with allowThemeKeys) }.
export function applyStorePatch(config, domain, patch, home, opts) {
  const allowThemeKeys = !!(opts && opts.allowThemeKeys)
  const i = findIndex(config, domain)
  if (i === -1) return refused(config, Errors.unknownStore().error)
  if (!isPlainObject(patch)) return refused(config, patchError("patch must be an object"))
  const keys = Object.keys(patch)
  if (keys.length === 0) return refused(config, patchError("empty patch"))
  const next = plain(config)
  const store = next.stores[i]
  for (let k = 0; k < keys.length; k++) {
    const key = keys[k]
    const value = patch[key]
    if (key === "label") {
      const label = cleanLabel(value)
      if (label === null) return refused(config, patchError("label must be 1-80 characters"))
      store.label = label
    } else if (key === "showInBar") {
      if (typeof value !== "boolean") return refused(config, patchError("showInBar must be true or false"))
      store.showInBar = value
    } else if (key === "theme" && allowThemeKeys) {
      const r = patchTheme(store.theme, value, home)
      if (r.error) return refused(config, r.error)
      store.theme = r.theme
    } else {
      return refused(config, patchError("\"" + String(key).substring(0, 40) + "\" can't be changed here"))
    }
  }
  return { config: next, error: null }
}

function patchTheme(current, value, home) {
  if (value === null) return { theme: null }
  if (!isPlainObject(value)) return { error: patchError("theme must be an object or null") }
  const base = current ? plain(current) : { folder: "", target: "live", allowLive: false }
  const keys = Object.keys(value)
  let reset = false
  for (let k = 0; k < keys.length; k++) {
    const key = keys[k]
    const v = value[key]
    if (key === "folder") {
      if (typeof v !== "string") return { error: patchError("folder must be a path") }
      let f = v.trim()
      if (f === "~") f = String(home || "")
      else if (f.startsWith("~/")) f = String(home || "") + f.substring(1)
      if (f.length > 1) f = f.replace(/\/+$/, "")
      if (!isAbsoluteFolder(f)) return { error: patchError("folder must be an absolute path") }
      if (f !== base.folder) reset = true
      base.folder = f
    } else if (key === "target") {
      const t = String(v)
      if (!THEME_TARGET_RE.test(t)) return { error: patchError("target must be \"live\" or a theme id") }
      if (t !== base.target) reset = true
      base.target = t
    } else if (key === "allowLive") {
      if (typeof v !== "boolean") return { error: patchError("allowLive must be true or false") }
      base.allowLive = v
    } else {
      return { error: patchError("unknown theme key") }
    }
  }
  if (reset) base.allowLive = false
  return { theme: base }
}

// patch: { pollSeconds?, alerts?: { notify?, sound? }, bar?: { display? } }.
export function applySettingsPatch(config, patch) {
  if (!isPlainObject(patch) || Object.keys(patch).length === 0) return refused(config, patchError("patch must be a non-empty object"))
  const next = plain(config)
  const keys = Object.keys(patch)
  for (let k = 0; k < keys.length; k++) {
    const key = keys[k]
    const v = patch[key]
    if (key === "pollSeconds") {
      if (!isNum(v)) return refused(config, patchError("pollSeconds must be a number"))
      next.pollSeconds = clampPollSeconds(v)
    } else if (key === "alerts") {
      if (!isPlainObject(v)) return refused(config, patchError("alerts must be an object"))
      const ak = Object.keys(v)
      for (let j = 0; j < ak.length; j++) {
        if ((ak[j] !== "notify" && ak[j] !== "sound") || typeof v[ak[j]] !== "boolean") return refused(config, patchError("alerts.notify and alerts.sound take true or false"))
        next.alerts[ak[j]] = v[ak[j]]
      }
    } else if (key === "bar") {
      if (!isPlainObject(v) || Object.keys(v).length !== 1 || !BAR_DISPLAYS.includes(v.display)) return refused(config, patchError("bar.display must be stores, total or icon"))
      next.bar.display = v.display
    } else {
      return refused(config, patchError("\"" + String(key).substring(0, 40) + "\" isn't a setting"))
    }
  }
  return { config: next, error: null }
}

// -> { config, error }; on success also domain, label, showInBar, shownCount. The label is
// the given one (cleaned), else the discovered name, else the subdomain.
// shownCount is how many stores were shown before it was added. Shop keeps
// at most MAX_STORES stores.
export function addStore(config, domainInput, labelInput, discovered) {
  const domain = normalizeDomain(domainInput)
  if (domain === null) return refused(config, Errors.invalidDomain().error)
  if (findIndex(config, domain) !== -1) return refused(config, Errors.duplicateStore().error)
  if (config.stores.length >= MAX_STORES) return refused(config, Errors.tooManyStores(MAX_STORES).error)
  const label = newStoreLabel(domain, labelInput, discovered)
  const shown = config.stores.filter(s => s.showInBar).length
  const showInBar = shown < BAR_PILLS
  const next = plain(config)
  next.stores.push({ domain: domain, label: label, showInBar: showInBar, theme: null })
  return { config: next, error: null, domain: domain, label: label, showInBar: showInBar, shownCount: shown }
}

// -> { config, error } (unknown_store when it isn't there).
export function removeStore(config, domain) {
  if (findIndex(config, domain) === -1) return refused(config, Errors.unknownStore().error)
  const next = plain(config)
  next.stores = next.stores.filter(s => s.domain !== domain)
  return { config: next, error: null }
}

// -> { config, error }: the store moved to `index` (clamped; a non-number
// keeps its place), or unknown_store.
export function moveStore(config, domain, index) {
  const i = findIndex(config, domain)
  if (i === -1) return refused(config, Errors.unknownStore().error)
  const next = plain(config)
  const item = next.stores.splice(i, 1)[0]
  let to = Math.round(Number(index))
  if (!isNum(to)) to = i
  to = Math.max(0, Math.min(next.stores.length, to))
  next.stores.splice(to, 0, item)
  return { config: next, error: null }
}

// The file text for `config`: known keys first, then the original file's
// unknown top-level keys, with its invalid store entries put back at their
// original positions so a write never drops what Shop could not read.
export function serializeConfig(config, originalRaw) {
  const out = { version: 2, pollSeconds: config.pollSeconds, alerts: plain(config.alerts), bar: plain(config.bar) }
  const stores = plain(config.stores).map(s => ({ domain: s.domain, label: s.label, showInBar: s.showInBar, theme: s.theme }))
  const parsed = parseRaw(originalRaw)
  const orig = parsed.value
  if (isPlainObject(orig) && orig.version === 2) {
    if (Array.isArray(orig.stores)) {
      const r = normalizeConfig(orig)
      for (let i = 0; i < r.invalidStores.length; i++) {
        const inv = r.invalidStores[i]
        stores.splice(Math.min(inv.index, stores.length), 0, plain(orig.stores[inv.index]))
      }
    }
    out.stores = stores
    const keys = Object.keys(orig)
    for (let k = 0; k < keys.length; k++) if (!KNOWN_TOP.includes(keys[k])) out[keys[k]] = plain(orig[keys[k]])
  } else {
    out.stores = stores
  }
  return JSON.stringify(out, null, 2) + "\n"
}
