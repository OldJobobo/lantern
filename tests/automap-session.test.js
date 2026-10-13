const test = require("node:test")
const assert = require("node:assert/strict")
const Session = require("../AutomapSession.js")
const Automap = require("../Automap.js")

function acceptedQueue(queue, operation, maximum) {
  const result = Session.enqueueOperation(queue, operation, maximum)
  assert.equal(result.accepted, true)
  return result.queue
}

test("bounded command queue is immutable, ordered, and fail-closed on overflow", () => {
  const empty = Session.createCommandQueue(2)
  const first = Session.enqueueCommand(empty, "north")
  const second = Session.enqueueCommand(first, "look")
  const overflow = Session.enqueueCommand(second, "south")

  assert.deepEqual(empty.items, [])
  assert.deepEqual(second.items, ["north", "look"])
  assert.deepEqual(overflow, { limit: 2, items: [], suppressed: true })
  assert.equal(Session.enqueueCommand(overflow, "west").suppressed, true)
})

test("command shifting pairs one logical command with each confirmed status", () => {
  let queue = Session.enqueueCommand(Session.createCommandQueue(), "north")
  queue = Session.enqueueCommand(queue, "save")
  const first = Session.shiftCommand(queue)
  const second = Session.shiftCommand(first.queue)
  const startup = Session.shiftCommand(second.queue)

  assert.equal(first.command, "north")
  assert.equal(second.command, "save")
  assert.equal(startup.command, "")
  assert.deepEqual(startup.queue.items, [])
})

test("startup status preserves a queued command and the next prompt status consumes it", () => {
  const queued = Session.enqueueCommand(Session.createCommandQueue(), "north")
  const startupFrame = Automap.observeFrotzStatusFrame(
    " West of House                 Score: 0        Moves: 0", "startup")
  const promptFrame = Automap.observeFrotzStatusFrame(
    "> North of House                Score: 0        Moves: 1", "startup")
  const startup = Session.consumeCommandForFrame(queued, startupFrame.frame)
  const prompt = Session.consumeCommandForFrame(startup.queue, promptFrame.frame)

  assert.equal(startupFrame.frame, "startup")
  assert.equal(promptFrame.frame, "prompt")
  assert.equal(startup.command, "")
  assert.deepEqual(startup.queue.items, ["north"])
  assert.equal(prompt.command, "north")
  assert.deepEqual(prompt.queue.items, [])
})

test("startup completion requires the same epoch and expected story path", () => {
  assert.equal(Session.startupResultMatches(4, "/story.z3", 4, "/story.z3"), true)
  assert.equal(Session.startupResultMatches(5, "/story.z3", 4, "/story.z3"), false)
  assert.equal(Session.startupResultMatches(4, "/other.z3", 4, "/story.z3"), false)
})

test("persistence read remains ordered behind a final queued write", () => {
  const sha = "c".repeat(64)
  let queue = acceptedQueue([], {
    op: "write", engine: "zmachine", sha256: sha, epoch: 1, payload: "final"
  })
  queue = acceptedQueue(queue, {
    op: "read", engine: "zmachine", sha256: sha, epoch: 2, requestPath: "/story.z3"
  })
  assert.deepEqual(queue.map(item => item.op), ["write", "read"])
  assert.equal(queue[1].requestPath, "/story.z3")
})

test("reset followed by read remains two ordered persistence barriers", () => {
  const sha = "d".repeat(64)
  let queue = acceptedQueue([], {
    op: "reset", engine: "zmachine", sha256: sha, epoch: 1
  })
  const result = Session.enqueueOperation(queue, {
    op: "read", engine: "zmachine", sha256: sha, epoch: 2, requestPath: "/story.z3"
  })

  assert.equal(result.accepted, true)
  assert.equal(result.coalesced, false)
  assert.deepEqual(result.queue.map(item => item.op), ["reset", "read"])
})

test("persistence coalesces only adjacent same-key writes or resets", () => {
  const sha = "a".repeat(64)
  const write = payload => ({ op: "write", engine: "zmachine", sha256: sha, epoch: 1, payload })
  const reset = epoch => ({ op: "reset", engine: "zmachine", sha256: sha, epoch })
  let result = Session.enqueueOperation([], write("one"))
  result = Session.enqueueOperation(result.queue, write("two"))
  assert.equal(result.coalesced, true)
  assert.deepEqual(result.queue.map(item => item.payload), ["two"])

  result = Session.enqueueOperation(result.queue, reset(1))
  result = Session.enqueueOperation(result.queue, reset(2))
  assert.equal(result.coalesced, true)
  assert.deepEqual(result.queue.map(item => [item.op, item.epoch]), [
    ["write", 1], ["reset", 2]
  ])
})

test("capacity rejects other-key reset without evicting final-write/read ordering", () => {
  const firstKey = "e".repeat(64)
  const otherKey = "f".repeat(64)
  let queue = acceptedQueue([], {
    op: "write", engine: "zmachine", sha256: firstKey, epoch: 1, payload: "final"
  }, 2)
  queue = acceptedQueue(queue, {
    op: "read", engine: "zmachine", sha256: firstKey, epoch: 2, requestPath: "/story.z3"
  }, 2)
  const before = JSON.parse(JSON.stringify(queue))
  const rejected = Session.enqueueOperation(queue, {
    op: "reset", engine: "zmachine", sha256: otherKey, epoch: 3
  }, 2)

  assert.equal(rejected.accepted, false)
  assert.equal(rejected.coalesced, false)
  assert.deepEqual(rejected.queue, before)
  assert.deepEqual(queue, before)
})

test("invalid persistence operations report rejection without queue mutation", () => {
  const queue = [{ op: "reset", engine: "zmachine", sha256: "a".repeat(64), epoch: 1 }]
  const result = Session.enqueueOperation(queue, { op: "write" })
  assert.deepEqual(result, { queue, accepted: false, coalesced: false })
})
