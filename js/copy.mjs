// Every user-facing string in Shop, and the texts derived from them. The
// only home of UI text: ui/Copy.qml forwards to this module for QML, and
// the pure modules that build text (banner, confirm, bar, keymap,
// themejob) and model/OrderAlerts import it directly.
//
// Keys are `<area>.<thing>[.<variant>]`: the area is the view or part that
// shows the string (or `error`, `count`, `action`, `keys`, `hints`…), the
// thing is what it is (a dialog's or banner's thing is `<id>.<part>`:
// `confirm.push.title`), and a variant chosen at run time is always one
// more dotted segment (`count.orders.one`, `confirm.push.title.live`,
// `result.stopped.none.pull`), never a camel suffix: no segment extends a
// sibling key or prefix (`theme.preview.starting` beside `theme.preview`).
// Segments are lowerCamel, except error codes and folder reasons, which
// keep their snake_case (`error.store_busy.anyStore`,
// `theme.unsafe.not_owned`).
//
// `{name}` placeholders are filled literally (fillTemplate), so values are
// never interpreted as markup (every PlainLabel that shows them is
// PlainText). Versions come from snapshot.pins, never from a literal here.
import { clockLocal, count, timeAgo } from "./format.mjs"
import { fillTemplate } from "./text.mjs"
import { folderState } from "./themes.mjs"

export const STRINGS = {

  // ----- bar -----
  "bar.installing": "Installing…",
  "bar.signingIn": "Signing in…",
  "bar.installCli": "Install CLI",
  "bar.tooltip": "{label} — {sales} today · {orders}{trend} · {updated}",
  "bar.tooltip.tail": "right-click to refresh",
  "bar.tooltip.error": "{label} — {error}",
  "bar.unavailable": "Shop's service isn't available on this bar. Use the default Omarchy bar or restart the shell.",
  "bar.hiddenFromBar": "Hidden from bar ({n} already shown)",
  "bar.configError": "Config error",
  "bar.stateError": "Can't start",
  "bar.cliError": "CLI error",

  // ----- states shared by the bar and the views -----
  "status.checking": "Checking…",
  "status.signedIn": "Signed in",
  "status.signedOut": "Signed out",
  "status.configError": "Nothing to show until config.json is fixed.",

  // ----- sales access (store auth) -----
  "access.step": "Grant sales access (opens your browser)",
  "access.grant": "Grant access…",
  "access.regrant": "Grant again…",
  "access.granting": "Finish in your browser…",
  "access.granted": "Granted",
  "access.notGranted": "Not granted",
  "access.unknown": "Not checked yet",
  "access.help": "Opens your browser so Shop can read this store's sales (read_reports, read_orders).",

  // ----- counted nouns -----
  "count.orders": "{n} orders",
  "count.orders.one": "1 order",
  "count.stores": "{n} stores",
  "count.stores.one": "1 store",
  "count.sessions": "{n} sessions",
  "count.sessions.one": "1 session",
  "count.files": "{n} files",
  "count.files.one": "1 file",

  // ----- periods and trends -----
  "period.today": "Today",
  "period.yesterday": "Yesterday",
  "period.last7d": "7d",
  "period.last14d": "14d",
  "period.last30d": "30d",
  "period.last12m": "12m",
  "caption.today": "Today so far",
  "caption.yesterday": "Yesterday",
  "caption.last7d": "Last 7 complete days",
  "caption.last14d": "Last 14 complete days",
  "caption.last30d": "Last 30 complete days",
  "caption.last12m": "Last 12 months",
  "source.today": "Order totals as they come in",
  "source.history": "Shopify net sales, after returns",
  "trend.baseline.today": "{amount} at this time yesterday",
  "trend.baseline.yesterday": "{amount} the day before",
  "trend.baseline.last7d": "{amount} previous 7 days",
  "trend.baseline.last14d": "{amount} previous 14 days",
  "trend.baseline.last30d": "{amount} previous 30 days",

  // ----- home -----
  "home.title": "Shop",
  "home.updated": "updated {ago}",
  "home.never": "not updated yet",
  "home.summary": "{orders} · {stores} · {updated}",
  "home.summary.noFigures": "{stores} · {updated}",
  "home.invalidEntries.one": "1 entry in config.json can't be read: {what}",
  "home.invalidEntries": "{n} entries in config.json can't be read",
  "home.openFile": "Open file",
  "setup.title": "Set up Shop",
  "setup.cli": "Shopify CLI {cli} installed",
  "setup.cli.missing": "Install the Shopify CLI",
  "setup.signIn": "Sign in to Shopify",
  "setup.signedIn": "Signed in to Shopify",
  "setup.access": "Grant sales access for each store (opens your browser)",
  "setup.folderHint": "Optional: link a theme folder to push, pull and preview.",
  "setup.findStores": "Find my stores",

  // ----- store -----
  "kpi.orders": "Orders",
  "kpi.sessions": "Sessions",
  "kpi.aov": "Average order",
  "kpi.salesPerSession": "Sales / session",
  "kpi.conversion": "Conversion",
  "kpi.addToCart": "Added to cart",
  "kpi.reachedCheckout": "Reached checkout",
  "kpi.checkoutCompletion": "Checkout completion",
  "kpi.lifetime": "Lifetime",
  "kpi.tip.aov": "Sales divided by orders",
  "kpi.tip.salesPerSession": "Sales divided by sessions",
  "kpi.tip.conversion": "Sessions that ended in an order",
  "kpi.tip.addToCart": "Sessions that added something to the cart",
  "kpi.tip.reachedCheckout": "Sessions that reached checkout",
  "kpi.tip.checkoutCompletion": "Checkouts that became orders",
  "kpi.trafficAge": "Traffic updated {ago}",
  "store.truncated": "Some of today's orders didn't load, so the total is partial",
  "spark.tip": "{day} · {sales} · {sessions} · {perSession} / session{partial}",
  "spark.partial": " (partial)",
  "store.subtitle": "{domain} · {updated}",
  "store.signInToSee": "Sign in to see sales",
  "store.installToSee": "Install the Shopify CLI to see sales",
  "store.limited": "Shopify is limiting requests · retrying at {time}",

  // ----- theme card -----
  "theme.section": "Theme",
  "theme.backupsLink": "Backups ({n}) ›",
  "theme.tip.backups": "Theme backups taken before each push or restore, and folder copies taken before each pull",
  "theme.liveChip": "LIVE",
  "theme.liveTheme": "Live theme",
  "theme.themeId": "Theme {id}",
  "theme.push": "Push…",
  "theme.pullInto": "Pull into folder…",
  "theme.preview": "Preview",
  "theme.stopPreview": "Stop",
  "theme.preview.running": "Preview running · {url}",
  "theme.preview.starting": "Starting preview…",
  "theme.preview.failed": "Preview stopped: {error}",
  "theme.preview.ended": "Preview ended unexpectedly",
  "theme.tip.push": "Upload {folder} to {theme} on Shopify",
  "theme.tip.pull": "Download {theme} from Shopify into {folder}",
  "theme.tip.preview": "Run your folder on the store's development theme",
  "theme.tip.locked": "Live theme changes are off for this store · press p to turn them on",
  "theme.noFolder": "Link a theme folder to push, pull and preview.",
  "theme.chooseFolder": "Choose folder…",
  "theme.folderMissing": "Folder not found",
  "theme.unsafe.theme_toml": "Remove shopify.theme.toml from this folder or the folders above it; Shop passes its own settings.",
  "theme.unsafe.symlink": "A theme file here is a symlink; Shop doesn't push or pull through links",
  "theme.unsafe.hardlink": "A theme file here is hard-linked elsewhere",
  "theme.unsafe.special_file": "A theme file here is a pipe, socket or device",
  "theme.unsafe.unreadable": "Shop can't read part of this folder",
  "theme.unsafe.too_many_files": "Too many files for a theme folder",
  "theme.unsafe.root": "Pick a theme folder, not the whole disk",
  "theme.unsafe.home": "Pick a theme folder, not your home folder",
  "theme.unsafe.plugin": "Shop's own folder can't be a theme folder",
  "theme.unsafe.state": "Shop's state folder can't be a theme folder",
  "theme.unsafe.config": "Your config folder can't be a theme folder",
  "theme.unsafe.not_owned": "This folder belongs to another user",
  "theme.unsafe.world_writable": "Anyone can write to this folder",
  "theme.unsafe.group_writable": "Others in your group can write to this folder",
  "theme.unsafe.unsafe_parent": "Other users can write to a folder above this one (like /tmp); move the theme somewhere only you can write",
  "theme.unsafe.not_absolute": "Use a full path for the theme folder",
  "theme.unsafe.not_directory": "That path isn't a folder",
  "theme.unsafe.default": "Shop can't use this folder ({reason})",
  "theme.showDetails": "Details",
  "theme.hideDetails": "Hide details",
  "theme.running": "{action}… {elapsed}",
  "job.push": "Pushing",
  "job.pull": "Pulling",
  "job.restore": "Restoring",
  "job.noun.push": "push",
  "job.noun.pull": "pull",
  "job.noun.restore": "restore",
  "job.noun.preview": "preview",
  "job.noun.grant": "sales access grant",
  "job.title.push": "Push",
  "job.title.pull": "Pull",
  "job.title.restore": "Restore",
  "result.pushed": "Pushed to {theme}",
  "result.pulled": "Pulled {theme} into {folder}",
  "result.restored": "Restored backup to {theme}",
  "result.theme.live": "{theme} (live)",
  "result.partial": "{action} with {n} file problems",
  "result.partial.one": "{action} with a file problem",
  "result.links": "Pulled, but {n} files in the folder are links Shop won't push. See Details.",
  "result.links.one": "Pulled, but 1 file in the folder is a link Shop won't push. See Details.",
  "result.stopped.none.push": "Stopped before anything was pushed to {theme}",
  "result.stopped.none.restore": "Stopped before anything was restored to {theme}",
  "result.stopped.none.pull": "Stopped before anything in {folder} changed",
  "result.stopped.maybe": "Stopped. {mayHaveChanged}.",
  "result.failed.none": "{action} failed: {message}",
  "result.failed.maybe": "{action} failed: {message}. {mayHaveChanged}.",
  "result.mayHaveChanged.theme": "Files on {theme} may have changed: check the theme",
  "result.mayHaveChanged.folder": "Files in {folder} may have changed: check the folder",
  "result.mayHaveChanged.emptyFolder": "{folder} may now hold part of the theme",
  "result.backupKept": "Backup kept · {when}",
  "result.folderCopyKept": "Folder copy kept · {when}",

  // ----- backups -----
  "backups.title": "Backups · {label}",
  "backups.intro": "Copies of the theme taken before each push or restore (Shop keeps the 10 newest), and of the folder taken before each pull.",
  "backups.row": "{theme} · before {before} · {files} · {bytes}",
  "backups.restore": "Restore…",
  "backups.empty": "No backups yet. Shop takes one before every push and restore.",
  "backups.folderCopies": "Folder copies taken before a pull · Shop keeps 5",
  "backups.folderCopyRow": "{files} · {bytes}",
  "backups.openFolder": "Open folder",
  "backups.loading": "Loading backups…",

  // ----- edit -----
  "edit.title": "Edit {label}",
  "edit.store": "Store",
  "edit.access": "Sales access",
  "edit.danger": "Danger",
  "edit.name": "Name",
  "edit.domain": "Store domain",
  "edit.domain.help": "To change it, remove the store and add it again.",
  "edit.folder": "Theme folder",
  "edit.browse": "Browse…",
  "edit.folder.placeholder": "~/themes/my-store",
  "edit.target": "Target theme",
  "edit.target.filter": "Filter themes…",
  "edit.target.none": "No themes match",
  "edit.loadingThemes": "Loading themes…",
  "edit.themesFailed": "Couldn't load themes",
  "edit.themesWaiting": "Shopify is limiting requests; themes load shortly.",
  "edit.allowLive": "Live theme changes",
  "edit.allowLive.help": "Allows pushes and restores to the live theme. Turns off when you change the folder or target.",
  "edit.showInBar": "Show in bar",
  "edit.saved": "Saved ✓",
  "edit.remove": "Remove store…",

  // ----- add a store -----
  "add.title": "Add a store",
  "add.yourStores": "Your stores",
  "add.lastSession": "Your stores · from your last session",
  "add.finding": "Finding your stores…",
  "add.filter": "Filter stores…",
  "add.manual": "Enter a domain",
  "add.domainPlaceholder": "your-store",
  "add.add": "Add",
  "add.none": "No stores found on this account. Enter a domain below.",
  "add.noMatches": "No stores match the filter.",
  "add.truncated": "Showing the first {n} stores",
  "add.signedOut": "Sign in to list your stores, or enter a domain below.",
  "add.cliMissing": "Install the Shopify CLI to list your stores, or enter a domain below.",

  // ----- settings -----
  "settings.alerts": "Alerts",
  "settings.bar": "Bar",
  "settings.shopify": "Shopify",
  "settings.about": "About",
  "settings.notify": "New order alerts",
  "settings.notify.help": "Desktop notification for each new order",
  "settings.sound": "Order sound",
  "settings.sound.help": "Plays with each alert",
  "settings.sendTestAlert": "Send test",
  "settings.notify.missing": "notify-send isn't installed",
  "settings.needsConfig": "Alerts, the bar and the refresh interval show again once config.json is fixed",
  "settings.sound.missing": "No sound player found (pw-play or paplay)",
  "settings.bar.shows": "Bar shows",
  "settings.bar.stores": "Each store",
  "settings.bar.total": "Total",
  "settings.bar.icon": "Icon",
  "settings.poll": "Refresh every",
  "settings.poll.unit": "seconds",
  "settings.poll.less": "Refresh 10 seconds sooner",
  "settings.poll.more": "Refresh 10 seconds later",
  "settings.cli": "Shopify CLI",
  "settings.cli.ready": "{cli} (Node {node})",
  "settings.cli.missing": "Not installed",
  "settings.copyCommand": "Copy",
  "settings.copyCommand.tip": "Copy the install command to run in a terminal",
  "settings.copied": "Install command copied",
  "settings.account": "Account",
  "settings.account.needsCli": "Needs the Shopify CLI",
  "settings.signOut": "Sign out…",
  "settings.account.error": "Sign-in check failed: {error}",
  "settings.version.label": "Version",
  "settings.version": "Shop {version}",
  "settings.configPath": "Config",
  "settings.statePath": "State",
  "settings.keys": "Keyboard shortcuts",
  "settings.resetConfig": "Reset config…",
  "settings.resetConfig.help": "config.json can't be used. Reset it to start over.",

  // ----- banner -----
  "banner.cliMissing.body": "{missing} isn't in {miseInstalls}. Shop uses only its own pinned copy.",
  "banner.missing.node": "Node {node}",
  "banner.missing.cli": "Shopify CLI {cli}",
  "banner.installing.title": "Installing the Shopify CLI…",
  "banner.installing.body": "This can take a few minutes.",
  "banner.cliCheckFailed.title": "Couldn't check the Shopify CLI",
  "banner.installFailed.title": "Couldn't install the Shopify CLI",
  "banner.signingIn.title": "Finish signing in with your browser…",
  "banner.signedOut.title": "You're signed out of Shopify",
  "banner.signedOut.body": "Push, pull and preview may keep working until Shopify asks you to sign in again.",
  "banner.sessionExpired.title": "Your Shopify session expired",
  "banner.sessionExpired.action": "Sign in again",
  "banner.configError.title": "config.json couldn't be read",
  "banner.configError.body": "{message}. Shop won't change the file until you fix or reset it.",
  "banner.configWriteError.title": "Couldn't save your changes",
  "banner.stale.title": "Sales haven't updated for {minutes} min",
  "banner.rateLimited.body": "Retrying at {time}.",

  // ----- dialogs -----
  "confirm.push.title": "Push to {theme}?",
  "confirm.push.body": "Shop backs up {theme} first. Files missing from the folder stay on Shopify.",
  "confirm.push.ok": "Push",
  "confirm.push.title.live": "Push to the live theme?",
  "confirm.push.body.live": "Shoppers see every change right away. Shop backs up {theme} first. Files missing from the folder stay on Shopify.",
  "confirm.push.ok.live": "Push to live",
  "confirm.rootFiles": "(also {files})",
  "confirm.rootFiles.maybe": "(also AGENTS.md and DESIGN.md, if present)",
  "confirm.pull.title": "Pull {theme} into the folder?",
  "confirm.pull.body": "Files that differ are replaced, including AGENTS.md and DESIGN.md at the top of the folder. Files only in your folder are kept. Shop copies the folder first.",
  "confirm.pull.ok": "Pull",
  "confirm.restore.title": "Restore this backup?",
  "confirm.restore.body": "Shop backs up {theme} first. Files added since this backup stay on Shopify.",
  "confirm.restore.ok": "Restore",
  "confirm.remove.title": "Remove {label} from Shop?",
  "confirm.remove.body": "It disappears from the bar and panel. Your theme folder, backups and Shopify access aren't touched.",
  "confirm.remove.ok": "Remove",
  "confirm.addStore.title": "Add {domain} to Shop?",
  "confirm.addStore.body": "Shop will start reading today's sales once you grant access.",
  "confirm.install.title": "Install the Shopify CLI?",
  "confirm.install.body": "Node {node} and Shopify CLI {cli} install under {miseInstalls}; your mise config isn't changed. The CLI's npm install scripts run during setup.",
  "confirm.install.ok": "Install",
  "confirm.signOut.title": "Sign out of Shopify?",
  "confirm.signOut.body": "Sales keep working for stores with access. Push, pull, preview and finding stores need you to sign in again.",
  "confirm.signOut.ok": "Sign out",
  "confirm.resetConfig.title": "Reset Shop's config?",
  "confirm.resetConfig.body": "Shop renames config.json to config.json.old and starts with no stores. Theme folders, backups and Shopify access aren't touched.",
  "confirm.resetConfig.ok": "Reset",
  "confirm.allowLive.title": "Allow changes to the live theme?",
  "confirm.allowLive.body": "Shop still asks before each push or restore and backs the theme up first.",
  "confirm.allowLive.ok": "Allow and continue",
  "confirm.ipcHint": "Requested from outside the panel · Ctrl+Enter confirms, Esc declines",
  "fact.from": "From",
  "fact.to": "To",
  "fact.into": "Into",
  "fact.store": "Store",
  "fact.theme": "Theme",
  "fact.backup": "Backup",
  "fact.taken": "Taken",
  "fact.node": "Node",
  "fact.cli": "CLI",
  "fact.on": "{theme} on {label}",
  "fact.backup.value": "{theme} · before {before}",
  "confirm.and": " and ",
  "confirm.install.command": "mise install node@{node} && mise exec node@{node} -- mise install npm:@shopify/cli@{cli}",

  // ----- actions -----
  "action.cancel": "Cancel",
  "action.retry": "Retry",
  "action.tryAgain": "Try again",
  "action.refresh": "Refresh",
  "action.dismiss": "Dismiss",
  "action.signIn": "Sign in",
  "action.open": "Open",
  "action.install": "Install…",
  "action.add": "Add store",
  "action.settings": "Settings",
  "action.edit": "Edit",
  "action.back": "Back",
  "action.admin": "Admin",

  // ----- errors (one line per code) -----
  "error.cli_missing": "The Shopify CLI isn't installed",
  "error.cli_checking": "Still checking the Shopify CLI",
  "error.cli_installing": "The Shopify CLI is installing",
  "error.signed_out": "Signed out of Shopify",
  "error.theme_session_expired": "Your Shopify session expired. Sign in again.",
  "error.sales_access_required": "Sales access needed",
  "error.store_unavailable": "This store is paused or unavailable",
  "error.rate_limited": "Shopify is limiting requests",
  "error.timeout": "Shopify took too long to respond",
  "error.terminated": "Stopped",
  "error.bad_response": "Unexpected response from Shopify",
  "error.output_too_large": "Shopify's response was too large",
  "error.cli_failed": "The Shopify CLI failed: {message}",
  "error.tool_failed": "A system tool failed: {message}",
  "error.internal_error": "Shop hit a bug: {message}",
  "error.clipboard_too_large": "The clipboard is too large to paste here",
  "error.clipboard_unavailable": "Pasting needs wl-paste (wl-clipboard)",
  "error.store_busy": "Another action is running for this store",
  "error.store_busy.action": "Wait for the {action} to finish",
  "error.store_busy.blocked": "Stop the preview before you {action}",
  "error.store_busy.anyStore": "Wait for the running push, pull, restore or preview to finish",
  "error.store_busy.grant": "Wait for the sales access grant in your browser to finish",
  "error.account_busy": "Shop is busy with your Shopify account",
  "error.confirm_open": "Answer the open confirmation first",
  "error.recently_declined": "You just declined this — try again in a moment",
  "error.config_busy": "Saving config.json…",
  "error.config_unavailable": "Shop is still loading",
  "error.backup_failed": "Backup failed, so nothing was changed",
  "error.backup_not_found": "That backup is incomplete or missing",
  "error.theme_not_found": "That theme no longer exists",
  "error.not_a_theme_folder": "Not a theme folder: it needs config/, layout/ and templates/",
  "error.unsafe_folder": "Shop can't use this folder",
  "error.folder_unusable": "Can't {action}: fix the folder first",
  "error.folder_unusable.empty": "Can't {action} an empty folder: pull a theme into it first",
  "error.folder_too_large": "The folder is too large to copy before pulling",
  "error.live_not_allowed": "Live theme changes are off for this store",
  "error.live_not_confirmed": "Changing the live theme needs confirmation",
  "error.invalid_domain": "Enter a .myshopify.com address",
  "error.duplicate_store": "That store is already added",
  "error.too_many_stores": "Shop keeps at most 50 stores",
  "error.unknown_store": "That store isn't in Shop",
  "error.invalid_patch": "That change isn't allowed",
  "error.no_theme_folder": "Link a theme folder first",
  "error.rate_limited_locally": "Just refreshed — try again in a moment",
  "error.config_invalid": "config.json needs fixing first",
  "error.config_unsupported": "This config.json is from a different Shop version.",
  "error.config_write_failed": "Couldn't save config.json: {message}",
  "error.failed_to_start": "Couldn't start a Shop helper",
  "error.mise_missing": "mise isn't installed",
  "error.invalid_argument": "That value isn't valid",
  "error.unsafe_state_dir": "Shop's state folder is a link or owned by someone else",
  "error.no_pending": "That confirmation expired",
  "error.default": "Something went wrong: {message}",

  // ----- new-order notifications (model/OrderAlerts) -----
  "alert.title": "{n} new orders · {label}",
  "alert.title.one": "New order · {label}",
  "alert.moreItems": " +{n} more items",
  "alert.moreItems.one": " +1 more item",
  "alert.body": "{number} · {total} · {firstItem}{moreItems}\n{orders} today · {sales}",
  "alert.testTitle": "Shop test alert",
  "alert.testBody": "Alerts are working.",

  // ----- key sheet: the sheet's chrome and the keymap rows' labels -----
  "keys.title": "Keys",
  "keys.closeSheet": "Esc / ? close",
  "keys.group.navigate": "Navigate",
  "keys.group.view": "This view",
  "keys.group.panel": "Panel",
  "keys.move": "Move",
  "keys.viewStore": "Open store",
  "keys.closePanel": "Close panel",
  "keys.scroll": "Scroll",
  "keys.switch": "Switch panel",
  "keys.refreshAll": "Refresh all",
  "keys.refreshStore": "Refresh store",
  "keys.help": "This sheet",
  "keys.reorder": "Reorder stores",
  "keys.period": "Previous / next period",
  "keys.period.jump": "Jump to period",
  "keys.admin": "Open Shopify admin",
  "keys.grant": "Grant sales access",
  "keys.cancelGrant": "Cancel granting access",
  "keys.pull": "Pull…",
  "keys.preview": "Start preview",
  "keys.openPreview": "Open preview",
  "keys.stopPreview": "Stop preview",
  "keys.cancelJob": "Cancel theme job",
  "keys.backups": "Backups",
  "keys.resultDetails": "Show / hide details",
  "keys.dismissThemeResult": "Dismiss theme result",
  "keys.addSelected": "Add selected store",
  "keys.addByDomain": "Add a store by its domain",
  "keys.filter": "Filter stores",
  "keys.discoverAgain": "Find stores again",
  "keys.activate": "Toggle / activate",
  "keys.option": "Change option",
  "keys.fields": "Next / previous field (while typing)",
  "keys.reloadThemes": "Reload themes",
  "keys.reloadBackups": "Reload backups",
  "keys.banner": "Banner action (first / second)",
  "keys.banner.one": "Banner action",
  "keys.runStep": "Run the highlighted step",
  "keys.runButton": "Run the highlighted button",
  "keys.chooseButton": "Choose a button",
  "keys.chooseFolder": "Choose a theme folder",

  // ----- footer: a keymap row's short label after its key -----
  "hints.keys": "? keys",
  "hints.back": "back",
  "hints.broken": "i open file · Shift+i reset",
  "hints.open": "open",
  "hints.add": "add",
  "hints.settings": "settings",
  "hints.period": "period",
  "hints.edit": "edit",
  "hints.admin": "admin",
  "hints.run.step": "run step",
  "hints.run": "run",
  "hints.choose": "choose",
  "hints.push": "push",
  "hints.pull": "pull",
  "hints.backups": "backups",
  "hints.grant": "grant access",
  "hints.signIn": "sign in",
  "hints.install": "install",
  "hints.cancel": "cancel",
  "hints.choose.folder": "choose folder",
  "hints.stopPreview": "stop",
  "hints.open.preview": "open preview",
  "hints.restartPreview": "restart preview",
  "hints.filter": "filter",
  "hints.add.byDomain": "add by domain",
  "hints.restore": "restore",
  "hints.open.folder": "open folder",
  "hints.reload": "reload",
  "hints.savesAsYouGo": "changes save as you go"

}

function has(key) {
  return Object.prototype.hasOwnProperty.call(STRINGS, key)
}

// The string for `key` with its placeholders filled. A missing key renders
// as the key itself, so a miss is visible.
export function t(key, vars) {
  return fillTemplate(has(key) ? STRINGS[key] : key, vars)
}

// "updated 2 min ago", or "not updated yet" before any fetch (atMs <= 0).
export function updatedText(atMs, nowMs) {
  return atMs > 0 ? t("home.updated", { ago: timeAgo(atMs, nowMs) }) : t("home.never")
}

// The rate-limit line with the retry time ("…" when Shopify gave none).
export function limitedText(retryAtMs) {
  const at = Number(retryAtMs) || 0
  return t("store.limited", { time: at > 0 ? clockLocal(at) : "…" })
}

// A theme's display name ({id, name, live}: Snapshot.targetTheme, a backup's
// theme): its name, else "Live theme" for a live target without one, else
// "Theme {id}".
export function themeName(theme) {
  const th = theme || {}
  if (th.name) return String(th.name)
  return th.live === true ? t("theme.liveTheme") : t("theme.themeId", { id: th.id })
}

// Counted nouns: the one place that picks singular or plural, from
// "count.<noun>" and "count.<noun>.one".
export function countText(n, noun) {
  const v = Number(n || 0)
  return v === 1 ? t("count." + noun + ".one") : t("count." + noun, { n: count(v) })
}
export function ordersText(n) { return countText(n, "orders") }
export function sessionsText(n) { return countText(n, "sessions") }
export function storesText(n) { return countText(n, "stores") }
export function filesText(n) { return countText(n, "files") }

export function unsafeText(reason) {
  const key = "theme.unsafe." + String(reason || "")
  if (has(key)) return STRINGS[key]
  return t("theme.unsafe.default", { reason: String(reason || "") })
}

// Text for a `{code, message, reason?}` error object (null-safe).
// `message` is the helper's cleaned, capped message; it is only shown
// inside {message} slots.
export function errorOf(err) {
  if (!err) return ""
  if (err.code === "unsafe_folder" && err.reason) return unsafeText(err.reason)
  if (err.code === "store_busy" && err.anyStore === true) return t(err.what === "access" ? "error.store_busy.grant" : "error.store_busy.anyStore")
  // Preflight names the work holding the store (and the action a running
  // preview blocks), so the panel says what to wait for or stop.
  if (err.code === "store_busy" && err.blocked) return t("error.store_busy.blocked", { action: t("job.noun." + err.blocked) })
  if (err.code === "store_busy" && err.action) return t("error.store_busy.action", { action: t("job.noun." + err.action) })
  // The folder line under the target already says what is wrong with it.
  if (err.code === "folder_unusable" && err.action)
    return t(err.state === "empty" ? "error.folder_unusable.empty" : "error.folder_unusable", { action: t("job.noun." + err.action) })
  const c = String(err.code || "")
  const m = err.message === undefined || err.message === null ? "" : String(err.message)
  if (c !== "" && has("error." + c)) return t("error." + c, { message: m })
  return t("error.default", { message: m !== "" ? m : c })
}

export function periodCaption(id) {
  return t("caption." + id)
}

// The baseline phrase next to a trend, from "trend.baseline." + periodId
// (today, yesterday, last7d, last14d, last30d): "$35.50 at this time
// yesterday", "$1,204 the day before", "$8,120 previous 7 days". Empty
// without a comparison (12m) or without an amount.
export function baselineText(periodId, amountText) {
  const a = String(amountText || "")
  if (a === "") return ""
  const key = "trend.baseline." + periodId
  return has(key) ? t(key, { amount: a }) : ""
}

// The warning under a theme card's folder row for `folder` (the store's
// theme.folder), from the last inspection (Themes.folderState): empty
// until inspect-folder has answered for that folder, and for a usable one
// (theme-shaped, or still empty: a pull target).
export function folderWarning(ts, folder) {
  const state = folderState(ts, folder)
  if (state === "error") return ts.folder.error ? errorOf(ts.folder.error) : t("error.default", { message: "" })
  if (state === "missing") return t("theme.folderMissing")
  if (state === "unsafe") return unsafeText(ts.folder.reason)
  if (state === "notTheme") return t("error.not_a_theme_folder")
  return ""
}

// Edit's target picker rows ([{value, label, description}]) for the saved
// target ("live" or a theme id): "Live theme · <name>" first, then every
// other theme in the cached list ("<role> · <id>" under its name), and the
// saved id itself when the list does not have it.
export function themeTargetOptions(ts, target) {
  const saved = String(target || "live")
  const items = ts && ts.themes && Array.isArray(ts.themes.items) ? ts.themes.items : []
  let live = null
  for (let i = 0; i < items.length; i++) if (items[i].role === "live") live = items[i]
  const out = [{ value: "live", label: t("theme.liveTheme") + (live ? " · " + String(live.name || "") : ""), description: "" }]
  for (let i = 0; i < items.length; i++) {
    if (items[i].role === "live") continue
    out.push({ value: String(items[i].id), label: String(items[i].name || ""), description: String(items[i].role || "") + " · " + items[i].id })
  }
  if (!out.some(o => o.value === saved)) out.push({ value: saved, label: t("theme.themeId", { id: saved }), description: "" })
  return out
}
