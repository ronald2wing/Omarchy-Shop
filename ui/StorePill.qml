import QtQuick
import qs.Commons
import qs.Ui
import "../js/metrics.mjs" as Metrics
import "../js/format.mjs" as Format
import "../js/snapshot.mjs" as Snapshot

// One bar pill. Text stays monochrome; state rides on the
// glyph, `active` (accent pulse for 8 s after a new order, or the tone
// colour of an account-state pill) and `dimmed` (needs access, rate
// limited, info tone).
//
// Modes (display):
//   "stores"  one store: "Acme Apparel $812 ▲", or "AA $812 ▲" with `code`
//   "total"   "󰒚 $1,284 ▲ · 37 orders", or "· 5 stores" with storeCount
//   "icon"    "󰒚" (+ a 4 px tone dot when `dotTone` is set: vertical bars)
//   fixedText any other pill: "󰒚 Add store", "󰒚 Signed out", "󰒚 …"
// The tooltip is computed only while hovered and ends with "right-click
// to refresh" (tailTip). Left click opens, right click refreshes.
WidgetButton {
  id: root

  property var store: null
  property string display: "stores"
  // The host's deduplicated short code; "" shows the label.
  property string code: ""
  property real nowMs: 0
  // total mode: Metrics.periodTotals(…, "today") result, the per-store tooltip lines, and
  // the visible-store count for the auto total (0 = show orders).
  property var totals: null
  property var tooltipLines: []
  property int storeCount: 0
  // total/icon mode: some store has a sales error or needs access; some
  // store is rate limited; figures are still loading.
  property bool problem: false
  property bool limited: false
  property bool loading: false
  // Latest new-order detection time (ms) to pulse on.
  property real pulseKey: 0
  // Fixed text/tooltip pills (empty state, account state, not bound yet).
  property string fixedText: ""
  property string fixedTooltip: ""
  // Account-state tone: "" | info | warn | error (colours the text).
  property string tone: ""
  // Vertical bar: a dot in this tone's colour, "" for none.
  property string dotTone: ""
  property bool tailTip: true

  signal openRequested(string domain)
  signal refreshRequested(string domain)

  readonly property string domain: root.store ? String(root.store.domain || "") : ""
  readonly property var sales: root.store && root.store.sales ? root.store.sales : null
  readonly property var today: root.sales && root.sales.today ? root.sales.today : null
  readonly property string access: root.store ? String(root.store.salesAccess || "unknown") : "unknown"
  readonly property bool needsAccess: Snapshot.needsAccess(root.access)
  readonly property bool hasToday: !!root.today && typeof root.today.sales === "number"
  readonly property bool failed: Snapshot.salesFailed(root.store)
  readonly property bool rateLimited: Snapshot.salesRateLimited(root.store)
  readonly property bool previewRunning: !!root.store && !!root.store.themeState && !!root.store.themeState.preview
    && root.store.themeState.preview.status === "ready"
  readonly property var todayTrend: root.store ? Metrics.periodView(root.store, "today").salesTrend : null

  function arrow(t) {
    return t ? Format.trendGlyph(t.direction) : ""
  }

  function shortLabel(label) {
    var s = String(label || "")
    return s.length > 16 ? s.slice(0, 15) + "…" : s
  }

  function storeText() {
    var parts = []
    var head = root.code !== "" ? root.code : root.shortLabel(root.store ? root.store.label : "")
    if (head !== "") parts.push(head)
    if (root.needsAccess) { parts.push("󰌆"); return parts.join(" ") }
    if (!root.hasToday && root.failed) { parts.push("󰀨"); return parts.join(" ") }
    // store can turn null a moment before the pill's other bindings catch
    // up (the store list emptying while config.json is unreadable).
    parts.push(root.hasToday && root.store ? Format.money(root.today.sales, root.store.currency, { compact: true })
      : (root.store && root.store.sales && root.store.sales.paused === true ? "—" : "…"))
    // A failing store keeps its last figure but never looks current: the
    // error glyph replaces the trend arrow. Rate limiting only mutes.
    var failing = root.failed
    if (failing) parts.push("󰀨")
    var a = failing ? "" : root.arrow(root.todayTrend)
    if (a !== "" && root.hasToday) parts.push(a)
    if (root.previewRunning) parts.push("󰐊")
    return parts.join(" ")
  }

  function totalText() {
    var t = root.totals
    if (!t) return "󰒚"
    var by = t.byCurrency || []
    var tail = root.storeCount > 0 ? Copy.storesText(root.storeCount) : Copy.ordersText(Number(t.orders || 0))
    if (by.length === 1) {
      const a = root.arrow(t.trend)
      return "󰒚 " + Format.money(by[0].sales, by[0].currency, { compact: true }) + (a !== "" ? " " + a : "") + " · " + tail
    }
    if (by.length > 1) return "󰒚 " + tail
    return "󰒚 " + (root.loading ? "…" : "—")
  }

  function trendPhrase(t) {
    var text = Format.trendText(t)
    return text === "" ? "" : " · " + text
  }

  function limitedLine() {
    return Copy.limitedText(root.sales ? root.sales.retryAt : 0)
  }

  function storeTooltip() {
    if (!root.store) return ""
    var label = String(root.store.label || root.domain)
    if (root.needsAccess) return Copy.t("bar.tooltip.error", { label: label, error: Copy.t("error.sales_access_required") })
    if (root.failed && !root.hasToday) return Copy.t("bar.tooltip.error", { label: label, error: Copy.errorOf(root.sales.error) })
    if (!root.hasToday) return label + " — " + (root.rateLimited ? root.limitedLine() : Copy.t("home.never"))
    var at = root.sales.fetchedAt ? Number(root.sales.fetchedAt.today) || 0 : 0
    var line = Copy.t("bar.tooltip", {
      label: label,
      sales: Format.money(root.today.sales, root.store.currency),
      orders: Copy.ordersText(Number(root.today.orders || 0)),
      trend: root.failed ? "" : root.trendPhrase(root.todayTrend),
      updated: Copy.updatedText(at, root.nowMs)
    })
    if (root.rateLimited) return line + "\n" + root.limitedLine()
    return root.failed ? line + " · " + Copy.errorOf(root.sales.error) : line
  }

  // Built only while the pointer is over the pill (tooltipHovered), so a
  // snapshot tick never re-renders text nobody sees.
  function tooltip() {
    var body = root.fixedText !== "" ? root.fixedTooltip
      : (root.display === "stores" ? root.storeTooltip() : root.tooltipLines.join("\n"))
    if (!root.tailTip) return body
    return body !== "" ? body + "\n" + Copy.t("bar.tooltip.tail") : Copy.t("bar.tooltip.tail")
  }

  onPulseKeyChanged: {
    if (root.pulseKey > 0 && Date.now() - root.pulseKey < 8000) pulse.restart()
  }

  Timer {
    id: pulse
    interval: 8000
  }

  text: root.fixedText !== "" ? root.fixedText
    : (root.display === "icon" ? "󰒚" + (root.problem ? " 󰀨" : "")
      : (root.display === "total" ? root.totalText() + (root.problem ? " 󰀨" : "") : root.storeText()))
  tooltipText: root.tooltipHovered ? root.tooltip() : ""
  active: (root.tone === "warn" || root.tone === "error")
    || (pulse.running && !(root.display === "stores" && root.failed && !root.hasToday))
  activeColor: root.tone === "error" ? Look.negative : (root.tone === "warn" ? Look.warn : Look.accent)
  dimmed: root.tone === "info"
    || (root.display === "stores" && (root.access === "required" || root.rateLimited))
    || (root.display !== "stores" && root.fixedText === "" && root.limited)

  Accessible.role: Accessible.Button
  Accessible.name: root.fixedTooltip !== "" ? root.fixedTooltip : root.text
  Accessible.onPressAction: root.openRequested(root.domain)

  onPressed: (button) => {
    if (button === Qt.LeftButton) root.openRequested(root.domain)
    else if (button === Qt.RightButton) root.refreshRequested(root.domain)
    // Middle click does nothing.
  }

  // The vertical bar's attention dot: banner tone warn or error.
  Rectangle {
    visible: root.dotTone !== ""
    width: Style.space(4)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(3)
    color: Look.toneColor(root.dotTone)
  }
}
