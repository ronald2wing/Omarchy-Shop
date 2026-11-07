// One keymap per view: the rows the key sheet lists, the footer shows and
// the view's textKey dispatches from, built from the view's flags. Pure.
//
// A row: { id (what the view runs), key (as the sheet spells it), label (a
// Copy key: the sheet's text), short (a Copy key: the footer's text after
// the key; "" = the row is not in the footer), footerKey (the key as the
// footer spells it, default `key`), chars (the text keys that run it;
// "" for keys the panel routes itself: Enter, arrows, Delete), on (it acts
// right now: listed in the sheet and the footer), footer (the footer's
// order, 0 = sheet only), sheet (false: footer only), group (navigate |
// view | panel) }.
//
// A row's chars dispatch whether or not it is `on`: `on` only says what
// the sheet and the footer list, and the view's textKey keeps its own
// guards (a key that does nothing is listed nowhere, never refused here).
import { t } from "./copy.mjs"

// The footer lists at most this many of a view's rows (KeyHints adds Esc
// back and "? keys").
export const FOOTER_ROWS = 4

function row(id, key, label, o) {
  return Object.assign({ id: id, key: key, label: label, short: "", footerKey: "", chars: "", on: true, footer: 0, sheet: true, group: "view" }, o || {})
}

// The move / scroll row of the Navigate group.
function moveRow(label, on) {
  return row("move", "↑/↓ or j/k", label, { group: "navigate", on: on !== false })
}

// The row whose chars include `ch` (a typed key), or null.
export function rowForKey(keymap, ch) {
  const rows = keymap || []
  const c = String(ch || "")
  if (c === "") return null
  for (let i = 0; i < rows.length; i++) if (rows[i].chars.indexOf(c) >= 0) return rows[i]
  return null
}

// The sheet's rows of one group: [[key, text]] for the rows that act.
export function sheetRows(keymap, group) {
  const rows = keymap || []
  const out = []
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i]
    if (r.on && r.sheet && r.group === group) out.push([r.key, t(r.label)])
  }
  return out
}

// The rows the footer shows, in its order: at most FOOTER_ROWS rows that
// act and have a short label.
export function footerRows(keymap) {
  const rows = (keymap || []).filter(r => r.on && r.footer > 0 && r.short !== "")
  rows.sort((a, b) => a.footer - b.footer)
  return rows.slice(0, FOOTER_ROWS)
}

// The footer's pieces, in order: "<key> <short>" for each footer row, then
// the config-broken banner keys, then "Esc back" above the bottom of the
// view stack. opts: { broken, canGoBack }.
export function footerParts(keymap, opts) {
  const o = opts || {}
  const parts = footerRows(keymap).map(r => {
    const key = r.footerKey !== "" ? r.footerKey : r.key
    return key !== "" ? key + " " + t(r.short) : t(r.short)
  })
  if (o.broken) parts.push(t("hints.broken"))
  if (o.canGoBack) parts.push("Esc " + t("hints.back"))
  return parts
}

export function footerText(keymap, opts) {
  return footerParts(keymap, opts).join(" · ")
}

// ----- the views -----

// Home. f: { broken (config.json unreadable: the empty state's buttons),
// firstRun (the setup checklist), periodSwitch (the hero shows) }.
export function home(f) {
  const buttons = !!f.broken || !!f.firstRun
  const rows = [moveRow("keys.move")]
  if (buttons) {
    rows.push(
      row("activate", "Enter", f.broken ? "keys.runButton" : "keys.runStep", { short: f.broken ? "hints.run" : "hints.run.step", footer: 1 }),
      row("choose", "h / l", "keys.chooseButton", { footerKey: "h/l", short: "hints.choose", footer: 2 }))
  } else {
    rows.push(
      row("activate", "Enter", "keys.viewStore", { short: "hints.open", footer: 1 }),
      row("period", "h / l", "keys.period", { footerKey: "h/l", short: "hints.period", footer: 4, on: !!f.periodSwitch }))
  }
  rows.push(
    row("add", "a", "add.title", { chars: "a", short: "hints.add", footer: buttons ? 0 : 2 }),
    row("settings", "s", "action.settings", { chars: "s", short: "hints.settings", footer: f.broken ? 0 : 3 }),
    row("edit", "e", "action.edit", { chars: "e", short: "hints.edit", footer: 5, on: !buttons }),
    row("admin", "o", "keys.admin", { chars: "o", on: !buttons }),
    row("reorder", "Ctrl+j / Ctrl+k", "keys.reorder", { on: !buttons }),
    row("remove", "x / Delete", "edit.remove", { on: !buttons }),
    row("refresh", "r", "keys.refreshAll", { chars: "r", group: "panel" }))
  return rows
}

// What a store's Enter and theme keys do right now, in priority order: a
// grant in flight, a theme job, a preview, the access step, no CLI, a
// sign-in or sign-out in flight, signed out, no theme folder, or idle. A
// job or preview comes before the access and sign-in steps: both run on a
// store without sales access or while signed out, and c / d must stay
// named.
function storeMode(f) {
  if (f.granting) return "granting"
  if (f.job) return "job"
  if (f.previewOn) return "preview"
  if (f.needsAccess) return "grant"
  if (f.cliBlocked) return "install"
  if (f.accountBusy) return "accountBusy"
  if (f.signInStep) return "signIn"
  if (!f.linked) return "noFolder"
  return "idle"
}

// Store. f: { broken, granting, job, previewOn, previewReady, previewFailed,
// needsAccess, linked, cliBlocked, accountBusy, signInStep (signed out, or
// the signed-out empty state), figuresShown (the period tabs show),
// hasResult, hasDetails }.
//
// Theme keys need a linked folder and the CLI; signed out they are offered
// as signed in (the service does not refuse them); while a job runs only c
// works, while a grant runs none does (store_busy), while a preview runs
// push and pull are refused (d stops it), and during a sign-in or sign-out
// all three are refused (account_busy). The card's buttons say the same.
export function store(f) {
  const mode = f.broken ? "broken" : storeMode(f)
  const live = mode !== "broken"
  const idleTheme = !!f.linked && (mode === "idle" || mode === "grant" || mode === "signIn")
  const themeKeys = idleTheme || mode === "preview"
  const period = live && !!f.figuresShown
  return [
    moveRow("keys.scroll"),
    row("access", "Enter / a", mode === "granting" ? "keys.cancelGrant" : "keys.grant", { footerKey: "Enter", chars: "a", short: mode === "granting" ? "hints.cancel" : "hints.grant", footer: 1, on: mode === "grant" || mode === "granting" }),
    row("signIn", "Enter", "setup.signIn", { short: "hints.signIn", footer: 1, on: mode === "signIn" }),
    row("install", "Enter", "setup.cli.missing", { short: "hints.install", footer: 1, on: mode === "install" }),
    row("chooseFolder", "Enter", "keys.chooseFolder", { short: "hints.choose.folder", footer: 1, on: mode === "noFolder" }),
    row("cancelJob", "c", "keys.cancelJob", { chars: "c", short: "hints.cancel", footer: 1, on: mode === "job" }),
    row("period", "h / l", "keys.period", { footerKey: "h/l", short: "hints.period", footer: 3, on: period }),
    row("periodJump", "1–6", "keys.period.jump", { chars: "123456", on: period }),
    row("preview", "d", "keys.stopPreview", { chars: "d", short: "hints.stopPreview", footer: 1, on: mode === "preview" }),
    row("push", "p", "theme.push", { chars: "p", short: "hints.push", footer: 4, on: idleTheme }),
    row("pull", "u", "keys.pull", { chars: "u", short: "hints.pull", footer: 5, on: idleTheme }),
    // After a preview that failed or ended on its own the footer names d.
    row("preview", "d", "keys.preview", { chars: "d", short: "hints.restartPreview", footer: f.previewFailed ? 1 : 0, on: idleTheme }),
    row("openPreview", "v", "keys.openPreview", { chars: "v", short: "hints.open.preview", footer: 2, on: themeKeys && !!f.previewReady }),
    row("details", "t", "keys.resultDetails", { chars: "t", on: themeKeys && !!f.hasDetails }),
    row("dismiss", "x / Delete", "keys.dismissThemeResult", { on: themeKeys && !!f.hasResult }),
    row("backups", "b", "keys.backups", { chars: "b", short: "hints.backups", footer: 6, on: live }),
    row("edit", "e", "action.edit", { chars: "e", short: "hints.edit", footer: 7, on: live }),
    row("admin", "o", "keys.admin", { chars: "o", short: "hints.admin", footer: 8, on: live }),
    row("refresh", "r", "keys.refreshStore", { chars: "r", group: "panel", on: live })
  ]
}

// Add. f: { broken, manualRow (the cursor is on the manual-entry row),
// manualOnly (no CLI and nothing discovered: that row is all there is),
// inShop (the cursor's store is already in Shop: Enter opens it),
// canDiscover (the CLI is ready) }.
export function add(f) {
  const live = !f.broken
  const enterLabel = f.manualRow ? "keys.addByDomain" : (f.inShop ? "keys.viewStore" : "keys.addSelected")
  const enterShort = f.manualRow ? "hints.add.byDomain" : (f.inShop ? "hints.open" : "hints.add")
  return [
    moveRow("keys.move", live),
    row("activate", "Enter", enterLabel, { short: enterShort, footer: 1, on: live }),
    row("filter", "/", "keys.filter", { chars: "/", short: "hints.filter", footer: 2, on: live && !f.manualOnly }),
    row("manual", "m", "keys.addByDomain", { chars: "m", short: "hints.add.byDomain", footer: 3, on: live && !f.manualRow }),
    row("discover", "r", "keys.discoverAgain", { chars: "r", on: live && !!f.canDiscover })
  ]
}

// Backups. f: { broken, empty (no backup and no folder copy), noCopies (no
// folder copy: o has nothing to open), onFolderCopy (Enter opens the
// cursor's folder copy) }.
export function backups(f) {
  const live = !f.broken
  const rows = !f.empty
  return [
    moveRow("keys.move", rows),
    row("activate", "Enter", f.onFolderCopy ? "backups.openFolder" : "backups.restore", { short: f.onFolderCopy ? "hints.open.folder" : "hints.restore", footer: 1, on: live && rows }),
    row("openFolder", "o", "backups.openFolder", { chars: "o", short: "hints.open.folder", footer: 2, on: live && rows && !f.noCopies && !f.onFolderCopy }),
    row("reload", "r", "keys.reloadBackups", { chars: "r", short: "hints.reload", footer: f.empty ? 1 : 0, on: live })
  ]
}

// Edit. f: { broken }. No left/right option: Enter / Space toggles a row or
// opens the target list (h / l would write a new target per keypress).
export function edit(f) {
  const live = !f.broken
  return [
    moveRow("keys.move"),
    row("activate", "Enter / Space", "keys.activate", { on: live }),
    row("fields", "Tab / Shift+Tab", "keys.fields", { on: live }),
    row("reload", "r", "keys.reloadThemes", { chars: "r", on: live }),
    row("note", "", "hints.savesAsYouGo", { short: "hints.savesAsYouGo", footer: 1, sheet: false, on: live })
  ]
}

// Settings. f: { broken: only the buttons are left (the toggles, bar
// options and refresh field are hidden) }.
export function settings(f) {
  return [
    moveRow("keys.move"),
    row("activate", f.broken ? "Enter" : "Enter / Space", "keys.activate"),
    row("option", "h / l", "keys.option", { on: !f.broken })
  ]
}
