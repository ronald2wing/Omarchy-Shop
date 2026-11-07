import QtQuick
import qs.Commons

// The LIVE mark beside a theme name: a small warn-coloured capsule with
// the kit's caption. The outline form sits in rows (the backups list, the
// theme card's target line); `filled` is the confirmation dialog's
// stronger one.
Rectangle {
  id: root

  property bool filled: false

  implicitWidth: label.implicitWidth + (root.filled ? Look.gapMd * 2 : Style.space(8))
  implicitHeight: label.implicitHeight + (root.filled ? Look.gapXs * 2 : Style.space(2))
  radius: Style.cornerRadius
  color: root.filled ? Util.alpha(Look.warn, 0.14) : "transparent"
  border.width: 1
  border.color: root.filled ? Util.alpha(Look.warn, 0.6) : Look.warn

  PlainLabel {
    id: label
    anchors.centerIn: parent
    text: Copy.t("theme.liveChip")
    color: Look.warn
    font.pixelSize: Look.caption
    font.bold: true
    font.letterSpacing: 1
  }
}
