pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Steps with a ✓ for the finished ones and small buttons for the open
// ones; numbered when there are several, a bullet for a lone step (a "1"
// would promise steps that never come). Home's first run ("Set up Shop")
// and the store's sales-access step use it.
//
// Contract:
//   title        optional heading (Look.small, uppercase)
//   steps        [{id, label, done, actions: [] or [{id, label}], help: "" or text}]
//   cursorStep   index of the step whose button the keyboard cursor lights
//                (-1 none); cursorAction picks among that step's buttons
//   activate()   runs the lit button
//   actionCount(stepIndex) for the view's h/l handling
//   signals      activated(id) with the action id
Column {
  id: root

  property string title: ""
  property var steps: []
  property int cursorStep: -1
  property int cursorAction: 0

  signal activated(string id)

  // cursorStep can be -1 or past the last step.
  function actionsOf(step) {
    return step ? step.actions : []
  }

  function actionCount(stepIndex) {
    return root.actionsOf(root.steps[stepIndex]).length
  }

  function activate() {
    var acts = root.actionsOf(root.steps[root.cursorStep])
    var a = acts[Math.max(0, Math.min(acts.length - 1, root.cursorAction))]
    if (!a) return
    root.activated(String(a.id))
  }

  spacing: Look.gapLg

  SectionHeader {
    visible: root.title !== ""
    text: root.title.toUpperCase()
  }

  Repeater {
    model: root.steps

    delegate: Item {
      id: stepRow
      required property var modelData
      required property int index
      readonly property bool done: modelData.done
      readonly property var acts: root.actionsOf(modelData)
      readonly property string help: modelData.help

      width: parent ? parent.width : 0
      implicitHeight: Math.max(stepText.implicitHeight, buttons.implicitHeight)

      PlainLabel {
        id: marker
        anchors.left: parent.left
        anchors.top: parent.top
        width: Style.space(18)
        text: stepRow.done ? "✓" : (root.steps.length > 1 ? String(stepRow.index + 1) : "•")
        color: stepRow.done ? Look.positive : Look.muted
        font.bold: !stepRow.done
      }

      Column {
        id: stepText
        anchors.left: marker.right
        anchors.right: buttons.visible ? buttons.left : parent.right
        anchors.rightMargin: buttons.visible ? Look.gapLg : 0
        anchors.top: parent.top
        spacing: Look.gapXs

        PlainLabel {
          width: parent.width
          text: stepRow.modelData.label
          color: stepRow.done ? Look.muted : Look.fg
          wrapMode: Text.WordWrap
        }

        PlainLabel {
          visible: stepRow.help !== ""
          width: parent.width
          text: stepRow.help
          color: Look.muted
          font.pixelSize: Look.small
          wrapMode: Text.WordWrap
        }
      }

      ActionButtons {
        id: buttons
        anchors.right: parent.right
        anchors.top: parent.top
        visible: !stepRow.done && stepRow.acts.length > 0
        actions: stepRow.acts
        cursorIndex: root.cursorStep === stepRow.index ? root.cursorAction : -1
        onActionPicked: (id) => root.activated(id)
      }
    }
  }
}
