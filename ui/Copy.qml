pragma Singleton
import QtQuick
import "../js/copy.mjs" as CopyJs

// QML's handle on js/copy.mjs, the only home of UI text: `t` and the
// derived texts the QML reads, forwarded unchanged (see that module for the
// key grammar and what each helper says).
QtObject {
  function t(key, vars) { return CopyJs.t(key, vars) }
  function updatedText(atMs, nowMs) { return CopyJs.updatedText(atMs, nowMs) }
  function limitedText(retryAtMs) { return CopyJs.limitedText(retryAtMs) }
  function themeName(theme) { return CopyJs.themeName(theme) }
  function ordersText(n) { return CopyJs.ordersText(n) }
  function sessionsText(n) { return CopyJs.sessionsText(n) }
  function storesText(n) { return CopyJs.storesText(n) }
  function filesText(n) { return CopyJs.filesText(n) }
  function errorOf(err) { return CopyJs.errorOf(err) }
  function periodCaption(id) { return CopyJs.periodCaption(id) }
  function baselineText(periodId, amountText) { return CopyJs.baselineText(periodId, amountText) }
  function folderWarning(ts, folder) { return CopyJs.folderWarning(ts, folder) }
  function themeTargetOptions(ts, target) { return CopyJs.themeTargetOptions(ts, target) }
}
