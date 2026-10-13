const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const crypto = require("node:crypto")
const Automap = require("../Automap.js")
const Model = require("../Model.js")
const root = path.resolve(__dirname, "..")

test("automap support is fingerprint-based and restricted to the proven Zork I fixture", () => {
  for (const story of ["zork1", "zork2", "zork3"]) {
    const digest = crypto.createHash("sha256").update(fs.readFileSync(path.join(root, "games", story + ".z3"))).digest("hex")
    assert.equal(Automap.supportsCartridge("zmachine", digest), story === "zork1")
    assert.equal(Automap.supportsCartridge("scottfree", digest), false)
  }
  assert.equal(Automap.supportsCartridge("zmachine", "1".repeat(64)), false)
  assert.equal(Automap.supportsCartridge("zmachine", ""), false)
})

test("recorded Zork I death never creates a route to the resurrection room", () => {
  const fixture = path.join(root, "tests/fixtures/automap")
  const raw = fs.readFileSync(path.join(fixture, "zork1-death.raw"), "utf8")
  const commands = fs.readFileSync(path.join(fixture, "zork1-death.commands"), "utf8").trim().split("\n")
  const turns = raw.split(/(?=^> )/m)
  assert.equal(turns.length, commands.length + 1)
  let state = Automap.createEmptyState({ engine: "zmachine", sha256: "1".repeat(64) })
  let previous = null
  let deaths = 0
  for (let index = 0; index < turns.length; index++) {
    const framed = Automap.observeFrotzStatusFrame(turns[index], index === 0 ? "startup" : "prompt")
    assert.ok(framed, `missing status ${index}`)
    const before = state.edges.length
    const discontinuity = Automap.statusDiscontinuity(previous, framed.observation.status)
    if (discontinuity) state = Automap.resynchronizeState(state)
    state = Automap.reduceTurn(state, index === 0 ? "" : commands[index - 1], [framed.observation])
    if (turns[index].includes("You have died")) {
      deaths++
      assert.equal(discontinuity, true)
      assert.equal(state.edges.length, before, "no grue-to-resurrection compass route")
    }
    previous = framed.observation.status
  }
  assert.equal(deaths, 1)
})

test("original paper samples have bounded mono PCM duration and audio settings parse", () => {
  for (const [name, duration] of [["open", 0.420], ["close", 0.320]]) {
    const wav = fs.readFileSync(path.join(root, "assets", `paper-map-${name}.wav`))
    assert.equal(wav.toString("ascii", 0, 4), "RIFF")
    assert.equal(wav.toString("ascii", 8, 12), "WAVE")
    assert.equal(wav.readUInt16LE(20), 1)
    assert.equal(wav.readUInt16LE(22), 1)
    assert.equal(wav.readUInt32LE(24), 22050)
    assert.equal(wav.readUInt16LE(34), 16)
    assert.ok(Math.abs(wav.readUInt32LE(40) / 44100 - duration) < 0.001)
  }
  const config = Model.parseLanternConfig(fs.readFileSync(path.join(root, "lantern.toml"), "utf8"))
  assert.equal(config.audio.mute, false)
  assert.equal(config.audio.paper_volume, 0.18)
  assert.equal(config.accessibility.reduce_motion, false)
})
