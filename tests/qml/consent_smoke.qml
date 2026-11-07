import QtQuick
import "../../model"

// model/Consent.qml in the real QML engine: one pending request at a time,
// no request while a dialog is open, and a 30 s hold on every request
// after the user declined one. Runs under the plain qml runtime (no Quickshell).
// Run alone: tests/run tests/qml/consent_smoke.qml
Item {
  id: root

  property real fakeNow: 1762520400000

  Consent {
    id: consent
  }

  Smoke {
    id: smoke
    name: "CONSENT"
    interval: 0
    steps: [
      function() {
        consent.clock = function () { return root.fakeNow }
        const d = "acme.myshopify.com"
        smoke.check(consent.pending === null && !consent.dialogOpen && !consent.panelOpen, "starts empty")

        // One request at a time.
        const r1 = consent.request({ action: "push", domain: d, live: true })
        smoke.check(r1.ok && r1.pending === "confirm" && typeof r1.id === "string", "first request opens")
        smoke.check(consent.pending.action === "push" && consent.pending.live === true, "pending shape")
        const r2 = consent.request({ action: "pull", domain: d })
        smoke.check(!r2.ok && r2.error.code === "confirm_open", "second request refused")
        smoke.check(consent.resolve("nope", true).error.code === "no_pending", "wrong id")
        const res = consent.resolve(r1.id, true)
        smoke.check(res.ok && res.accepted && res.spec.action === "push" && consent.pending === null, "accepted")

        // A decline holds every request for 30 s, whatever it asks (a script
        // rotating the action, store or backup id gains nothing).
        const r3 = consent.request({ action: "pull", domain: d })
        smoke.check(r3.ok, "request")
        smoke.check(consent.resolve(r3.id, false).accepted === false, "declined")
        const r4 = consent.request({ action: "pull", domain: d })
        smoke.check(!r4.ok && r4.error.code === "recently_declined", "repeat held")
        smoke.check(consent.request({ action: "push", domain: d }).error.code === "recently_declined", "another action is held too")
        smoke.check(consent.request({ action: "pull", domain: "other.myshopify.com" }).error.code === "recently_declined", "another store is held too")
        smoke.check(consent.request({ action: "restore", domain: d, backupId: "1762500001-1" }).error.code === "recently_declined", "another backup id is held too")
        smoke.check(consent.request({ action: "addStore", domain: "new.myshopify.com", label: "New" }).error.code === "recently_declined", "an add is held too")
        smoke.check(consent.pending === null, "nothing pending while held")
        smoke.check(consent.request({ action: "pull", domain: d }).error.code === "recently_declined", "still held")
        root.fakeNow += 29999
        smoke.check(consent.request({ action: "pull", domain: d }).error.code === "recently_declined", "held for the whole 30 s")
        root.fakeNow += 2
        const r6 = consent.request({ action: "push", domain: d })
        smoke.check(r6.ok, "hold expired")
        // Accepting a request holds nothing.
        consent.resolve(r6.id, true)
        smoke.check(consent.request({ action: "pull", domain: d }).ok, "an accepted request does not hold")
        consent.resolve(consent.pending.id, true)

        // An open dialog blocks requests; the panel closing closes its dialog.
        consent.setDialogOpen("panel-1", true)
        smoke.check(consent.dialogOpen, "dialog open")
        smoke.check(consent.request({ action: "pull", domain: d }).error.code === "confirm_open", "dialog blocks")
        smoke.check(consent.setPanelOpen("panel-1", true) === true, "panel just opened")
        smoke.check(consent.setPanelOpen("panel-1", true) === false, "already open")
        smoke.check(consent.setPanelOpen("panel-1", false) === false && !consent.panelOpen && !consent.dialogOpen, "panel closed closes its dialog")
        smoke.check(consent.request({ action: "pull", domain: d }).ok, "unblocked")

        // Removing the store voids its request.
        consent.clear("other.myshopify.com")
        smoke.check(consent.pending !== null, "other store untouched")
        consent.clear(d)
        smoke.check(consent.pending === null, "cleared")
      }
    ]
  }
}
