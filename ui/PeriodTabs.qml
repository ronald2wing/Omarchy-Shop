import QtQuick
import qs.Ui
import "../js/metrics.mjs" as Metrics

// The period switch. Default: Today · Yesterday · 7d · 14d · 30d · 12m
// (the store view); Home's TotalCard passes ids: ["today", "last7d", "last30d"].
// Driven by the panel's keys (h/l, and 1-6 on the full set), so the group
// itself never takes focus. The digit lives in each tab's tooltip, never
// on the tab.
//
// Contract: ids (period ids to show); periodId (current); signal
// periodPicked(id); step(delta) returns the neighbouring id.
ButtonGroup {
  id: root

  property var ids: Metrics.PERIOD_IDS
  property string periodId: "today"

  signal periodPicked(string id)

  readonly property bool fullSet: root.ids.length === Metrics.PERIOD_IDS.length

  function optionsFor(list) {
    var out = []
    for (var i = 0; i < list.length; i++) {
      var tip = Copy.periodCaption(list[i]) + (root.fullSet ? " · " + (i + 1) : "")
      out.push({ value: list[i], label: Copy.t("period." + list[i]), tooltip: tip })
    }
    return out
  }

  // The id `delta` steps away from the current one, clamped to the ends.
  function step(delta) {
    var i = root.ids.indexOf(root.periodId)
    if (i < 0) i = 0
    return root.ids[Math.max(0, Math.min(root.ids.length - 1, i + delta))]
  }

  focusable: false
  cursorIndex: -1
  spacing: Look.gapXs
  fontSize: Look.small
  options: root.optionsFor(root.ids)
  value: root.periodId
  onChanged: (v) => root.periodPicked(v)
}
