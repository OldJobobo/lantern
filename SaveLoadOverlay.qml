import QtQuick

Item {
  id: overlay

  required property var controller
  required property var saveModel

  function focusCurrent() {
    if (controller.fileActionMode === "save") saveNameInput.forceActiveFocus()
    else actionFocus.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(controller.screenColor.r, controller.screenColor.g, controller.screenColor.b, 0.92)

    FocusScope {
      id: actionFocus
      anchors.fill: parent
      focus: overlay.visible

      Keys.onEscapePressed: function(event) {
        controller.closeFileAction(true)
        event.accepted = true
      }
      Keys.onUpPressed: function(event) {
        if (controller.fileActionMode === "load") controller.moveLoadSelection(-1)
        event.accepted = true
      }
      Keys.onDownPressed: function(event) {
        if (controller.fileActionMode === "load") controller.moveLoadSelection(1)
        event.accepted = true
      }
      Keys.onReturnPressed: function(event) {
        if (controller.fileActionMode !== "load") return
        controller.completeSelectedLoad()
        event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (controller.fileActionMode !== "load") return
        controller.completeSelectedLoad()
        event.accepted = true
      }

      Rectangle {
        width: 620
        height: controller.fileActionMode === "save" ? 224 : 390
        anchors.centerIn: parent
        color: controller.screenColor
        border.width: 1
        border.color: controller.phosphorDim

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 22
          anchors.top: parent.top
          anchors.topMargin: 18
          text: controller.fileActionMode === "save" ? "MEMORY BANK  //  SAVE GAME" : "MEMORY BANK  //  RESTORE GAME"
          color: controller.phosphorColor
          font.family: "monospace"
          font.pixelSize: 15
          font.bold: true
          font.letterSpacing: 1
          textFormat: Text.PlainText
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 22
          anchors.top: parent.top
          anchors.topMargin: 20
          text: overlay.saveModel.count + (overlay.saveModel.count === 1 ? " SAVE" : " SAVES")
          color: controller.phosphorDim
          font.family: "monospace"
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 0.7
          textFormat: Text.PlainText
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 22
          anchors.rightMargin: 22
          anchors.top: parent.top
          anchors.topMargin: 50
          height: 1
          color: controller.phosphorDim
          opacity: 0.65
        }

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 22
          anchors.rightMargin: 22
          anchors.top: parent.top
          anchors.topMargin: 72
          spacing: 10
          visible: controller.fileActionMode === "save"

          Text {
            text: controller.saveOverwritePending ? "OVERWRITE SAVE" : "SAVE AS"
            color: controller.phosphorDim
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.8
            textFormat: Text.PlainText
          }

          Rectangle {
            width: parent.width
            height: 42
            color: Qt.rgba(controller.phosphorColor.r, controller.phosphorColor.g, controller.phosphorColor.b, 0.055)
            border.width: 1
            border.color: controller.saveOverwritePending ? controller.phosphorColor : controller.phosphorDim

            TextInput {
              id: saveNameInput
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              verticalAlignment: TextInput.AlignVCenter
              text: controller.saveDraft
              color: controller.phosphorColor
              selectionColor: controller.phosphorDim
              selectedTextColor: controller.screenColor
              font.family: "monospace"
              font.pixelSize: 15
              font.letterSpacing: 0.4
              maximumLength: 20
              selectByMouse: true
              onTextEdited: {
                controller.saveDraft = text
                controller.saveOverwritePending = false
                controller.fileActionMessage = ""
              }
              onAccepted: controller.completeSave(text, controller.saveOverwritePending)
            }
          }

          Text {
            width: parent.width
            text: controller.fileActionMessage !== "" ? controller.fileActionMessage : "ENTER  WRITE SAVE    ESC  CANCEL"
            color: controller.fileActionMessage !== "" ? controller.phosphorColor : controller.phosphorDim
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: controller.fileActionMessage !== ""
            font.letterSpacing: 0.7
            textFormat: Text.PlainText
          }
        }

        ListView {
          id: loadSaveList
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 22
          anchors.rightMargin: 22
          anchors.top: parent.top
          anchors.topMargin: 70
          height: 242
          visible: controller.fileActionMode === "load"
          clip: true
          spacing: 4
          model: overlay.saveModel
          currentIndex: controller.loadSaveIndex

          delegate: Rectangle {
            required property int index
            required property string fileName
            required property var fileModified
            readonly property bool selected: index === controller.loadSaveIndex
            width: loadSaveList.width
            height: 42
            color: selected ? Qt.rgba(controller.phosphorColor.r, controller.phosphorColor.g, controller.phosphorColor.b, 0.10) : "transparent"
            border.width: 1
            border.color: selected ? controller.phosphorDim : Qt.rgba(controller.phosphorColor.r, controller.phosphorColor.g, controller.phosphorColor.b, 0.14)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: parent.selected ? ">" : " "
              color: controller.phosphorColor
              font.family: "monospace"
              font.pixelSize: 13
              font.bold: true
              textFormat: Text.PlainText
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 36
              anchors.verticalCenter: parent.verticalCenter
              text: parent.fileName.replace(/\.qzl$/i, "")
              color: controller.phosphorColor
              font.family: "monospace"
              font.pixelSize: 13
              font.bold: parent.selected
              textFormat: Text.PlainText
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: Qt.formatDateTime(parent.fileModified, "MMM d  HH:mm")
              color: controller.phosphorDim
              font.family: "monospace"
              font.pixelSize: 10
              font.letterSpacing: 0.4
              textFormat: Text.PlainText
            }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              onTapped: controller.loadSaveIndex = parent.index
              onDoubleTapped: controller.completeLoad(parent.fileName)
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 22
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 20
          visible: controller.fileActionMode === "load"
          text: controller.fileActionMessage !== "" ? controller.fileActionMessage : "UP/DOWN  SELECT    ENTER  RESTORE    ESC  CANCEL"
          color: controller.fileActionMessage !== "" ? controller.phosphorColor : controller.phosphorDim
          font.family: "monospace"
          font.pixelSize: 10
          font.bold: controller.fileActionMessage !== ""
          font.letterSpacing: 0.65
          textFormat: Text.PlainText
        }
      }
    }
  }
}
