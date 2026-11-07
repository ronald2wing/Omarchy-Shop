pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/keymap.mjs" as Keymap
import "../js/preflight.mjs" as Preflight
import "../js/urls.mjs" as Urls

// Settings in four groups, one row style (label column, trailing control):
// Alerts, Bar, Shopify (CLI and account), About. Every consequential action
// (install, sign out, reset) goes through the panel's confirmation.
PanelView {
  id: root

  readonly property var settings: root.snapshot && root.snapshot.settings ? root.snapshot.settings : ({ pollSeconds: 60, alerts: { notify: true, sound: true }, bar: { display: "stores" } })
  readonly property var alerts: root.settings.alerts || ({ notify: true, sound: true })
  readonly property string display: root.settings.bar && root.settings.bar.display ? root.settings.bar.display : "stores"
  readonly property int savedPoll: Number(root.settings.pollSeconds) || 60
  readonly property var health: root.snapshot && root.snapshot.alertTools ? root.snapshot.alertTools : ({})
  readonly property var cli: root.snapshot && root.snapshot.cli ? root.snapshot.cli : ({ status: "unknown" })
  readonly property string cliStatus: String(root.cli.status || "unknown")
  readonly property var pins: root.snapshot && root.snapshot.pins ? root.snapshot.pins : ({})
  readonly property var account: root.snapshot && root.snapshot.account ? root.snapshot.account : ({ status: "unknown" })
  readonly property string accountStatus: String(root.account.status || "unknown")
  // A failed sign-in, sign-out or session check (status "unknown" + error).
  readonly property var accountError: root.accountStatus === "unknown" && root.account.error ? root.account.error : null
  // The view's keys (js/keymap.mjs); Settings has no text keys.
  keymap: Keymap.settings({ broken: root.configInvalid })
  readonly property string home: root.panel ? root.panel.home : ""
  readonly property var displayOptions: [
    { value: "stores", label: Copy.t("settings.bar.stores") },
    { value: "total", label: Copy.t("settings.bar.total") },
    { value: "icon", label: Copy.t("settings.bar.icon") }
  ]

  readonly property bool canCopyCommand: root.cliStatus === "missing" || root.cliStatus === "install_failed"
  // "copy" (the Copy command button) is a stop of its own while it shows.
  // While config.json is unreadable the alert, bar and refresh rows are
  // hidden (their values would be Config's defaults, not the user's, and
  // every write is refused): the cursor skips them. Send test writes
  // nothing and stays.
  // Every row, top to bottom; rowIds is the ones showing.
  readonly property var allRowIds: ["notify", "sound", "test", "barShows", "poll", "cli", "copy", "account", "configPath", "statePath", "keys", "reset"]
  readonly property var rowIds: root.allRowIds.filter(function(id) {
    if (id === "notify" || id === "sound" || id === "barShows" || id === "poll") return !root.configInvalid
    if (id === "copy") return root.canCopyCommand
    if (id === "reset") return root.configInvalid
    return true
  })
  // The cursor stays on its row when rows come and go (the Copy command
  // button, Reset, the alert rows while config.json is unreadable); a row
  // that left hands it to the nearest showing row above it.
  property alias cursorId: cursor.rowId
  readonly property int cursorIndex: cursor.rowIndex
  RowCursor {
    id: cursor
    ids: root.rowIds
    order: root.allRowIds
    rowId: "notify"
    view: root
    panel: root.panel
  }

  function patch(obj) {
    // Backstop for a click that reaches a hidden row: the write would be
    // refused anyway; say why without asking the service.
    if (root.configInvalid) { root.panel.showToast(Copy.t("error.config_invalid")); return }
    if (root.service) root.panel.run(root.service.updateSettings(JSON.stringify(obj)))
  }

  function toggleNotify() { root.patch({ alerts: { notify: !root.alerts.notify } }) }
  // The sound toggle is unavailable (greyed out) while alerts are off.
  function toggleSound() { if (root.alerts.notify) root.patch({ alerts: { sound: !root.alerts.sound } }) }
  function sendTest() { if (root.service) root.panel.run(root.service.sendTestAlert()) }

  function setDisplay(v) {
    if (v !== root.display) root.patch({ bar: { display: v } })
  }

  // The index of the saved bar display among displayOptions (-1 unknown).
  function displayIndex() {
    for (var i = 0; i < root.displayOptions.length; i++) if (root.displayOptions[i].value === root.display) return i
    return -1
  }

  function stepDisplay(delta) {
    var next = Math.max(0, Math.min(root.displayOptions.length - 1, Math.max(0, root.displayIndex()) + delta))
    root.setDisplay(root.displayOptions[next].value)
  }

  function cliAction() {
    if (!root.service) return
    if (root.canCopyCommand) root.panel.confirm({ action: "installCli" })
    else if (root.cliStatus === "installing") root.panel.run(root.service.cancelInstall())
  }

  function accountAction() {
    // Enter does what the account button does, and the button is hidden
    // until the CLI is ready (Preflight.requireCli, which the service
    // checks on sign-in and sign-out).
    if (!root.service || Preflight.requireCli(Preflight.factsOf(root.snapshot, null))) return
    if (root.accountStatus === "signed_in") root.panel.confirm({ action: "signOut" })
    else if (root.accountStatus === "signing_in") root.panel.run(root.service.cancelSignIn())
    else if (root.accountStatus !== "signing_out") root.panel.run(root.service.signIn())
  }

  function copyCommand() {
    root.panel.copyText(Copy.t("confirm.install.command", { cli: root.pins.cli, node: root.pins.node }))
  }

  // which: "config" | "state". They open as the two file URLs Urls allows
  // (no store).
  function openPath(which) {
    root.panel.openUrl(which === "state" ? Urls.stateDirUrl(root.home) : Urls.configFileUrl(root.home), "")
  }

  function cliText() {
    if (root.cliStatus === "ready") return Copy.t("settings.cli.ready", { cli: root.pins.cli, node: root.pins.node })
    if (root.cliStatus === "missing") return Copy.t("settings.cli.missing")
    if (root.cliStatus === "installing") return Copy.t("banner.installing.title")
    if (root.cliStatus === "install_failed") return Copy.errorOf(root.cli.error)
    // An account check that failed says why (Account re-runs it by itself);
    // "Checking…" is only for a check that is actually running.
    if (root.cliStatus === "unknown" && root.cli.error) return Copy.errorOf(root.cli.error)
    return Copy.t("status.checking")
  }

  function accountText() {
    if (root.accountStatus === "signed_in") return Copy.t("status.signedIn")
    if (root.accountStatus === "signing_in") return Copy.t("banner.signingIn.title")
    if (root.accountStatus === "signing_out") return "…"
    if (root.accountStatus === "signed_out") return Copy.t("status.signedOut")
    // Nothing probes the account until the CLI exists: "Checking…" is only
    // for an account check that is actually running.
    if (root.cliStatus === "missing" || root.cliStatus === "installing" || root.cliStatus === "install_failed") return Copy.t("settings.account.needsCli")
    if (root.accountError) return Copy.t("settings.account.error", { error: Copy.errorOf(root.accountError) })
    return Copy.t("status.checking")
  }

  // ----- keyboard (called by ShopPanel) -----
  function itemFor(id) {
    if (id === "notify") return notifyRow
    if (id === "sound") return soundRow
    if (id === "test") return testRow
    if (id === "barShows") return barRow
    if (id === "poll") return pollRow
    if (id === "cli" || id === "copy") return cliRow
    if (id === "account") return accountRow
    if (id === "configPath") return configRow
    if (id === "statePath") return stateRow
    if (id === "keys") return keysRow
    return resetRow
  }
  function moveCursor(dx, dy) {
    if (dx !== 0 && root.cursorId === "barShows") { root.stepDisplay(dx); return }
    cursor.moveBy(dy)
  }
  function activate() {
    var id = root.cursorId
    if (id === "notify") root.toggleNotify()
    else if (id === "sound") root.toggleSound()
    else if (id === "test") root.sendTest()
    else if (id === "barShows") root.stepDisplay(1)
    else if (id === "poll") pollField.focusField()
    else if (id === "cli") root.cliAction()
    else if (id === "copy") root.copyCommand()
    else if (id === "account") root.accountAction()
    else if (id === "configPath") root.openPath("config")
    else if (id === "statePath") root.openPath("state")
    else if (id === "keys") root.openKeys()
    else if (id === "reset") { root.panel.confirm({ action: "resetConfig" }) }
  }

  // The panel's key sheet (the same one `?` opens).
  function openKeys() {
    root.panel.showKeys()
  }

  spacing: Look.gapLg

  ViewHeader {
    width: parent.width
    canGoBack: true
    title: Copy.t("action.settings")
    onBack: root.panel.pop()
  }

  // ----- Alerts -----
  SectionHeader { text: Copy.t("settings.alerts") }

  StatusLine {
    visible: root.configInvalid
    width: parent.width
    tone: "warn"
    text: Copy.t("settings.needsConfig")
  }

  ToggleRow {
    id: notifyRow
    visible: !root.configInvalid
    width: parent.width
    label: Copy.t("settings.notify")
    help: Copy.t("settings.notify.help")
    checked: !!root.alerts.notify
    selected: root.cursorId === "notify"
    onHoveredRow: cursor.moveTo("notify")
    onToggled: root.toggleNotify()
  }

  ToggleRow {
    id: soundRow
    visible: !root.configInvalid
    width: parent.width
    label: Copy.t("settings.sound")
    help: Copy.t("settings.sound.help")
    checked: !!root.alerts.sound
    selected: root.cursorId === "sound"
    dimmed: !root.alerts.notify
    onHoveredRow: cursor.moveTo("sound")
    onToggled: root.toggleSound()
  }

  ValueRow {
    id: testRow
    width: parent.width

    SmallButton {
      iconText: "󰂚"
      text: Copy.t("settings.sendTestAlert")
      hasCursor: root.cursorId === "test"
      onHovered: (h) => { if (h) cursor.moveTo("test") }
      onClicked: root.sendTest()
    }
  }

  StatusLine {
    visible: root.health.notify === false
    width: parent.width
    tone: "info"
    text: Copy.t("settings.notify.missing")
  }

  StatusLine {
    visible: root.health.sound === false
    width: parent.width
    tone: "info"
    text: Copy.t("settings.sound.missing")
  }

  // ----- Bar -----
  SectionHeader {
    visible: !root.configInvalid
    text: Copy.t("settings.bar")
  }

  ValueRow {
    id: barRow
    visible: !root.configInvalid
    width: parent.width
    label: Copy.t("settings.bar.shows")
    lit: root.cursorId === "barShows"

    ButtonGroup {
      anchors.verticalCenter: parent.verticalCenter
      focusable: false
      fontSize: Look.small
      spacing: Look.gapXs
      options: root.displayOptions
      value: root.display
      cursorIndex: root.cursorId === "barShows" ? root.displayIndex() : -1
      onChanged: (v) => root.setDisplay(v)
      onHovered: (index, isHovered) => { if (isHovered) cursor.moveTo("barShows") }
    }
  }

  // Refresh every 30–3600 s, in steps of 10 (StepperField: the debounced
  // save, Enter, Esc and the save on leaving Settings).
  ValueRow {
    id: pollRow
    visible: !root.configInvalid
    width: parent.width
    label: Copy.t("settings.poll")
    lit: root.cursorId === "poll"

    StepperField {
      id: pollField
      anchors.verticalCenter: parent.verticalCenter
      value: root.savedPoll
      min: 30
      max: 3600
      step: 10
      unit: Copy.t("settings.poll.unit")
      hasCursor: root.cursorId === "poll"
      paste: root.panel ? root.panel.paste : null
      accessibleName: Copy.t("settings.poll")
      lessName: Copy.t("settings.poll.less")
      moreName: Copy.t("settings.poll.more")
      onCommitted: (v) => root.patch({ pollSeconds: v })
      onReleased: if (root.panel) root.panel.restoreFocus()
    }
  }

  // ----- Shopify -----
  SectionHeader { text: Copy.t("settings.shopify") }

  ValueRow {
    id: cliRow
    width: parent.width
    label: Copy.t("settings.cli")
    lit: root.cursorId === "cli" || root.cursorId === "copy"
    value: root.cliText()
    valueColor: root.cliStatus === "install_failed" ? Look.negative : (root.cliStatus === "missing" ? Look.warn : Look.fg)
    valueWraps: true
    valueMaxLines: 2

    trailing: [
      SmallButton {
        visible: root.canCopyCommand || root.cliStatus === "installing"
        text: root.cliStatus === "installing" ? Copy.t("action.cancel")
          : (root.cliStatus === "install_failed" ? Copy.t("action.retry") : Copy.t("action.install"))
        hasCursor: root.cursorId === "cli"
        onHovered: (h) => { if (h) cursor.moveTo("cli") }
        onClicked: root.cliAction()
      },
      SmallButton {
        visible: root.canCopyCommand
        text: Copy.t("settings.copyCommand")
        tooltipText: Copy.t("settings.copyCommand.tip")
        Accessible.name: Copy.t("settings.copyCommand.tip")
        hasCursor: root.cursorId === "copy"
        onHovered: (h) => { if (h) cursor.moveTo("copy") }
        onClicked: root.copyCommand()
      }
    ]
  }

  ValueRow {
    id: accountRow
    width: parent.width
    label: Copy.t("settings.account")
    lit: root.cursorId === "account"
    value: root.accountText()
    valueColor: root.accountError ? Look.negative : (root.accountStatus === "signed_in" ? Look.fg : Look.muted)
    valueElide: Text.ElideNone
    valueWraps: true
    // The row keeps the button's height while it is hidden.
    minHeight: accountButton.implicitHeight

    trailing: [
      SmallButton {
        id: accountButton
        visible: root.cliStatus === "ready" && root.accountStatus !== "signing_out"
        text: root.accountStatus === "signed_in" ? Copy.t("settings.signOut")
          : root.accountStatus === "signing_in" ? Copy.t("action.cancel")
          : root.accountError ? Copy.t("action.retry")
          : Copy.t("action.signIn")
        hasCursor: root.cursorId === "account"
        onHovered: (h) => { if (h) cursor.moveTo("account") }
        onClicked: root.accountAction()
      }
    ]
  }

  // ----- About -----
  SectionHeader { text: Copy.t("settings.about") }

  ValueRow {
    width: parent.width
    label: Copy.t("settings.version.label")
    value: Copy.t("settings.version", { version: root.service && root.service.version ? String(root.service.version) : "" })
  }

  ValueRow {
    id: configRow
    width: parent.width
    label: Copy.t("settings.configPath")
    lit: root.cursorId === "configPath"
    value: "~" + Urls.CONFIG_REL
    valueElide: Text.ElideMiddle

    trailing: [
      SmallButton {
        text: Copy.t("action.open")
        hasCursor: root.cursorId === "configPath"
        onHovered: (h) => { if (h) cursor.moveTo("configPath") }
        onClicked: root.openPath("config")
      }
    ]
  }

  ValueRow {
    id: stateRow
    width: parent.width
    label: Copy.t("settings.statePath")
    lit: root.cursorId === "statePath"
    value: "~" + Urls.STATE_REL
    valueElide: Text.ElideMiddle

    trailing: [
      SmallButton {
        text: Copy.t("action.open")
        hasCursor: root.cursorId === "statePath"
        onHovered: (h) => { if (h) cursor.moveTo("statePath") }
        onClicked: root.openPath("state")
      }
    ]
  }

  ValueRow {
    id: keysRow
    width: parent.width

    SmallButton {
      iconText: "󰌌"
      text: Copy.t("settings.keys")
      hasCursor: root.cursorId === "keys"
      onHovered: (h) => { if (h) cursor.moveTo("keys") }
      onClicked: root.openKeys()
    }
  }

  // Reset config: offered only while config.json cannot be used.
  Item {
    id: resetRow
    visible: root.configInvalid
    width: parent.width
    height: Math.max(resetText.implicitHeight, resetButton.implicitHeight)

    PlainLabel {
      id: resetText
      anchors.left: parent.left
      anchors.right: resetButton.left
      anchors.rightMargin: Look.gapLg
      anchors.verticalCenter: parent.verticalCenter
      text: Copy.t("settings.resetConfig.help")
      color: Look.warn
      font.pixelSize: Look.small
      wrapMode: Text.WordWrap
    }

    SmallButton {
      id: resetButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Copy.t("settings.resetConfig")
      foreground: Look.negative
      accent: Look.negative
      hasCursor: root.cursorId === "reset"
      onHovered: (h) => { if (h) cursor.moveTo("reset") }
      onClicked: root.panel.confirm({ action: "resetConfig" })
    }
  }
}
