import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
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
  property real crtRasterOpacity: 1.0
  property real crtRasterGain: 2.25
  property real crtTime: 0
  property real channelGlitch: 0.0
  property real channelGlitchSeed: 0.0
  property string phosphor: "amber"
  property color themePhosphorColor: "#d8e7df"
  property color themeScreenColor: "#0a0f0d"
  property int cursorFadeMs: 520
  property int historyLimit: 100
  property int transcriptLineLimit: 1200
  property real dialStep: 0.05
  property real windowScale: 1.0
  property string bundledConfigText: ""
  property string userConfigText: ""
  property string themeColorsText: ""
  property var commandHistory: []
  property int historyIndex: 0
  property string fileActionMode: ""
  property bool fileActionCommandRecorded: false
  property string saveDraft: ""
  property bool saveOverwritePending: false
  property int loadSaveIndex: 0
  property string fileActionMessage: ""

  readonly property var window: windowLoader.item
  readonly property int baseWindowWidth: 1020
  readonly property int baseWindowHeight: 765
  readonly property string windowScaleLabel: windowScale === 1.0 ? "1" : windowScale.toFixed(2).replace(/0$/, "")

  readonly property string homePath: Quickshell.env("HOME") || "/tmp"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homePath + "/.local/state"
  readonly property string configRoot: Quickshell.env("XDG_CONFIG_HOME") || homePath + "/.config"
  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl(".")))
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string bundledConfigPath: pluginRoot + "/lantern.toml"
  readonly property string userConfigPath: configRoot + "/lantern/lantern.toml"
  readonly property string themeColorsPath: homePath + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string runtimePath: pluginRoot + "/runtime/x86_64-linux/dfrotz"
  readonly property string bundledStoryPath: pluginRoot + "/games/zork1.z3"
  readonly property string zork2StoryPath: pluginRoot + "/games/zork2.z3"
  readonly property string zork3StoryPath: pluginRoot + "/games/zork3.z3"
  readonly property string windowStateHelper: pluginRoot + "/bin/window-state"
  readonly property string boundedFileReader: pluginRoot + "/bin/read-bounded-file"
  readonly property int boundedFileBytes: 65536
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
    : phosphor === "theme" ? themePhosphorColor
    : phosphor === "white" ? "#d8e7df" : "#ffb84d"
  readonly property color screenColor: phosphor === "green" ? "#061008"
    : phosphor === "theme" ? themeScreenColor
    : phosphor === "white" ? "#0a0f0d" : "#120d06"
  readonly property color phosphorDim: Qt.rgba(phosphorColor.r, phosphorColor.g, phosphorColor.b, 0.48)
  readonly property string phosphorLabel: phosphor === "green" ? "GRN" : phosphor === "theme" ? "THM" : "AMB"

  function loadThemePalette(raw) {
    var values = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*(foreground|fg|color7|background|bg|color0)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) values[match[1]] = match[2]
    }
    themePhosphorColor = values.foreground || values.fg || values.color7 || "#d8e7df"
    themeScreenColor = values.background || values.bg || values.color0 || "#0a0f0d"
  }

  function triggerChannelGlitch() {
    if (!crtEffects) {
      channelGlitch = 0.0
      return
    }
    channelGlitchSeed = (channelGlitchSeed + 0.371) % 1.0
    channelSwitchGlitch.restart()
  }

  function cyclePhosphor() {
    phosphor = phosphor === "amber" ? "green" : phosphor === "green" ? "theme" : "amber"
    triggerChannelGlitch()
  }

  function cycleWindowScale() {
    windowScale = windowScale === 1.0 ? 1.25 : windowScale === 1.25 ? 1.5 : 1.0
    windowStateCheckpointTimer.restart()
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function checkpointWindowPosition() {
    if (window && window.visible) windowStateCheckpointTimer.restart()
  }

  function configNumber(value, fallback, minimum, maximum) {
    var number = Number(value)
    if (!isFinite(number)) return fallback
    return Math.max(minimum, Math.min(maximum, number))
  }

  function applyUserConfig(raw) {
    var config = Model.parseLanternConfig(raw)
    var display = config.display || {}
    var terminal = config.terminal || {}
    var launcher = config.launcher || {}
    var controls = config.controls || {}

    if (display.phosphor === "amber" || display.phosphor === "green" || display.phosphor === "theme" || display.phosphor === "white")
      phosphor = display.phosphor
    if (display.effects === true || display.effects === false) crtEffects = display.effects
    crtRasterOpacity = configNumber(display.raster_opacity, crtRasterOpacity, 0.0, 1.0)
    crtRasterGain = configNumber(display.raster_gain, crtRasterGain, 0.25, 4.0)
    cursorFadeMs = Math.round(configNumber(display.cursor_fade_ms, cursorFadeMs, 150, 2000))
    historyLimit = Math.round(configNumber(terminal.history_limit, historyLimit, 10, 500))
    transcriptLineLimit = Math.round(configNumber(terminal.transcript_line_limit, transcriptLineLimit, 200, 5000))
    dialStep = configNumber(controls.dial_step, dialStep, 0.01, 0.25)
    menuIndex = Math.round(configNumber(launcher.default_cartridge, menuIndex + 1, 1, bundledGames.length)) - 1
  }

  function applyConfigLayers() {
    if (bundledConfigText !== "") applyUserConfig(bundledConfigText)
    if (userConfigText !== "") applyUserConfig(userConfigText)
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) {}

    if (payload.phosphor === "green" || payload.phosphor === "theme" || payload.phosphor === "white" || payload.phosphor === "amber")
      phosphor = payload.phosphor
    if (payload.effects === true || payload.effects === false)
      crtEffects = payload.effects

    var requested = Model.bundledStoryPath(payload.story || "", [
      bundledStoryPath,
      zork2StoryPath,
      zork3StoryPath
    ])

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
    fileActionMode = ""
    fileActionCommandRecorded = false
    saveOverwritePending = false
    fileActionMessage = ""
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
    fileActionMode = ""
    fileActionCommandRecorded = false
    saveOverwritePending = false
    fileActionMessage = ""
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

  function setCrtRasterOpacity(value) {
    crtRasterOpacity = Math.max(0.0, Math.min(1.0, Number(value)))
  }

  function adjustCrtRasterOpacity(delta) {
    setCrtRasterOpacity(crtRasterOpacity + Number(delta))
  }

  function appendOutput(raw) {
    var cleaned = Model.cleanOutput(raw)
    if (cleaned === "") return
    transcript = Model.appendTranscript(transcript, cleaned, transcriptLineLimit)
    Qt.callLater(scrollToBottom)
  }

  function scrollToBottom() {
    if (window && typeof window.scrollTranscriptToBottom === "function")
      window.scrollTranscriptToBottom()
  }

  function rememberCommand(command) {
    transcript = Model.appendTranscript(transcript, "\n> " + command, transcriptLineLimit)
    var nextHistory = commandHistory.slice(0)
    if (nextHistory.length === 0 || nextHistory[nextHistory.length - 1] !== command)
      nextHistory.push(command)
    if (nextHistory.length > historyLimit) nextHistory = nextHistory.slice(nextHistory.length - historyLimit)
    commandHistory = nextHistory
    historyIndex = commandHistory.length
    if (window && typeof window.clearCommandInput === "function") window.clearCommandInput()
    Qt.callLater(scrollToBottom)
  }

  function currentStoryId() {
    for (var i = 0; i < bundledGames.length; i++)
      if (bundledGames[i].path === storyPath) return bundledGames[i].id
    return "story"
  }

  function defaultSaveName() {
    return currentStoryId() + "-" + Qt.formatDateTime(new Date(), "MMdd-HHmmss")
  }

  function matchingSaveFileName(raw) {
    var stem = Model.normalizeSaveName(raw)
    if (stem === "") return ""
    var target = (stem + ".qzl").toLowerCase()
    for (var i = 0; i < saveFiles.count; i++) {
      var fileName = String(saveFiles.get(i, "fileName") || "")
      if (fileName.toLowerCase() === target) return fileName
    }
    return ""
  }

  function closeFileAction(cancelled) {
    if (cancelled && fileActionCommandRecorded)
      transcript = Model.appendTranscript(transcript, "[FILE OPERATION CANCELLED]", transcriptLineLimit)
    fileActionMode = ""
    fileActionCommandRecorded = false
    saveOverwritePending = false
    fileActionMessage = ""
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function beginSave(recorded, requestedName) {
    if (!frotzProc.running) return
    fileActionMode = "save"
    fileActionCommandRecorded = recorded === true
    saveOverwritePending = false
    fileActionMessage = ""
    saveDraft = Model.normalizeSaveName(requestedName) || defaultSaveName()
    Qt.callLater(function() { root.focusCurrentView() })
    if (requestedName) completeSave(saveDraft, false)
  }

  function completeSave(raw, overwriteConfirmed) {
    if (fileActionMode !== "save") return
    var stem = Model.normalizeSaveName(raw)
    if (stem === "") {
      fileActionMessage = "ENTER A NAME FOR THIS SAVE"
      return
    }

    var existing = matchingSaveFileName(stem)
    if (existing !== "" && !overwriteConfirmed) {
      saveDraft = existing.replace(/\.qzl$/i, "")
      saveOverwritePending = true
      fileActionMessage = "SAVE EXISTS — ENTER TO OVERWRITE"
      Qt.callLater(function() { root.focusCurrentView() })
      return
    }

    if (!fileActionCommandRecorded) rememberCommand("SAVE")
    var fileName = existing !== "" ? existing : stem + ".qzl"
    transcript = Model.appendTranscript(transcript, "[SAVING  " + fileName + "]", transcriptLineLimit)
    closeFileAction(false)
    frotzProc.write("save\n" + stem + "\n" + (existing !== "" ? "y\n" : ""))
  }

  function beginLoad(recorded, requestedName) {
    if (!frotzProc.running) return
    fileActionMode = "load"
    fileActionCommandRecorded = recorded === true
    fileActionMessage = ""
    loadSaveIndex = Math.max(0, Math.min(loadSaveIndex, saveFiles.count - 1))

    if (requestedName) {
      var existing = matchingSaveFileName(requestedName)
      if (existing !== "") {
        completeLoad(existing)
        return
      }
      fileActionMessage = "SAVE NOT FOUND — SELECT AN AVAILABLE FILE"
    } else if (saveFiles.count === 0) {
      fileActionMessage = "NO SAVED GAMES YET"
    }
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function moveLoadSelection(direction) {
    if (saveFiles.count === 0) return
    loadSaveIndex = Model.menuStep(loadSaveIndex, saveFiles.count, direction)
  }

  function completeSelectedLoad() {
    if (saveFiles.count === 0) return
    completeLoad(String(saveFiles.get(loadSaveIndex, "fileName") || ""))
  }

  function completeLoad(raw) {
    if (fileActionMode !== "load") return
    var existing = matchingSaveFileName(String(raw || "").replace(/\.qzl$/i, ""))
    if (existing === "") {
      fileActionMessage = "SAVE FILE IS NO LONGER AVAILABLE"
      return
    }
    if (!fileActionCommandRecorded) rememberCommand("RESTORE")
    transcript = Model.appendTranscript(transcript, "[LOADING  " + existing + "]", transcriptLineLimit)
    closeFileAction(false)
    frotzProc.write("restore\n" + existing + "\n")
  }

  function submitCommand(raw) {
    var command = Model.normalizeCommand(raw)
    if (command === "" || !frotzProc.running || fileActionMode !== "") return

    var fileCommand = command.match(/^(save|restore|load)(?:\s+(.+))?$/i)
    if (fileCommand) {
      rememberCommand(command)
      if (fileCommand[1].toLowerCase() === "save") beginSave(true, fileCommand[2] || "")
      else beginLoad(true, fileCommand[2] || "")
      return
    }

    rememberCommand(command)
    frotzProc.write(command + "\n")
  }

  function stepHistory(direction) {
    var next = Model.historyStep(commandHistory, historyIndex, direction)
    historyIndex = next.index
    if (window && typeof window.setCommandDraft === "function") window.setCommandDraft(next.value)
  }

  FolderListModel {
    id: saveFiles
    folder: "file://" + root.saveRoot
    nameFilters: ["*.qzl"]
    sortField: FolderListModel.Time
    sortReversed: false
    showFiles: true
    showDirs: false
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
  }

  Process {
    id: bundledConfigReader
    command: [root.boundedFileReader, root.bundledConfigPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.boundedFileText(text, root.boundedFileBytes)
        if (next === root.bundledConfigText) return
        root.bundledConfigText = next
        root.applyConfigLayers()
      }
    }
  }

  Process {
    id: userConfigReader
    command: [root.boundedFileReader, root.userConfigPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.boundedFileText(text, root.boundedFileBytes)
        if (next === root.userConfigText) return
        root.userConfigText = next
        root.applyConfigLayers()
      }
    }
  }

  Process {
    id: themePaletteReader
    command: [root.boundedFileReader, root.themeColorsPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.boundedFileText(text, root.boundedFileBytes)
        if (next === root.themeColorsText) return
        root.themeColorsText = next
        root.loadThemePalette(next)
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      if (!bundledConfigReader.running) bundledConfigReader.running = true
      if (!userConfigReader.running) userConfigReader.running = true
      if (!themePaletteReader.running) themePaletteReader.running = true
    }
  }

  Connections {
    target: Color
    function onForegroundChanged() {
      if (!themePaletteReader.running) themePaletteReader.running = true
    }
    function onShellValuesChanged() {
      if (!themePaletteReader.running) themePaletteReader.running = true
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: root.opened && root.crtEffects
    onTriggered: root.crtTime += 0.05
  }

  SequentialAnimation {
    id: channelSwitchGlitch

    PropertyAction { target: root; property: "channelGlitch"; value: 0.0 }
    NumberAnimation {
      target: root
      property: "channelGlitch"
      from: 0.0
      to: 1.0
      duration: 28
      easing.type: Easing.OutQuad
    }
    PauseAnimation { duration: 96 }
    NumberAnimation {
      target: root
      property: "channelGlitch"
      from: 1.0
      to: 0.48
      duration: 72
      easing.type: Easing.InQuad
    }
    NumberAnimation {
      target: root
      property: "channelGlitch"
      from: 0.48
      to: 0.96
      duration: 34
      easing.type: Easing.OutQuad
    }
    PauseAnimation { duration: 54 }
    NumberAnimation {
      target: root
      property: "channelGlitch"
      from: 0.96
      to: 0.0
      duration: 340
      easing.type: Easing.OutExpo
    }
  }

  Timer {
    id: clearWindowRuleTimer
    interval: 250
    repeat: false
    onTriggered: if (!windowStateClear.running) windowStateClear.running = true
  }

  Timer {
    id: windowStateCheckpointTimer
    interval: 150
    repeat: false
    onTriggered: if (window && window.visible && !windowStateCheckpoint.running) windowStateCheckpoint.running = true
  }

  Process {
    id: windowStateCheckpoint
    command: [root.windowStateHelper, "save"]
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
      storyCheck.command = ["test", "-f", root.pendingStoryPath]
      storyCheck.running = true
    }
  }

  Process {
    id: storyCheck
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.startPending = false
        root.statusText = "NO STORY"
        root.appendOutput("The selected bundled story is not a regular file. Reinstall Lantern to restore the bundled Zork trilogy.")
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
    implicitWidth: Math.round(root.baseWindowWidth * root.windowScale)
    implicitHeight: Math.round(root.baseWindowHeight * root.windowScale)
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    function focusCurrentView() {
      if (root.viewMode === "menu") launcherScreen.forceActiveFocus()
      else if (root.fileActionMode !== "") saveLoadOverlay.focusCurrent()
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
      width: root.baseWindowWidth
      height: root.baseWindowHeight
      transformOrigin: Item.TopLeft
      scale: root.windowScale
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
            onActiveChanged: {
              if (active) window.startSystemMove()
              else root.checkpointWindowPosition()
            }
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
          anchors.bottomMargin: 70
          radius: root.crtEffects ? 0 : 58
          color: root.screenColor
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
                width: Math.max(80, parent.width - promptText.implicitWidth - actionButtons.width - parent.spacing * 2)
                color: root.phosphorColor
                selectionColor: root.phosphorDim
                selectedTextColor: "#080a07"
                font.family: "monospace"
                font.pixelSize: 18
                font.letterSpacing: 0.3
                activeFocusOnTab: true
                enabled: frotzProc.running && root.fileActionMode === ""
                clip: true
                onAccepted: root.submitCommand(commandInput.text)
                Keys.onEscapePressed: function(event) { root.requestClose(); event.accepted = true }
                Keys.onUpPressed: function(event) { root.stepHistory(-1); event.accepted = true }
                Keys.onDownPressed: function(event) { root.stepHistory(1); event.accepted = true }
                Keys.onPressed: function(event) {
                  if (!(event.modifiers & Qt.ControlModifier)) return
                  if (event.key === Qt.Key_S) root.beginSave(false, "")
                  else if (event.key === Qt.Key_L) root.beginLoad(false, "")
                  else if (event.key === Qt.Key_M) root.returnToMenu()
                  else return
                  event.accepted = true
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
                    NumberAnimation { from: 1.0; to: 0.18; duration: root.cursorFadeMs }
                    NumberAnimation { from: 0.18; to: 1.0; duration: root.cursorFadeMs }
                  }
                }
              }

              Row {
                id: actionButtons
                spacing: 6

                Repeater {
                  model: [{ label: "SAVE  ^S", action: "save" },
                    { label: "LOAD  ^L", action: "load" },
                    { label: "MENU  ^M", action: "menu" }]

                  delegate: Rectangle {
                    required property var modelData
                    width: 74
                    height: 25
                    color: "transparent"
                    border.width: 1
                    border.color: root.phosphorDim
                    opacity: frotzProc.running && !root.returningToMenu && root.fileActionMode === "" ? 0.88 : 0.35

                    Text {
                      anchors.centerIn: parent
                      text: parent.modelData.label
                      color: root.phosphorColor
                      font.family: "monospace"
                      font.pixelSize: 9
                      font.bold: true
                      font.letterSpacing: 0.45
                      textFormat: Text.PlainText
                    }

                    HoverHandler {
                      enabled: frotzProc.running && !root.returningToMenu && root.fileActionMode === ""
                      cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                      enabled: frotzProc.running && !root.returningToMenu && root.fileActionMode === ""
                      acceptedButtons: Qt.LeftButton
                      onTapped: {
                        if (parent.modelData.action === "save") root.beginSave(false, "")
                        else if (parent.modelData.action === "load") root.beginLoad(false, "")
                        else root.returnToMenu()
                      }
                    }
                  }
                }
              }
            }

            SaveLoadOverlay {
              id: saveLoadOverlay
              anchors.fill: parent
              visible: root.fileActionMode !== ""
              z: 40
              controller: root
              saveModel: saveFiles
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
            textureSize: Qt.size(Math.max(1, Math.round(screen.width * root.windowScale)), Math.max(1, Math.round(screen.height * root.windowScale)))
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
            property real rasterOpacity: root.crtRasterOpacity
            property real rasterGain: root.crtRasterGain
            property real channelGlitch: root.channelGlitch
            property real channelGlitchSeed: root.channelGlitchSeed
            fragmentShader: Qt.resolvedUrl("shaders/crt.frag.qsb")
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.focusCurrentView()
          }
        }

        Rectangle {
          id: controlShelf
          width: 580
          height: 54
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 14
          z: 31
          radius: 2
          color: "#0d0e0c"
          border.width: 2
          border.color: "#080907"

          Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 1
            color: "#191a16"
            border.width: 1
            border.color: "#424238"
          }

          Repeater {
            model: [{ x: 9, y: 9 }, { x: 565, y: 9 }, { x: 9, y: 39 }, { x: 565, y: 39 }]

            delegate: Rectangle {
              required property var modelData
              x: modelData.x
              y: modelData.y
              width: 6
              height: 6
              radius: 3
              color: "#0a0b09"
              border.width: 1
              border.color: "#4a4a3f"

              Rectangle {
                width: 4
                height: 1
                anchors.centerIn: parent
                rotation: 28
                color: "#555548"
              }
            }
          }
        }

        Rectangle {
          width: 206
          height: 30
          anchors.left: parent.left
          anchors.leftMargin: 28
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 18
          z: 32
          radius: 1
          color: "#1b1c18"
          border.width: 1
          border.color: "#393930"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "LANTERN   MODEL ZM-80"
            color: "#8f8c7c"
            font.family: "monospace"
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1.0
            textFormat: Text.PlainText
          }
        }

        Item {
          id: crtDial
          property real dragStart: 1.0
          readonly property real dialAngle: -135 + root.crtRasterOpacity * 270
          width: 146
          height: 46
          anchors.right: parent.right
          anchors.rightMargin: 30
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 18
          z: 32

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              text: "BRIGHT  " + Math.round(root.crtRasterOpacity * 100)
              color: "#aaa694"
              font.family: "monospace"
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.8
              textFormat: Text.PlainText
            }

            Text {
              text: "INTENSITY"
              color: "#5f5e53"
              font.family: "monospace"
              font.pixelSize: 7
              font.letterSpacing: 0.7
              textFormat: Text.PlainText
            }
          }

          Item {
            id: dialFace
            width: 40
            height: 40
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: 7

              delegate: Rectangle {
                required property int index
                readonly property real tickAngle: -135 + index * 45
                readonly property real radians: tickAngle * Math.PI / 180
                width: 1
                height: index === 0 || index === 6 ? 5 : 4
                radius: 1
                x: dialFace.width / 2 + Math.sin(radians) * 18 - width / 2
                y: dialFace.height / 2 - Math.cos(radians) * 18 - height / 2
                rotation: tickAngle
                color: "#666357"
                opacity: 0.8
              }
            }

            Rectangle {
              width: 28
              height: 28
              radius: 14
              anchors.centerIn: parent
              color: "#24251f"
              border.width: 1
              border.color: "#090a08"

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 12
                color: "#303128"
                border.width: 1
                border.color: "#48483d"
              }

              Rectangle {
                width: 13
                height: 3
                radius: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 3
                color: "#565648"
                opacity: 0.45
              }

              Item {
                anchors.fill: parent
                rotation: crtDial.dialAngle

                Rectangle {
                  width: 2
                  height: 8
                  radius: 1
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top
                  anchors.topMargin: 2
                  color: root.phosphorDim
                }
              }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.adjustCrtRasterOpacity(event.angleDelta.y > 0 ? root.dialStep : -root.dialStep)
                event.accepted = true
              }
            }

            DragHandler {
              target: null
              acceptedButtons: Qt.LeftButton
              onActiveChanged: if (active) crtDial.dragStart = root.crtRasterOpacity
              onTranslationChanged: if (active)
                root.setCrtRasterOpacity(crtDial.dragStart - translation.y / 90 + translation.x / 180)
            }
          }
        }

        Item {
          id: phosphorSelector
          width: 156
          height: 46
          anchors.right: crtDial.left
          anchors.rightMargin: 14
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 18
          z: 32

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              text: "COLOR  " + root.phosphorLabel
              color: "#aaa694"
              font.family: "monospace"
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.8
              textFormat: Text.PlainText
            }

            Text {
              text: "PHOSPHOR"
              color: "#5f5e53"
              font.family: "monospace"
              font.pixelSize: 7
              font.letterSpacing: 0.7
              textFormat: Text.PlainText
            }
          }

          Item {
            id: rgbButton
            width: 34
            height: 26
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: 32
              height: 23
              radius: 3
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 3
              color: "#0e0f0d"
              border.width: 1
              border.color: "#070806"
            }

            Rectangle {
              width: 28
              height: 20
              radius: 3
              anchors.horizontalCenter: parent.horizontalCenter
              y: rgbTap.pressed ? 4 : 3
              color: rgbTap.pressed ? "#292a23" : "#37382f"
              border.width: 1
              border.color: rgbTap.pressed ? "#505044" : "#5f5f51"

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                height: 2
                radius: 1
                color: "#777768"
                opacity: rgbTap.pressed ? 0.18 : 0.38
              }

              Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                spacing: 1

                Repeater {
                  model: [{ letter: "R", color: "#c9685f" },
                    { letter: "G", color: "#76a96f" },
                    { letter: "B", color: "#698fb6" }]

                  delegate: Text {
                    required property var modelData
                    text: modelData.letter
                    color: modelData.color
                    font.family: "monospace"
                    font.pixelSize: 7
                    font.bold: true
                    textFormat: Text.PlainText
                  }
                }
              }
            }

            Rectangle {
              width: 10
              height: 2
              radius: 1
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              color: root.phosphorColor
              opacity: 0.72
            }

            HoverHandler {
              id: rgbHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              id: rgbTap
              acceptedButtons: Qt.LeftButton
              onTapped: root.cyclePhosphor()
            }

            ToolTip.visible: rgbHover.hovered
            ToolTip.text: "CRT color: " + (root.phosphor === "theme" ? "Omarchy theme" : root.phosphor)
          }
        }

        Item {
          id: scaleSelector
          width: 130
          height: 46
          anchors.right: phosphorSelector.left
          anchors.rightMargin: 14
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 18
          z: 32

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              text: "SCALE"
              color: "#aaa694"
              font.family: "monospace"
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.8
              textFormat: Text.PlainText
            }

            Text {
              text: "DISPLAY"
              color: "#5f5e53"
              font.family: "monospace"
              font.pixelSize: 7
              font.letterSpacing: 0.7
              textFormat: Text.PlainText
            }
          }

          Item {
            width: 34
            height: 26
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: 32
              height: 23
              radius: 3
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 3
              color: "#0e0f0d"
              border.width: 1
              border.color: "#070806"
            }

            Rectangle {
              width: 28
              height: 20
              radius: 3
              anchors.horizontalCenter: parent.horizontalCenter
              y: scaleTap.pressed ? 4 : 3
              color: scaleTap.pressed ? "#292a23" : "#37382f"
              border.width: 1
              border.color: scaleTap.pressed ? "#505044" : "#5f5f51"

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                height: 2
                radius: 1
                color: "#777768"
                opacity: scaleTap.pressed ? 0.18 : 0.38
              }

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: root.windowScaleLabel
                color: root.phosphorColor
                font.family: "monospace"
                font.pixelSize: 7
                font.bold: true
                font.letterSpacing: 0.2
                textFormat: Text.PlainText
              }
            }

            Rectangle {
              width: 10
              height: 2
              radius: 1
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              color: root.phosphorColor
              opacity: 0.72
            }

            HoverHandler {
              id: scaleHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              id: scaleTap
              acceptedButtons: Qt.LeftButton
              onTapped: root.cycleWindowScale()
            }

            ToolTip.visible: scaleHover.hovered
            ToolTip.text: "Window scale: " + root.windowScaleLabel + "× · click to cycle"
          }
        }

        Item {
          width: 76
          height: 30
          anchors.right: scaleSelector.left
          anchors.rightMargin: 12
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 26
          z: 32

          Rectangle {
            width: 10
            height: 10
            radius: 5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: frotzProc.running ? root.phosphorColor : "#413f37"
            border.width: 1
            border.color: frotzProc.running ? root.phosphorDim : "#24251f"
            opacity: frotzProc.running ? 0.82 : 0.55

            Rectangle {
              width: 3
              height: 3
              radius: 2
              anchors.left: parent.left
              anchors.leftMargin: 2
              anchors.top: parent.top
              anchors.topMargin: 2
              color: "#ffffff"
              opacity: frotzProc.running ? 0.55 : 0.12
            }
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              text: frotzProc.running ? "SIGNAL" : "STANDBY"
              color: frotzProc.running ? "#aaa694" : "#6c6a5e"
              font.family: "monospace"
              font.pixelSize: 8
              font.bold: true
              font.letterSpacing: 0.7
              textFormat: Text.PlainText
            }

            Text {
              text: frotzProc.running ? "LOCKED" : "READY"
              color: "#56554b"
              font.family: "monospace"
              font.pixelSize: 7
              font.letterSpacing: 0.6
              textFormat: Text.PlainText
            }
          }
        }
      }
    }
      }
    }
  }
}
