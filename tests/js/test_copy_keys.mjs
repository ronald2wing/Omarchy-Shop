// The copy deck (js/copy.mjs STRINGS) against its readers: every key a
// js/*.mjs module or a QML file names exists, every key built at run time
// ("job.noun." + action) resolves for each value the code can produce, and
// every key is read somewhere. t() renders a missing key as the key itself,
// so a renamed key would otherwise pass every test and show raw.
import assert from "node:assert/strict"
import { STRINGS } from "../../js/copy.mjs"
import { KPI_SLOTS, KPI_TIPS, PERIOD_IDS } from "../../js/metrics.mjs"
import { listDir, read as readSource, strip } from "./support.mjs"

const keys = new Set(Object.keys(STRINGS))
assert(keys.size > 300, "Copy keys: " + keys.size)
const namespaces = new Set([...keys].map(k => k.split(".")[0]))

// One grammar: `<area>.<thing>[.<variant>]`, lowerCamel segments (error
// codes and folder reasons keep their snake_case), a variant always its own
// segment.
for (const k of keys) {
  const parts = k.split(".")
  assert(parts.length >= 2 && parts.length <= 4, "key shape: " + k)
  const snake = parts[0] === "error" || (parts[0] === "theme" && parts[1] === "unsafe")
  for (const p of parts) assert(snake ? /^[a-z][a-zA-Z0-9_]*$/.test(p) : /^[a-z][a-zA-Z0-9]*$/.test(p), "key segment " + p + " in " + k)
  assert(!/.(One|NoFigures)$/.test(parts[parts.length - 1]), "a variant is a dotted segment, not a camel suffix: " + k)
}
// A camel segment never extends a sibling key or prefix: beside
// theme.preview, a preview state is the variant theme.preview.starting
// (never theme.previewStarting); beside settings.cli, its ready line is
// settings.cli.ready.
const prefixes = new Set()
for (const k of keys) {
  const parts = k.split(".")
  for (let i = 1; i < parts.length; i++) prefixes.add(parts.slice(0, i).join("."))
}
for (const k of keys) {
  const parts = k.split(".")
  for (let i = 1; i < parts.length; i++) {
    const humps = parts[i].split(/(?=[A-Z])/)
    for (let n = 1; n < humps.length; n++) {
      const stem = parts.slice(0, i).concat([humps.slice(0, n).join("")]).join(".")
      assert(!keys.has(stem) && !prefixes.has(stem), "a camel segment extends " + stem + ": make it a dotted part (" + k + ")")
    }
  }
}

// Keys built at run time: prefix -> the suffixes the code can produce.
const contributing = readSource("CONTRIBUTING.md")
const reasons = [...contributing.match(/`error\.reason` is one of ([^|]*)\|/)[1].matchAll(/`([a-z_]+)`/g)].map(m => m[1])
assert(reasons.length > 10, "unsafe_folder reasons read from CONTRIBUTING: " + reasons.length)
const errorCodes = [...contributing.matchAll(/^\| `([a-z_]+)` \|/gm)].map(m => m[1]).filter(c => c !== "consent_required")
assert(errorCodes.length > 20, "error codes read from CONTRIBUTING: " + errorCodes.length)
// ...and every service-level code js/results.mjs and js/config.mjs build.
for (const f of ["js/results.mjs", "js/config.mjs"])
  for (const m of readSource(f).matchAll(/\b(?:fail|error)\("([a-z_]+)"/g))
    if (!errorCodes.includes(m[1])) errorCodes.push(m[1])
const built = {
  "job.": ["push", "pull", "restore"],
  "job.noun.": ["push", "pull", "restore", "preview", "grant"],
  // themejob.mjs resultText: the stopped-before line and the failed line's title.
  "job.title.": ["push", "pull", "restore"],
  "result.stopped.none.": ["push", "pull", "restore"],
  "kpi.": KPI_SLOTS,
  "kpi.tip.": KPI_TIPS,
  "period.": PERIOD_IDS,
  "caption.": PERIOD_IDS,
  // copy.mjs baselineText: every period but 12m (which has no comparison).
  "trend.baseline.": PERIOD_IDS.filter(id => id !== "last12m"),
  "count.": ["orders", "orders.one", "stores", "stores.one", "sessions", "sessions.one", "files", "files.one"],
  "theme.unsafe.": reasons,
  // errorOf: every helper code (the table in CONTRIBUTING) has its line.
  "error.": errorCodes,
  // confirm.mjs: the live push dialog's variant.
  "confirm.push.title": ["", ".live"],
  "confirm.push.body": ["", ".live"],
  "confirm.push.ok": ["", ".live"]
}
for (const prefix of Object.keys(built))
  for (const suffix of built[prefix]) assert(keys.has(prefix + suffix), "Copy key " + prefix + suffix + " exists")

const read = rel => strip(readSource(rel))
const jsFiles = listDir("js", ".mjs").filter(f => f !== "js/copy.mjs").sort()
const qmlFiles = ["BarWidget.qml", "Service.qml"].concat(listDir("ui", ".qml"), listDir("model", ".qml"))
const copySrc = read("js/copy.mjs").replace(/export const STRINGS = \{[\s\S]*?\n\}\n/, "")

const used = new Set()
let checked = 0
for (const rel of jsFiles.concat(qmlFiles, ["js/copy.mjs"])) {
  const src = rel === "js/copy.mjs" ? copySrc : read(rel)
  // Any key-shaped string literal in a Copy namespace: covers t("k"),
  // t(cond ? "a" : "b"), keymap labels and the prefixes of built keys alike.
  for (const m of src.matchAll(/"([a-z][a-zA-Z0-9_]*\.[a-zA-Z0-9_.]*)"/g)) {
    const lit = m[1]
    if (!namespaces.has(lit.split(".")[0])) continue
    if (/\.(mjs|qml|json|md|com)$/.test(lit)) continue
    checked++
    if (Object.prototype.hasOwnProperty.call(built, lit)) { for (const sfx of built[lit]) used.add(lit + sfx); continue }
    assert(!lit.endsWith("."), rel + ": built Copy key prefix \"" + lit + "\" is listed in this test")
    assert(keys.has(lit), rel + ": Copy key " + lit + " exists in js/copy.mjs")
    used.add(lit)
  }
  // Every literal t("key") exists, whatever its namespace (the scan above
  // skips a literal outside the deck's namespaces, such as a typo'd one).
  for (const m of src.matchAll(/\bt\(\s*"([a-zA-Z0-9_.]+)"\s*[,)]/g)) {
    assert(keys.has(m[1]), rel + ": Copy key " + m[1] + " exists in js/copy.mjs")
    checked++
  }
  // A t("…" + …) call whose prefix is not in `built` would slip past.
  for (const m of src.matchAll(/\bt\(\s*"([^"]*)"\s*\+/g))
    assert(Object.prototype.hasOwnProperty.call(built, m[1]), rel + ": t(\"" + m[1] + "\" + …) builds a key; list its suffixes in this test")
}
assert(checked > 150, "key literals checked: " + checked)

// No dead strings: every key is read by a literal or a built family.
const unused = [...keys].filter(k => !used.has(k))
assert.deepEqual(unused, [], "Copy keys nothing reads")
