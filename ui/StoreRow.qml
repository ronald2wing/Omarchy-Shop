import QtQuick
import qs.Commons
import "../js/metrics.mjs" as Metrics
import "../js/format.mjs" as Format
import "../js/snapshot.mjs" as Snapshot

// One store on the Home list for the chosen period:
//   Acme Apparel                        $60.01  ▲ 69%
//   3 orders · 1,621 sessions               ▁▂▃▅▂▆▇
// A store that needs sales access shows the warn line and a Grant access
// button instead of figures; while the banner carries an account-level
// state the row shows "—" and nothing else (never the banner's text).
//
// Contract: store (snapshot store); periodId; selected; showSpark (the
// host decides all-or-none); muted (banner-level state); signals
// activated(), hoveredRow() (ListRow), accessToggled() (Grant access, or
// Cancel while the browser flow runs).
ListRow {
  id: root

  property var store: null
  property string periodId: "today"
  property bool showSpark: false
  property bool muted: false

  signal accessToggled()

  readonly property var sales: root.store && root.store.sales ? root.store.sales : null
  readonly property string currency: root.store && root.store.currency ? root.store.currency : ""
  readonly property string access: root.store ? String(root.store.salesAccess || "unknown") : "unknown"
  readonly property bool needsAccess: Snapshot.needsAccess(root.access)
  readonly property bool granting: root.access === "granting"
  // Rate limiting is a banner-level state: the figures stay and nothing is red.
  readonly property bool failed: Snapshot.salesFailed(root.store)
  readonly property var view: root.store ? Metrics.periodView(root.store, root.periodId) : null
  readonly property bool hasFigure: !!root.view && typeof root.view.sales === "number"
  readonly property var trend: root.view ? root.view.salesTrend : null
  readonly property var sparkBuckets: root.store ? Metrics.periodView(root.store, "last7d").buckets : []

  readonly property string amountText: {
    if (root.needsAccess || root.muted) return "—"
    if (root.hasFigure) return Format.money(root.view.sales, root.currency)
    return Metrics.awaitingFigures(root.sales) ? "…" : "—"
  }

  readonly property string detailText: {
    if (!root.store || root.muted) return ""
    if (root.granting) return Copy.t("access.granting")
    if (root.needsAccess) return Copy.t("error.sales_access_required")
    if (root.failed && !root.hasFigure) return Copy.errorOf(root.sales.error)
    if (!root.view) return ""
    var parts = []
    if (typeof root.view.orders === "number") parts.push(Copy.ordersText(root.view.orders))
    if (typeof root.view.sessions === "number") parts.push(Copy.sessionsText(root.view.sessions))
    return parts.join(" · ")
  }

  implicitHeight: rowColumn.implicitHeight + Style.spacing.lg * 2

  Accessible.name: (root.store ? root.store.label : "") + ", " + root.amountText + ", " + root.detailText

  Column {
    id: rowColumn
    x: Look.rowPadX
    y: Style.spacing.lg
    width: parent.width - Look.rowPadX * 2
    spacing: Look.gapXs

    Item {
      width: parent.width
      height: Math.max(nameText.implicitHeight, amount.implicitHeight)

      PlainLabel {
        id: nameText
        anchors.left: parent.left
        anchors.right: amountRow.left
        anchors.rightMargin: Look.gapLg
        anchors.verticalCenter: parent.verticalCenter
        text: root.store ? root.store.label : ""
        font.pixelSize: Look.subtitle
        font.bold: root.selected
        elide: Text.ElideRight
      }

      Row {
        id: amountRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Look.gapMd

        PlainLabel {
          id: amount
          anchors.verticalCenter: parent.verticalCenter
          text: root.amountText
          font.pixelSize: Look.subtitle
          font.bold: true
        }

        TrendBadge {
          anchors.verticalCenter: parent.verticalCenter
          trend: root.needsAccess || root.muted ? null : root.trend
        }
      }
    }

    Item {
      visible: root.detailText !== "" || grantButton.visible || spark.visible
      width: parent.width
      height: Math.max(detail.implicitHeight, grantButton.visible ? grantButton.implicitHeight : 0, spark.visible ? spark.height : 0)

      PlainLabel {
        id: detail
        anchors.left: parent.left
        anchors.right: grantButton.visible ? grantButton.left : (spark.visible ? spark.left : parent.right)
        anchors.rightMargin: Look.gapLg
        anchors.verticalCenter: parent.verticalCenter
        text: root.detailText
        color: root.needsAccess || root.failed ? Look.warn : Look.muted
        font.pixelSize: Look.small
        elide: Text.ElideRight
      }

      SmallButton {
        id: grantButton
        // While the browser flow runs the same button cancels it.
        visible: root.needsAccess && !root.muted
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.granting ? Copy.t("action.cancel") : Copy.t("access.grant")
        verticalPadding: Style.spacing.xxs
        onClicked: root.accessToggled()
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: root.accessToggled()
      }

      Sparkline {
        id: spark
        visible: root.showSpark && !root.needsAccess && !root.muted && root.sparkBuckets.length > 1
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(64)
        height: Style.space(14)
        compact: true
        buckets: root.sparkBuckets
        currency: root.currency
      }
    }
  }
}
