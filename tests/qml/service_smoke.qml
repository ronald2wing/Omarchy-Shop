// runner: quickshell
import QtQuick
import Quickshell
import Quickshell.Io
import "shop/js/snapshot.mjs" as Snapshot
import "shop/tests/qml"

// The real Service against the fake CLI in the throwaway HOME that
// tests/qml/fake-home.sh builds (three stores linked to theme folders).
// Checks: the CLI guard answers cli_checking before check-account has
// run; nothing lists themes at startup; a running preview makes the store
// busy; one confirmation at a time and a decline holds every request for
// 30 s; an IPC add refuses a label Config would reject; while
// config.json is unreadable a store action says so (config_invalid), never
// "That store isn't in Shop", and a config write says config_invalid; a
// config.json missing for a moment (rename-style save) forgets nothing,
// one still missing after the re-check is an empty config, and a removal
// it refuses meanwhile forgets nothing; Sign out cancels a running
// discovery; sign-in and sign-out refuse (store_busy) while a preview or
// theme job runs on any store; Reset config refuses while a preview (the
// config broken) or a grant runs, and keeps a config that reads again; a
// discovery started during a sign-out can't undo it; status() keeps
// per-store object identity across the next publish.
// Run alone: tests/run tests/qml/service_smoke.qml
ShellRoot {
  id: root

  readonly property var domains: ["acme.myshopify.com", "beta.myshopify.com", "gamma.myshopify.com"]
  property var service: null
  property string addId: ""
  // Consent's clock: a decline holds requests for 30 s of it.
  property real now: 1762520400000

  property string goodConfig: ""
  property real d1FetchedAt: 0

  FileView {
    id: cfgFile
    path: Quickshell.env("HOME") + "/.config/shop/config.json"
    blockLoading: true
    blockWrites: true
    printErrors: false
  }

  function move(from, to) {
    mover.command = ["mv", "-f", from, to]
    mover.running = true
  }

  Process { id: mover }

  // Signed out, theme actions are not refused (Service leaves it to the
  // CLI's stored theme tokens). A theme job that then fails on an
  // expired theme session still raises its own banner.
  FileView {
    id: scenarioFile
    path: Quickshell.env("HOME") + "/.fake-shopify/scenario"
    blockWrites: true
    printErrors: false
  }

  property var gammaBefore: null

  Smoke {
    id: smoke
    name: "SERVICE"
    interval: 0
    steps: [
      function() {
        const c = Qt.createComponent(Qt.resolvedUrl("shop/Service.qml"), Component.PreferSynchronous)
        if (c.status !== Component.Ready) {
          smoke.check(false, "cannot load shop/Service.qml: " + c.errorString())
          smoke.finish()
          return
        }
        const service = c.createObject(root, { manifest: { id: "shop", version: "9.9.9" }, consentClock: function () { return root.now } })
        root.service = service
        // Before check-account has answered, every CLI-backed action says so;
        // before the config has loaded, no store is known yet.
        const r = service.requestPush(root.domains[0])
        smoke.check(!r.ok && r.error.code === "unknown_store", "requestPush before the config loads -> unknown_store, got " + JSON.stringify(r))
        smoke.check(service.signIn().error.code === "cli_checking", "signIn before the CLI check -> cli_checking")
        smoke.check(service.requestInstallCli().error.code === "cli_checking", "requestInstallCli before the CLI check -> cli_checking")
        const s = service.status()
        smoke.check(s.ok && s.version === "9.9.9", "status().version comes from the manifest, got " + JSON.stringify(s.version))
        smoke.check(s.pins && s.pins.cli === Snapshot.CLI_PIN && s.pins.node === Snapshot.NODE_PIN, "status().pins")
        smoke.check(service.requestPush("nope.myshopify.com").error.code === "unknown_store", "unknown store")
        smoke.check(service.snapshot.cli.status === "unknown", "initial snapshot")
      },
      // check-account has answered and config.json has loaded.
      smoke.waitFor(() => root.service.snapshot.cli.status === "ready" && root.service.snapshot.account.status === "signed_in"
                          && root.domains.every(d => !!root.service.snapshot.stores[d]), "the CLI check and the three stores", 15000),
      function() {
        const service = root.service
        const snap = service.snapshot
        smoke.check(snap.cli.status === "ready", "CLI ready, got " + snap.cli.status)
        smoke.check(snap.account.status === "signed_in", "signed in, got " + snap.account.status)
        smoke.check(service.storeOrder.length === 3, "three stores, got " + service.storeOrder.length)
        for (let i = 0; i < root.domains.length; i++) {
          const st = snap.stores[root.domains[i]]
          smoke.check(!!st, "store " + root.domains[i] + " published")
          if (!st) continue
          smoke.check(st.themeState.themes.status === "idle" && st.themeState.themes.fetchedAt === 0, "no list-themes at startup for " + root.domains[i] + ", got " + st.themeState.themes.status)
          smoke.check(st.label !== "" && !!st.theme && st.theme.folder !== "", "linked store " + root.domains[i])
        }
        const d0 = root.domains[0]
        const d1 = root.domains[1]
        const d2 = root.domains[2]
        // A preview holds the store until it stops.
        const p = service.startPreview(d0)
        smoke.check(p.ok === true, "startPreview, got " + JSON.stringify(p))
        const busy = service.requestPush(d0)
        smoke.check(!busy.ok && busy.error.code === "store_busy" && busy.error.action === "preview", "requestPush during a preview -> store_busy(preview), got " + JSON.stringify(busy))
        smoke.check(service.requestPull(d0).error.code === "store_busy", "requestPull during a preview -> store_busy")
        smoke.check(service.startPreview(d0).error.code === "store_busy", "second preview -> store_busy")
        smoke.check(service.requestInstallCli().ok === true, "requestInstallCli with the CLI ready is a no-op")
        // A new folder or target (or none) under the running preview is
        // refused like remove; a change that keeps both still writes.
        const cleared = service.updateStore(d0, JSON.stringify({ theme: null }))
        smoke.check(!cleared.ok && cleared.error.code === "store_busy" && cleared.error.action === "preview", "unlinking the folder during a preview -> store_busy(preview), got " + JSON.stringify(cleared))
        const moved = service.updateStore(d0, JSON.stringify({ theme: { folder: "/run/elsewhere" } }))
        smoke.check(!moved.ok && moved.error.code === "store_busy", "a new folder during a preview -> store_busy, got " + JSON.stringify(moved))
        smoke.check(service.updateStore(d0, JSON.stringify({ theme: { target: "123456" } })).error.code === "store_busy", "a new target during a preview -> store_busy")
        const relabel = service.updateStore(d0, JSON.stringify({ label: "Acme Two" }))
        smoke.check(relabel.ok === true, "a label change during a preview still writes, got " + JSON.stringify(relabel))
        smoke.check(service.storeOrder.length === 3 && service.snapshot.stores[d0] && !!service.snapshot.stores[d0].theme && service.snapshot.stores[d0].theme.folder !== "", "the folder stayed linked")
        service.stopPreview(d0)
        // A request opens exactly one confirmation; a decline holds them all.
        const r1 = service.requestPull(d1)
        smoke.check(r1.ok && r1.pending === "confirm", "requestPull opens a confirmation, got " + JSON.stringify(r1))
        // (d0 stays busy until its preview has stopped, so another store asks.)
        const r2 = service.requestPull(d2)
        smoke.check(!r2.ok && r2.error.code === "confirm_open", "one confirmation at a time, got " + JSON.stringify(r2))
        // The live target with allowLive off is refused before anyone is asked.
        const lv = service.requestPush(d2)
        smoke.check(!lv.ok && lv.error.code === "live_not_allowed", "push to live with allowLive off -> live_not_allowed, got " + JSON.stringify(lv))
        smoke.check(service.resolvePending(r1.id, false).ok === true, "declined")
        smoke.check(service.requestPull(d1).error.code === "recently_declined", "repeat held")
        // The hold is not per request: another store, another action and an
        // add are refused too, and no dialog opens for them.
        smoke.check(service.requestPull(d2).error.code === "recently_declined", "request for another store held")
        smoke.check(service.requestInstallCli().ok === true, "a no-op install request is still a no-op")
        smoke.check(service.requestRestore(d1, "1762500001-160258293983").error.code === "recently_declined", "restore of a made-up backup held")
        smoke.check(service.requestAddStore("delta", "").error.code === "recently_declined", "add held")
        smoke.check(service.snapshot.pendingConfirm === null, "nothing pending while held")
        root.now += 30001
        // Adding a store from IPC only asks, and only with a label Config
        // would keep: a huge one or one with control characters never
        // reaches the dialog.
        const long = new Array(20001).join("A")
        const bad1 = service.requestAddStore("delta", long)
        smoke.check(!bad1.ok && bad1.error.code === "invalid_patch", "a 20 KB label is refused, got " + JSON.stringify(bad1.error))
        const bad2 = service.requestAddStore("delta", "\u202eDelta\n\u0007")
        smoke.check(!bad2.ok && bad2.error.code === "invalid_patch", "a control-character label is refused, got " + JSON.stringify(bad2.error))
        smoke.check(service.snapshot.pendingConfirm === null, "no pendingConfirm after refused labels")
        const add = service.requestAddStore("delta", "  Delta   Outlet ")
        smoke.check(add.ok && add.pending === "confirm", "requestAddStore asks, got " + JSON.stringify(add))
        root.addId = add.id
      },
      // The snapshot publishes at most every 250 ms: the pending label and
      // the stopped preview show once it has.
      smoke.waitFor(() => !!root.service.snapshot.pendingConfirm && ["ready", "stopping", "starting"].indexOf(root.service.snapshot.stores[root.domains[0]].themeState.preview.status) < 0,
                    "the add request and the stopped preview"),
      function() {
        const service = root.service
        const d0 = root.domains[0]
        const st = service.snapshot.stores[d0]
        smoke.check(!!st && st.themeState.preview.status !== "ready", "preview stopped, got " + (st ? st.themeState.preview.status : "none"))
        smoke.check(!!st && st.themeState.preview.status !== "stopping", "preview process gone, got " + (st ? st.themeState.preview.status : "none"))
        const pc = service.snapshot.pendingConfirm
        smoke.check(!!pc && pc.action === "addStore" && pc.label === "Delta Outlet", "the add dialog gets the cleaned label, got " + JSON.stringify(pc))
        service.resolvePending(root.addId, false)
        root.now += 30001
        smoke.check(service.requestAddStore(d0, "").error.code === "duplicate_store", "duplicate add refused")
        smoke.check(service.storeOrder.length === 3, "still three stores")
        // config.json breaks under an editor: the stores are unknown, not gone.
        root.goodConfig = cfgFile.text()
        smoke.check(root.goodConfig.indexOf(d0) >= 0, "the smoke reads config.json")
        // A preview keeps running while the file is broken (the stores are
        // kept), and Reset config would forget them: refused below.
        smoke.check(service.startPreview(d0).ok === true, "a preview runs into the broken config")
        cfgFile.setText("{ \"stores\": [")
      },
      smoke.waitFor(() => !!root.service.snapshot.configError, "config.json read as broken"),
      function() {
        const service = root.service
        const d0 = root.domains[0]
        smoke.check(!!service.snapshot.configError, "config.json broken, got " + JSON.stringify(service.snapshot.configError))
        // Every config write too: the file needs fixing, Shop isn't "still loading".
        const calls = [service.requestPush(d0), service.requestRestore(d0, "1762500001-160258293983"), service.refreshStore(d0), service.removeStore(d0),
          service.updateStore(d0, JSON.stringify({ label: "Broken Name" })), service.updateStore(d0, JSON.stringify({ theme: null })),
          service.updateSettings(JSON.stringify({ pollSeconds: 120 })), service.addStore("added.myshopify.com", ""),
          service.requestAddStore("added.myshopify.com", "")]
        for (let i = 0; i < calls.length; i++)
          smoke.check(!calls[i].ok && calls[i].error.code === "config_invalid", "store action " + i + " with a broken config.json -> config_invalid, got " + JSON.stringify(calls[i]))
        // Reset forgets every store and so stops its helpers: refused while
        // the preview runs, though the snapshot lists no stores; the panel
        // reads the top-level themesBusy for the same refusal.
        smoke.check(Object.keys(service.snapshot.stores).length === 0 && service.snapshot.themesBusy === "preview", "broken config: no stores, themesBusy preview, got " + JSON.stringify(service.snapshot.themesBusy))
        const reset = service.resetConfig()
        smoke.check(!reset.ok && reset.error.code === "store_busy" && reset.error.what === "preview" && reset.error.anyStore === true, "resetConfig during a preview -> store_busy preview, got " + JSON.stringify(reset))
        cfgFile.setText(root.goodConfig)
      },
      smoke.waitFor(() => !root.service.snapshot.configError && root.service.storeOrder.length === 3, "config.json readable again"),
      function() {
        const service = root.service
        smoke.check(!service.snapshot.configError && service.storeOrder.length === 3, "config.json readable again, three stores")
        smoke.check(service.requestPush("nope.myshopify.com").error.code === "unknown_store", "an unknown store is still unknown_store")
        const pv = service.snapshot.stores[root.domains[0]].themeState.preview.status
        smoke.check(pv === "starting" || pv === "ready", "the preview survived the broken config, got " + pv)
        service.stopPreview(root.domains[0])
        // A rename-style save: config.json is gone for a moment, then back.
        root.move(cfgFile.path, cfgFile.path + "~")
      },
      // Inside the gap: before ConfigStore re-checks the missing file.
      smoke.pause(400),
      function() {
        const service = root.service
        const d0 = root.domains[0]
        smoke.check(service.storeOrder.length === 3 && !!service.snapshot.stores[d0], "config.json missing for a moment keeps every store, got " + service.storeOrder.length)
        smoke.check(!service.snapshot.configError, "a short gap is not a config error")
        const w = service.updateStore(d0, JSON.stringify({ label: "Gap" }))
        smoke.check(!w.ok && w.error.code === "config_busy", "a write during the gap waits, got " + JSON.stringify(w))
        // A removal the config refuses forgets nothing: the store keeps its
        // figures (only a written removal forgets, through configUpdated).
        const d1 = root.domains[1]
        root.d1FetchedAt = service.snapshot.stores[d1].sales.fetchedAt.today
        smoke.check(root.d1FetchedAt > 0, "the store has today's figures before the refused removal")
        const rm = service.removeStore(d1)
        smoke.check(!rm.ok && rm.error.code === "config_busy", "a removal during the gap waits, got " + JSON.stringify(rm))
        root.move(cfgFile.path + "~", cfgFile.path)
      },
      // Past the re-check, so a write is no longer held.
      smoke.pause(2500),
      function() {
        const service = root.service
        smoke.check(service.storeOrder.length === 3 && !service.snapshot.configError, "config.json back after the gap, three stores, got " + service.storeOrder.length)
        const kept = service.snapshot.stores[root.domains[1]]
        smoke.check(!!kept && kept.sales.fetchedAt.today >= root.d1FetchedAt, "a refused removal kept the store's sales record, got " + (kept ? kept.sales.fetchedAt.today : "no store"))
        smoke.check(service.updateStore(root.domains[0], JSON.stringify({ label: "Acme" })).ok === true, "writes work again after the gap")
        smoke.check(service.snapshot.themesBusy === "" && service.snapshot.granting === false, "nothing busy, got " + JSON.stringify([service.snapshot.themesBusy, service.snapshot.granting]))
        // Reset of a config that reads again (fixed while the dialog was
        // open) keeps it: nothing is renamed, no store is forgotten.
        const keep = service.resetConfig()
        smoke.check(keep.ok === true && keep.skipped === true && service.storeOrder.length === 3, "resetConfig of a readable config is a no-op, got " + JSON.stringify(keep))
        cfgFile.reload()
        smoke.check(cfgFile.text().indexOf(root.domains[0]) >= 0, "config.json kept its stores")
        // An IPC grant on a store still named after its subdomain: the grant
        // runs, but config.json keeps the label (config writes are panel-only).
        smoke.check(service.addStore("delta.myshopify.com", "").ok === true, "delta added")
        smoke.check(service.grantSalesAccess("delta.myshopify.com", "ipc").ok === true, "IPC grant starts")
        // Removing a store stops its helpers: refused while its grant runs.
        const busyRemove = service.removeStore("delta.myshopify.com")
        smoke.check(!busyRemove.ok && busyRemove.error.code === "store_busy", "remove during a grant -> store_busy, got " + JSON.stringify(busyRemove))
        const busyReset = service.resetConfig()
        smoke.check(!busyReset.ok && busyReset.error.code === "store_busy" && busyReset.error.what === "access" && busyReset.error.anyStore === true, "resetConfig during a grant -> store_busy access, got " + JSON.stringify(busyReset))
        // A discovery started before Sign out is cancelled by it: its
        // account report would otherwise undo the sign-out when it lands.
        service.discoverStores()
        smoke.check(service.signOut().ok === true, "signOut starts")
        // A sign-out in flight (Account sets signing_out synchronously):
        // requireAccountIdle refuses every theme action as account_busy, and
        // no request leaves a pending dialog behind.
        const d0 = root.domains[0]
        const busyResults = {
          requestPull: service.requestPull(d0),
          requestRestore: service.requestRestore(d0, "1762500001-160258293983"),
          requestPush: service.requestPush(d0),
          pushTheme: service.pushTheme(d0, {}),
          pullTheme: service.pullTheme(d0),
          restoreBackup: service.restoreBackup(d0, "1762500001-160258293983", {}),
          startPreview: service.startPreview(d0)
        }
        for (const name in busyResults) {
          const r = busyResults[name]
          smoke.check(!r.ok && r.error && r.error.code === "account_busy" && !r.id, "signing out: " + name + " -> account_busy, got " + JSON.stringify(r))
        }
      },
      smoke.waitFor(() => root.service.snapshot.account.status === "signed_out", "the sign-out"),
      function() {
        const service = root.service
        const d0 = root.domains[0]
        const d1 = root.domains[1]
        smoke.check(service.snapshot.account.status === "signed_out", "signed out, got " + service.snapshot.account.status)
        smoke.check(service.snapshot.discovery.status === "idle", "signOut cancelled the running discovery, got " + service.snapshot.discovery.status)
        const pull = service.requestPull(d0)
        smoke.check(pull.ok === true && pull.pending === "confirm", "signed out: requestPull opens its dialog, got " + JSON.stringify(pull))
        if (pull.ok) service.resolvePending(pull.id, false)
        root.now += 30001
        const restore = service.requestRestore(d0, "1762500001-160258293983")
        smoke.check(restore.ok === true && restore.pending === "confirm", "signed out: requestRestore opens its dialog, got " + JSON.stringify(restore))
        if (restore.ok) service.resolvePending(restore.id, false)
        const push = service.requestPush(d0)
        smoke.check(!push.ok && push.error.code === "live_not_allowed", "signed out: requestPush reaches the live rule, got " + JSON.stringify(push))
        const preview = service.startPreview(d0)
        smoke.check(preview.ok === true, "signed out: startPreview starts, got " + JSON.stringify(preview))
        // Sign-in and sign-out wait for a preview or job on any store
        // (requireThemesIdle): either would rewrite the session it reads.
        for (const fn of ["signIn", "signOut"]) {
          const r = service[fn]()
          smoke.check(!r.ok && r.error.code === "store_busy" && r.error.what === "preview" && r.error.anyStore === true, fn + " during a preview -> store_busy preview, got " + JSON.stringify(r))
        }
        if (preview.ok) service.stopPreview(d0)
        // The store's theme session expired: the job fails theme_session_expired.
        scenarioFile.setText("admin-401-theme")
        const job = service.pullTheme(d1)
        smoke.check(job.ok === true && job.started === true, "signed out: a pull starts, got " + JSON.stringify(job))
        const busyIn = service.signIn()
        smoke.check(!busyIn.ok && busyIn.error.code === "store_busy" && busyIn.error.what === "job", "signIn during a pull -> store_busy job, got " + JSON.stringify(busyIn))
        const delta = service.snapshot.stores["delta.myshopify.com"]
        smoke.check(!!delta && delta.salesAccess === "granted" && delta.label === "delta", "IPC grant: access granted, label kept, got " + JSON.stringify(delta ? [delta.salesAccess, delta.label] : null))
        cfgFile.reload()
        smoke.check(cfgFile.text().indexOf("Delta Shop") < 0, "IPC grant left config.json without the verified name")
        smoke.check(service.grantSalesAccess("delta.myshopify.com").ok === true, "panel grant starts")
      },
      smoke.waitFor(function() {
        const delta = root.service.snapshot.stores["delta.myshopify.com"]
        const st1 = root.service.snapshot.stores[root.domains[1]]
        return !!delta && delta.label === "Delta Shop" && !!st1 && !!st1.themeState.lastResult
      }, "the panel grant's relabel and the failed pull"),
      function() {
        const delta = root.service.snapshot.stores["delta.myshopify.com"]
        smoke.check(!!delta && delta.label === "Delta Shop", "panel grant relabels with the verified name, got " + (delta ? delta.label : "none"))
        const d1 = root.domains[1]
        const st1 = root.service.snapshot.stores[d1]
        const lr = st1 && st1.themeState ? st1.themeState.lastResult : null
        smoke.check(!!lr && !!lr.error && lr.error.code === "theme_session_expired", "signed out: the failed pull is theme_session_expired, got " + JSON.stringify(lr))
        // (js/banner.mjs puts sessionExpired over signedOut for that result:
        // tests/js/test_banner.mjs; the panel smoke checks the banner shown.)
        root.service.dismissThemeResult(d1)
        // A discovery started while a sign-out runs reports the session the
        // sign-out replaced, after it has settled: Account.noteSession drops
        // a report older than the last sign-in/out (the fake keeps listing
        // stores as signed in, so without that rule this would sign back in).
        scenarioFile.setText("slow-store-list")
        const out = root.service.signOut()
        // (Account is signing_out from here on; the snapshot follows within 250 ms.)
        smoke.check(out.ok === true && out.started === true, "second signOut starts, got " + JSON.stringify(out))
        const late = root.service.discoverStores()
        smoke.check(late.ok === true && late.started === true, "a discovery starts during the sign-out, got " + JSON.stringify(late))
      },
      smoke.waitFor(() => root.service.snapshot.discovery.status === "done", "the late discovery", 15000),
      // A report that would undo the sign-out lands with the discovery.
      smoke.pause(500),
      function() {
        const service = root.service
        smoke.check(service.snapshot.discovery.status === "done", "the late discovery finished, got " + service.snapshot.discovery.status)
        smoke.check(service.snapshot.account.status === "signed_out", "a discovery started before the sign-out settled can't undo it, got " + service.snapshot.account.status)
        scenarioFile.setText("ok")
        // status() reads the published snapshot: the next publish still
        // reuses every store object nothing changed (here gamma, while only
        // acme refreshes).
        root.gammaBefore = service.snapshot.stores[root.domains[2]]
        const s = service.status()
        smoke.check(s.ok && s.stores.length === 4 && s.stores[0].domain === root.domains[0] && s.stores[3].domain === "delta.myshopify.com", "status() lists the stores in config order, got " + JSON.stringify(s.stores.map(x => x.domain)))
        smoke.check(service.refreshStore(root.domains[0]).ok === true, "acme refreshes")
      },
      // The next publish after status().
      smoke.pause(600),
      function() {
        smoke.check(!!root.gammaBefore && root.service.snapshot.stores[root.domains[2]] === root.gammaBefore, "a publish after status() reuses an unchanged store's object")
        // Deleted for good: the re-check finds it still missing.
        root.move(cfgFile.path, cfgFile.path + "~")
      },
      smoke.waitFor(() => root.service.storeOrder.length === 0, "the re-check of the deleted config.json"),
      function() {
        smoke.check(root.service.storeOrder.length === 0, "a deleted config.json is an empty config after the re-check, got " + root.service.storeOrder.length)
        // Put the file back for whatever runs next in this HOME.
        root.move(cfgFile.path + "~", cfgFile.path)
      },
      smoke.waitFor(() => !mover.running, "config.json put back")
    ]
  }
}
