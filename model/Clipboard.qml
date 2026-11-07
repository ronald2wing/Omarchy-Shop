pragma ComponentBehavior: Bound
import QtQuick

// Clipboard reads for a paste, through helpers/read-clipboard. The shell
// never reads the clipboard itself (Quickshell.clipboardText, a TextInput's
// paste): Qt's Wayland read has no size or time bound, so a clipboard owner
// that keeps sending would block or exhaust the whole shell. The helper's
// wl-paste child is capped and supervised instead.
//
// One read at a time: a new read() cancels the one in flight, whose
// callback never fires.
Item {
  id: root

  // done(result): {ok: true, text} (text "" for an empty clipboard) or
  // {ok: false, error: {code, message}}.
  function read(done) {
    internal.done = done
    proc.run([])
  }

  QtObject {
    id: internal
    property var done: null
  }

  HelperProcess {
    id: proc
    helper: "read-clipboard"
    onFinished: (r) => {
      const done = internal.done
      internal.done = null
      if (typeof done === "function") done(r.ok === true ? { ok: true, text: typeof r.text === "string" ? r.text : "" } : r)
    }
  }
}
