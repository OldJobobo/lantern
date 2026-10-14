const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const Automap = require("../Automap.js")
const root = path.resolve(__dirname, "..")
const identity = { engine: "zmachine", sha256: "37084966477dff679282de42974b2077156b1bd68fad92a65d4ea94d8eb64d79" }
const fixture = path.join(__dirname, "fixtures/automap/zork1-room-id-long-play")

// Mirrors the installed observer: native input, metadata, then exactly the next
// matching status line. Neither prose nor a client command queue creates identity.
function replay(raw, initial = Automap.createEmptyState(identity)) {
  let state = initial, pending = null, command = "", status = null
  const frames = []
  for (const line of raw.split("\n")) {
    const input = Automap.parseInputEvent(line)
    if (input) {
      command = input.command
      pending = null
      if (!input.valid || Automap.normalizeControlCommand(command)) state = Automap.resynchronizeState(state)
      continue
    }
    const event = Automap.parseRoomEvent(line)
    if (event) {
      pending = { ...event, command }
      command = ""
      continue
    }
    const framed = Automap.pairRoomStatus(pending, line)
    const previous = pending
    pending = null
    const observation = framed ? framed.observation : Automap.knownRoomObservation(state, previous)
    if (!observation) {
      if (previous) state = Automap.resynchronizeState(state)
      continue
    }
    if (Automap.statusDiscontinuity(status, observation.status)) state = Automap.resynchronizeState(state)
    status = observation.status
    state = Automap.reduceIdentifiedTurn(state, previous.command, observation)
    if (framed) frames.push({ roomId: observation.roomId, label: observation.label, command: previous.command })
  }
  return { state, frames }
}

function run(commands, saveRoot) {
  const result = spawnSync(path.join(root, "runtime/x86_64-linux/dfrotz"),
    ["-q", "-m", "-s", "1", "-w", "76", "-R", saveRoot, path.join(root, "games/zork1.z3")],
    { input: commands, encoding: "utf8", env: { ...process.env, LANTERN_ROOM_EVENTS: "1" }, timeout: 10000 })
  assert.equal(result.status, 0, result.stderr)
  return result.stdout
}

function location(id, label) {
  return { type: "location", engine: "zmachine", confidence: "confirmed", roomId: `room-${id}`, label }
}

test("recorded long play has exactly nine authoritative rooms and reuses every revisited edge", () => {
  const raw = fs.readFileSync(`${fixture}.raw`, "utf8")
  const { state, frames } = replay(raw)
  assert.equal(frames.length, 31)
  assert.equal(new Set(frames.map(frame => frame.roomId)).size, 9)
  assert.equal(state.nodes.length, 9)
  assert.equal(state.nodes.filter(node => node.label === "Forest").length, 2)
  assert.equal(state.nodes.filter(node => node.label === "Clearing").length, 2)
  const expected = new Map()
  for (let index = 1; index < frames.length; index++) {
    const from = frames[index - 1].roomId, to = frames[index].roomId
    const direction = Automap.normalizeMovementCommand(frames[index].command)
    if (from !== to && direction) {
      const key = `${from}:${direction}:${to}`
      expected.set(key, (expected.get(key) || 0) + 1)
    }
  }
  assert.equal(state.edges.length, expected.size)
  for (const edge of state.edges) assert.equal(edge.traversals, expected.get(`${edge.from}:${edge.direction}:${edge.to}`))
  assert.equal(Automap.validateMapState(state).valid, true)
})

test("bundled patched runtime reproduces the recorded identities and traversal counts", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-room-identity-"))
  try {
    const commands = fs.readFileSync(`${fixture}.commands`, "utf8")
    const actual = replay(run(commands, directory))
    const recorded = replay(fs.readFileSync(`${fixture}.raw`, "utf8"))
    assert.deepEqual(actual, recorded)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})

test("1,600 real backtracking moves keep nine rooms and fifteen routes", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-room-identity-"))
  try {
    const commands = ["n", "n", "n", "s", "e", "w", "w", "n", "e", "s"]
      .concat(Array.from({ length: 400 }, () => ["w", "n", "e", "s"]).flat(), ["quit", "y"])
    const { state } = replay(run(commands.join("\n") + "\n", directory))
    assert.equal(state.nodes.length, 9)
    assert.equal(state.edges.length, 15)
    assert.equal(state.edges.find(edge => edge.from === "room-64" && edge.to === "room-137").traversals, 400)
    assert.equal(Automap.validatePersistentState(Automap.toPersistentState(state)).valid, true)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})

test("identity survives non-Euclidean backtracking, renamed titles and coordinate collisions", () => {
  let state = Automap.createEmptyState(identity)
  state = Automap.reduceIdentifiedTurn(state, "", location(64, "West of House"))
  state = Automap.reduceIdentifiedTurn(state, "east", location(32, "Forest"))
  state = Automap.reduceIdentifiedTurn(state, "east", location(64, "House, West Side"))
  state = Automap.reduceIdentifiedTurn(state, "east", location(32, "Forest"))
  assert.equal(state.nodes.length, 2)
  assert.equal(state.edges.length, 2)
  assert.equal(state.edges[0].traversals, 2)
  assert.equal(state.nodes[0].label, "House, West Side")
  state = Automap.reduceIdentifiedTurn(Automap.resynchronizeState(state), "north", location(87, "Forest"))
  assert.equal(state.nodes.length, 3)
  assert.equal(state.edges.length, 2)
  assert.notDeepEqual(state.layout.positions["room-87"], state.layout.positions["room-32"])
})

function cellKey(position) { return `${position.x}:${position.y}:${position.z}` }
function projected(position) { return { x: position.x * 148 + position.z * 46, y: position.y * 106 - position.z * 72 } }

// True when the straight route between two rooms passes through a third room.
function routeCrossesRoom(state, edge) {
  const from = projected(state.layout.positions[edge.from]), to = projected(state.layout.positions[edge.to])
  return Object.entries(state.layout.positions).some(([id, position]) => {
    if (id === edge.from || id === edge.to) return false
    const box = projected(position)
    for (let sample = 1; sample < 16; sample++) {
      const t = sample / 16
      if (Math.abs(from.x + (to.x - from.x) * t - box.x) < 54 && Math.abs(from.y + (to.y - from.y) * t - box.y) < 29) return true
    }
    return false
  })
}

// Wintermute dogfood routes. Clearing east leads to a Forest whose implied cell
// is North of House; the house loop reuses cells the forest already holds.
const sessionTurns = [["", 64, "West of House"], ["n", 137, "North of House"], ["n", 238, "Forest Path"],
  ["s", 137, "North of House"], ["w", 64, "West of House"], ["w", 87, "Forest"], ["n", 160, "Clearing"],
  ["e", 32, "Forest"], ["e", 167, "Forest"], ["s", 32, "Forest"], ["s", 128, "Clearing"]]
const exploreTurns = [["", 64, "West of House"], ["n", 137, "North of House"], ["n", 238, "Forest Path"],
  ["u", 5, "Up a Tree"], ["d", 238, "Forest Path"], ["s", 137, "North of House"], ["e", 85, "Behind House"],
  ["w", 27, "Kitchen"], ["w", 75, "Living Room"], ["e", 27, "Kitchen"], ["e", 85, "Behind House"],
  ["s", 209, "South of House"], ["w", 64, "West of House"], ["w", 87, "Forest"], ["n", 160, "Clearing"],
  ["e", 32, "Forest"], ["e", 167, "Forest"], ["s", 32, "Forest"], ["s", 128, "Clearing"]]

for (const [name, turns] of [["session", sessionTurns], ["exploration", exploreTurns]]) {
  test(`non-Euclidean ${name} places rooms in free cells, never moves them, and keeps routes clear`, () => {
    let state = Automap.createEmptyState(identity)
    const placed = {}
    for (const [command, id, label] of turns) {
      state = Automap.reduceIdentifiedTurn(state, command, location(id, label))
      for (const known of Object.keys(placed)) assert.deepEqual(state.layout.positions[known], placed[known])
      placed[`room-${id}`] = state.layout.positions[`room-${id}`]
    }
    const cells = Object.values(state.layout.positions).map(cellKey)
    assert.equal(new Set(cells).size, state.nodes.length)
    assert.deepEqual(state.layout.positions["room-64"], { x: 0, y: 0, z: 0 })
    assert.deepEqual(state.layout.positions["room-137"], { x: 0, y: -1, z: 0 })
    for (const edge of state.edges) assert.equal(routeCrossesRoom(state, edge), false, `${edge.from} -> ${edge.to}`)
    assert.equal(Automap.validatePersistentState(Automap.toPersistentState(state)).valid, true)
  })
}

test("restore/restart reacquires actual identity without adding a teleport edge", () => {
  let state = Automap.reduceIdentifiedTurn(Automap.createEmptyState(identity), "", location(64, "West of House"))
  state = Automap.reduceIdentifiedTurn(state, "north", location(137, "North of House"))
  state = Automap.reduceIdentifiedTurn(state, "restore", location(64, "West of House"))
  assert.equal(state.nodes.length, 2)
  assert.equal(state.edges.length, 1)
  assert.equal(state.currentNodeId, "room-64")
  const hydrated = Automap.hydratePersistentState(Automap.serializePersistentState(state))
  state = Automap.reduceIdentifiedTurn(hydrated, "north", location(137, "North of House"))
  assert.equal(state.edges.length, 1)
  assert.equal(state.edges[0].traversals, 1)
  assert.equal(state.currentNodeId, "room-137")
})

test("missing identity, malformed events and mismatched status cannot fall back to names or coordinates", () => {
  let state = Automap.reduceIdentifiedTurn(Automap.createEmptyState(identity), "", location(64, "West of House"))
  state = Automap.reduceIdentifiedTurn(state, "north", { ...location(137, "North of House"), roomId: undefined })
  assert.equal(state.nodes.length, 1)
  assert.equal(state.currentNodeId, null)
  assert.equal(state.resyncRequired, true)
  for (const raw of ["\x1eLANTERN_ROOM_V1 0 0 0\x1f", "\x1eLANTERN_ROOM_V1 256 0 0\x1f",
    "\x1eLANTERN_ROOM_V1 64 32768 0\x1f", "\x1eLANTERN_ROOM_V1 64 0 65536\x1f",
    "\x1eLANTERN_ROOM_V1 064 0 0\x1f", "\x1eLANTERN_ROOM_V1 64 0 0\x1f extra"]) assert.equal(Automap.parseRoomEvent(raw), null)
  const event = Automap.parseRoomEvent("\x1eLANTERN_ROOM_V1 64 -1 2\x1f")
  assert.equal(Automap.pairRoomStatus(event, " West of House    Score: 0   Moves: 2"), null)
  assert.equal(Automap.pairRoomStatus(event, " West of House    Score: -1   Moves: 3"), null)
  assert.equal(Automap.pairRoomStatus(event, "West of House"), null)
  assert.equal(Automap.pairRoomStatus(event, " West of House    Score: -1   Moves: 2").observation.roomId, "room-64")
})

test("native death status precedes prose and never creates a resurrection route", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-room-identity-"))
  try {
    const recorded = fs.readFileSync(path.join(__dirname, "fixtures/automap/zork1-room-id-death.raw"), "utf8")
    const commands = fs.readFileSync(path.join(__dirname, "fixtures/automap/zork1-death.commands"), "utf8") + "\n"
    const actual = run(commands, directory)
    assert.ok(actual.indexOf("LANTERN_ROOM_V1 87 25 9") < actual.indexOf("You have died"))
    const { state, frames } = replay(actual)
    assert.deepEqual({ state, frames }, replay(recorded))
    assert.equal(state.edges.some(edge => edge.from === "room-33" && edge.to === "room-87"), false)
    assert.equal(state.edges.some(edge => edge.from === "room-87" && edge.to === "room-160"), true)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})

test("input records are bounded, preserve actual VM commands and hide only metadata", () => {
  assert.deepEqual(Automap.parseInputEvent(">\x1eLANTERN_INPUT_V1 6e6f727468\x1f"), { valid: true, command: "north" })
  assert.deepEqual(Automap.parseInputEvent("\x1eLANTERN_INPUT_V1 !\x1f"), { valid: false, command: "" })
  assert.equal(Automap.parseInputEvent(`\x1eLANTERN_INPUT_V1 ${"61".repeat(97)}\x1f`), null)
  assert.equal(Automap.parseInputEvent("\x1eLANTERN_INPUT_V1 a\x1f"), null)
  assert.deepEqual(Automap.parseInputEvent("\x1eLANTERN_INPUT_V1 0a\x1f"), { valid: false, command: "" })
  assert.equal(Automap.stripRoomMetadata(">\x1eLANTERN_INPUT_V1 6e\x1f"), "")
  assert.equal(Automap.stripRoomMetadata("Continue? >\x1eLANTERN_INPUT_V1 79\x1f"), "Continue? >")
  assert.equal(Automap.stripRoomMetadata("\x1eLANTERN_ROOM_V1 64 0 0\x1f"), "")
  assert.equal(Automap.stripRoomMetadata("Ordinary game text"), "Ordinary game text")
})

test("real quit cancellation and restart do not misassociate a later movement", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-room-identity-"))
  try {
    const raw = run("north\nquit\nn\nwest\nrestart\ny\nnorth\nquit\ny\n", directory)
    const { state } = replay(raw)
    assert.equal(state.nodes.length, 2)
    assert.equal(state.edges.length, 2)
    const outward = state.edges.find(edge => edge.from === "room-64")
    assert.equal(outward.direction, "north")
    assert.equal(outward.to, "room-137")
    assert.equal(outward.traversals, 2)
    assert.equal(state.edges.find(edge => edge.from === "room-137").direction, "west")
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})

test("real save/restore resynchronizes even when restoring to a greater move count", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-room-identity-"))
  try {
    const raw = run("north\nsave\nidentity-test\nrestart\ny\nrestore\nidentity-test\nwest\nquit\ny\n", directory)
    const { state } = replay(raw)
    assert.equal(state.nodes.length, 2)
    assert.equal(state.edges.length, 2)
    assert.equal(state.edges.find(edge => edge.from === "room-137").direction, "west")
    assert.equal(state.edges.filter(edge => edge.from === "room-64").length, 1)
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})
