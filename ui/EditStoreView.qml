pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../js/format.mjs" as Format
import "../js/keymap.mjs" as Keymap
import "../js/errors.mjs" as Errors
import "../js/snapshot.mjs" as Snapshot

// Edit one store, in groups: Store (name; the domain is fixed), Theme
// (folder, target, live pushes), Bar, Sales access, Danger. Changes save as
// they are made. j/k and Tab walk the rows; Esc in a field reverts it.
//
// Contract: PanelView (snapshot, service, panel); domain; signals back(),
// removeRequested(), chooseFolderRequested(). Keyboard entry points called
// by ShopPanel: moveCursor, activate, textKey, dropHiddenInput; popupOpen.
PanelView {
  id: root

  property string domain: ""

  signal removeRequested()
  signal back()
  signal chooseFolderRequested()

  readonly property var store: Snapshot.storeOf(root.snapshot, root.domain)
  readonly property var theme: root.store ? root.store.theme : null
  readonly property var ts: Snapshot.themeState(root.store)
  readonly property var themes: root.ts ? root.ts.themes : null
  readonly property var folder: root.ts ? root.ts.folder : null
  readonly property string access: root.store ? String(root.store.salesAccess || "unknown") : "unknown"
  readonly property string home: root.panel ? root.panel.home : ""
  readonly property bool themesFailed: !!root.themes && root.themes.status === "error"
  // A rate-limited list is not a failure: ThemeInfo fetches it again by
  // itself once Shopify allows it.
  readonly property bool themesLimited: root.themesFailed && !!root.themes.error && Errors.isRateLimit(root.themes.error.code)
  // The target list is open: the panel leaves the keys to it.
  readonly property bool popupOpen: targetDropdown.popupOpen
  // The view's keys (js/keymap.mjs).
  keymap: Keymap.edit({ broken: root.configInvalid })

  // Rows walked by j/k and Tab, top to bottom.
  readonly property var rowIds: ["name", "folder", "target", "allowLive", "showInBar", "access", "remove"]
  property alias cursorId: cursor.rowId
  readonly property int cursorIndex: cursor.rowIndex
  RowCursor {
    id: cursor
    ids: root.rowIds
    rowId: "name"
    view: root
    panel: root.panel
  }
  property string savedField: ""
  // A refused save under its field: field (name|folder) -> the error
  // ({code, message}), rendered with Copy.errorOf.
  property var fieldErrors: ({})
  // The saved theme target ("live" or a theme id).
  readonly property string target: root.theme ? String(root.theme.target || "live") : "live"

  // The target picker's rows (Copy.themeTargetOptions).
  readonly property var targetOptions: Copy.themeTargetOptions(root.ts, root.target)

  // config.json broke under the form (now hidden): revert the editable
  // fields and let go of the keyboard, so nothing typed meanwhile is saved
  // as the name or folder once the file reads again.
  function dropHiddenInput() {
    nameField.revertAndBlur()
    folderField.revertAndBlur()
  }
  // config.json reads again: a refusal from before ("needs fixing first")
  // no longer applies; the fields show the stored values again.
  onConfigInvalidChanged: {
    if (root.configInvalid) root.dropHiddenInput()
    else root.fieldErrors = ({})
  }

  function flashSaved(field) {
    root.savedField = field
    savedTimer.restart()
  }

  // A save's result for field (name|folder): its refusal under the field,
  // or the Saved flash.
  function applySave(field, res) {
    var errors = Object.assign({}, root.fieldErrors)
    if (res && res.ok === false) errors[field] = res.error || {}
    else delete errors[field]
    root.fieldErrors = errors
    if (!res || res.ok !== false) root.flashSaved(field)
  }

  // The refusal shown under field, or "".
  function errorText(field) {
    var e = root.fieldErrors[field]
    return e ? Copy.errorOf(e) : ""
  }

  function setTheme(patch) {
    if (root.service) root.panel.run(root.service.updateStore(root.domain, JSON.stringify({ theme: patch })))
  }

  function toggleAllowLive() {
    root.setTheme({ allowLive: !(root.theme && root.theme.allowLive) })
  }

  function toggleShowInBar() {
    if (root.service) root.panel.run(root.service.updateStore(root.domain, JSON.stringify({ showInBar: !(root.store && root.store.showInBar) })))
  }

  function reloadThemes() {
    if (root.service) root.service.listThemes(root.domain)
  }

  // Tab / Shift+Tab out of a field: the cursor moves to the neighbouring
  // row, and lands in its field when that row has one.
  function tabFrom(id, direction) {
    if (root.rowIds.indexOf(id) < 0) return
    cursor.rowId = cursor.neighbour(id, direction)
    if (cursor.rowId === "name") nameField.focusField()
    else if (cursor.rowId === "folder") folderField.focusField()
    else root.panel.restoreFocus()
    cursor.reveal()
  }

  // ----- keyboard (called by ShopPanel) -----
  function moveCursor(dx, dy) {
    if (root.configInvalid) return
    cursor.moveBy(dy)
  }
  function itemFor(id) {
    if (id === "name") return nameField
    if (id === "folder") return folderField
    if (id === "target") return targetRow
    if (id === "allowLive") return allowLiveRow
    if (id === "showInBar") return showInBarRow
    if (id === "access") return accessRow
    return removeButton
  }
  function activate() {
    if (root.configInvalid) return
    var id = root.cursorId
    if (id === "name") nameField.focusField()
    else if (id === "folder") folderField.focusField()
    else if (id === "target") {
      // A failed theme load leaves only "Live theme" to pick: Enter retries
      // (a rate-limited one is retried by ThemeInfo itself: Enter opens).
      if (root.themesFailed && !root.themesLimited) root.reloadThemes()
      else targetDropdown.open()
    }
    else if (id === "allowLive") root.toggleAllowLive()
    else if (id === "showInBar") root.toggleShowInBar()
    else if (id === "access") { root.panel.toggleAccess(root.domain) }
    else if (id === "remove") root.removeRequested()
  }
  function textKey(t) {
    var row = Keymap.rowForKey(root.keymap, t)
    if (!row || root.configInvalid) return
    // While Shopify limits the theme list, r says so instead of doing
    // nothing (the list retries itself once it is allowed).
    if (row.id === "reload") {
      if (!root.themesLimited) root.reloadThemes()
      else root.panel.showToast(Copy.t("edit.themesWaiting"))
      return
    }
  }

  Component.onCompleted: {
    if (!root.service || root.domain === "") return
    if (!root.themes || (root.themes.status !== "ok" && !root.themesLimited)) root.reloadThemes()
    if (root.theme && root.theme.folder && (!root.folder || root.folder.status === "unknown")) root.service.inspectFolder(root.domain)
  }

  Timer {
    id: savedTimer
    interval: 2000
    onTriggered: root.savedField = ""
  }

  spacing: Look.gapLg

  ViewHeader {
    width: parent.width
    canGoBack: true
    title: Copy.t("edit.title", { label: root.store ? root.store.label : root.domain })
    onBack: root.back()
  }

  // config.json can't be read: the store is unknown, so one line instead
  // of a blank form whose every change would be refused.
  StatusLine {
    visible: root.configInvalid
    width: parent.width
    tone: "error"
    text: Copy.t("error.config_invalid")
  }

  Column {
    visible: !root.configInvalid
    width: parent.width
    spacing: Look.gapLg
    // ----- Store -----
    SectionHeader { text: Copy.t("edit.store") }

    InputRow {
      id: nameField
      width: parent.width
      label: Copy.t("edit.name")
      text: root.store ? root.store.label : ""
      hasCursor: root.cursorId === "name"
      paste: root.panel ? root.panel.paste : null
      note: root.savedField === "name" ? Copy.t("edit.saved") : ""
      error: root.errorText("name")
      onCommitted: (text) => root.service && root.applySave("name", root.service.updateStore(root.domain, JSON.stringify({ label: text })))
      onFieldFocusChanged: (focused) => {
        if (focused) cursor.moveTo("name")
        else if (root.panel) root.panel.restoreFocus()
      }
      onFieldTabbed: (direction) => root.tabFrom("name", direction)
    }

    InputRow {
      width: parent.width
      label: Copy.t("edit.domain")
      text: root.domain
      readOnly: true
      helper: Copy.t("edit.domain.help")
    }

    // ----- Theme -----
    SectionHeader { text: Copy.t("theme.section") }

    InputRow {
      id: folderField
      width: parent.width
      label: Copy.t("edit.folder")
      text: root.theme && root.theme.folder ? Format.homeRelative(root.theme.folder, root.home) : ""
      placeholder: Copy.t("edit.folder.placeholder")
      hasCursor: root.cursorId === "folder"
      paste: root.panel ? root.panel.paste : null
      note: root.savedField === "folder" ? Copy.t("edit.saved") : ""
      error: root.errorText("folder") || (root.theme && root.theme.folder ? Copy.folderWarning(root.ts, root.theme.folder) : "")
      onCommitted: (text) => root.service && root.applySave("folder", root.service.updateStore(root.domain, JSON.stringify({ theme: { folder: text } })))
      onFieldFocusChanged: (focused) => {
        if (focused) cursor.moveTo("folder")
        else if (root.panel) root.panel.restoreFocus()
      }
      onFieldTabbed: (direction) => root.tabFrom("folder", direction)

      trailing: [
        SmallButton {
          text: Copy.t("edit.browse")
          onClicked: root.chooseFolderRequested()
        }
      ]
    }

    Item {
      id: targetRow
      // The picker, for the panel smoke.
      readonly property Item picker: targetDropdown
      width: parent.width
      height: Math.max(targetLabel.implicitHeight, targetColumn.implicitHeight)

      RowLabel {
        id: targetLabel
        y: Math.max(0, (targetDropdown.height - implicitHeight) / 2)
        text: Copy.t("edit.target")
        lit: root.cursorId === "target"
      }

      Column {
        id: targetColumn
        anchors.left: targetLabel.right
        anchors.leftMargin: Look.gapLg
        anchors.right: parent.right
        spacing: Look.gapXs

        ThemePicker {
          id: targetDropdown
          width: parent.width
          options: root.targetOptions
          value: root.target
          hasCursor: root.cursorId === "target"
          placeholder: Copy.t("edit.target.filter")
          emptyText: Copy.t("edit.target.none")
          paste: root.panel ? root.panel.paste : null
          onHovered: (h) => { if (h) cursor.moveTo("target") }
          onPicked: (v) => {
            root.setTheme({ target: v })
            targetDropdown.value = Qt.binding(function() { return root.target })
          }
          // Qt hands focus back from the closed popup to whichever field last
          // held it in the view (sometimes Name), which would take the keys
          // and move the cursor there; the keyboard goes to the panel. A
          // click that closed it reaches its field after this.
          onClosed: if (root.panel) root.panel.takeKeyboard()
        }

        // A rate-limited list is not a failure: ThemeInfo fetches it again
        // by itself once Shopify allows it, so the line is info, says only
        // that (the rate-limit banner, when it shows, names the limit), and
        // offers no Retry; Enter and r do not retry either.
        StatusLine {
          visible: !!root.themes && (root.themes.status === "loading" || root.themesFailed)
          width: parent.width
          tone: root.themesFailed && !root.themesLimited ? "error" : "info"
          icon: !!root.themes && root.themes.status === "loading" ? "󰔟" : ""
          text: root.themesLimited ? Copy.t("edit.themesWaiting")
            : root.themesFailed ? Copy.t("edit.themesFailed") + (root.themes.error ? ": " + Copy.errorOf(root.themes.error) : "")
            : Copy.t("edit.loadingThemes")
          actions: root.themesFailed && !root.themesLimited ? [{ id: "retry", label: Copy.t("action.retry") }] : []
          onAction: root.reloadThemes()
        }
      }
    }

    ToggleRow {
      id: allowLiveRow
      width: parent.width
      label: Copy.t("edit.allowLive")
      help: Copy.t("edit.allowLive.help")
      checked: !!root.theme && !!root.theme.allowLive
      selected: root.cursorId === "allowLive"
      onHoveredRow: cursor.moveTo("allowLive")
      onToggled: root.toggleAllowLive()
    }

    // ----- Bar -----
    SectionHeader { text: Copy.t("settings.bar") }

    ToggleRow {
      id: showInBarRow
      width: parent.width
      label: Copy.t("edit.showInBar")
      checked: !!root.store && !!root.store.showInBar
      selected: root.cursorId === "showInBar"
      onHoveredRow: cursor.moveTo("showInBar")
      onToggled: root.toggleShowInBar()
    }

    // ----- Sales access -----
    SectionHeader { text: Copy.t("edit.access") }

    Item {
      id: accessRow
      width: parent.width
      height: Math.max(accessStatus.implicitHeight, accessButton.implicitHeight)

      StatusLine {
        id: accessStatus
        anchors.left: parent.left
        anchors.right: accessButton.left
        anchors.rightMargin: Look.gapLg
        anchors.verticalCenter: parent.verticalCenter
        tone: root.access === "granted" ? "ok" : root.access === "required" ? "warn" : "info"
        icon: root.access === "granting" ? "󰔟" : ""
        text: root.access === "granted" ? Copy.t("access.granted")
          : root.access === "granting" ? Copy.t("access.granting")
          : root.access === "required" ? Copy.t("access.notGranted")
          : Copy.t("access.unknown")
      }

      SmallButton {
        id: accessButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.access === "granting" ? Copy.t("action.cancel")
          : (root.access === "granted" ? Copy.t("access.regrant") : Copy.t("access.grant"))
        hasCursor: root.cursorId === "access"
        onHovered: (h) => { if (h) cursor.moveTo("access") }
        onClicked: root.panel.toggleAccess(root.domain)
      }
    }

    PlainLabel {
      width: parent.width
      text: Copy.t("access.help")
      color: Look.muted
      font.pixelSize: Look.caption
      wrapMode: Text.WordWrap
    }

    // ----- Danger -----
    SectionHeader { text: Copy.t("edit.danger") }

    SmallButton {
      id: removeButton
      iconText: "󰆴"
      text: Copy.t("edit.remove")
      verticalPadding: Style.spacing.controlPaddingY
      foreground: Look.negative
      accent: Look.negative
      hasCursor: root.cursorId === "remove"
      onHovered: (h) => { if (h) cursor.moveTo("remove") }
      onClicked: root.removeRequested()
    }
  }
}
