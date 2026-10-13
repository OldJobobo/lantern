var DEFAULT_COMMAND_LIMIT = 64

function createCommandQueue(limit) {
  var maximum = Math.max(1, Math.min(128, Math.floor(Number(limit) || DEFAULT_COMMAND_LIMIT)))
  return { limit: maximum, items: [], suppressed: false }
}

function enqueueCommand(queue, command) {
  var source = queue && typeof queue === "object" ? queue : createCommandQueue()
  if (source.suppressed === true)
    return { limit: source.limit, items: [], suppressed: true }
  var items = Array.isArray(source.items) ? source.items.slice(0) : []
  if (items.length >= source.limit)
    return { limit: source.limit, items: [], suppressed: true }
  items.push(String(command === undefined || command === null ? "" : command))
  return { limit: source.limit, items: items, suppressed: false }
}

function shiftCommand(queue) {
  var source = queue && typeof queue === "object" ? queue : createCommandQueue()
  if (source.suppressed === true)
    return { command: "", queue: { limit: source.limit, items: [], suppressed: true } }
  var items = Array.isArray(source.items) ? source.items.slice(0) : []
  var command = items.length > 0 ? String(items.shift()) : ""
  return { command: command, queue: { limit: source.limit, items: items, suppressed: false } }
}

function consumeCommandForFrame(queue, frame) {
  if (frame === "prompt") return shiftCommand(queue)
  var source = queue && typeof queue === "object" ? queue : createCommandQueue()
  return {
    command: "",
    queue: {
      limit: source.limit,
      items: Array.isArray(source.items) ? source.items.slice(0) : [],
      suppressed: source.suppressed === true
    }
  }
}

function startupResultMatches(activeEpoch, activePath, requestEpoch, requestPath) {
  return Number(activeEpoch) === Number(requestEpoch) && String(activePath || "") === String(requestPath || "")
}

function validOperation(operation) {
  return operation && (operation.op === "read" || operation.op === "write" || operation.op === "reset") &&
    typeof operation.engine === "string" && typeof operation.sha256 === "string" &&
    typeof operation.epoch === "number" &&
    (operation.op !== "write" || typeof operation.payload === "string") &&
    (operation.op !== "read" || typeof operation.requestPath === "string")
}

// Coalescing is deliberately adjacent: writes never cross an operation
// barrier, and only reset -> reset for the same key can collapse. Capacity
// rejects the incoming operation without evicting already ordered work.
function enqueueOperation(queue, operation, maximum) {
  var source = Array.isArray(queue) ? queue.slice(0) : []
  var limit = Math.max(1, Math.min(32, Math.floor(Number(maximum) || 8)))
  if (!validOperation(operation)) return { queue: source, accepted: false, coalesced: false }
  var next = {
    op: operation.op,
    engine: operation.engine,
    sha256: operation.sha256,
    epoch: operation.epoch,
    payload: operation.op === "write" ? operation.payload : "",
    requestPath: operation.op === "read" ? operation.requestPath : ""
  }
  if (source.length > 0) {
    var last = source[source.length - 1]
    var sameKey = last.engine === next.engine && last.sha256 === next.sha256
    if (sameKey && last.op === "write" && next.op === "write") {
      source[source.length - 1] = next
      return { queue: source, accepted: true, coalesced: true }
    }
    if (sameKey && last.op === "reset" && next.op === "reset") {
      source[source.length - 1] = next
      return { queue: source, accepted: true, coalesced: true }
    }
  }
  if (source.length >= limit)
    return { queue: source, accepted: false, coalesced: false }
  source.push(next)
  return { queue: source, accepted: true, coalesced: false }
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_COMMAND_LIMIT: DEFAULT_COMMAND_LIMIT,
    createCommandQueue: createCommandQueue,
    enqueueCommand: enqueueCommand,
    shiftCommand: shiftCommand,
    consumeCommandForFrame: consumeCommandForFrame,
    startupResultMatches: startupResultMatches,
    enqueueOperation: enqueueOperation
  }
}
