import QtQuick
import qs.Commons
import qs.Ui

// Shop's one-line text field, styled like the kit's TextField. It is built
// on TextEdit, not TextInput, and never lets Qt read the clipboard:
// - TextInput reads the whole clipboard whenever it changes (its canPaste
//   check), and any native paste reads it before inserting. Qt's Wayland
//   read has no size or time bound, so a clipboard owner that keeps sending
//   would block or exhaust the shared shell. TextEdit checks offered formats
//   only.
// - Every paste key (StandardKey.Paste, Shift+Insert) calls `paste(done)`,
//   the panel's capped helper read (ShopPanel.paste); the text arrives
//   single-line, filtered and capped. A middle click (primary selection)
//   and dropped text are swallowed. TextEdit has no context menu.
// Return and Enter never insert a newline: they emit accepted(). Tab and
// Shift+Tab emit tabbed(±1) instead of typing a tab. Esc and every other
// key the field leaves alone reach the owner's Keys handlers.
//
// Contract: text; placeholderText; hasCursor; verticalPadding;
// framed (the kit's border and fill; false inside an owner's frame);
// inputMethodHints; allowed (a character-class body, e.g. "0-9"; "" = any);
// maximumLength; appendOnly (caret pinned at the end, no selection: list
// filters); keyHandler (sees every key first); paste (function(done));
// cursorPosition; composing; selectAll(); signals accepted(), tabbed(dir).
FocusScope {
  id: root

  property alias text: edit.text
  property string placeholderText: ""
  property bool hasCursor: false
  property bool framed: true
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property alias inputMethodHints: edit.inputMethodHints
  property string allowed: ""
  property int maximumLength: 4096
  property bool appendOnly: false
  property Item keyHandler: null
  property var paste: null
  readonly property alias cursorPosition: edit.cursorPosition
  // An input method is composing (its preedit text is not in `text` yet).
  readonly property bool composing: edit.preeditText !== ""

  signal accepted()
  signal tabbed(int direction)

  function selectAll() {
    edit.selectAll()
  }

  // `value` cut to one line, the allowed characters and maximumLength,
  // counting what the field already holds outside the replaced selection.
  function fit(value, keep) {
    var line = String(value).replace(/[\r\n\u2028\u2029][\s\S]*$/, "")
    if (root.allowed !== "") line = line.replace(new RegExp("[^" + root.allowed + "]", "g"), "")
    return line.substring(0, Math.max(0, root.maximumLength - keep))
  }

  function insertPasted(value) {
    if (root.appendOnly) {
      edit.insert(edit.length, root.fit(value, edit.length))
      return
    }
    var from = Math.min(edit.selectionStart, edit.selectionEnd)
    var to = Math.max(edit.selectionStart, edit.selectionEnd)
    var piece = root.fit(value, edit.length - (to - from))
    if (to > from) edit.remove(from, to)
    edit.insert(from, piece)
    edit.cursorPosition = from + piece.length
  }

  function requestPaste() {
    if (typeof root.paste !== "function") return
    root.paste(function(value) { root.insertPasted(value) })
  }

  readonly property bool hot: hover.hovered || root.hasCursor
  readonly property var borderSpec: root.framed ? Border.controlSpec(edit.activeFocus ? "focus" : (root.hot ? "hover-cursor" : "normal"), Look.fg, Look.accent) : null

  implicitWidth: Style.space(200)
  implicitHeight: edit.implicitHeight + root.verticalPadding * 2 + Border.top(root.borderSpec) + Border.bottom(root.borderSpec)

  Accessible.role: Accessible.EditableText

  BorderSurface {
    visible: root.framed
    anchors.fill: parent
    color: Style.controlFill(edit.activeFocus, root.hot, Look.fg, Look.accent)
    borderSpec: root.borderSpec
    radius: Style.cornerRadius
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.IBeamCursor
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: root.horizontalPadding + Border.left(root.borderSpec)
    anchors.rightMargin: root.horizontalPadding + Border.right(root.borderSpec)
    anchors.topMargin: root.verticalPadding + Border.top(root.borderSpec)
    anchors.bottomMargin: root.verticalPadding + Border.bottom(root.borderSpec)
    clip: true
    interactive: false
    contentWidth: edit.width
    contentHeight: height

    // Keeps the caret in view as the text outgrows the field.
    function follow(r) {
      if (flick.contentX > r.x) flick.contentX = r.x
      else if (flick.contentX + flick.width < r.x + r.width) flick.contentX = r.x + r.width - flick.width
    }

    TextEdit {
      id: edit
      focus: true
      width: Math.max(flick.width, edit.contentWidth + 2)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      selectByMouse: !root.appendOnly
      persistentSelection: false
      color: Look.fg
      selectionColor: Style.selectionFillFor(Look.fg, Look.accent)
      selectedTextColor: Look.fg
      font.family: Look.fontFamily
      font.pixelSize: Look.body
      cursorDelegate: root.appendOnly ? hiddenCaret : null
      Accessible.ignored: true

      Keys.priority: Keys.BeforeItem
      Keys.forwardTo: root.keyHandler ? [root.keyHandler] : []
      Keys.onPressed: (event) => {
        if (event.matches(StandardKey.Paste) || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
          event.accepted = true
          root.requestPaste()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (edit.inputMethodComposing) return
          event.accepted = true
          root.accepted()
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.tabbed(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
        } else if (root.appendOnly && (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
          // Alt and Super chords are shortcuts, never text.
          event.accepted = true
        }
      }

      onCursorRectangleChanged: flick.follow(edit.cursorRectangle)
      onCursorPositionChanged: if (root.appendOnly && edit.cursorPosition !== edit.length) edit.cursorPosition = edit.length
      onSelectedTextChanged: if (root.appendOnly && edit.selectedText !== "") edit.deselect()
      // Typed or committed text that breaks the rules (an IME newline, a
      // character outside `allowed`, past maximumLength) is fitted back.
      onTextChanged: {
        var fitted = root.fit(edit.text, 0)
        if (fitted === edit.text) return
        edit.text = fitted
        edit.cursorPosition = fitted.length
      }
    }
  }

  Component {
    id: hiddenCaret
    Item {}
  }

  PlainLabel {
    visible: edit.text === "" && !root.composing && root.placeholderText !== ""
    anchors.left: flick.left
    anchors.right: flick.right
    anchors.verticalCenter: flick.verticalCenter
    text: root.placeholderText
    color: Look.muted
    font.pixelSize: Look.body
    elide: Text.ElideRight
  }

  // The primary selection is a clipboard too: a middle click never pastes.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    onPressed: (mouse) => { mouse.accepted = true }
  }

  // Dropped text is a clipboard transfer: taken here, never read.
  DropArea {
    anchors.fill: parent
    onDropped: (drop) => { drop.accepted = false }
  }
}
