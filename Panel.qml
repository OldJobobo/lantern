import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Automap.js" as Automap
import "AutomapSession.js" as AutomapSession

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
  property var pendingCartridge: null
  property var currentCartridge: null
  property string viewMode: "menu"
  property string launcherStage: "engines"
  property int engineIndex: 0
  property int menuIndex: 0
  property string importSourcePath: ""
  property string importEngineId: ""
  property string importedFileName: ""
  property string importMessage: ""
  property bool importPending: false
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
  property bool reduceMotion: false
  property bool audioMuted: false
  property real paperVolume: 0.18
  property int mapSessionEpoch: 0
  property string mapFingerprint: ""
  property var mapState: Automap.createEmptyState({ engine: "", sha256: "" })
  property var mapCommandQueue: AutomapSession.createCommandQueue(64)
  property bool mapObserverReady: false
  property var mapLastStatus: null
  property var mapPendingRoom: null
  property string mapPendingCommand: ""
  property bool mapObserverSuppressed: false
  property var mapPersistenceQueue: []
  property var mapActiveOperation: null
  property bool mapFinalizationPending: false

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
  readonly property string dataRoot: Quickshell.env("XDG_DATA_HOME") || homePath + "/.local/share"
  readonly property string runtimePath: pluginRoot + "/runtime/x86_64-linux/dfrotz"
  readonly property string adventureRuntimePath: pluginRoot + "/runtime/x86_64-linux/advent"
  readonly property string scottFreeRuntimePath: pluginRoot + "/runtime/x86_64-linux/scottfree"
  readonly property string bundledStoryPath: pluginRoot + "/games/zork1.z3"
  readonly property string zork2StoryPath: pluginRoot + "/games/zork2.z3"
  readonly property string zork3StoryPath: pluginRoot + "/games/zork3.z3"
  readonly property string cartridgeRoot: dataRoot + "/lantern/cartridges"
  readonly property string cartridgeHelper: pluginRoot + "/bin/lantern-cartridge"
  readonly property string mapStateHelper: pluginRoot + "/bin/lantern-map-state"
  readonly property string windowStateHelper: pluginRoot + "/bin/window-state"
  readonly property string boundedFileReader: pluginRoot + "/bin/read-bounded-file"
  readonly property int boundedFileBytes: 65536
  readonly property string saveRoot: stateRoot + "/lantern/saves"
  readonly property string currentSaveRoot: currentCartridge ? saveRootFor(currentCartridge) : saveRoot
  readonly property string adventureAutosavePath: saveRoot + "/open-adventure/colossal-cave-1.22.sav"
  readonly property var engines: [{
    id: "zmachine",
    title: "Z-MACHINE",
    detail: "FROTZ 2.55  /  Z1-Z8"
  }, {
    id: "adventure",
    title: "OPEN ADVENTURE",
    detail: "NATIVE 1.22  /  430 PT"
  }, {
    id: "scottfree",
    title: "SCOTT ADAMS",
    detail: "SCOTTFREE 1.14  /  DAT"
  }]
  readonly property var bundledGames: [{
    id: "zork1", engine: "zmachine", number: "01", title: "ZORK I",
    subtitle: "THE GREAT UNDERGROUND EMPIRE  /  INFOCOM, 1980", path: bundledStoryPath,
    runtime: runtimePath, source: "factory", saveMode: "frotz"
  }, {
    id: "zork2", engine: "zmachine", number: "02", title: "ZORK II",
    subtitle: "THE WIZARD OF FROBOZZ  /  INFOCOM, 1981", path: zork2StoryPath,
    runtime: runtimePath, source: "factory", saveMode: "frotz"
  }, {
    id: "zork3", engine: "zmachine", number: "03", title: "ZORK III",
    subtitle: "THE DUNGEON MASTER  /  INFOCOM, 1982", path: zork3StoryPath,
    runtime: runtimePath, source: "factory", saveMode: "frotz"
  }]
  readonly property var adventureCartridge: ({
    id: "colossal-cave", engine: "adventure", number: "04", title: "COLOSSAL CAVE ADVENTURE",
    subtitle: "CROWTHER & WOODS  /  OPEN ADVENTURE 1.22", path: "",
    runtime: adventureRuntimePath, source: "factory", saveMode: "autosave"
  })
  readonly property var menuCartridges: buildMenuCartridges()
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
  readonly property color phosphorMuted: Qt.rgba(phosphorColor.r, phosphorColor.g, phosphorColor.b, 0.72)
  readonly property bool supportsMemoryBank: currentCartridge && (currentCartridge.saveMode === "frotz" || currentCartridge.saveMode === "scottfree")
  readonly property string saveExtension: currentCartridge && currentCartridge.saveMode === "scottfree" ? ".sav" : ".qzl"
  readonly property string phosphorLabel: phosphor === "green" ? "GRN" : phosphor === "theme" ? "THM" : "AMB"
  readonly property string mapSessionKey: mapFingerprint === "" ? "" : "zmachine:" + mapFingerprint
  readonly property bool mapCartridgeSupported: Automap.supportsCartridge("zmachine", mapFingerprint)
  readonly property bool mapAvailable: viewMode === "game" && gameProc.running && fileActionMode === "" &&
    currentCartridge && currentCartridge.engine === "zmachine" && mapCartridgeSupported &&
    mapObserverReady && !mapObserverSuppressed
  readonly property string mapUnavailableReason: currentCartridge && currentCartridge.engine !== "zmachine"
    ? "AUTOMAP IS NOT AVAILABLE FOR THIS ENGINE"
    : mapObserverSuppressed ? "AUTOMAP PAUSED AFTER AMBIGUOUS COMMAND TIMING"
    : mapFingerprint === "" ? "CARTRIDGE IDENTITY IS UNAVAILABLE"
    : !mapCartridgeSupported ? "AUTOMAP IN 0.2.0 SUPPORTS THE BUNDLED ZORK I STORY ONLY"
    : !mapObserverReady ? "WAITING FOR THE FIRST CONFIRMED ROOM"
    : fileActionMode !== "" ? "CLOSE THE MEMORY OVERLAY TO OPEN THE MAP"
    : "AUTOMAP IS NOT AVAILABLE RIGHT NOW"

  function currentEngineId() {
    return engines[Math.max(0, Math.min(engines.length - 1, engineIndex))].id
  }

  function buildMenuCartridges() {
    var engine = currentEngineId()
    if (engine === "adventure") return [adventureCartridge]

    var cartridges = engine === "zmachine" ? bundledGames.slice(0) : []
    var importedModel = engine === "zmachine" ? importedStories : importedScottStories
    var importedCount = importedModel ? importedModel.count : 0
    for (var i = 0; i < importedCount; i++) {
      var fileName = String(importedModel.get(i, "fileName") || "")
      cartridges.push({
        id: Model.importedCartridgeId(fileName),
        engine: engine,
        number: "U" + (i + 1 < 10 ? "0" : "") + String(i + 1),
        title: Model.cartridgeTitle(fileName),
        subtitle: engine === "zmachine" ? "IMPORTED Z-MACHINE STORY  /  " + fileName.toUpperCase()
          : "IMPORTED SCOTT ADAMS DATABASE  /  " + fileName.toUpperCase(),
        path: cartridgeRoot + "/" + fileName,
        runtime: engine === "zmachine" ? runtimePath : scottFreeRuntimePath,
        source: "imported",
        saveMode: engine === "zmachine" ? "frotz" : "scottfree",
        action: ""
      })
    }
    if (engine === "scottfree" && importedCount === 0) cartridges.push({
      action: "empty", number: "--", title: "NO CARTRIDGES LOADED",
      subtitle: "SCOTT ADAMS GAMES ARE NOT BUNDLED  /  PRESS I TO IMPORT A LEGAL .DAT FILE"
    })
    cartridges.push({ action: "import", title: "IMPORT CARTRIDGE" })
    return cartridges
  }

  function selectEngine(index) {
    engineIndex = Math.max(0, Math.min(engines.length - 1, Number(index)))
    menuIndex = 0
    statusText = "SELECT ENGINE"
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function moveEngineSelection(direction) {
    selectEngine(Model.menuStep(engineIndex, engines.length, direction))
  }

  function enterSelectedEngine() {
    menuIndex = 0
    launcherStage = "cartridges"
    statusText = "SELECT CARTRIDGE"
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function backToEngines() {
    launcherStage = "engines"
    statusText = "SELECT ENGINE"
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function cartridgeForBundledPath(path) {
    for (var i = 0; i < bundledGames.length; i++)
      if (bundledGames[i].path === path) return bundledGames[i]
    return null
  }

  function quickBoot(index) {
    if (index >= 0 && index < bundledGames.length) {
      engineIndex = 0
      menuIndex = index
      launchCartridge(bundledGames[index])
    } else if (index === 3) {
      engineIndex = 1
      menuIndex = 0
      launchCartridge(adventureCartridge)
    }
  }

  function beginCartridgeImport() {
    var engine = currentEngineId()
    if ((engine !== "zmachine" && engine !== "scottfree") || gameProc.running || startPending || importPending) return
    importEngineId = engine
    importMessage = ""
    statusText = "AWAITING CARTRIDGE"
    cartridgePicker.resultText = ""
    cartridgePicker.command = ["zenity", "--file-selection", "--title",
      engine === "scottfree" ? "Import a Scott Adams cartridge" : "Import a Z-machine cartridge",
      engine === "scottfree"
        ? "--file-filter=Scott Adams databases | *.dat"
        : "--file-filter=Z-machine stories | *.z1 *.z2 *.z3 *.z4 *.z5 *.z6 *.z7 *.z8",
      "--file-filter=All files | *"]
    cartridgePicker.running = true
  }

  function selectImportedFile() {
    if (importedFileName === "") return
    var model = importEngineId === "scottfree" ? importedScottStories : importedStories
    for (var i = 0; i < model.count; i++) {
      if (String(model.get(i, "fileName") || "") === importedFileName) {
        engineIndex = importEngineId === "scottfree" ? 2 : 0
        launcherStage = "cartridges"
        menuIndex = (importEngineId === "scottfree" ? 0 : bundledGames.length) + i
        statusText = "CARTRIDGE READY"
        importedFileName = ""
        importEngineId = ""
        Qt.callLater(function() { root.focusCurrentView() })
        return
      }
    }
  }

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
    var accessibility = config.accessibility || {}
    var audio = config.audio || {}

    if (display.phosphor === "amber" || display.phosphor === "green" || display.phosphor === "theme" || display.phosphor === "white")
      phosphor = display.phosphor
    if (display.effects === true || display.effects === false) crtEffects = display.effects
    crtRasterOpacity = configNumber(display.raster_opacity, crtRasterOpacity, 0.0, 1.0)
    crtRasterGain = configNumber(display.raster_gain, crtRasterGain, 0.25, 4.0)
    cursorFadeMs = Math.round(configNumber(display.cursor_fade_ms, cursorFadeMs, 150, 2000))
    historyLimit = Math.round(configNumber(terminal.history_limit, historyLimit, 10, 500))
    transcriptLineLimit = Math.round(configNumber(terminal.transcript_line_limit, transcriptLineLimit, 200, 5000))
    dialStep = configNumber(controls.dial_step, dialStep, 0.01, 0.25)
    if (accessibility.reduce_motion === true || accessibility.reduce_motion === false)
      reduceMotion = accessibility.reduce_motion
    if (audio.mute === true || audio.mute === false) audioMuted = audio.mute
    paperVolume = configNumber(audio.paper_volume, paperVolume, 0.0, 1.0)
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
    var requestedId = Model.bundledCartridgeId(payload.cartridge || "", [
      "zork1", "zork2", "zork3", "colossal-cave"
    ])
    var requestedCartridge = requested !== "" ? cartridgeForBundledPath(requested) : null
    if (requestedId === "colossal-cave") requestedCartridge = adventureCartridge
    else if (requestedId !== "") {
      for (var cartridgeIndex = 0; cartridgeIndex < bundledGames.length; cartridgeIndex++)
        if (bundledGames[cartridgeIndex].id === requestedId) requestedCartridge = bundledGames[cartridgeIndex]
    }

    closePending = false
    nativeClosePending = false
    opened = true
    if (!windowLoader.active) windowLoader.active = true
    if (!windowStatePrepare.running) windowStatePrepare.running = true

    if (requestedCartridge && !gameProc.running && !startPending) {
      launchCartridge(requestedCartridge)
    } else if (gameProc.running || startPending) {
      viewMode = "game"
    } else {
      viewMode = "menu"
      launcherStage = "engines"
      statusText = "SELECT ENGINE"
    }
  }

  function storyActivity() {
    return gameProc.running ? "active" : "idle"
  }

  function returnToMenu() {
    if (viewMode !== "game" || startPending || returningToMenu) return
    forceMapClosed()
    returningToMenu = true
    statusText = "EJECTING"
    if (gameProc.running) gameProc.running = false
    else finishReturnToMenu()
  }

  function finishReturnToMenu(nextStatus, message) {
    returningToMenu = false
    clearMapSession(currentCartridge !== null)
    var finishedEngine = currentCartridge ? currentCartridge.engine
      : pendingCartridge ? pendingCartridge.engine : ""
    storyPath = ""
    pendingStoryPath = ""
    pendingCartridge = null
    currentCartridge = null
    transcript = ""
    commandHistory = []
    historyIndex = 0
    fileActionMode = ""
    fileActionCommandRecorded = false
    saveOverwritePending = false
    fileActionMessage = ""
    importMessage = String(message || "")
    if (window && typeof window.clearCommandInput === "function") window.clearCommandInput()
    viewMode = "menu"
    launcherStage = finishedEngine !== "" ? "cartridges" : "engines"
    statusText = String(nextStatus || (launcherStage === "cartridges" ? "SELECT CARTRIDGE" : "SELECT ENGINE"))
    Qt.callLater(function() { root.focusCurrentView() })
  }

  function failCartridgeStart(status, message) {
    startPending = false
    finishReturnToMenu(status, message)
  }

  function focusCurrentView() {
    if (window && typeof window.focusCurrentView === "function") window.focusCurrentView()
  }

  function forceMapClosed() {
    if (window && typeof window.forceMapClosed === "function") window.forceMapClosed()
  }

  function toggleMap(userInitiated) {
    if (window && typeof window.toggleMap === "function") window.toggleMap(userInitiated !== false)
  }

  function mapModal() {
    return window && typeof window.mapModal === "function" && window.mapModal()
  }

  function validMapFingerprint(value) {
    return /^[a-f0-9]{64}$/.test(String(value || ""))
  }

  function resetMapMemory() {
    if (!validMapFingerprint(mapFingerprint) || !currentCartridge || currentCartridge.engine !== "zmachine") return
    var identity = { engine: "zmachine", sha256: mapFingerprint }
    var result = AutomapSession.enqueueOperation(mapPersistenceQueue, {
      op: "reset", engine: identity.engine, sha256: identity.sha256,
      epoch: mapSessionEpoch, payload: ""
    })
    if (!result.accepted) {
      statusText = "MAP RESET DEFERRED — TRY AGAIN"
      return
    }
    mapWriteDebounce.stop()
    mapPersistenceQueue = result.queue
    mapState = Automap.createEmptyState(identity)
    mapObserverReady = false
    startNextMapPersistenceOperation()
  }

  function enqueueMapPersistenceWrite() {
    if (!validMapFingerprint(mapFingerprint)) return false
    var payload = ""
    try { payload = Automap.serializePersistentState(mapState) } catch (error) { return false }
    var result = AutomapSession.enqueueOperation(mapPersistenceQueue, {
      op: "write", engine: "zmachine", sha256: mapFingerprint,
      epoch: mapSessionEpoch, payload: payload
    })
    if (!result.accepted) {
      if (gameProc.running) statusText = "MAP CHECKPOINT DEFERRED"
      return false
    }
    mapPersistenceQueue = result.queue
    startNextMapPersistenceOperation()
    return true
  }

  function startNextMapPersistenceOperation() {
    if (mapPersistenceProc.running || mapActiveOperation || mapPersistenceQueue.length === 0) return
    var queue = mapPersistenceQueue.slice(0)
    var operation = queue.shift()
    mapPersistenceQueue = queue
    mapActiveOperation = operation
    mapPersistenceProc.operation = operation
    mapPersistenceProc.resultText = ""
    mapPersistenceProc.command = [mapStateHelper, operation.op, operation.engine, operation.sha256]
    mapPersistenceProc.stdinEnabled = operation.op === "write"
    mapPersistenceProc.running = true
  }

  function finishMapSessionClear() {
    mapFinalizationPending = false
    mapSessionEpoch++
    mapFingerprint = ""
    mapState = Automap.createEmptyState({ engine: "", sha256: "" })
    mapCommandQueue = AutomapSession.createCommandQueue(64)
    mapObserverReady = false
    mapLastStatus = null
    mapPendingRoom = null
    mapPendingCommand = ""
    mapObserverSuppressed = false
  }

  function retryPendingMapFinalization() {
    if (!mapFinalizationPending) return
    if (!enqueueMapPersistenceWrite()) return
    finishMapSessionClear()
  }

  function clearMapSession(persistFinal) {
    forceMapClosed()
    mapWriteDebounce.stop()
    if (persistFinal === true && mapCartridgeSupported && !enqueueMapPersistenceWrite()) {
      mapFinalizationPending = true
      startNextMapPersistenceOperation()
      return false
    }
    finishMapSessionClear()
    return true
  }

  function beginMapStartup() {
    mapSessionEpoch++
    mapFingerprint = ""
    mapState = Automap.createEmptyState({ engine: "", sha256: "" })
    mapCommandQueue = AutomapSession.createCommandQueue(64)
    mapObserverReady = false
    mapObserverSuppressed = false
    mapLastStatus = null
    mapPendingRoom = null
    mapPendingCommand = ""
    if (!pendingCartridge || pendingCartridge.engine !== "zmachine") {
      startPendingCartridge()
      return
    }
    mapFingerprintProc.requestEpoch = mapSessionEpoch
    mapFingerprintProc.requestPath = pendingStoryPath
    mapFingerprintProc.resultText = ""
    mapFingerprintProc.command = [cartridgeHelper, "fingerprint-zmachine", pendingStoryPath]
    mapFingerprintProc.running = true
  }

  function continueAfterMapFingerprint(exitCode, resultText, requestEpoch, requestPath) {
    if (!AutomapSession.startupResultMatches(mapSessionEpoch, pendingStoryPath, requestEpoch, requestPath)) return
    var fingerprint = String(resultText || "").trim()
    if (exitCode !== 0 || !validMapFingerprint(fingerprint)) {
      mapFingerprint = ""
      startPendingCartridge()
      return
    }
    mapFingerprint = fingerprint
    if (!mapCartridgeSupported) {
      startPendingCartridge()
      return
    }
    var readOperation = {
      op: "read", engine: "zmachine", sha256: fingerprint,
      epoch: requestEpoch, requestPath: requestPath, payload: ""
    }
    var result = AutomapSession.enqueueOperation(mapPersistenceQueue, readOperation)
    if (!result.accepted) {
      mapState = Automap.createEmptyState({ engine: "zmachine", sha256: fingerprint })
      startPendingCartridge()
      return
    }
    mapPersistenceQueue = result.queue
    startNextMapPersistenceOperation()
  }

  function continueAfterMapRead(exitCode, resultText, requestEpoch, requestPath, requestFingerprint) {
    if (!AutomapSession.startupResultMatches(mapSessionEpoch, pendingStoryPath, requestEpoch, requestPath) ||
        mapFingerprint !== requestFingerprint) return
    var identity = { engine: "zmachine", sha256: requestFingerprint }
    var hydrated = null
    if (exitCode === 0) {
      try { hydrated = Automap.hydratePersistentState(String(resultText || "")) } catch (error) {}
    }
    mapState = hydrated || Automap.createEmptyState(identity)
    startPendingCartridge()
  }

  function enqueueMapCommand(command) {
    if (!currentCartridge || currentCartridge.engine !== "zmachine" ||
        !mapCartridgeSupported || mapObserverSuppressed) return
    var next = AutomapSession.enqueueCommand(mapCommandQueue, command)
    mapCommandQueue = next
    if (next.suppressed) {
      mapObserverSuppressed = true
      try { mapState = Automap.resynchronizeState(mapState) } catch (error) {}
      forceMapClosed()
    }
  }

  function writeGameInput(payload, logicalCommand) {
    enqueueMapCommand(logicalCommand)
    gameProc.write(payload)
  }

  function observeAutomapOutput(raw) {
    if (!currentCartridge || currentCartridge.engine !== "zmachine" ||
        !mapCartridgeSupported || mapObserverSuppressed) return
    var input = Automap.parseInputEvent(raw)
    if (input) {
      // Native VM input acknowledges commands even when no status follows (quit
      // and confirmation prompts). File dialogs do not enter the VM queue.
      mapCommandQueue = AutomapSession.shiftCommand(mapCommandQueue).queue
      mapPendingCommand = input.command
      mapPendingRoom = null
      if (!input.valid || Automap.normalizeControlCommand(input.command) !== "")
        mapState = Automap.resynchronizeState(mapState)
      return
    }
    var event = Automap.parseRoomEvent(raw)
    if (event) {
      event.command = mapPendingCommand
      mapPendingCommand = ""
      mapPendingRoom = event
      return
    }
    var pending = mapPendingRoom
    mapPendingRoom = null
    var framed = Automap.pairRoomStatus(pending, raw)
    var observation = framed ? framed.observation : Automap.knownRoomObservation(mapState, pending)
    if (!observation) {
      if (pending) mapState = Automap.resynchronizeState(mapState)
      return
    }
    var command = pending.command
    try {
      if (Automap.statusDiscontinuity(mapLastStatus, observation.status))
        mapState = Automap.resynchronizeState(mapState)
      mapLastStatus = observation.status
      mapState = Automap.reduceIdentifiedTurn(mapState, command, observation)
      mapObserverReady = true
      mapWriteDebounce.restart()
    } catch (error) {
      mapObserverSuppressed = true
      try { mapState = Automap.resynchronizeState(mapState) } catch (ignored) {}
      forceMapClosed()
    }
  }

  function moveMenuSelection(direction) {
    menuIndex = Model.menuStep(menuIndex, menuCartridges.length, direction)
  }

  function activateMenuSelection() {
    if (menuIndex < 0 || menuIndex >= menuCartridges.length) {
      statusText = "NO CARTRIDGE SELECTED"
      return
    }
    var cartridge = menuCartridges[menuIndex]
    if (!cartridge || cartridge.action === "empty") {
      statusText = "NO CARTRIDGES  /  PRESS I TO IMPORT"
      importMessage = "SCOTT ADAMS DATABASES MUST BE SUPPLIED BY THE USER"
      return
    }
    if (cartridge.action === "import") beginCartridgeImport()
    else launchCartridge(cartridge)
  }

  function launchCartridge(cartridge) {
    if (!cartridge || gameProc.running || startPending) return
    if (mapFinalizationPending) {
      statusText = "FINISHING MAP CHECKPOINT — TRY AGAIN"
      return
    }
    forceMapClosed()
    for (var index = 0; index < engines.length; index++)
      if (engines[index].id === cartridge.engine) engineIndex = index
    launcherStage = "cartridges"
    pendingCartridge = cartridge
    pendingStoryPath = String(cartridge.path || "")
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

  function launchStory(path) {
    var cartridge = cartridgeForBundledPath(path)
    if (cartridge) launchCartridge(cartridge)
  }

  function saveRootFor(cartridge) {
    if (!cartridge) return saveRoot
    if (cartridge.engine === "scottfree") return saveRoot + "/scottfree/" + cartridge.id
    if (cartridge.engine === "adventure") return saveRoot + "/open-adventure"
    return saveRoot
  }

  function preparationCommand(cartridge) {
    var directories = [dataRoot + "/lantern"]
    if (cartridge && cartridge.engine === "scottfree") directories.push(stateRoot)
    else directories.push(saveRoot, saveRootFor(cartridge))
    return ["mkdir", "-p", "--"].concat(directories)
  }

  function gameCommand(cartridge) {
    if (!cartridge) return []
    if (cartridge.engine === "adventure")
      return [cartridge.runtime, "-o", "-a", adventureAutosavePath]
    if (cartridge.engine === "scottfree")
      return [cartridge.runtime, "--save-root", stateRoot, "--save-key", cartridge.id,
        "-w", cartridge.path]
    return [cartridge.runtime, "-q", "-m", "-w", "76", "-R", saveRootFor(cartridge), cartridge.path]
  }

  function startPendingCartridge() {
    if (!pendingCartridge) return
    statusText = "WARMING UP"
    currentCartridge = pendingCartridge
    storyPath = pendingStoryPath
    gameProc.command = gameCommand(pendingCartridge)
    gameProc.running = true
    startPending = false
  }

  function close() {
    forceMapClosed()
    opened = false
    if (cartridgePicker.running) cartridgePicker.running = false
    importEngineId = ""
    importSourcePath = ""
    importPending = false
    continueClose()
  }

  function continueClose() {
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
    return currentCartridge && currentCartridge.id ? currentCartridge.id : "story"
  }

  function defaultSaveName() {
    return currentStoryId() + "-" + Qt.formatDateTime(new Date(), "MMdd-HHmmss")
  }

  function normalizeCurrentSaveName(raw) {
    var stem = Model.normalizeSaveName(raw)
    return currentCartridge && currentCartridge.saveMode === "scottfree" ? stem.replace(/\s+/g, "-") : stem
  }

  function matchingSaveFileName(raw) {
    var stem = normalizeCurrentSaveName(raw)
    if (stem === "") return ""
    var target = (stem + saveExtension).toLowerCase()
    for (var i = 0; i < saveFiles.count; i++) {
      var fileName = String(saveFiles.get(i, "fileName") || "")
      if (fileName.toLowerCase() === target) return fileName
    }
    return ""
  }

  function refreshSaveFiles() {
    // FolderListModel cannot watch a directory that did not exist at startup.
    saveFiles.folder = ""
    Qt.callLater(function() {
      saveFiles.folder = Qt.binding(function() { return "file://" + root.currentSaveRoot })
    })
  }

  function saveDisplayName(raw) {
    return String(raw || "").replace(/\.(?:qzl|sav)$/i, "")
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
    if (!gameProc.running || !supportsMemoryBank) return
    forceMapClosed()
    fileActionMode = "save"
    fileActionCommandRecorded = recorded === true
    saveOverwritePending = false
    fileActionMessage = ""
    saveDraft = normalizeCurrentSaveName(requestedName) || defaultSaveName()
    Qt.callLater(function() { root.focusCurrentView() })
    if (requestedName) completeSave(saveDraft, false)
  }

  function completeSave(raw, overwriteConfirmed) {
    if (fileActionMode !== "save") return
    var stem = normalizeCurrentSaveName(raw)
    if (stem === "") {
      fileActionMessage = "ENTER A NAME FOR THIS SAVE"
      return
    }

    var existing = matchingSaveFileName(stem)
    if (existing !== "" && !overwriteConfirmed) {
      saveDraft = saveDisplayName(existing)
      saveOverwritePending = true
      fileActionMessage = "SAVE EXISTS — ENTER TO OVERWRITE"
      Qt.callLater(function() { root.focusCurrentView() })
      return
    }

    if (!fileActionCommandRecorded) rememberCommand("SAVE")
    if (existing !== "") stem = saveDisplayName(existing)
    var fileName = existing !== "" ? existing : stem + saveExtension
    transcript = Model.appendTranscript(transcript, "[SAVING  " + fileName + "]", transcriptLineLimit)
    closeFileAction(false)
    if (currentCartridge.saveMode === "scottfree") gameProc.write("save\n" + stem + "\n")
    else writeGameInput("save\n" + stem + "\n" + (existing !== "" ? "y\n" : ""), "save")
    saveLibraryRefresh.restart()
  }

  function beginLoad(recorded, requestedName) {
    if (!gameProc.running || !supportsMemoryBank) return
    forceMapClosed()
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
    var existing = matchingSaveFileName(saveDisplayName(raw))
    if (existing === "") {
      fileActionMessage = "SAVE FILE IS NO LONGER AVAILABLE"
      return
    }
    if (!fileActionCommandRecorded) rememberCommand("RESTORE")
    transcript = Model.appendTranscript(transcript, "[LOADING  " + existing + "]", transcriptLineLimit)
    closeFileAction(false)
    writeGameInput("restore\n" + existing + "\n", "restore")
  }

  function submitCommand(raw) {
    var command = Model.normalizeCommand(raw)
    if (command === "" || !gameProc.running || fileActionMode !== "") return

    var fileCommand = supportsMemoryBank ? command.match(/^(save|restore|load)(?:\s+(.+))?$/i) : null
    if (fileCommand) {
      rememberCommand(command)
      if (fileCommand[1].toLowerCase() === "save") beginSave(true, fileCommand[2] || "")
      else beginLoad(true, fileCommand[2] || "")
      return
    }

    rememberCommand(command)
    writeGameInput(command + "\n", command)
  }

  function stepHistory(direction) {
    var next = Model.historyStep(commandHistory, historyIndex, direction)
    historyIndex = next.index
    if (window && typeof window.setCommandDraft === "function") window.setCommandDraft(next.value)
  }

  FolderListModel {
    id: saveFiles
    folder: "file://" + root.currentSaveRoot
    nameFilters: ["*" + root.saveExtension]
    sortField: FolderListModel.Time
    sortReversed: true
    showFiles: true
    showDirs: false
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
  }

  FolderListModel {
    id: importedStories
    folder: "file://" + root.cartridgeRoot
    nameFilters: ["*.z1", "*.z2", "*.z3", "*.z4", "*.z5", "*.z6", "*.z7", "*.z8"]
    sortField: FolderListModel.Name
    showFiles: true
    showDirs: false
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
    onCountChanged: root.selectImportedFile()
  }

  FolderListModel {
    id: importedScottStories
    folder: "file://" + root.cartridgeRoot
    nameFilters: ["*.dat"]
    sortField: FolderListModel.Name
    showFiles: true
    showDirs: false
    showDotAndDotDot: false
    showHidden: false
    showOnlyReadable: true
    onCountChanged: root.selectImportedFile()
  }

  Process {
    id: cartridgePicker
    property string resultText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cartridgePicker.resultText = text
    }
    onExited: function(exitCode) {
      if (!root.opened) return
      if (exitCode !== 0) {
        root.importEngineId = ""
        root.importSourcePath = ""
        root.importPending = false
        root.statusText = "SELECT CARTRIDGE"
        Qt.callLater(function() { root.focusCurrentView() })
        return
      }
      var path = String(resultText || "").replace(/[\r\n]+$/, "")
      if (!/^\/[^\r\n\u0000]+$/.test(path)) {
        root.statusText = "IMPORT REJECTED"
        root.importMessage = "SELECT A LOCAL CARTRIDGE FILE"
        Qt.callLater(function() { root.focusCurrentView() })
        return
      }
      root.importSourcePath = path
      root.importPending = true
      root.statusText = "FILING CARTRIDGE"
      importPrepareDir.running = true
    }
  }

  Process {
    id: importPrepareDir
    command: ["mkdir", "-p", "--", root.dataRoot + "/lantern"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.importPending = false
        root.statusText = "STORAGE ERROR"
        root.importMessage = "CARTRIDGE LIBRARY COULD NOT BE PREPARED"
        return
      }
      cartridgeImport.command = [root.cartridgeHelper,
        root.importEngineId === "scottfree" ? "import-scott" : "import-zmachine",
        root.importSourcePath, root.cartridgeRoot]
      cartridgeImport.running = true
    }
  }

  Process {
    id: cartridgeImport
    property string resultText: ""
    stdinEnabled: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cartridgeImport.resultText = text
    }
    stderr: StdioCollector {
      id: cartridgeImportErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.importPending = false
      root.importSourcePath = ""
      if (exitCode !== 0) {
        root.statusText = "IMPORT REJECTED"
        root.importMessage = Model.cleanOutput(cartridgeImportErrors.text) || "HEADER CHECK FAILED — FILE WAS NOT COPIED"
        root.importEngineId = ""
        Qt.callLater(function() { root.focusCurrentView() })
        return
      }
      root.importedFileName = String(resultText || "").trim()
      root.importMessage = ""
      root.statusText = "CARTRIDGE READY"
      var importedModel = root.importEngineId === "scottfree" ? importedScottStories : importedStories
      importedModel.folder = ""
      importedModel.folder = "file://" + root.cartridgeRoot
      Qt.callLater(root.selectImportedFile)
    }
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
    command: root.preparationCommand(root.pendingCartridge)
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.failCartridgeStart("STORAGE ERROR", "GAME AND SAVE DIRECTORIES COULD NOT BE PREPARED")
        return
      }
      root.refreshSaveFiles()
      runtimeCheck.command = ["test", "-x", root.pendingCartridge.runtime]
      runtimeCheck.running = true
    }
  }

  Process {
    id: runtimeCheck
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.failCartridgeStart("RUNTIME ERROR", "SELECTED ENGINE IS MISSING — REINSTALL LANTERN")
        return
      }
      if (root.pendingCartridge.engine === "adventure") {
        root.startPendingCartridge()
        return
      }
      storyCheck.command = root.pendingCartridge.source === "imported"
        ? [root.cartridgeHelper,
          root.pendingCartridge.engine === "scottfree" ? "check-scott" : "check-zmachine",
          root.pendingStoryPath, root.cartridgeRoot]
        : ["test", "-f", root.pendingStoryPath]
      storyCheck.running = true
    }
  }

  Process {
    id: storyCheck
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.failCartridgeStart("NO CARTRIDGE", "CARTRIDGE IS UNAVAILABLE OR FAILED ITS FORMAT CHECK")
        return
      }
      root.beginMapStartup()
    }
  }

  Process {
    id: mapFingerprintProc
    property int requestEpoch: 0
    property string requestPath: ""
    property string resultText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mapFingerprintProc.resultText = text
    }
    onExited: function(exitCode) {
      root.continueAfterMapFingerprint(exitCode, resultText, requestEpoch, requestPath)
    }
  }

  Process {
    id: mapPersistenceProc
    property var operation: null
    property string resultText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mapPersistenceProc.resultText = text
    }
    onStarted: {
      if (operation && operation.op === "write") {
        write(operation.payload)
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      var completed = operation
      var output = resultText
      root.mapActiveOperation = null
      operation = null
      resultText = ""
      if (completed && completed.op === "read")
        root.continueAfterMapRead(exitCode, output, completed.epoch, completed.requestPath, completed.sha256)
      else if (completed && exitCode !== 0 && completed.epoch === root.mapSessionEpoch)
        root.statusText = "MAP STORAGE ERROR — CHECK STATE DIRECTORY PERMISSIONS"
      root.startNextMapPersistenceOperation()
      root.retryPendingMapFinalization()
    }
  }

  Timer {
    id: saveLibraryRefresh
    interval: 250
    repeat: false
    onTriggered: root.refreshSaveFiles()
  }

  Timer {
    id: mapWriteDebounce
    interval: 750
    repeat: false
    onTriggered: root.enqueueMapPersistenceWrite()
  }

  Process {
    id: gameProc
    stdinEnabled: true
    environment: ({ "LANTERN_ROOM_EVENTS": root.mapCartridgeSupported ? "1" : "0" })
    stdout: SplitParser {
      onRead: function(line) {
        root.observeAutomapOutput(line)
        root.appendOutput(Automap.stripRoomMetadata(line))
      }
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
      root.statusText = root.currentCartridge && root.currentCartridge.saveMode === "autosave" ? "ONLINE  /  AUTO MEMORY" : "ONLINE"
      Qt.callLater(function() {
        if (root.opened && window && window.visible) root.focusCurrentView()
      })
    }
    onExited: function(exitCode) {
      if (root.returningToMenu) {
        root.finishReturnToMenu()
        return
      }
      root.finishReturnToMenu(
        exitCode === 0 ? "SESSION ENDED" : "ENGINE STOPPED",
        exitCode === 0 ? "CARTRIDGE SESSION ENDED" : "ENGINE STOPPED UNEXPECTEDLY"
      )
    }
  }

  PaperSound {
    id: paperSound
    muted: root.audioMuted
    reduceMotion: root.reduceMotion
    volume: root.paperVolume
  }

  Loader {
    id: windowLoader
    active: true

    sourceComponent: Component {
      FloatingWindow {
        id: window
    title: "Lantern — Interactive Fiction Terminal"
    visible: false
    color: "#ff141512"
    implicitWidth: Math.round(root.baseWindowWidth * root.windowScale)
    implicitHeight: Math.round(root.baseWindowHeight * root.windowScale)
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    function focusCurrentView() {
      if (mapOverlay.modal) mapOverlay.focusCurrent()
      else if (root.viewMode === "menu") {
        if (root.launcherStage === "engines") engineMenu.focusCurrent()
        else cartridgeMenu.focusCurrent()
      } else if (root.fileActionMode !== "") saveLoadOverlay.focusCurrent()
      else commandInput.forceActiveFocus()
    }

    function forceMapClosed() { mapOverlay.forceClosed() }
    function toggleMap(userInitiated) { mapOverlay.toggleMap(userInitiated !== false) }
    function mapModal() { return mapOverlay.modal }
    function restoreMapFocus(priorItem) {
      if (!visible) return
      if (priorItem && priorItem.visible === true && priorItem.enabled === true &&
          typeof priorItem.forceActiveFocus === "function") priorItem.forceActiveFocus()
      else focusCurrentView()
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

    Shortcut {
      sequence: "Ctrl+P"
      autoRepeat: false
      enabled: root.viewMode === "game" && mapOverlay.motionState === "closed"
      onActivated: root.toggleMap(true)
    }

    onClosed: {
      root.forceMapClosed()
      if (root.opened && !root.closingFromHost) {
        root.nativeClosePending = true
        root.requestClose()
      }
    }

    onVisibleChanged: {
      if (!visible) root.forceMapClosed()
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    Rectangle {
      id: terminalShell
      width: root.baseWindowWidth
      height: root.baseWindowHeight
      transformOrigin: Item.TopLeft
      scale: root.windowScale
      opacity: 1.0
      color: "#ff141512"

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
          text: "LANTERN  //  MULTI-ENGINE TERMINAL"
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
          color: gameProc.running ? root.phosphorDim : "#8c8978"
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
                enabled: gameProc.running && root.fileActionMode === "" && !root.mapModal()
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
                  model: [{ label: root.mapAvailable ? "MAP  ^P" : "MAP  --", action: "map" },
                    { label: "SAVE  ^S", action: "save" },
                    { label: "LOAD  ^L", action: "load" },
                    { label: "MENU  ^M", action: "menu" }]

                  delegate: Rectangle {
                    id: actionButton
                    required property var modelData
                    readonly property bool baseAvailable: gameProc.running && !root.returningToMenu &&
                      root.fileActionMode === "" && !root.mapModal()
                    readonly property bool available: baseAvailable &&
                      (modelData.action === "map" ? root.mapAvailable
                        : modelData.action === "menu" || root.supportsMemoryBank)
                    width: 74
                    height: 25
                    color: "transparent"
                    border.width: 1
                    border.color: root.phosphorDim
                    opacity: available ? 0.88 : 0.35

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
                      id: mapButtonHover
                      enabled: actionButton.available || (actionButton.modelData.action === "map" && actionButton.baseAvailable)
                      cursorShape: actionButton.available ? Qt.PointingHandCursor : Qt.WhatsThisCursor
                    }

                    ToolTip.visible: actionButton.modelData.action === "map" && mapButtonHover.hovered && !root.mapAvailable
                    ToolTip.text: root.mapUnavailableReason

                    TapHandler {
                      enabled: actionButton.available
                      acceptedButtons: Qt.LeftButton
                      onTapped: {
                        if (actionButton.modelData.action === "map") root.toggleMap(true)
                        else if (actionButton.modelData.action === "save") root.beginSave(false, "")
                        else if (actionButton.modelData.action === "load") root.beginLoad(false, "")
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

            EngineMenu {
              id: engineMenu
              anchors.fill: parent
              visible: root.viewMode === "menu" && root.launcherStage === "engines"
              focus: visible
              controller: root
            }

            CartridgeMenu {
              id: cartridgeMenu
              anchors.fill: parent
              visible: root.viewMode === "menu" && root.launcherStage === "cartridges"
              focus: visible
              controller: root
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
            color: gameProc.running ? root.phosphorColor : "#413f37"
            border.width: 1
            border.color: gameProc.running ? root.phosphorDim : "#24251f"
            opacity: gameProc.running ? 0.82 : 0.55

            Rectangle {
              width: 3
              height: 3
              radius: 2
              anchors.left: parent.left
              anchors.leftMargin: 2
              anchors.top: parent.top
              anchors.topMargin: 2
              color: "#ffffff"
              opacity: gameProc.running ? 0.55 : 0.12
            }
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              text: gameProc.running ? "SIGNAL" : "STANDBY"
              color: gameProc.running ? "#aaa694" : "#6c6a5e"
              font.family: "monospace"
              font.pixelSize: 8
              font.bold: true
              font.letterSpacing: 0.7
              textFormat: Text.PlainText
            }

            Text {
              text: gameProc.running ? "LOCKED" : "READY"
              color: "#56554b"
              font.family: "monospace"
              font.pixelSize: 7
              font.letterSpacing: 0.6
              textFormat: Text.PlainText
            }
          }
        }
      }

      MapOverlay {
        id: mapOverlay
        mapState: root.mapState
        currentNodeId: root.mapState && root.mapState.currentNodeId ? String(root.mapState.currentNodeId) : ""
        sessionKey: root.mapSessionKey
        mapTitle: root.currentCartridge ? String(root.currentCartridge.title || "EXPLORER'S FIELD MAP") : "EXPLORER'S FIELD MAP"
        available: root.mapAvailable
        unavailableReason: root.mapUnavailableReason
        reduceMotion: root.reduceMotion
        resetEnabled: root.mapAvailable
        renderScale: root.windowScale
        crtRect: Qt.rect(46, 60, 928, 617)
        dragStripHeight: 42
        z: 100
        onTransitionSoundRequested: function(kind) { paperSound.request(kind) }
        onClosed: paperSound.stop()
        onResetMapRequested: root.resetMapMemory()
        onUnavailableActivated: function(reason) { root.statusText = String(reason || root.mapUnavailableReason) }
        onFocusRestoreRequested: function(priorItem) { window.restoreMapFocus(priorItem) }
      }

      Item {
        id: topDragHandle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 42
        z: 120

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
    }
      }
    }
  }
}
