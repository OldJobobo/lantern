import QtQuick
import "MapRender.js" as MapRender

Item {
  id: map

  // Public model contract. The graph is treated as immutable input; the active
  // room remains session-local and is supplied separately.
  required property var mapState
  property string currentNodeId: ""
  property bool interactionEnabled: true
  property real zoom: 0.85
  property real panX: 0
  property real panY: 0
  property real renderScale: 1.0
  property bool viewportUserAdjusted: false
  readonly property real minimumZoom: 0.55
  readonly property real maximumZoom: 1.35
  readonly property real defaultMaximumZoom: 0.88
  readonly property real effectiveRenderScale: isFinite(renderScale) ? Math.max(1, Math.min(3, renderScale)) : 1
  // Compatibility aliases for the interrupted prototype; new hosts use zoom.
  property alias viewScale: map.zoom
  readonly property real minimumScale: minimumZoom
  readonly property real maximumScale: maximumZoom
  property color paperColor: "#D8D1BE"
  property color graphiteColor: "#423E38"
  property color graphiteSecondary: "#5B5349"
  property color gridColor: "#7898A8"

  readonly property rect worldBounds: Qt.rect(cachedGeometry.bounds.left, cachedGeometry.bounds.top,
    cachedGeometry.bounds.right - cachedGeometry.bounds.left,
    cachedGeometry.bounds.bottom - cachedGeometry.bounds.top)
  readonly property int placedNodeCount: validGraph ? cachedGeometry.nodes.length - cachedGeometry.unplacedCount : 0
  readonly property int unplacedNodeCount: validGraph ? cachedGeometry.unplacedCount : 0
  readonly property string accessibleSummary: buildAccessibleSummary()
  readonly property bool validGraph: cachedGeometry.valid === true
  readonly property int visitedRoomCount: validGraph ? cachedGeometry.nodes.length : 0
  readonly property int confirmedRouteCount: validGraph ? cachedGeometry.routes.length : 0

  signal viewportChanged(real panX, real panY, real zoom)
  signal interactionStarted()

  property var cachedGeometry: ({
    valid: false,
    reason: "No map data yet",
    nodes: [],
    routes: [],
    nodeById: ({}),
    bounds: ({ left: -180, top: -120, right: 180, bottom: 120 }),
    unplacedCount: 0
  })
  property int geometryRevision: 0
  property real dragPreviousX: 0
  property real dragPreviousY: 0

  Accessible.role: Accessible.Pane
  Accessible.name: accessibleSummary
  clip: true

  onMapStateChanged: invalidateGraph()
  onCurrentNodeIdChanged: drawing.requestPaint()
  onPanXChanged: drawing.requestPaint()
  onPanYChanged: drawing.requestPaint()
  onZoomChanged: drawing.requestPaint()
  onRenderScaleChanged: drawing.requestPaint()
  onWidthChanged: { if (viewportUserAdjusted) clampViewport(); else fitGraph(); drawing.requestPaint() }
  onHeightChanged: { if (viewportUserAdjusted) clampViewport(); else fitGraph(); drawing.requestPaint() }
  Component.onCompleted: invalidateGraph()

  function boundedString(value, maximum) {
    var text = String(value === undefined || value === null ? "" : value)
    text = text.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
    return text.slice(0, maximum)
  }

  function hashText(value, seed) {
    var text = String(value || "")
    var hash = (Number(seed) >>> 0) || 2166136261
    for (var index = 0; index < text.length; index++) {
      hash ^= text.charCodeAt(index)
      hash = Math.imul(hash, 16777619)
    }
    return hash >>> 0
  }

  function seededUnit(value, seed, salt) {
    return (hashText(String(value) + ":" + String(salt), seed) % 10001) / 10000
  }

  function validDirection(direction) {
    return MapRender.EXIT_DIRECTIONS.indexOf(direction) !== -1
  }

  function finiteInteger(value, bound) {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value && Math.abs(value) <= bound
  }

  function buildGeometry() {
    var state = mapState
    var invalid = function(reason) {
      return {
        valid: false, reason: reason, nodes: [], routes: [], nodeById: ({}),
        bounds: ({ left: -180, top: -120, right: 180, bottom: 120 }), unplacedCount: 0
      }
    }
    if (!state || typeof state !== "object" || !Array.isArray(state.nodes) || !Array.isArray(state.edges) ||
        !state.layout || typeof state.layout !== "object" || !state.layout.positions ||
        typeof state.layout.positions !== "object") return invalid("No map data yet")
    if (state.nodes.length > 4096 || state.edges.length > 16384) return invalid("Map data is outside safe bounds")

    var seed = finiteInteger(state.layout.seed, 4294967295) && state.layout.seed > 0 ? state.layout.seed : 1
    var nodeById = {}
    var sourceNodes = []
    var positionedNodes = []
    var unplaced = []
    var index
    for (index = 0; index < state.nodes.length; index++) {
      var source = state.nodes[index]
      if (!source || typeof source !== "object" || source.confidence !== "confirmed" ||
          typeof source.id !== "string" || !/^room-[1-9]\d{0,9}$/.test(source.id) || nodeById[source.id])
        return invalid("Map data is unavailable")
      var label = boundedString(source.label, 128)
      if (label.length === 0) return invalid("Map data is unavailable")
      var position = state.layout.positions[source.id]
      var positioned = position && finiteInteger(position.x, 1000000) &&
        finiteInteger(position.y, 1000000) && finiteInteger(position.z, 1000000)
      var node = {
        id: source.id,
        label: label.toUpperCase(),
        positioned: positioned,
        x: 0,
        y: 0,
        width: 108,
        height: 58,
        rotation: (seededUnit(source.id, seed, "rotation") - 0.5) * 2.2,
        roughness: seededUnit(source.id, seed, "roughness")
      }
      nodeById[node.id] = node
      sourceNodes.push(node)
      if (positioned) {
        node.anchorX = position.x * 148 + position.z * 46
        node.anchorY = position.y * 106 - position.z * 72
        positionedNodes.push({
          id: node.id,
          anchorX: node.anchorX,
          anchorY: node.anchorY,
          width: node.width,
          height: node.height
        })
      } else unplaced.push(node)
    }

    var nodeLayout = MapRender.planNodeLayout(positionedNodes)
    if (!nodeLayout.valid) return invalid("Map layout is unavailable")
    for (index = 0; index < nodeLayout.nodes.length; index++) {
      var renderedNode = nodeLayout.nodes[index]
      var positionedSource = nodeById[renderedNode.id]
      positionedSource.x = renderedNode.x
      positionedSource.y = renderedNode.y
      positionedSource.displaced = renderedNode.displaced
      positionedSource.overflow = renderedNode.overflow
    }

    var left = Infinity
    var top = Infinity
    var right = -Infinity
    var bottom = -Infinity
    for (index = 0; index < sourceNodes.length; index++) {
      var positionedNode = sourceNodes[index]
      if (!positionedNode.positioned) continue
      left = Math.min(left, positionedNode.x - positionedNode.width / 2)
      top = Math.min(top, positionedNode.y - positionedNode.height / 2 - 18)
      right = Math.max(right, positionedNode.x + positionedNode.width / 2)
      bottom = Math.max(bottom, positionedNode.y + positionedNode.height / 2)
    }
    if (!isFinite(left)) { left = -180; top = -100; right = 180; bottom = 100 }

    // Confirmed but unplaced rooms remain explicit rather than being mixed into
    // inferred compass geometry.
    var rackX = right + 150
    var rackTop = top + 28
    unplaced.sort(function(a, b) {
      var order = MapRender.roomOrder(a.id) - MapRender.roomOrder(b.id)
      return order !== 0 ? order : a.id < b.id ? -1 : a.id > b.id ? 1 : 0
    })
    for (index = 0; index < unplaced.length; index++) {
      unplaced[index].x = rackX + (index % 2) * 126
      unplaced[index].y = rackTop + Math.floor(index / 2) * 76
      right = Math.max(right, unplaced[index].x + unplaced[index].width / 2 + 18)
      bottom = Math.max(bottom, unplaced[index].y + unplaced[index].height / 2 + 18)
    }
    if (unplaced.length > 0) {
      left = Math.min(left, rackX - 76)
      top = Math.min(top, rackTop - 58)
    }

    var confirmedEdges = []
    for (index = 0; index < state.edges.length; index++) {
      var edge = state.edges[index]
      if (!edge || edge.confirmed !== true || !nodeById[edge.from] || !nodeById[edge.to] ||
          !validDirection(edge.direction)) continue
      confirmedEdges.push({
        from: edge.from,
        to: edge.to,
        direction: edge.direction,
        command: boundedString(edge.command, 96),
        traversals: Math.max(1, Math.min(2147483647, Number(edge.traversals) || 1)),
        sourceIndex: index
      })
    }

    var edgePlan = MapRender.planEdges(confirmedEdges)
    if (!edgePlan.valid) return invalid("Map data contains duplicate routes")

    var pairGroups = {}
    for (index = 0; index < edgePlan.edges.length; index++) {
      var groupedEdge = edgePlan.edges[index]
      if (!pairGroups[groupedEdge.pairKey]) pairGroups[groupedEdge.pairKey] = []
      pairGroups[groupedEdge.pairKey].push(groupedEdge)
    }

    var routes = []
    var pairKeys = Object.keys(pairGroups).sort()
    for (var pairIndex = 0; pairIndex < pairKeys.length; pairIndex++) {
      var pairEdges = pairGroups[pairKeys[pairIndex]]
      pairEdges.sort(function(a, b) { return a.sortKey < b.sortKey ? -1 : a.sortKey > b.sortKey ? 1 : 0 })
      for (var edgeIndex = 0; edgeIndex < pairEdges.length; edgeIndex++) {
        var plannedEdge = pairEdges[edgeIndex]
        var routeEdge = plannedEdge.edge
        var fromNode = nodeById[routeEdge.from]
        var toNode = nodeById[routeEdge.to]
        var parallelOffset = (edgeIndex - (pairEdges.length - 1) / 2) * 13
        var route = buildRoute(fromNode, toNode, routeEdge, parallelOffset, plannedEdge.hasReverse, seed)
        routes.push(route)
        left = Math.min(left, route.bounds.left)
        top = Math.min(top, route.bounds.top)
        right = Math.max(right, route.bounds.right)
        bottom = Math.max(bottom, route.bounds.bottom)
      }
    }

    return {
      valid: true,
      reason: "",
      nodes: sourceNodes,
      routes: routes,
      nodeById: nodeById,
      bounds: ({ left: left - 54, top: top - 58, right: right + 54, bottom: bottom + 58 }),
      rack: unplaced.length > 0 ? ({ x: rackX - 76, y: rackTop - 48, width: right - rackX + 150, height: bottom - rackTop + 92 }) : null,
      unplacedCount: unplaced.length,
      seed: seed
    }
  }

  function buildRoute(fromNode, toNode, edge, offset, hasReverse, seed) {
    var selfLoop = fromNode.id === toNode.id
    if (selfLoop) {
      var loopSide = seededUnit(edge.from + edge.direction, seed, "loop") > 0.5 ? 1 : -1
      var loopX = fromNode.x + loopSide * (fromNode.width / 2 + 34)
      var loopY = fromNode.y - fromNode.height / 2 - 38 - Math.abs(offset)
      return {
        edge: edge, selfLoop: true, oneWay: true,
        x1: fromNode.x + loopSide * fromNode.width / 2, y1: fromNode.y - 8,
        cx1: loopX, cy1: fromNode.y - 8,
        cx2: loopX, cy2: loopY,
        x2: fromNode.x + loopSide * 18, y2: fromNode.y - fromNode.height / 2,
        label: routeLabel(edge.direction),
        bounds: ({ left: Math.min(fromNode.x, loopX) - 18, top: loopY - 18,
          right: Math.max(fromNode.x, loopX) + 18, bottom: fromNode.y + 18 })
      }
    }
    var dx = toNode.x - fromNode.x
    var dy = toNode.y - fromNode.y
    var length = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    var ux = dx / length
    var uy = dy / length
    var px = -uy
    var py = ux
    var fromInset = MapRender.routeInset(fromNode.width, fromNode.height, dx, dy, 6)
    var toInset = MapRender.routeInset(toNode.width, toNode.height, dx, dy, 6)
    var x1 = fromNode.x + ux * fromInset + px * offset
    var y1 = fromNode.y + uy * fromInset + py * offset
    var x2 = toNode.x - ux * toInset + px * offset
    var y2 = toNode.y - uy * toInset + py * offset
    var bend = (seededUnit(edge.from + edge.to + edge.direction, seed, "bend") - 0.5) * 18
    var middleX = (x1 + x2) / 2 + px * bend
    var middleY = (y1 + y2) / 2 + py * bend
    var cx1 = (x1 + middleX) / 2
    var cy1 = (y1 + middleY) / 2
    var cx2 = (x2 + middleX) / 2
    var cy2 = (y2 + middleY) / 2
    var anchor = MapRender.exitAnchor(fromNode.width, fromNode.height, edge.direction)
    // Only when the named side roughly faces the destination; a large mismatch
    // would loop the route around its own room, so that stays straight.
    if (anchor && anchor.ux * ux + anchor.uy * uy > 0.34) {
      // Leave from the named side, offset along it for parallel routes, then
      // curve in toward the destination along the straight approach.
      var reach = Math.min(56, Math.max(28, length * 0.4))
      x1 = fromNode.x + anchor.x - anchor.uy * offset
      y1 = fromNode.y + anchor.y + anchor.ux * offset
      cx1 = x1 + anchor.ux * reach
      cy1 = y1 + anchor.uy * reach
      cx2 = x2 - ux * reach
      cy2 = y2 - uy * reach
    }
    return {
      edge: edge, selfLoop: false, oneWay: !hasReverse,
      x1: x1, y1: y1,
      cx1: cx1, cy1: cy1,
      cx2: cx2, cy2: cy2,
      x2: x2, y2: y2,
      label: routeLabel(edge.direction),
      bounds: ({ left: Math.min(x1, x2, cx1, cx2) - 24, top: Math.min(y1, y2, cy1, cy2) - 24,
        right: Math.max(x1, x2, cx1, cx2) + 24, bottom: Math.max(y1, y2, cy1, cy2) + 24 })
    }
  }

  function routeLabel(direction) {
    if (direction === "up") return "U"
    if (direction === "down") return "D"
    if (direction === "in") return "IN"
    if (direction === "out") return "OUT"
    return ""
  }

  function invalidateGraph() {
    cachedGeometry = buildGeometry()
    geometryRevision++
    if (cachedGeometry.valid && !viewportUserAdjusted) fitGraph()
    else clampViewport()
    drawing.requestPaint()
  }

  function invalidateGeometry() { invalidateGraph() }

  // Stable, plain-data geometry for tests, diagnostics, and future renderers.
  function geometrySnapshot() {
    return JSON.parse(JSON.stringify(cachedGeometry))
  }

  function graphCenter() {
    var bounds = cachedGeometry.bounds
    return ({ x: (bounds.left + bounds.right) / 2, y: (bounds.top + bounds.bottom) / 2 })
  }

  function emitViewport() {
    viewportChanged(panX, panY, zoom)
  }

  function setViewport(nextPanX, nextPanY, nextZoom, userAdjusted) {
    zoom = Math.max(minimumZoom, Math.min(maximumZoom, Number(nextZoom) || defaultMaximumZoom))
    panX = isFinite(Number(nextPanX)) ? Number(nextPanX) : 0
    panY = isFinite(Number(nextPanY)) ? Number(nextPanY) : 0
    viewportUserAdjusted = userAdjusted === true
    clampViewport()
    emitViewport()
  }

  function panBy(dx, dy) {
    var deltaX = Number(dx)
    var deltaY = Number(dy)
    if (!isFinite(deltaX) || !isFinite(deltaY)) return
    panX += deltaX / zoom
    panY += deltaY / zoom
    viewportUserAdjusted = true
    clampViewport()
    emitViewport()
  }

  function panByPixels(dx, dy) { panBy(dx, dy) }

  function setZoom(value, anchorX, anchorY) {
    var oldZoom = zoom
    var nextZoom = Math.max(minimumZoom, Math.min(maximumZoom, Number(value)))
    if (!isFinite(nextZoom) || Math.abs(nextZoom - oldZoom) < 0.0001) return
    var centerX = width / 2
    var centerY = height / 2
    var screenX = isFinite(Number(anchorX)) ? Number(anchorX) : centerX
    var screenY = isFinite(Number(anchorY)) ? Number(anchorY) : centerY
    var worldX = (screenX - centerX) / oldZoom - panX
    var worldY = (screenY - centerY) / oldZoom - panY
    zoom = nextZoom
    panX = (screenX - centerX) / nextZoom - worldX
    panY = (screenY - centerY) / nextZoom - worldY
    viewportUserAdjusted = true
    clampViewport()
    emitViewport()
  }

  function zoomBy(factor, anchorX, anchorY) {
    setZoom(zoom * Number(factor), anchorX, anchorY)
  }

  function zoomAt(screenX, screenY, factor) { zoomBy(factor, screenX, screenY) }

  function centerCurrent() {
    var node = cachedGeometry.nodeById[currentNodeId]
    if (node) { panX = -node.x; panY = -node.y }
    else {
      var center = graphCenter()
      panX = -center.x
      panY = -center.y
    }
    viewportUserAdjusted = true
    clampViewport()
    emitViewport()
  }

  function fitGraph() {
    if (!cachedGeometry || !cachedGeometry.bounds || width <= 0 || height <= 0) return
    var fitted = MapRender.fitViewport(cachedGeometry.bounds, width, height,
      minimumZoom, maximumZoom, defaultMaximumZoom)
    panX = fitted.panX
    panY = fitted.panY
    zoom = fitted.zoom
    clampViewport()
  }

  function resetView() {
    viewportUserAdjusted = false
    fitGraph()
    emitViewport()
  }

  function clampViewport() {
    if (!cachedGeometry || !cachedGeometry.bounds || width <= 0 || height <= 0) return
    var clamped = MapRender.clampViewport(cachedGeometry.bounds, width, height, zoom, panX, panY)
    panX = clamped.panX
    panY = clamped.panY
  }

  function buildAccessibleSummary() {
    if (!cachedGeometry.valid) return cachedGeometry.reason
    var current = cachedGeometry.nodeById[currentNodeId]
    var room = current ? current.label : "NO CURRENT ROOM"
    var routeEdges = []
    for (var index = 0; index < cachedGeometry.routes.length; index++)
      routeEdges.push(cachedGeometry.routes[index].edge)
    var exits = MapRender.orderedExitLabels(routeEdges, currentNodeId)
    return "Current room: " + room + ". Confirmed exits: " +
      (exits.length ? exits.join(", ") : "none") + ". Visited rooms: " + cachedGeometry.nodes.length + "."
  }

  function visibleWorldBounds() {
    var halfWidth = width / (2 * zoom)
    var halfHeight = height / (2 * zoom)
    return ({ left: -panX - halfWidth - 36, top: -panY - halfHeight - 36,
      right: -panX + halfWidth + 36, bottom: -panY + halfHeight + 36 })
  }

  function intersects(a, b) {
    return a.right >= b.left && a.left <= b.right && a.bottom >= b.top && a.top <= b.bottom
  }

  function strokeRoute(context, route, color, width) {
    context.beginPath()
    context.moveTo(route.x1, route.y1)
    context.bezierCurveTo(route.cx1, route.cy1, route.cx2, route.cy2, route.x2, route.y2)
    context.strokeStyle = color
    context.lineWidth = width
    context.lineCap = "round"
    context.lineJoin = "round"
    context.stroke()
  }

  function routeEndTangent(route) {
    var dx = route.x2 - route.cx2
    var dy = route.y2 - route.cy2
    var length = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    return ({ x: dx / length, y: dy / length })
  }

  function paintRoute(context, route) {
    // Paper-colored under-stroke makes crossings read like separate pencil paths.
    strokeRoute(context, route, Qt.rgba(0.847, 0.82, 0.745, 0.88), 7.2)
    strokeRoute(context, route, graphiteSecondary, 2.1)
    strokeRoute(context, route, Qt.rgba(0.26, 0.243, 0.22, 0.34), 0.75)
    if (route.oneWay) {
      var tangent = routeEndTangent(route)
      var px = -tangent.y
      var py = tangent.x
      context.beginPath()
      context.moveTo(route.x2, route.y2)
      context.lineTo(route.x2 - tangent.x * 11 + px * 5, route.y2 - tangent.y * 11 + py * 5)
      context.moveTo(route.x2, route.y2)
      context.lineTo(route.x2 - tangent.x * 11 - px * 5, route.y2 - tangent.y * 11 - py * 5)
      context.strokeStyle = graphiteColor
      context.lineWidth = 2
      context.stroke()
    }
    if (route.label !== "") {
      context.save()
      context.font = "bold 10px monospace"
      context.textAlign = "center"
      context.textBaseline = "middle"
      context.fillStyle = paperColor
      context.fillRect((route.x1 + route.x2) / 2 - 12, (route.y1 + route.y2) / 2 - 9, 24, 18)
      context.fillStyle = graphiteColor
      context.fillText(route.label, (route.x1 + route.x2) / 2, (route.y1 + route.y2) / 2)
      context.restore()
    }
  }

  function splitLabel(context, label, maximumWidth) {
    if (context.measureText(label).width <= maximumWidth) return [label]
    var words = label.split(" ")
    var lines = [""]
    for (var index = 0; index < words.length; index++) {
      var candidate = lines[lines.length - 1] === "" ? words[index] : lines[lines.length - 1] + " " + words[index]
      if (context.measureText(candidate).width <= maximumWidth || lines.length === 2)
        lines[lines.length - 1] = candidate
      else lines.push(words[index])
    }
    if (lines[1] && context.measureText(lines[1]).width > maximumWidth) {
      while (lines[1].length > 1 && context.measureText(lines[1] + "…").width > maximumWidth)
        lines[1] = lines[1].slice(0, -1)
      lines[1] += "…"
    }
    return lines.slice(0, 2)
  }

  function paintRoom(context, node, current) {
    var left = node.x - node.width / 2
    var top = node.y - node.height / 2
    var jitter = function(salt) { return (seededUnit(node.id, cachedGeometry.seed, salt) - 0.5) * 3.8 }
    context.save()
    context.translate(node.x, node.y)
    context.rotate(node.rotation * Math.PI / 180)
    context.translate(-node.x, -node.y)
    context.beginPath()
    context.moveTo(left + jitter("a"), top + jitter("b"))
    context.lineTo(left + node.width + jitter("c"), top + jitter("d"))
    context.lineTo(left + node.width + jitter("e"), top + node.height + jitter("f"))
    context.lineTo(left + jitter("g"), top + node.height + jitter("h"))
    context.closePath()
    context.strokeStyle = graphiteColor
    context.lineWidth = current ? 2.7 : 2.1
    context.stroke()
    context.globalAlpha = 0.32
    context.strokeStyle = graphiteSecondary
    context.lineWidth = 0.8
    context.stroke()
    context.globalAlpha = 1
    if (current) {
      context.strokeStyle = graphiteSecondary
      context.lineWidth = 1.1
      context.strokeRect(left + 5, top + 5, node.width - 10, node.height - 10)
      context.beginPath()
      context.moveTo(left + node.width - 18, top - 1)
      context.lineTo(left + node.width - 11, top - 8)
      context.lineTo(left + node.width - 6, top - 1)
      context.stroke()
    }
    context.font = "bold 11px monospace"
    context.textAlign = "center"
    context.textBaseline = "middle"
    context.fillStyle = graphiteColor
    var lines = splitLabel(context, node.label, node.width - 15)
    var baseline = node.y - (lines.length - 1) * 7
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++)
      context.fillText(lines[lineIndex], node.x, baseline + lineIndex * 14)
    if (current) {
      context.font = "bold 9px monospace"
      context.textAlign = "left"
      context.fillStyle = graphiteSecondary
      context.fillText("HERE", left + 8, top - 10)
    }
    context.restore()
  }

  Canvas {
    id: drawing
    anchors.fill: parent
    canvasSize: Qt.size(width * map.effectiveRenderScale, height * map.effectiveRenderScale)
    canvasWindow: Qt.rect(0, 0, canvasSize.width, canvasSize.height)
    renderStrategy: Canvas.Threaded
    antialiasing: true

    onPaint: {
      var context = getContext("2d")
      var density = map.effectiveRenderScale
      context.reset()
      context.clearRect(0, 0, canvasSize.width, canvasSize.height)
      context.scale(density, density)
      if (!map.cachedGeometry.valid) {
        context.fillStyle = map.graphiteSecondary
        context.font = "bold 13px monospace"
        context.textAlign = "center"
        context.textBaseline = "middle"
        context.fillText(map.cachedGeometry.reason.toUpperCase(), width / 2, height / 2 - 6)
        context.font = "10px monospace"
        context.fillText("THE PAPER WILL FILL AS YOU EXPLORE", width / 2, height / 2 + 16)
        return
      }

      context.save()
      context.translate(width / 2, height / 2)
      context.scale(map.zoom, map.zoom)
      context.translate(map.panX, map.panY)
      var visible = map.visibleWorldBounds()
      if (map.cachedGeometry.rack && map.intersects(map.cachedGeometry.rack, visible)) {
        var rack = map.cachedGeometry.rack
        context.save()
        context.setLineDash([7, 5])
        context.strokeStyle = Qt.rgba(0.357, 0.325, 0.286, 0.56)
        context.lineWidth = 1.2
        context.strokeRect(rack.x, rack.y, rack.width, rack.height)
        context.setLineDash([])
        context.font = "bold 9px monospace"
        context.fillStyle = map.graphiteSecondary
        context.textAlign = "left"
        context.fillText("UNPLACED / CONFIRMED", rack.x + 9, rack.y + 15)
        context.restore()
      }
      for (var routeIndex = 0; routeIndex < map.cachedGeometry.routes.length; routeIndex++) {
        var route = map.cachedGeometry.routes[routeIndex]
        if (map.intersects(route.bounds, visible)) map.paintRoute(context, route)
      }
      for (var nodeIndex = 0; nodeIndex < map.cachedGeometry.nodes.length; nodeIndex++) {
        var node = map.cachedGeometry.nodes[nodeIndex]
        var bounds = ({ left: node.x - node.width / 2 - 14, top: node.y - node.height / 2 - 22,
          right: node.x + node.width / 2 + 14, bottom: node.y + node.height / 2 + 14 })
        if (map.intersects(bounds, visible)) map.paintRoom(context, node, node.id === map.currentNodeId)
      }
      context.restore()
    }
  }

  DragHandler {
    id: mapDrag
    target: null
    enabled: map.interactionEnabled
    acceptedButtons: Qt.LeftButton
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
    onActiveChanged: {
      if (active) {
        map.interactionStarted()
        map.viewportUserAdjusted = true
        map.dragPreviousX = activeTranslation.x
        map.dragPreviousY = activeTranslation.y
      } else map.emitViewport()
    }
    onActiveTranslationChanged: {
      if (!active) return
      var dx = activeTranslation.x - map.dragPreviousX
      var dy = activeTranslation.y - map.dragPreviousY
      map.dragPreviousX = activeTranslation.x
      map.dragPreviousY = activeTranslation.y
      map.panX += dx / map.zoom
      map.panY += dy / map.zoom
      map.clampViewport()
      map.emitViewport()
    }
  }

  HoverHandler {
    enabled: map.interactionEnabled
    acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
    cursorShape: mapDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
  }

  WheelHandler {
    enabled: map.interactionEnabled
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      if (event.modifiers & Qt.ControlModifier) {
        var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y
        if (delta !== 0) {
          map.interactionStarted()
          map.zoomBy(delta > 0 ? 1.1 : 1 / 1.1, event.x, event.y)
        }
      }
      // Ordinary wheel input is deliberately consumed without moving the map;
      // panning is pointer-drag or keyboard-only.
      event.accepted = true
    }
  }
}
