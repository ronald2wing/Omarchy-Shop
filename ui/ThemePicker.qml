pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Edit's theme-target picker: a trigger that shows the chosen option and a
// popup with a filter and the option list. It replaces the kit's
// SearchableDropdown, whose popup filter is a native TextField: Qt reads
// the whole clipboard into a TextInput on every paste (and clipboard
// change) with no size or time bound. The filter here is a LineEdit, whose
// paste keys go through `paste` (the panel's capped helper read).
//
// Keyboard: Enter, Space or ↓ on the focused trigger opens; in the popup
// typing filters, ↑/↓ move, Enter picks, Esc closes. The filter clears
// whenever the popup closes.
//
// Contract: options ([{value, label, description}]); value; hasCursor;
// placeholder; emptyText; paste (function(done)); popupOpen; open();
// close(); signals picked(value), hovered(bool), closed() (the popup has
// closed and Qt has put focus back, possibly into a field the user never
// chose; the owner takes it from there). Exposes `filter` (the
// LineEdit), `currentIndex`, `filtered` and `popupContent` for the panel
// smoke.
Item {
  id: root

  property var options: []
  property string value: ""
  property bool hasCursor: false
  property string placeholder: ""
  property string emptyText: ""
  property var paste: null

  readonly property bool popupOpen: popup.opened
  readonly property Item filter: filterEdit
  readonly property int currentIndex: list.currentIndex
  readonly property Item popupContent: popup.contentItem
  readonly property var filtered: {
    var q = filterEdit.text.toLowerCase()
    var out = []
    for (var i = 0; i < root.options.length; i++) {
      var o = root.options[i]
      if (q === "" || String(o.label).toLowerCase().indexOf(q) !== -1 || String(o.description || "").toLowerCase().indexOf(q) !== -1) out.push(o)
    }
    return out
  }

  signal picked(string value)
  signal hovered(bool isHovered)
  signal closed()

  function open() { popup.open() }
  function close() { popup.close() }

  function currentLabel() {
    for (var i = 0; i < root.options.length; i++) if (String(root.options[i].value) === root.value) return String(root.options[i].label)
    return root.value
  }

  function pick(index) {
    if (index < 0 || index >= root.filtered.length) return
    var v = String(root.filtered[index].value)
    popup.close()
    root.picked(v)
  }

  function step(dy) {
    if (root.filtered.length === 0) return
    list.currentIndex = Math.max(0, Math.min(root.filtered.length - 1, list.currentIndex + dy))
    list.positionViewAtIndex(list.currentIndex, ListView.Contain)
  }

  implicitWidth: Style.spacing.searchableDropdownWidth
  implicitHeight: Style.spacing.controlHeight

  Accessible.role: Accessible.ComboBox
  Accessible.name: root.currentLabel()

  BorderSurface {
    id: trigger
    anchors.fill: parent
    radius: Style.cornerRadius

    readonly property bool hot: triggerHover.hovered || root.hasCursor
    color: Style.controlFill(trigger.activeFocus, trigger.hot, Look.fg, Look.accent)
    borderSpec: Border.controlSpec(trigger.activeFocus ? "focus" : (trigger.hot ? "hover-cursor" : "normal"), Look.fg, Look.accent)
    activeFocusOnTab: true

    HoverHandler {
      id: triggerHover
      onHoveredChanged: root.hovered(hovered)
    }

    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        if (popup.opened) popup.close()
        else popup.open()
        event.accepted = true
      }
    }

    PlainLabel {
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: trigger.borderRight + Style.spacing.md
      text: root.currentLabel()
      elide: Text.ElideRight
    }

    PlainLabel {
      id: chevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
      text: "󰅀"
      color: Look.muted
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      // A press on the trigger counts as inside the popup's parent, so a
      // second click closes instead of reopening.
      onClicked: {
        trigger.forceActiveFocus()
        if (popup.opened) popup.close()
        else popup.open()
      }
    }

    QQC.Popup {
      id: popup
      y: trigger.height + Style.spacing.xxs
      width: trigger.width
      padding: Style.spacing.hairline
      closePolicy: QQC.Popup.CloseOnPressOutsideParent | QQC.Popup.CloseOnEscape
      focus: true
      implicitHeight: filterBox.height + 1 + listBox.height + 2 * Style.spacing.hairline

      background: BorderSurface {
        color: Look.surface
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius
      }

      onOpened: {
        filterEdit.text = ""
        var i = 0
        for (var k = 0; k < root.filtered.length; k++) if (String(root.filtered[k].value) === root.value) i = k
        list.currentIndex = root.filtered.length > 0 ? i : -1
        list.positionViewAtIndex(Math.max(0, list.currentIndex), ListView.Contain)
        Qt.callLater(function() { filterEdit.forceActiveFocus() })
      }
      onClosed: {
        filterEdit.text = ""
        root.closed()
      }

      contentItem: Column {
        spacing: 0

        Item {
          id: filterBox
          width: parent.width
          height: filterEdit.implicitHeight + 2 * Style.spacing.md

          LineEdit {
            id: filterEdit
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            placeholderText: root.placeholder
            appendOnly: true
            maximumLength: 200
            keyHandler: keyRelay
            paste: root.paste
            Accessible.name: root.placeholder
            onTextChanged: list.currentIndex = root.filtered.length > 0 ? 0 : -1
          }

          // Sees the filter's keys first: navigation, Enter, Esc (a visible
          // 0×0 item: Keys.forwardTo skips invisible ones).
          Item {
            id: keyRelay
            width: 0
            height: 0
            Keys.onPressed: (event) => {
              if (event.key === Qt.Key_Down) { root.step(1); event.accepted = true }
              else if (event.key === Qt.Key_Up) { root.step(-1); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.pick(list.currentIndex); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Look.hairline
        }

        Item {
          id: listBox
          width: parent.width
          height: Math.max(Style.spacing.popupRowHeight, Math.min(list.contentHeight, Style.spacing.popupRowHeight * 6 + 5 * Style.spacing.labelGap))

          PlainLabel {
            anchors.centerIn: parent
            visible: root.filtered.length === 0
            text: root.emptyText
            color: Look.muted
          }

          ListView {
            id: list
            anchors.fill: parent
            spacing: Style.spacing.labelGap
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered
            currentIndex: -1
            keyNavigationEnabled: false

            delegate: Rectangle {
              id: optionRow
              required property var modelData
              required property int index
              readonly property bool current: optionRow.index === list.currentIndex
              width: list.width
              height: Math.max(Style.spacing.popupRowHeight, rowText.implicitHeight + Style.spacing.rowPaddingX)
              color: optionRow.current ? Style.hoverFillFor(Look.fg, Look.accent) : "transparent"

              Accessible.role: Accessible.ListItem
              Accessible.name: String(optionRow.modelData.label)

              Column {
                id: rowText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                spacing: Style.spacing.xxs

                PlainLabel {
                  width: parent.width
                  text: String(optionRow.modelData.label)
                  color: optionRow.current ? Style.hoverStateColor(Look.fg, Look.accent) : Look.fg
                  elide: Text.ElideRight
                }
                PlainLabel {
                  width: parent.width
                  visible: text !== ""
                  text: String(optionRow.modelData.description || "")
                  color: Look.muted
                  font.pixelSize: Look.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: list.currentIndex = optionRow.index
                onClicked: root.pick(optionRow.index)
              }
            }
          }
        }
      }
    }
  }
}
