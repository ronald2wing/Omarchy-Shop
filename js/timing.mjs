// The QML side of Shop::TIMING (lib/shop.rb): per helper (fetch-sales per
// range), the QML deadline that backs up the helper's own (its H + 5 s;
// 0 = none, for the preview stream) and the stdout cap (a streamer's line
// cap). HelperProcess and HelperStream default to these from their `helper`
// (and `range`), so no model spells a deadline or a cap.
// tests/ruby/test_source_contracts.rb parses the HELPERS rows below and
// fails when one differs from Shop::TIMING: keep each row on one line, as
// `"name": row(H seconds, cap),` or `"name": stream(cap),`.

const KIB = 1024
const MIB = 1024 * KIB
// QML deadline = helper deadline H + 5 s (CONTRIBUTING "Timing").
const GRACE_S = 5

function row(helperSeconds, cap) {
  return { deadlineMs: (helperSeconds + GRACE_S) * 1000, cap: cap }
}

// A streamer that lives until stopped: no QML deadline.
function stream(cap) {
  return { deadlineMs: 0, cap: cap }
}

export const HELPERS = {
  "prepare-state": row(5, 4 * KIB),
  "check-account": row(20, 64 * KIB),
  "sign-in": row(900, 64 * KIB),
  "sign-out": row(30, 4 * KIB),
  "install-cli": row(900, 4 * KIB),
  "grant-sales-access": row(600, 4 * KIB),
  "discover-stores": row(45, 2 * MIB),
  "fetch-sales today": row(25, 1 * MIB),
  "fetch-sales history": row(45, 1 * MIB),
  "fetch-sales yesterday": row(45, 2 * MIB),
  "list-themes": row(20, 256 * KIB),
  "inspect-folder": row(15, 16 * KIB),
  "list-backups": row(5, 256 * KIB),
  "push-theme": row(600, 32 * KIB),
  "pull-theme": row(600, 32 * KIB),
  "restore-backup": row(600, 32 * KIB),
  "notify-order": row(10, 1 * KIB),
  "read-clipboard": row(4, 32 * KIB),
  "preview-theme": stream(4 * KIB)
}

// The row for a helper (and fetch-sales' range), or null for an unknown one.
function rowFor(helper, range) {
  const key = range ? helper + " " + range : helper
  return Object.prototype.hasOwnProperty.call(HELPERS, key) ? HELPERS[key] : null
}

// The QML deadline in ms (0 = none). An unknown helper gets none: its
// HelperProcess then also has no output cap and fails closed on any output.
export function deadlineMs(helper, range) {
  const r = rowFor(helper, range)
  return r ? r.deadlineMs : 0
}

// The stdout cap in bytes (a streamer's line cap), 0 for an unknown helper.
export function cap(helper, range) {
  const r = rowFor(helper, range)
  return r ? r.cap : 0
}
