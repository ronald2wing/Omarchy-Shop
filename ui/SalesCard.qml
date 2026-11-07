pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../js/metrics.mjs" as Metrics
import "../js/format.mjs" as Format
import "../js/snapshot.mjs" as Snapshot

// The store's figures for one period: the caption, the hero amount with its
// trend and baseline, the partial-total warning, the sparkline, which sales
// the figures count, the KPI tiles, the traffic age, and the rate-limit or
// fetch-failure line. StoreView shows it while the store has figures to
// show (figuresShown).
//
// Contract: store; periodId; nowMs; figuresShown; limitBannerShown (the
// panel banner already says Shopify is limiting requests); signal
// retryRequested(). `shown` is whether any line shows, for the owner's
// `visible` (an empty card must not add spacing to the view).
Column {
  id: root

  property var store: null
  property string periodId: "today"
  property real nowMs: 0
  property bool figuresShown: false
  property bool limitBannerShown: false

  signal retryRequested()

  readonly property var sales: root.store && root.store.sales ? root.store.sales : null
  readonly property string currency: root.store && root.store.currency ? root.store.currency : ""
  readonly property var view: root.store ? Metrics.periodView(root.store, root.periodId) : null
  readonly property var buckets: root.view && root.view.buckets ? root.view.buckets : []
  // The one "…" rule (Metrics.awaitingFigures), shared with the KPI tiles and Home.
  readonly property bool loading: Metrics.awaitingFigures(root.sales)
  readonly property bool hasFigures: !!root.view && root.view.sales !== null && root.view.sales !== undefined
  readonly property var salesError: root.sales && root.sales.error ? root.sales.error : null
  readonly property bool fetchFailed: root.figuresShown && Snapshot.salesFailed(root.store)
  readonly property string trafficAgeText: {
    if (root.periodId !== "today" || !root.sales || !root.sales.fetchedAt) return ""
    var live = Number(root.sales.fetchedAt.today) || 0
    var traffic = Number(root.sales.fetchedAt.traffic) || 0
    if (live <= 0 || traffic <= 0 || live - traffic <= 90000) return ""
    return Copy.t("kpi.trafficAge", { ago: Format.timeAgo(traffic, root.nowMs) })
  }
  readonly property string baselineText: {
    if (!root.view || !root.view.compare || !Format.isNum(root.view.compare.sales)) return ""
    return Copy.baselineText(root.periodId, Format.money(root.view.compare.sales, root.currency))
  }
  readonly property string heroText: root.hasFigures ? Format.money(root.view.sales, root.currency)
    : (root.loading ? "…" : "—")
  readonly property bool shown: root.figuresShown || root.trafficAgeText !== ""

  spacing: Look.gapLg

  // Hero.
  Column {
    visible: root.figuresShown
    width: parent.width
    spacing: Style.space(2)

    PlainLabel {
      text: Copy.periodCaption(root.periodId).toUpperCase()
      color: Look.muted
      font.pixelSize: Look.small
      font.bold: true
      font.letterSpacing: 1.2
    }

    Item {
      width: parent.width
      height: Math.max(heroAmount.implicitHeight, heroTrend.implicitHeight)

      PlainLabel {
        id: heroAmount
        anchors.left: parent.left
        anchors.right: heroTrend.visible ? heroTrend.left : parent.right
        anchors.rightMargin: Look.gapLg
        anchors.bottom: parent.bottom
        text: root.heroText
        font.pixelSize: Look.display
        font.bold: true
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Look.title
        elide: Text.ElideRight
      }

      TrendBadge {
        id: heroTrend
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(3)
        trend: root.view ? root.view.salesTrend : null
        baselineText: root.baselineText
      }
    }

    PlainLabel {
      visible: root.periodId === "today" && !!root.sales && !!root.sales.today && !!root.sales.today.truncated
      width: parent.width
      text: "󰀦 " + Copy.t("store.truncated")
      color: Look.warn
      font.pixelSize: Look.small
      wrapMode: Text.WordWrap
    }
  }

  Sparkline {
    visible: root.figuresShown && root.buckets.length > 1
    width: parent.width
    buckets: root.buckets
    currency: root.currency
  }

  // Which sales the figures, chart and comparison count (README › About the
  // figures): today's live order totals, or Shopify's net
  // sales for the completed periods.
  PlainLabel {
    visible: root.figuresShown && root.hasFigures
    width: parent.width
    text: Copy.t(root.periodId === "today" ? "source.today" : "source.history")
    color: Look.muted
    font.pixelSize: Look.caption
    elide: Text.ElideRight
  }

  KpiGrid {
    visible: root.figuresShown
    width: parent.width
    store: root.store
    periodId: root.periodId
  }

  PlainLabel {
    visible: text !== ""
    text: root.trafficAgeText
    color: Look.muted
    font.pixelSize: Look.caption
  }

  // Shopify is throttling: the figures stay, the retry is automatic. The
  // panel banner says so first; this line shows only while a higher
  // banner (signed out, CLI missing, config error) has displaced it, so
  // the screen never says it twice.
  StatusLine {
    visible: root.figuresShown && Snapshot.salesRateLimited(root.store) && !root.limitBannerShown
    width: parent.width
    tone: "info"
    text: Copy.limitedText(root.sales ? root.sales.retryAt : 0)
  }

  StatusLine {
    visible: root.fetchFailed
    width: parent.width
    tone: "error"
    text: Copy.errorOf(root.salesError)
    actions: [{ id: "retry", label: Copy.t("action.retry") }]
    onAction: root.retryRequested()
  }
}
