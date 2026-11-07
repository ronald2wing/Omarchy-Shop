import QtQuick

// The label column of a settings or edit row (Look.labelWidth, Look.small):
// lit (foreground, bold) while the row holds the keyboard cursor, muted
// otherwise. The owner places it (anchors or y) and sets wrapping.
PlainLabel {
  id: root

  property bool lit: false

  width: Look.labelWidth
  color: root.lit ? Look.fg : Look.muted
  font.pixelSize: Look.small
  font.bold: root.lit
}
