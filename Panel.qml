import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false
  property string transcript: ""
  property string statusText: "READY"
  property string storyPath: ""
  property bool startPending: false
  property string pendingStoryPath: ""
  property string phosphor: "amber"
  property var commandHistory: []
  property int historyIndex: 0

  readonly property string homePath: Quickshell.env("HOME") || "/tmp"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homePath + "/.local/state"
  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl(".")))
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string runtimePath: pluginRoot + "/runtime/x86_64-linux/dfrotz"
  readonly property string bundledStoryPath: pluginRoot + "/games/zork1.z3"
  readonly property string saveRoot: stateRoot + "/lantern/saves"
  readonly property color phosphorColor: phosphor === "green" ? "#78ff83"
    : phosphor === "white" ? "#d8e7df" : "#ffb84d"
  readonly property color phosphorDim: Qt.rgba(phosphorColor.r, phosphorColor.g, phosphorColor.b, 0.48)

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) {}

    if (payload.phosphor === "green" || payload.phosphor === "white" || payload.phosphor === "amber")
      phosphor = payload.phosphor

    var requested = Model.safeStoryPath(payload.story || "")

    opened = true
    window.visible = true
    Qt.callLater(function() { commandInput.forceActiveFocus() })

    if (!frotzProc.running && !startPending) {
      pendingStoryPath = requested !== "" ? requested : bundledStoryPath
      startPending = true
      prepareDir.running = true
    }
  }

  function close() {
    closingFromHost = true
    opened = false
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "jobo.lantern")
    else close()
  }

  function appendOutput(raw) {
    var cleaned = Model.cleanOutput(raw)
    if (cleaned === "") return
    transcript = Model.appendTranscript(transcript, cleaned, 1200)
    Qt.callLater(scrollToBottom)
  }

  function scrollToBottom() {
    transcriptView.contentY = Math.max(0, transcriptText.height - transcriptView.height)
  }

  function submitCommand() {
    var command = Model.normalizeCommand(commandInput.text)
    if (command === "" || !frotzProc.running) return

    transcript = Model.appendTranscript(transcript, "\n> " + command, 1200)
    var nextHistory = commandHistory.slice(0)
    if (nextHistory.length === 0 || nextHistory[nextHistory.length - 1] !== command)
      nextHistory.push(command)
    if (nextHistory.length > 100) nextHistory = nextHistory.slice(nextHistory.length - 100)
    commandHistory = nextHistory
    historyIndex = commandHistory.length
    commandInput.text = ""
    frotzProc.write(command + "\n")
    Qt.callLater(scrollToBottom)
  }

  function stepHistory(direction) {
    var next = Model.historyStep(commandHistory, historyIndex, direction)
    historyIndex = next.index
    commandInput.text = next.value
    commandInput.cursorPosition = commandInput.text.length
  }

  Process {
    id: prepareDir
    command: ["mkdir", "-p", "--", root.saveRoot]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.startPending = false
        root.statusText = "STORAGE ERROR"
        root.appendOutput("Lantern could not prepare its game and save directories.")
        return
      }
      runtimeCheck.command = ["test", "-x", root.runtimePath]
      runtimeCheck.running = true
    }
  }

  Process {
    id: runtimeCheck
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.startPending = false
        root.statusText = "RUNTIME ERROR"
        root.appendOutput("Lantern's bundled x86-64 dfrotz runtime is missing or not executable. Reinstall the plugin from its official repository.")
        return
      }
      storyCheck.command = ["test", "-r", root.pendingStoryPath]
      storyCheck.running = true
    }
  }

  Process {
    id: storyCheck
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.startPending = false
        root.statusText = "NO STORY"
        root.appendOutput("The selected story could not be read. Reinstall Lantern to restore the bundled Zork I story, or summon it with another absolute story path.")
        return
      }
      root.statusText = "WARMING UP"
      root.storyPath = root.pendingStoryPath
      frotzProc.command = [root.runtimePath, "-q", "-m", "-w", "76", "-R", root.saveRoot, root.pendingStoryPath]
      frotzProc.running = true
      root.startPending = false
    }
  }

  Process {
    id: frotzProc
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.appendOutput(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = Model.cleanOutput(text)
        if (message !== "") root.appendOutput(message)
      }
    }
    onStarted: root.statusText = "ONLINE"
    onExited: function(exitCode) {
      root.statusText = exitCode === 0 ? "SESSION ENDED" : "FROTZ UNAVAILABLE"
      if (exitCode !== 0)
        root.appendOutput("Lantern's bundled dfrotz runtime could not be started. This release supports x86-64 glibc Linux systems.")
    }
  }

  FloatingWindow {
    id: window
    title: "Lantern — Interactive Fiction Terminal"
    visible: false
    color: "#111210"
    implicitWidth: 790
    implicitHeight: 620
    minimumSize: Qt.size(620, 480)

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    Rectangle {
      anchors.fill: parent
      color: "#141512"

      Rectangle {
        id: bezel
        anchors.fill: parent
        anchors.margins: 18
        radius: 18
        color: "#24241f"
        border.width: 2
        border.color: "#3a3931"

        Rectangle {
          anchors.fill: parent
          anchors.margins: 8
          radius: 14
          color: "#171814"
          border.width: 1
          border.color: "#0a0b09"
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 30
          anchors.top: parent.top
          anchors.topMargin: 16
          text: "LANTERN  //  Z-MACHINE TERMINAL"
          color: "#8c8978"
          font.family: "monospace"
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 1.5
          textFormat: Text.PlainText
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 30
          anchors.top: parent.top
          anchors.topMargin: 16
          text: root.statusText
          color: root.statusText === "ONLINE" ? root.phosphorDim : "#8c8978"
          font.family: "monospace"
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 1
          textFormat: Text.PlainText
        }

        Rectangle {
          id: screen
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 28
          anchors.topMargin: 42
          anchors.bottomMargin: 34
          radius: 34
          color: root.phosphor === "amber" ? "#120d06" : root.phosphor === "green" ? "#061008" : "#0a0f0d"
          border.width: 2
          border.color: "#050604"
          clip: true

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 12
            border.color: Qt.rgba(0, 0, 0, 0.34)
            radius: screen.radius
            z: 20
          }

          Flickable {
            id: transcriptView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: commandRow.top
            anchors.margins: 24
            anchors.bottomMargin: 8
            contentWidth: width
            contentHeight: Math.max(height, transcriptText.height)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: transcriptGlow
              x: 1
              y: 1
              width: transcriptView.width
              text: root.transcript
              color: Qt.rgba(root.phosphorColor.r, root.phosphorColor.g, root.phosphorColor.b, 0.18)
              font.family: "monospace"
              font.pixelSize: 17
              font.letterSpacing: 0.25
              lineHeight: 1.18
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
            }

            Text {
              id: transcriptText
              width: transcriptView.width
              text: root.transcript
              color: root.phosphorColor
              font.family: "monospace"
              font.pixelSize: 17
              font.letterSpacing: 0.25
              lineHeight: 1.18
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
            }
          }

          Row {
            id: commandRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 22
            spacing: 8

            Text {
              text: ">"
              color: root.phosphorColor
              font.family: "monospace"
              font.pixelSize: 18
              font.bold: true
              textFormat: Text.PlainText
            }

            TextInput {
              id: commandInput
              width: parent.width - 28
              color: root.phosphorColor
              selectionColor: root.phosphorDim
              selectedTextColor: "#080a07"
              font.family: "monospace"
              font.pixelSize: 18
              font.letterSpacing: 0.3
              activeFocusOnTab: true
              enabled: frotzProc.running
              clip: true
              onAccepted: root.submitCommand()
              Keys.onUpPressed: function(event) { root.stepHistory(-1); event.accepted = true }
              Keys.onDownPressed: function(event) { root.stepHistory(1); event.accepted = true }

              cursorDelegate: Rectangle {
                width: 9
                color: root.phosphorColor
                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.18; duration: 520 }
                  NumberAnimation { to: 1; duration: 520 }
                }
              }
            }
          }

          Column {
            anchors.fill: parent
            spacing: 3
            opacity: 0.13
            z: 10
            Repeater {
              model: Math.ceil(screen.height / 5)
              Rectangle {
                width: screen.width
                height: 1
                color: "#000000"
              }
            }
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 18
            border.color: Qt.rgba(0, 0, 0, 0.22)
            radius: screen.radius
            z: 19
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: commandInput.forceActiveFocus()
            z: 21
            propagateComposedEvents: true
          }
        }

        Rectangle {
          width: 7
          height: 7
          radius: 4
          anchors.right: parent.right
          anchors.rightMargin: 30
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 16
          color: frotzProc.running ? root.phosphorColor : "#413f37"
          opacity: frotzProc.running ? 0.75 : 0.45
        }
      }
    }
  }
}
