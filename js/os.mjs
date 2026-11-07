// The Qt/OS boundary: file URLs as paths, UTF-8 byte lengths for byte caps,
// exit codes as errors, and plain copies of values that crossed a signal.

export const SIGTERM = 15
export const SIGKILL = 9

// The exit codes a stream can end with before its final event: a crash
// before main (1) and the QML deadline (124). A streamer prints its final
// event before any other coded exit.
const EXIT_CODES = { 1: "cli_failed", 124: "timeout" }

// A "file://" URL as a filesystem path; input without the scheme passes
// through. A malformed %-escape keeps the undecoded path.
export function fileUrlToPath(url) {
  let s = String(url == null ? "" : url)
  if (!s.startsWith("file://")) return s
  s = s.substring(7)
  if (s.charAt(0) !== "/") s = "/" + s
  try { return decodeURIComponent(s) } catch (e) { return s }
}

// UTF-8 byte length (not UTF-16 units). null and undefined count as "".
export function utf8ByteLength(s) {
  const str = s == null ? "" : String(s)
  let bytes = 0
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i)
    if (code < 0x80) bytes += 1
    else if (code < 0x800) bytes += 2
    else if (code < 0xD800 || code >= 0xE000) bytes += 3
    else { bytes += 4; i++ }
  }
  return bytes
}

// The error for a stream that ended without its final event: -1 is a
// failed launch, death by any signal (signal > 0: TERM, KILL from the OOM
// killer, a crash's SEGV/ABRT) is terminated,
// 1 and 124 map through EXIT_CODES, and anything else (0, a missing
// interpreter's 127, an unknown code) is bad_response. `signal` is 0 for
// a normal exit: a plain exit(9) is the code 9, never a kill.
export function exitToError(code, signal) {
  if (code === -1) return { code: "failed_to_start", message: "" }
  if (typeof signal === "number" && signal > 0) return { code: "terminated", message: "" }
  const mapped = EXIT_CODES[code]
  return { code: mapped || "bad_response", message: "" }
}

// A plain JS copy of a value that crossed a QML `var` signal parameter. The
// engine turns a JS object emitted that way into a QVariantMap, and arrays
// inside it come back as sequence wrappers for which Array.isArray() is
// false; a JSON round trip restores real arrays. Non-JSON values -> null.
export function plain(v) {
  if (v === undefined || v === null) return null
  try { return JSON.parse(JSON.stringify(v)) } catch (e) { return null }
}
