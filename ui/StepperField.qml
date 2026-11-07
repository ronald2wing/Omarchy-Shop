import QtQuick
import qs.Commons
import qs.Ui

// A whole-number field with − / + buttons and a unit (Settings' refresh
// interval), on LineEdit (digits only, the panel's capped paste). Typing a
// value in range that differs from `value`, or a step (↑/↓ in the field,
// −/+), arms a save after debounceMs; Enter or leaving the field saves at
// once (out of range is clamped); Esc puts `value` back, saves nothing and
// hands the keyboard back. Typing back to `value` disarms the save. A save
// still armed when the field is destroyed (the view closed) is made then.
// No re-entrancy flag: a shown value is written before the debounce stops,
// and Esc reverts the text before the blur, so the blur's commit sees no
// change.
//
// Contract: value (the saved value, from the owner); min; max; step;
// debounceMs; unit; hasCursor; paste (the panel's, for LineEdit);
// accessibleName, lessName, moreName; focusField(); signals committed(v)
// (save v), released() (Enter or Esc gave the keyboard back).
Row {
  id: root

  property int value: 0
  property int min: 0
  property int max: 100
  property int step: 1
  property int debounceMs: 800
  property string unit: ""
  property bool hasCursor: false
  property var paste: null
  property string accessibleName: ""
  property string lessName: ""
  property string moreName: ""
  // The value an armed save will write.
  property int pending: 0

  signal committed(int v)
  signal released()

  function focusField() {
    field.forceActiveFocus()
  }

  function clamp(v) {
    return Math.max(root.min, Math.min(root.max, isNaN(v) ? root.value : v))
  }

  // Shows v without leaving a save armed (the text is written first: a
  // focused field's onTextChanged may arm one).
  function show(v) {
    field.text = String(v)
    debounce.stop()
  }

  function arm(v) {
    if (v === root.value) { debounce.stop(); return }
    root.pending = v
    debounce.restart()
  }

  function typed() {
    if (!field.activeFocus) return
    var v = parseInt(field.text, 10)
    if (v >= root.min && v <= root.max) root.arm(v)
    else debounce.stop()
  }

  function stepBy(direction) {
    var v = root.clamp(parseInt(field.text, 10) + direction * root.step)
    field.text = String(v)
    root.arm(v)
  }

  // Enter or blur: save what the field shows (clamped), then show it.
  function commit() {
    var v = root.clamp(parseInt(field.text, 10))
    root.show(v)
    if (v !== root.value) root.committed(v)
  }

  function revert() {
    root.show(root.value)
    field.focus = false
    root.released()
  }

  function flush() {
    if (!debounce.running) return
    debounce.stop()
    root.committed(root.pending)
  }

  // A saved value from elsewhere (config.json edited, another panel) shows
  // unless the field is being edited.
  onValueChanged: if (!field.activeFocus && !debounce.running) root.show(root.value)
  Component.onDestruction: root.flush()

  spacing: Look.gapMd

  Timer {
    id: debounce
    interval: root.debounceMs
    onTriggered: root.committed(root.pending)
  }

  LineEdit {
    id: field
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(80)
    text: String(root.value)
    allowed: "0-9"
    maximumLength: String(root.max).length
    inputMethodHints: Qt.ImhDigitsOnly
    hasCursor: root.hasCursor
    paste: root.paste
    keyHandler: stepKeys
    Accessible.name: root.accessibleName
    onTextChanged: root.typed()
    onActiveFocusChanged: if (!activeFocus) root.commit()
    // Enter: the blur saves; the keyboard goes back to the owner.
    onAccepted: {
      field.focus = false
      root.released()
    }
    Keys.onEscapePressed: (event) => {
      event.accepted = true
      root.revert()
    }
  }

  // Sees the field's keys first: ↑/↓ step. A keyHandler must stay visible
  // (LineEdit forwards with Keys.forwardTo).
  Item {
    id: stepKeys
    width: 0
    height: 0
    Keys.onUpPressed: (event) => { event.accepted = true; root.stepBy(1) }
    Keys.onDownPressed: (event) => { event.accepted = true; root.stepBy(-1) }
  }

  SmallButton {
    anchors.verticalCenter: parent.verticalCenter
    text: "−"
    Accessible.name: root.lessName
    onClicked: root.stepBy(-1)
  }

  SmallButton {
    anchors.verticalCenter: parent.verticalCenter
    text: "+"
    Accessible.name: root.moreName
    onClicked: root.stepBy(1)
  }

  PlainLabel {
    anchors.verticalCenter: parent.verticalCenter
    text: root.unit
    color: Look.muted
    font.pixelSize: Look.small
  }
}
