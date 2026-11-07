import QtQuick

// A view's keyboard cursor, kept as a row id, never an index: when rows
// come and go (a relist puts a new backup on top, a store moves, a
// Settings row hides) the cursor stays on its row, so Enter never lands on
// whatever slid under an old index. When its row leaves, the cursor goes
// to the nearest surviving row: with `order` (the view's fixed, full row
// order) the nearest one above it there, else below; without it the row
// now at its old position, clamped. While `ids` is empty (a list not
// loaded yet, config.json unreadable) the id is kept for when rows return.
//
// Contract: ids (the rows, top to bottom); rowId (the cursor's id,
// writable: a row the pointer entered, a field that took focus); rowIndex
// (its position in ids, -1 off any row); order; view (its itemFor(id) gives the row's Item)
// and panel (ensureVisible) for moveBy and reveal; moveBy(dy), moveTo(id),
// neighbour(id, dy), reveal().
QtObject {
  id: cursor

  property var ids: []
  property string rowId: ""
  property var order: []
  property var view: null
  property var panel: null
  readonly property int rowIndex: cursor.ids.indexOf(cursor.rowId)

  property var lastIds: []

  // The row dy rows from `id`, clamped to the list ("" when it is empty).
  function neighbour(id, dy) {
    var n = cursor.ids.length
    if (n === 0) return ""
    var i = cursor.ids.indexOf(id)
    return cursor.ids[Math.max(0, Math.min(n - 1, (i < 0 ? 0 : i) + dy))]
  }

  function moveTo(id) {
    if (cursor.ids.indexOf(id) >= 0) cursor.rowId = id
  }

  // j/k: one row on, clamped, and scrolled into view.
  function moveBy(dy) {
    if (dy === 0 || cursor.ids.length === 0) return
    cursor.rowId = cursor.neighbour(cursor.rowId, dy)
    cursor.reveal()
  }

  function reveal() {
    if (cursor.panel && cursor.view && cursor.rowIndex >= 0) cursor.panel.ensureVisible(cursor.view.itemFor(cursor.rowId))
  }

  // Where the cursor goes when its row is not in `ids` (prev: the rows it
  // was among).
  function fallback(ids, prev) {
    var gone = cursor.rowId
    if (gone !== "" && cursor.order.length > 0) {
      var at = cursor.order.indexOf(gone)
      for (var up = at - 1; at >= 0 && up >= 0; up--) if (ids.indexOf(cursor.order[up]) >= 0) return cursor.order[up]
      for (var down = at + 1; at >= 0 && down < cursor.order.length; down++) if (ids.indexOf(cursor.order[down]) >= 0) return cursor.order[down]
    }
    var was = prev.indexOf(gone)
    return ids[was < 0 ? 0 : Math.min(was, ids.length - 1)]
  }

  function settle() {
    var ids = cursor.ids
    var prev = cursor.lastIds
    cursor.lastIds = ids
    if (ids.length === 0 || ids.indexOf(cursor.rowId) >= 0) return
    cursor.rowId = cursor.fallback(ids, prev)
  }

  onIdsChanged: cursor.settle()
  Component.onCompleted: cursor.settle()
}
