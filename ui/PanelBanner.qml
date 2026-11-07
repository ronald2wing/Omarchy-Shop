pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../js/banner.mjs" as Banner

// The one banner at the top of the panel: a tone-tinted frame with icon,
// title, a body of at most three lines, an optional spinner and kit
// buttons, and what those buttons do. Which banner shows is the pure rule
// in js/banner.mjs; account, CLI, limit and config states appear here and
// only here (store rows show "—" instead of repeating it).
//
// Contract: panel (ShopPanel: openConfigFile(), confirm(), run());
// service; snapshot; nowMs; spec (the bannerFor result, null while none);
// actions (its buttons, reassigned only when they change); run(id).
// The frame is an AlertMessage named by its title and body.
Rectangle {
  id: root

  property var panel: null
  property var service: null
  property var snapshot: ({})
  property real nowMs: 0
  // The config write error the user dismissed (JSON), so it stays hidden
  // until a different one comes.
  property string dismissedWriteError: ""

  readonly property var spec: root.service ? Banner.bannerFor(root.snapshot, root.nowMs, root.dismissedWriteError) : null
  readonly property string tone: root.spec ? root.spec.tone : "info"
  readonly property string title: root.spec ? root.spec.title : ""
  readonly property string body: root.spec ? root.spec.body : ""
  readonly property bool busy: !!root.spec && root.spec.busy

  // `spec` is a new object on every snapshot publish (up to 4/s), and a
  // reassigned JS-array model makes the Repeater rebuild its buttons,
  // losing a click in progress, hover and focus. So `actions` is
  // reassigned only when the ids or labels change.
  property var actions: []
  readonly property var specActions: root.spec ? root.spec.actions : []
  readonly property string actionsKey: {
    var a = root.specActions
    var parts = []
    for (var i = 0; i < a.length; i++) parts.push(String(a[i].id) + "\u001f" + String(a[i].label))
    return parts.join("\u001e")
  }
  onActionsKeyChanged: root.actions = root.specActions
  Component.onCompleted: root.actions = root.specActions

  function run(id) {
    if (id === "openConfig") root.panel.openConfigFile()
    else if (id === "resetConfig") root.panel.confirm({ action: "resetConfig" })
    else if (id === "dismissWriteError") {
      root.dismissedWriteError = JSON.stringify(root.snapshot.configWriteError)
      root.service.dismissConfigWriteError()
    }
    else if (id === "install") root.panel.confirm({ action: "installCli" })
    else if (id === "cancelInstall") root.panel.run(root.service.cancelInstall())
    else if (id === "cancelSignIn") root.panel.run(root.service.cancelSignIn())
    else if (id === "retryCheck") root.panel.run(root.service.refresh())
    else if (id === "signIn") root.panel.run(root.service.signIn())
    else if (id === "resignIn") {
      // Sign out, then sign in: Account queues the sign-in behind a running
      // sign-out, so no flag outlives this click.
      var out = root.panel.run(root.service.signOut())
      if (!out || out.ok !== false) root.panel.run(root.service.signIn())
    }
  }

  readonly property color toneColor: Look.toneColor(root.tone)

  visible: !!root.spec
  implicitHeight: content.implicitHeight + Look.gapLg * 2
  radius: Style.cornerRadius
  color: Util.alpha(root.toneColor, 0.08)
  border.width: 1
  border.color: Util.alpha(root.toneColor, 0.45)

  Accessible.role: Accessible.AlertMessage
  Accessible.name: root.title + (root.body !== "" ? ". " + root.body : "")

  Row {
    id: content
    x: Look.rowPadX
    y: Look.gapLg
    width: parent.width - Look.rowPadX * 2
    spacing: Look.gapLg

    PlainLabel {
      id: glyph
      text: root.busy ? "󰑓" : Look.toneGlyph(root.tone)
      color: root.toneColor
      font.pixelSize: Look.title
      transformOrigin: Item.Center

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: Style.duration(1100)
        loops: Animation.Infinite
        running: root.busy && !Style.reduceMotion
      }
    }

    Column {
      width: parent.width - glyph.width - parent.spacing
      spacing: Look.gapXs

      PlainLabel {
        width: parent.width
        text: root.title
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      PlainLabel {
        visible: root.body !== ""
        width: parent.width
        text: root.body
        color: Look.muted
        font.pixelSize: Look.small
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      ActionButtons {
        visible: root.actions.length > 0
        width: parent.width
        topPadding: Look.gapXs
        actions: root.actions
        onActionPicked: (id) => root.run(id)
      }
    }
  }
}
