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
  property bool nativeClosePending: false
  property string transcript: ""
  property string statusText: "READY"
  property string storyPath: ""
  property bool startPending: false
  property bool returningToMenu: false
  property string pendingStoryPath: ""
  property string viewMode: "menu"
  property int menuIndex: 0
  property bool crtEffects: true
  property real crtTime: 0
  property string phosphor: "amber"
  property var commandHistory: []
  property int historyIndex: 0

  readonly property var window: windowLoader.item

  readonly property string homePath: Quickshell.env("HOME") || "/tmp"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homePath + "/.local/state"
  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl(".")))
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string runtimePath: pluginRoot + "/runtime/x86_64-linux/dfrotz"
  readonly property string bundledStoryPath: pluginRoot + "/games/zork1.z3"
  readonly property string zork2StoryPath: pluginRoot + "/games/zork2.z3"
  readonly property string zork3StoryPath: pluginRoot + "/games/zork3.z3"
  readonly property string windowStateHelper: pluginRoot + "/bin/window-state"
  readonly property string saveRoot: stateRoot + "/lantern/saves"
  readonly property var bundledGames: [{
    id: "zork1",
    number: "01",
    title: "ZORK I",
    subtitle: "THE GREAT UNDERGROUND EMPIRE  /  INFOCOM, 1980",
    path: bundledStoryPath
  }, {
    id: "zork2",
    number: "02",
    title: "ZORK II",
    subtitle: "THE WIZARD OF FROBOZZ  /  INFOCOM, 1981",
    path: zork2StoryPath
  }, {
    id: "zork3",
    number: "03",
    title: "ZORK III",
    subtitle: "THE DUNGEON MASTER  /  INFOCOM, 1982",
    path: zork3StoryPath
  }]
  readonly property string lanternLogo:
    " _        _    _   _ _____ _____ ____  _   _\n" +
    "| |      / \\  | \\ | |_   _| ____|  _ \\| \\ | |\n" +
    "| |     / _ \\ |  \\| | | | |  _| | |_) |  \\| |\n" +
    "| |___ / ___ \\| |\\  | | | | |___|  _ <| |\\  |\n" +
    "|_____/_/   \\_\\_| \\_| |_| |_____|_| \\_\\_| \\_|"
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
    nativeClosePending = false
    opened = true
    if (!windowLoader.active) windowLoader.active = true
    if (!windowStatePrepare.running) windowStatePrepare.running = true

    if (requested !== "" && !frotzProc.running && !startPending) {
      launchStory(requested)
    } else if (frotzProc.running || startPending) {
      viewMode = "game"
    } else {
      viewMode = "menu"
      statusText = "SELECT STORY"
    }
  }

  function storyActivity() {
    return frotzProc.running ? "active" : "idle"
  }

  function returnToMenu() {
    if (viewMode !== "game" || startPending || returningToMenu) return
    returningToMenu = true
    statusText = "EJECTING"
    if (frotzProc.running) frotzProc.running = false
    else finishReturnToMenu()
  }

  function finishReturnToMenu() {
    returningToMenu = false
    storyPath = ""
    pendingStoryPath = ""
    transcript = ""
    commandHistory = []
    historyIndex = 0
    if (window && typeof window.clearCommandInput === "function") window.clearCommandInput()
    viewMode = "menu"
    statusText = "SELECT STORY"
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function focusCurrentView() {
    if (window && typeof window.focusCurrentView === "function") window.focusCurrentView()
  }

  function moveMenuSelection(direction) {
    menuIndex = Model.menuStep(menuIndex, bundledGames.length, direction)
  }

  function activateMenuSelection() {
    if (menuIndex < 0 || menuIndex >= bundledGames.length) return
    launchStory(bundledGames[menuIndex].path)
  }

  function launchStory(path) {
    if (frotzProc.running || startPending) return
    pendingStoryPath = path
    transcript = ""
    commandHistory = []
    historyIndex = 0
    viewMode = "game"
    statusText = "WARMING UP"
    startPending = true
    prepareDir.running = true
  }

  function close() {
    opened = false
    if (nativeClosePending) {
      nativeClosePending = false
      closePending = false
      windowLoader.active = false
      return
    }
    if (!window || !window.visible) {
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
    if (window && typeof window.scrollTranscriptToBottom === "function")
      window.scrollTranscriptToBottom()
  }

  function submitCommand(raw) {
    var command = Model.normalizeCommand(raw)
    if (command === "" || !frotzProc.running) return

    transcript = Model.appendTranscript(transcript, "\n> " + command, 1200)
    var nextHistory = commandHistory.slice(0)
    if (nextHistory.length === 0 || nextHistory[nextHistory.length - 1] !== command)
      nextHistory.push(command)
    if (nextHistory.length > 100) nextHistory = nextHistory.slice(nextHistory.length - 100)
    commandHistory = nextHistory
    historyIndex = commandHistory.length
    if (window && typeof window.clearCommandInput === "function") window.clearCommandInput()
    frotzProc.write(command + "\n")
    Qt.callLater(scrollToBottom)
  }

  function stepHistory(direction) {
    var next = Model.historyStep(commandHistory, historyIndex, direction)
    historyIndex = next.index
    if (window && typeof window.setCommandDraft === "function") window.setCommandDraft(next.value)
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
      Qt.callLater(function() { root.focusCurrentView() })
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
        root.appendOutput("The selected story could not be read. Reinstall Lantern to restore the bundled Zork trilogy, or summon it with another absolute story path.")
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
      root.viewMode = "game"
      root.statusText = "ONLINE"
      Qt.callLater(function() {
        if (root.opened && window && window.visible) root.focusCurrentView()
      })
    }
    onExited: function(exitCode) {
      if (root.returningToMenu) {
        root.finishReturnToMenu()
        return
      }
      root.statusText = exitCode === 0 ? "SESSION ENDED" : "FROTZ UNAVAILABLE"
      if (exitCode !== 0)
        root.appendOutput("Lantern's bundled dfrotz runtime could not be started. This release supports x86-64 glibc Linux systems.")
    }
  }

  Loader {
    id: windowLoader
    active: true

    sourceComponent: Component {
      FloatingWindow {
        id: window
    title: "Lantern — Interactive Fiction Terminal"
    visible: false
    color: "#141512"
    implicitWidth: 1020
    implicitHeight: 765
    minimumSize: Qt.size(1020, 765)
    maximumSize: Qt.size(1020, 765)

    function focusCurrentView() {
      if (root.viewMode === "menu") launcherScreen.forceActiveFocus()
      else commandInput.forceActiveFocus()
    }

    function clearCommandInput() {
      commandInput.text = ""
    }

    function setCommandDraft(value) {
      commandInput.text = String(value || "")
      commandInput.cursorPosition = commandInput.text.length
    }

    function scrollTranscriptToBottom() {
      transcriptView.contentY = Math.max(0, transcriptText.height - transcriptView.height)
    }

    onClosed: {
      if (root.opened && !root.closingFromHost) {
        root.nativeClosePending = true
        root.requestClose()
      }
    }

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

            Item {
              id: gameScreen
              anchors.fill: parent
              visible: root.viewMode === "game"

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
                id: promptText
                text: ">"
                color: root.phosphorColor
                font.family: "monospace"
                font.pixelSize: 18
                font.bold: true
                textFormat: Text.PlainText
              }

              TextInput {
                id: commandInput
                width: Math.max(80, parent.width - promptText.implicitWidth - menuButton.width - parent.spacing * 2)
                color: root.phosphorColor
                selectionColor: root.phosphorDim
                selectedTextColor: "#080a07"
                font.family: "monospace"
                font.pixelSize: 18
                font.letterSpacing: 0.3
                activeFocusOnTab: true
                enabled: frotzProc.running
                clip: true
                onAccepted: root.submitCommand(commandInput.text)
                Keys.onEscapePressed: function(event) { root.requestClose(); event.accepted = true }
                Keys.onUpPressed: function(event) { root.stepHistory(-1); event.accepted = true }
                Keys.onDownPressed: function(event) { root.stepHistory(1); event.accepted = true }
                Keys.onPressed: function(event) {
                  if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_M) {
                    root.returnToMenu()
                    event.accepted = true
                  }
                }

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

              Rectangle {
                id: menuButton
                width: 92
                height: 25
                color: "transparent"
                border.width: 1
                border.color: root.phosphorDim
                opacity: frotzProc.running && !root.returningToMenu ? 0.88 : 0.35

                Text {
                  anchors.centerIn: parent
                  text: "MENU  ^M"
                  color: root.phosphorColor
                  font.family: "monospace"
                  font.pixelSize: 11
                  font.bold: true
                  font.letterSpacing: 0.7
                  textFormat: Text.PlainText
                }

                HoverHandler {
                  enabled: frotzProc.running && !root.returningToMenu
                  cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                  enabled: frotzProc.running && !root.returningToMenu
                  acceptedButtons: Qt.LeftButton
                  onTapped: root.returnToMenu()
                }
              }
            }
          }

            FocusScope {
              id: launcherScreen
              anchors.fill: parent
              visible: root.viewMode === "menu"
              focus: visible

              Keys.onUpPressed: function(event) {
                root.moveMenuSelection(-1)
                event.accepted = true
              }
              Keys.onDownPressed: function(event) {
                root.moveMenuSelection(1)
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) {
                root.activateMenuSelection()
                event.accepted = true
              }
              Keys.onEnterPressed: function(event) {
                root.activateMenuSelection()
                event.accepted = true
              }
              Keys.onEscapePressed: function(event) {
                root.requestClose()
                event.accepted = true
              }
              Keys.onPressed: function(event) {
                if (event.key < Qt.Key_1 || event.key > Qt.Key_9) return
                var selected = event.key - Qt.Key_1
                if (selected >= root.bundledGames.length) return
                root.menuIndex = selected
                root.activateMenuSelection()
                event.accepted = true
              }

              Column {
                anchors.centerIn: parent
                width: parent.width - 150
                spacing: 18

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.lanternLogo
                  color: root.phosphorColor
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
                  text: "Z-MACHINE STORY TERMINAL  //  SELECT A CARTRIDGE"
                  color: root.phosphorDim
                  font.family: "monospace"
                  font.pixelSize: 12
                  font.bold: true
                  font.letterSpacing: 1.4
                  textFormat: Text.PlainText
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: root.phosphorDim
                  opacity: 0.55
                }

                Column {
                  width: parent.width
                  spacing: 8

                  Repeater {
                    model: root.bundledGames

                    delegate: Rectangle {
                      required property int index
                      required property var modelData
                      readonly property bool selected: index === root.menuIndex
                      width: parent.width
                      height: 76
                      color: selected ? Qt.rgba(root.phosphorColor.r, root.phosphorColor.g, root.phosphorColor.b, 0.09) : "transparent"
                      border.width: 1
                      border.color: selected ? root.phosphorDim : Qt.rgba(root.phosphorColor.r, root.phosphorColor.g, root.phosphorColor.b, 0.16)

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.selected ? ">" : " "
                        color: root.phosphorColor
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
                        text: "[ " + parent.modelData.number + " ]  " + parent.modelData.title
                        color: root.phosphorColor
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
                        text: parent.modelData.subtitle
                        color: root.phosphorDim
                        font.family: "monospace"
                        font.pixelSize: 12
                        font.letterSpacing: 0.6
                        textFormat: Text.PlainText
                      }

                      TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                          root.menuIndex = parent.index
                          root.activateMenuSelection()
                        }
                      }
                    }
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "UP/DOWN  SELECT    ENTER  BOOT    1-3  QUICK START"
                  color: root.phosphorDim
                  font.family: "monospace"
                  font.pixelSize: 11
                  font.bold: true
                  font.letterSpacing: 0.8
                  textFormat: Text.PlainText
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
            onTapped: root.focusCurrentView()
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
  }
}
