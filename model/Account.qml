pragma ComponentBehavior: Bound
import QtQuick
import "../js/errors.mjs" as Errors
import "../js/format.mjs" as Format

// The pinned Shopify CLI and the account session: check-account, sign-in,
// sign-out and install-cli. One managed, cancellable flow of each kind at a
// time. (The state directories are StateDir's.)
Item {
  id: root

  // { status: unknown|checking|ready|missing|installing|install_failed,
  //   missing, installs, error }; installs is the helper's mise
  //   installs dir, home-relative for display.
  readonly property var cli: internal.cli
  // { status: unknown|signed_in|signed_out|signing_in|signing_out, error }
  readonly property var account: internal.account
  // First wait before a failed account check re-runs by itself (doubles up
  // to 5 min). Tests shorten it.
  property int retryBaseMs: 30000
  property string home: ""

  // Sign-in finished with a signed-in session (Service then discovers stores).
  signal signedIn()

  // Run the account check (check-account: the CLI and the session) again.
  // Ignored during sign-in, sign-out or install, whose own results update
  // the same fields.
  function check() {
    if (signInProc.running || signOutProc.running || installProc.running || checkProc.running) return
    retryTimer.stop()
    if (internal.cli.status !== "ready") internal.setCli({ status: "checking" })
    checkProc.run([])
  }

  // The Service checks the CLI first (Preflight.requireCli); these only guard the flows.
  function signIn() {
    if (signInProc.running) return Errors.accountBusy("Already signing in")
    // "Sign in again" calls signOut() then signIn(): sign in once the
    // sign-out has finished.
    if (signOutProc.running) {
      internal.signInQueued = true
      return Errors.started()
    }
    internal.startSignIn()
    return Errors.started()
  }

  function cancelSignIn() {
    internal.signInQueued = false
    if (!signInProc.running) return Errors.ok()
    signInProc.cancel()
    internal.setAccount({ status: "unknown", error: null })
    root.check()
    return Errors.ok()
  }

  function signOut() {
    if (signInProc.running || signOutProc.running) return Errors.accountBusy("Already signing in or out")
    checkProc.cancel()
    internal.setAccount({ status: "signing_out", error: null })
    signOutProc.run([])
    return Errors.started()
  }

  function installCli() {
    if (installProc.running) return Errors.accountBusy("Already installing")
    if (signInProc.running || signOutProc.running) return Errors.accountBusy("Signing in or out")
    if (internal.cli.status === "ready") return Errors.ok()
    checkProc.cancel()
    internal.setCli({ status: "installing", error: null })
    installProc.run(["--consent=install"])
    return Errors.started()
  }

  function cancelInstall() {
    if (!installProc.running) return Errors.ok()
    installProc.cancel()
    internal.setCli({ status: "missing", error: null })
    root.check()
    return Errors.ok()
  }

  // Another helper (discovery, sales) learned the session state. startedAt
  // (ms, optional): when that helper's run began; a run older than the last
  // finished sign-in or sign-out reports the session it replaced.
  function noteSession(session, startedAt) {
    if (internal.account.status === "signing_in" || internal.account.status === "signing_out") return
    if (startedAt > 0 && startedAt < internal.settledAt) return
    internal.setAccount({ status: session, error: null })
    internal.resetRetry()
  }

  QtObject {
    id: internal
    property var cli: ({ status: "unknown", missing: null, installs: null, error: null })
    property var account: ({ status: "unknown", error: null })
    property bool signInQueued: false
    // When the last sign-in or sign-out finished (noteSession).
    property real settledAt: 0

    function startSignIn() {
      internal.signInQueued = false
      checkProc.cancel()
      internal.setAccount({ status: "signing_in", error: null })
      signInProc.run([])
    }

    function setCli(patch) {
      internal.cli = Object.assign({}, internal.cli, patch)
    }

    function setAccount(patch) {
      internal.account = Object.assign({}, internal.account, patch)
    }

    // A found CLI (check-account reports it) and a missing one. A report
    // without installs (a cli_missing failure) keeps the last one.
    function setCliReady(c) {
      internal.setCli(internal.withInstalls({ status: "ready", missing: null, error: null }, c))
    }

    function setCliMissing(c) {
      internal.setCli(internal.withInstalls({ status: "missing", missing: c.missing === "node" ? "node" : "cli", error: null }, c))
    }

    function withInstalls(patch, c) {
      if (typeof c.installs === "string") patch.installs = Format.homeRelative(c.installs.substring(0, 4096), root.home)
      return patch
    }

    // A check-account-shaped result:
    // { cli: { found, missing, installs }, account: { status, error } }.
    function applyStatus(r) {
      const c = r.cli
      if (c.found === true) internal.setCliReady(c)
      else internal.setCliMissing(c)
      const a = r.account
      const status = a.status
      const error = status === "unknown" && a.error ? Errors.fromHelper(a.error) : null
      internal.setAccount({ status: status, error: error })
      if (error) internal.scheduleRetry()
      else if (status !== "unknown") internal.resetRetry()
    }

    // An account check that failed (or answered unknown with an error, e.g.
    // a timed-out `store list`) is re-run by itself: retryBaseMs (30 s),
    // doubling up to 5 min; a good answer resets it. Nothing else runs it
    // again on its own, so without this a slow network at startup would
    // leave Shop on "Checking…" until the user pressed r.
    property int retryMs: root.retryBaseMs

    function scheduleRetry() {
      retryTimer.interval = internal.retryMs
      retryTimer.restart()
      internal.retryMs = Math.min(internal.retryMs * 2, 300000)
    }

    function resetRetry() {
      retryTimer.stop()
      internal.retryMs = root.retryBaseMs
    }

    function failStatus(r) {
      const e = Errors.fromHelper(r.error)
      if (e.code === "cli_missing") {
        internal.setCliMissing(e)
        internal.setAccount({ status: "unknown", error: null })
      } else {
        if (internal.cli.status === "checking") internal.setCli({ status: "unknown", error: e })
        internal.setAccount({ status: "unknown", error: e })
        internal.scheduleRetry()
      }
    }
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.check()
  }

  HelperProcess {
    id: checkProc
    helper: "check-account"
    onFinished: (r) => r.ok ? internal.applyStatus(r) : internal.failStatus(r)
  }

  HelperProcess {
    id: signInProc
    helper: "sign-in"
    onFinished: (r) => {
      internal.settledAt = Date.now()
      if (r.ok) {
        internal.applyStatus(r)
        if (internal.account.status === "signed_in") root.signedIn()
      } else {
        const e = Errors.fromHelper(r.error)
        internal.setAccount({ status: e.code === "signed_out" ? "signed_out" : "unknown", error: e.code === "signed_out" ? null : e })
        if (e.code === "cli_missing") internal.setCli({ status: "missing" })
        root.check()
      }
    }
  }

  HelperProcess {
    id: signOutProc
    helper: "sign-out"
    onFinished: (r) => {
      internal.settledAt = Date.now()
      if (r.ok) internal.setAccount({ status: "signed_out", error: null })
      else internal.setAccount({ status: "unknown", error: Errors.fromHelper(r.error) })
      if (internal.signInQueued && internal.cli.status === "ready") internal.startSignIn()
      else if (!r.ok) root.check()
    }
  }

  HelperProcess {
    id: installProc
    helper: "install-cli"
    onFinished: (r) => {
      if (r.ok) {
        // install-cli marks the CLI ready; check-account supplies installs.
        internal.setCli({ status: "ready", missing: null, error: null })
        checkProc.run([])
      } else {
        internal.setCli({ status: "install_failed", error: Errors.fromHelper(r.error) })
      }
    }
  }
}
