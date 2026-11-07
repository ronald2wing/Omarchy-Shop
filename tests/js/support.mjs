// Shared by the Node tests: the fixtures (load(rel) parses
// tests/fixtures/<rel>, text(rel) reads it raw), the repo's sources
// (read(rel), listDir(dir, ext), strip(src)) and snapshotStore, one store
// of a service snapshot.
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { emptyPreview, emptyThemeState } from "../../js/themes.mjs"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
const FIXTURES = path.join(ROOT, "tests", "fixtures")

export function text(rel) {
  return fs.readFileSync(path.join(FIXTURES, rel), "utf8")
}

export function load(rel) {
  return JSON.parse(text(rel))
}

// A repo file's source, by its path from the checkout root.
export function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), "utf8")
}

// The repo paths of dir's files ending in ext ([] when dir is absent).
export function listDir(dir, ext) {
  const abs = path.join(ROOT, dir)
  return fs.existsSync(abs) ? fs.readdirSync(abs).filter(f => f.endsWith(ext)).map(f => dir + "/" + f) : []
}

// Comments removed (block comments keep their newlines, so line numbers
// hold). A `//` right after `:` (a URL) or `"` (a string) is not one.
export function strip(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, c => c.replace(/[^\n]/g, "")).replace(/(^|[^:"\\])\/\/.*$/gm, "$1")
}

// One snapshot store (CONTRIBUTING "Service snapshot"): acme with sales
// access, nothing fetched yet, no theme linked, no job and a stopped
// preview. extra, salesExtra and themeStateExtra replace fields of the
// store, its sales and its themeState.
export function snapshotStore(extra, salesExtra, themeStateExtra) {
  return Object.assign({
    domain: "acme.myshopify.com", label: "Acme", showInBar: true, theme: null, currency: "USD",
    salesAccess: "granted", salesAccessError: null,
    sales: Object.assign({ status: "ok", pending: false, paused: false, retryAt: 0, error: null,
      fetchedAt: { today: 0, traffic: 0, history: 0 }, today: null, newOrderAt: 0, history: null }, salesExtra),
    themeState: Object.assign(emptyThemeState(), { job: null, lastResult: null, preview: emptyPreview() }, themeStateExtra)
  }, extra)
}
