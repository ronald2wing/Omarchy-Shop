// The test fixtures: load(name) parses one of tests/js/fixtures/ (canned
// fetch-sales results and config files), text(name) reads it raw, and
// loadShared(name) parses one of tests/fixtures/ (the Ruby tests read it too).
import fs from "node:fs"

export function text(name) {
  return fs.readFileSync(new URL("./fixtures/" + name, import.meta.url), "utf8")
}

export function load(name) {
  return JSON.parse(text(name))
}

export function loadShared(name) {
  return JSON.parse(fs.readFileSync(new URL("../fixtures/" + name, import.meta.url), "utf8"))
}
