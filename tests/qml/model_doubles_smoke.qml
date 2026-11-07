// runner: quickshell
import QtQuick
import Quickshell
import "shop/tests/qml"

// model/HelperProcess, HelperStream and ThemeInfo against helper doubles
// that tests/qml/fake-home.sh puts in a stand-in plugin tree (stub/: links
// to model/ and js/, plus its own helpers/; the model resolves
// ../helpers/<name> next to itself). Loaded with Qt.createComponent: the
// linter cannot see the stand-in tree.
// - A helper killed by SIGKILL before it printed a result (the OOM killer,
//   a pkill -9, a crash) ends as `terminated` in both modes, never as
//   bad_response ("Unexpected response from Shopify"); a helper that exits
//   9 normally is still the exit code 9, not a kill.
// - A list-themes double rate limited once (retryAfter 1 s): ThemeInfo
//   fetches the list again by itself, once, without another listThemes.
// - A check-account double that times out once: Account re-runs the
//   account check by itself after retryBaseMs (no check() from outside),
//   and the CLI is not left on "checking" in between.
// Run alone: tests/run tests/qml/model_doubles_smoke.qml
ShellRoot {
  id: root

  property var results: ({})
  property var themeInfo: null
  property var account: null
  readonly property string themesDomain: "t" + Date.now() + ".myshopify.com"

  function note(key, value) {
    var r = Object.assign({}, root.results)
    // A var signal argument: a JSON round trip makes it a plain object.
    r[key] = JSON.parse(JSON.stringify(value))
    root.results = r
  }

  function make(file, props) {
    var c = Qt.createComponent(Qt.resolvedUrl("stub/model/" + file), Component.PreferSynchronous)
    if (c.status !== Component.Ready) {
      smoke.check(false, "cannot load stub/model/" + file + ": " + c.errorString())
      return null
    }
    return c.createObject(root, props)
  }

  function runResult(key, helper) {
    var p = root.make("HelperProcess.qml", { helper: helper, deadline: 10000, maxStdoutBytes: 4096 })
    if (!p) return
    p.finished.connect(function(r) { root.note(key, r) })
    p.run([])
  }

  function runStream(key, helper) {
    var s = root.make("HelperStream.qml", { helper: helper, deadline: 10000 })
    if (!s) return
    s.ended.connect(function(code, killSignal) { root.note(key, { code: code, killSignal: killSignal }) })
    s.start([])
  }

  Smoke {
    id: smoke
    name: "MODEL_DOUBLES"
    interval: 0
    steps: [
      function() {
        root.runResult("killedResult", "killed-by-signal")
        root.runResult("exitResult", "exits-9")
        root.runStream("killedStream", "killed-by-signal")
        root.runStream("exitStream", "exits-9")
        root.themeInfo = root.make("ThemeInfo.qml", {})
        if (root.themeInfo) root.themeInfo.listThemes(root.themesDomain)
        root.account = root.make("Account.qml", { retryBaseMs: 1000 })
        if (root.account) root.account.check()
      },
      // The first runs answered: the theme list rate limited (a retry
      // pending at retryAfter), the account check timed out. Both retry
      // after 1 s, so this is read well before that.
      smoke.waitFor(function() {
        var st = root.themeInfo ? root.themeInfo.stateFor(root.themesDomain) : null
        return !!st && st.themes.status === "error" && !!root.account && !!root.account.cli.error
      }, "the first theme list and account check", 900),
      function() {
        if (!root.themeInfo || !root.account) return
        var st = root.themeInfo.stateFor(root.themesDomain)
        smoke.check(!!st && st.themes.status === "error" && st.themes.error.code === "rate_limited", "themes rate limited first, got " + JSON.stringify(st ? st.themes : null))
        var ms = root.themeInfo.themesRetryMs(root.themesDomain)
        smoke.check(ms === 1000, "the retry waits retryAfter (1000 ms), got " + ms)
        const c = root.account.cli
        smoke.check(c.status === "unknown" && !!c.error && c.error.code === "timeout", "a timed-out status leaves cli unknown with the error (not checking), got " + JSON.stringify(c))
      },
      smoke.waitFor(function() {
        var r = root.results
        var loaded = root.themeInfo ? root.themeInfo.stateFor(root.themesDomain) : null
        return !!r.killedResult && !!r.exitResult && !!r.killedStream && !!r.exitStream
          && !!loaded && loaded.themes.status === "ok" && !!root.account && root.account.cli.status === "ready"
      }, "every helper double's result, the retried theme list and the re-run account check"),
      function() {
        var r = root.results
        var kr = r.killedResult
        smoke.check(!!kr && kr.ok === false && kr.error.code === "terminated", "result mode, SIGKILL -> terminated, got " + JSON.stringify(kr))
        // No writeStarted: a theme job that ends this way has unknown writes
        // (ThemeJob.writeStartedOf), never "nothing written".
        smoke.check(!!kr && !("writeStarted" in kr), "a SIGKILLed helper's result carries no writeStarted, got " + JSON.stringify(kr))
        var er = r.exitResult
        smoke.check(!!er && er.ok === false && er.error.code === "bad_response" && er.exitCode === 9, "result mode, exit 9 -> bad_response, got " + JSON.stringify(er))
        var ks = r.killedStream
        smoke.check(!!ks && ks.code === 9 && ks.killSignal === 9, "stream, SIGKILL -> ended(9, 9), got " + JSON.stringify(ks))
        var es = r.exitStream
        smoke.check(!!es && es.code === 9 && es.killSignal === 0, "stream, exit 9 -> ended(9, 0), got " + JSON.stringify(es))
        const loaded = root.themeInfo.stateFor(root.themesDomain)
        smoke.check(!!loaded && loaded.themes.status === "ok" && loaded.themes.items.length === 1 && loaded.themes.items[0].name === "Dawn", "the rate-limited list loaded by itself, got " + JSON.stringify(loaded ? loaded.themes : null))
        smoke.check(root.themeInfo.themesRetryMs(root.themesDomain) === 0, "no retry pending after the list loaded")
        smoke.check(root.account.cli.status === "ready" && root.account.account.status === "signed_in", "the timed-out account check re-ran by itself, got cli " + JSON.stringify(root.account.cli) + " account " + JSON.stringify(root.account.account))
      }
    ]
  }
}
