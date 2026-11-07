// The QML engine's JS subset (tests/js/js_subset.json) over js/*.mjs, the
// service's QML, the views, the bar widget and the QML smokes, plus the Node-only checks on the JS
// modules and the model: arrow-function signal handlers, pure modules, no
// dead exports, URL opening only behind isSafeOpenUrl, one Process owner
// and the argv flags the model passes. Cross-file rules (deadlines from
// Shop::TIMING, the IPC surface, property names, atomic writes, the pins)
// live in tests/ruby/test_source_contracts.rb; the Os.plain round trip
// through a var signal is checked at runtime by tests/qml/js_modules_smoke.qml.
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, "..", "..")
const read = rel => fs.readFileSync(path.join(ROOT, rel), "utf8")
const listDir = (dir, ext) => fs.existsSync(path.join(ROOT, dir)) ? fs.readdirSync(path.join(ROOT, dir)).filter(f => f.endsWith(ext)).map(f => dir + "/" + f) : []
// Comments removed (block comments keep their newlines).
const strip = src => src.replace(/\/\*[\s\S]*?\*\//g, c => c.replace(/[^\n]/g, "")).replace(/(^|[^:\\])\/\/.*$/gm, "$1")

const jsFiles = listDir("js", ".mjs")
const modelFiles = listDir("model", ".qml")
const qmlFiles = ["Service.qml"].concat(modelFiles)
const smokeFiles = listDir("tests/qml", ".qml")
assert(jsFiles.length >= 10, "js/*.mjs present")
assert(modelFiles.length >= 10, "model/*.qml present")
// Every QML file: the service's, the views and the bar widget.
const guardFiles = qmlFiles.concat(listDir("ui", ".qml"), ["BarWidget.qml"])
assert(guardFiles.length > qmlFiles.length + 10, "ui/*.qml and BarWidget.qml are scanned")

// The subset: every pattern in js_subset.json is forbidden in every file.
const rules = JSON.parse(fs.readFileSync(path.join(HERE, "js_subset.json"), "utf8"))
assert(Array.isArray(rules) && rules.length > 10, "js_subset.json is a list of {pattern, note}")
for (const f of jsFiles.concat(guardFiles, smokeFiles)) {
  const src = strip(read(f))
  for (const rule of rules) {
    assert(typeof rule.pattern === "string" && typeof rule.note === "string", "rule shape")
    const m = new RegExp(rule.pattern).exec(src)
    assert(!m, f + ": the QML engine's JS subset forbids " + rule.note + " (" + (m ? m[0] : "") + ")")
  }
}

// Every signal handler with parameters is an arrow function (Qt 6.12
// injects no signal parameters into a plain handler block).
for (const f of qmlFiles) {
  const src = strip(read(f))
  for (const h of ["onExited", "onRead", "onLoadFailed", "onSaveFailed", "onFinished", "onEvent", "onEnded", "onFetched", "onSessionKnown", "onJobFinished", "onLine"]) {
    const re = new RegExp("\\b" + h + ":\\s*([^\\n]*)", "g")
    let m
    while ((m = re.exec(src)) !== null) assert(/^\([^)]*\)\s*=>/.test(m[1]), f + ": " + h + " must be an arrow function")
  }
}

// Only the helpers spawn processes, through the one HelperProcess; URLs
// open in exactly two places (the preview's auto-open, the panel's
// openUrl), each call right behind its own isSafeOpenUrl check, in every
// QML file (guardFiles).
const OPENERS = { "model/Previews.qml": 1, "ui/ShopPanel.qml": 1 }
for (const f of guardFiles) {
  const src = strip(read(f))
  if (f !== "model/HelperProcess.qml") assert(!/\bProcess\s*\{/.test(src), f + ": only HelperProcess owns a Process")
  const lines = src.split("\n")
  let calls = 0
  for (let i = 0; i < lines.length; i++) {
    if (!/openUrlExternally/.test(lines[i])) continue
    calls++
    const before = lines.slice(Math.max(0, i - 4), i + 1).join("\n")
    assert(/Urls\.isSafeOpenUrl\(/.test(before), f + ":" + (i + 1) + ": openUrlExternally must sit right behind an isSafeOpenUrl check")
  }
  assert.equal(calls, OPENERS[f] || 0, f + ": openUrlExternally call sites")
  // The TERM -> KILL graces live in HelperProcess only (no pass-through
  // copy of 5000 / 8000 elsewhere).
  if (f !== "model/HelperProcess.qml") assert(!/\b(?:killGrace|stopGrace)\b/.test(src), f + ": killGrace/stopGrace are set only in model/HelperProcess.qml")
}

// The argv flags the model passes (single-argument form, built from the
// job's own fields).
assert(read("model/SalesScheduler.qml").includes('"--range=" + job.range'), "fetch-sales takes --range")
assert(read("model/ThemeInfo.qml").includes('"--folder=" + folder'), "inspect-folder takes --folder")
const jobs = read("js/themejob.mjs")
assert(jobs.includes('"--folder=" + o.folder') && jobs.includes('"--target=" + o.target') && jobs.includes('"--backup=" + o.backupId'), "push/pull/restore flags")
assert(read("model/Previews.qml").includes('"--folder=" + folder'), "preview-theme takes --folder")

// The model never imports ui/ and the js modules never import QML.
for (const f of qmlFiles) assert(!/import\s+"\.\.?\/ui|import\s+"ui\//.test(read(f)), f + ": the model never imports ui/")
for (const f of jsFiles) {
  const src = strip(read(f))
  assert(!/\bQt\.|\bQuickshell\b|console\.log/.test(src), f + ": pure module")
  for (const m of src.match(/from "\.\/[a-z]+\.mjs"/g) || []) assert(jsFiles.includes("js/" + m.slice(8, -1)), f + " imports " + m)
}
// Only the exports the code and tests use (no dead exports).
const everything = jsFiles.concat(qmlFiles, smokeFiles, listDir("tests/js", ".mjs"), listDir("ui", ".qml"), ["BarWidget.qml"].filter(f => fs.existsSync(path.join(ROOT, f)))).map(read).join("\n")
for (const f of jsFiles) {
  const names = (strip(read(f)).match(/^export (?:function|const) ([A-Za-z_]\w*)/gm) || []).map(s => s.split(" ").pop())
  for (const n of names) {
    const uses = (everything.match(new RegExp("\\b" + n + "\\b", "g")) || []).length
    assert(uses > 1, f + " exports " + n + " which nothing uses")
  }
}
