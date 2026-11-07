pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/format.mjs" as Format

// One outcome or state on a single line: icon · [time ·] text · small
// trailing buttons · optional ✕. Used for theme results (ThemeCard), the
// store's rate-limit notice, Add's status row and Home's invalid-entry
// lines.
//
// Contract:
//   tone        ok | info | warn | error (colours the icon; text stays fg)
//   icon        glyph; "" takes the tone's default (✓ 󰋽 󰀦 ✕)
//   text        the message (PlainText, wraps)
//   when        ms; > 0 renders "just now · " / "2 min ago · " first
//   nowMs       the clock `when` is measured against (set it with `when`)
//   actions     [{id, label}] rendered as small bordered buttons
//   dismissable shows the ✕ button
//   signals     action(id), dismissed()
// Examples:
//   ok    "✓ just now · Pulled Dawn into ~/work/acme" [✕]
//   error "✕ 2 min ago · Push failed: …" [Details] [✕]
//   warn  "󰀦 Stopped. Some files may already be on Dawn…" [Backups] [✕]
//   info  "󰔟 Pushing… 0:42" [Cancel]
Item {
  id: root

  property string tone: "info"
  property string icon: ""
  property string text: ""
  property real when: 0
  property real nowMs: 0
  property var actions: []
  property bool dismissable: false

  signal action(string id)
  signal dismissed()

  readonly property color toneColor: Look.toneColor(root.tone)
  readonly property string glyph: root.icon !== "" ? root.icon : Look.toneGlyph(root.tone)
  readonly property string ago: root.when > 0 ? Format.timeAgo(root.when, root.nowMs) : ""
  readonly property string line: (root.ago !== "" ? root.ago + " · " : "") + root.text

  implicitHeight: Math.max(message.implicitHeight, trailing.implicitHeight, glyphLabel.implicitHeight)

  Accessible.role: Accessible.StaticText
  Accessible.name: root.line

  PlainLabel {
    id: glyphLabel
    anchors.left: parent.left
    anchors.top: parent.top
    text: root.glyph
    color: root.toneColor
    // Keeps the column steady whichever glyph a tone draws.
    width: Style.space(16)
  }

  PlainLabel {
    id: message
    anchors.left: glyphLabel.right
    anchors.leftMargin: Look.gapSm
    anchors.right: trailing.left
    anchors.rightMargin: trailing.visible ? Look.gapLg : 0
    anchors.top: parent.top
    text: root.line
    font.pixelSize: Look.small
    wrapMode: Text.WordWrap
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.top: parent.top
    visible: root.actions.length > 0 || root.dismissable
    spacing: Look.gapSm

    ActionButtons {
      visible: root.actions.length > 0
      spacing: Look.gapSm
      actions: root.actions
      horizontalPadding: Style.spacing.md
      verticalPadding: Style.spacing.xxs
      onActionPicked: (id) => root.action(id)
    }

    PanelActionButton {
      visible: root.dismissable
      iconText: "󰅖"
      tooltipText: Copy.t("action.dismiss")
      size: Style.space(20)
      onClicked: root.dismissed()
      Accessible.role: Accessible.Button
      Accessible.name: Copy.t("action.dismiss")
      Accessible.onPressAction: root.dismissed()
    }
  }
}
