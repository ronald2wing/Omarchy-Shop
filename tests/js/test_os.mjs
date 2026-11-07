// js/os.mjs: file URLs as paths, UTF-8 byte lengths, exit codes, plain copies.
import assert from "node:assert/strict"
import * as Os from "../../js/os.mjs"

assert.equal(Os.utf8ByteLength(""), 0)
assert.equal(Os.utf8ByteLength("abc"), 3)
assert.equal(Os.utf8ByteLength("é"), 2)
assert.equal(Os.utf8ByteLength("€"), 3)
assert.equal(Os.utf8ByteLength("💡"), 4)
assert.equal(Os.utf8ByteLength("aé€💡"), 10)
assert.equal(Os.utf8ByteLength(null), 0)
assert.equal(Os.utf8ByteLength(undefined), 0)

assert.equal(Os.fileUrlToPath("file:///tmp/a%20b"), "/tmp/a b")
assert.equal(Os.fileUrlToPath("file:///tmp/a%b"), "/tmp/a%b")
assert.equal(Os.fileUrlToPath("/tmp/plain"), "/tmp/plain")
assert.equal(Os.fileUrlToPath("file://relative/x"), "/relative/x")
assert.equal(Os.fileUrlToPath(undefined), "")

assert.equal(Os.SIGTERM, 15)
assert.equal(Os.SIGKILL, 9)
assert.equal(Os.exitToError(-1, 0).code, "failed_to_start")
assert.equal(Os.exitToError(0, 15).code, "terminated")
// Death by any signal (Qt's CrashExit) is terminated, the OOM killer's KILL
// and a crash included; the same number as a plain exit code is not.
assert.equal(Os.exitToError(9, 9).code, "terminated")
assert.equal(Os.exitToError(11, 11).code, "terminated")
assert.equal(Os.exitToError(6, 6).code, "terminated")
assert.equal(Os.exitToError(9, 0).code, "bad_response")
assert.equal(Os.exitToError(143, 0).code, "bad_response", "a streamer stopped by TERM prints its final event first")
const table = { 1: "cli_failed", 124: "timeout" }
for (const code of Object.keys(table)) assert.equal(Os.exitToError(Number(code), 0).code, table[code], code)
assert.equal(Os.exitToError(0, 0).code, "bad_response", "a stream that exited 0 without its final event")
assert.equal(Os.exitToError(99, 0).code, "bad_response")
assert.equal(Os.exitToError(64, 0).code, "bad_response", "a coded exit always follows the final event")
assert.equal(Os.exitToError(1, 0).message, "")

const src = { a: [1, { b: [2] }], s: "x" }
const copy = Os.plain(src)
assert.deepEqual(copy, src)
assert.ok(copy !== src && Array.isArray(copy.a) && Array.isArray(copy.a[1].b))
assert.equal(Os.plain(undefined), null)
assert.equal(Os.plain(null), null)
const cyclic = {}
cyclic.self = cyclic
assert.equal(Os.plain(cyclic), null)
