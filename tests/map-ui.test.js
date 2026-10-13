const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")
const canvasPath = path.join(root, "MapCanvas.qml")
const renderPath = path.join(root, "MapRender.js")
const overlayPath = path.join(root, "MapOverlay.qml")
const previewPath = path.join(root, "tests/manual/MapPreview.qml")

function source(file) { return fs.readFileSync(file, "utf8") }

test("standalone automap ships only its blank physical paper asset", () => {
  const canvas = source(canvasPath)
  const overlay = source(overlayPath)
  const paper = path.join(root, "assets/old-graph-paper.png")

  assert.equal(fs.existsSync(paper), true)
  assert.equal(fs.readFileSync(paper).subarray(1, 4).toString("ascii"), "PNG")
  assert.match(overlay, /assets\/old-graph-paper\.png/)
  for (const forbidden of ["map-concept-open", "map-concept-closed", "zork-rough-map"])
    assert.equal(canvas.includes(forbidden) || overlay.includes(forbidden), false, forbidden)
})

test("MapCanvas keeps immutable graph truth separate from viewport and session location", () => {
  const qml = source(canvasPath)
  for (const contract of [
    "required property var mapState", "property string currentNodeId", "property bool interactionEnabled",
    "property real zoom: 0.85", "property real panX", "property real panY", "property real renderScale",
    "property bool viewportUserAdjusted", "readonly property real minimumZoom: 0.55",
    "readonly property real maximumZoom: 1.35", "readonly property real defaultMaximumZoom: 0.88",
    "readonly property rect worldBounds", "readonly property int placedNodeCount",
    "readonly property int unplacedNodeCount", "readonly property string accessibleSummary",
    "signal viewportChanged(real panX, real panY, real zoom)", "signal interactionStarted()",
    "function invalidateGraph()", "function panBy(", "function setZoom(", "function zoomBy(",
    "function centerCurrent()", "function fitGraph()", "function resetView()", "function clampViewport()",
    "function geometrySnapshot()"
  ]) assert.ok(qml.includes(contract), contract)

  assert.match(qml, /import "MapRender\.js" as MapRender/)
  assert.match(qml, /Canvas\s*\{[\s\S]*anchors\.fill: parent/)
  assert.match(qml, /renderStrategy: Canvas\.Threaded/)
  assert.match(qml, /canvasSize: Qt\.size\(width \* map\.effectiveRenderScale/)
  assert.match(qml, /if \(state\.nodes\.length > 4096 \|\| state\.edges\.length > 16384\)/)
  assert.doesNotMatch(qml, /Math\.random/)
  assert.doesNotMatch(qml, /mapState\s*\.[A-Za-z_$][\w$]*\s*=/)

  const centerCurrent = qml.slice(qml.indexOf("function centerCurrent()"), qml.indexOf("function fitGraph()"))
  const resetView = qml.slice(qml.indexOf("function resetView()"), qml.indexOf("function clampViewport()"))
  assert.doesNotMatch(centerCurrent, /zoom\s*=/, "centering must preserve zoom")
  assert.match(resetView, /viewportUserAdjusted = false[\s\S]*fitGraph\(\)/)
  assert.match(qml, /MapRender\.fitViewport\(cachedGeometry\.bounds, width, height/)
  assert.match(qml, /MapRender\.clampViewport\(cachedGeometry\.bounds, width, height, zoom, panX, panY\)/)
  assert.match(qml, /DragHandler \{[\s\S]*acceptedButtons: Qt\.LeftButton[\s\S]*acceptedDevices: PointerDevice\.Mouse[\s\S]*map\.viewportUserAdjusted = true[\s\S]*map\.emitViewport\(\)/)
  assert.match(qml, /cursorShape: mapDrag\.active \? Qt\.ClosedHandCursor : Qt\.OpenHandCursor/)
})

test("MapCanvas renders bounded hand-drawn graph grammar with culling", () => {
  const qml = source(canvasPath)
  for (const contract of [
    "positionedNodes", "MapRender.planNodeLayout", "parallelOffset", "selfLoop", "plannedEdge.hasReverse", "oneWay",
    "routeLabel", "UNPLACED / CONFIRMED", "HERE", "strokeRoute",
    "Paper-colored under-stroke", "visibleWorldBounds", "intersects(route.bounds",
    "for (var routeIndex", "for (var nodeIndex", "boundedString(source.label, 128)",
    'source.confidence !== "confirmed"'
  ]) assert.ok(qml.includes(contract), contract)

  assert.ok(qml.indexOf("for (var routeIndex") < qml.indexOf("for (var nodeIndex"),
    "routes must paint before room boxes")
  for (const color of ["#D8D1BE", "#423E38", "#5B5349", "#7898A8"])
    assert.ok(qml.includes(color), color)
  assert.match(qml, /node\.anchorX = position\.x \* 148 \+ position\.z \* 46/)
  assert.match(qml, /node\.anchorY = position\.y \* 106 - position\.z \* 72/)
  assert.match(qml, /var nodeLayout = MapRender\.planNodeLayout\(positionedNodes\)/)
  assert.match(qml, /MapRender\.roomOrder\(a\.id\) - MapRender\.roomOrder\(b\.id\)/)
  assert.match(qml, /var edgePlan = MapRender\.planEdges\(confirmedEdges\)/)
  assert.match(qml, /MapRender\.routeInset\(fromNode\.width, fromNode\.height, dx, dy, 6\)/)
  assert.match(qml, /MapRender\.routeInset\(toNode\.width, toNode\.height, dx, dy, 6\)/)
  assert.doesNotMatch(qml, /Math\.min\(fromNode\.width \/ 2, fromNode\.height \/ 2\)/)
  assert.match(qml, /selfLoop: true, oneWay: true/)
  assert.doesNotMatch(qml, /reverseIndex|for \([^)]*pairEdges\.length[^)]*\)[\s\S]*hasReverse = true/)

  const render = source(renderPath)
  assert.match(render, /source\.from !== source\.to && endpoints\[endpointKey\(source\.to, source\.from\)\]/)
  assert.match(render, /duplicate directed edge/)
  assert.match(render, /orderedExitLabels/)
})

test("MapOverlay exposes modal lifecycle, paper geometry, controls, and viewport memory", () => {
  const qml = source(overlayPath)
  for (const contract of [
    "required property var mapState", "property string currentNodeId", "property string sessionKey",
    "property string mapTitle", "property bool available", "property bool reduceMotion",
    "property bool resetEnabled", "property string unavailableReason", "property real renderScale",
    "property url paperSource", "property rect crtRect", "property real dragStripHeight",
    "readonly property string motionState", "readonly property bool modal",
    "readonly property string accessibleSummary", "signal opening", "signal opened", "signal closing",
    "signal closed", "signal viewportChanged", "signal resetMapRequested",
    "signal unavailableActivated", "signal focusRestoreRequested", "signal transitionSoundRequested",
    "function openMap", "function closeMap", "function toggleMap", "function forceClosed",
    "function focusCurrent", "function centerCurrent", "function resetView"
  ]) assert.ok(qml.includes(contract), contract)

  for (const geometry of [
    "readonly property real logicalWidth: 1020", "readonly property real logicalHeight: 765",
    "readonly property real closedRotation: 0.9", "readonly property real openRotation: 1.4",
    "x: -854", "paper.x = 46", "y: 29",
    "width: 914", "height: 682", "x: 82", "y: 123", "width: 750", "height: 456",
    "x: parent.width - 68", "width: 44", "height: 100", "width: 92", "id: mapTabLabel",
    "paper.rotation = openRotation"
  ]) assert.ok(qml.includes(geometry), geometry)

  for (const state of ["\"closed\"", "\"opening\"", "\"open\"", "\"closing\""])
    assert.ok(qml.includes(state), state)
  for (const timing of ["duration: 340", "duration: 90", "duration: 80", "Math.max(120", "Math.min(maximum"])
    assert.ok(qml.includes(timing), timing)
  for (const control of ["CENTER", "RESET VIEW", "ERASE MAP", "ERASE? AGAIN", "CLOSE"])
    assert.ok(qml.includes(control), control)
  for (const note of ["arrows — pan", "+ / − — zoom", "0 — reset", "esc — close"])
    assert.ok(qml.includes(note), note)
  for (const inset of ["anchors.leftMargin: 54", "anchors.rightMargin: 54", "anchors.topMargin: 36", "anchors.topMargin: 40", "anchors.topMargin: 70", "anchors.bottomMargin: 40", "anchors.bottomMargin: 38"])
    assert.ok(qml.includes(inset), inset)
  assert.match(qml, /MouseArea\s*\{[\s\S]*id: modalBlocker/)
  assert.match(qml, /y: Math\.max\(0, overlay\.dragStripHeight\)/)
  assert.match(qml, /visible: !overlay\.available && tabHover\.hovered/)
  const tabVisual = qml.slice(qml.indexOf("id: paperTabHitTarget"), qml.indexOf("HoverHandler { id: tabHover"))
  assert.match(tabVisual, /Text \{[\s\S]*id: mapTabLabel/)
  assert.doesNotMatch(tabVisual, /Rectangle \{|border\.|color: "#C9C0AA"/)
  assert.match(qml, /Parent-window drag handling remains above this/)
  assert.match(qml, /event\.key === Qt\.Key_P && \(event\.modifiers & Qt\.ControlModifier\)[\s\S]*!event\.isAutoRepeat\) overlay\.toggleMap\(true\)/)
  assert.match(qml, /event\.key === Qt\.Key_Escape[\s\S]*overlay\.eraseArmed[\s\S]*overlay\.cancelErase\(\)[\s\S]*overlay\.closeMap\(true\)/)
  assert.match(qml, /event\.key === Qt\.Key_0[\s\S]*mapCanvas\.resetView\(\)/)
  for (const direction of ["Left", "Right", "Up", "Down", "Shift+Left", "Shift+Right", "Shift+Up", "Shift+Down"])
    assert.match(qml, new RegExp(`Shortcut \\{ sequence: "${direction.replace("+", "\\+")}"; context: Qt\\.WindowShortcut; enabled: overlay\\.modalActive`))
  assert.doesNotMatch(qml, /if \(event\.isAutoRepeat\) \{ event\.accepted = true; return \}/)
  assert.equal((qml.match(/if \(!event\.isAutoRepeat/g) || []).length, 4,
    "Ctrl+P, Escape, paper tab, and reusable buttons must suppress activation repeats")
  assert.match(qml, /layer\.effect: MultiEffect \{[\s\S]*brightness: -0\.16[\s\S]*shadowEnabled: true[\s\S]*shadowBlur: 1\.0[\s\S]*blurMax: 64/)
  assert.doesNotMatch(qml, /id: paperShadow|layer\.sourceRect|QtQuick\.Controls|ShaderEffectSource/)
})

test("MapCanvas consumes wheel input and uses trackpad deltas only for Ctrl+zoom", () => {
  const qml = source(canvasPath)
  assert.match(qml, /event\.pixelDelta\.y !== 0 \? event\.pixelDelta\.y : event\.angleDelta\.y/)
  assert.match(qml, /if \(event\.modifiers & Qt\.ControlModifier\)/)
  assert.doesNotMatch(qml, /else map\.panBy\(event\.angleDelta/)
  assert.match(qml, /event\.accepted = true/)
})

test("map UI bounds story text to plain Canvas or Text rendering", () => {
  const qml = source(canvasPath) + source(overlayPath)
  assert.doesNotMatch(qml, /RichText|StyledText|createQmlObject|Qt\.createComponent/)
  const textBlockCount = (qml.match(/\bText\s*\{/g) || []).length
  const plainTextCount = (qml.match(/textFormat:\s*Text\.PlainText/g) || []).length
  assert.equal(textBlockCount, 10, "nine fixed labels plus one reusable button label")
  assert.equal(plainTextCount, textBlockCount, "every Text item must use Text.PlainText")
})

test("manual preview exercises dense graph edge cases and offscreen capture", () => {
  const qml = source(previewPath)
  for (const contract of [
    "import \"../..\" as Lantern", "Lantern.MapOverlay", "--capture",
    "../../assets/map-preview.png", "grabToImage", "Qt.quit()", "Qt.Key_P", "Qt.ControlModifier",
    "Qt.Key_R", "previewScale", "room-16", "Echo Chamber (Unplaced)",
    'from: "room-10", to: "room-10"', 'from: "room-10", to: "room-11"'
  ]) assert.ok(qml.includes(contract), contract)
})
