// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// The panel's store view (PanelHarness): what Enter, the theme keys, the
// footer and the sheet offer in each state, and the theme card's result
// wording.
// Run alone: tests/run tests/qml/panel_store_smoke.qml
ShellRoot {
  id: root

  PanelHarness { id: h }

  Smoke {
    id: smoke
    name: "PANEL_STORE"
    steps: [
      function() {
        // 1. A store that still needs sales access: no period switch.
        h.publish({ stores: [h.acmeLinked()], salesState: h.salesOf(h.accessState()) })
        h.panel.navigate({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.viewName === "store" && h.panel.view.needsAccess === true, "store needs access")
        smoke.check(h.footerIs(["hints.grant", "hints.push", "hints.pull", "hints.backups"]), "access footer, got " + h.footerKeys())
        smoke.check(h.panel.periodId === "today", "period starts at today")
        h.panel.view.textKey("3")
        h.panel.view.moveCursor(1, 0)
        smoke.check(h.panel.periodId === "today", "1–6 and h/l leave the period alone while the switch is hidden, got " + h.panel.periodId)
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("Enter / a") >= 0 && keys.indexOf("1–6") < 0 && keys.indexOf("h / l") < 0, "access sheet: Enter / a, no period keys: " + keys.join(","))
        smoke.check(keys.indexOf("p") >= 0, "access sheet keeps the theme keys of a linked folder")
        // 2. Figures, but no theme folder: Enter chooses one.
        var sales = {}
        sales[h.beta] = h.figuresState()
        h.publish({ stores: [h.cfgStore(h.beta, "Beta", "")], salesState: sales })
        h.panel.navigate({ view: "store", domain: h.beta })
      },
      function() {
        smoke.check(h.panel.viewName === "store" && h.panel.view.figuresShown === true && h.panel.view.linked === false, "store with figures and no folder")
        smoke.check(h.footerIs(["hints.choose.folder", "hints.period", "hints.backups", "hints.edit"]), "no-folder footer, got " + h.footerKeys())
        // Backups are per store and restore needs no folder: an unlinked
        // store still loads its count (never a false "Backups (0)").
        smoke.check(h.service.calls.indexOf("listBackups " + h.beta) >= 0, "an unlinked store lists its backups, calls " + h.service.calls.join(","))
        h.panel.view.textKey("3")
        smoke.check(h.panel.periodId === "last7d", "3 jumps to 7d while the switch shows, got " + h.panel.periodId)
        h.panel.view.textKey("1")
        smoke.check(h.panel.periodId === "today", "1 jumps back to today")
        var keys = h.sheetKeys()
        smoke.check(h.sheetText("Enter") === h.t("keys.chooseFolder"), "no-folder sheet: Enter chooses a folder")
        smoke.check(keys.indexOf("p") < 0 && keys.indexOf("u") < 0 && keys.indexOf("1–6") >= 0, "no-folder sheet: period keys, no theme keys: " + keys.join(","))
        h.panel.view.activate()
        smoke.check(h.folderAsks === 1, "Enter asks for a folder, got " + h.folderAsks)
        // 3. Figures, a folder and a failed push with details: t opens the
        //    box and scrolls it into view.
        var lines = []
        for (var i = 1; i <= 14; i++) lines.push("stderr line " + i + " of the CLI's cleaned tail")
        h.publishAcme({ jobState: h.forAcme({ job: null, lastResult: { ok: false, action: "push", at: Date.now(), target: "live",
          error: { code: "cli_failed", message: "The theme 'Dawn' could not be pushed." }, details: lines, backupId: "1762500001-160258293983" } }) })
        h.panel.navigate({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.viewName === "store" && h.footerIs(["hints.period", "hints.push", "hints.pull", "hints.backups"]), "linked store with figures, got " + h.footerKeys())
        var rk = h.sheetKeys()
        smoke.check(rk.indexOf("t") >= 0 && rk.indexOf("x / Delete") >= 0 && rk.indexOf("c") < 0 && rk.indexOf("v") < 0, "failed result with details: t and x, no c/v: " + rk.join(","))
        var box = h.panel.view.card.detailsItem
        smoke.check(!!box && box.visible === false, "details closed before t")
        h.panel.view.textKey("t")
      },
      function() {
        var box = h.panel.view.card.detailsItem
        smoke.check(!!box && box.visible === true && box.height > 0, "t opens the details box")
        var p = box.mapToItem(h.panel, 0, 0)
        smoke.check(p.y >= 0 && p.y + box.height <= h.panel.height, "the details box is inside the panel after t, top " + Math.round(p.y) + " bottom " + Math.round(p.y + box.height) + " of " + h.panel.height)
        smoke.check(h.panel.view.card.keptShown === true, "a failed push (writes unknown) shows the Backup kept row")
        var link = h.t("theme.backupsLink", { n: h.panel.view.card.backupCount })
        smoke.check(h.countVisibleText(h.panel.view.card, link) === 1, "a failed push card has one Backups (n) link, got " + h.countVisibleText(h.panel.view.card, link))
        h.panel.showToast("hello")
        smoke.check(h.panel.toastText === "hello", "the host reads the toast text")
        // 4. A stopped push or restore says nothing reached the theme only
        //    on the helper's own writeStarted: false; a helper killed before
        //    its line (no writeStarted) is hedged, as is a synthesized timeout.
        h.publishEnded("push", { writeStarted: false })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.none.push", { theme: h.t("theme.liveTheme") }), "a push stopped before the CLI push: " + h.panel.view.card.resultLine)
        h.publishEnded("push", {})
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", h.themeMayHaveChanged()), "a killed push (no writeStarted) is hedged, never early: " + h.panel.view.card.resultLine)
        smoke.check(h.panel.view.card.resultLine.indexOf("before anything") < 0, "a killed push never says nothing was pushed")
        h.publishEnded("push", { writeStarted: true, backupId: "1762500001-160258293983" })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", h.themeMayHaveChanged()), "a push stopped during the CLI push: " + h.panel.view.card.resultLine)
        smoke.check(h.panel.view.card.keptShown === true, "a stopped push whose writes began shows the Backup kept row")
        h.publishEnded("push", { error: { code: "timeout", message: "push-theme took too long" } })
      },
      function() {
        var failed = { action: h.t("job.title.push"), message: h.t("error.timeout").replace(/[.\s]+$/, ""), mayHaveChanged: h.themeMayHaveChanged().mayHaveChanged }
        smoke.check(h.resultIs("result.failed.maybe", failed), "a push whose helper timed out before its line is hedged: " + h.panel.view.card.resultLine)
        h.publishEnded("restore", { writeStarted: false })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.none.restore", { theme: h.t("theme.liveTheme") }), "a restore stopped before the CLI push: " + h.panel.view.card.resultLine)
        h.publishEnded("restore", {})
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", h.themeMayHaveChanged()), "a killed restore (no writeStarted) is hedged, never early: " + h.panel.view.card.resultLine)
        h.publishEnded("restore", { writeStarted: true, backupId: "1762500001-160258293983" })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", h.themeMayHaveChanged()), "a restore stopped during the CLI push: " + h.panel.view.card.resultLine)
        // 5. A stopped pull: early (the CLI pull never began), with a folder
        //    copy, and unknown (a killed helper) is hedged.
        h.publishEnded("pull", { writeStarted: false })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.none.pull", { folder: "/work/acme" }), "a pull stopped before the CLI pull: " + h.panel.view.card.resultLine)
        h.publishEnded("pull", { writeStarted: true, folderCopy: "1762500001" })
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", { mayHaveChanged: h.t("result.mayHaveChanged.folder", { folder: "/work/acme" }) }), "a pull stopped after its folder copy: " + h.panel.view.card.resultLine)
        h.publishEnded("pull", {})
      },
      function() {
        smoke.check(h.resultIs("result.stopped.maybe", { mayHaveChanged: h.t("result.mayHaveChanged.folder", { folder: "/work/acme" }) }), "a killed pull (no writeStarted) is hedged, never early: " + h.panel.view.card.resultLine)
        // 6. The store above Home: Esc / Backspace go back, ↑/↓ scroll.
        h.publishAcme()
        h.panel.navigate({ view: "home" })
        h.panel.push({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.viewName === "store" && h.panel.keySheetItem.canGoBack === true, "store pushed above home")
        smoke.check(h.sheetText("Esc / Backspace", "navigate") === h.t("action.back"), "Store: Esc / Backspace go back")
        smoke.check(h.sheetText("↑/↓ or j/k", "navigate") === h.t("keys.scroll"), "Store: ↑/↓ scroll")
        // 7. Signed out with cached figures: Enter signs in, the period
        //    switch stays, and the theme keys are offered as signed in
        //    (Service does not refuse them signed out).
        h.publishAcme({ account: { status: "signed_out", error: null } })
        h.panel.navigate({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.footerIs(["hints.signIn", "hints.period", "hints.push", "hints.pull"]), "signed out with figures footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("Enter") >= 0 && keys.indexOf("h / l") >= 0 && keys.indexOf("p") >= 0 && keys.indexOf("u") >= 0 && keys.indexOf("d") >= 0 && keys.indexOf("b") >= 0, "signed-out sheet: Enter, period and p/u/d/b: " + keys.join(","))
        smoke.check(h.sheetText("Enter") === h.t("setup.signIn"), "signed-out sheet: Enter signs in")
        smoke.check(h.footerHas("hints.push") && h.footerHas("hints.pull") && h.footerHas("hints.signIn"), "signed-out footer offers sign in, push and pull")
        smoke.check(h.panel.view.card.canPush === true && h.panel.view.card.refusal("push") === "" && h.panel.view.card.refusal("pull") === "" && h.panel.view.card.refusal("preview") === "", "signed out: push, pull and preview are not refused")
        smoke.check(h.panel.banner && h.panel.banner.id === "signedOut", "signed out: the signed-out banner, got " + (h.panel.banner ? h.panel.banner.id : "none"))
        smoke.check(h.t("banner.signedOut.body").indexOf("push or pull") < 0 && h.t("confirm.signOut.body").indexOf("Push, pull, preview and finding stores need you to sign in again") > 0 && h.t("confirm.signOut.body").indexOf("keep working with each store") < 0 && h.t("banner.signedOut.body").indexOf("until Shopify asks you to sign in again") > 0 && h.t("banner.signedOut.body").indexOf("Sign out") < 0, "sign-out copy: theme actions need a sign-in after Sign out (auth logout deletes the session store); the signed-out banner does not talk about signing out")
        h.panel.view.textKey("u")
        smoke.check(h.panel.confirmFlow.opened === true, "u signed out opens the pull dialog")
        h.panel.confirmFlow.close(false)
        var before = h.service.calls.length
        h.panel.view.activate()
        smoke.check(h.callsSince(before).indexOf("signIn") >= 0, "Enter signs in, got " + JSON.stringify(h.callsSince(before)))
        // 8. Signed out without a folder: Enter still signs in, no p/u/d.
        h.publish({ stores: [h.cfgStore(h.acme, "Acme", "")], salesState: h.salesOf(h.figuresState()), account: { status: "signed_out", error: null } })
      },
      function() {
        smoke.check(h.footerIs(["hints.signIn", "hints.period", "hints.backups", "hints.edit"]), "signed out, no folder footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("Enter") >= 0 && keys.indexOf("p") < 0 && keys.indexOf("u") < 0, "signed out, no folder: Enter, no p/u: " + keys.join(","))
        // 9. Signed out, a theme job that failed on the store's expired
        //    session still raises its own banner; one that failed
        //    signed_out shows its result under the signed-out banner.
        h.publishAcme({ account: { status: "signed_out", error: null },
                        jobState: h.forAcme({ job: null, lastResult: { ok: false, action: "pull", at: Date.now(), target: "live", error: { code: "theme_session_expired", message: "" }, details: [] } }) })
      },
      function() {
        smoke.check(h.panel.banner && h.panel.banner.id === "sessionExpired", "signed out, theme session expired: sessionExpired banner, got " + (h.panel.banner ? h.panel.banner.id : "none"))
        smoke.check(h.panel.view.resultShown === true, "signed out: the failed job's result shows")
        h.publishAcme({ account: { status: "signed_out", error: null },
                        jobState: h.forAcme({ job: null, lastResult: { ok: false, action: "push", at: Date.now(), target: "live", error: { code: "signed_out", message: "" }, details: [] } }) })
      },
      function() {
        smoke.check(h.panel.banner && h.panel.banner.id === "signedOut", "a job failed signed_out: signedOut banner, got " + (h.panel.banner ? h.panel.banner.id : "none"))
        smoke.check(h.panel.view.resultShown === true, "a job failed signed_out: its result shows")
        // 10. A running job: c cancels, p/u are not offered.
        h.publishAcme({ themesBusy: "job", jobState: h.forAcme({ job: { action: "pull", startedAt: Date.now(), target: "live" }, lastResult: null }) })
      },
      function() {
        smoke.check(h.footerIs(["hints.cancel", "hints.period", "hints.backups", "hints.edit"]), "job running footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("c") >= 0 && keys.indexOf("p") < 0 && keys.indexOf("u") < 0 && keys.indexOf("h / l") >= 0, "job sheet: c and period, no p/u: " + keys.join(","))
        // Remove mid-job is refused before any dialog (it would stop the job).
        var removeCalls = h.service.calls.length
        smoke.check(h.panel.confirm({ action: "remove", domain: h.acme }) === false && h.panel.confirmFlow.opened === false, "remove during a job opens no dialog")
        // Preflight names the work holding the store (Copy.errorOf).
        smoke.check(h.panel.toastText === h.t("error.store_busy.action", { action: h.t("job.noun.pull") }), "remove during a job says which job to wait for, got " + h.panel.toastText)
        smoke.check(h.callsSince(removeCalls).indexOf("removeStore") < 0, "remove during a job never reaches the service")
        // Sign out mid-job is refused before its dialog (it would delete the
        // session the job reads; Preflight.requireThemesIdle refuses the same).
        smoke.check(h.panel.confirm({ action: "signOut" }) === false && h.panel.confirmFlow.opened === false, "sign out during a job opens no dialog")
        smoke.check(h.panel.toastText === h.t("error.store_busy.anyStore") && h.panel.toastText !== h.t("error.store_busy"), "sign out during a job says to wait for it, got " + h.panel.toastText)
        // 11. A job on a store that still needs sales access: c is named,
        //     no grant step, no period switch (the tabs are hidden).
        h.publish({ stores: [h.acmeLinked()], salesState: h.salesOf(h.accessState()),
                    jobState: h.forAcme({ job: { action: "push", startedAt: Date.now(), target: "live" }, lastResult: null }) })
      },
      function() {
        smoke.check(h.footerIs(["hints.cancel", "hints.backups", "hints.edit", "hints.admin"]), "needs access, job running footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("c") >= 0 && keys.indexOf("p") < 0 && keys.indexOf("u") < 0 && keys.indexOf("h / l") < 0 && keys.indexOf("1–6") < 0 && keys.indexOf("Enter / a") < 0, "needs-access job sheet: c, no p/u/period/grant: " + keys.join(","))
        smoke.check(h.footerHas("hints.cancel") && !h.footerHas("hints.period"), "needs-access job footer: cancel, no period")
        // 12. Signed out, access unknown, no figures (the empty state), a
        //     preview starting: d is named, no period switch.
        h.publish({ stores: [h.acmeLinked()], salesState: h.salesOf(h.emptySales()), account: { status: "signed_out", error: null },
                    previewState: h.forAcme({ status: "starting", url: "", error: null }) })
      },
      function() {
        smoke.check(h.panel.view.emptyShown === true && h.footerIs(["hints.stopPreview", "hints.backups", "hints.edit", "hints.admin"]), "signed out, empty state, preview starting footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("d") >= 0 && keys.indexOf("h / l") < 0 && keys.indexOf("1–6") < 0 && keys.indexOf("p") < 0, "empty-state preview sheet: d, no period, no p: " + keys.join(","))
        smoke.check(!h.footerHas("hints.period") && h.footerKeys()[0] === "hints.stopPreview", "empty-state preview footer: stop first, no period")
        // 13. A sign-in in flight: theme keys are refused, so none is
        //     offered; the period switch still works.
        h.publishAcme({ account: { status: "signing_in", error: null } })
      },
      function() {
        smoke.check(h.footerIs(["hints.period", "hints.backups", "hints.edit", "hints.admin"]), "signing in footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("p") < 0 && keys.indexOf("u") < 0 && keys.indexOf("d") < 0 && keys.indexOf("h / l") >= 0 && keys.indexOf("b") >= 0, "signing-in sheet: period and b, no p/u/d: " + keys.join(","))
        smoke.check(!h.footerHas("hints.push") && !h.footerHas("hints.pull"), "signing-in footer: no push or pull")
        // 14. A preview runs: d stops it, p/u/c are not offered.
        h.publishAcme({ previewState: h.forAcme({ status: "ready", url: "http://127.0.0.1:9292", error: null }) })
      },
      function() {
        smoke.check(h.footerIs(["hints.stopPreview", "hints.open.preview", "hints.period", "hints.backups"]), "preview ready footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("d") >= 0 && keys.indexOf("v") >= 0 && keys.indexOf("p") < 0 && keys.indexOf("u") < 0 && keys.indexOf("c") < 0 && keys.indexOf("h / l") >= 0,
          "preview sheet: d, v and period, no p/u/c: " + keys.join(","))
        smoke.check(h.sheetText("d") === h.t("keys.stopPreview"), "preview sheet: d stops the preview")
        // 15. The folder unlinked under a running preview (an older config
        //     or an external edit): d still stops it, never asks for a folder.
        h.publish({ stores: [h.cfgStore(h.acme, "Acme", "")], salesState: h.salesOf(h.figuresState()),
                    previewState: h.forAcme({ status: "ready", url: "http://127.0.0.1:9292", error: null }) })
        var asks = h.folderAsks
        h.panel.view.textKey("d")
        smoke.check(h.service.calls[h.service.calls.length - 1] === "stopPreview " + h.acme && h.folderAsks === asks, "d on an unlinked store with a preview stops it, got " + h.service.calls.slice(-1) + " asks " + (h.folderAsks - asks))
        // 16. Granting: Enter / a cancel the grant.
        var st = h.figuresState()
        st.salesAccess = "granting"
        h.publish({ stores: [h.acmeLinked()], salesState: h.salesOf(st) })
      },
      function() {
        smoke.check(h.footerIs(["hints.cancel", "hints.backups", "hints.edit", "hints.admin"]), "granting footer, got " + h.footerKeys())
        smoke.check(h.sheetText("Enter / a") === h.t("keys.cancelGrant"), "granting sheet: Enter / a cancel")
        // The service refuses push, pull, restore and preview while a grant
        // runs (store_busy/access): no theme row, no dialog, the toast says why.
        var gk = h.sheetKeys()
        smoke.check(["p", "u", "d", "v", "c"].every(function(k) { return gk.indexOf(k) < 0 }), "granting sheet: no p/u/d/v/c rows: " + gk.join(","))
        smoke.check(!h.footerHas("hints.push") && !h.footerHas("hints.pull"), "granting footer offers no push or pull")
        var grantTip = h.t("error.store_busy.action", { action: h.t("job.noun.grant") })
        var dPreviews = h.service.calls.length
        h.panel.view.textKey("p")
        smoke.check(!h.panel.confirmFlow.opened && h.panel.toastText === grantTip, "p during a grant: toast, no dialog, got " + h.panel.toastText)
        h.panel.view.textKey("u")
        smoke.check(!h.panel.confirmFlow.opened && h.panel.toastText === grantTip, "u during a grant: toast, no dialog")
        h.panel.view.textKey("d")
        smoke.check(!h.panel.confirmFlow.opened && h.panel.toastText === grantTip && h.service.calls.length === dPreviews, "d during a grant: refused, no preview")
        smoke.check(h.panel.confirm({ action: "restore", domain: h.acme, backupId: h.backupRow.id }) === false && !h.panel.confirmFlow.opened, "restore during a grant: no dialog")
        // 17. A sign-in in flight: Service refuses push, pull, restore and
        //     preview (account_busy), so p/u/d toast that before any dialog,
        //     and panel.confirm opens none (not even the allow-live stage).
        h.publishAcme({ account: { status: "signing_in", error: null } })
      },
      function() {
        var busyTip = h.t("error.account_busy")
        var before = h.service.calls.length
        ;["p", "u", "d"].forEach(function(k) {
          h.panel.view.textKey(k)
          smoke.check(!h.panel.confirmFlow.opened && h.panel.toastText === busyTip, "signing in: " + k + " toasts account_busy, no dialog, got " + h.panel.toastText)
        })
        smoke.check(h.service.calls.length === before, "signing in: p/u/d reach no service call, got " + JSON.stringify(h.callsSince(before)))
        smoke.check(h.panel.view.card.refusal("push") === busyTip && h.panel.view.card.refusal("pull") === busyTip && h.panel.view.card.refusal("preview") === busyTip, "signing in: the card refuses push, pull and preview")
        ;["push", "pull"].forEach(function(a) {
          smoke.check(h.panel.confirm({ action: a, domain: h.acme }) === false && !h.panel.confirmFlow.opened && h.panel.toastText === busyTip, "signing in: confirm " + a + " opens no dialog (no allow-live stage)")
        })
        smoke.check(h.panel.confirm({ action: "restore", domain: h.acme, backupId: h.backupRow.id }) === false && !h.panel.confirmFlow.opened, "signing in: restore opens no dialog")
        // 18. The same while a sign-out runs.
        h.publishAcme({ account: { status: "signing_out", error: null } })
      },
      function() {
        h.panel.view.textKey("u")
        smoke.check(!h.panel.confirmFlow.opened && h.panel.toastText === h.t("error.account_busy"), "signing out: u toasts account_busy, no dialog")
        // 19. The CLI missing over cached figures: the period switch stays,
        //     Enter installs, and no p/u/d is offered (each would only be
        //     refused).
        h.publishAcme({ cli: h.cliMissing })
      },
      function() {
        smoke.check(h.panel.view.figuresShown === true && h.footerIs(["hints.install", "hints.period", "hints.backups", "hints.edit"]), "CLI missing with figures footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("Enter") >= 0 && keys.indexOf("h / l") >= 0 && ["p", "u", "d"].every(function(k) { return keys.indexOf(k) < 0 }), "CLI missing with figures sheet: Enter and period, no p/u/d: " + keys.join(","))
        smoke.check(h.sheetText("Enter") === h.t("setup.cli.missing"), "CLI missing with figures: Enter installs")
        smoke.check(h.footerHas("hints.install") && h.footerHas("hints.period") && !h.footerHas("hints.push") && !h.footerHas("hints.pull"), "CLI missing with figures footer: install and period, no push or pull")
        h.panel.view.activate()
        smoke.check(h.panel.confirmFlow.opened && h.panel.confirmFlow.activeSpec && h.panel.confirmFlow.activeSpec.action === "installCli", "CLI missing with figures: Enter opens the install dialog, got " + (h.panel.confirmFlow.activeSpec ? h.panel.confirmFlow.activeSpec.action : "none"))
        h.panel.confirmFlow.close(false)
        // 20. Sales access needed and no theme folder: the footer offers no
        //     p/u (they would open the folder picker), like the sheet.
        h.publish({ stores: [h.cfgStore(h.acme, "Acme", "")], salesState: h.salesOf(h.accessState()) })
      },
      function() {
        smoke.check(h.footerIs(["hints.grant", "hints.backups", "hints.edit", "hints.admin"]), "access needed, no folder footer, got " + h.footerKeys())
        var keys = h.sheetKeys()
        smoke.check(keys.indexOf("Enter / a") >= 0 && keys.indexOf("p") < 0 && keys.indexOf("u") < 0, "access needed, no folder sheet: Enter / a, no p/u: " + keys.join(","))
        smoke.check(h.footerHas("hints.grant") && !h.footerHas("hints.push") && !h.footerHas("hints.pull"), "access needed, no folder footer: grant, no push or pull")
        // 21. config.json breaks under the store view: the store is unknown,
        //     the footer offers only the banner's keys, Enter just says so.
        h.publishBroken()
      },
      function() {
        smoke.check(h.panel.viewName === "store" && h.footerIs(["hints.broken"]), "broken store view: the banner's keys only, got " + h.panel.viewName + " " + h.footerKeys())
        smoke.check(h.panel.keySheetItem.viewRows.length === 0, "broken store sheet has no view rows: " + JSON.stringify(h.sheetRows()))
        h.panel.view.activate()
        smoke.check(h.panel.toastText === h.t("error.config_invalid"), "Enter on a broken store says config.json needs fixing, got " + h.panel.toastText)
        // 22. A preview whose process was killed: "ended", not "stopped: Stopped".
        h.publishAcme({ previewState: h.forAcme({ status: "failed", url: "", error: { code: "terminated", message: "" } }) })
        h.panel.navigate({ view: "store", domain: h.acme })
      },
      function() {
        smoke.check(h.panel.view.card.previewLine === h.t("theme.preview.ended"), "killed preview line, got " + h.panel.view.card.previewLine)
        smoke.check(h.panel.view.card.targetName === h.t("theme.liveTheme") && h.panel.view.card.liveChipShown === false, "\"Live theme\" placeholder has no LIVE chip beside it")
        var themes = { status: "ok", items: [{ id: "160258293983", name: "Dawn", role: "live" }], fetchedAt: Date.now(), error: null }
        h.publishAcme({ infoState: h.infoOf(themes, null) })
      },
      function() {
        smoke.check(h.panel.view.card.targetName === "Dawn" && h.panel.view.card.liveChipShown === true, "a named live theme keeps its LIVE chip, got " + h.panel.view.card.targetName + " " + h.panel.view.card.liveChipShown)
        // 23. The sheet lists v, t, x and c only when they act: an idle
        //     linked store has p/u/d; a result without details adds x.
        h.publishAcme()
      },
      function() {
        var idle = h.sheetKeys()
        smoke.check(h.footerIs(["hints.period", "hints.push", "hints.pull", "hints.backups"]) && idle.indexOf("p") >= 0 && idle.indexOf("u") >= 0 && idle.indexOf("d") >= 0, "idle store: p/u/d, got " + h.footerKeys() + " " + idle.join(","))
        smoke.check(["v", "c", "t", "x / Delete"].every(function(k) { return idle.indexOf(k) < 0 }), "idle store: no v/c/t/x rows: " + idle.join(","))
        h.publishAcme({ jobState: h.forAcme({ job: null, lastResult: { ok: true, action: "pull", at: Date.now(), target: "live", error: null, details: [] } }) })
      },
      function() {
        var done = h.sheetKeys()
        smoke.check(done.indexOf("x / Delete") >= 0 && done.indexOf("t") < 0, "result without details: x, no t: " + done.join(","))
      }
    ]
  }
}
