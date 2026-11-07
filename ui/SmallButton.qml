import QtQuick
import qs.Commons
import qs.Ui

// The panel's compact bordered button: Look.small text, a tight vertical
// padding. Rows that sit in a list pass Style.spacing.xxs; every other kit
// Button property (text, iconText, hasCursor, foreground, tooltipText, …)
// stays available.
Button {
  bordered: true
  fontSize: Look.small
  verticalPadding: Style.spacing.xs
}
