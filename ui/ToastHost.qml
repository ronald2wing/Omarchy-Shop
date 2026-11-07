import QtQuick

// The panel's one transient line: an immediate {ok:false} from a service
// call, or a short confirmation ("Install command copied"). Shows for 4 s;
// a new message restarts the clock. Long-lived outcomes (a finished theme
// job) belong in a StatusLine, not here.
//
// Contract: show(text); `text` is "" while nothing shows (bind `visible`
// or height on it).
PlainLabel {
  id: root

  function show(message) {
    root.text = String(message || "")
    hideTimer.restart()
  }

  visible: root.text !== ""
  horizontalAlignment: Text.AlignHCenter
  font.pixelSize: Look.small
  wrapMode: Text.WordWrap
  maximumLineCount: 2
  elide: Text.ElideRight

  Accessible.role: Accessible.Notification
  Accessible.name: root.text

  Timer {
    id: hideTimer
    interval: 4000
    onTriggered: root.text = ""
  }
}
