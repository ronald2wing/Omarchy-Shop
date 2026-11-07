// js/text.mjs: control scrubbing, short codes, subdomain labels.
import assert from "node:assert/strict"
import { loadShared } from "./fixture.mjs"
import * as T from "../../js/text.mjs"

for (const c of ["\t", "\u0000", "\u007f", "\u0085", " ", " ", "​", "‏", "‮", "⁠", "﻿"]) assert(T.CONTROL_RE.test("a" + c + "b"), JSON.stringify(c))
for (const ok of ["a", "Épicerie Zoé", "日本", "a b", "emoji 💡"]) assert(!T.CONTROL_RE.test(ok), ok)

// The set is exactly Ruby Text.clean's (dumped into the fixture): every
// code point, astral ones included; ZWJ is not in it.
{
  const fixture = loadShared("control-codepoints.json")
  const ranges = fixture.ranges.split(" ").map(r => r.split("-").map(h => parseInt(h, 16))).map(p => [p[0], p.length > 1 ? p[1] : p[0]])
  const inRuby = (c) => ranges.some(r => c >= r[0] && c <= r[1])
  const wrong = []
  for (let c = 0; c <= 0x10ffff; c++) {
    if (c >= 0xd800 && c <= 0xdfff) continue
    if (T.CONTROL_RE.test("a" + String.fromCodePoint(c) + "b") !== inRuby(c)) wrong.push(c.toString(16))
    if (wrong.length > 20) break
  }
  assert.deepEqual(wrong, [], "JS CONTROL_RE differs from Ruby's at U+" + wrong.join(", U+"))
}
// Bidi isolates and astral tags are scrubbed; an emoji ZWJ sequence keeps
// its joiners; a whole astral format character becomes one space.
assert.equal(T.scrubControl("a\u2067b\u2069c\u061cd", 300), "a b c d")
assert.equal(T.scrubControl("x\udb40\udc41y", 300), "x y")
assert.equal(T.scrubControl("\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67 Shop", 300), "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67 Shop")
assert(!T.CONTROL_RE.test("\u200d"), "ZWJ kept, as in Ruby")

assert.equal(T.scrubControl(" a​b\t", 300), "a b")
assert.equal(T.scrubControl("x‮y", 300), "x y")
assert.equal(T.scrubControl(null, 300), "")
assert.equal(T.scrubControl(undefined, 300), "")
assert.equal(T.scrubControl(42, 300), "42")
assert.equal(T.scrubControl("abcdef", 2), "ab")

assert.deepEqual(T.shortCodes(["Acme Apparel", "Gamma", "Épicerie Zoé", "7 Seas", "acme-store", "日本", ""]), ["AA", "GA", "EZ", "7S", "AS", "日本", "?"])
assert.deepEqual(T.shortCodes(["Acme Apparel", "Acme Apparel", "Acme Apparel"]), ["AA", "AA2", "AA3"])
assert.deepEqual(T.shortCodes(["Acme Apparel", "Alpha Audio", "Gamma", "Gamma"]), ["AA", "AA2", "GA", "GA2"])

assert.equal(T.subdomainLabel("acme.myshopify.com"), "acme")
assert.equal(T.subdomainLabel("acme"), "acme")
assert.equal(T.subdomainLabel(null), "")

// fillTemplate: literal substitution, null/undefined read as "", no vars is a no-op.
assert.equal(T.fillTemplate("{n} new orders · {label}", { n: "2", label: "Acme {x}" }), "2 new orders · Acme {x}")
assert.equal(T.fillTemplate("a {b} c", { b: null, d: 1 }), "a  c")
assert.equal(T.fillTemplate("plain", null), "plain")
assert.equal(T.fillTemplate(null, {}), "")
// A value holding another key's placeholder stays literal, in either key
// order (a theme named "Dawn {label}", a product titled "Mug {orders}").
assert.equal(T.fillTemplate("{theme} on {label}", { theme: "Dawn {label}", label: "Acme" }), "Dawn {label} on Acme")
assert.equal(T.fillTemplate("{theme} on {label}", { label: "Acme", theme: "Dawn {label}" }), "Dawn {label} on Acme")
assert.equal(T.fillTemplate("{number} · {total} · {firstItem}{moreItems}\n{orders} today · {sales}",
  { number: "#1001", total: "$9.00", firstItem: "Mug {orders}{sales}", moreItems: "", orders: "12", sales: "$900.00" }),
  "#1001 · $9.00 · Mug {orders}{sales}\n12 today · $900.00")
assert.equal(T.fillTemplate("{a} {missing}", { a: "x" }), "x {missing}")
assert.equal(T.fillTemplate("{toString}", {}), "{toString}")
