import QtQuick
import "../js/format.mjs" as Format

// "▲ 69% · $35.50 at this time yesterday". The glyph carries the direction;
// the colour is only a second cue. A flat or missing trend draws no
// percentage (the figure beside it already says what happened); the
// baseline, when given, still shows.
Row {
  id: root

  // {direction: "up"|"down"|"flat", pct: number in percent units} or null.
  property var trend: null
  // The comparison amount in words ("$35.50 at this time yesterday"),
  // rendered muted after the percentage. Empty for a bare badge.
  property string baselineText: ""
  property real fontSize: Look.small
  property bool bold: false

  readonly property string direction: root.trend ? String(root.trend.direction || "flat") : "flat"
  readonly property color tone: root.direction === "up" ? Look.positive : Look.negative

  readonly property bool trendShown: root.direction !== "flat"

  visible: root.trendShown || root.baselineText !== ""
  spacing: Look.gapSm

  Accessible.role: Accessible.StaticText
  Accessible.name: root.visible ? Format.trendText(root.trend) + " " + root.baselineText : ""

  PlainLabel {
    visible: root.trendShown
    text: Format.trendText(root.trend)
    color: root.tone
    font.pixelSize: root.fontSize
    font.bold: root.bold
  }

  PlainLabel {
    visible: root.baselineText !== ""
    text: (root.trendShown ? "· " : "") + root.baselineText
    color: Look.muted
    font.pixelSize: root.fontSize
  }
}
