const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Automap = require("../Automap.js")

const fixtureRoot = path.join(__dirname, "fixtures/automap")

function location(label, roomId) {
  const observation = {
    type: "location",
    engine: "zmachine",
    label,
    confidence: "confirmed"
  }
  if (roomId) observation.roomId = roomId
  return observation
}

function phase2ReplayFixture() {
  const raw = fs.readFileSync(path.join(fixtureRoot, "zork1-phase2.raw"), "utf8")
  const commands = fs.readFileSync(path.join(fixtureRoot, "zork1-phase2.commands"), "utf8")
    .trim().split("\n")
  const rawTurns = raw.split(/(?=^> )/m)
  assert.equal(rawTurns.length, commands.length + 1, "each command must retain one raw output turn")

  const turns = rawTurns.map((rawTurn, index) => {
    const observations = Automap.observeFrotzStatusLines(rawTurn, index === 0 ? "startup" : "turn")
    assert.equal(observations.length, 1, `turn ${index} must contain exactly one framed status observation`)
    return { command: index === 0 ? "" : commands[index - 1], observations }
  })
  return { commands, rawTurns, turns }
}

test("movement normalization accepts only exact movement commands", () => {
  const accepted = {
    n: "north", north: "north", "go north": "north",
    ne: "northeast", northeast: "northeast", "go northeast": "northeast",
    e: "east", east: "east", se: "southeast", southeast: "southeast",
    s: "south", south: "south", sw: "southwest", southwest: "southwest",
    w: "west", west: "west", nw: "northwest", northwest: "northwest",
    u: "up", up: "up", d: "down", down: "down",
    in: "in", out: "out"
  }

  for (const [command, direction] of Object.entries(accepted))
    assert.equal(Automap.normalizeMovementCommand(command), direction, command)

  assert.equal(Automap.normalizeMovementCommand("  GO   NORTH  "), "north")
  for (const rejected of [
    "", "look north", "ask troll about north", "north then east", "north;east",
    "n and e", "enter", "exit", "north\neast", "northwestward"
  ]) assert.equal(Automap.normalizeMovementCommand(rejected), "", rejected)
})

test("Frotz observer confirms fixture-proven startup and prompt-framed status lines", () => {
  const startup = fs.readFileSync(path.join(fixtureRoot, "zork1-startup.txt"), "utf8")
  const northTurn = fs.readFileSync(path.join(fixtureRoot, "zork1-north-turn.txt"), "utf8")

  assert.deepEqual(Automap.observeFrotzStatusLine(startup, "startup"), {
    type: "location",
    engine: "zmachine",
    label: "West of House",
    confidence: "confirmed",
    status: { score: 0, moves: 0 }
  })
  assert.deepEqual(Automap.observeFrotzStatusLine(northTurn), {
    type: "location",
    engine: "zmachine",
    label: "North of House",
    confidence: "confirmed",
    status: { score: 0, moves: 2 }
  })
  assert.equal(Automap.observeFrotzStatusLine(startup), null, "startup framing must be explicit")
  assert.equal(Automap.observeFrotzStatusFrame(startup, "startup").frame, "startup")
  assert.equal(Automap.observeFrotzStatusFrame(northTurn, "startup").frame, "prompt")
  assert.equal(Automap.observeFrotzStatusFrame(startup), null)

  const colored = northTurn.replace("North of House", "\u001b[32mNorth of House\u001b[0m")
  assert.equal(Automap.observeFrotzStatusLine(colored).label, "North of House")
  assert.equal(Automap.observeFrotzStatusLine("x".repeat(Automap.LIMITS.rawOutput + 1)), null)
})

test("Frotz observer rejects status-like prose without exact runtime framing", () => {
  for (const prose of [
    "Forest                         Score: 0        Moves: 2",
    " The sign says Forest          Score: 0        Moves: 2",
    "  Forest                        Score: 0        Moves: 2",
    "\tForest                        Time: 9:05 am",
    "Score: 0 Moves: 2"
  ]) assert.equal(Automap.observeFrotzStatusLine(prose), null, prose)

  const startupWithLaterProse = [
    " West of House                 Score: 0        Moves: 0",
    " The sign says Forest          Score: 0        Moves: 2"
  ].join("\n")
  assert.equal(Automap.observeFrotzStatusLines(startupWithLaterProse, "startup").length, 1)
})

test("Frotz observer supports clock status and returns observations in raw order", () => {
  const observations = Automap.observeFrotzStatusLines([
    " Kitchen                        Time: 9:05 am",
    "> Attic                         Score: 12      Moves: 41"
  ], "startup")

  assert.equal(observations.length, 2)
  assert.equal(observations[0].label, "Kitchen")
  assert.deepEqual(observations[0].status, { time: "9:05 am" })
  assert.equal(observations[1].label, "Attic")
})

test("raw Zork I replay fixture preserves command and framed-status association", () => {
  const fixture = phase2ReplayFixture()
  assert.deepEqual(fixture.commands, [
    "north", "east", "south", "west", "east", "north", "east", "open window",
    "in", "up", "down", "west", "move rug", "open trap door", "down"
  ])
  assert.deepEqual(fixture.turns.map(turn => turn.observations[0].label), [
    "West of House", "North of House", "Behind House", "South of House", "West of House",
    "West of House", "North of House", "Behind House", "Behind House", "Kitchen", "Attic",
    "Kitchen", "Living Room", "Living Room", "Living Room", "Cellar"
  ])
  assert.deepEqual(fixture.turns.map(turn => turn.observations[0].status.moves),
    Array.from({ length: 16 }, (_, index) => index))
  assert.match(fixture.rawTurns[0], /^ West of House/m)
  for (const rawTurn of fixture.rawTurns.slice(1)) assert.match(rawTurn, /^> /)
})

test("engine-neutral replay builds only fixture-confirmed rooms and traversed edges", () => {
  const fixture = phase2ReplayFixture()
  const cartridge = { engine: "zmachine", sha256: "1".repeat(64) }
  const initial = Automap.createEmptyState(cartridge)
  const first = Automap.replayTurns(initial, fixture.turns)
  const second = Automap.replayTurns(initial, fixture.turns)

  assert.equal(first.stopped, false)
  assert.equal(first.error, "")
  assert.equal(first.processed, fixture.turns.length)
  assert.equal(initial.nodes.length, 0, "replay must not mutate its input state")
  assert.deepEqual(first, second, "replay and layout must be deterministic")
  assert.deepEqual(first.state.nodes.map(node => node.label), [
    "West of House", "North of House", "Behind House", "South of House",
    "Kitchen", "Attic", "Living Room", "Cellar"
  ])
  assert.deepEqual(first.state.edges.map(edge => [
    edge.from, edge.direction, edge.to, edge.traversals
  ]), [
    ["room-1", "north", "room-2", 2],
    ["room-2", "east", "room-3", 2],
    ["room-3", "south", "room-4", 1],
    ["room-4", "west", "room-1", 1],
    ["room-3", "in", "room-5", 1],
    ["room-5", "up", "room-6", 1],
    ["room-6", "down", "room-5", 1],
    ["room-5", "west", "room-7", 1],
    ["room-7", "down", "room-8", 1]
  ])
  assert.equal(first.state.edges.some(edge => edge.from === "room-1" && edge.direction === "east"), false,
    "failed east movement at West of House must not create an edge")
  assert.equal(first.state.edges.some(edge => edge.from === "room-2" && edge.direction === "south"), false,
    "a reverse route that was not traversed must not be fabricated")
  assert.deepEqual(first.state.layout.positions, {
    "room-1": { x: 0, y: 0, z: 0 },
    "room-2": { x: 0, y: -1, z: 0 },
    "room-3": { x: 1, y: -1, z: 0 },
    "room-4": { x: 1, y: 0, z: 0 },
    "room-5": { x: 1, y: -1, z: 1 },
    "room-6": { x: 1, y: -1, z: 2 },
    "room-7": { x: 0, y: -1, z: 1 },
    "room-8": { x: 0, y: -1, z: 0 }
  })
  assert.deepEqual(Automap.validateMapState(first.state), { valid: true, errors: [] })
})

test("replay stops safely on malformed or oversized turn input", () => {
  const initial = Automap.createEmptyState({ engine: "zmachine" })
  const malformed = Automap.replayTurns(initial, [{
    command: "", observations: location("West of House")
  }, {
    command: { movement: "north" }, observations: location("North of House")
  }])
  assert.equal(malformed.stopped, true)
  assert.equal(malformed.error, "malformed-turn:1")
  assert.equal(malformed.processed, 1)
  assert.deepEqual(malformed.state.nodes.map(node => node.label), ["West of House"])
  assert.equal(initial.nodes.length, 0)

  const oversized = Automap.replayTurns(initial, new Array(Automap.LIMITS.replayTurns + 1))
  assert.deepEqual({ processed: oversized.processed, stopped: oversized.stopped, error: oversized.error }, {
    processed: 0, stopped: true, error: "turn-limit"
  })

  const tooManyObservations = Automap.replayTurns(initial, [{
    command: "north",
    observations: new Array(Automap.LIMITS.observations + 1).fill(location("North of House"))
  }])
  assert.equal(tooManyObservations.error, "malformed-turn:0")
  assert.equal(tooManyObservations.state.nodes.length, 0)
})

test("empty state is versioned, deterministic, and valid", () => {
  const cartridge = { engine: "zmachine", sha256: "a".repeat(64) }
  const first = Automap.createEmptyState(cartridge)
  const second = Automap.createEmptyState(cartridge)

  assert.equal(first.schemaVersion, 2)
  assert.deepEqual(first.cartridge, cartridge)
  assert.deepEqual(first.nodes, [])
  assert.deepEqual(first.edges, [])
  assert.deepEqual(first.layout.positions, {})
  assert.equal(first.layout.seed, second.layout.seed)
  assert.deepEqual(Automap.validateMapState(first), { valid: true, errors: [] })
})

test("reducer creates generated room identities and one directed traversed edge", () => {
  const empty = Automap.createEmptyState({ engine: "zmachine" })
  const west = Automap.reduceTurn(empty, "", location("West of House"))
  const north = Automap.reduceTurn(west, "n", location("North of House"))

  assert.equal(empty.nodes.length, 0, "input state must not be mutated")
  assert.deepEqual(north.nodes.map(node => [node.id, node.label]), [
    ["room-1", "West of House"],
    ["room-2", "North of House"]
  ])
  assert.deepEqual(north.edges, [{
    from: "room-1",
    to: "room-2",
    direction: "north",
    command: "n",
    confirmed: true,
    traversals: 1
  }])
  assert.deepEqual(north.layout.positions, {
    "room-1": { x: 0, y: 0, z: 0 },
    "room-2": { x: 0, y: -1, z: 0 }
  })
  assert.equal(north.currentNodeId, "room-2")
  assert.equal(Automap.validateMapState(north).valid, true)
})

test("failed movement and same-location observation create no edge", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("West of House"))
  state = Automap.reduceTurn(state, "west", location("West of House"))

  assert.equal(state.nodes.length, 1)
  assert.equal(state.edges.length, 0)
  assert.equal(state.nodes[0].lastSeen, 2)
})

test("known same-label directional targets win over failed-move inference", () => {
  const state = Automap.createEmptyState({ engine: "zmachine" })
  state.nodes = [{
    id: "room-1", label: "Maze", confidence: "confirmed", firstSeen: 1, lastSeen: 1
  }, {
    id: "room-2", label: "Maze", confidence: "confirmed", firstSeen: 2, lastSeen: 2
  }]
  state.edges = [{
    from: "room-1", to: "room-2", direction: "east", command: "e",
    confirmed: true, traversals: 1
  }]
  state.layout.positions = {
    "room-1": { x: 0, y: 0, z: 0 },
    "room-2": { x: 1, y: 0, z: 0 }
  }
  state.currentNodeId = "room-1"
  state.turn = 2
  assert.equal(Automap.validateMapState(state).valid, true)

  const traversed = Automap.reduceTurn(state, "east", location("Maze"))
  assert.equal(traversed.currentNodeId, "room-2")
  assert.equal(traversed.nodes.length, 2)
  assert.equal(traversed.edges.length, 1)
  assert.equal(traversed.edges[0].traversals, 2)
})

test("reducer never fabricates reverse edges and counts a known traversal", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("West of House"))
  state = Automap.reduceTurn(state, "north", location("North of House"))
  state = Automap.reduceTurn(state, "restore slot.qzl", location("West of House"))

  assert.equal(state.edges.length, 1, "restore must not draw a route")
  assert.equal(state.currentNodeId, "room-1")

  state = Automap.reduceTurn(state, "n", location("North of House"))
  assert.equal(state.edges.length, 1)
  assert.equal(state.edges[0].traversals, 2)
  assert.equal(state.edges.some(edge => edge.direction === "south"), false)
})

test("restore, load, undo, and restart clear pending location before reacquisition", () => {
  for (const command of ["restore", "load slot", "undo", "restart"]) {
    let state = Automap.createEmptyState({ engine: "zmachine" })
    state = Automap.reduceTurn(state, "", location("Kitchen"))
    const waiting = Automap.reduceTurn(state, command, null)
    assert.equal(waiting.currentNodeId, null, command)
    assert.equal(waiting.resyncRequired, true, command)
    assert.equal(waiting.edges.length, 0, command)

    const reacquired = Automap.reduceTurn(waiting, "", location("Kitchen"))
    assert.equal(reacquired.currentNodeId, "room-1", command)
    assert.equal(reacquired.resyncRequired, false, command)
    assert.equal(reacquired.edges.length, 0, command)
  }
})

test("duplicate labels remain separate and ambiguous resynchronization draws nothing", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("Maze"))
  state = Automap.reduceTurn(state, "east", location("Passage"))
  state = Automap.reduceTurn(state, "east", location("Maze"))

  assert.deepEqual(state.nodes.filter(node => node.label === "Maze").map(node => node.id), ["room-1", "room-3"])
  const before = { nodes: state.nodes.length, edges: state.edges.length }
  state = Automap.reduceTurn(state, "undo", location("Maze"))

  assert.equal(state.currentNodeId, null)
  assert.deepEqual(state.candidateNodeIds, ["room-1", "room-3"])
  assert.equal(state.nodes.length, before.nodes)
  assert.equal(state.edges.length, before.edges)

  state = Automap.reduceTurn(state, "east", location("Passage"))
  assert.equal(state.currentNodeId, "room-2", "known candidate routes must reach the navigation branch")
  assert.equal(state.resyncRequired, false)
  assert.equal(state.nodes.length, before.nodes)
  assert.equal(state.edges.length, before.edges)
  assert.equal(state.edges[0].traversals, 1, "ambiguous source does not invent a traversal")
})

test("nonmovement location changes are confirmed but remain unplaced and unconnected", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("Cellar"))
  state = Automap.reduceTurn(state, "wait", location("Forest"))

  assert.equal(state.nodes.length, 2)
  assert.equal(state.edges.length, 0)
  assert.equal(state.currentNodeId, "room-2")
  assert.equal(state.layout.positions["room-2"], undefined)
})

test("uncertain and oversized observations cannot grow confirmed graph truth", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("West of House"))
  const uncertain = Automap.reduceTurn(state, "north", {
    type: "location",
    label: "North of House",
    confidence: "uncertain"
  })
  const oversized = Automap.reduceTurn(state, "north", location("x".repeat(Automap.LIMITS.labelLength + 1)))

  assert.equal(uncertain.nodes.length, 1)
  assert.equal(uncertain.edges.length, 0)
  assert.equal(oversized.nodes.length, 1)
  assert.equal(oversized.edges.length, 0)
})

test("direction vectors produce deterministic compass and vertical coordinates", () => {
  assert.deepEqual(Automap.coordinatesFromDirection({ x: 4, y: 7, z: 1 }, "sw"), { x: 3, y: 8, z: 1 })
  assert.deepEqual(Automap.coordinatesFromDirection({ x: 4, y: 7, z: 1 }, "up"), { x: 4, y: 7, z: 2 })
  assert.deepEqual(Automap.coordinatesFromDirection({ x: 4, y: 7, z: 1 }, "out"), { x: 4, y: 7, z: 0 })
  assert.equal(Automap.coordinatesFromDirection({ x: 0, y: 0, z: 0 }, "look north"), null)
})

test("coordinate overflow leaves a confirmed destination unplaced and state valid", () => {
  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("Boundary"))
  state.layout.positions["room-1"] = { x: Automap.LIMITS.coordinate, y: 0, z: 0 }

  state = Automap.reduceTurn(state, "east", location("Beyond"))
  assert.equal(state.currentNodeId, "room-2")
  assert.equal(state.edges.length, 1)
  assert.equal(state.layout.positions["room-2"], undefined)
  assert.equal(Automap.coordinatesFromDirection({ x: Automap.LIMITS.coordinate, y: 0, z: 0 }, "east"), null)
  assert.deepEqual(Automap.validateMapState(state), { valid: true, errors: [] })
})

test("state validation enforces graph-count bounds", () => {
  const state = Automap.createEmptyState({ engine: "zmachine" })
  state.nodes = Array.from({ length: Automap.LIMITS.nodes + 1 }, (_, index) => ({
    id: `room-${index + 1}`,
    label: `Room ${index + 1}`,
    confidence: "confirmed",
    firstSeen: 0,
    lastSeen: 0
  }))

  const checked = Automap.validateMapState(state)
  assert.equal(checked.valid, false)
  assert.equal(checked.errors.includes("node limit exceeded"), true)
})

test("state validation rejects future schemas, oversized labels, and dangling edges", () => {
  const future = Automap.createEmptyState({ engine: "zmachine" })
  future.schemaVersion = 3
  assert.equal(Automap.validateMapState(future).valid, false)

  let state = Automap.createEmptyState({ engine: "zmachine" })
  state = Automap.reduceTurn(state, "", location("West of House"))
  state.nodes[0].label = "x".repeat(Automap.LIMITS.labelLength + 1)
  assert.equal(Automap.validateMapState(state).valid, false)

  state = Automap.createEmptyState({ engine: "zmachine" })
  state.edges.push({
    from: "room-1", to: "room-2", direction: "north", command: "n",
    confirmed: true, traversals: 1
  })
  assert.equal(Automap.validateMapState(state).valid, false)
})
