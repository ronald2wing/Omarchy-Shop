// js/timing.mjs: the QML deadlines and caps per helper. That each row
// equals Shop::TIMING is tests/ruby/test_source_contracts.rb's check.
import assert from "node:assert/strict"
import * as T from "../../js/timing.mjs"

assert.equal(T.deadlineMs("check-account"), 25000, "H + 5 s")
assert.equal(T.cap("check-account"), 65536)
assert.equal(T.deadlineMs("fetch-sales", "today"), 30000)
assert.equal(T.deadlineMs("fetch-sales", "history"), 50000)
assert.equal(T.cap("fetch-sales", "yesterday"), 2 * 1024 * 1024)
assert.equal(T.deadlineMs("fetch-sales"), 0, "fetch-sales needs its range")
assert.equal(T.deadlineMs("preview-theme"), 0, "the preview stream has no deadline")
assert.equal(T.cap("preview-theme"), 4096, "its line cap")
assert.equal(T.deadlineMs("nope"), 0)
assert.equal(T.cap("nope"), 0, "an unknown helper fails closed on any output")
assert.equal(T.cap("toString"), 0, "no prototype keys")
for (const name of Object.keys(T.HELPERS)) {
  const r = T.HELPERS[name]
  assert(Number.isInteger(r.deadlineMs) && r.deadlineMs >= 0 && Number.isInteger(r.cap) && r.cap > 0, name)
}
