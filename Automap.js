// 0.2.0 ships only the cartridge proven by recorded runtime fixtures.
// Imported byte-identical copies qualify; filenames and engine type do not.
function supportsCartridge(engine, sha256) {
  return engine === "zmachine" &&
    sha256 === "37084966477dff679282de42974b2077156b1bd68fad92a65d4ea94d8eb64d79"
}

var MAP_SCHEMA_VERSION = 1
var MAX_RAW_OUTPUT = 65536
var MAX_PERSISTENCE_BYTES = 2097152
var MAX_COMMAND_LENGTH = 96
var MAX_LABEL_LENGTH = 128
var MAX_NODES = 4096
var MAX_EDGES = 16384
var MAX_OBSERVATIONS = 256
var MAX_REPLAY_TURNS = 4096
var MAX_TRAVERSALS = 2147483647
var MAX_COORDINATE = 1000000

var MOVEMENT_COMMANDS = {
  "n": "north",
  "north": "north",
  "go north": "north",
  "ne": "northeast",
  "northeast": "northeast",
  "go northeast": "northeast",
  "e": "east",
  "east": "east",
  "go east": "east",
  "se": "southeast",
  "southeast": "southeast",
  "go southeast": "southeast",
  "s": "south",
  "south": "south",
  "go south": "south",
  "sw": "southwest",
  "southwest": "southwest",
  "go southwest": "southwest",
  "w": "west",
  "west": "west",
  "go west": "west",
  "nw": "northwest",
  "northwest": "northwest",
  "go northwest": "northwest",
  "u": "up",
  "up": "up",
  "go up": "up",
  "d": "down",
  "down": "down",
  "go down": "down",
  "in": "in",
  "go in": "in",
  "out": "out",
  "go out": "out"
}

var DIRECTION_VECTORS = {
  north: { x: 0, y: -1, z: 0 },
  northeast: { x: 1, y: -1, z: 0 },
  east: { x: 1, y: 0, z: 0 },
  southeast: { x: 1, y: 1, z: 0 },
  south: { x: 0, y: 1, z: 0 },
  southwest: { x: -1, y: 1, z: 0 },
  west: { x: -1, y: 0, z: 0 },
  northwest: { x: -1, y: -1, z: 0 },
  up: { x: 0, y: 0, z: 1 },
  down: { x: 0, y: 0, z: -1 },
  in: { x: 0, y: 0, z: 1 },
  out: { x: 0, y: 0, z: -1 }
}

function exactCommand(raw, maximum) {
  var value = String(raw === undefined || raw === null ? "" : raw)
  if (value.length > maximum || /[\r\n\u0000]/.test(value)) return ""
  return value.trim().toLowerCase().replace(/[ \t]+/g, " ")
}

function normalizeMovementCommand(raw) {
  var command = exactCommand(raw, MAX_COMMAND_LENGTH)
  return Object.prototype.hasOwnProperty.call(MOVEMENT_COMMANDS, command)
    ? MOVEMENT_COMMANDS[command] : ""
}

function normalizePersistedMovementCommand(raw) {
  if (typeof raw !== "string" || hasLoneSurrogate(raw) || utf8ByteLength(raw) > MAX_COMMAND_LENGTH) return ""
  var start = 0
  var end = raw.length
  while (start < end && (raw.charAt(start) === " " || raw.charAt(start) === "\t")) start++
  while (end > start && (raw.charAt(end - 1) === " " || raw.charAt(end - 1) === "\t")) end--
  var normalized = ""
  var pendingSpace = false
  for (var i = start; i < end; i++) {
    var character = raw.charAt(i)
    if (character === " " || character === "\t") {
      pendingSpace = normalized.length > 0
      continue
    }
    if (pendingSpace) {
      normalized += " "
      pendingSpace = false
    }
    var code = character.charCodeAt(0)
    normalized += code >= 0x41 && code <= 0x5a ? String.fromCharCode(code + 0x20) : character
  }
  return Object.prototype.hasOwnProperty.call(MOVEMENT_COMMANDS, normalized)
    ? MOVEMENT_COMMANDS[normalized] : ""
}

function normalizeControlCommand(raw) {
  var command = exactCommand(raw, MAX_COMMAND_LENGTH)
  if (command === "undo" || command === "restart") return command
  if (/^restore(?: [^\s].*)?$/.test(command)) return "restore"
  if (/^load(?: [^\s].*)?$/.test(command)) return "load"
  return ""
}

function directionVector(direction) {
  var canonical = normalizeMovementCommand(direction)
  var vector = DIRECTION_VECTORS[canonical]
  return vector ? { x: vector.x, y: vector.y, z: vector.z } : null
}

function coordinatesFromDirection(origin, direction) {
  var vector = directionVector(direction)
  if (!vector) return null
  var base = origin && typeof origin === "object" ? origin : { x: 0, y: 0, z: 0 }
  var x = Number(base.x)
  var y = Number(base.y)
  var z = Number(base.z)
  if (!isFinite(x) || !isFinite(y) || !isFinite(z)) return null
  var position = { x: x + vector.x, y: y + vector.y, z: z + vector.z }
  return boundedCoordinate(position.x) && boundedCoordinate(position.y) && boundedCoordinate(position.z)
    ? position : null
}

function stripTerminalControls(raw) {
  return String(raw || "")
    .replace(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "")
    .replace(/\u0000/g, "")
}

function parseFrotzStatusLine(rawLine, allowStartupFrame) {
  var line = stripTerminalControls(rawLine).replace(/\r$/, "")
  if (line.length === 0 || line.length > 512) return null

  // Dumb Frotz frames later status with its raw prompt. Its unprompted startup
  // status is accepted only when the observer is explicitly in startup framing.
  if (line.indexOf("> ") === 0) line = line.slice(2)
  else if (allowStartupFrame === true && line.charAt(0) === " " &&
           line.charAt(1) !== " " && line.charAt(1) !== "\t") line = line.slice(1)
  else return null

  var match = line.match(/^(.{1,128}?)\s{2,}Score:\s*([+-]?\d+)\s+Moves:\s*(\d+)\s*$/i)
  if (match) {
    var label = match[1].trim()
    var score = Number(match[2])
    var moves = Number(match[3])
    if (!validObservedLabel(label) || !safeTurnNumber(moves) || !isFinite(score)) return null
    return {
      type: "location",
      engine: "zmachine",
      label: label,
      confidence: "confirmed",
      status: { score: score, moves: moves }
    }
  }

  match = line.match(/^(.{1,128}?)\s{2,}Time:\s*(\d{1,2}):(\d{2})(?:\s*([ap])\.?m\.?)?\s*$/i)
  if (!match) return null
  var clockLabel = match[1].trim()
  var hour = Number(match[2])
  var minute = Number(match[3])
  if (!validObservedLabel(clockLabel) || hour > 23 || minute > 59) return null
  return {
    type: "location",
    engine: "zmachine",
    label: clockLabel,
    confidence: "confirmed",
    status: { time: match[2] + ":" + match[3] + (match[4] ? " " + match[4].toLowerCase() + "m" : "") }
  }
}

function observeFrotzStatusLines(rawLines, framing) {
  var raw = ""
  if (Array.isArray(rawLines)) {
    if (rawLines.length > MAX_OBSERVATIONS) return []
    for (var chunkIndex = 0; chunkIndex < rawLines.length; chunkIndex++) {
      var chunk = String(rawLines[chunkIndex] || "")
      if (raw.length + chunk.length + 1 > MAX_RAW_OUTPUT) return []
      raw += (chunkIndex === 0 ? "" : "\n") + chunk
    }
  } else raw = String(rawLines || "")
  if (raw.length > MAX_RAW_OUTPUT) return []

  var lines = raw.replace(/\r\n?/g, "\n").split("\n")
  var observations = []
  for (var i = 0; i < lines.length; i++) {
    var observation = parseFrotzStatusLine(lines[i], framing === "startup" && i === 0)
    if (observation) observations.push(observation)
  }
  return observations
}

function observeFrotzStatusLine(rawLines, framing) {
  var observations = observeFrotzStatusLines(rawLines, framing)
  return observations.length > 0 ? observations[observations.length - 1] : null
}

// Return the structural frame with the confirmed observation so callers can
// pair commands only with prompt-framed turn output. Unprompted startup status
// is deliberately distinct and can never consume a queued command.
function observeFrotzStatusFrame(rawLines, framing) {
  var raw = ""
  if (Array.isArray(rawLines)) {
    if (rawLines.length > MAX_OBSERVATIONS) return null
    for (var chunkIndex = 0; chunkIndex < rawLines.length; chunkIndex++) {
      var chunk = String(rawLines[chunkIndex] || "")
      if (raw.length + chunk.length + 1 > MAX_RAW_OUTPUT) return null
      raw += (chunkIndex === 0 ? "" : "\n") + chunk
    }
  } else raw = String(rawLines || "")
  if (raw.length > MAX_RAW_OUTPUT) return null

  var lines = raw.replace(/\r\n?/g, "\n").split("\n")
  var result = null
  for (var index = 0; index < lines.length; index++) {
    var structural = stripTerminalControls(lines[index]).replace(/\r$/, "")
    var frame = structural.indexOf("> ") === 0 ? "prompt"
      : framing === "startup" && index === 0 && structural.charAt(0) === " " &&
        structural.charAt(1) !== " " && structural.charAt(1) !== "\t" ? "startup" : ""
    if (frame === "") continue
    var observation = parseFrotzStatusLine(lines[index], frame === "startup")
    if (observation) result = { observation: observation, frame: frame }
  }
  return result
}

// Zork I reports the post-death location before its death prose. Treat a
// decreasing score or move counter as discontinuous before drawing a route.
// False negatives are preferable to a fabricated compass edge.
function statusDiscontinuity(previous, next) {
  if (!previous || !next) return false
  return (typeof previous.score === "number" && typeof next.score === "number" && next.score < previous.score) ||
    (typeof previous.moves === "number" && typeof next.moves === "number" && next.moves < previous.moves)
}

function hashSeed(value) {
  var text = String(value || "")
  var hash = 2166136261
  for (var i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0 || 1
}

function cleanCartridge(cartridge) {
  var source = cartridge && typeof cartridge === "object" ? cartridge : {}
  var engine = String(source.engine || "")
  var sha256 = String(source.sha256 || "").toLowerCase()
  if (!/^[a-z0-9_-]{1,32}$/.test(engine)) engine = ""
  if (!/^[a-f0-9]{64}$/.test(sha256)) sha256 = ""
  return { engine: engine, sha256: sha256 }
}

function createEmptyState(cartridge) {
  var identity = cleanCartridge(cartridge)
  return {
    schemaVersion: MAP_SCHEMA_VERSION,
    cartridge: identity,
    nodes: [],
    edges: [],
    layout: {
      seed: hashSeed(identity.engine + ":" + identity.sha256),
      positions: {}
    },
    currentNodeId: null,
    candidateNodeIds: [],
    resyncRequired: false,
    turn: 0
  }
}

function clonePosition(position) {
  return { x: position.x, y: position.y, z: position.z }
}

function cloneState(state) {
  var result = {
    schemaVersion: state.schemaVersion,
    cartridge: { engine: state.cartridge.engine, sha256: state.cartridge.sha256 },
    nodes: [],
    edges: [],
    layout: { seed: state.layout.seed, positions: {} },
    currentNodeId: state.currentNodeId === undefined ? null : state.currentNodeId,
    candidateNodeIds: Array.isArray(state.candidateNodeIds) ? state.candidateNodeIds.slice(0) : [],
    resyncRequired: state.resyncRequired === true,
    turn: state.turn === undefined ? 0 : state.turn
  }
  var i
  for (i = 0; i < state.nodes.length; i++) {
    var node = state.nodes[i]
    result.nodes.push({
      id: node.id,
      label: node.label,
      confidence: node.confidence,
      firstSeen: node.firstSeen,
      lastSeen: node.lastSeen
    })
  }
  for (i = 0; i < state.edges.length; i++) {
    var edge = state.edges[i]
    result.edges.push({
      from: edge.from,
      to: edge.to,
      direction: edge.direction,
      command: edge.command,
      confirmed: edge.confirmed,
      traversals: edge.traversals
    })
  }
  var positionIds = Object.keys(state.layout.positions)
  for (i = 0; i < positionIds.length; i++)
    result.layout.positions[positionIds[i]] = clonePosition(state.layout.positions[positionIds[i]])
  return result
}

function hasLoneSurrogate(value) {
  var text = String(value || "")
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff) {
      if (i + 1 >= text.length) return true
      var next = text.charCodeAt(i + 1)
      if (next < 0xdc00 || next > 0xdfff) return true
      i++
    } else if (code >= 0xdc00 && code <= 0xdfff) return true
  }
  return false
}

function utf8ByteLength(value) {
  var text = String(value || "")
  var length = 0
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code < 0x80) length += 1
    else if (code < 0x800) length += 2
    else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length &&
             text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
      length += 4
      i++
    } else length += 3
  }
  return length
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasExactKeys(value, expected) {
  if (!plainObject(value)) return false
  var keys = Object.keys(value)
  if (keys.length !== expected.length) return false
  for (var i = 0; i < expected.length; i++)
    if (!Object.prototype.hasOwnProperty.call(value, expected[i])) return false
  return true
}

function validatePersistentState(state) {
  var errors = []
  function fail(message) { if (errors.length < 32) errors.push(message) }

  if (!hasExactKeys(state, ["schemaVersion", "cartridge", "nodes", "edges", "layout", "turn"]))
    return { valid: false, errors: ["persistent state has invalid fields"] }
  if (!hasExactKeys(state.cartridge, ["engine", "sha256"])) fail("persistent cartridge has invalid fields")
  else {
    if (typeof state.cartridge.engine !== "string" || !/^[a-z0-9_-]{1,32}$/.test(state.cartridge.engine))
      fail("persistent cartridge engine is required")
    if (typeof state.cartridge.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(state.cartridge.sha256))
      fail("persistent cartridge sha256 is required")
  }
  if (!Array.isArray(state.nodes)) fail("persistent nodes must be an array")
  else for (var nodeIndex = 0; nodeIndex < state.nodes.length; nodeIndex++) {
    if (!hasExactKeys(state.nodes[nodeIndex], ["id", "label", "confidence", "firstSeen", "lastSeen"]))
      fail("persistent node has invalid fields at index " + nodeIndex)
    else if (typeof state.nodes[nodeIndex].label === "string" &&
             utf8ByteLength(state.nodes[nodeIndex].label) > MAX_LABEL_LENGTH)
      fail("persistent node label exceeds byte limit at index " + nodeIndex)
  }
  if (!Array.isArray(state.edges)) fail("persistent edges must be an array")
  else for (var edgeIndex = 0; edgeIndex < state.edges.length; edgeIndex++) {
    if (!hasExactKeys(state.edges[edgeIndex], ["from", "to", "direction", "command", "confirmed", "traversals"]))
      fail("persistent edge has invalid fields at index " + edgeIndex)
    else if (normalizePersistedMovementCommand(state.edges[edgeIndex].command) !== state.edges[edgeIndex].direction)
      fail("persistent edge command is invalid at index " + edgeIndex)
  }
  if (!hasExactKeys(state.layout, ["seed", "positions"])) fail("persistent layout has invalid fields")
  else if (!plainObject(state.layout.positions)) fail("persistent positions must be an object")
  else {
    var positionIds = Object.keys(state.layout.positions)
    for (var positionIndex = 0; positionIndex < positionIds.length; positionIndex++)
      if (!hasExactKeys(state.layout.positions[positionIds[positionIndex]], ["x", "y", "z"]))
        fail("persistent position has invalid fields for " + positionIds[positionIndex])
  }

  if (errors.length > 0) return { valid: false, errors: errors }
  var hydrated = clonePersistentState(state)
  hydrated.currentNodeId = null
  hydrated.candidateNodeIds = []
  hydrated.resyncRequired = true
  var checked = validateMapState(hydrated)
  for (var checkedIndex = 0; checkedIndex < checked.errors.length; checkedIndex++) fail(checked.errors[checkedIndex])
  if (safeTurnNumber(state.turn) && Array.isArray(state.nodes))
    for (var timestampIndex = 0; timestampIndex < state.nodes.length; timestampIndex++)
      if (state.nodes[timestampIndex].lastSeen > state.turn)
        fail("node timestamp exceeds persisted turn at index " + timestampIndex)
  if (errors.length === 0 && utf8ByteLength(JSON.stringify(state)) > MAX_PERSISTENCE_BYTES)
    fail("persistent state exceeds byte limit")
  return { valid: errors.length === 0, errors: errors }
}

function clonePersistentState(state) {
  var result = {
    schemaVersion: state.schemaVersion,
    cartridge: { engine: state.cartridge.engine, sha256: state.cartridge.sha256 },
    nodes: [],
    edges: [],
    layout: { seed: state.layout.seed, positions: {} },
    turn: state.turn
  }
  var i
  for (i = 0; i < state.nodes.length; i++) {
    var node = state.nodes[i]
    result.nodes.push({
      id: node.id, label: node.label, confidence: node.confidence,
      firstSeen: node.firstSeen, lastSeen: node.lastSeen
    })
  }
  for (i = 0; i < state.edges.length; i++) {
    var edge = state.edges[i]
    result.edges.push({
      from: edge.from, to: edge.to, direction: edge.direction, command: edge.command,
      confirmed: edge.confirmed, traversals: edge.traversals
    })
  }
  var positionIds = Object.keys(state.layout.positions)
  for (i = 0; i < positionIds.length; i++)
    result.layout.positions[positionIds[i]] = clonePosition(state.layout.positions[positionIds[i]])
  return result
}

// Turn is persisted so firstSeen/lastSeen remain monotonic after a fresh-evidence
// session hydration. Current location and resynchronization candidates are not.
function toPersistentState(state) {
  var checked = validateMapState(state)
  if (!checked.valid) throw new TypeError("invalid automap state: " + checked.errors[0])
  var persistent = clonePersistentState(state)
  var persistentChecked = validatePersistentState(persistent)
  if (!persistentChecked.valid) throw new TypeError("invalid persistent automap state: " + persistentChecked.errors[0])
  if (utf8ByteLength(JSON.stringify(persistent)) > MAX_PERSISTENCE_BYTES)
    throw new RangeError("persistent automap state exceeds byte limit")
  return persistent
}

function serializePersistentState(state) {
  return JSON.stringify(toPersistentState(state))
}

function hydratePersistentState(raw) {
  var parsed = raw
  if (typeof raw === "string") {
    if (utf8ByteLength(raw) > MAX_PERSISTENCE_BYTES) throw new RangeError("persistent automap state exceeds byte limit")
    try { parsed = JSON.parse(raw) } catch (error) { throw new TypeError("invalid persistent automap JSON") }
  }
  var checked = validatePersistentState(parsed)
  if (!checked.valid) throw new TypeError("invalid persistent automap state: " + checked.errors[0])
  var state = clonePersistentState(parsed)
  state.currentNodeId = null
  state.candidateNodeIds = []
  state.resyncRequired = true
  return state
}

function nodeById(state, id) {
  for (var i = 0; i < state.nodes.length; i++)
    if (state.nodes[i].id === id) return state.nodes[i]
  return null
}

function nodeIndexById(state, id) {
  for (var i = 0; i < state.nodes.length; i++)
    if (state.nodes[i].id === id) return i
  return -1
}

function nodesWithLabel(state, label) {
  var ids = []
  for (var i = 0; i < state.nodes.length; i++)
    if (state.nodes[i].label === label) ids.push(state.nodes[i].id)
  return ids
}

function nextRoomId(state) {
  for (var number = 1; number <= MAX_NODES; number++)
    if (!nodeById(state, "room-" + number)) return "room-" + number
  return ""
}

function validObservedLabel(label) {
  return typeof label === "string" && label.length > 0 && label.length <= MAX_LABEL_LENGTH &&
    !/[\u0000-\u001f\u007f]/.test(label) && !hasLoneSurrogate(label) && label.trim() === label
}

function confirmedObservation(observations) {
  var list = Array.isArray(observations) ? observations : [observations]
  if (list.length > MAX_OBSERVATIONS) return null
  for (var i = list.length - 1; i >= 0; i--) {
    var observation = list[i]
    if (!observation || observation.type !== "location" || observation.confidence !== "confirmed") continue
    var label = String(observation.label === undefined ? "" : observation.label)
    if (!validObservedLabel(label)) continue
    var roomId = observation.roomId === undefined ? "" : String(observation.roomId)
    if (roomId !== "" && !/^room-[1-9]\d{0,9}$/.test(roomId)) continue
    return { label: label, roomId: roomId }
  }
  return null
}

function addNode(state, label, turn, position) {
  if (state.nodes.length >= MAX_NODES) return null
  var id = nextRoomId(state)
  if (id === "") return null
  state.nodes.push({
    id: id,
    label: label,
    confidence: "confirmed",
    firstSeen: turn,
    lastSeen: turn
  })
  if (position) state.layout.positions[id] = position
  return id
}

function touchNode(state, id, turn) {
  var index = nodeIndexById(state, id)
  if (index !== -1) state.nodes[index].lastSeen = Math.max(state.nodes[index].lastSeen, turn)
}

function matchingDirectedTargets(state, sourceIds, direction, label) {
  var sourceLookup = {}
  var nodeLookup = {}
  var targetLookup = {}
  var targets = []
  var i
  for (i = 0; i < sourceIds.length; i++) sourceLookup[sourceIds[i]] = true
  for (i = 0; i < state.nodes.length; i++) nodeLookup[state.nodes[i].id] = state.nodes[i]
  for (i = 0; i < state.edges.length; i++) {
    var edge = state.edges[i]
    if (!sourceLookup[edge.from] || edge.direction !== direction) continue
    var target = nodeLookup[edge.to]
    if (target && target.label === label && !targetLookup[target.id]) {
      targetLookup[target.id] = true
      targets.push(target.id)
    }
  }
  return targets
}

function matchingPositionTargets(state, position, label) {
  var targets = []
  if (!position) return targets
  for (var i = 0; i < state.nodes.length; i++) {
    var node = state.nodes[i]
    var existing = state.layout.positions[node.id]
    if (node.label === label && existing && existing.x === position.x &&
        existing.y === position.y && existing.z === position.z) targets.push(node.id)
  }
  return targets
}

function addOrTraverseEdge(state, from, to, direction, command) {
  for (var i = 0; i < state.edges.length; i++) {
    var edge = state.edges[i]
    if (edge.from === from && edge.to === to && edge.direction === direction) {
      edge.traversals = Math.min(MAX_TRAVERSALS, edge.traversals + 1)
      return true
    }
  }
  if (state.edges.length >= MAX_EDGES) return false
  state.edges.push({
    from: from,
    to: to,
    direction: direction,
    command: command,
    confirmed: true,
    traversals: 1
  })
  return true
}

function resynchronizeState(state) {
  var checked = validateMapState(state)
  if (!checked.valid) throw new TypeError("invalid automap state: " + checked.errors[0])
  var next = cloneState(state)
  next.currentNodeId = null
  next.candidateNodeIds = []
  next.resyncRequired = true
  return next
}

function reduceTurn(state, command, observations) {
  var checked = validateMapState(state)
  if (!checked.valid) throw new TypeError("invalid automap state: " + checked.errors[0])

  var next = cloneState(state)
  next.turn = Math.min(MAX_TRAVERSALS, next.turn + 1)
  var control = normalizeControlCommand(command)
  var movement = normalizeMovementCommand(command)
  var rawCommand = exactCommand(command, MAX_COMMAND_LENGTH)

  if (control !== "") {
    next.currentNodeId = null
    next.candidateNodeIds = []
    next.resyncRequired = true
  }

  var observation = confirmedObservation(observations)
  if (!observation) return next

  if (observation.roomId !== "") {
    var explicitNode = nodeById(next, observation.roomId)
    if (!explicitNode || explicitNode.label !== observation.label) return next
    var explicitSource = nodeById(next, next.currentNodeId)
    if (control === "" && movement !== "" && explicitSource && explicitSource.id !== explicitNode.id) {
      if (!next.layout.positions[explicitNode.id] && next.layout.positions[explicitSource.id]) {
        var explicitPosition = coordinatesFromDirection(next.layout.positions[explicitSource.id], movement)
        if (explicitPosition) next.layout.positions[explicitNode.id] = explicitPosition
      }
      addOrTraverseEdge(next, explicitSource.id, explicitNode.id, movement, rawCommand)
    }
    touchNode(next, explicitNode.id, next.turn)
    next.currentNodeId = explicitNode.id
    next.candidateNodeIds = []
    next.resyncRequired = false
    return next
  }

  if (control !== "" || next.resyncRequired) {
    var candidates = nodesWithLabel(next, observation.label)
    if (candidates.length === 1) {
      touchNode(next, candidates[0], next.turn)
      next.currentNodeId = candidates[0]
      next.candidateNodeIds = []
      next.resyncRequired = false
    } else if (candidates.length > 1) {
      next.currentNodeId = null
      next.candidateNodeIds = candidates
      next.resyncRequired = true
    } else {
      var reacquired = addNode(next, observation.label, next.turn, null)
      next.currentNodeId = reacquired
      next.candidateNodeIds = []
      next.resyncRequired = reacquired === null
    }
    return next
  }

  var current = nodeById(next, next.currentNodeId)
  if (!current && next.candidateNodeIds.length > 0 && movement !== "") {
    var candidateTargets = matchingDirectedTargets(next, next.candidateNodeIds, movement, observation.label)
    if (candidateTargets.length === 1) {
      touchNode(next, candidateTargets[0], next.turn)
      next.currentNodeId = candidateTargets[0]
      next.candidateNodeIds = []
      next.resyncRequired = false
    }
    return next
  }

  if (!current) {
    var initialPosition = next.nodes.length === 0 ? { x: 0, y: 0, z: 0 } : null
    var initial = addNode(next, observation.label, next.turn, initialPosition)
    next.currentNodeId = initial
    next.candidateNodeIds = []
    next.resyncRequired = initial === null
    return next
  }

  var knownTargets = movement === "" ? []
    : matchingDirectedTargets(next, [current.id], movement, observation.label)
  if (knownTargets.length > 1) {
    next.currentNodeId = null
    next.candidateNodeIds = knownTargets
    next.resyncRequired = true
    return next
  }
  if (knownTargets.length === 1) {
    touchNode(next, knownTargets[0], next.turn)
    addOrTraverseEdge(next, current.id, knownTargets[0], movement, rawCommand)
    next.currentNodeId = knownTargets[0]
    next.candidateNodeIds = []
    next.resyncRequired = false
    return next
  }

  if (current.label === observation.label) {
    touchNode(next, current.id, next.turn)
    return next
  }

  if (movement === "") {
    var transitioned = addNode(next, observation.label, next.turn, null)
    next.currentNodeId = transitioned
    next.candidateNodeIds = []
    next.resyncRequired = transitioned === null
    return next
  }

  var sourcePosition = next.layout.positions[current.id]
  var targetPosition = sourcePosition ? coordinatesFromDirection(sourcePosition, movement) : null
  var positionedTargets = matchingPositionTargets(next, targetPosition, observation.label)
  if (positionedTargets.length > 1) {
    next.currentNodeId = null
    next.candidateNodeIds = positionedTargets
    next.resyncRequired = true
    return next
  }

  var targetId = positionedTargets.length === 1 ? positionedTargets[0] : null
  if (targetId === null) {
    targetId = addNode(next, observation.label, next.turn, targetPosition)
    if (targetId === null) {
      next.currentNodeId = null
      next.resyncRequired = true
      return next
    }
  }

  touchNode(next, targetId, next.turn)
  addOrTraverseEdge(next, current.id, targetId, movement, rawCommand)
  next.currentNodeId = targetId
  next.candidateNodeIds = []
  next.resyncRequired = false
  return next
}

function validReplayObservations(observations) {
  if (observations === null) return true
  var list = Array.isArray(observations) ? observations : [observations]
  if (list.length > MAX_OBSERVATIONS) return false
  var allowedKeys = { type: true, engine: true, label: true, confidence: true, status: true, roomId: true }
  for (var i = 0; i < list.length; i++) {
    var observation = list[i]
    if (!observation || typeof observation !== "object" || Array.isArray(observation)) return false
    var keys = Object.keys(observation)
    if (keys.length > 6) return false
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++)
      if (!allowedKeys[keys[keyIndex]]) return false
    if (observation.type !== "location" || !validObservedLabel(observation.label)) return false
    if (observation.confidence !== "confirmed" && observation.confidence !== "uncertain") return false
    if (observation.engine !== undefined &&
        (typeof observation.engine !== "string" || observation.engine.length > 32)) return false
    if (observation.roomId !== undefined &&
        (typeof observation.roomId !== "string" || !/^room-[1-9]\d{0,9}$/.test(observation.roomId))) return false
    if (!validReplayStatus(observation.status)) return false
  }
  return true
}

function validReplayStatus(status) {
  if (status === undefined) return true
  if (!status || typeof status !== "object" || Array.isArray(status)) return false
  var keys = Object.keys(status)
  if (keys.length > 8) return false
  for (var i = 0; i < keys.length; i++) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(keys[i])) return false
    var value = status[keys[i]]
    if (typeof value === "string" && value.length <= MAX_LABEL_LENGTH && !/[\r\n\u0000]/.test(value)) continue
    if (typeof value === "number" && isFinite(value) && Math.abs(value) <= MAX_TRAVERSALS) continue
    if (typeof value === "boolean") continue
    return false
  }
  return true
}

// Replay consumes already-observed engine-neutral turns and stops at the first
// malformed turn, returning the last valid immutable state.
function replayTurns(state, turns) {
  var checked = validateMapState(state)
  if (!checked.valid) return { state: null, processed: 0, stopped: true, error: "invalid-state" }

  var current = cloneState(state)
  if (!Array.isArray(turns))
    return { state: current, processed: 0, stopped: true, error: "turns-must-be-an-array" }
  if (turns.length > MAX_REPLAY_TURNS)
    return { state: current, processed: 0, stopped: true, error: "turn-limit" }

  for (var i = 0; i < turns.length; i++) {
    var turn = turns[i]
    var turnKeys = turn && typeof turn === "object" && !Array.isArray(turn) ? Object.keys(turn) : []
    if (!turn || typeof turn !== "object" || Array.isArray(turn) || turnKeys.length !== 2 ||
        !Object.prototype.hasOwnProperty.call(turn, "command") ||
        !Object.prototype.hasOwnProperty.call(turn, "observations") ||
        typeof turn.command !== "string" || turn.command.length > MAX_COMMAND_LENGTH ||
        /[\r\n\u0000]/.test(turn.command) || !validReplayObservations(turn.observations))
      return { state: current, processed: i, stopped: true, error: "malformed-turn:" + i }
    current = reduceTurn(current, turn.command, turn.observations)
  }

  return { state: current, processed: turns.length, stopped: false, error: "" }
}

function safeTurnNumber(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value &&
    value >= 0 && value <= MAX_TRAVERSALS
}

function safeSeed(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value &&
    value >= 1 && value <= 4294967295
}

function validateMapState(state) {
  var errors = []
  function fail(message) { if (errors.length < 32) errors.push(message) }

  if (!state || typeof state !== "object" || Array.isArray(state))
    return { valid: false, errors: ["state must be an object"] }
  if (state.schemaVersion !== MAP_SCHEMA_VERSION) fail("unsupported schemaVersion")
  if (!state.cartridge || typeof state.cartridge !== "object") fail("cartridge is required")
  else {
    if (typeof state.cartridge.engine !== "string" ||
        (state.cartridge.engine !== "" && !/^[a-z0-9_-]{1,32}$/.test(state.cartridge.engine)))
      fail("invalid cartridge engine")
    if (typeof state.cartridge.sha256 !== "string" ||
        (state.cartridge.sha256 !== "" && !/^[a-f0-9]{64}$/.test(state.cartridge.sha256)))
      fail("invalid cartridge sha256")
  }

  if (!Array.isArray(state.nodes)) fail("nodes must be an array")
  else if (state.nodes.length > MAX_NODES) fail("node limit exceeded")
  if (!Array.isArray(state.edges)) fail("edges must be an array")
  else if (state.edges.length > MAX_EDGES) fail("edge limit exceeded")

  var nodeIds = {}
  var nodes = Array.isArray(state.nodes) ? state.nodes : []
  var i
  for (i = 0; i < nodes.length; i++) {
    var node = nodes[i]
    if (!node || typeof node !== "object") { fail("invalid node at index " + i); continue }
    if (typeof node.id !== "string" || !/^room-[1-9]\d{0,9}$/.test(node.id)) fail("invalid node id at index " + i)
    else if (nodeIds[node.id]) fail("duplicate node id " + node.id)
    else nodeIds[node.id] = true
    if (!validObservedLabel(node.label)) fail("invalid node label at index " + i)
    if (node.confidence !== "confirmed") fail("invalid node confidence at index " + i)
    if (!safeTurnNumber(node.firstSeen) || !safeTurnNumber(node.lastSeen) || node.lastSeen < node.firstSeen)
      fail("invalid node timestamps at index " + i)
  }

  var edges = Array.isArray(state.edges) ? state.edges : []
  var edgeKeys = {}
  for (i = 0; i < edges.length; i++) {
    var edge = edges[i]
    if (!edge || typeof edge !== "object") { fail("invalid edge at index " + i); continue }
    if (!nodeIds[edge.from] || !nodeIds[edge.to]) fail("edge references unknown node at index " + i)
    if (!DIRECTION_VECTORS[edge.direction]) fail("invalid edge direction at index " + i)
    if (typeof edge.command !== "string" || edge.command.length === 0 || edge.command.length > MAX_COMMAND_LENGTH ||
        normalizeMovementCommand(edge.command) !== edge.direction)
      fail("invalid edge command at index " + i)
    if (edge.confirmed !== true) fail("edge must be confirmed at index " + i)
    if (!safeTurnNumber(edge.traversals) || edge.traversals < 1) fail("invalid traversal count at index " + i)
    var edgeKey = edge.from + "\u0000" + edge.to + "\u0000" + edge.direction
    if (edgeKeys[edgeKey]) fail("duplicate directed edge at index " + i)
    edgeKeys[edgeKey] = true
  }

  if (!state.layout || typeof state.layout !== "object" || Array.isArray(state.layout)) fail("layout is required")
  else {
    if (!safeSeed(state.layout.seed)) fail("invalid layout seed")
    if (!state.layout.positions || typeof state.layout.positions !== "object" || Array.isArray(state.layout.positions))
      fail("layout positions must be an object")
    else {
      var positionIds = Object.keys(state.layout.positions)
      if (positionIds.length > MAX_NODES) fail("position limit exceeded")
      for (i = 0; i < positionIds.length; i++) {
        var positionId = positionIds[i]
        var position = state.layout.positions[positionId]
        if (!nodeIds[positionId]) { fail("position references unknown node " + positionId); continue }
        if (!position || typeof position !== "object" ||
            !boundedCoordinate(position.x) || !boundedCoordinate(position.y) || !boundedCoordinate(position.z))
          fail("invalid position for " + positionId)
      }
    }
  }

  if (state.currentNodeId !== null && state.currentNodeId !== undefined && !nodeIds[state.currentNodeId])
    fail("currentNodeId references unknown node")
  if (state.candidateNodeIds !== undefined) {
    if (!Array.isArray(state.candidateNodeIds) || state.candidateNodeIds.length > MAX_NODES)
      fail("invalid candidateNodeIds")
    else {
      var seenCandidates = {}
      for (i = 0; i < state.candidateNodeIds.length; i++) {
        var candidate = state.candidateNodeIds[i]
        if (!nodeIds[candidate] || seenCandidates[candidate]) fail("invalid candidate node " + candidate)
        seenCandidates[candidate] = true
      }
    }
  }
  if (state.resyncRequired !== undefined && typeof state.resyncRequired !== "boolean") fail("invalid resyncRequired")
  if (state.currentNodeId && Array.isArray(state.candidateNodeIds) && state.candidateNodeIds.length > 0)
    fail("current node and candidates are mutually exclusive")
  if (Array.isArray(state.candidateNodeIds) && state.candidateNodeIds.length > 0 && state.resyncRequired !== true)
    fail("candidate nodes require resynchronization")
  if (state.turn !== undefined && !safeTurnNumber(state.turn)) fail("invalid turn")

  return { valid: errors.length === 0, errors: errors }
}

function boundedCoordinate(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value &&
    Math.abs(value) <= MAX_COORDINATE
}

if (typeof module !== "undefined") {
  module.exports = {
    MAP_SCHEMA_VERSION: MAP_SCHEMA_VERSION,
    supportsCartridge: supportsCartridge,
    statusDiscontinuity: statusDiscontinuity,
    LIMITS: {
      rawOutput: MAX_RAW_OUTPUT,
      persistenceBytes: MAX_PERSISTENCE_BYTES,
      commandLength: MAX_COMMAND_LENGTH,
      labelLength: MAX_LABEL_LENGTH,
      nodes: MAX_NODES,
      edges: MAX_EDGES,
      observations: MAX_OBSERVATIONS,
      replayTurns: MAX_REPLAY_TURNS,
      coordinate: MAX_COORDINATE
    },
    normalizeMovementCommand: normalizeMovementCommand,
    normalizeControlCommand: normalizeControlCommand,
    directionVector: directionVector,
    coordinatesFromDirection: coordinatesFromDirection,
    observeFrotzStatusLine: observeFrotzStatusLine,
    observeFrotzStatusLines: observeFrotzStatusLines,
    observeFrotzStatusFrame: observeFrotzStatusFrame,
    createEmptyState: createEmptyState,
    resynchronizeState: resynchronizeState,
    reduceTurn: reduceTurn,
    replayTurns: replayTurns,
    validateMapState: validateMapState,
    validatePersistentState: validatePersistentState,
    toPersistentState: toPersistentState,
    serializePersistentState: serializePersistentState,
    hydratePersistentState: hydratePersistentState
  }
}
