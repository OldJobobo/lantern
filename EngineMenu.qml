import QtQuick

FocusScope {
  id: menu

  required property var controller

  function focusCurrent() {
    forceActiveFocus()
  }

  Keys.onUpPressed: function(event) {
    controller.moveEngineSelection(-1)
    event.accepted = true
  }
  Keys.onDownPressed: function(event) {
    controller.moveEngineSelection(1)
    event.accepted = true
  }
  Keys.onReturnPressed: function(event) {
    controller.enterSelectedEngine()
    event.accepted = true
  }
  Keys.onEnterPressed: function(event) {
    controller.enterSelectedEngine()
    event.accepted = true
  }
  Keys.onEscapePressed: function(event) {
    controller.requestClose()
    event.accepted = true
  }
  Keys.onPressed: function(event) {
    if (event.key < Qt.Key_1 || event.key > Qt.Key_3) return
    controller.selectEngine(event.key - Qt.Key_1)
    controller.enterSelectedEngine()
    event.accepted = true
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - 150
    spacing: 16

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: controller.lanternLogo
      color: controller.phosphorColor
      font.family: "monospace"
      font.pixelSize: 18
      font.bold: true
      font.letterSpacing: 0.4
      lineHeight: 1.0
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "INTERACTIVE FICTION TERMINAL  //  SELECT AN ENGINE"
      color: controller.phosphorDim
      font.family: "monospace"
      font.pixelSize: 12
      font.bold: true
      font.letterSpacing: 1.35
      textFormat: Text.PlainText
    }

    Rectangle {
      width: parent.width
      height: 1
      color: controller.phosphorDim
      opacity: 0.55
    }

    Column {
      width: parent.width
      spacing: 8

      Repeater {
        model: controller.engines

        delegate: Rectangle {
          required property int index
          required property var modelData
          readonly property bool selected: index === controller.engineIndex
          width: parent.width
          height: 76
          color: selected
            ? Qt.rgba(controller.phosphorColor.r, controller.phosphorColor.g, controller.phosphorColor.b, 0.09)
            : "transparent"
          border.width: 1
          border.color: selected ? controller.phosphorDim
            : Qt.rgba(controller.phosphorColor.r, controller.phosphorColor.g, controller.phosphorColor.b, 0.16)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: parent.selected ? ">" : " "
            color: controller.phosphorColor
            font.family: "monospace"
            font.pixelSize: 18
            font.bold: true
            textFormat: Text.PlainText
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 52
            anchors.top: parent.top
            anchors.topMargin: 14
            text: "[ " + (parent.index + 1 < 10 ? "0" : "") + String(parent.index + 1)
              + " ]  " + parent.modelData.title
            color: controller.phosphorColor
            font.family: "monospace"
            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 0.5
            textFormat: Text.PlainText
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 52
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 13
            text: parent.modelData.detail
            color: controller.phosphorDim
            font.family: "monospace"
            font.pixelSize: 12
            font.letterSpacing: 0.6
            textFormat: Text.PlainText
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
              controller.selectEngine(parent.index)
              controller.enterSelectedEngine()
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "UP/DOWN  SELECT    ENTER  OPEN ENGINE    1-3  DIRECT"
      color: controller.phosphorDim
      font.family: "monospace"
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 0.75
      textFormat: Text.PlainText
    }
  }
}
