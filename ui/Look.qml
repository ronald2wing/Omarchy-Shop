pragma Singleton
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Design tokens for the Shop panel and pills. Everything derives from the
// shell theme (Color, Style), so light and dark themes both read correctly.
QtObject {
  id: look

  readonly property color fg: Commons.Color.foreground
  readonly property color muted: Commons.Color.muted
  readonly property color accent: Commons.Color.accent
  // Up trends use the accent; a theme whose accent equals its foreground
  // gets the foreground instead, and the glyph still carries the meaning.
  readonly property color positive: Qt.colorEqual(Commons.Color.accent, Commons.Color.foreground) ? Commons.Color.foreground : Commons.Color.accent
  // Reserved for a failed operation and down trends.
  readonly property color negative: Commons.Color.urgent
  // Color has no warn token: tint the foreground toward urgent.
  readonly property color warn: Qt.tint(Commons.Color.foreground, Util.alpha(Commons.Color.urgent, 0.6))
  readonly property color surface: Commons.Color.popups.background
  readonly property color hairline: Util.alpha(Commons.Color.foreground, 0.12)
  readonly property color softFill: Util.alpha(Commons.Color.foreground, 0.04)
  readonly property color scrim: Util.alpha(Commons.Color.background, 0.7)
  readonly property color barFill: Util.alpha(Commons.Color.foreground, 0.55)

  readonly property string fontFamily: Style.font.family

  // Spacing aliases, so the views read as one rhythm: blocks are separated
  // by `block`, rows inside a block by `gapLg`.
  readonly property int gapXs: Style.spacing.xs
  readonly property int gapSm: Style.spacing.sm
  readonly property int gapMd: Style.spacing.md
  readonly property int gapLg: Style.spacing.lg
  readonly property int block: Style.spacing.huge
  readonly property int rowPadX: Style.spacing.rowPaddingX
  // Between the rows of a list (Home's stores, Add's results, Backups).
  readonly property int listGap: Style.space(2)
  // A sub-item under a line (Home's invalid config entries).
  readonly property int indent: Style.space(20)
  // The label column wherever one exists (Edit, Settings, Theme card, Dialog facts).
  readonly property int labelWidth: Style.space(112)

  // Type scale.
  readonly property int caption: Style.font.caption
  // Also section headers and KPI/field labels.
  readonly property int small: Style.font.bodySmall
  readonly property int body: Style.font.body
  readonly property int subtitle: Style.font.subtitle
  readonly property int title: Style.font.title
  readonly property int heading: Style.font.heading
  readonly property int display: Style.font.display
  readonly property int displayLarge: Style.font.displayLarge

  // A control that is shown but refused right now (the theme actions).
  readonly property real disabledOpacity: 0.45

  // Tone -> colour for banners, status lines, chips and dots.
  // Tones: ok | info | warn | error.
  function toneColor(tone) {
    if (tone === "error") return look.negative
    if (tone === "warn") return look.warn
    if (tone === "ok") return look.positive
    return look.muted
  }

  // The default glyph for a tone, when a status line or banner names none.
  function toneGlyph(tone) {
    if (tone === "error") return "✕"
    if (tone === "warn") return "󰀦"
    if (tone === "ok") return "✓"
    return "󰋽"
  }
}
