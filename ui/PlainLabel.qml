import QtQuick

// The one Text in the Shop UI. Every data string (store labels, theme
// names, helper messages, paths) renders through this preset, so nothing
// that came from Shopify, a file or a process is ever parsed as markup.
//
// Contract: a Text with textFormat PlainText, Look.fontFamily, Look.fg and
// Look.body preset; every Text property (wrapMode, elide, color,
// font.pixelSize, font.bold, horizontalAlignment, ...) stays available.
// `textFormat` is final: do not override it.
// This is the only file under ui/ (and BarWidget.qml) allowed to contain
// a bare `Text {` (tests/ruby/test_source_contracts.rb).
Text {
  textFormat: Text.PlainText
  color: Look.fg
  font.family: Look.fontFamily
  font.pixelSize: Look.body
}
