// The QML engine's JS subset: every pattern in tests/js/js_subset.json is
// forbidden in js/*.mjs, the service's QML, the model, the views, the bar
// widget and the QML smokes (CONTRIBUTING "JavaScript subset"). The other
// source rules over QML and JS live in tests/ruby/contracts/test_qml.rb,
// dead exports in test_exports.mjs; the Os.plain round trip through a var
// signal is checked at runtime by tests/qml/js_modules_smoke.qml.
import assert from "node:assert/strict"
import { listDir, read, strip } from "./support.mjs"

const jsFiles = listDir("js", ".mjs")
const qmlFiles = ["Service.qml", "BarWidget.qml"].concat(listDir("model", ".qml"), listDir("ui", ".qml"))
const smokeFiles = listDir("tests/qml", ".qml")
assert(jsFiles.length >= 10, "js/*.mjs present")
assert(qmlFiles.length > 30, "Service.qml, BarWidget.qml, model/*.qml and ui/*.qml present")
assert(smokeFiles.length >= 10, "tests/qml/*.qml present")

const rules = JSON.parse(read("tests/js/js_subset.json"))
assert(Array.isArray(rules) && rules.length > 10, "js_subset.json is a list of {pattern, note}")
for (const f of jsFiles.concat(qmlFiles, smokeFiles)) {
  const src = strip(read(f))
  for (const rule of rules) {
    assert(typeof rule.pattern === "string" && typeof rule.note === "string", "rule shape")
    const m = new RegExp(rule.pattern).exec(src)
    assert(!m, f + ": the QML engine's JS subset forbids " + rule.note + " (" + (m ? m[0] : "") + ")")
  }
}
