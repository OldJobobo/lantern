function normalizeCommand(raw) {
  return String(raw || "").replace(/[\r\n]+/g, " ").trim()
}

function cleanOutput(raw) {
  var text = String(raw || "")
    .replace(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "")
    .replace(/\r\n?/g, "\n")
    .replace(/\u0000/g, "")
    .replace(/>?Please enter a filename \[[^\]\n]*\]:[ \t]*/g, "")
    .replace(/Overwrite existing file\?[ \t]*/g, "")
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("> ") === 0 && lines[i].indexOf("Score:") !== -1 && lines[i].indexOf("Moves:") !== -1)
      lines[i] = lines[i].slice(2)
  }
  text = lines.join("\n")
  text = text.replace(/(?:^|\n)>\s*$/g, "")
  return text.replace(/[ \t]+$/gm, "").trim()
}

function normalizeSaveName(raw) {
  return String(raw || "")
    .replace(/[\r\n\u0000]/g, " ")
    .replace(/\.qzl\s*$/i, "")
    .replace(/[^A-Za-z0-9 _-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 20)
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

function menuStep(index, count, direction) {
  var size = Math.max(0, Math.floor(Number(count) || 0))
  if (size === 0) return 0
  var current = Math.max(0, Math.min(size - 1, Math.floor(Number(index) || 0)))
  var delta = Number(direction) < 0 ? -1 : 1
  return (current + delta + size) % size
}

function bundledStoryPath(raw, allowedPaths) {
  var value = String(raw || "")
  var allowed = Array.isArray(allowedPaths) ? allowedPaths : []
  if (value === "" || /[\r\n\u0000]/.test(value)) return ""
  return allowed.indexOf(value) === -1 ? "" : value
}

function boundedFileText(raw, maxBytes) {
  var value = String(raw || "")
  var limit = Math.max(0, Number(maxBytes) || 0)
  return value.length <= limit ? value : ""
}

function tomlValue(raw) {
  var value = String(raw || "").trim()
  if (/^"(?:[^"\\]|\\.)*"$/.test(value)) {
    try { return JSON.parse(value) } catch (error) { return undefined }
  }
  if (value === "true") return true
  if (value === "false") return false
  if (/^[+-]?(?:\d+\.?\d*|\.\d+)$/.test(value)) return Number(value)
  return undefined
}

function parseLanternConfig(raw) {
  var result = {}
  var section = ""
  var lines = String(raw || "").replace(/\r\n?/g, "\n").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || line.indexOf("#") === 0) continue

    var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(?:#.*)?$/)
    if (sectionMatch) {
      section = sectionMatch[1]
      if (!result[section]) result[section] = {}
      continue
    }

    var assignment = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*(?:#.*)?$/)
    if (!assignment || section === "") continue
    var parsed = tomlValue(assignment[2])
    if (parsed !== undefined) result[section][assignment[1]] = parsed
  }

  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeCommand: normalizeCommand,
    normalizeSaveName: normalizeSaveName,
    cleanOutput: cleanOutput,
    appendTranscript: appendTranscript,
    historyStep: historyStep,
    menuStep: menuStep,
    bundledStoryPath: bundledStoryPath,
    boundedFileText: boundedFileText,
    parseLanternConfig: parseLanternConfig
  }
}
