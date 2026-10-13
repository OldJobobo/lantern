var EXIT_DIRECTIONS = [
  "north", "northeast", "east", "southeast", "south", "southwest",
  "west", "northwest", "up", "down", "in", "out"
]
var EXIT_LABELS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "U", "D", "IN", "OUT"]

function directedEdgeKey(edge) {
  return edge.from + "\u0000" + edge.to + "\u0000" + edge.direction
}

function endpointKey(from, to) {
  return from + "\u0000" + to
}

function pairKey(from, to) {
  return from < to ? endpointKey(from, to) : endpointKey(to, from)
}

// Validate directed uniqueness once and attach lookup-derived route metadata.
// This keeps reverse detection linear even at the renderer's maximum edge count.
function planEdges(edges) {
  if (!Array.isArray(edges)) return { valid: false, reason: "edges must be an array", edges: [] }

  var directed = {}
  var endpoints = {}
  var index
  for (index = 0; index < edges.length; index++) {
    var edge = edges[index]
    if (!edge || typeof edge.from !== "string" || typeof edge.to !== "string" ||
        typeof edge.direction !== "string")
      return { valid: false, reason: "edge metadata is invalid", edges: [] }
    var key = directedEdgeKey(edge)
    if (directed[key]) return { valid: false, reason: "duplicate directed edge", edges: [] }
    directed[key] = true
    endpoints[endpointKey(edge.from, edge.to)] = true
  }

  var planned = []
  for (index = 0; index < edges.length; index++) {
    var source = edges[index]
    planned.push({
      edge: source,
      pairKey: pairKey(source.from, source.to),
      sortKey: source.from + ":" + source.to + ":" + source.direction,
      // A self-loop cannot be its own reciprocal traversal.
      hasReverse: source.from !== source.to && endpoints[endpointKey(source.to, source.from)] === true
    })
  }
  return { valid: true, reason: "", edges: planned }
}

function roomOrder(id) {
  var match = /^room-([1-9]\d*)$/.exec(id)
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER
}

function planNodeLayout(nodes) {
  if (!Array.isArray(nodes) || nodes.length > 4096)
    return { valid: false, reason: "nodes must be a bounded array", nodes: [], overflowCount: 0 }

  var planned = []
  for (var index = 0; index < nodes.length; index++) {
    var source = nodes[index]
    if (!source || typeof source.id !== "string" || !isFinite(source.anchorX) || !isFinite(source.anchorY) ||
        !isFinite(source.width) || !isFinite(source.height) || source.width <= 0 || source.height <= 0)
      return { valid: false, reason: "node geometry is invalid", nodes: [], overflowCount: 0 }
    planned.push({
      id: source.id,
      anchorX: Number(source.anchorX),
      anchorY: Number(source.anchorY),
      width: Number(source.width),
      height: Number(source.height),
      x: Number(source.anchorX),
      y: Number(source.anchorY),
      displaced: false,
      overflow: false
    })
  }
  planned.sort(function(left, right) {
    var leftOrder = roomOrder(left.id)
    var rightOrder = roomOrder(right.id)
    if (leftOrder !== rightOrder) return leftOrder - rightOrder
    return left.id < right.id ? -1 : left.id > right.id ? 1 : 0
  })

  var gutter = 14
  var cellWidth = 128
  var cellHeight = 80
  var occupied = {}
  function cellKey(x, y) { return String(x) + ":" + String(y) }
  function cellRange(node) {
    return {
      left: Math.floor((node.x - node.width / 2 - gutter) / cellWidth),
      right: Math.floor((node.x + node.width / 2 + gutter) / cellWidth),
      top: Math.floor((node.y - node.height / 2 - gutter) / cellHeight),
      bottom: Math.floor((node.y + node.height / 2 + gutter) / cellHeight)
    }
  }
  function intersects(left, right) {
    return Math.abs(left.x - right.x) < (left.width + right.width) / 2 + gutter &&
      Math.abs(left.y - right.y) < (left.height + right.height) / 2 + gutter
  }
  function isFree(candidate) {
    var range = cellRange(candidate)
    var seen = {}
    for (var x = range.left; x <= range.right; x++) {
      for (var y = range.top; y <= range.bottom; y++) {
        var bucket = occupied[cellKey(x, y)] || []
        for (var bucketIndex = 0; bucketIndex < bucket.length; bucketIndex++) {
          var other = bucket[bucketIndex]
          if (!seen[other.id]) {
            seen[other.id] = true
            if (intersects(candidate, other)) return false
          }
        }
      }
    }
    return true
  }
  function occupy(node) {
    var range = cellRange(node)
    for (var x = range.left; x <= range.right; x++) {
      for (var y = range.top; y <= range.bottom; y++) {
        var key = cellKey(x, y)
        if (!occupied[key]) occupied[key] = []
        occupied[key].push(node)
      }
    }
  }

  var overflowCount = 0
  var maximumAnchorX = -Infinity
  var step = 24
  var maximumRing = 12
  for (index = 0; index < planned.length; index++) {
    var node = planned[index]
    maximumAnchorX = Math.max(maximumAnchorX, node.anchorX + node.width / 2)
    var placed = false
    for (var ring = 0; ring <= maximumRing && !placed; ring++) {
      for (var offsetY = -ring; offsetY <= ring && !placed; offsetY++) {
        for (var offsetX = -ring; offsetX <= ring; offsetX++) {
          if (ring !== 0 && Math.abs(offsetX) !== ring && Math.abs(offsetY) !== ring) continue
          node.x = node.anchorX + offsetX * step
          node.y = node.anchorY + offsetY * step
          if (isFree(node)) { placed = true; break }
        }
      }
    }
    if (!placed) {
      node.x = maximumAnchorX + 180 + (overflowCount % 8) * 126
      node.y = -280 + Math.floor(overflowCount / 8) * 76
      node.overflow = true
      overflowCount++
      var overflowAttempts = 0
      while (!isFree(node) && overflowAttempts < 4096) {
        node.y += 76
        overflowAttempts++
      }
      if (overflowAttempts === 4096)
        return { valid: false, reason: "node overflow is exhausted", nodes: [], overflowCount: overflowCount }
    }
    node.displaced = node.x !== node.anchorX || node.y !== node.anchorY
    occupy(node)
  }

  return { valid: true, reason: "", nodes: planned, overflowCount: overflowCount }
}

function validBounds(bounds) {
  return bounds && isFinite(bounds.left) && isFinite(bounds.top) && isFinite(bounds.right) &&
    isFinite(bounds.bottom) && bounds.right >= bounds.left && bounds.bottom >= bounds.top
}

function fitViewport(bounds, width, height, minimumZoom, maximumZoom, defaultMaximum) {
  if (!validBounds(bounds) || !isFinite(width) || !isFinite(height) || width <= 0 || height <= 0)
    return { panX: 0, panY: 0, zoom: minimumZoom }
  var contentWidth = Math.max(1, bounds.right - bounds.left)
  var contentHeight = Math.max(1, bounds.bottom - bounds.top)
  var usableWidth = Math.max(1, width - 96)
  var usableHeight = Math.max(1, height - 84)
  var zoom = Math.min(Number(defaultMaximum), usableWidth / contentWidth, usableHeight / contentHeight)
  zoom = Math.max(Number(minimumZoom), Math.min(Number(maximumZoom), zoom))
  return {
    panX: -(bounds.left + bounds.right) / 2,
    panY: -(bounds.top + bounds.bottom) / 2,
    zoom: zoom
  }
}

function clampViewport(bounds, width, height, zoom, panX, panY) {
  if (!validBounds(bounds) || !isFinite(width) || !isFinite(height) || width <= 0 || height <= 0 ||
      !isFinite(zoom) || zoom <= 0)
    return { panX: isFinite(panX) ? panX : 0, panY: isFinite(panY) ? panY : 0 }

  function clampAxis(lower, upper, visible, pan) {
    var content = Math.max(1, upper - lower)
    var graphCenter = (lower + upper) / 2
    var center = -pan
    var edgePadding = 64 / zoom
    var minimumCenter
    var maximumCenter
    if (content <= visible - edgePadding * 2) {
      var freedom = Math.max(32 / zoom, Math.min(visible * 0.22, Math.max(0, (visible - content) / 2)))
      minimumCenter = graphCenter - freedom
      maximumCenter = graphCenter + freedom
    } else {
      minimumCenter = lower + visible / 2 - edgePadding
      maximumCenter = upper - visible / 2 + edgePadding
      if (minimumCenter > maximumCenter) minimumCenter = maximumCenter = graphCenter
    }
    center = Math.max(minimumCenter, Math.min(maximumCenter, center))
    return -center
  }

  return {
    panX: clampAxis(bounds.left, bounds.right, width / zoom, Number(panX) || 0),
    panY: clampAxis(bounds.top, bounds.bottom, height / zoom, Number(panY) || 0)
  }
}

function routeInset(width, height, dx, dy, gap) {
  var length = Math.sqrt(dx * dx + dy * dy)
  if (!isFinite(length) || length <= 0) return 0
  var ux = Math.abs(dx / length)
  var uy = Math.abs(dy / length)
  var horizontal = ux > 0.000001 ? Number(width) / 2 / ux : Infinity
  var vertical = uy > 0.000001 ? Number(height) / 2 / uy : Infinity
  return Math.min(horizontal, vertical) + Math.max(0, Number(gap) || 0)
}

function orderedExitLabels(edges, currentNodeId) {
  var present = {}
  if (Array.isArray(edges)) {
    for (var index = 0; index < edges.length; index++) {
      var edge = edges[index]
      if (edge && edge.from === currentNodeId && EXIT_DIRECTIONS.indexOf(edge.direction) !== -1)
        present[edge.direction] = true
    }
  }

  var labels = []
  for (var directionIndex = 0; directionIndex < EXIT_DIRECTIONS.length; directionIndex++) {
    var direction = EXIT_DIRECTIONS[directionIndex]
    if (present[direction]) labels.push(EXIT_LABELS[directionIndex])
  }
  return labels
}

if (typeof module !== "undefined") {
  module.exports = {
    EXIT_DIRECTIONS: EXIT_DIRECTIONS.slice(0),
    EXIT_LABELS: EXIT_LABELS.slice(0),
    directedEdgeKey: directedEdgeKey,
    planEdges: planEdges,
    roomOrder: roomOrder,
    planNodeLayout: planNodeLayout,
    fitViewport: fitViewport,
    clampViewport: clampViewport,
    routeInset: routeInset,
    orderedExitLabels: orderedExitLabels
  }
}
