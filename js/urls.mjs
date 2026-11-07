// URL building and the allowlist every Qt.openUrlExternally call goes through.
import { DOMAIN_RE } from "./config.mjs"
import { EPOCH_RE } from "./themes.mjs"

// Where Shop keeps its files, relative to $HOME (Settings > About shows
// them as "~" + REL).
export const CONFIG_REL = "/.config/shop/config.json"
export const STATE_REL = "/.local/state/shop"

const EXTRA_BAD_RE = /[\s\u0000-\u001f\u007f"'<>\\`]/

export function adminUrl(domain) {
  const d = String(domain == null ? "" : domain)
  if (!DOMAIN_RE.test(d)) return ""
  return "https://" + d + "/admin"
}

// "file://" + the user's config.json: the banner's "Open file" action and
// Settings > About > Config > Open.
export function configFileUrl(home) {
  const h = cleanHome(home)
  return h === null ? "" : "file://" + h + CONFIG_REL
}

// "file://" + Shop's state folder (backups, cache): Settings > About >
// State > Open.
export function stateDirUrl(home) {
  const h = cleanHome(home)
  return h === null ? "" : "file://" + h + STATE_REL
}

function cleanHome(home) {
  const h = String(home == null ? "" : home)
  if (!/^\/[^\s\u0000-\u001f]*$/.test(h) || h.indexOf("/..") !== -1 || h.indexOf("/./") !== -1) return null
  return h.replace(/\/+$/, "")
}

// Only five shapes open:
//   https://<domain>/admin, optionally followed by /path, ?query or #fragment
//   http://127.0.0.1:<1024-65535>/..., the local preview server
//   file://<home>/.config/shop/config.json, exactly (no domain needed)
//   file://<home>/.local/state/shop, exactly (no domain needed)
//   file://<home>/.local/state/shop/backups/<domain>/local/<10 digits>, exactly
export function isSafeOpenUrl(url, domain, home) {
  if (typeof url !== "string" || url.length === 0 || url.length > 2048) return false
  if (EXTRA_BAD_RE.test(url)) return false
  const d = String(domain == null ? "" : domain)

  if (url.startsWith("https://")) {
    if (!DOMAIN_RE.test(d)) return false
    const prefix = "https://" + d + "/admin"
    if (!url.startsWith(prefix)) return false
    const rest = url.substring(prefix.length)
    return rest === "" || /^[/?#]/.test(rest)
  }

  if (url.startsWith("http://")) {
    const m = /^http:\/\/127\.0\.0\.1:(\d{4,5})(\/[^@]*)?$/.exec(url)
    if (!m) return false
    const port = parseInt(m[1], 10)
    return port >= 1024 && port <= 65535 && String(port) === m[1]
  }

  if (url.startsWith("file://")) {
    const h = cleanHome(home)
    if (h === null) return false
    if (url === "file://" + h + CONFIG_REL) return true
    if (url === "file://" + h + STATE_REL) return true
    if (!DOMAIN_RE.test(d)) return false
    const base = "file://" + h + STATE_REL + "/backups/" + d + "/local/"
    if (!url.startsWith(base)) return false
    return EPOCH_RE.test(url.substring(base.length))
  }

  return false
}
