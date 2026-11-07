// js/confirm.mjs: the confirmation dialog's content per pending action,
// asserted as the text the dialog shows (js/copy.mjs).
import assert from "node:assert/strict"
import { confirmSpec } from "../../js/confirm.mjs"
import { themeName } from "../../js/copy.mjs"
import { backupWhen } from "../../js/format.mjs"
import * as S from "../../js/snapshot.mjs"
import * as T from "../../js/themes.mjs"

const HOME = "/home/u"
const STOPPED = { status: "stopped", url: "", error: null }
const NOW = new Date(2025, 10, 7, 12, 0).getTime()
const AT = new Date(2025, 10, 6, 11, 35).getTime()
const opts = { pins: { cli: S.CLI_PIN, node: S.NODE_PIN }, installs: "~/.local/share/mise/installs", nowMs: NOW }
const store = {
  domain: "acme.myshopify.com", label: "Acme Apparel", theme: { folder: "/home/u/themes/acme", target: "live", allowLive: true },
  themeState: {
    themes: { status: "ok", items: [{ id: "1", name: "Dawn", role: "live" }, { id: "2", name: "Dev", role: "unpublished" }], fetchedAt: 1, error: null },
    folder: Object.assign(T.emptyFolder(), { status: "ok", requested: "/home/u/themes/acme", rootFiles: ["AGENTS.md", "DESIGN.md"] }),
    backups: { status: "ok", items: [{ id: "1762500000-1", at: AT, theme: { id: "1", name: "Dawn", role: "live" }, before: "push", files: 3, bytes: 9 }], folderCopies: [], error: null },
    job: null, lastResult: null, preview: STOPPED
  }
}
const withTheme = theme => Object.assign({}, store, { theme: Object.assign({}, store.theme, theme) })
const withFolder = folder => Object.assign({}, store, { themeState: Object.assign({}, store.themeState, { folder: folder }) })

// Push to the live theme.
let spec = confirmSpec({ action: "push", domain: store.domain, live: true }, store, HOME, opts)
assert.equal(spec.action, "push")
assert.equal(spec.live, true)
assert.equal(spec.destructive, true)
assert.equal(spec.title, "Push to the live theme?")
assert.deepEqual(spec.facts, [
  { label: "From", value: "~/themes/acme (also AGENTS.md and DESIGN.md)" },
  { label: "To", value: "Dawn on Acme Apparel" }
])
assert.equal(spec.body, "Shoppers see every change right away. Shop backs up Dawn first. Files missing from the folder stay on Shopify.")
assert.equal(spec.okText, "Push to live")
assert.equal("commands" in spec, false)

// Push to a development theme.
spec = confirmSpec({ action: "push", domain: store.domain }, withTheme({ target: "2" }), HOME, opts)
assert.equal(spec.live, false)
assert.equal(spec.title, "Push to Dev?")
assert.equal(spec.facts[1].value, "Dev on Acme Apparel")
assert.equal(spec.body, "Shop backs up Dev first. Files missing from the folder stay on Shopify.")
assert.equal(spec.okText, "Push")
// An id the cached list does not know keeps the id.
assert.equal(confirmSpec({ action: "push" }, withTheme({ target: "9" }), HOME, opts).title, "Push to Theme 9?")
// No themes list yet: the live target is still named.
assert.equal(confirmSpec({ action: "push" }, Object.assign({}, store, { themeState: Object.assign({}, store.themeState, { themes: T.emptyThemeState().themes }) }), HOME, opts).body, "Shoppers see every change right away. Shop backs up Live theme first. Files missing from the folder stay on Shopify.")
// Folder not inspected yet: "if present"; inspected with no root files: nothing.
assert.equal(confirmSpec({ action: "push" }, withFolder(T.emptyFolder()), HOME, opts).facts[0].value, "~/themes/acme (also AGENTS.md and DESIGN.md, if present)")
assert.equal(confirmSpec({ action: "push" }, withFolder(Object.assign(T.emptyFolder(), { status: "ok", requested: "/home/u/themes/acme", rootFiles: [] })), HOME, opts).facts[0].value, "~/themes/acme")
assert.equal(confirmSpec({ action: "push" }, withFolder(Object.assign(T.emptyFolder(), { status: "ok", requested: "/home/u/themes/acme", rootFiles: ["AGENTS.md"] })), HOME, opts).facts[0].value, "~/themes/acme (also AGENTS.md)")

// Pull.
spec = confirmSpec({ action: "pull", domain: store.domain }, store, HOME, opts)
assert.equal(spec.live, false)
assert.equal(spec.destructive, true)
assert.equal(spec.title, "Pull Dawn into the folder?")
assert.deepEqual(spec.facts, [{ label: "From", value: "Dawn on Acme Apparel" }, { label: "Into", value: "~/themes/acme" }])
assert.equal(spec.okText, "Pull")

// Restore with the backup row at hand.
spec = confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500000-1" }, store, HOME, opts)
assert.equal(spec.live, true, "the backup came from the live theme")
// The title has no {when}: "Restore the backup from Today 11:50?" read as
// a capital in mid-sentence; when it was taken is the first fact.
assert.equal(spec.title, "Restore this backup?")
assert.deepEqual(spec.facts, [
  { label: "Taken", value: backupWhen(AT, NOW) },
  { label: "Backup", value: "Dawn · before push" },
  { label: "To", value: "Dawn on Acme Apparel" }
])
// One wording with the push dialog: the theme it backs up is named.
assert.equal(spec.body, "Shop backs up Dawn first. Files added since this backup stay on Shopify.")
assert.equal(spec.okText, "Restore")
// Without the row (an IPC request before Backups was opened): the id names
// the theme, never the push target.
spec = confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500000-2" }, store, HOME, opts)
assert.equal(spec.live, false)
assert.equal(spec.title, "Restore this backup?")
assert.deepEqual(spec.facts[0], { label: "Taken", value: backupWhen(1762500000000, NOW) })
assert.deepEqual(spec.facts[1], { label: "Backup", value: "Dev" })
assert.equal(spec.facts[2].value, "Dev on Acme Apparel")
spec = confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500000-9" }, store, HOME, opts)
assert.equal(spec.facts[1].value, "Theme 9")
assert.equal(spec.live, false)
// Live by Themes.restoreIsLive: no row, but the id's theme is live now.
assert.equal(confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500099-1" }, store, HOME, opts).live, true, "no row: the id's theme is live now")
// A backup of a theme that became live since it was taken.
const swapped = Object.assign({}, store, { themeState: Object.assign({}, store.themeState, { themes: Object.assign({}, store.themeState.themes,
  { items: [{ id: "1", name: "Dawn", role: "unpublished" }, { id: "2", name: "Dev", role: "live" }] }) }) })
assert.equal(confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500000-2" }, swapped, HOME, opts).live, true, "a theme that became live since")
assert.equal(confirmSpec({ action: "restore", domain: store.domain, backupId: "1762500000-1" }, swapped, HOME, opts).live, true, "taken from the live theme stays live")

// Allow live.
spec = confirmSpec({ action: "allowLive", domain: store.domain }, store, HOME, opts)
assert.equal(spec.live, true)
assert.equal(spec.title, "Allow changes to the live theme?")
assert.deepEqual(spec.facts, [{ label: "Store", value: "Acme Apparel" }, { label: "Theme", value: "Dawn" }])
assert.equal(spec.okText, "Allow and continue")
assert.equal(spec.body, "Shop still asks before each push or restore and backs the theme up first.")
// Before a restore of a live backup while the push target is a non-live
// theme: the dialog names the backup's theme (not the target) and asks
// the one question (the opt-in covers pushes and restores alike).
const devTarget = withTheme({ target: "2", allowLive: false })
const restoreReq = { action: "restore", domain: store.domain, backupId: "1762500000-1" }
assert.equal(confirmSpec(restoreReq, devTarget, HOME, opts).live, true, "the restore itself is live")
spec = confirmSpec({ action: "allowLive", domain: store.domain, forAction: "restore", backupId: "1762500000-1" }, devTarget, HOME, opts)
assert.deepEqual(spec.facts, [{ label: "Store", value: "Acme Apparel" }, { label: "Theme", value: "Dawn" }], "allow-live before a restore names the backup's theme")
assert.deepEqual([spec.title, spec.body, spec.live], ["Allow changes to the live theme?", "Shop still asks before each push or restore and backs the theme up first.", true])
// An IPC restore before Backups loaded (no row): the id's theme part.
const noRows = Object.assign({}, devTarget, { themeState: Object.assign({}, devTarget.themeState, { backups: { status: "idle", items: [], folderCopies: [], error: null } }) })
spec = confirmSpec({ action: "allowLive", domain: store.domain, forAction: "restore", backupId: "1762500099-1" }, noRows, HOME, opts)
assert.equal(spec.facts[1].value, "Dawn", "no backup row: the theme from the id")
// Before a push it stays the push target.
spec = confirmSpec({ action: "allowLive", domain: store.domain, forAction: "push" }, devTarget, HOME, opts)
assert.deepEqual([spec.facts[1].value, spec.title], ["Dev", "Allow changes to the live theme?"])

// Remove, sign out, reset.
spec = confirmSpec({ action: "remove", domain: store.domain }, store, HOME, opts)
assert.equal(spec.title, "Remove Acme Apparel from Shop?")
assert.deepEqual(spec.facts, [])
assert.equal(spec.destructive, true)
assert.equal(spec.okText, "Remove")
spec = confirmSpec({ action: "signOut" }, null, HOME, opts)
assert.deepEqual([spec.title, spec.body, spec.okText, spec.destructive, spec.live], ["Sign out of Shopify?", "Sales keep working for stores with access. Push, pull, preview and finding stores need you to sign in again.", "Sign out", true, false])
spec = confirmSpec({ action: "resetConfig" }, null, HOME, opts)
assert.deepEqual([spec.title, spec.body, spec.okText, spec.destructive], ["Reset Shop's config?", "Shop renames config.json to config.json.old and starts with no stores. Theme folders, backups and Shopify access aren't touched.", "Reset", true])

// Add store (from IPC): the dialog shows the domain and the name it gets.
spec = confirmSpec({ action: "addStore", domain: "beta.myshopify.com", label: "Beta Goods" }, null, HOME, opts)
assert.equal(spec.title, "Add beta.myshopify.com to Shop?")
assert.deepEqual(spec.facts, [{ label: "Name", value: "Beta Goods" }])
assert.equal(spec.destructive, false)
assert.equal(spec.okText, "Add")

// Install CLI: pins, mise installs dir and the exact commands.
spec = confirmSpec({ action: "installCli" }, null, HOME, opts)
assert.equal(spec.title, "Install the Shopify CLI?")
assert.deepEqual(spec.facts, [{ label: "Node", value: S.NODE_PIN }, { label: "CLI", value: S.CLI_PIN }])
assert.equal(spec.body, "Node " + S.NODE_PIN + " and Shopify CLI " + S.CLI_PIN + " install under ~/.local/share/mise/installs; your mise config isn't changed. The CLI's npm install scripts run during setup.")
assert.deepEqual(spec.commands, ["mise install node@" + S.NODE_PIN, "mise exec node@" + S.NODE_PIN + " -- mise install npm:@shopify/cli@" + S.CLI_PIN])
assert.equal(spec.destructive, false)

// An unknown action is null; no store never throws.
assert.equal(confirmSpec({ action: "nope" }, store, HOME, opts), null)
assert.equal(confirmSpec({ action: "push", domain: "x.myshopify.com" }, null, HOME, opts).facts[1].value, "Live theme on x.myshopify.com")

// themeName (js/copy.mjs, the one display-name rule): the name, else
// "Live theme" / "Theme {id}".
assert.equal(themeName({ id: "1", name: "Dawn", live: true }), "Dawn")
assert.equal(themeName({ id: "", name: "", live: true }), "Live theme")
assert.equal(themeName({ id: "77", name: "", live: false }), "Theme 77")

// The theme refusals said before a dialog are js/preflight.mjs (test_preflight.mjs).
