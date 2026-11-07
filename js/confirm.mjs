// The confirmation dialog's content for a pending request: pure, so the
// exact texts of every dialog are unit-tested. The text comes from
// js/copy.mjs (this module never holds UI strings).
import { t, themeName } from "./copy.mjs"
import { backupWhen, homeRelative } from "./format.mjs"
import { targetTheme, themeState } from "./snapshot.mjs"
import { backupById, parseBackupId, restoreIsLive, rootFiles, themeById } from "./themes.mjs"

function fact(label, value) {
  return { label: label, value: value }
}

function folderOf(store, home) {
  return store && store.theme && store.theme.folder ? homeRelative(store.theme.folder, home) : ""
}

// " (also AGENTS.md and DESIGN.md)" after the From folder: the names found
// by the last inspection, or the "if present" wording before any.
function rootNote(store) {
  const names = rootFiles(themeState(store), store && store.theme ? store.theme.folder : "")
  if (names === null) return " " + t("confirm.rootFiles.maybe")
  if (names.length === 0) return ""
  return " " + t("confirm.rootFiles", { files: names.join(t("confirm.and")) })
}

// Splits Copy's install command ("a && b") into the lines the dialog shows
// in its non-wrapping block.
function installCommands(p) {
  return t("confirm.install.command", { node: p.node, cli: p.cli }).split(" && ").map(s => s.trim()).filter(s => s.length > 0)
}

// The theme a restore writes, from the backup: its list row, else the id
// itself, <epoch>-<themeId> (an IPC request before Backups was opened),
// never the push target. Live by Themes.restoreIsLive, or when the request
// says so (a re-prompt after live_not_confirmed). -> { id, row, name,
// live, atMs }.
function restoreTheme(store, p) {
  const id = String(p.backupId || "")
  const ts = themeState(store)
  const row = backupById(ts, id)
  const parsed = parseBackupId(id)
  const rowTheme = row && row.theme ? row.theme : null
  const themeId = rowTheme ? String(rowTheme.id) : (parsed ? parsed.themeId : "")
  const known = themeById(ts, themeId)
  const name = rowTheme && rowTheme.name ? String(rowTheme.name) : (known && known.name ? String(known.name) : themeName({ id: themeId }))
  return { id: id, row: row, name: name, live: restoreIsLive(ts, id) || p.live === true, atMs: row ? row.at : (parsed ? parsed.epochMs : 0) }
}

// p (the pending request): { action: push|pull|restore|remove|addStore|installCli|signOut|
// resetConfig|allowLive, domain, backupId, label, live, forAction }
// (allowLive's forAction: the push or restore it unlocks). store: the
// snapshot store for p.domain (null for account-level actions).
// opts (required): { pins: {cli, node}, installs (snapshot cli.installs),
// nowMs }.
// -> { action, title, facts: [{label, value}], body, okText,
// destructive, live, commands? } or null for an unknown action.
export function confirmSpec(p, store, home, opts) {
  const action = String(p.action || "")
  const label = store && store.label ? String(store.label) : String(p.label || p.domain || "")
  const target = targetTheme(store)
  const base = { action: action, title: "", facts: [], body: "", okText: "", destructive: false, live: false }

  if (action === "push") {
    const live = target.live || p.live === true
    const name = themeName(target)
    const v = live ? ".live" : ""
    return Object.assign(base, {
      live: live, destructive: true,
      title: t("confirm.push.title" + v, { theme: name }),
      facts: [fact(t("fact.from"), folderOf(store, home) + rootNote(store)), fact(t("fact.to"), t("fact.on", { theme: name, label: label }))],
      body: t("confirm.push.body" + v, { theme: name }),
      okText: t("confirm.push.ok" + v)
    })
  }

  if (action === "pull") {
    const name = themeName(target)
    return Object.assign(base, {
      destructive: true,
      title: t("confirm.pull.title", { theme: name }),
      facts: [fact(t("fact.from"), t("fact.on", { theme: name, label: label })), fact(t("fact.into"), folderOf(store, home))],
      body: t("confirm.pull.body"),
      okText: t("confirm.pull.ok")
    })
  }

  if (action === "restore") {
    const r = restoreTheme(store, p)
    const row = r.row
    const live = r.live
    const name = r.name
    // When it was taken is a fact row: backupWhen is a standalone label
    // ("Today 11:50"), which reads wrong inside a sentence.
    const when = backupWhen(r.atMs, opts.nowMs) || r.id
    const before = row && row.before ? t("job.noun." + String(row.before)) : ""
    return Object.assign(base, {
      live: live, destructive: true,
      title: t("confirm.restore.title"),
      facts: [fact(t("fact.taken"), when), fact(t("fact.backup"), before ? t("fact.backup.value", { theme: name, before: before }) : name), fact(t("fact.to"), t("fact.on", { theme: name, label: label }))],
      body: t("confirm.restore.body", { theme: name }),
      okText: t("confirm.restore.ok")
    })
  }

  if (action === "allowLive") {
    // One question for pushes and restores (the opt-in covers both);
    // before a restore the theme is the backup's, which may not be the
    // push target.
    const name = p.forAction === "restore" ? restoreTheme(store, p).name : themeName(target)
    return Object.assign(base, {
      live: true, destructive: true,
      title: t("confirm.allowLive.title"),
      facts: [fact(t("fact.store"), label), fact(t("fact.theme"), name)],
      body: t("confirm.allowLive.body"),
      okText: t("confirm.allowLive.ok")
    })
  }

  if (action === "remove") {
    return Object.assign(base, {
      destructive: true,
      title: t("confirm.remove.title", { label: label }),
      body: t("confirm.remove.body"),
      okText: t("confirm.remove.ok")
    })
  }

  if (action === "addStore") {
    const domain = String(p.domain || "")
    return Object.assign(base, {
      title: t("confirm.addStore.title", { domain: domain }),
      facts: [fact(t("edit.name"), String(p.label || label))],
      body: t("confirm.addStore.body"),
      okText: t("add.add")
    })
  }

  if (action === "installCli") {
    const pins = opts.pins
    const spec = Object.assign(base, {
      title: t("confirm.install.title"),
      facts: [fact(t("fact.node"), String(pins.node)), fact(t("fact.cli"), String(pins.cli))],
      body: t("confirm.install.body", { node: pins.node, cli: pins.cli, miseInstalls: opts.installs }),
      okText: t("confirm.install.ok")
    })
    spec.commands = installCommands(pins)
    return spec
  }

  if (action === "signOut") {
    return Object.assign(base, {
      destructive: true,
      title: t("confirm.signOut.title"),
      body: t("confirm.signOut.body"),
      okText: t("confirm.signOut.ok")
    })
  }

  if (action === "resetConfig") {
    return Object.assign(base, {
      destructive: true,
      title: t("confirm.resetConfig.title"),
      body: t("confirm.resetConfig.body"),
      okText: t("confirm.resetConfig.ok")
    })
  }

  return null
}
