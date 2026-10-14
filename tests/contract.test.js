const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const crypto = require("node:crypto")
const { spawnSync } = require("node:child_process")

const root = path.resolve(__dirname, "..")

test("manifest declares a summonable third-party panel", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "jobo.lantern")
  assert.deepEqual(manifest.kinds, ["panel", "bar-widget"])
  assert.equal(manifest.entryPoints.panel, "Panel.qml")
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml")
  assert.equal(manifest.keepLoaded, true)
  assert.equal(manifest.license, "MIT AND GPL-2.0-or-later AND BSD-2-Clause")
})

test("shell entry points import the host modules they use", () => {
  // BarWidget needs WidgetButton/Style and Panel needs Color; the host only
  // resolves them through these imports, which offline Qt tests cannot catch.
  // Isolated Panel harnesses supply Color from tests/host-stubs instead.
  const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
  assert.match(bar, /^import qs\.Commons$/m)
  assert.match(bar, /^import qs\.Ui$/m)
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  assert.match(panel, /^import qs\.Commons$/m)
  assert.doesNotMatch(panel, /^import qs\.(?!Commons$)/m, "Panel imports only stubbed host modules")
  assert.match(fs.readFileSync(path.join(root, "tests/host-stubs/Commons/Color.qml"), "utf8"), /pragma Singleton/)
})

test("release polls Lantern configuration through the bounded reader", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const config = fs.readFileSync(path.join(root, "lantern.toml"), "utf8")

  for (const required of [
    'bundledConfigPath: pluginRoot + "/lantern.toml"',
    'userConfigPath: configRoot + "/lantern/lantern.toml"',
    "Model.parseLanternConfig(raw)",
    "function applyConfigLayers()",
    'boundedFileReader: pluginRoot + "/bin/read-bounded-file"',
    "Model.boundedFileText(text, root.boundedFileBytes)",
    "command: [root.boundedFileReader, root.bundledConfigPath]",
    "command: [root.boundedFileReader, root.userConfigPath]",
    "command: [root.boundedFileReader, root.themeColorsPath]",
    "property real rasterGain: root.crtRasterGain"
  ]) assert.match(panel, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.doesNotMatch(panel, /FileView\s*\{/)

  for (const required of [
    "[display]", "phosphor", "effects", "raster_opacity", "raster_gain",
    "cursor_fade_ms", "[terminal]", "history_limit", "transcript_line_limit",
    "[launcher]", "default_cartridge", "[controls]", "dial_step"
  ]) assert.match(config, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
})

test("bounded file reader rejects symlinks, special files, and oversized input", () => {
  const reader = path.join(root, "bin/read-bounded-file")
  const fixtureRoot = fs.mkdtempSync(path.join(root, ".test-bounded-reader-"))

  try {
    const regular = path.join(fixtureRoot, "regular.toml")
    const maximum = path.join(fixtureRoot, "maximum.toml")
    const oversized = path.join(fixtureRoot, "oversized.toml")
    const symlink = path.join(fixtureRoot, "linked.toml")
    const fifo = path.join(fixtureRoot, "config.fifo")
    fs.writeFileSync(regular, "[display]\nphosphor = \"green\"\n")
    fs.writeFileSync(maximum, "x".repeat(65536))
    fs.writeFileSync(oversized, "x".repeat(65537))
    fs.symlinkSync(regular, symlink)
    assert.equal(spawnSync("mkfifo", [fifo]).status, 0)

    assert.equal(spawnSync(reader, [regular], { encoding: "utf8" }).stdout, fs.readFileSync(regular, "utf8"))
    assert.equal(spawnSync(reader, [maximum], { encoding: "utf8" }).stdout.length, 65536)
    assert.equal(spawnSync(reader, [oversized], { encoding: "utf8" }).stdout, "")
    assert.equal(spawnSync(reader, [symlink], { encoding: "utf8" }).stdout, "")
    assert.equal(spawnSync(reader, [fixtureRoot], { encoding: "utf8" }).stdout, "")
    const fifoRead = spawnSync(reader, [fifo], { encoding: "utf8", timeout: 1500 })
    assert.equal(fifoRead.error, undefined)
    assert.equal(fifoRead.stdout, "")
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true })
  }
})

test("native helper executables are rebuilt reproducibly in CI", () => {
  const build = fs.readFileSync(path.join(root, "scripts/build-bounded-reader"), "utf8")
  const mapBuild = fs.readFileSync(path.join(root, "scripts/build-map-state-helper"), "utf8")
  const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8")
  const provenance = fs.readFileSync(path.join(root, "docs/read-bounded-file-provenance.md"), "utf8")
  const digest = "sha256:82549aa8f90ada3236a8be70c74543132a76662ef33f0c3271ed802b81584a82"

  assert.match(build, new RegExp(digest))
  assert.match(build, /--platform linux\/amd64/)
  assert.match(build, /SOURCE_DATE_EPOCH=0/)
  assert.match(build, /--build-id=none/)
  assert.match(workflow, /\.\/scripts\/build-bounded-reader "\$RUNNER_TEMP\/read-bounded-file"/)
  assert.match(workflow, /cmp --silent bin\/read-bounded-file "\$RUNNER_TEMP\/read-bounded-file"/)
  assert.match(mapBuild, new RegExp(digest))
  assert.match(workflow, /\.\/scripts\/build-map-state-helper "\$RUNNER_TEMP\/lantern-map-state"/)
  assert.match(workflow, /cmp --silent bin\/lantern-map-state "\$RUNNER_TEMP\/lantern-map-state"/)
  assert.match(provenance, new RegExp(digest))
})

test("bar widget opens Lantern through the shell host with its bundled icon", () => {
  const source = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
  const icon = fs.readFileSync(path.join(root, "assets/lantern.svg"), "utf8")
  for (const required of [
    'moduleName: "jobo.lantern"',
    "WidgetButton",
    'tooltipText: root.storyActive ? "Lantern · Story running" : "Lantern"',
    'Qt.resolvedUrl("assets/lantern.svg")',
    'root.bar.run("omarchy-shell shell toggle jobo.lantern \'{}\'")',
    'boundedFileReader: pluginRoot + "/bin/read-bounded-file"',
    "Model.boundedFileText(text, root.boundedFileBytes)",
    "command: [root.boundedFileReader, root.themeColorsPath]"
  ]) assert.match(source, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.doesNotMatch(source, /FileView\s*\{/)
  assert.match(icon, /viewBox="0 0 24 24"/)
  assert.match(icon, /#ffffff/)
  assert.match(icon, /transform="translate\(0 1\)"/)
  assert.doesNotMatch(icon, /#ffb84d|#2b1908|#4a2c0d/)
  assert.match(source, /MultiEffect/)
  assert.match(source, /anchors\.verticalCenterOffset: 0/)
  assert.match(source, /width: Style\.space\(14\)/)
  assert.match(source, /height: Style\.space\(13\)/)
  assert.match(source, /fillMode: Image\.Stretch/)
  assert.match(source, /host\.callIfLoaded\(moduleName, "storyActivity", ""\)/)
  assert.match(source, /values\.yellow \|\| values\.color3 \|\| values\.color9/)
  assert.match(source, /colorizationColor: root\.storyActive \? root\.themeYellow : button\.foreground/)
  assert.match(source, /shadowEnabled: root\.storyActive/)
  assert.match(source, /running: root\.storyActive/)
})

test("panel follows the Quattro lifecycle and keeps Frotz file access restricted", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  for (const required of [
    "property var shell: null",
    "property var manifest: null",
    "function open(payloadJson)",
    "function close()",
    "function continueClose()",
    "if (cartridgePicker.running) cartridgePicker.running = false",
    "FloatingWindow",
    'title: "Lantern — Interactive Fiction Terminal"',
    "implicitWidth: Math.round(root.baseWindowWidth * root.windowScale)",
    "implicitHeight: Math.round(root.baseWindowHeight * root.windowScale)",
    "minimumSize: Qt.size(implicitWidth, implicitHeight)",
    "maximumSize: Qt.size(implicitWidth, implicitHeight)",
    "DragHandler",
    "cursorShape: Qt.SizeAllCursor",
    "window.startSystemMove()",
    'property string viewMode: "menu"',
    'property string launcherStage: "engines"',
    "readonly property var engines",
    "readonly property var bundledGames",
    "readonly property var adventureCartridge",
    "readonly property var menuCartridges",
    "EngineMenu",
    "CartridgeMenu",
    "function enterSelectedEngine()",
    "function backToEngines()",
    "function activateMenuSelection()",
    "property bool returningToMenu: false",
    "function returnToMenu()",
    "if (gameProc.running) gameProc.running = false",
    '{ label: "MENU  ^M", action: "menu" }',
    "event.key === Qt.Key_M",
    "else root.returnToMenu()",
    "property real crtRasterOpacity: 1.0",
    "function setCrtRasterOpacity(value)",
    "property real windowScale: 1.0",
    "function cycleWindowScale()",
    "windowScale === 1.0 ? 1.25 : windowScale === 1.25 ? 1.5 : 1.0",
    "scale: root.windowScale",
    "screen.width * root.windowScale",
    "id: scaleSelector",
    'text: "SCALE"',
    'text: "DISPLAY"',
    "onTapped: root.cycleWindowScale()",
    'text: "BRIGHT  " + Math.round(root.crtRasterOpacity * 100)',
    'text: "INTENSITY"',
    "id: controlShelf",
    'text: "LANTERN   MODEL ZM-80"',
    "root.adjustCrtRasterOpacity(event.angleDelta.y > 0 ? root.dialStep : -root.dialStep)",
    "property real effectStrength: root.crtEffects ? 1.0 : 0.0",
    "property real rasterOpacity: root.crtRasterOpacity",
    'themeColorsPath: homePath + "/.local/state/omarchy/current/theme/colors.toml"',
    "function loadThemePalette(raw)",
    "function cyclePhosphor()",
    "function triggerChannelGlitch()",
    "channelSwitchGlitch.restart()",
    'text: "COLOR  " + root.phosphorLabel',
    'text: "PHOSPHOR"',
    'text: gameProc.running ? "SIGNAL" : "STANDBY"',
    'text: "CRT color: " + (root.phosphor === "theme" ? "Omarchy theme" : root.phosphor)',
    "onTapped: root.cyclePhosphor()",
    "onClosed:",
    "property bool nativeClosePending: false",
    "readonly property var window: windowLoader.item",
    "if (!windowLoader.active) windowLoader.active = true",
    "windowLoader.active = false",
    'windowStateHelper: pluginRoot + "/bin/window-state"',
    'command: [root.windowStateHelper, "save"]',
    "function checkpointWindowPosition()",
    "id: windowStateCheckpointTimer",
    "id: windowStateCheckpoint",
    "else root.checkpointWindowPosition()",
    'command: [root.windowStateHelper, "prepare"]',
    'command: [root.windowStateHelper, "clear"]',
    "anchors.leftMargin: 52",
    "anchors.topMargin: 40",
    "stdinEnabled: true",
    "runtime/x86_64-linux/dfrotz",
    '"-R"',
    "textFormat: Text.PlainText"
  ]) assert.match(source, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.match(source, /FloatingWindow \{[\s\S]*visible: false[\s\S]*color: "#ff141512"/)
  assert.match(source, /id: terminalShell[\s\S]*opacity: 1\.0[\s\S]*color: "#ff141512"/)
  assert.doesNotMatch(source, /PanelWindow/)
  assert.doesNotMatch(source, /WlrLayershell|WlrKeyboardFocus|ExclusionMode/)
})

test("panel provides engine-aware save and restore controls", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const overlay = fs.readFileSync(path.join(root, "SaveLoadOverlay.qml"), "utf8")

  for (const required of [
    'import Qt.labs.folderlistmodel',
    'nameFilters: ["*" + root.saveExtension]',
    'saveMode === "scottfree" ? ".sav" : ".qzl"',
    'function beginSave(recorded, requestedName)',
    'function beginLoad(recorded, requestedName)',
    'function completeSave(raw, overwriteConfirmed)',
    'function completeLoad(raw)',
    'function normalizeCurrentSaveName(raw)',
    'saveRoot + "/scottfree/" + cartridge.id',
    'command.match(/^(save|restore|load)',
    'gameProc.write("save\\n" + stem + "\\n"',
    'writeGameInput("restore\\n" + existing + "\\n", "restore")',
    '{ label: "SAVE  ^S", action: "save" }',
    '{ label: "LOAD  ^L", action: "load" }',
    'event.key === Qt.Key_S',
    'event.key === Qt.Key_L',
    'SaveLoadOverlay'
  ]) assert.ok(panel.includes(required), `missing save/load contract: ${required}`)

  for (const required of [
    'MEMORY BANK  //  SAVE GAME',
    'MEMORY BANK  //  RESTORE GAME',
    'ENTER  WRITE SAVE',
    'ENTER  RESTORE',
    'onDoubleTapped: controller.completeLoad(parent.fileName)'
  ]) assert.ok(overlay.includes(required), `missing save/load overlay contract: ${required}`)
})

test("staged launcher imports only validated managed cartridge formats", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const engineMenu = fs.readFileSync(path.join(root, "EngineMenu.qml"), "utf8")
  const cartridgeMenu = fs.readFileSync(path.join(root, "CartridgeMenu.qml"), "utf8")
  const helper = path.join(root, "bin/lantern-cartridge")
  const fixtureRoot = fs.mkdtempSync(path.join(root, ".test-cartridge-"))
  const library = path.join(fixtureRoot, "library")

  try {
    for (const required of [
      "id: cartridgePicker", '"zenity", "--file-selection"', "function beginCartridgeImport()",
      'cartridgeHelper: pluginRoot + "/bin/lantern-cartridge"',
      'root.importEngineId === "scottfree" ? "import-scott" : "import-zmachine"',
      'root.pendingCartridge.engine === "scottfree" ? "check-scott" : "check-zmachine"',
      '"--file-filter=Scott Adams databases | *.dat"',
      '"--file-filter=Z-machine stories | *.z1 *.z2 *.z3 *.z4 *.z5 *.z6 *.z7 *.z8"'
    ]) assert.ok(panel.includes(required), `missing import contract: ${required}`)

    for (const required of [
      "controller.lanternLogo", "SELECT AN ENGINE", "controller.enterSelectedEngine()",
      "UP/DOWN  SELECT"
    ]) assert.ok(engineMenu.includes(required), `missing engine menu contract: ${required}`)

    for (const required of [
      "SELECT A CARTRIDGE", "+  IMPORT CARTRIDGE", "controller.backToEngines()",
      "controller.beginCartridgeImport()", "ESC/LEFT  ENGINES"
    ]) assert.ok(cartridgeMenu.includes(required), `missing cartridge menu contract: ${required}`)
    assert.ok(panel.includes('action: "empty", number: "--", title: "NO CARTRIDGES LOADED"'))
    assert.ok(panel.includes('statusText = "NO CARTRIDGES  /  PRESS I TO IMPORT"'))

    const imported = spawnSync(helper, ["import-zmachine", path.join(root, "games/zork1.z3"), library], { encoding: "utf8" })
    assert.equal(imported.status, 0, imported.stderr)
    assert.equal(imported.stdout.trim(), "zork1.z3")
    const managed = path.join(library, "zork1.z3")
    assert.equal(fs.statSync(managed).isFile(), true)
    assert.equal(spawnSync(helper, ["check-zmachine", managed, library]).status, 0)
    assert.notEqual(spawnSync(helper, ["check-zmachine", path.join(root, "games/zork1.z3"), library]).status, 0)

    const scottImport = spawnSync(helper, ["import-scott", path.join(root, "tests/fixtures/minimal-scott.dat"), library], { encoding: "utf8" })
    assert.equal(scottImport.status, 0, scottImport.stderr)
    assert.equal(scottImport.stdout.trim(), "minimal-scott.dat")
    const managedScott = path.join(library, "minimal-scott.dat")
    assert.equal(spawnSync(helper, ["check-scott", managedScott, library]).status, 0)
    assert.notEqual(spawnSync(helper, ["check-scott", managed, library]).status, 0)

    const invalid = path.join(fixtureRoot, "invalid.z3")
    const linked = path.join(fixtureRoot, "linked.z3")
    fs.writeFileSync(invalid, "not a story")
    fs.symlinkSync(path.join(root, "games/zork1.z3"), linked)
    assert.notEqual(spawnSync(helper, ["import-zmachine", invalid, library]).status, 0)
    assert.notEqual(spawnSync(helper, ["import-zmachine", linked, library]).status, 0)
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true })
  }
})

test("ScottFree bounds action parameters and confines save files", () => {
  const runtime = path.join(root, "runtime/x86_64-linux/scottfree")
  const story = path.join(root, "tests/fixtures/minimal-scott.dat")
  const fixture = fs.readFileSync(story, "utf8")
  const fixtureRoot = fs.mkdtempSync(path.join(root, ".test-scottfree-"))
  const stateRoot = path.join(fixtureRoot, "state")
  const runtimeArgs = (key, game = story) => ["--save-root", stateRoot, "--save-key", key, "-w", game]
  fs.mkdirSync(stateRoot)

  try {
    for (const [opcode, category] of [[7800, "item"], [8100, "room"], [8700, "flag"], [12150, "counter slot"], [13050, "saved room slot"]]) {
      const malicious = path.join(fixtureRoot, `bad-${opcode}.dat`)
      fs.writeFileSync(malicious, fixture.replace(
        "900 0 0 0 0 0 10650 0",
        `900 10000 0 0 0 0 ${opcode} 0`
      ))
      const result = spawnSync(runtime, runtimeArgs("bounds-test", malicious), {
        input: "save\n", encoding: "utf8", timeout: 5000
      })
      assert.match(result.stdout, new RegExp(`${category} parameter out of range`))
      assert.equal(result.signal, null)
    }

    const boundaryFlag = path.join(fixtureRoot, "boundary-flag.dat")
    fs.writeFileSync(boundaryFlag, fixture.replace(
      "900 0 0 0 0 0 10650 0",
      "900 1260 0 0 0 0 8700 0"
    ))
    const boundaryResult = spawnSync(runtime, runtimeArgs("bounds-test", boundaryFlag), {
      input: "save\n", encoding: "utf8", timeout: 5000
    })
    assert.match(boundaryResult.stdout, /flag parameter out of range/)
    assert.equal(boundaryResult.signal, null)

    const tooFew = path.join(fixtureRoot, "too-few.dat")
    fs.writeFileSync(tooFew, fixture.replace(
      "900 0 0 0 0 0 10650 0",
      "900 0 11 11 11 11 10800 0"
    ))
    const tooFewResult = spawnSync(runtime, runtimeArgs("bounds-test", tooFew), {
      input: "save\n", encoding: "utf8", timeout: 5000
    })
    assert.match(tooFewResult.stdout, /action has too few parameters/)
    assert.equal(tooFewResult.signal, null)

    const linkedRoot = path.join(fixtureRoot, "linked-root")
    fs.symlinkSync(stateRoot, linkedRoot)
    const rootResult = spawnSync(runtime, ["--save-root", linkedRoot, "--save-key", "root-test", "-w", story], {
      input: "look\n", encoding: "utf8", timeout: 5000
    })
    assert.notEqual(rootResult.status, 0)
    assert.match(rootResult.stderr, /save root is unavailable or unsafe/)

    const unsafeState = path.join(fixtureRoot, "unsafe-state")
    const outsideDirectory = path.join(fixtureRoot, "outside-directory")
    fs.mkdirSync(path.join(unsafeState, "lantern"), { recursive: true })
    fs.mkdirSync(outsideDirectory)
    fs.symlinkSync(outsideDirectory, path.join(unsafeState, "lantern/saves"))
    const intermediateResult = spawnSync(runtime,
      ["--save-root", unsafeState, "--save-key", "intermediate-test", "-w", story],
      { input: "save\nslot\n", encoding: "utf8", timeout: 5000 })
    assert.notEqual(intermediateResult.status, 0)
    assert.match(intermediateResult.stderr, /save directory is unavailable or unsafe/)
    assert.deepEqual(fs.readdirSync(outsideDirectory), [])

    const saveDirectory = path.join(stateRoot, "lantern/saves/scottfree/bounds-test")
    const outside = path.join(fixtureRoot, "outside.sav")
    const linkedSave = path.join(saveDirectory, "slot.sav")
    fs.writeFileSync(outside, "sentinel")
    fs.symlinkSync(outside, linkedSave)
    const saveResult = spawnSync(runtime, runtimeArgs("bounds-test"), {
      input: "save\nslot\n", encoding: "utf8", timeout: 5000
    })
    assert.equal(fs.readFileSync(outside, "utf8"), "sentinel")
    assert.doesNotMatch(saveResult.stdout, /Saved\./)

    for (const key of ["cartridge-one", "cartridge-two"])
      spawnSync(runtime, runtimeArgs(key), { input: "save\nshared\n", encoding: "utf8", timeout: 5000 })
    assert.ok(fs.statSync(path.join(stateRoot, "lantern/saves/scottfree/cartridge-one/shared.sav")).isFile())
    assert.ok(fs.statSync(path.join(stateRoot, "lantern/saves/scottfree/cartridge-two/shared.sav")).isFile())
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true })
  }
})

test("release contains self-contained x86-64 engines and factory cartridges", () => {
  const runtime = path.join(root, "runtime/x86_64-linux/dfrotz")
  const adventureRuntime = path.join(root, "runtime/x86_64-linux/advent")
  const scottFreeRuntime = path.join(root, "runtime/x86_64-linux/scottfree")
  const cartridgeHelper = path.join(root, "bin/lantern-cartridge")
  const stories = ["zork1.z3", "zork2.z3", "zork3.z3"]
    .map(file => path.join(root, "games", file))
  const windowStateHelper = path.join(root, "bin/window-state")

  for (const required of [
    runtime,
    adventureRuntime,
    scottFreeRuntime,
    cartridgeHelper,
    ...stories,
    windowStateHelper,
    path.join(root, "THIRD_PARTY_NOTICES.md"),
    path.join(root, "third_party/frotz/COPYING"),
    path.join(root, "third_party/frotz/BUILD.md"),
    path.join(root, "third_party/frotz/source/frotz-2.55.tar.gz"),
    path.join(root, "bin/read-bounded-file"),
    path.join(root, "bin/read-bounded-file.c"),
    path.join(root, "scripts/build-bounded-reader"),
    path.join(root, "docs/read-bounded-file-provenance.md"),
    path.join(root, "bin/lantern-map-state"),
    path.join(root, "bin/lantern-map-state.c"),
    path.join(root, "scripts/build-map-state-helper"),
    path.join(root, "docs/map-state-helper.md"),
    path.join(root, "third_party/zork1/LICENSE"),
    path.join(root, "third_party/zork2/LICENSE"),
    path.join(root, "third_party/zork3/LICENSE"),
    path.join(root, "third_party/open-adventure/COPYING"),
    path.join(root, "third_party/open-adventure/BUILD.md"),
    path.join(root, "third_party/open-adventure/lantern-terminal.patch"),
    path.join(root, "third_party/open-adventure/source/open-adventure-1.22.tar.gz"),
    path.join(root, "scripts/build-open-adventure"),
    path.join(root, "third_party/scottfree/COPYING"),
    path.join(root, "third_party/scottfree/BUILD.md"),
    path.join(root, "third_party/scottfree/source/scottfree-glk-b69a8498.tar.gz"),
    path.join(root, "third_party/scottfree/lantern-safety.patch"),
    path.join(root, "third_party/scottfree/stdio-glk/stdio-glk.c"),
    path.join(root, "scripts/build-scottfree"),
    path.join(root, "scripts/build-cartridge-helper"),
    path.join(root, "third_party/SHA256SUMS")
  ]) assert.equal(fs.existsSync(required), true, `missing ${path.relative(root, required)}`)

  assert.equal(fs.statSync(runtime).mode & 0o111, 0o111, "bundled dfrotz must be executable")
  assert.equal(fs.statSync(adventureRuntime).mode & 0o111, 0o111, "bundled advent must be executable")
  assert.equal(fs.statSync(scottFreeRuntime).mode & 0o111, 0o111, "bundled scottfree must be executable")
  assert.equal(fs.statSync(cartridgeHelper).mode & 0o111, 0o111, "cartridge helper must be executable")
  assert.equal(fs.statSync(windowStateHelper).mode & 0o111, 0o111, "window state helper must be executable")
  assert.equal(fs.statSync(path.join(root, "bin/read-bounded-file")).mode & 0o111, 0o111, "bounded reader must be executable")
  assert.equal(fs.statSync(path.join(root, "bin/lantern-map-state")).mode & 0o111, 0o111, "map-state helper must be executable")
  assert.deepEqual([...fs.readFileSync(runtime).subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  assert.deepEqual([...fs.readFileSync(adventureRuntime).subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  assert.deepEqual([...fs.readFileSync(scottFreeRuntime).subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  assert.deepEqual([...fs.readFileSync(cartridgeHelper).subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  for (const story of stories)
    assert.equal(fs.readFileSync(story)[0], 3, `${path.basename(story)} must be a V3 story`)
})

test("third-party checksum inventory covers every distributed upstream artifact", () => {
  const inventory = fs.readFileSync(path.join(root, "third_party/SHA256SUMS"), "utf8")
    .trim().split("\n").map(line => line.match(/^([0-9a-f]{64})  (.+)$/))
  assert.equal(inventory.every(Boolean), true, "checksum inventory has malformed lines")

  const covered = new Set()
  for (const [, expected, relative] of inventory) {
    const file = path.join(root, relative)
    assert.equal(fs.existsSync(file), true, `missing checksummed file ${relative}`)
    const actual = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")
    assert.equal(actual, expected, `checksum mismatch for ${relative}`)
    covered.add(relative)
  }

  for (const relative of [
    "runtime/x86_64-linux/dfrotz",
    "runtime/x86_64-linux/advent",
    "runtime/x86_64-linux/scottfree",
    "bin/read-bounded-file",
    "bin/lantern-cartridge",
    "bin/lantern-cartridge.c",
    "bin/lantern-map-state",
    "bin/lantern-map-state.c",
    "bin/read-bounded-file.c",
    "games/zork1.z3",
    "games/zork2.z3",
    "games/zork3.z3",
    "third_party/frotz/source/frotz-2.55.tar.gz",
    "third_party/frotz/lantern-room-events.patch",
    "scripts/build-frotz",
    "third_party/open-adventure/source/open-adventure-1.22.tar.gz",
    "third_party/open-adventure/COPYING",
    "third_party/open-adventure/generated/dungeon.c",
    "third_party/open-adventure/generated/dungeon.h",
    "third_party/open-adventure/lantern-terminal.patch",
    "third_party/scottfree/source/scottfree-glk-b69a8498.tar.gz",
    "third_party/scottfree/COPYING",
    "third_party/scottfree/lantern-safety.patch",
    "third_party/scottfree/stdio-glk/glk.h",
    "third_party/scottfree/stdio-glk/glkstart.h",
    "third_party/scottfree/stdio-glk/stdio-glk.c"
  ]) assert.equal(covered.has(relative), true, `checksum inventory omits ${relative}`)
})

test("panel launches only bundled or validated managed cartridges", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  assert.match(source, /Qt\.resolvedUrl\("\."\)/)
  assert.match(source, /runtime\/x86_64-linux\/dfrotz/)
  assert.match(source, /games\/zork1\.z3/)
  assert.match(source, /games\/zork2\.z3/)
  assert.match(source, /games\/zork3\.z3/)
  assert.match(source, /title: "ZORK II"/)
  assert.match(source, /title: "ZORK III"/)
  assert.match(source, /title: "COLOSSAL CAVE ADVENTURE"/)
  assert.match(source, /runtime\/x86_64-linux\/advent/)
  assert.match(source, /runtime\/x86_64-linux\/scottfree/)
  assert.match(source, /"check-scott" : "check-zmachine"/)
  assert.doesNotMatch(source, /\["dfrotz"/)
  assert.doesNotMatch(source, /Install the Arch package/)
})

test("release bundles the Qt 6 CRT shader and an effects-off fallback", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  const shaderSource = fs.readFileSync(path.join(root, "shaders/crt.frag"), "utf8")
  const shaderPack = fs.readFileSync(path.join(root, "shaders/crt.frag.qsb"))

  assert.equal(manifest.version, "0.2.0")
  for (const required of [
    "property bool crtEffects: true",
    "payload.effects === true || payload.effects === false",
    "running: root.opened && root.crtEffects",
    "ShaderEffectSource",
    "visible: false",
    "hideSource: root.crtEffects",
    "live: root.crtEffects",
    "visible: root.crtEffects",
    'fragmentShader: Qt.resolvedUrl("shaders/crt.frag.qsb")',
    "if (root.opened && window && window.visible) root.focusCurrentView()",
    "wrapMode: Text.NoWrap",
    "TapHandler"
  ]) assert.match(panel, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.doesNotMatch(panel, /MouseArea\s*\{[\s\S]*?z:\s*21/)

  for (const required of [
    "#version 440", "curvature", "scanline", "bloom", "vignette", "grain",
    "rasterOpacity", "rasterStrength", "rasterGain", "lineWeave", "scanDepth", "lineEnergy", "refreshBand", "refreshWake", "powerFlutter",
    "channelGlitch", "channelGlitchSeed", "stackRow", "stackGate", "channelKick",
    "frameSurface", "tubeWell", "edgePixels", "frameOpening", "glassOpening", "frameRidge"
  ])
    assert.match(shaderSource, new RegExp(required))
  assert.ok(shaderPack.length > 0, "compiled CRT shader pack must not be empty")
})

test("panel serializes startup around one immutable checked cartridge", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  for (const required of [
    "property bool startPending: false",
    "property string pendingStoryPath: \"\"",
    "property var pendingCartridge: null",
    "if (!cartridge || gameProc.running || startPending) return",
    "launchCartridge(cartridge)",
    "Model.bundledStoryPath(payload.story || \"\"",
    "Model.bundledCartridgeId(payload.cartridge || \"\"",
    "root.pendingCartridge.source === \"imported\"",
    "root.pendingStoryPath"
  ]) assert.match(source, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.doesNotMatch(source, /Model\.safeStoryPath|storyPath\s*=\s*requested/)
  assert.doesNotMatch(source, /summon it with another absolute story path/)
})
