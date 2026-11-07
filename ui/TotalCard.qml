import QtQuick

// Home's hero: the period caption with the period switch beside it, the
// total across stores, its trend and baseline, and the orders · stores ·
// updated line (warn-coloured once sales are stale).
//
// Contract: periodId; totals (HomeView.totals: amount, multi,
// trend); baselineText; summary; stale; signal periodPicked(id);
// step(delta) returns the neighbouring period id.
Column {
  id: root

  property string periodId: "today"
  property var totals: ({})
  property string baselineText: ""
  property string summary: ""
  property bool stale: false

  signal periodPicked(string id)

  function step(delta) {
    return tabs.step(delta)
  }

  spacing: Look.gapSm

  Item {
    width: parent.width
    height: Math.max(caption.implicitHeight, tabs.implicitHeight)

    SectionHeader {
      id: caption
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: Copy.periodCaption(root.periodId).toUpperCase()
    }

    PeriodTabs {
      id: tabs
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      ids: ["today", "last7d", "last30d"]
      periodId: root.periodId
      onPeriodPicked: (id) => root.periodPicked(id)
    }
  }

  PlainLabel {
    width: parent.width
    text: String(root.totals.amount || "")
    font.pixelSize: root.totals.multi ? Look.heading : Look.displayLarge
    font.bold: true
    fontSizeMode: Text.HorizontalFit
    minimumPixelSize: Look.body
    elide: Text.ElideRight
  }

  TrendBadge {
    trend: root.totals.trend || null
    baselineText: root.baselineText
    bold: true
  }

  PlainLabel {
    width: parent.width
    text: root.summary
    color: root.stale ? Look.warn : Look.muted
    font.pixelSize: Look.small
    elide: Text.ElideRight
  }
}
