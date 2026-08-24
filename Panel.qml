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
  property bool closePending: false
  property string transcript: ""
  property string statusText: "READY"
  property string storyPath: ""
  property bool startPending: false
  property string pendingStoryPath: ""
  property bool crtEffects: true
  property real crtTime: 0
  property string phosphor: "amber"
  property var commandHistory: []
  property int historyIndex: 0

  readonly property string homePath: Quickshell.env("HOME") || "/tmp"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homePath + "/.local/state"
  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl(".")))
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string runtimePath: pluginRoot + "/runtime/x86_64-linux/dfrotz"
  readonly property string bundledStoryPath: pluginRoot + "/games/zork1.z3"
  readonly property string windowStateHelper: pluginRoot + "/bin/window-state"
  readonly property string saveRoot: stateRoot + "/lantern/saves"
  readonly property color phosphorColor: phosphor === "green" ? "#78ff83"
    : phosphor === "white" ? "#d8e7df" : "#ffb84d"
  readonly property color phosphorDim: Qt.rgba(phosphorColor.r, phosphorColor.g, phosphorColor.b, 0.48)

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) {}

    if (payload.phosphor === "green" || payload.phosphor === "white" || payload.phosphor === "amber")
      phosphor = payload.phosphor
    if (payload.effects === true || payload.effects === false)
      crtEffects = payload.effects

    var requested = Model.safeStoryPath(payload.story || "")

    closePending = false
    opened = true
    if (!windowStatePrepare.running) windowStatePrepare.running = true

    if (!frotzProc.running && !startPending) {
      pendingStoryPath = requested !== "" ? requested : bundledStoryPath
      startPending = true
      prepareDir.running = true
    }
  }

  function close() {
    opened = false
    if (!window.visible) {
      closePending = false
      return
    }

    closePending = true
    if (!windowStateSave.running) windowStateSave.running = true
  }

  function finishClose() {
    if (opened || !closePending) return
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    closePending = false
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

  Timer {
    interval: 50
    repeat: true
    running: root.opened && root.crtEffects
    onTriggered: root.crtTime += 0.05
  }

  Timer {
    id: clearWindowRuleTimer
    interval: 250
    repeat: false
    onTriggered: if (!windowStateClear.running) windowStateClear.running = true
  }

  Process {
    id: windowStateSave
    command: [root.windowStateHelper, "save"]
    onExited: root.finishClose()
  }

  Process {
    id: windowStatePrepare
    command: [root.windowStateHelper, "prepare"]
    onExited: {
      if (!root.opened) {
        if (!windowStateClear.running) windowStateClear.running = true
        return
      }
      window.visible = true
      clearWindowRuleTimer.restart()
      Qt.callLater(function() { commandInput.forceActiveFocus() })
    }
  }

  Process {
    id: windowStateClear
    command: [root.windowStateHelper, "clear"]
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
    onStarted: {
      root.statusText = "ONLINE"
      Qt.callLater(function() {
        if (root.opened && window.visible) commandInput.forceActiveFocus()
      })
    }
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
    color: "#141512"
    implicitWidth: 1020
    implicitHeight: 765
    minimumSize: Qt.size(1020, 765)
    maximumSize: Qt.size(1020, 765)
    Keys.onEscapePressed: root.requestClose()

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    Rectangle {
      id: terminalShell
      anchors.fill: parent
      color: "#141512"

      Rectangle {
        id: bezel
        anchors.fill: parent
        anchors.margins: 18
        z: 1
        radius: 22
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

        Item {
          id: dragHandle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 42
          z: 30

          HoverHandler { cursorShape: Qt.SizeAllCursor }

          DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) window.startSystemMove()
          }
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
          radius: root.crtEffects ? 0 : 58
          color: root.phosphor === "amber" ? "#120d06" : root.phosphor === "green" ? "#061008" : "#0a0f0d"
          border.width: root.crtEffects ? 0 : 2
          border.color: "#050604"
          clip: true

          Item {
            id: crtContent
            anchors.fill: parent

            Rectangle {
              anchors.fill: parent
              color: screen.color
            }

            Flickable {
              id: transcriptView
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: commandRow.top
              anchors.leftMargin: 52
              anchors.rightMargin: 52
              anchors.topMargin: 40
              anchors.bottomMargin: 10
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
                wrapMode: Text.NoWrap
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
                wrapMode: Text.NoWrap
                textFormat: Text.PlainText
              }
            }

            Row {
              id: commandRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: 52
              anchors.rightMargin: 52
              anchors.bottomMargin: 36
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
                  id: blockCursor
                  property real blinkOpacity: 1.0
                  width: 9
                  color: root.phosphorColor
                  opacity: root.crtEffects ? blinkOpacity : 1.0
                  SequentialAnimation on blinkOpacity {
                    running: root.crtEffects
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.18; duration: 520 }
                    NumberAnimation { from: 0.18; to: 1.0; duration: 520 }
                  }
                }
              }
            }
          }

          ShaderEffectSource {
            id: crtSource
            anchors.fill: parent
            visible: false
            sourceItem: crtContent
            hideSource: root.crtEffects
            live: root.crtEffects
            textureSize: Qt.size(Math.max(1, Math.round(screen.width)), Math.max(1, Math.round(screen.height)))
          }

          ShaderEffect {
            id: crtShader
            anchors.fill: parent
            z: 10
            visible: root.crtEffects
            blending: true
            property variant source: crtSource
            property size sourceSize: Qt.size(Math.max(1, crtSource.textureSize.width), Math.max(1, crtSource.textureSize.height))
            property real time: root.crtTime
            property real effectStrength: root.crtEffects ? 1.0 : 0.0
            fragmentShader: Qt.resolvedUrl("shaders/crt.frag.qsb")
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: commandInput.forceActiveFocus()
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
