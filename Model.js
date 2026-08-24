function normalizeCommand(raw) {
  return String(raw || "").replace(/[\r\n]+/g, " ").trim()
}

function cleanOutput(raw) {
  var text = String(raw || "")
    .replace(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "")
    .replace(/\r\n?/g, "\n")
    .replace(/\u0000/g, "")
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("> ") === 0 && lines[i].indexOf("Score:") !== -1 && lines[i].indexOf("Moves:") !== -1)
      lines[i] = lines[i].slice(2)
  }
  text = lines.join("\n")
  text = text.replace(/(?:^|\n)>\s*$/g, "")
  return text.replace(/[ \t]+$/gm, "").trim()
}

function appendTranscript(current, addition, maxLines) {
  var existing = String(current || "")
  var incoming = String(addition || "")
  var joined = existing && incoming ? existing + "\n" + incoming : existing + incoming
  var lines = joined.split("\n")
  var limit = Math.max(1, Number(maxLines) || 1)
  if (lines.length > limit) lines = lines.slice(lines.length - limit)
  return lines.join("\n")
}

function historyStep(history, index, direction) {
  var items = Array.isArray(history) ? history : []
  var next = Math.max(0, Math.min(items.length, Number(index) + Number(direction)))
  return { index: next, value: next < items.length ? String(items[next]) : "" }
}

function safeStoryPath(raw) {
  var value = String(raw || "")
  if (!value.startsWith("/") || /[\r\n\u0000]/.test(value)) return ""
  if (!/\.(?:z[1-8]|zblorb|blorb)$/i.test(value)) return ""
  return value
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeCommand: normalizeCommand,
    cleanOutput: cleanOutput,
    appendTranscript: appendTranscript,
    historyStep: historyStep,
    safeStoryPath: safeStoryPath
  }
}
