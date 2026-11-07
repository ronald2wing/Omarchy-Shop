pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/format.mjs" as Format
import "../js/preflight.mjs" as Preflight
import "../js/snapshot.mjs" as Snapshot
import "../js/themes.mjs" as Themes

// The store's Theme block: header with a Backups link, the target line
// (ThemeTargetLine) or the Choose folder… prompt, three actions at most,
// then whichever of these applies: the preview's status, the running job,
// the last result (ThemeResultBlock).
Column {
  id: root

  property var store: null
  property real nowMs: 0
  property string home: ""
  // The service snapshot: js/preflight.mjs reads the CLI, the account and
  // what holds the store from it (factsOf).
  property var snapshot: null

  signal push()
  signal pull()
  signal togglePreview()
  signal openPreview()
  signal backups()
  signal chooseFolder()
  signal dismissThemeResult()
  signal cancelJob()
  // The details text gave up key focus (Esc): the owner hands it back to
  // the panel's key catcher.
  signal detailsFocusReleased()
  // The Details / Hide details button flipped `detailsOpen`: the owner
  // scrolls the box into view (the card has no panel of its own).
  signal detailsToggled()

  readonly property var theme: root.store ? root.store.theme : null
  readonly property bool linked: !!root.theme && !!root.theme.folder
  readonly property var ts: Snapshot.themeState(root.store)
  // What js/preflight.mjs decides from: the same facts the Service reads.
  readonly property var facts: Preflight.factsOf(root.snapshot, root.store)
  readonly property var job: root.ts ? root.ts.job : null
  readonly property var result: root.ts ? root.ts.lastResult : null
  readonly property var preview: root.ts ? root.ts.preview : null
  readonly property var target: Snapshot.targetTheme(root.store)
  // The target's display name: the cached theme name, else what is known
  // ("Live theme" before the list loads, "Theme 1234" for an unknown id).
  readonly property string targetName: Copy.themeName(root.target)
  // Everything Backups lists: theme backups and the folder copies taken
  // before pulls (a stopped pull points there for its copy).
  readonly property int backupCount: root.ts && root.ts.backups
    ? (root.ts.backups.items || []).length + (root.ts.backups.folderCopies || []).length : 0
  readonly property string folderText: root.linked ? Format.homeRelative(root.theme.folder, root.home) : ""
  // Themes.folderState of the linked folder, and the line under it.
  readonly property string folderState: root.linked ? Themes.folderState(root.ts, root.theme.folder) : "unknown"
  readonly property string folderWarning: root.linked ? Copy.folderWarning(root.ts, root.theme.folder) : ""
  // The status dot: ok (usable, or an empty pull target), warn (files, but
  // not a theme), error (can't be used), info (not checked yet).
  readonly property string folderTone: root.folderState === "usable" || root.folderState === "empty" ? "ok"
    : root.folderState === "notTheme" ? "warn"
    : root.folderState === "unknown" ? "info" : "error"
  readonly property string previewStatus: root.preview ? String(root.preview.status || "stopped") : "stopped"
  readonly property bool previewOn: root.previewStatus === "starting" || root.previewStatus === "ready"
  readonly property bool previewBusy: root.previewStatus === "starting" || root.previewStatus === "stopping"
  // The preview's process was killed (terminated): it ended, nothing in
  // the theme failed, so it gets its own line rather than "stopped: Stopped".
  readonly property bool previewKilled: root.previewStatus === "failed" && !!root.preview && !!root.preview.error && root.preview.error.code === "terminated"
  // The LIVE chip shows (the panel smoke reads it).
  readonly property bool liveChipShown: targetRow.liveChipShown
  // The preview status line's text ("" when the line is hidden); the
  // panel smoke reads it.
  readonly property string previewLine: root.previewStatus === "starting" ? Copy.t("theme.preview.starting")
    : root.previewStatus === "ready" ? Copy.t("theme.preview.running", { url: root.preview && root.preview.url ? String(root.preview.url) : "" })
    : root.previewStatus !== "failed" ? ""
    : root.previewKilled ? Copy.t("theme.preview.ended")
    : Copy.t("theme.preview.failed", { error: Copy.errorOf(root.preview ? root.preview.error : null) })
  readonly property bool canPush: root.refusal("push") === ""
  readonly property bool canPull: root.refusal("pull") === ""
  readonly property bool canPreview: root.refusal("preview") === ""
  // A push would change the live theme while the store's opt-in is off.
  readonly property bool liveLocked: Preflight.liveLocked(root.facts, "push")
  readonly property bool resultShown: !!root.result && !root.job
  readonly property bool hasDetails: resultBlock.hasDetails
  readonly property bool keptShown: resultBlock.keptShown
  // The result line's text ("" without a result; the panel smoke reads it).
  readonly property string resultLine: resultBlock.text
  property alias detailsOpen: resultBlock.detailsOpen
  property real tick: Date.now()
  // The failure-details box, for the owner's panel.ensureVisible.
  readonly property Item detailsItem: resultBlock.detailsItem

  // Why `action` (push | pull | preview) is refused right now, or "" when
  // it can run: js/preflight.mjs, the answer the Service gives on accept
  // (push and pull as before their dialog, whose first stage asks for the
  // live opt-in). The disabled buttons, their tooltips and the owner's
  // p/u/d keys all read it. Stopping a running preview always works.
  function refusal(action) {
    if (action === "preview" && root.previewOn) return ""
    var refused = action === "preview" ? Preflight.checkPreview(root.facts) : Preflight.beforeDialog(root.facts, action)
    return refused ? Copy.errorOf(refused.error) : ""
  }

  function tooltip(action) {
    var why = root.refusal(action)
    if (why !== "") return why
    if (action === "push") return root.liveLocked ? Copy.t("theme.tip.locked") : Copy.t("theme.tip.push", { folder: root.folderText, theme: root.targetName })
    if (action === "pull") return Copy.t("theme.tip.pull", { folder: root.folderText, theme: root.targetName })
    return root.previewOn ? Copy.t("theme.stopPreview") : Copy.t("theme.tip.preview")
  }

  function elapsedText(startedAt) {
    return Format.elapsed(Math.max(0, root.tick - Number(startedAt || root.tick)))
  }

  // Lays the result block and the card out now, so a caller that just
  // opened the details box can measure where it landed (positioners
  // otherwise move it on the next polish).
  function layoutDetails() {
    resultBlock.forceLayout()
    root.forceLayout()
  }

  spacing: Look.gapLg

  Timer {
    interval: 1000
    repeat: true
    running: !!root.job
    triggeredOnStart: true
    onTriggered: root.tick = Date.now()
  }

  // Header: THEME … Backups (n) ›
  Item {
    width: parent.width
    height: Math.max(sectionHeader.implicitHeight, backupsLink.implicitHeight)

    SectionHeader {
      id: sectionHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: Copy.t("theme.section").toUpperCase()
    }

    Button {
      id: backupsLink
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Copy.t("theme.backupsLink", { n: root.backupCount })
      fontSize: Look.small
      horizontalPadding: Style.spacing.md
      verticalPadding: Style.spacing.xxs
      tooltipText: Copy.t("theme.tip.backups")
      onClicked: root.backups()
    }
  }

  // No folder yet: one sentence and the only folder CTA on the screen.
  Row {
    visible: !root.linked
    width: parent.width
    spacing: Look.gapLg

    PlainLabel {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - chooseButton.width - parent.spacing
      text: Copy.t("theme.noFolder")
      color: Look.muted
      wrapMode: Text.WordWrap
    }

    SmallButton {
      id: chooseButton
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰉋"
      text: Copy.t("theme.chooseFolder")
      verticalPadding: Style.spacing.controlPaddingY
      onClicked: root.chooseFolder()
    }
  }

  ThemeTargetLine {
    id: targetRow
    visible: root.linked
    width: parent.width
    targetName: root.targetName
    // Only beside a real theme name: the "Live theme" placeholder (list not
    // loaded yet) already says it.
    showLive: root.target.live && !!root.target.name
    locked: root.liveLocked
    folderText: root.folderText
    folderTone: root.folderTone
    folderWarning: root.folderWarning
  }

  // Actions: at most three, on one row with fixed labels (the target name
  // is on the line above and in the push tooltip, so a long theme name can
  // never wrap the row). Disabled, never hidden; the tooltip says why.
  Row {
    visible: root.linked
    width: parent.width
    spacing: Look.gapMd

    SmallButton {
      iconText: "󰕒"
      text: Copy.t("theme.push")
      verticalPadding: Style.spacing.controlPaddingY
      enabled: root.canPush
      opacity: enabled ? 1 : Look.disabledOpacity
      tooltipText: root.tooltip("push")
      onClicked: root.push()
    }

    SmallButton {
      iconText: "󰇚"
      text: Copy.t("theme.pullInto")
      verticalPadding: Style.spacing.controlPaddingY
      enabled: root.canPull
      opacity: enabled ? 1 : Look.disabledOpacity
      tooltipText: root.tooltip("pull")
      onClicked: root.pull()
    }

    SmallButton {
      iconText: root.previewBusy ? "󰑓" : "󰐊"
      iconSpinning: root.previewBusy
      text: Copy.t("theme.preview")
      verticalPadding: Style.spacing.controlPaddingY
      selected: root.previewOn
      // Stopping a running preview never needs the CLI check.
      enabled: root.previewOn || root.canPreview
      opacity: enabled ? 1 : Look.disabledOpacity
      tooltipText: root.tooltip("preview")
      onClicked: root.togglePreview()
    }
  }

  // Preview status, only while it says something: starting, ready, failed.
  StatusLine {
    visible: root.linked && (root.previewStatus === "starting" || root.previewStatus === "ready" || root.previewStatus === "failed")
    width: parent.width
    tone: root.previewKilled ? "warn" : root.previewStatus === "failed" ? "error" : "info"
    icon: root.previewStatus === "starting" ? "󰔟" : (root.previewStatus === "failed" ? "" : "󰐊")
    text: root.previewLine
    actions: root.previewStatus === "ready" ? [{ id: "open", label: Copy.t("action.open") }, { id: "stop", label: Copy.t("theme.stopPreview") }]
      : root.previewStatus === "starting" ? [{ id: "stop", label: Copy.t("theme.stopPreview") }] : []
    onAction: (id) => { if (id === "open") root.openPreview(); else root.togglePreview() }
  }

  // Running job.
  StatusLine {
    visible: !!root.job
    width: parent.width
    tone: "info"
    icon: "󰔟"
    text: root.job ? Copy.t("theme.running", { action: Copy.t("job." + root.job.action), elapsed: root.elapsedText(root.job.startedAt) })
      + (root.job.name ? " · " + root.job.name : "") : ""
    actions: [{ id: "cancel", label: Copy.t("action.cancel") }]
    onAction: root.cancelJob()
  }

  ThemeResultBlock {
    id: resultBlock
    visible: root.resultShown
    width: parent.width
    result: root.result
    targetName: root.targetName
    folder: root.theme && root.theme.folder ? String(root.theme.folder) : ""
    home: root.home
    nowMs: root.nowMs
    onDismissed: root.dismissThemeResult()
    onDetailsToggled: root.detailsToggled()
    onDetailsFocusReleased: root.detailsFocusReleased()
  }
}
