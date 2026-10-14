const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const Automap = require("../Automap.js")

const root = path.resolve(__dirname, "..")
const helper = path.join(root, "bin/lantern-map-state")
const engine = "zmachine"
const sha256 = "a".repeat(64)

function location(label) {
  return { type: "location", engine, label, confidence: "confirmed" }
}

function sessionState() {
  let state = Automap.createEmptyState({ engine, sha256 })
  state = Automap.reduceTurn(state, "", location("West of House"))
  state = Automap.reduceTurn(state, "north", location("North of House"))
  return state
}

function stateWithLabel(label) {
  let state = Automap.createEmptyState({ engine, sha256 })
  state = Automap.reduceTurn(state, "", location(label))
  return state
}

function helperEnvironment(stateRoot) {
  return { ...process.env, XDG_STATE_HOME: stateRoot, HOME: stateRoot }
}

function runHelper(stateRoot, operation, keyEngine = engine, keySha = sha256, input) {
  return spawnSync(helper, [operation, keyEngine, keySha], {
    env: helperEnvironment(stateRoot),
    input,
    encoding: "utf8",
    timeout: 5000,
    maxBuffer: 8 * 1024 * 1024
  })
}

function targetPath(stateRoot, keyEngine = engine, keySha = sha256) {
  return path.join(stateRoot, "lantern/maps", `${keyEngine}-v2-${keySha}.json`)
}

function mode(file) {
  return fs.statSync(file).mode & 0o777
}

function replaceRequired(text, from, to) {
  assert.ok(text.includes(from), `missing replacement source: ${from}`)
  return text.replace(from, to)
}

test("persistence projection strips session fields and hydration requires fresh evidence", () => {
  const session = sessionState()
  assert.equal(session.currentNodeId, "room-2")
  const persistent = Automap.toPersistentState(session)

  assert.deepEqual(Object.keys(persistent), ["schemaVersion", "cartridge", "nodes", "edges", "layout", "turn"])
  for (const sessionField of ["currentNodeId", "candidateNodeIds", "resyncRequired"])
    assert.equal(Object.hasOwn(persistent, sessionField), false)
  assert.equal(persistent.turn, session.turn, "turn is persisted for monotonic timestamps")
  assert.deepEqual(Automap.validatePersistentState(persistent), { valid: true, errors: [] })

  const json = Automap.serializePersistentState(session)
  assert.deepEqual(JSON.parse(json), persistent)
  const hydrated = Automap.hydratePersistentState(json)
  assert.equal(hydrated.currentNodeId, null)
  assert.deepEqual(hydrated.candidateNodeIds, [])
  assert.equal(hydrated.resyncRequired, true)
  assert.equal(hydrated.turn, session.turn)
  assert.deepEqual(hydrated.layout, session.layout)

  const reacquired = Automap.reduceTurn(hydrated, "", location("North of House"))
  assert.equal(reacquired.currentNodeId, "room-2")
  assert.equal(reacquired.edges.length, session.edges.length)
  assert.equal(reacquired.turn, session.turn + 1)
  assert.equal(reacquired.nodes[1].lastSeen, session.turn + 1)
})

test("persistent state rejects session fields, empty identity, future schemas, timestamp rollback, and corrupt JSON", () => {
  const persistent = Automap.toPersistentState(sessionState())
  assert.throws(() => Automap.toPersistentState(Automap.createEmptyState()), /engine is required/)
  assert.throws(() => Automap.hydratePersistentState("{"), /invalid persistent automap JSON/)
  assert.throws(() => Automap.hydratePersistentState({ ...persistent, schemaVersion: 3 }), /schemaVersion/)
  assert.throws(() => Automap.hydratePersistentState({ ...persistent, currentNodeId: "room-1" }), /invalid fields/)

  const rollback = JSON.parse(JSON.stringify(persistent))
  rollback.turn = 0
  assert.throws(() => Automap.hydratePersistentState(rollback), /timestamp exceeds persisted turn/)
  assert.throws(() => Automap.hydratePersistentState("x".repeat(Automap.LIMITS.persistenceBytes + 1)), /byte limit/)

  let multibyte = Automap.createEmptyState({ engine, sha256 })
  multibyte = Automap.reduceTurn(multibyte, "", location("é".repeat(100)))
  assert.equal(Automap.validateMapState(multibyte).valid, true)
  assert.throws(() => Automap.toPersistentState(multibyte), /label exceeds byte limit/)
})

test("JS and native persistence agree on decoded Unicode and control-label bounds", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const rawMultibyte = Automap.serializePersistentState(stateWithLabel("Café"))
    assert.equal(runHelper(stateRoot, "write", engine, sha256, rawMultibyte).status, 0)
    assert.equal(Automap.hydratePersistentState(runHelper(stateRoot, "read").stdout).nodes[0].label, "Café")

    const escapedMultibyte = rawMultibyte.replace("Café", "Caf\\u00e9")
    assert.equal(runHelper(stateRoot, "write", engine, sha256, escapedMultibyte).status, 0)
    assert.equal(Automap.hydratePersistentState(runHelper(stateRoot, "read").stdout).nodes[0].label, "Café")

    const rawPair = Automap.serializePersistentState(stateWithLabel("Room 😀"))
    const escapedPair = rawPair.replace("😀", "\\ud83d\\ude00")
    assert.equal(runHelper(stateRoot, "write", engine, sha256, rawPair).status, 0)
    assert.equal(runHelper(stateRoot, "write", engine, sha256, escapedPair).status, 0)
    assert.equal(Automap.hydratePersistentState(runHelper(stateRoot, "read").stdout).nodes[0].label, "Room 😀")

    const internalNbsp = Automap.serializePersistentState(stateWithLabel("North\u00a0Hall"))
    assert.equal(runHelper(stateRoot, "write", engine, sha256, internalNbsp).status, 0)
    assert.equal(Automap.hydratePersistentState(runHelper(stateRoot, "read").stdout).nodes[0].label, "North\u00a0Hall")

    const trimWhitespace = [
      "\u00a0", "\u1680", "\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005",
      "\u2006", "\u2007", "\u2008", "\u2009", "\u200a", "\u2028", "\u2029", "\u202f",
      "\u205f", "\u3000", "\ufeff"
    ]
    const validRoom = Automap.toPersistentState(stateWithLabel("Room"))
    const validRoomJson = JSON.stringify(validRoom)
    for (const whitespace of trimWhitespace) {
      for (const invalidLabel of [whitespace + "Room", "Room" + whitespace]) {
        const invalid = JSON.parse(validRoomJson)
        invalid.nodes[0].label = invalidLabel
        assert.equal(Automap.validatePersistentState(invalid).valid, false)
        assert.notEqual(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(invalid)).status, 0)
      }
      const escaped = `\\u${whitespace.charCodeAt(0).toString(16).padStart(4, "0")}`
      for (const escapedLabel of [escaped + "Room", "Room" + escaped]) {
        const escapedJson = validRoomJson.replace('"label":"Room"', `"label":"${escapedLabel}"`)
        assert.notEqual(runHelper(stateRoot, "write", engine, sha256, escapedJson).status, 0)
      }
    }

    const decodedTooLong = Automap.toPersistentState(stateWithLabel("Valid"))
    decodedTooLong.nodes[0].label = "é".repeat(65)
    assert.equal(Automap.validatePersistentState(decodedTooLong).valid, false)
    const escapedTooLong = JSON.stringify(decodedTooLong).replace("é".repeat(65), "\\u00e9".repeat(65))
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, escapedTooLong).status, 0)

    for (const invalidLabel of ["tab\troom", "control\u0001room", "delete\u007froom", "lone\ud800room"]) {
      const invalid = Automap.toPersistentState(stateWithLabel("Valid"))
      invalid.nodes[0].label = invalidLabel
      assert.equal(Automap.validatePersistentState(invalid).valid, false)
      assert.throws(() => Automap.hydratePersistentState(invalid), /invalid persistent automap state/)
      assert.notEqual(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(invalid)).status, 0)
    }

    const validBytes = Buffer.from(Automap.serializePersistentState(stateWithLabel("WXYZ")))
    const labelOffset = validBytes.indexOf(Buffer.from("WXYZ"))
    assert.ok(labelOffset >= 0)
    for (const invalidBytes of [
      [0xc0, 0xaf, 0x59, 0x5a],
      [0xed, 0xa0, 0x80, 0x5a],
      [0xf4, 0x90, 0x80, 0x80],
      [0xf5, 0x80, 0x80, 0x80],
      [0xff, 0x58, 0x59, 0x5a]
    ]) {
      const malformed = Buffer.from(validBytes)
      Buffer.from(invalidBytes).copy(malformed, labelOffset)
      assert.notEqual(runHelper(stateRoot, "write", engine, sha256, malformed).status, 0)
    }
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("persistent edge commands use native ASCII whitespace grammar and decoded-byte bounds", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const persistent = Automap.toPersistentState(sessionState())
    const acceptedCommands = [" \tGo\t NORTH ", " ".repeat(91) + "north"]
    for (const command of acceptedCommands) {
      const candidate = JSON.parse(JSON.stringify(persistent))
      candidate.edges[0].command = command
      assert.deepEqual(Automap.validatePersistentState(candidate), { valid: true, errors: [] })
      assert.equal(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(candidate)).status, 0)
    }

    assert.equal(Automap.normalizeMovementCommand("\u00a0north\u00a0"), "north",
      "transient command handling remains user-friendly")
    assert.equal(Automap.normalizeMovementCommand("\fnorth\f"), "north")
    for (const command of ["\u00a0north\u00a0", "\fnorth\f", " ".repeat(92) + "north"]) {
      const candidate = JSON.parse(JSON.stringify(persistent))
      candidate.edges[0].command = command
      assert.equal(Automap.validatePersistentState(candidate).valid, false)
      assert.notEqual(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(candidate)).status, 0)
    }
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("native numeric parsing matches JSON.parse integer and range semantics", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const base = Automap.serializePersistentState(sessionState())
    const seed = Automap.toPersistentState(sessionState()).layout.seed
    let accepted = base
    accepted = replaceRequired(accepted, '"schemaVersion":2', '"schemaVersion":2e0')
    accepted = replaceRequired(accepted, '"firstSeen":1', '"firstSeen":1.0')
    accepted = replaceRequired(accepted, '"lastSeen":1', '"lastSeen":1e0')
    accepted = replaceRequired(accepted, '"firstSeen":2', '"firstSeen":2.0')
    accepted = replaceRequired(accepted, '"lastSeen":2', '"lastSeen":2e0')
    accepted = replaceRequired(accepted, '"traversals":1', '"traversals":1.0')
    accepted = replaceRequired(accepted, `"seed":${seed}`, `"seed":${seed}.0`)
    accepted = replaceRequired(accepted, '"x":0', '"x":-0')
    accepted = replaceRequired(accepted, '"y":0', '"y":0e0')
    accepted = replaceRequired(accepted, '"z":0', '"z":0.0')
    accepted = replaceRequired(accepted, '"y":-1', '"y":-1e0')
    accepted = replaceRequired(accepted, '"turn":2', '"turn":2e0')
    assert.deepEqual(Automap.validatePersistentState(JSON.parse(accepted)), { valid: true, errors: [] })
    assert.equal(runHelper(stateRoot, "write", engine, sha256, accepted).status, 0)

    const empty = Automap.serializePersistentState(Automap.createEmptyState({ engine, sha256 }))
    const negativeZeroTurn = replaceRequired(empty, '"turn":0', '"turn":-0')
    assert.deepEqual(Automap.validatePersistentState(JSON.parse(negativeZeroTurn)), { valid: true, errors: [] })
    assert.equal(runHelper(stateRoot, "write", engine, sha256, negativeZeroTurn).status, 0)

    const longIntegral = "2." + "0".repeat(16 * 1024)
    const longIntegralTurn = replaceRequired(base, '"turn":2', `"turn":${longIntegral}`)
    assert.deepEqual(Automap.validatePersistentState(JSON.parse(longIntegralTurn)), { valid: true, errors: [] })
    assert.equal(runHelper(stateRoot, "write", engine, sha256, longIntegralTurn).status, 0)

    const longFraction = "2.5" + "0".repeat(16 * 1024)
    const longFractionTurn = replaceRequired(base, '"turn":2', `"turn":${longFraction}`)
    assert.equal(Automap.validatePersistentState(JSON.parse(longFractionTurn)).valid, false)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, longFractionTurn).status, 0)
    const longMalformed = longIntegral + "e"
    assert.throws(() => JSON.parse(replaceRequired(base, '"turn":2', `"turn":${longMalformed}`)), SyntaxError)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256,
      replaceRequired(base, '"turn":2', `"turn":${longMalformed}`)).status, 0)

    const rejected = [
      ['"schemaVersion":2', '"schemaVersion":2.5'],
      ['"firstSeen":1', '"firstSeen":1.5'],
      ['"traversals":1', '"traversals":1e-1'],
      [`"seed":${seed}`, `"seed":${seed}.5`],
      ['"x":0', '"x":0.5'],
      ['"x":0', '"x":1000001'],
      ['"turn":2', '"turn":2.5'],
      ['"turn":2', '"turn":2147483648'],
      ['"turn":2', '"turn":02'],
      ['"turn":2', '"turn":+2'],
      ['"turn":2', '"turn":.2'],
      ['"turn":2', '"turn":2.'],
      ['"turn":2', '"turn":2e'],
      ['"turn":2', '"turn":NaN'],
      ['"turn":2', '"turn":Infinity']
    ]
    for (const [from, to] of rejected) {
      const candidate = replaceRequired(base, from, to)
      assert.notEqual(runHelper(stateRoot, "write", engine, sha256, candidate).status, 0, to)
      try {
        assert.equal(Automap.validatePersistentState(JSON.parse(candidate)).valid, false, to)
      } catch (error) {
        assert.ok(error instanceof SyntaxError, to)
      }
    }
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("native helper roundtrips, overwrites, and resets exact-key state with private modes", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const first = Automap.serializePersistentState(sessionState())
    const written = runHelper(stateRoot, "write", engine, sha256, first)
    assert.equal(written.status, 0, written.stderr)

    const lanternDir = path.join(stateRoot, "lantern")
    const mapsDir = path.join(lanternDir, "maps")
    const target = targetPath(stateRoot)
    assert.equal(mode(lanternDir), 0o700)
    assert.equal(mode(mapsDir), 0o700)
    assert.equal(mode(target), 0o600)
    assert.deepEqual(fs.readdirSync(mapsDir), [path.basename(target)])

    const readFirst = runHelper(stateRoot, "read")
    assert.equal(readFirst.status, 0, readFirst.stderr)
    assert.equal(readFirst.stdout, first)

    let updatedSession = Automap.hydratePersistentState(readFirst.stdout)
    updatedSession = Automap.reduceTurn(updatedSession, "", location("North of House"))
    updatedSession = Automap.reduceTurn(updatedSession, "east", location("Behind House"))
    const second = Automap.serializePersistentState(updatedSession)
    assert.equal(runHelper(stateRoot, "write", engine, sha256, second).status, 0)
    assert.equal(runHelper(stateRoot, "read").stdout, second)
    assert.equal(mode(target), 0o600)
    assert.equal(fs.readdirSync(mapsDir).some(name => name.includes(".tmp.")), false)

    assert.equal(runHelper(stateRoot, "reset").status, 0)
    assert.equal(fs.existsSync(target), false)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.equal(runHelper(stateRoot, "reset").status, 0, "reset is idempotent")
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("v2 read/write/reset preserves legacy v1 maps byte-for-byte in a separate namespace", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const maps = path.join(stateRoot, "lantern/maps")
    fs.mkdirSync(maps, { recursive: true, mode: 0o700 })
    const legacyPath = path.join(maps, `${engine}-${sha256}.json`)
    const current = Automap.toPersistentState(sessionState())
    const legacy = JSON.stringify({ ...current, schemaVersion: 1 })
    fs.writeFileSync(legacyPath, legacy, { mode: 0o600 })
    const inode = fs.statSync(legacyPath).ino
    assert.throws(() => Automap.hydratePersistentState(legacy), /schemaVersion/)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.equal(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(current)).status, 0)
    assert.deepEqual(JSON.parse(runHelper(stateRoot, "read").stdout), current)
    assert.equal(runHelper(stateRoot, "reset").status, 0)
    assert.equal(fs.readFileSync(legacyPath, "utf8"), legacy)
    assert.equal(fs.statSync(legacyPath).ino, inode)
    assert.equal(mode(legacyPath), 0o600)
    assert.deepEqual(fs.readdirSync(maps), [path.basename(legacyPath)])
  } finally { fs.rmSync(stateRoot, { recursive: true, force: true }) }
})

test("native helper rejects unsafe hierarchy modes and symlinks while reset distinguishes absence", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const json = Automap.serializePersistentState(sessionState())
    assert.equal(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    const lantern = path.join(stateRoot, "lantern")
    const maps = path.join(lantern, "maps")

    fs.chmodSync(maps, 0o750)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)
    fs.chmodSync(maps, 0o700)

    fs.chmodSync(lantern, 0o755)
    assert.equal(runHelper(stateRoot, "read").status, 0, "v0.1.7 shared state parent is compatible")
    assert.equal(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.equal(mode(lantern), 0o755, "upgrade must not chmod existing directories")
    fs.chmodSync(lantern, 0o777)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }

  const absentRoot = path.join(root, `.test-map-absent-${process.pid}-${Date.now()}`, "nested")
  assert.equal(runHelper(absentRoot, "reset").status, 0, "genuinely absent hierarchy is reset-safe")

  const symlinkRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const destination = path.join(symlinkRoot, "elsewhere")
    fs.mkdirSync(destination, { mode: 0o700 })
    fs.symlinkSync(destination, path.join(symlinkRoot, "lantern"))
    assert.notEqual(runHelper(symlinkRoot, "reset").status, 0)
  } finally {
    fs.rmSync(symlinkRoot, { recursive: true, force: true })
  }
})

test("native helper securely creates a pristine HOME fallback hierarchy", () => {
  const home = fs.mkdtempSync(path.join(root, ".test-map-home-"))
  try {
    const env = { ...process.env, HOME: home }
    delete env.XDG_STATE_HOME
    const json = Automap.serializePersistentState(sessionState())
    const written = spawnSync(helper, ["write", engine, sha256], {
      env, input: json, encoding: "utf8", timeout: 5000
    })
    assert.equal(written.status, 0, written.stderr)

    const stateRoot = path.join(home, ".local/state")
    for (const directory of [
      path.join(home, ".local"), stateRoot, path.join(stateRoot, "lantern"), path.join(stateRoot, "lantern/maps")
    ]) assert.equal(mode(directory), 0o700, directory)
    assert.equal(mode(targetPath(stateRoot)), 0o600)

    const read = spawnSync(helper, ["read", engine, sha256], { env, encoding: "utf8", timeout: 5000 })
    assert.equal(read.status, 0)
    assert.equal(read.stdout, json)
  } finally {
    fs.rmSync(home, { recursive: true, force: true })
  }
})

test("native helper rejects bad operations, keys, key/state mismatch, and oversized stdin", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const json = Automap.serializePersistentState(sessionState())
    for (const args of [
      ["write", "../zmachine", sha256],
      ["write", engine, "A".repeat(64)],
      ["write", engine, "a".repeat(63)],
      ["delete", engine, sha256]
    ]) {
      const result = spawnSync(helper, args, { env: helperEnvironment(stateRoot), input: json, encoding: "utf8" })
      assert.notEqual(result.status, 0, args.join(" "))
    }
    assert.notEqual(runHelper(stateRoot, "write", "glulx", sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256,
      "x".repeat(Automap.LIMITS.persistenceBytes + 1)).status, 0)
    assert.equal(fs.readdirSync(path.join(stateRoot, "lantern/maps")).length, 0,
      "invalid writes must not create a target or temporary file")
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("native helper rejects corrupt, future, excessive, and structurally invalid JSON", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const valid = Automap.toPersistentState(sessionState())
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, "{").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256,
      JSON.stringify({ ...valid, schemaVersion: 3 })).status, 0)

    const longLabel = JSON.parse(JSON.stringify(valid))
    longLabel.nodes[0].label = "x".repeat(Automap.LIMITS.labelLength + 1)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, JSON.stringify(longLabel)).status, 0)

    const excessiveNodes = Automap.toPersistentState(Automap.createEmptyState({ engine, sha256 }))
    excessiveNodes.nodes = Array.from({ length: Automap.LIMITS.nodes + 1 }, (_, index) => ({
      id: `room-${index + 1}`, label: "Room", confidence: "confirmed", firstSeen: 0, lastSeen: 0
    }))
    const nodeJson = JSON.stringify(excessiveNodes)
    assert.ok(nodeJson.length < Automap.LIMITS.persistenceBytes)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, nodeJson).status, 0)

    const excessiveEdges = Automap.toPersistentState(Automap.createEmptyState({ engine, sha256 }))
    excessiveEdges.nodes = [{
      id: "room-1", label: "One", confidence: "confirmed", firstSeen: 0, lastSeen: 0
    }, {
      id: "room-2", label: "Two", confidence: "confirmed", firstSeen: 0, lastSeen: 0
    }]
    excessiveEdges.edges = Array.from({ length: Automap.LIMITS.edges + 1 }, () => ({
      from: "room-1", to: "room-2", direction: "north", command: "n", confirmed: true, traversals: 1
    }))
    const edgeJson = JSON.stringify(excessiveEdges)
    assert.ok(edgeJson.length < Automap.LIMITS.persistenceBytes)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, edgeJson).status, 0)
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("native helper fails closed on corrupt targets, symlinks, and non-regular files", () => {
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-state-"))
  try {
    const json = Automap.serializePersistentState(sessionState())
    assert.equal(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    const target = targetPath(stateRoot)

    fs.writeFileSync(target, "{", { mode: 0o600 })
    fs.chmodSync(target, 0o600)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)

    fs.rmSync(target, { force: true })
    const protectedFile = path.join(stateRoot, "protected.json")
    fs.writeFileSync(protectedFile, "do not replace")
    fs.symlinkSync(protectedFile, target)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)
    assert.equal(fs.readFileSync(protectedFile, "utf8"), "do not replace")

    fs.rmSync(target, { force: true })
    assert.equal(spawnSync("mkfifo", [target]).status, 0)
    const fifoRead = runHelper(stateRoot, "read")
    assert.equal(fifoRead.error, undefined)
    assert.notEqual(fifoRead.status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("native helper rejects wrong-owner targets and helper directories where ownership changes are permitted", t => {
  if (typeof process.getuid !== "function" || process.getuid() !== 0) {
    t.skip("requires root to construct a wrong-owner regular file")
    return
  }
  const stateRoot = fs.mkdtempSync(path.join(root, ".test-map-owner-"))
  try {
    const json = Automap.serializePersistentState(sessionState())
    assert.equal(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    const target = targetPath(stateRoot)
    const maps = path.dirname(target)
    fs.chownSync(target, 65534, 65534)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)

    fs.chownSync(target, 0, 0)
    fs.chownSync(maps, 65534, 65534)
    assert.notEqual(runHelper(stateRoot, "read").status, 0)
    assert.notEqual(runHelper(stateRoot, "write", engine, sha256, json).status, 0)
    assert.notEqual(runHelper(stateRoot, "reset").status, 0)
  } finally {
    fs.rmSync(stateRoot, { recursive: true, force: true })
  }
})

test("map-state helper ships as a hardened reproducible native executable", () => {
  const build = fs.readFileSync(path.join(root, "scripts/build-map-state-helper"), "utf8")
  const source = fs.readFileSync(path.join(root, "bin/lantern-map-state.c"), "utf8")
  const provenance = fs.readFileSync(path.join(root, "docs/map-state-helper.md"), "utf8")
  const binary = fs.readFileSync(helper)

  assert.deepEqual([...binary.subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  assert.equal(fs.statSync(helper).mode & 0o111, 0o111)
  assert.match(build, /gcc:14\.2\.0-bookworm@sha256:82549aa8f90ada3236a8be70c74543132a76662ef33f0c3271ed802b81584a82/)
  for (const required of ["--platform linux/amd64", "SOURCE_DATE_EPOCH=0", "--build-id=none", "-fstack-protector-strong", "-z,relro,-z,now"])
    assert.ok(build.includes(required), required)
  for (const required of [
    "O_NOFOLLOW", "AT_SYMLINK_NOFOLLOW", "mkdirat", "fsync(parent)", "fsync(descriptor)",
    "fsync(maps)", "renameat", "MAX_STATE_BYTES", "append_raw_utf8", "parse_hex_quad"
  ]) assert.ok(source.includes(required), required)
  assert.match(provenance, /turn counter is persisted deliberately/i)
  assert.match(provenance, /standard input/)
})
