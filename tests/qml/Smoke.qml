import QtQuick

// The runner every tests/qml smoke shares. `steps` run in order: a function
// runs on its own tick, `interval` ms after a function step and at once
// after a wait; `waitFor` polls a condition every 50 ms (a failed check
// when it times out); `pause` waits a fixed time, for a check that
// something did NOT happen meanwhile. Failures name steps from 1.
// A step that throws ends the smoke. After the last step, or on finish(),
// it prints <name>_OK, or <name>_FAIL and every failed check, and quits;
// tests/run passes a smoke on that line and no engine error.
QtObject {
  id: smoke

  required property string name
  property var steps: []
  property int interval: 400
  property var failures: []
  property bool finished: false
  property int index: 0
  property real waitStartedMs: 0

  function check(ok, what) {
    if (!ok) smoke.failures.push(String(what))
  }

  // A step that waits until cond() is true, failing `what` after timeoutMs.
  function waitFor(cond, what, timeoutMs) {
    return { waitFor: cond, what: String(what), timeoutMs: timeoutMs || 10000 }
  }

  // A step that waits ms milliseconds.
  function pause(ms) {
    return { pauseMs: ms }
  }

  function finish() {
    if (smoke.finished) return
    smoke.finished = true
    smoke.ticker.stop()
    if (smoke.failures.length === 0) console.log(smoke.name + "_OK")
    else console.log(smoke.name + "_FAIL " + smoke.failures.join(" | "))
    Qt.quit()
  }

  function schedule(ms) {
    smoke.ticker.interval = ms
    smoke.ticker.restart()
  }

  function advance() {
    if (smoke.finished) return
    if (smoke.index >= smoke.steps.length) { smoke.finish(); return }
    const step = smoke.steps[smoke.index]
    if (step && typeof step.waitFor === "function") {
      if (smoke.waitStartedMs === 0) smoke.waitStartedMs = Date.now()
      let ok = false
      try { ok = !!step.waitFor() } catch (e) { ok = false }
      if (!ok && Date.now() - smoke.waitStartedMs < step.timeoutMs) { smoke.schedule(50); return }
      smoke.check(ok, "step " + (smoke.index + 1) + ": timed out waiting for " + step.what)
      smoke.waitStartedMs = 0
      smoke.index++
      smoke.schedule(0)
      return
    }
    smoke.index++
    if (step && typeof step.pauseMs === "number") { smoke.schedule(step.pauseMs); return }
    try {
      step()
    } catch (e) {
      smoke.check(false, "step " + smoke.index + ": " + e)
      smoke.finish()
      return
    }
    smoke.schedule(smoke.interval)
  }

  property Timer ticker: Timer {
    onTriggered: smoke.advance()
  }

  Component.onCompleted: smoke.schedule(smoke.interval)
}
