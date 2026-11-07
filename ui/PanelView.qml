import QtQuick

// The shape every panel view shares (ShopPanel builds each one with
// snapshot, service and panel): the service snapshot, the service, the
// panel (ShopPanel's view contract), and two panel facts read the same way
// everywhere, and the keyboard entry points ShopPanel calls on whichever
// view is showing, as no-ops a view replaces when it has that key.
Column {
  id: view

  required property var snapshot
  property var service: null
  property var panel: null
  // config.json is unusable (ShopPanel.configInvalid).
  readonly property bool configInvalid: !!view.panel && view.panel.configInvalid
  // The panel's clock (ShopPanel.nowMs, ticking while it is open).
  readonly property real nowMs: view.panel ? view.panel.nowMs : Date.now()
  // The view's keys (js/keymap.mjs rows): the key sheet, the footer and
  // textKey read them.
  property var keymap: []

  // A typed key (Keymap.rowForKey picks its row).
  function textKey(text) {}
  // x / Delete.
  function deleteSelected() {}
  // Ctrl+j / Ctrl+k (dy: -1 up, 1 down).
  function reorder(dy) {}
  // Config broke under the view: drop what a hidden field held.
  function dropHiddenInput() {}
}
