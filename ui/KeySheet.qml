pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import "../js/keymap.mjs" as Keymap

// The "?" overlay: every key for the current view in three groups,
// Navigate / This view / Panel. A group lays out two-up (key · what, key ·
// what) when its widest pair fits twice across the sheet, else one per
// row; nothing is ever elided. The key column is as wide as the longest
// key on the sheet, so keys align across groups. Notation: Ctrl+j,
// Shift+Tab, Backspace, Esc, Enter, Space, 1–6. Takes focus while shown;
// Esc, ? or q closes it.
//
// Contract: view (home | store | edit | add | backups | settings); keymap
// (the view's js/keymap.mjs rows: its navigate rows join the Navigate group,
// its view rows are "This view", its panel rows lead the Panel group; only
// rows that act are listed, so the sheet never lists a key the screen
// under it ignores); bannerActions (how many actions the banner offers: i
// / Shift+i run the first two); canGoBack (a view sits under this one, so
// Esc / Backspace go back instead of closing); show(); hide(); signal
// closed().
Rectangle {
  id: root

  property string view: "home"
  property var keymap: []
  property int bannerActions: 0
  property bool canGoBack: false

  signal closed()

  // Esc and Backspace go back only above the bottom of the view stack; at
  // the bottom Esc closes the panel, and so does Backspace except on Home,
  // where it does nothing.
  readonly property var navigateRows: {
    var rows = Keymap.sheetRows(root.keymap, "navigate")
    if (root.canGoBack) rows.push(["Esc / Backspace", Copy.t("action.back")])
    else rows.push([root.view === "home" ? "Esc" : "Esc / Backspace", Copy.t("keys.closePanel")])
    rows.push(["Tab / Shift+Tab", Copy.t("keys.switch")])
    return rows
  }

  readonly property var viewRows: Keymap.sheetRows(root.keymap, "view")

  readonly property var panelRows: {
    var list = Keymap.sheetRows(root.keymap, "panel")
    if (root.bannerActions > 1) list.push(["i / Shift+i", Copy.t("keys.banner")])
    else if (root.bannerActions === 1) list.push(["i", Copy.t("keys.banner.one")])
    list.push(["?", Copy.t("keys.help")])
    return list
  }

  readonly property var groups: [
    { title: Copy.t("keys.group.navigate"), rows: root.navigateRows },
    { title: Copy.t("keys.group.view"), rows: root.viewRows },
    { title: Copy.t("keys.group.panel"), rows: root.panelRows }
  ]

  // Widest key over every group, measured in the key font.
  readonly property real keyColumn: {
    var m = 0
    for (var g = 0; g < root.groups.length; g++) m = Math.max(m, root.widest(root.groups[g].rows, 0, keyMetrics))
    return m
  }

  function widest(rows, col, metrics) {
    var m = 0
    for (var i = 0; i < rows.length; i++) m = Math.max(m, metrics.advanceWidth(String(rows[i][col])))
    return Math.ceil(m)
  }

  function show() {
    root.visible = true
    root.forceActiveFocus()
  }

  function hide() {
    if (!root.visible) return
    root.visible = false
    root.closed()
  }

  visible: false
  color: Look.surface
  focus: visible
  implicitHeight: body.implicitHeight + Look.gapLg * 2

  FontMetrics {
    id: keyMetrics
    font.family: Look.fontFamily
    font.pixelSize: Look.body
    font.bold: true
  }

  FontMetrics {
    id: bodyMetrics
    font.family: Look.fontFamily
    font.pixelSize: Look.body
  }

  Accessible.role: Accessible.Dialog
  Accessible.name: Copy.t("keys.title")

  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape || event.text === "?" || event.text === "q" || event.key === Qt.Key_Return) {
      root.hide()
    }
    // The sheet is modal: nothing reaches the panel behind it.
    event.accepted = true
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.hide()
  }

  Column {
    id: body
    anchors.fill: parent
    anchors.margins: Look.gapLg
    spacing: Look.gapLg

    Item {
      width: parent.width
      height: titleText.implicitHeight

      PlainLabel {
        id: titleText
        text: Copy.t("keys.title")
        font.pixelSize: Look.title
        font.bold: true
      }

      PlainLabel {
        anchors.right: parent.right
        anchors.verticalCenter: titleText.verticalCenter
        text: Copy.t("keys.closeSheet")
        color: Look.muted
        font.pixelSize: Look.caption
      }
    }

    PanelSeparator {}

    Repeater {
      model: root.groups

      delegate: Column {
        id: group
        required property var modelData
        visible: modelData.rows.length > 0
        width: parent ? parent.width : 0
        spacing: Look.gapSm

        SectionHeader {
          text: String(group.modelData.title).toUpperCase()
        }

        Grid {
          id: grid
          readonly property real gap: Look.gapLg
          readonly property real descWidest: root.widest(group.modelData.rows, 1, bodyMetrics)
          readonly property bool twoUp: 2 * (root.keyColumn + grid.descWidest) + 3 * grid.gap <= group.width
          readonly property real descWidth: grid.twoUp
            ? Math.floor((group.width - 2 * root.keyColumn - 3 * grid.gap) / 2)
            : group.width - root.keyColumn - grid.gap

          width: parent.width
          columns: grid.twoUp ? 4 : 2
          columnSpacing: grid.gap
          rowSpacing: Look.gapXs

          Repeater {
            model: group.modelData.rows.length * 2

            delegate: PlainLabel {
              id: cell
              required property int index
              readonly property bool isKey: cell.index % 2 === 0
              readonly property var row: group.modelData.rows[Math.floor(cell.index / 2)]

              width: cell.isKey ? root.keyColumn : grid.descWidth
              text: cell.row ? String(cell.row[cell.isKey ? 0 : 1]) : ""
              color: cell.isKey ? Look.accent : Look.fg
              font.bold: cell.isKey
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
