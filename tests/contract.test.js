const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const crypto = require("node:crypto")

const root = path.resolve(__dirname, "..")

test("manifest declares a summonable third-party panel", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "jobo.lantern")
  assert.deepEqual(manifest.kinds, ["panel"])
  assert.equal(manifest.entryPoints.panel, "Panel.qml")
  assert.equal(manifest.keepLoaded, true)
  assert.equal(manifest.license, "MIT AND GPL-2.0-or-later")
})

test("panel follows the Quattro lifecycle and keeps Frotz file access restricted", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  for (const required of [
    "property var shell: null",
    "property var manifest: null",
    "function open(payloadJson)",
    "function close()",
    "FloatingWindow",
    "stdinEnabled: true",
    "runtime/x86_64-linux/dfrotz",
    '"-R"',
    "textFormat: Text.PlainText"
  ]) assert.match(source, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
})

test("release contains a self-contained x86-64 runtime and default story", () => {
  const runtime = path.join(root, "runtime/x86_64-linux/dfrotz")
  const story = path.join(root, "games/zork1.z3")

  for (const required of [
    runtime,
    story,
    path.join(root, "THIRD_PARTY_NOTICES.md"),
    path.join(root, "third_party/frotz/COPYING"),
    path.join(root, "third_party/frotz/BUILD.md"),
    path.join(root, "third_party/frotz/source/frotz-2.55.tar.gz"),
    path.join(root, "third_party/zork1/LICENSE"),
    path.join(root, "third_party/SHA256SUMS")
  ]) assert.equal(fs.existsSync(required), true, `missing ${path.relative(root, required)}`)

  assert.equal(fs.statSync(runtime).mode & 0o111, 0o111, "bundled dfrotz must be executable")
  assert.deepEqual([...fs.readFileSync(runtime).subarray(0, 5)], [0x7f, 0x45, 0x4c, 0x46, 0x02])
  assert.equal(fs.readFileSync(story)[0], 3, "bundled Zork I must be a V3 story")
})

test("third-party checksum inventory covers every distributed upstream artifact", () => {
  const inventory = fs.readFileSync(path.join(root, "third_party/SHA256SUMS"), "utf8")
    .trim().split("\n").map(line => line.match(/^([0-9a-f]{64})  (.+)$/))
  assert.equal(inventory.every(Boolean), true, "checksum inventory has malformed lines")

  const covered = new Set()
  for (const [, expected, relative] of inventory) {
    const file = path.join(root, relative)
    assert.equal(fs.existsSync(file), true, `missing checksummed file ${relative}`)
    const actual = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")
    assert.equal(actual, expected, `checksum mismatch for ${relative}`)
    covered.add(relative)
  }

  for (const relative of [
    "runtime/x86_64-linux/dfrotz",
    "games/zork1.z3",
    "third_party/frotz/source/frotz-2.55.tar.gz"
  ]) assert.equal(covered.has(relative), true, `checksum inventory omits ${relative}`)
})

test("panel launches only bundled defaults without PATH or external game setup", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  assert.match(source, /Qt\.resolvedUrl\("\."\)/)
  assert.match(source, /runtime\/x86_64-linux\/dfrotz/)
  assert.match(source, /games\/zork1\.z3/)
  assert.doesNotMatch(source, /\["dfrotz"/)
  assert.doesNotMatch(source, /\.local\/share\/lantern\/games/)
  assert.doesNotMatch(source, /Install the Arch package/)
})

test("panel serializes startup around one immutable checked story path", () => {
  const source = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  for (const required of [
    "property bool startPending: false",
    "property string pendingStoryPath: \"\"",
    "if (!frotzProc.running && !startPending)",
    "storyCheck.command = [\"test\", \"-r\", root.pendingStoryPath]",
    "root.pendingStoryPath"
  ]) assert.match(source, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.doesNotMatch(source, /storyPath\s*=\s*requested/)
})
