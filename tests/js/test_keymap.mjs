// js/keymap.mjs: each view's one keymap, as the footer and the key sheet
// render it, and the text keys its textKey dispatches.
import assert from "node:assert/strict"
import * as K from "../../js/keymap.mjs"

const keysOf = rows => rows.map(r => r[0])
const view = km => K.sheetRows(km, "view")
const footer = (km, o) => K.footerText(km, o || {})
const back = { canGoBack: true }

// Every combination of a view's boolean flags.
function combos(names) {
  const out = []
  for (let bits = 0; bits < (1 << names.length); bits++) {
    const f = {}
    names.forEach((n, i) => { f[n] = !!(bits & (1 << i)) })
    out.push(f)
  }
  return out
}
const STORE_FLAGS = ["broken", "granting", "job", "previewOn", "previewReady", "previewFailed", "needsAccess", "linked", "cliBlocked", "accountBusy", "signInStep", "figuresShown", "hasResult", "hasDetails"]
const all = []
for (const f of combos(STORE_FLAGS)) all.push(K.store(f))
for (const f of combos(["broken", "firstRun", "periodSwitch"])) all.push(K.home(f))
for (const f of combos(["broken", "manualRow", "manualOnly", "inShop", "canDiscover"])) all.push(K.add(f))
for (const f of combos(["broken", "empty", "noCopies", "onFolderCopy"])) all.push(K.backups(f))
for (const f of combos(["broken"])) { all.push(K.edit(f)); all.push(K.settings(f)) }

// The key never repeats as the label's first word ("Enter enter a domain"),
// in the footer or the sheet; the footer has at most FOOTER_ROWS rows of a
// view; a row in the footer has its short label; text keys are unique per
// view.
for (const km of all) {
  for (const part of K.footerParts(km, back)) {
    const words = part.toLowerCase().split(" ")
    assert.notEqual(words[0], words[1], "footer piece repeats its key: " + part)
  }
  for (const g of ["navigate", "view", "panel"]) {
    for (const [key, text] of K.sheetRows(km, g)) {
      const last = key.toLowerCase().split(/[ /+]+/).filter(Boolean).pop() || ""
      assert.notEqual(text.toLowerCase().split(" ")[0], last, "sheet row repeats its key: " + key + " " + text)
      assert(!/^[a-z]+\.[a-zA-Z.]+$/.test(text), "sheet text is not a raw key: " + text)
    }
  }
  assert(K.footerParts(km, {}).length <= K.FOOTER_ROWS)
  // footerRows: the rows behind the footer's pieces (the panel smokes
  // assert these ids), acting, labelled, in footer order.
  const rows = K.footerRows(km)
  assert.equal(rows.length, K.footerParts(km, {}).length, "one footer piece per footer row")
  assert(rows.every(r => r.on && r.footer > 0 && r.short !== ""), "footer rows act and have a short label")
  for (let i = 1; i < rows.length; i++) assert(rows[i - 1].footer <= rows[i].footer, "footer rows in footer order")
  const seen = {}
  for (const r of km) {
    if (r.footer > 0) assert.notEqual(r.short, "", r.id + " in the footer has a short label")
    for (const c of r.chars) {
      if (seen[c] !== undefined) assert.equal(seen[c], r.id, "char " + c + " runs one action")
      seen[c] = r.id
    }
  }
}

// footerRows with no keymap, and over FOOTER_ROWS candidates: the lowest
// footer numbers win, in order.
assert.deepEqual(K.footerRows(null), [])
{
  const many = []
  for (let i = 0; i < K.FOOTER_ROWS + 2; i++) many.push({ id: "r" + i, on: true, footer: K.FOOTER_ROWS + 2 - i, short: "action.refresh", key: "r" + i, footerKey: "", chars: [] })
  many.push({ id: "off", on: false, footer: 1, short: "action.refresh", key: "x", footerKey: "", chars: [] })
  assert.deepEqual(K.footerRows(many).map(r => r.footer), Array.from({ length: K.FOOTER_ROWS }, (_, i) => i + 1))
}

// ----- store -----
const S = o => K.store(Object.assign({ linked: true, figuresShown: true }, o))
// Every text key the store answered before the keymap still dispatches,
// whatever the state (on or not): `on` only says what is listed.
const storeChars = { r: "refresh", a: "access", e: "edit", o: "admin", p: "push", u: "pull", d: "preview", v: "openPreview", c: "cancelJob", b: "backups", t: "details", 1: "periodJump", 6: "periodJump" }
for (const f of [{}, { broken: true }, { job: true }, { needsAccess: true, linked: false }]) {
  const km = S(f)
  for (const c of Object.keys(storeChars)) assert.equal(K.rowForKey(km, c).id, storeChars[c], "store " + c + " -> " + storeChars[c])
  for (const c of "fghijklmnqswxyz/") assert.equal(K.rowForKey(km, c), null, "store ignores " + c)
}

assert.equal(footer(S({}), back), "h/l period · p push · u pull · b backups · Esc back")
assert.deepEqual(keysOf(view(S({}))), ["h / l", "1–6", "p", "u", "d", "b", "e", "o"])
assert.deepEqual(K.sheetRows(S({}), "panel"), [["r", "Refresh store"]])
assert.deepEqual(K.sheetRows(S({}), "navigate"), [["↑/↓ or j/k", "Scroll"]])
// A theme result, its details and a preview URL add x, t and v.
assert.deepEqual(keysOf(view(S({ hasResult: true, hasDetails: true }))), ["h / l", "1–6", "p", "u", "d", "t", "x / Delete", "b", "e", "o"])
// A preview that ended on its own: the footer names d.
assert.equal(footer(S({ previewFailed: true }), back), "d restart preview · h/l period · p push · u pull · Esc back")
// The access step (linked folder: the theme keys stay; no figures).
let km = S({ needsAccess: true, figuresShown: false })
assert.equal(footer(km, back), "Enter grant access · p push · u pull · b backups · Esc back")
assert.deepEqual(view(km)[0], ["Enter / a", "Grant sales access"])
assert(!keysOf(view(km)).includes("h / l") && !keysOf(view(km)).includes("1–6"))
km = S({ needsAccess: true, linked: false, figuresShown: false })
assert.equal(footer(km, back), "Enter grant access · b backups · e edit · o admin · Esc back")
assert(!keysOf(view(km)).includes("p"))
// A grant in flight: Enter / a cancel; no theme keys.
km = S({ granting: true, needsAccess: true, figuresShown: false })
assert.equal(footer(km, back), "Enter cancel · b backups · e edit · o admin · Esc back")
assert.deepEqual(view(km)[0], ["Enter / a", "Cancel granting access"])
assert(["p", "u", "d", "v", "c"].every(k => !keysOf(view(km)).includes(k)))
// Signed out with figures: Enter signs in, period and p/u/d stay.
km = S({ signInStep: true })
assert.equal(footer(km, back), "Enter sign in · h/l period · p push · u pull · Esc back")
assert.deepEqual(keysOf(view(km)), ["Enter", "h / l", "1–6", "p", "u", "d", "b", "e", "o"])
assert.equal(view(km)[0][1], "Sign in to Shopify")
km = S({ signInStep: true, linked: false })
assert.equal(footer(km, back), "Enter sign in · h/l period · b backups · e edit · Esc back")
// No folder: Enter chooses one; no theme keys.
km = S({ linked: false })
assert.equal(footer(km, back), "Enter choose folder · h/l period · b backups · e edit · Esc back")
assert.equal(view(km)[0][1], "Choose a theme folder")
assert(!keysOf(view(km)).includes("p") && !keysOf(view(km)).includes("u"))
// A theme job: c cancels; period with figures, none without.
km = S({ job: true })
assert.equal(footer(km, back), "c cancel · h/l period · b backups · e edit · Esc back")
assert(keysOf(view(km)).includes("c") && !keysOf(view(km)).includes("p"))
km = S({ job: true, needsAccess: true, figuresShown: false })
assert.equal(footer(km, back), "c cancel · b backups · e edit · o admin · Esc back")
assert(!keysOf(view(km)).includes("Enter / a"), "a job comes before the access step")
// A preview: d stops it, v opens it once it has a URL.
km = S({ previewOn: true, previewReady: true })
assert.equal(footer(km, back), "d stop · v open preview · h/l period · b backups · Esc back")
assert.deepEqual(view(km).find(r => r[0] === "d"), ["d", "Stop preview"])
assert(!keysOf(view(km)).includes("p") && !keysOf(view(km)).includes("c"))
assert.equal(footer(S({ previewOn: true, figuresShown: false }), back), "d stop · b backups · e edit · o admin · Esc back")
// A sign-in or sign-out in flight: no p/u/d, the period switch stays.
km = S({ accountBusy: true })
assert.equal(footer(km, back), "h/l period · b backups · e edit · o admin · Esc back")
assert(["p", "u", "d"].every(k => !keysOf(view(km)).includes(k)))
// No CLI: Enter installs; with cached figures the period switch stays.
km = S({ cliBlocked: true })
assert.equal(footer(km, back), "Enter install · h/l period · b backups · e edit · Esc back")
assert.equal(view(km)[0][1], "Install the Shopify CLI")
assert.equal(footer(S({ cliBlocked: true, figuresShown: false }), back), "Enter install · b backups · e edit · o admin · Esc back")
// config.json unreadable: only the banner's keys.
km = S({ broken: true })
assert.deepEqual(view(km), [])
assert.deepEqual(K.sheetRows(km, "panel"), [])
assert.equal(footer(km, { broken: true, canGoBack: true }), "i open file · Shift+i reset · Esc back")

// ----- home -----
km = K.home({ periodSwitch: true })
assert.equal(footer(km), "Enter open · a add · s settings · h/l period")
assert.deepEqual(keysOf(view(km)), ["Enter", "h / l", "a", "s", "e", "o", "Ctrl+j / Ctrl+k", "x / Delete"])
assert.deepEqual(K.sheetRows(km, "panel"), [["r", "Refresh all"]])
assert.equal(footer(K.home({})), "Enter open · a add · s settings · e edit", "no hero: no h/l")
km = K.home({ firstRun: true })
assert.equal(footer(km), "Enter run step · h/l choose · s settings")
assert.deepEqual(view(km), [["Enter", "Run the highlighted step"], ["h / l", "Choose a button"], ["a", "Add a store"], ["s", "Settings"]])
km = K.home({ broken: true })
assert.equal(footer(km, { broken: true }), "Enter run · h/l choose · i open file · Shift+i reset")
assert.equal(view(km)[0][1], "Run the highlighted button")
for (const f of [{}, { firstRun: true }, { broken: true }]) {
  const h = K.home(f)
  for (const [c, id] of [["r", "refresh"], ["a", "add"], ["s", "settings"], ["e", "edit"], ["o", "admin"]]) assert.equal(K.rowForKey(h, c).id, id)
  assert.equal(K.rowForKey(h, "p"), null)
}

// ----- add -----
km = K.add({ canDiscover: true })
assert.equal(footer(km, back), "Enter add · / filter · m add by domain · Esc back")
assert.deepEqual(view(km), [["Enter", "Add selected store"], ["/", "Filter stores"], ["m", "Add a store by its domain"], ["r", "Find stores again"]])
assert.equal(footer(K.add({ inShop: true }), back), "Enter open · / filter · m add by domain · Esc back")
km = K.add({ manualRow: true, canDiscover: true })
assert.equal(footer(km, back), "Enter add by domain · / filter · Esc back")
assert(!keysOf(view(km)).includes("m"))
km = K.add({ manualRow: true, manualOnly: true })
assert.equal(footer(km, back), "Enter add by domain · Esc back")
assert.deepEqual(keysOf(view(km)), ["Enter"], "no CLI and nothing found: no / and no r")
assert.deepEqual(view(K.add({ broken: true, canDiscover: true })), [])
assert.equal(footer(K.add({ broken: true }), { broken: true, canGoBack: true }), "i open file · Shift+i reset · Esc back")
for (const [c, id] of [["/", "filter"], ["r", "discover"], ["m", "manual"]]) assert.equal(K.rowForKey(K.add({}), c).id, id)

// ----- backups -----
km = K.backups({})
assert.equal(footer(km, back), "Enter restore · o open folder · Esc back")
assert.deepEqual(view(km), [["Enter", "Restore…"], ["o", "Open folder"], ["r", "Reload backups"]])
km = K.backups({ onFolderCopy: true })
assert.equal(footer(km, back), "Enter open folder · Esc back")
assert.deepEqual(keysOf(view(km)), ["Enter", "r"])
km = K.backups({ noCopies: true })
assert.equal(footer(km, back), "Enter restore · Esc back")
assert.deepEqual(keysOf(view(km)), ["Enter", "r"])
km = K.backups({ empty: true, noCopies: true })
assert.equal(footer(km, back), "r reload · Esc back")
assert.deepEqual(keysOf(view(km)), ["r"])
assert.deepEqual(K.sheetRows(km, "navigate"), [], "an empty list has no row to move between")

// ----- edit and settings -----
km = K.edit({})
assert.equal(footer(km, back), "changes save as you go · Esc back")
assert.deepEqual(keysOf(view(km)), ["Enter / Space", "Tab / Shift+Tab", "r"])
assert.deepEqual(view(K.edit({ broken: true })), [])
assert.equal(K.rowForKey(km, "r").id, "reload")
assert.equal(footer(K.settings({}), back), "Esc back")
assert.equal(footer(K.settings({}), {}), "", "Settings at the bottom: nothing but ? keys")
assert.deepEqual(view(K.settings({})), [["Enter / Space", "Toggle / activate"], ["h / l", "Change option"]])
assert.deepEqual(view(K.settings({ broken: true })), [["Enter", "Toggle / activate"]])
