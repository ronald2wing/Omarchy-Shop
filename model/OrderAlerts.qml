pragma ComponentBehavior: Bound
import QtQuick
import "../js/copy.mjs" as Copy
import "../js/format.mjs" as Format

// New-order notifications through helpers/notify-order, with their text
// from js/copy.mjs (`alert.*`). One notification runs at a time; a burst
// queues at most a few.
Item {
  id: root

  // { notify: bool|null, sound: bool|null }; null = not known yet.
  readonly property var health: internal.health

  // label: the store's label; today: the live `today` object, which always
  // has a latestOrder (the caller notifies only once a new order is
  // detected); currency; delta: the new-order count (> 0).
  function notify(label, today, currency, delta, withSound) {
    const title = delta > 1 ? Copy.t("alert.title", { n: String(delta), label: label }) : Copy.t("alert.title.one", { label: label })
    const o = today.latestOrder
    const items = typeof o.itemCount === "number" ? o.itemCount : 0
    const more = items > 2 ? Copy.t("alert.moreItems", { n: String(items - 1) }) : (items === 2 ? Copy.t("alert.moreItems.one") : "")
    const body = Copy.t("alert.body", {
      number: String(o.number || ""),
      total: Format.money(o.total, currency),
      firstItem: String(o.firstItem || ""),
      moreItems: more,
      orders: Copy.ordersText(today.orders),
      sales: Format.money(today.sales, currency)
    })
    internal.send(title, body, withSound)
  }

  function test(withSound) {
    internal.send(Copy.t("alert.testTitle"), Copy.t("alert.testBody"), withSound)
  }

  QtObject {
    id: internal
    property var health: ({ notify: null, sound: null })
    property var pending: []

    // helpers/notify-order neutralises markup and caps both at 300 chars.
    function send(title, body, withSound) {
      const args = ["--title=" + title, "--body=" + body]
      if (withSound) args.push("--sound")
      if (proc.running) {
        if (internal.pending.length < 3) internal.pending.push(args)
        return
      }
      proc.run(args)
    }

    function next() {
      if (internal.pending.length > 0) proc.run(internal.pending.shift())
    }
  }

  HelperProcess {
    id: proc
    helper: "notify-order"
    onFinished: (r) => {
      if (r.ok) {
        internal.health = {
          notify: r.notified === true,
          sound: r.sound === null ? internal.health.sound : r.sound === true
        }
      }
      internal.next()
    }
  }
}
