pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../js/metrics.mjs" as Metrics
import "../js/format.mjs" as Format

// The period's figures as tiles, three per row, left-aligned: Orders,
// Sessions, Avg order, Sales / session, then the funnel rates, plus a
// Lifetime tile (money, no trend) when the period view carries lifetime
// (the last 12 months). The model is a count, so
// delegates never churn; each tile reads Metrics.kpi() by slot.
Grid {
  id: root

  property var store: null
  property string periodId: "today"

  readonly property var view: root.store ? Metrics.periodView(root.store, root.periodId) : null
  readonly property var lifetime: root.view ? root.view.lifetime : null
  readonly property int slotCount: Metrics.KPI_SLOTS.length + (root.lifetime ? 1 : 0)
  readonly property bool loading: !!root.store && Metrics.awaitingFigures(root.store.sales)
  readonly property string currency: root.store && root.store.currency ? root.store.currency : ""

  // {format: money|percent|count, value, trend, label, tip} for a tile;
  // label and tip are Copy keys (tip "" when the tile has none).
  function tile(index) {
    if (!root.store) return null
    if (index >= Metrics.KPI_SLOTS.length)
      return { format: "money", value: root.lifetime ? root.lifetime.sales : null, trend: null, label: "kpi.lifetime", tip: "" }
    return Metrics.kpi(root.store, root.periodId, index)
  }

  function valueText(k) {
    if (!k || k.value === null || k.value === undefined) return root.loading ? "…" : "—"
    if (k.format === "money") return Format.money(k.value, root.currency)
    if (k.format === "count") return Format.count(k.value)
    return Format.percent(k.value)
  }

  columns: 3
  columnSpacing: Look.gapLg
  rowSpacing: Look.gapLg

  Repeater {
    model: root.slotCount

    delegate: Item {
      id: cell
      required property int index
      readonly property var k: root.tile(index)
      readonly property string labelKey: k ? k.label : ""
      readonly property string tipKey: k ? k.tip : ""

      width: (root.width - root.columnSpacing * 2) / 3
      implicitHeight: cellColumn.implicitHeight

      Accessible.role: Accessible.StaticText
      Accessible.name: Copy.t(cell.labelKey) + " " + root.valueText(cell.k)

      Column {
        id: cellColumn
        width: parent.width
        spacing: Style.space(1)

        PlainLabel {
          width: parent.width
          text: Copy.t(cell.labelKey)
          color: Look.muted
          font.pixelSize: Look.small
          elide: Text.ElideRight
        }

        // value · badge read as two tokens (the badge's own glyph/percent
        // gap is a space), the same gap StoreRow puts between amount and trend.
        Row {
          spacing: Look.gapMd

          PlainLabel {
            text: root.valueText(cell.k)
            font.pixelSize: Look.subtitle
            font.bold: true
          }

          TrendBadge {
            anchors.verticalCenter: parent.verticalCenter
            trend: cell.k ? cell.k.trend : null
            fontSize: Look.caption
          }
        }
      }

      HoverTip { text: cell.tipKey ? Copy.t(cell.tipKey) : "" }
    }
  }
}
