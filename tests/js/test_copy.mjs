// js/copy.mjs: the texts derived from the strings (errorOf's variants and
// slots).
import assert from "node:assert/strict"
import * as C from "../../js/copy.mjs"
import * as E from "../../js/results.mjs"

// errorOf: store_busy names the work (or what to stop); folder_unusable the action.
assert.equal(C.errorOf(E.storeBusy("pull").error), "Wait for the pull to finish")
assert.equal(C.errorOf(E.storeBusy("preview", "push").error), "Stop the preview before you push")
assert.equal(C.errorOf(E.storeBusy("grant").error), "Wait for the sales access grant to finish")
assert.equal(C.errorOf(E.anyStoreBusy("job").error), "Wait for the running push, pull, restore or preview to finish")
assert.equal(C.errorOf(E.anyStoreBusy("grant").error), "Wait for the sales access grant in your browser to finish")
assert.equal(C.errorOf({ code: "store_busy", message: "" }), "Another action is running for this store", "another process holds the store")
assert.equal(C.errorOf(E.folderUnusable("preview", "unsafe").error), "Can't preview: fix the folder first")
assert.equal(C.errorOf(E.folderUnusable("push", "empty").error), "Can't push an empty folder: pull a theme into it first")
// The error's own fields fill the string's other slots.
assert.equal(C.errorOf(E.tooManyStores(7).error), "Shop keeps at most 7 stores")

