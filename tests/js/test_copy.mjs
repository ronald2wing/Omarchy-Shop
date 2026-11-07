// js/copy.mjs: the texts derived from the strings (errorOf's variants, the
// folder warning, Edit's target picker rows).
import assert from "node:assert/strict"
import * as C from "../../js/copy.mjs"
import * as E from "../../js/errors.mjs"
import * as T from "../../js/themes.mjs"

// errorOf: store_busy names the work (or what to stop); folder_unusable the action.
assert.equal(C.errorOf(E.storeBusy("pull").error), "Wait for the pull to finish")
assert.equal(C.errorOf(E.storeBusy("preview", "push").error), "Stop the preview before you push")
assert.equal(C.errorOf(E.storeBusy("grant").error), "Wait for the sales access grant to finish")
assert.equal(C.errorOf(E.anyStoreBusy("job").error), "Wait for the running push, pull, restore or preview to finish")
assert.equal(C.errorOf(E.anyStoreBusy("access").error), "Wait for the sales access grant in your browser to finish")
assert.equal(C.errorOf({ code: "store_busy", message: "" }), "Another action is running for this store", "another process holds the store")
assert.equal(C.errorOf(E.folderUnusable("preview", "unsafe").error), "Can't preview: fix the folder first")
assert.equal(C.errorOf(E.folderUnusable("push", "empty").error), "Can't push an empty folder: pull a theme into it first")

// folderWarning: only an inspection of that folder, and nothing for a usable one.
const fold = f => ({ folder: Object.assign(T.emptyFolder(), { status: "ok", requested: "/f" }, f) })
assert.equal(C.folderWarning(null, "/f"), "")
assert.equal(C.folderWarning(fold({ exists: true, safe: true, themeShaped: true }), "/f"), "")
assert.equal(C.folderWarning(fold({ exists: true, safe: true, empty: true }), "/f"), "", "an empty folder is a pull target")
assert.equal(C.folderWarning(fold({ exists: true, safe: true }), "/f"), C.t("error.not_a_theme_folder"))
assert.equal(C.folderWarning(fold({ exists: false }), "/f"), C.t("theme.folderMissing"))
assert.equal(C.folderWarning(fold({ exists: true, safe: false, reason: "symlink" }), "/f"), C.t("theme.unsafe.symlink"))
assert.equal(C.folderWarning(fold({ status: "error", error: { code: "timeout", message: "" } }), "/f"), C.errorOf({ code: "timeout", message: "" }))
assert.equal(C.folderWarning(fold({ exists: false }), "/other"), "", "another folder's inspection")

// themeTargetOptions: live first (with its name), the rest by name, and a
// saved id the list doesn't have.
const ts = { themes: { status: "ok", items: [{ id: "2", name: "Dev", role: "unpublished" }, { id: "1", name: "Dawn", role: "live" }] } }
assert.deepEqual(C.themeTargetOptions(ts, "live"), [
  { value: "live", label: "Live theme · Dawn", description: "" },
  { value: "2", label: "Dev", description: "unpublished · 2" }
])
assert.deepEqual(C.themeTargetOptions(ts, "9").map(o => o.value), ["live", "2", "9"])
assert.equal(C.themeTargetOptions(ts, "9")[2].label, "Theme 9")
assert.deepEqual(C.themeTargetOptions(null, ""), [{ value: "live", label: "Live theme", description: "" }], "no list yet: the live row only")
