// Shared text scrubbing and short labels. Mirrors Ruby Text.clean
// ([\p{Cc}\p{Cf}\p{Zl}\p{Zp}] except U+200D): C0/C1 controls, zero-width,
// bidi formatting (embeddings, overrides, isolates, marks) and the other
// format characters, astral ones included, plus the line and paragraph
// separators (Qt breaks lines on them even in PlainText). U+200D (ZWJ)
// stays: it joins emoji sequences. tests/js/test_text.mjs checks the set
// against a dump of Ruby's (tests/fixtures/control-codepoints.json).

function ch(code) {
  return String.fromCharCode(code)
}

// Regex escapes, not raw characters (a literal U+2028 inside a regex
// literal is a syntax error). The QML engine's subset has no \p{} and no
// u flag, so astral format characters match as surrogate pairs.
const CONTROL_BMP = "[\\x00-\\x1f\\x7f-\\x9f\\xad\\u0600-\\u0605\\u061c\\u06dd\\u070f\\u0890\\u0891\\u08e2\\u180e"
  + "\\u200b\\u200c\\u200e\\u200f\\u2028-\\u202e\\u2060-\\u2064\\u2066-\\u206f\\ufeff\\ufff9-\\ufffb]"
const CONTROL_ASTRAL = "\\ud804[\\udcbd\\udccd]|\\ud80d[\\udc30-\\udc3f]|\\ud82f[\\udca0-\\udca3]|\\ud834[\\udd73-\\udd7a]|\\udb40[\\udc01\\udc20-\\udc7f]"
const CONTROL_SRC = "(?:" + CONTROL_BMP + "|" + CONTROL_ASTRAL + ")"
export const CONTROL_RE = new RegExp(CONTROL_SRC)
const CONTROL_ALL_RE = new RegExp(CONTROL_SRC, "g")
const COMBINING_RE = new RegExp("[" + ch(0x300) + "-" + ch(0x36f) + "]", "g")

// Controls replaced by a space, trimmed and cut at `max` characters
// (required). null and undefined read as "".
export function scrubControl(s, max) {
  const str = s == null ? "" : String(s)
  return str.replace(CONTROL_ALL_RE, " ").trim().substring(0, max)
}

function asciiWords(label) {
  let s = scrubControl(label, 80)
  if (typeof s.normalize === "function") s = s.normalize("NFD")
  return s.replace(COMBINING_RE, "").replace(/[^A-Za-z0-9 ]+/g, " ").trim().split(/\s+/).filter(w => w.length > 0)
}

// The two-letter code a crowded bar shows: initials of the first two words
// ("Acme Apparel" -> "AA"), else the first two letters ("Gamma" -> "GA"),
// uppercased and ASCII-folded ("Épicerie Zoé" -> "EZ"). `taken` (an array
// of codes already in use) turns a collision into "AA2", "AA3", ...
function shortCode(label, taken) {
  const words = asciiWords(label)
  let code
  if (words.length >= 2) code = words[0].charAt(0) + words[1].charAt(0)
  else if (words.length === 1) code = words[0].substring(0, 2)
  else code = scrubControl(label, 2)
  code = code.toUpperCase()
  if (code === "") code = "?"
  if (!taken.includes(code)) return code
  for (let n = 2; n < 100; n++) if (!taken.includes(code + n)) return code + n
  return code
}

// A sentence used as a clause inside another ("{message}. Check …", a
// banner body): without its final full stops and trailing spaces, so the
// frame's own punctuation never doubles it.
export function asClause(text) {
  return String(text == null ? "" : text).replace(/[.\s]+$/, "")
}

// Codes for a list of labels, in order, collisions suffixed.
export function shortCodes(labels) {
  const out = []
  for (let i = 0; i < labels.length; i++) out.push(shortCode(labels[i], out))
  return out
}

// "acme.myshopify.com" -> "acme": the label a store starts with.
export function subdomainLabel(domain) {
  const d = String(domain == null ? "" : domain)
  const dot = d.indexOf(".")
  return dot === -1 ? d : d.substring(0, dot)
}

// "{n} new orders · {label}" with vars {n, label}, in one pass: a value is
// inserted as is and never searched again, so a remote string holding
// "{label}" stays literal whatever the key order. A placeholder with no
// such key stays as written; null and undefined read as "".
export function fillTemplate(template, vars) {
  const s = String(template == null ? "" : template)
  if (!vars) return s
  return s.replace(/\{([A-Za-z0-9_]+)\}/g, function (m, k) {
    if (!Object.prototype.hasOwnProperty.call(vars, k)) return m
    const v = vars[k]
    return v === undefined || v === null ? "" : String(v)
  })
}
