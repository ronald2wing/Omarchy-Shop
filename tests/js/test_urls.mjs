// js/urls.mjs: the open-URL allowlist.
import assert from "node:assert/strict"
import { CONFIG_REL, STATE_REL, adminUrl, configFileUrl, stateDirUrl, isSafeOpenUrl } from "../../js/urls.mjs"

const D = "acme.myshopify.com"
const H = "/home/u"

assert.equal(adminUrl(D), "https://acme.myshopify.com/admin")
assert.equal(adminUrl("evil.com"), "")
assert.equal(configFileUrl("/home/u/"), "file:///home/u/.config/shop/config.json")
assert.equal(configFileUrl("relative"), "")
assert.equal(configFileUrl("/home/u/../x"), "")
assert.equal(configFileUrl(null), "")
assert.equal(stateDirUrl("/home/u/"), "file:///home/u/.local/state/shop")
assert.equal(stateDirUrl("relative"), "")

const safe = [
  "https://acme.myshopify.com/admin",
  "https://acme.myshopify.com/admin/themes/1",
  "https://acme.myshopify.com/admin?x=1",
  "http://127.0.0.1:9292/",
  "http://127.0.0.1:9292",
  "http://127.0.0.1:65535/products/tee",
  "file:///home/u/.local/state/shop/backups/acme.myshopify.com/local/1762400000",
  "file:///home/u/.config/shop/config.json",
  "file:///home/u/.local/state/shop"
]
for (const u of safe) assert(isSafeOpenUrl(u, D, H), "safe: " + u)
// The config file and the state folder need no store.
assert(isSafeOpenUrl("file:///home/u/.config/shop/config.json", "", H))
assert(isSafeOpenUrl("file:///home/u/.local/state/shop", "", H))
assert(isSafeOpenUrl("file:///home/u/.config/shop/config.json", null, "/home/u/"))

const unsafe = [
  "", null, 42,
  "https://acme.myshopify.com/adminx",
  "https://acme.myshopify.com.evil.tld/admin",
  "https://acme.myshopify.com@evil.tld/admin",
  "https://beta.myshopify.com/admin",
  "https://acme.myshopify.com/",
  "http://acme.myshopify.com/admin",
  "http://127.0.0.1:80/",
  "http://127.0.0.1:1023/",
  "http://127.0.0.1:65536/",
  "http://127.0.0.1:09292/",
  "http://127.0.0.2:9292/",
  "http://localhost:9292/",
  "http://127.0.0.1:9292@evil.tld/",
  "http://127.0.0.1:9292/ x",
  "https://acme.myshopify.com/admin\nx",
  "file:///home/u/.local/state/shop/backups/acme.myshopify.com/local/1762400000/x",
  "file:///home/u/.local/state/shop/backups/acme.myshopify.com/local/176240000",
  "file:///home/u/.local/state/shop/backups/beta.myshopify.com/local/1762400000",
  "file:///home/u/.config/shop/config.json.old",
  "file:///home/u/.local/state/shop/",
  "file:///home/u/.local/state/shop/cache.json",
  "file:///home/u/.local/state/shop/backups",
  "file:///home/u/.local/state/shopx",
  "file:///home/u/.config/shop/",
  "file:///home/uu/.config/shop/config.json",
  "file:///etc/passwd",
  "javascript:alert(1)",
  "ftp://acme.myshopify.com/admin"
]
for (const u of unsafe) assert(!isSafeOpenUrl(u, D, H), "unsafe: " + JSON.stringify(u))
// A bad home or domain never opens files.
assert(!isSafeOpenUrl("file:///x/.local/state/shop/backups/acme.myshopify.com/local/1762400000", D, "relative"))
assert(!isSafeOpenUrl("file:///home/u/.config/shop/config.json", D, "relative"))
assert(!isSafeOpenUrl("https://evil.com/admin", "evil.com", H))

// The displayed paths and the file URLs agree.
assert.equal(configFileUrl(H), "file://" + H + CONFIG_REL)
assert.equal(stateDirUrl(H), "file://" + H + STATE_REL)
