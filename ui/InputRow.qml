import QtQuick
import qs.Commons

// One text row of a form (Edit): the label column, a text field (or a
// read-only value) with an optional trailing control, and note, error and
// helper lines under it. Commits on Enter, Tab or blur when the text
// changed; Esc reverts this field only and blurs. `text` is the committed
// value from the owner.
//
// Contract: label; text; placeholder; helper; error; note; readOnly;
// hasCursor; paste (the panel's, for LineEdit); trailing: [items]; focusField(); revertAndBlur(); leave(direction); signals
// committed(text), fieldFocusChanged(focused), fieldTabbed(direction).
Item {
  id: root

  property string label: ""
  property string text: ""
  property string placeholder: ""
  property string helper: ""
  property string error: ""
  property bool readOnly: false
  property bool hasCursor: false
  property var paste: null
  // A short "Saved ✓" style note shown under the field.
  property string note: ""
  // Optional trailing control (e.g. a Browse… button).
  property alias trailing: trailingSlot.data

  signal committed(string text)
  signal fieldFocusChanged(bool focused)
  // Tab (+1) or Shift+Tab (-1) left the field after committing: the owner
  // moves its cursor to the neighbouring row and focuses it if editable.
  signal fieldTabbed(int direction)

  function focusField() {
    if (root.readOnly) return
    field.forceActiveFocus()
    field.selectAll()
  }

  function revertAndBlur() {
    field.text = root.text
    field.focus = false
    root.fieldFocusChanged(false)
  }

  function commitIfChanged() {
    if (root.readOnly) return
    var value = field.text
    if (value !== root.text) root.committed(value)
  }

  // Enter (0), Tab (+1) or Shift+Tab (-1): the blur commits and reports
  // the focus change (onActiveFocusChanged); a Tab also moves the cursor.
  function leave(direction) {
    field.focus = false
    if (direction !== 0) root.fieldTabbed(direction)
  }

  onTextChanged: if (!field.activeFocus) field.text = root.text

  implicitHeight: Math.max(labelText.implicitHeight, rightColumn.implicitHeight)

  RowLabel {
    id: labelText
    anchors.left: parent.left
    y: root.readOnly ? 0 : Math.max(0, (field.implicitHeight - implicitHeight) / 2)
    text: root.label
    lit: root.hasCursor
    elide: Text.ElideRight
  }

  Column {
    id: rightColumn
    anchors.left: labelText.right
    anchors.leftMargin: Look.gapLg
    anchors.right: parent.right
    spacing: Look.gapXs

    Row {
      width: parent.width
      spacing: Look.gapMd

      PlainLabel {
        id: readOnlyText
        visible: root.readOnly
        width: parent.width - trailingSlot.width
        text: root.text
        elide: Text.ElideMiddle
      }

      LineEdit {
        id: field
        visible: !root.readOnly
        width: parent.width - (trailingSlot.width > 0 ? trailingSlot.width + parent.spacing : 0)
        text: root.text
        placeholderText: root.placeholder
        hasCursor: root.hasCursor
        verticalPadding: Style.spacing.xs
        paste: root.paste
        Accessible.name: root.label

        onActiveFocusChanged: {
          if (!activeFocus) root.commitIfChanged()
          root.fieldFocusChanged(activeFocus)
        }
        // Enter commits and blurs; LineEdit accepts the key, so it never reaches
        // the view, whose Enter would re-enter this field.
        onAccepted: root.leave(0)
        onTabbed: (direction) => root.leave(direction)
        Keys.onEscapePressed: (event) => {
          event.accepted = true
          root.revertAndBlur()
        }
      }

      Row {
        id: trailingSlot
        anchors.verticalCenter: root.readOnly ? readOnlyText.verticalCenter : field.verticalCenter
        spacing: Look.gapMd
      }
    }

    PlainLabel {
      visible: root.note !== ""
      text: root.note
      color: Look.positive
      font.pixelSize: Look.caption
    }

    PlainLabel {
      visible: root.error !== ""
      width: parent.width
      text: root.error
      color: Look.negative
      font.pixelSize: Look.caption
      wrapMode: Text.WordWrap
    }

    PlainLabel {
      visible: root.helper !== ""
      width: parent.width
      text: root.helper
      color: Look.muted
      font.pixelSize: Look.caption
      wrapMode: Text.WordWrap
    }
  }
}
