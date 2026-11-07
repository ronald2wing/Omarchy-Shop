// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's Backups view (PanelHarness): folder copies beside backups, what
// Enter does on each row, the cursor across relists, an empty list and
// config.json unreadable.
// Run alone: tests/run tests/qml/panel_backups_smoke.qml
ShellRoot {
  id: root

  PanelHarness { id: h }

  function publishBackups(items, folderCopies) {
    h.publishAcme({ infoState: h.infoOf(null, { status: "ok", items: items, folderCopies: folderCopies, error: null }) })
  }

  Smoke {
    id: smoke
    name: "PANEL_BACKUPS"
    steps: [
      function() {
        // 1. Folder copies count as backups; Enter on one opens it.
        root.publishBackups([], [h.folderCopyRow])
        h.panel.navigate({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.view.card.backupCount === 1, "a folder copy counts in Backups (n), got " + h.panel.view.card.backupCount)
        h.panel.push({ view: "backups", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.viewName === "backups" && h.footerIs(["hints.open.folder"]), "only folder copies: Enter opens the folder, got " + h.footerKeys())
        smoke.check(h.sheetText("Enter") === h.t("backups.openFolder") && h.sheetKeys().join(",") === "Enter,r", "only folder copies sheet: Enter opens the folder, got " + JSON.stringify(h.sheetRows()))
        smoke.check(!h.findText(h.panel.view, h.t("backups.empty")), "no \"No backups yet\" above listed folder copies")
        // 2. A relist puts a backup above the folder copy.
        root.publishBackups([h.backupRow], [h.folderCopyRow])
      },
      function() {
        // The cursor stays on the folder copy, not on whatever took its index.
        smoke.check(h.panel.view.cursorId === "f:" + h.folderCopyRow.id && h.panel.view.cursorIndex === 1 && h.footerIs(["hints.open.folder"]), "a backup listed on top: the cursor stays on the folder copy, got " + h.panel.view.cursorId + " " + h.footerKeys())
        h.panel.view.moveCursor(0, -1)
        smoke.check(h.panel.view.cursorIndex === 0 && h.footerIs(["hints.restore", "hints.open.folder"]), "on a backup: restore and open folder, got " + h.footerKeys())
        smoke.check(h.sheetText("Enter") === h.t("backups.restore"), "on a backup Enter restores")
        h.panel.view.moveCursor(0, 1)
      },
      function() {
        smoke.check(h.footerIs(["hints.open.folder"]), "on the folder copy: Enter opens the folder, got " + h.footerKeys())
        // 3. No folder copies: no o.
        root.publishBackups([h.backupRow], [])
      },
      function() {
        smoke.check(h.footerIs(["hints.restore"]), "no folder copies: Enter restores, got " + h.footerKeys())
        smoke.check(h.sheetKeys().indexOf("o") < 0 && h.sheetText("Enter") === h.t("backups.restore"), "no folder copies: no o row, got " + JSON.stringify(h.sheetRows()))
        smoke.check(!h.footerHas("hints.open.folder"), "no folder copies: the footer has no o")
        // 4. A relist with a newer backup on top keeps the cursor on its backup.
        smoke.check(h.panel.view.cursorId === "b:" + h.backupRow.id, "the folder copy left: the cursor is on the backup, got " + h.panel.view.cursorId)
        var newer = { id: "1762600001-160258293983", at: 1762600001000, theme: { id: "160258293983", name: "Dawn", role: "live" }, before: "restore", files: 12, bytes: 4096 }
        root.publishBackups([newer, h.backupRow], [])
      },
      function() {
        smoke.check(h.panel.view.cursorId === "b:" + h.backupRow.id && h.panel.view.cursorIndex === 1, "a newer backup listed on top: the cursor stays on the same backup, got " + h.panel.view.cursorId + " at " + h.panel.view.cursorIndex)
        // 5. An empty list: nothing to restore or open, nothing to move to.
        root.publishBackups([], [])
      },
      function() {
        smoke.check(h.footerIs(["hints.reload"]), "no backups at all: only reload, got " + h.footerKeys())
        smoke.check(h.sheetKeys().join(",") === "r", "empty backups sheet: only r, got " + JSON.stringify(h.sheetRows()))
        smoke.check(h.sheetKeys("navigate").indexOf("↑/↓ or j/k") < 0, "empty backups sheet: no move row")
        smoke.check(!h.footerHas("hints.restore") && !h.footerHas("hints.open.folder"), "empty backups footer: no Enter")
        smoke.check(h.sheetKeys().indexOf("r") >= 0 && h.sheetText("r") === h.t("keys.reloadBackups"), "backups sheet: r reloads backups")
        smoke.check(h.sheetKeys("panel").indexOf("r") < 0, "backups sheet: no \"r Refresh store\"")
        // The copy the restore dialog and the CLI banner carry (the JS
        // tests stub Copy).
        smoke.check(h.t("confirm.restore.body").indexOf("stay on Shopify") > 0, "the restore dialog says newer files stay")
        smoke.check(h.t("confirm.restore.title").indexOf("{") < 0 && h.t("fact.taken") !== "fact.taken", "restore title has no {when}; the Taken fact exists")
        smoke.check(h.t("banner.cliMissing.body", { missing: "Node 1", miseInstalls: "~/m" }).indexOf("Node 1 isn't in ~/m.") === 0, "the CLI banner names what is missing first")
        // 6. config.json unreadable under an open Backups: one error line,
        //    no endless loading, the banner's keys only.
        h.publishBroken()
      },
      function() {
        smoke.check(h.footerIs(["hints.broken"]) && !!h.findText(h.panel.view, h.t("error.config_invalid")) && !h.findText(h.panel.view, h.t("backups.loading")), "broken backups: one error line, no endless loading, got " + h.footerKeys())
      }
    ]
  }
}
