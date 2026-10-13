const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const root = path.resolve(__dirname, "..")
const helper = path.join(root, "bin/lantern-cartridge")

test("imports reject nonprivate libraries and overflowing Scott header tokens", () => {
  const directory = fs.mkdtempSync(path.join(root, ".test-import-safety-"))
  const library = path.join(directory, "library")
  const run = (format, source) => spawnSync(helper, [format, source, library], { encoding: "utf8", timeout: 5000 })
  try {
    fs.mkdirSync(library, { mode: 0o755 })
    assert.notEqual(run("import-zmachine", path.join(root, "games/zork1.z3")).status, 0)
    assert.deepEqual(fs.readdirSync(library), [])
    fs.chmodSync(library, 0o700)
    const fixture = fs.readFileSync(path.join(root, "tests/fixtures/minimal-scott.dat"), "utf8")
    for (const token of ["9".repeat(100), "0".repeat(100), "4294967305", "9x"]) {
      const source = path.join(directory, "bad.dat")
      fs.writeFileSync(source, fixture.replace(/^\S+/, token))
      const result = run("import-scott", source)
      assert.notEqual(result.status, 0, token)
      assert.equal(result.signal, null)
      assert.deepEqual(fs.readdirSync(library), [])
    }
    for (let i = 0; i < 2; i++) {
      const result = run("import-zmachine", path.join(root, "games/zork1.z3"))
      assert.equal(result.status, 0, result.stderr)
      const imported = path.join(library, result.stdout.trim())
      assert.deepEqual(fs.readFileSync(imported), fs.readFileSync(path.join(root, "games/zork1.z3")))
      assert.equal(fs.statSync(imported).mode & 0o777, 0o600)
    }
    assert.deepEqual(fs.readdirSync(library).sort(), ["zork1-2.z3", "zork1.z3"])
  } finally { fs.rmSync(directory, { recursive: true, force: true }) }
})
