const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("normalizeCommand trims line breaks and rejects empty input", () => {
  assert.equal(Model.normalizeCommand("  open mailbox\r\n"), "open mailbox")
  assert.equal(Model.normalizeCommand("   "), "")
})

test("cleanOutput removes control sequences and Frotz prompts without rewriting prose", () => {
  const raw = "\u001b[32mWest of House\u001b[0m\r\nYou are standing outside.\r\n>"
  assert.equal(Model.cleanOutput(raw), "West of House\nYou are standing outside.")
})

test("cleanOutput removes a prompt fused to a dumb-Frotz status line", () => {
  assert.equal(
    Model.cleanOutput("> West of House                 Score: 0      Moves: 1"),
    "West of House                 Score: 0      Moves: 1"
  )
})

test("cleanOutput hides interpreter filename prompts without losing game output", () => {
  assert.equal(
    Model.cleanOutput(">Please enter a filename [zork1.qzl]:  West of House  Score: 0  Moves: 0\n\nOk."),
    "West of House  Score: 0  Moves: 0\n\nOk."
  )
  assert.equal(
    Model.cleanOutput("Please enter a filename [slot.qzl]: Overwrite existing file?  Forest\n\nOk."),
    "Forest\n\nOk."
  )
})

test("normalizeSaveName creates a bounded save-root filename stem", () => {
  assert.equal(Model.normalizeSaveName("  Zork I / west.qzl\n"), "Zork I west")
  assert.equal(Model.normalizeSaveName("../escape"), "escape")
  assert.equal(Model.normalizeSaveName("x".repeat(80)).length, 20)
})

test("appendTranscript bounds retained lines and preserves newest prose", () => {
  const result = Model.appendTranscript("one\ntwo", "three\nfour", 3)
  assert.equal(result, "two\nthree\nfour")
})

test("history navigation moves backward and forward with a blank draft sentinel", () => {
  const history = ["look", "open mailbox"]
  assert.deepEqual(Model.historyStep(history, 2, -1), { index: 1, value: "open mailbox" })
  assert.deepEqual(Model.historyStep(history, 1, -1), { index: 0, value: "look" })
  assert.deepEqual(Model.historyStep(history, 0, 1), { index: 1, value: "open mailbox" })
  assert.deepEqual(Model.historyStep(history, 1, 1), { index: 2, value: "" })
})

test("menuStep wraps launcher selection in either direction", () => {
  assert.equal(Model.menuStep(0, 3, 1), 1)
  assert.equal(Model.menuStep(2, 3, 1), 0)
  assert.equal(Model.menuStep(0, 3, -1), 2)
  assert.equal(Model.menuStep(7, 0, 1), 0)
})

test("parseLanternConfig reads supported TOML scalar sections", () => {
  const config = Model.parseLanternConfig(`
    # user choices
    [display]
    phosphor = "green"
    effects = false
    raster_opacity = 0.65 # restrained

    [terminal]
    history_limit = 48
  `)

  assert.deepEqual(config, {
    display: { phosphor: "green", effects: false, raster_opacity: 0.65 },
    terminal: { history_limit: 48 }
  })
})

test("bundledStoryPath accepts only an exact bundled cartridge path", () => {
  const bundled = [
    "/home/me/.config/omarchy/plugins/jobo.lantern/games/zork1.z3",
    "/home/me/.config/omarchy/plugins/jobo.lantern/games/zork2.z3"
  ]

  assert.equal(Model.bundledStoryPath(bundled[0], bundled), bundled[0])
  assert.equal(Model.bundledStoryPath("/tmp/attacker.z3", bundled), "")
  assert.equal(Model.bundledStoryPath(`${bundled[0]}/../zork2.z3`, bundled), "")
  assert.equal(Model.bundledStoryPath(`${bundled[0]}\n--evil`, bundled), "")
  assert.equal(Model.bundledStoryPath(bundled[0], []), "")
})

test("boundedFileText rejects reader output above the byte cap", () => {
  assert.equal(Model.boundedFileText("phosphor = \"green\"", 64), "phosphor = \"green\"")
  assert.equal(Model.boundedFileText("x".repeat(65), 64), "")
  assert.equal(Model.boundedFileText("anything", 0), "")
})
