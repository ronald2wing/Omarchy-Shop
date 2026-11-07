// js/config.mjs: v2-only config parse, validation, patches and
// serialization that keeps what Shop could not read.
import assert from "node:assert/strict"
import { text } from "./fixture.mjs"
import * as C from "../../js/config.mjs"

const v2 = text("config-v2.json")

// normalizeDomain: accepted and rejected inputs
const good = {
  "acme": "acme.myshopify.com",
  " Acme.MyShopify.com ": "acme.myshopify.com",
  "https://acme.myshopify.com/admin/themes": "acme.myshopify.com",
  "https://acme.myshopify.com/": "acme.myshopify.com",
  "a.myshopify.com": "a.myshopify.com",
  "fen0iz-91": "fen0iz-91.myshopify.com"
}
for (const k of Object.keys(good)) assert.equal(C.normalizeDomain(k), good[k], k)
const bad = ["", "a.myshopify.com.evil.tld", "--x", "../..", "аlpha", "1 --allow-live", "a.myshopify.com\nx",
  "-a.myshopify.com", "a-.myshopify.com", "evil.com", "https://acme.myshopify.com/other", "a_b", null, 5,
  "x".repeat(64) + ".myshopify.com"]
for (const b of bad) assert.equal(C.normalizeDomain(b), null, JSON.stringify(b))

assert.equal(C.cleanLabel("  Acme  Apparel "), "Acme Apparel")
assert.equal(C.cleanLabel(""), null)
assert.equal(C.cleanLabel("x".repeat(81)), null)
// cleanRemoteLabel: controls scrubbed and cut to 80 first (a remote name
// never fails for a stray control character).
assert.equal(C.cleanRemoteLabel("Acme\u0007 Apparel"), "Acme Apparel")
assert.equal(C.cleanRemoteLabel("y".repeat(100)), "y".repeat(80))
assert.equal(C.cleanRemoteLabel(""), null)
assert.equal(C.cleanLabel("bad‮name"), null)
assert.equal(C.cleanLabel("tab\tname"), null)
// Bidi isolates are refused like the overrides; an emoji ZWJ label is kept.
assert.equal(C.cleanLabel("bad\u2067name"), null)
assert.equal(C.cleanLabel("\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67 Shop"), "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67 Shop")
assert.equal(C.cleanLabel("Acme Store B"), null)
assert.equal(C.cleanLabel("Acme Store B"), null)
assert.equal(C.cleanLabel("zero​width"), null)

// The two live consents are separate flags, so a live target the dialog did
// not confirm reaches the helper as --allow-live alone (-> live_not_confirmed).

// pollSeconds is clamped to 30-3600 s and rounded; junk reads as 60.
const pollOf = v => C.normalizeConfig(JSON.stringify({ version: 2, pollSeconds: v })).config.pollSeconds
assert.deepEqual([pollOf(5), pollOf(99999), pollOf("abc"), pollOf(90.4)], [30, 3600, 60, 90])

// The shared patterns (mirrors of the Ruby validators).
const targetOk = t => C.normalizeConfig(JSON.stringify({ version: 2, stores: [{ domain: "a.myshopify.com", label: "A", theme: { folder: "/x", target: t } }] })).invalidStores.length === 0
assert(targetOk("live") && targetOk("160258293983"))
assert(!targetOk("0") && !targetOk("1 --allow-live") && !targetOk("live\n"))
for (const tz of ["UTC", "America/Toronto", "America/Argentina/Buenos_Aires", "Etc/GMT+5", "America/Indiana/Knox"]) assert(C.TIMEZONE_RE.test(tz), tz)
for (const tz of ["", "America/", "/UTC", "a/b/c/d/e", "x".repeat(65), "America/New York", "UTC;rm", "Europe/Paris\n"]) assert(!C.TIMEZONE_RE.test(tz), JSON.stringify(tz))

// Missing file: empty v2 config, no error.
for (const raw of [null, undefined]) {
  const r = C.normalizeConfig(raw)
  assert.equal(r.error, null)
  assert.deepEqual(r.config, C.emptyConfig())
}

// Files without version 2 and other invalid files block everything.
assert.equal(C.normalizeConfig('{"stores":[]}').error.code, "config_unsupported")
assert.equal(C.normalizeConfig('{"version":3}').error.code, "config_unsupported")
assert.equal(C.normalizeConfig("{nope").error.code, "config_invalid")
// A blank file (an editor's truncate-then-write window) is an error, never a
// missing file, so the service does not forget its stores over it.
assert.equal(C.normalizeConfig("").error.code, "config_invalid")
assert.equal(C.normalizeConfig("  \n").error.message, "config.json is empty")
assert.equal(C.normalizeConfig("[1]").error.code, "config_invalid")
assert.equal(C.normalizeConfig('{"version":2,"stores":{}}').error.code, "config_invalid")

// A valid v2 file with invalid entries.
const r = C.normalizeConfig(v2)
assert.equal(r.error, null)
assert.deepEqual(r.config.stores.map(s => s.domain), ["acme.myshopify.com", "beta.myshopify.com"])
assert.deepEqual(r.config.stores[0].theme, { folder: "/home/me/themes/acme", target: "live", allowLive: false })
assert.deepEqual(r.invalidStores, [
  { index: 2, domain: null, problem: "missing domain" },
  { index: 3, domain: "acme.myshopify.com", problem: "duplicate domain" }
])
const lenient = C.normalizeConfig('{"version":2,"pollSeconds":5,"alerts":{"notify":"x"},"bar":{"display":"nope"}}')
assert.equal(lenient.config.pollSeconds, 30)
assert.equal(lenient.config.alerts.notify, true)
assert.equal(lenient.config.bar.display, "stores")
const badEntries = C.normalizeConfig(JSON.stringify({ version: 2, stores: [
  { domain: "Acme.myshopify.com", label: "x" },
  { domain: "b.myshopify.com", label: "" },
  { domain: "c.myshopify.com", label: "C", theme: { folder: "relative", target: "live" } },
  { domain: "d.myshopify.com", label: "D", theme: { folder: "/x", target: "1 --allow-live" } },
  { domain: "e.myshopify.com", label: "E", showInBar: "yes" }
] }))
assert.deepEqual(badEntries.invalidStores.map(i => i.problem), ["invalid domain", "invalid label", "invalid theme folder", "invalid theme target", "invalid showInBar"])

// Store patches.
const cfg = r.config
let p = C.applyStorePatch(cfg, "acme.myshopify.com", { label: "New", showInBar: false }, "/home/me", {})
assert.equal(p.error, null)
assert.equal(p.config.stores[0].label, "New")
assert.equal(p.config.stores[0].showInBar, false)
assert.equal(cfg.stores[0].label, "Acme Apparel", "input untouched")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { theme: null }, "/h", {}).error.code, "invalid_patch", "theme keys need allowThemeKeys")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { allowLive: true }, "/h", {}).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "nope.myshopify.com", { label: "x" }, "/h", {}).error.code, "unknown_store")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { label: "" }, "/h", {}).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { showInBar: "no" }, "/h", {}).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", {}, "/h", {}).error.code, "invalid_patch")

const T = { allowThemeKeys: true }
let t = C.applyStorePatch(cfg, "acme.myshopify.com", { theme: { allowLive: true } }, "/home/me", T)
assert.equal(t.config.stores[0].theme.allowLive, true)
// allowLive resets when target or folder changes, even in the same patch.
let t2 = C.applyStorePatch(t.config, "acme.myshopify.com", { theme: { target: "160258293983" } }, "/home/me", T)
assert.equal(t2.config.stores[0].theme.allowLive, false)
t2 = C.applyStorePatch(t.config, "acme.myshopify.com", { theme: { folder: "~/themes/other", allowLive: true } }, "/home/me", T)
assert.equal(t2.config.stores[0].theme.folder, "/home/me/themes/other")
assert.equal(t2.config.stores[0].theme.allowLive, false)
// Same folder again does not reset.
t2 = C.applyStorePatch(t.config, "acme.myshopify.com", { theme: { folder: "/home/me/themes/acme/" } }, "/home/me", T)
assert.equal(t2.config.stores[0].theme.allowLive, true)
// A null theme becomes a default one on merge; {theme:null} unlinks.
t2 = C.applyStorePatch(cfg, "beta.myshopify.com", { theme: { folder: "/srv/beta" } }, "/home/me", T)
assert.deepEqual(t2.config.stores[1].theme, { folder: "/srv/beta", target: "live", allowLive: false })
t2 = C.applyStorePatch(cfg, "acme.myshopify.com", { theme: null }, "/home/me", T)
assert.equal(t2.config.stores[0].theme, null)
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { theme: { folder: "rel" } }, "/h", T).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { theme: { folder: "/a b" } }, "/h", T).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { theme: { target: "0" } }, "/h", T).error.code, "invalid_patch")
assert.equal(C.applyStorePatch(cfg, "acme.myshopify.com", { theme: { evil: 1 } }, "/h", T).error.code, "invalid_patch")

// Settings patches.
let s = C.applySettingsPatch(cfg, { pollSeconds: 10, alerts: { sound: false }, bar: { display: "total" } })
assert.equal(s.error, null)
assert.equal(s.config.pollSeconds, 30)
assert.deepEqual(s.config.alerts, { notify: true, sound: false })
assert.equal(s.config.bar.display, "total")
assert.equal(C.applySettingsPatch(cfg, { pollSeconds: "60" }).error.code, "invalid_patch")
assert.equal(C.applySettingsPatch(cfg, { bar: { display: "x" } }).error.code, "invalid_patch")
assert.equal(C.applySettingsPatch(cfg, { alerts: { volume: 1 } }).error.code, "invalid_patch")
assert.equal(C.applySettingsPatch(cfg, { stores: [] }).error.code, "invalid_patch")

// addStore: normalizes, rejects duplicates, caps the bar at BAR_PILLS shown
// and the list at 50.
let a = C.addStore(cfg, "https://Gamma.myshopify.com/admin", "")
assert.equal(a.error, null)
assert.equal(a.domain, "gamma.myshopify.com")
assert.equal(a.config.stores[2].label, "gamma")
assert.equal(a.label, "gamma")
assert.equal(a.showInBar, true)
assert.equal(C.addStore(cfg, "acme", "x").error.code, "duplicate_store")
assert.equal(C.addStore(cfg, "evil.com", "x").error.code, "invalid_domain")
const badLabel = C.addStore(cfg, "delta", "bad\tlabel")
assert.equal(badLabel.error, null)
assert.equal(badLabel.config.stores[badLabel.config.stores.length - 1].label, "delta", "an unusable label falls back to the subdomain")
const deltaFound = [{ domain: "delta.myshopify.com", name: "Delta Goods" }]
assert.equal(C.addStore(cfg, "delta", "", deltaFound).config.stores.slice(-1)[0].label, "Delta Goods", "the discovered name")
assert.equal(C.addStore(cfg, "delta", "  Mine   Here ", deltaFound).label, "Mine Here", "the given label, cleaned")
assert.equal(C.addStore(cfg, "delta", "bad\u0007", deltaFound).label, "Delta Goods", "a label cleanLabel refuses falls back to the discovered name")
assert.equal(C.addStore(cfg, "delta", null, [{ domain: "delta.myshopify.com", name: "" }]).label, "delta", "an empty discovered name falls back to the subdomain")
assert.equal(C.BAR_PILLS, 5)
assert(C.BAR_INITIALS > 1 && C.BAR_INITIALS <= C.BAR_PILLS, "initials start within the pill range")
let many = C.emptyConfig()
for (const d of ["a", "b", "c", "d", "e", "f"]) many = C.addStore(many, d, d.toUpperCase()).config
assert.deepEqual(many.stores.map(x => x.showInBar), [true, true, true, true, true, false])
const shownAll = C.addStore(Object.assign({}, many, { stores: many.stores.map(x => Object.assign({}, x, { showInBar: true })) }), "g", "G")
assert.equal(shownAll.showInBar, false)
assert.equal(shownAll.shownCount, 6, "addStore reports how many stores were already shown")
let full = C.emptyConfig()
for (let i = 0; i < 50; i++) full = C.addStore(full, "s" + i, "").config
assert.equal(full.stores.length, 50)
assert.equal(C.addStore(full, "one-more", "").error.code, "too_many_stores")
assert.equal(C.addStore(full, "s1", "").error.code, "duplicate_store", "a duplicate is reported before the cap")

// remove / move
assert.deepEqual(C.removeStore(cfg, "acme.myshopify.com").config.stores.map(x => x.domain), ["beta.myshopify.com"])
assert.equal(C.removeStore(cfg, "acme.myshopify.com").error, null)
assert.equal(C.removeStore(cfg, "zz.myshopify.com").config, cfg)
assert.equal(C.removeStore(cfg, "zz.myshopify.com").error.code, "unknown_store")
assert.deepEqual(C.moveStore(many, "d.myshopify.com", 0).config.stores.map(x => x.label), ["D", "A", "B", "C", "E", "F"])
assert.deepEqual(C.moveStore(many, "a.myshopify.com", 99).config.stores.map(x => x.label), ["B", "C", "D", "E", "F", "A"])
assert.deepEqual(C.moveStore(many, "a.myshopify.com", -5).config.stores.map(x => x.label), ["A", "B", "C", "D", "E", "F"])
assert.equal(C.moveStore(many, "a.myshopify.com", 2).error, null)
assert.equal(C.moveStore(many, "zz.myshopify.com", 0).config, many)
assert.equal(C.moveStore(many, "zz.myshopify.com", 0).error.code, "unknown_store")

// serializeConfig keeps unknown keys and invalid entries in place.
const out = C.serializeConfig(C.applyStorePatch(cfg, "beta.myshopify.com", { label: "Beta 2" }, "/h", {}).config, v2)
assert(out.endsWith("}\n"))
const back = JSON.parse(out)
assert.equal(back.version, 2)
assert.equal(back.myNote, "kept")
assert.equal(back.stores.length, 4)
assert.deepEqual(back.stores[2], { label: "No domain" })
assert.equal(back.stores[1].label, "Beta 2")
assert.equal(back.stores[3].label, "Duplicate")
const round = C.normalizeConfig(out)
assert.equal(round.invalidStores.length, 2)
// From nothing.
assert.deepEqual(JSON.parse(C.serializeConfig(C.emptyConfig(), null)), C.emptyConfig())

// findStore: the entry for a domain, or null.
assert.equal(C.findStore(cfg, "beta.myshopify.com").label, cfg.stores[1].label)
assert.equal(C.findStore(cfg, "nope.myshopify.com"), null)

// parsePatch: the panel's JSON object text, at most 8 KiB.
assert.deepEqual(C.parsePatch('{"label":"A"}'), { value: { label: "A" } })
for (const bad of [null, 5, "[1]", "null", "\"x\"", "{", "{\"a\":\"" + "x".repeat(8200) + "\"}"]) {
  const r = C.parsePatch(bad)
  assert.equal(r.value, undefined, String(bad).substring(0, 20))
  assert.equal(r.error.code, "invalid_patch")
}
assert.equal(C.parsePatch("{").error.message, "patch is not valid JSON")
assert.equal(C.parsePatch("[1]").error.message, "patch must be a JSON object")
assert.equal(C.parsePatch(5).error.message, "patch must be a JSON string")

// sameThemeLink: folder and target, never allowLive; null is no link.
assert.equal(C.sameThemeLink({ folder: "/a", target: "live", allowLive: false }, { folder: "/a", target: "live", allowLive: true }), true)
assert.equal(C.sameThemeLink({ folder: "/a", target: "live" }, { folder: "/b", target: "live" }), false)
assert.equal(C.sameThemeLink({ folder: "/a", target: "live" }, { folder: "/a", target: "123" }), false)
assert.equal(C.sameThemeLink(null, { folder: "", target: "live" }), true)
assert.equal(C.sameThemeLink({ folder: "/a", target: "live" }, null), false)
