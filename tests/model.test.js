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

test("safeStoryPath accepts only absolute Z-machine story files", () => {
  assert.equal(Model.safeStoryPath("/home/me/.local/share/lantern/games/zork1.z3"), "/home/me/.local/share/lantern/games/zork1.z3")
  assert.equal(Model.safeStoryPath("relative/zork1.z3"), "")
  assert.equal(Model.safeStoryPath("/tmp/not-a-story.txt"), "")
  assert.equal(Model.safeStoryPath("/tmp/story.z3\n--evil"), "")
})
