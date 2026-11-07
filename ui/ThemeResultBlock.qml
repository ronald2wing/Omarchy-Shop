import QtQuick
import qs.Commons
import "../js/themejob.mjs" as ThemeJob

// The last theme job's outcome under the Theme card: one status line (time
// first, then what happened; Details when there are lines behind it, ✕
// dismisses), the "Backup kept" / "Folder copy kept" note of a failed or
// stopped job whose writes may have begun, and the selectable details. The
// wording and tone are js/themejob.mjs's (resultText, resultTone,
// keptText).
//
// Contract: result (themeState.lastResult); targetName (the card's
// target, for a result that names no theme); folder (the linked folder,
// for a result that names none); home; nowMs; detailsOpen (the owner may
// flip it: t); text, hasDetails, keptShown and detailsItem (read back);
// signals dismissed(), detailsToggled() (the Details button flipped
// detailsOpen), detailsFocusReleased() (Esc in the details).
Column {
  id: root

  property var result: null
  property string targetName: ""
  property string folder: ""
  property string home: ""
  property real nowMs: 0
  property bool detailsOpen: false

  signal dismissed()
  signal detailsToggled()
  signal detailsFocusReleased()

  readonly property string text: ThemeJob.resultText(root.result, { targetName: root.targetName, folder: root.folder, home: root.home })
  readonly property var details: ThemeJob.resultDetails(root.result)
  readonly property bool hasDetails: root.details.length > 0
  readonly property string keptText: ThemeJob.keptText(root.result, root.nowMs)
  readonly property bool keptShown: root.keptText !== ""
  readonly property Item detailsItem: detailsBox

  onResultChanged: root.detailsOpen = false

  spacing: Look.gapXs

  StatusLine {
    width: parent.width
    tone: ThemeJob.resultTone(root.result)
    text: root.text
    when: root.result && root.result.at ? Number(root.result.at) : 0
    nowMs: root.nowMs
    dismissable: true
    actions: root.hasDetails ? [{ id: "details", label: root.detailsOpen ? Copy.t("theme.hideDetails") : Copy.t("theme.showDetails") }] : []
    onAction: { root.detailsOpen = !root.detailsOpen; root.detailsToggled() }
    onDismissed: root.dismissed()
  }

  // The card's Backups (n) link and b lead to Backups: no second link.
  PlainLabel {
    visible: root.keptShown
    text: root.keptText
    color: Look.muted
    font.pixelSize: Look.small
  }

  Rectangle {
    id: detailsBox
    visible: root.detailsOpen && root.hasDetails
    width: parent.width
    height: detailsEdit.implicitHeight + Look.gapLg * 2
    radius: Style.cornerRadius
    color: Look.softFill
    border.width: 1
    border.color: Look.hairline

    // Selectable, read-only, plain text: the CLI's cleaned stderr tail, or
    // the per-file problems of a partial push/pull/restore.
    TextEdit {
      id: detailsEdit
      x: Look.gapLg
      y: Look.gapLg
      width: parent.width - Look.gapLg * 2
      textFormat: TextEdit.PlainText
      readOnly: true
      selectByMouse: true
      wrapMode: TextEdit.WrapAnywhere
      text: root.details.join("\n")
      color: Look.muted
      selectionColor: Style.selectionFillFor(Look.fg, Look.accent)
      selectedTextColor: Look.fg
      font.family: Look.fontFamily
      font.pixelSize: Look.caption
      // Esc only dismisses the selection: it is accepted here (so it never
      // reaches the catcher as "back") and key focus goes back to the panel.
      Keys.onEscapePressed: (event) => {
        detailsEdit.deselect()
        detailsEdit.focus = false
        event.accepted = true
        root.detailsFocusReleased()
      }
    }
  }
}
