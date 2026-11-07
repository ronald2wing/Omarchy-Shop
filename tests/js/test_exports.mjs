// No dead exports in js/*.mjs: every export has a reader outside its own
// module (a call inside the module needs no export). An export whose only
// outside reader is a test is a deliberate seam, listed in TEST_SEAMS;
// anything a public function already covers is tested through that
// function instead.
import assert from "node:assert/strict"
import path from "node:path"
import { listDir, read, strip } from "./support.mjs"

const TEST_SEAMS = [
  "copy.STRINGS", "keymap.FOOTER_ROWS", "keymap.footerRows", "keymap.footerParts", "metrics.KPI_TIPS",
  "preflight.requireAccountIdle", "preflight.checkThemeAction",
  "sales.withMeta", "sales.clearRangeError", "sales.markGranted", "sales.withHistory", "sales.normalizeYesterday",
  "schedule.nextDelayMs", "schedule.storeLocalDate", "snapshot.CLI_PIN", "snapshot.NODE_PIN",
  "themejob.liveFlags", "themejob.writeStartedOf"
]

const jsFiles = listDir("js", ".mjs")
assert(jsFiles.length >= 10, "js/*.mjs present")
const productionFiles = jsFiles.concat(["Service.qml", "BarWidget.qml"], listDir("model", ".qml"), listDir("ui", ".qml"))
const testFiles = listDir("tests/qml", ".qml").concat(listDir("tests/js", ".mjs"))
const stripped = {}
for (const f of productionFiles.concat(testFiles)) stripped[f] = strip(read(f))
const usedIn = (files, name, except) => files.some(f => f !== except && new RegExp("\\b" + name + "\\b").test(stripped[f]))

const seams = []
for (const f of jsFiles) {
  const names = (stripped[f].match(/^export (?:function|const) ([A-Za-z_]\w*)/gm) || []).map(s => s.split(" ").pop())
  for (const n of names) {
    const id = path.basename(f, ".mjs") + "." + n
    if (usedIn(productionFiles, n, f)) continue
    assert(usedIn(testFiles, n, f), f + " exports " + n + ", which no other file uses (drop the export)")
    assert(TEST_SEAMS.includes(id), f + " exports " + n + " for tests alone: test it through the public function that calls it, or list " + id + " in TEST_SEAMS")
    seams.push(id)
  }
}
assert.deepEqual(TEST_SEAMS.filter(id => !seams.includes(id)), [], "TEST_SEAMS names only exports that tests alone read")
