pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/format.mjs" as Format

// Single-colour bar sparkline over period buckets, with the first and last
// bucket named under the bars (00 … 23, Nov 3 … Nov 9, Dec 2025 … Nov 2026).
// Hover shows one tooltip: day, sales, sessions and sales per session; a
// partial bucket is drawn at half opacity and says so in the tooltip.
Item {
  id: root

  // [{date: "YYYY-MM-DD" | month: "YYYY-MM" | hour: n, sales, sessions, partial?}]
  property var buckets: []
  property string currency: ""
  // Rows (Home) draw a short, label-less strip.
  property bool compact: false

  property int hoverIndex: -1
  readonly property int count: root.buckets ? root.buckets.length : 0
  readonly property real gap: root.compact ? Style.space(1) : Style.space(2)
  readonly property real barWidth: root.count > 0 ? Math.max(1, (root.width - root.gap * (root.count - 1)) / root.count) : 0
  readonly property real barsHeight: root.compact ? Style.space(16) : Style.space(44)
  readonly property bool labelled: !root.compact && root.count > 1
  readonly property real maxValue: {
    var m = 0
    for (var i = 0; i < root.count; i++) m = Math.max(m, root.valueAt(i))
    return m
  }

  // The bar's height value. Analytics net sales can be negative (a return
  // booked in an hour or on a day with no orders): such a bar draws at the
  // floor height like an empty one, and its tooltip shows the amount.
  function valueAt(i) {
    var b = root.buckets[i]
    return b ? Math.max(0, Number(b.sales) || 0) : 0
  }

  // The bucket's name in the tooltip: "Tue 3 Nov", "Dec 2025" or "14:00".
  function bucketName(b) {
    if (!b) return ""
    if (b.date) return Format.dayLabel(b.date)
    if (b.month) return Format.monthLabel(b.month)
    if (b.hour !== undefined && b.hour !== null) return Format.pad2(Number(b.hour) || 0) + ":00"
    return ""
  }

  // The short tick under the first and last bar. Day and month names come
  // from Format (the only place that knows month names); a day tick keeps
  // just month + day ("Nov 3"); a month tick keeps the whole year ("Dec
  // 2025"): a two-digit year would read as a day of the month next to the
  // 7d chart's "Oct 31".
  function tickText(b) {
    if (!b) return ""
    if (b.hour !== undefined && b.hour !== null) return Format.pad2(Number(b.hour) || 0)
    if (b.date) {
      var parts = Format.dayLabel(b.date).split(" ")
      return parts.length === 3 ? parts[2] + " " + parts[1] : parts.join(" ")
    }
    if (b.month) return Format.monthLabel(b.month)
    return ""
  }

  function tipText(i) {
    var b = root.buckets[i]
    if (!b) return ""
    var sales = Number(b.sales) || 0
    var sessions = b.sessions === null || b.sessions === undefined ? null : Number(b.sessions)
    return Copy.t("spark.tip", {
      day: root.bucketName(b),
      sales: Format.money(sales, root.currency),
      sessions: sessions === null ? Copy.t("count.sessions", { n: "—" }) : Copy.sessionsText(sessions),
      perSession: sessions ? Format.money(sales / sessions, root.currency) : "—",
      partial: b.partial ? Copy.t("spark.partial") : ""
    })
  }

  implicitHeight: root.barsHeight + (root.labelled ? firstTick.implicitHeight + Look.gapXs : 0)
  implicitWidth: Style.space(120)

  Accessible.role: Accessible.Chart
  Accessible.name: root.hoverIndex >= 0 ? root.tipText(root.hoverIndex) : ""

  Item {
    id: bars
    width: parent.width
    height: root.barsHeight

    Repeater {
      model: root.count

      delegate: Rectangle {
        required property int index
        readonly property real value: root.valueAt(index)
        readonly property bool lit: index === root.hoverIndex
        x: index * (root.barWidth + root.gap)
        width: root.barWidth
        height: root.maxValue > 0 ? Math.max(Style.space(1), bars.height * value / root.maxValue) : Style.space(1)
        y: bars.height - height
        radius: root.compact ? 0 : Math.min(Style.space(2), Style.cornerRadius)
        color: lit ? Look.fg : Look.barFill
        opacity: (root.buckets[index] && root.buckets[index].partial) ? 0.5 : 1
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: !root.compact && root.count > 0
      hoverEnabled: true
      onPositionChanged: (mouse) => {
        var i = Math.floor(mouse.x / Math.max(1, root.barWidth + root.gap))
        root.hoverIndex = Math.max(0, Math.min(root.count - 1, i))
      }
      onExited: root.hoverIndex = -1
    }

    PanelToolTip {
      visible: !root.compact && root.hoverIndex >= 0 && root.hoverIndex < root.count
      delay: 0
      text: root.hoverIndex >= 0 ? root.tipText(root.hoverIndex) : ""
      x: Math.max(0, Math.min(root.width - width, root.hoverIndex * (root.barWidth + root.gap) + root.barWidth / 2 - width / 2))
      y: -height - Style.space(4)
    }
  }

  PlainLabel {
    id: firstTick
    visible: root.labelled
    anchors.left: parent.left
    anchors.top: bars.bottom
    anchors.topMargin: Look.gapXs
    text: root.tickText(root.buckets[0])
    color: Look.muted
    font.pixelSize: Look.caption
  }

  PlainLabel {
    visible: root.labelled
    anchors.right: parent.right
    anchors.top: bars.bottom
    anchors.topMargin: Look.gapXs
    text: root.tickText(root.buckets[root.count - 1])
    color: Look.muted
    font.pixelSize: Look.caption
  }
}
