import QtQuick
import qs.Commons
import "../js/format.mjs" as Format

// One theme backup, on two lines:
//   Today 11:35  LIVE                                        [Restore…]
//   Dawn · before push · 4 files · 47 KB
// or one folder copy taken before a pull ("Today 11:35" / "4 files · 47 KB"
// [Open folder]; the copy's path is where Open folder goes). A LIVE chip
// marks a backup whose restore counts as live (Themes.restoreIsLive: the
// restore dialog then asks about the live theme). The detail line wraps
// instead of eliding, so what the backup preceded and how big it is are
// readable before choosing Restore; rows align on their left edge.
//
// Contract: row; folderCopy; live (backup rows only); nowMs; selected and the signals
// activated(), hoveredRow() come from ListRow.
ListRow {
  id: root

  // backup: {id, at, theme {id, name, role}, before: push|restore, files, bytes}
  // folder copy: {id, at, path, files?, bytes}
  property var row: null
  property bool folderCopy: false
  // Restoring it counts as a live change (Themes.restoreIsLive).
  property bool live: false
  property real nowMs: 0

  readonly property string whenText: root.row ? Format.backupWhen(root.row.at, root.nowMs) : ""
  readonly property string detailText: {
    if (!root.row) return ""
    var files = Copy.filesText(Number(root.row.files) || 0)
    var bytes = Format.bytes(Number(root.row.bytes))
    if (root.folderCopy) return Copy.t("backups.folderCopyRow", { files: files, bytes: bytes })
    var theme = root.row.theme || {}
    var name = Copy.themeName(theme)
    var before = root.row.before === "restore" ? Copy.t("job.noun.restore") : Copy.t("job.noun.push")
    return Copy.t("backups.row", { theme: name, before: before, files: files, bytes: bytes })
  }

  implicitHeight: Math.max(lines.implicitHeight, actionButton.implicitHeight) + Style.spacing.md * 2

  Accessible.name: root.whenText + ", " + root.detailText + (root.live ? ", " + Copy.t("theme.liveChip") : "")

  Column {
    id: lines
    anchors.left: parent.left
    anchors.leftMargin: Look.rowPadX
    anchors.right: actionButton.left
    anchors.rightMargin: Look.gapLg
    anchors.verticalCenter: parent.verticalCenter
    spacing: Look.gapXs

    // Line 1: when, and the LIVE chip.
    Row {
      spacing: Look.gapMd

      PlainLabel {
        text: root.whenText
        font.bold: root.selected
      }

      LiveChip {
        visible: root.live
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Line 2: theme · before push · files · bytes (or files · bytes).
    PlainLabel {
      width: parent.width
      text: root.detailText
      color: Look.muted
      font.pixelSize: Look.small
      wrapMode: Text.WordWrap
    }
  }

  SmallButton {
    id: actionButton
    anchors.right: parent.right
    anchors.rightMargin: Look.rowPadX
    anchors.verticalCenter: parent.verticalCenter
    text: root.folderCopy ? Copy.t("backups.openFolder") : Copy.t("backups.restore")
    verticalPadding: Style.spacing.xxs
    onClicked: root.activated()
  }
}
