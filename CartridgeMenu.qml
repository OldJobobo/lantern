import QtQuick

FocusScope {
  id: menu

  required property var controller

  function focusCurrent() {
    forceActiveFocus()
    cartridgeList.positionViewAtIndex(controller.menuIndex, ListView.Contain)
  }

  Keys.onUpPressed: function(event) {
    controller.moveMenuSelection(-1)
    event.accepted = true
  }
  Keys.onDownPressed: function(event) {
    controller.moveMenuSelection(1)
    event.accepted = true
  }
  Keys.onLeftPressed: function(event) {
    controller.backToEngines()
    event.accepted = true
  }
  Keys.onReturnPressed: function(event) {
    controller.activateMenuSelection()
    event.accepted = true
  }
  Keys.onEnterPressed: function(event) {
    controller.activateMenuSelection()
    event.accepted = true
  }
  Keys.onEscapePressed: function(event) {
    controller.backToEngines()
    event.accepted = true
  }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
      controller.menuIndex = event.key === Qt.Key_Home
        ? 0 : Math.max(0, controller.menuCartridges.length - 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_B || event.key === Qt.Key_Backspace) {
      controller.backToEngines()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_I) {
      controller.beginCartridgeImport()
      event.accepted = true
      return
    }
    if (event.key < Qt.Key_1 || event.key > Qt.Key_9) return
    var selected = event.key - Qt.Key_1
    if (selected >= controller.menuCartridges.length) return
    controller.menuIndex = selected
    controller.activateMenuSelection()
    event.accepted = true
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: 74
    anchors.rightMargin: 74
    anchors.topMargin: 34
    anchors.bottomMargin: 28
    spacing: 12

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: controller.lanternLogo
      color: controller.phosphorColor
      font.family: "monospace"
      font.pixelSize: 15
      font.bold: true
      font.letterSpacing: 0.35
      lineHeight: 0.95
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
    }

    Row {
      width: parent.width
      height: 24

      Text {
        width: parent.width * 0.7
        text: controller.engines[controller.engineIndex].title + "  //  SELECT A CARTRIDGE"
        color: controller.phosphorDim
        font.family: "monospace"
        font.pixelSize: 12
        font.bold: true
        font.letterSpacing: 1.2
        textFormat: Text.PlainText
      }

      Text {
        width: parent.width * 0.3
        text: "<  ENGINE MENU"
        color: controller.phosphorMuted
        font.family: "monospace"
        font.pixelSize: 11
        font.bold: true
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: controller.backToEngines()
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: controller.phosphorDim
      opacity: 0.55
    }

    ListView {
      id: cartridgeList
      width: parent.width
      height: parent.height - 202
      clip: true
      spacing: 8
      boundsBehavior: Flickable.StopAtBounds
      model: controller.menuCartridges
      currentIndex: controller.menuIndex
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: Rectangle {
        required property int index
        required property var modelData
        readonly property bool selected: index === controller.menuIndex
        readonly property bool actionRow: modelData.action === "import"
        width: cartridgeList.width
        height: actionRow ? 62 : 76
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
          anchors.topMargin: parent.actionRow ? 20 : 14
          width: parent.width - 78
          text: parent.actionRow ? "+  IMPORT CARTRIDGE"
            : "[ " + parent.modelData.number + " ]  " + parent.modelData.title
          color: controller.phosphorColor
          font.family: "monospace"
          font.pixelSize: parent.actionRow ? 15 : 18
          font.bold: true
          font.letterSpacing: 0.45
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          visible: !parent.actionRow
          anchors.left: parent.left
          anchors.leftMargin: 52
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 13
          width: parent.width - 78
          text: String(parent.modelData.subtitle || "")
          color: controller.phosphorDim
          font.family: "monospace"
          font.pixelSize: 12
          font.letterSpacing: 0.55
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: {
            controller.menuIndex = parent.index
            controller.activateMenuSelection()
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: controller.currentEngineId() === "adventure"
        ? "UP/DOWN  SELECT    ENTER  BOOT    ESC/LEFT  ENGINES"
        : "UP/DOWN  SELECT    ENTER  BOOT    I  IMPORT    ESC/LEFT  ENGINES"
      color: controller.phosphorDim
      font.family: "monospace"
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 0.65
      textFormat: Text.PlainText
    }
  }
}
