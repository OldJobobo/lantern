const test = require("node:test")
const assert = require("node:assert/strict")
const crypto = require("node:crypto")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const root = path.resolve(__dirname, "..")
const helper = path.join(root, "bin/lantern-cartridge")

function fingerprint(story, options = {}) {
  return spawnSync(helper, ["fingerprint-zmachine", story], {
    encoding: "utf8",
    timeout: 5000,
    ...options
  })
}

test("cartridge helper fingerprints bundled Zork stories with exact SHA-256 output", () => {
  const expected = new Map([
    ["zork1.z3", "37084966477dff679282de42974b2077156b1bd68fad92a65d4ea94d8eb64d79"],
    ["zork2.z3", "3ae7d5558943e9721f3e4b273c8a7faec1a03a604e1ae4ee1cde472c21cb24ac"],
    ["zork3.z3", "b637a242865d059890184164ce8dec28554cc80901dcbf26c740b2d1ed0d4eb8"]
  ])

  for (const [fileName, digest] of expected) {
    const result = fingerprint(path.join(root, "games", fileName))
    assert.equal(result.error, undefined)
    assert.equal(result.status, 0)
    assert.equal(result.stderr, "")
    assert.equal(result.stdout, `${digest}\n`)
    assert.match(result.stdout, /^[0-9a-f]{64}\n$/)
  }
})

test("cartridge helper matches Node SHA-256 at padding and read-buffer boundaries", () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "lantern-fingerprint-"))
  const fixtures = [
    { remainder: 55, length: 119, version: 3 },
    { remainder: 56, length: 120, version: 4 },
    { remainder: 63, length: 65599, version: 5 },
    { remainder: 0, length: 65600, version: 8 }
  ]

  try {
    for (const fixture of fixtures) {
      assert.equal(fixture.length % 64, fixture.remainder)
      const story = path.join(fixtureRoot, `padding-${fixture.remainder}.z${fixture.version}`)
      const bytes = Buffer.alloc(fixture.length)
      bytes[0] = fixture.version
      for (let index = 1; index < bytes.length; index++)
        bytes[index] = (index * 37 + fixture.remainder * 11) & 0xff
      fs.writeFileSync(story, bytes)

      const expected = crypto.createHash("sha256").update(bytes).digest("hex")
      const result = fingerprint(story)
      assert.equal(result.status, 0, `remainder ${fixture.remainder}`)
      assert.equal(result.stdout, `${expected}\n`, `remainder ${fixture.remainder}`)
      assert.equal(result.stderr, "", `remainder ${fixture.remainder}`)
    }
    assert.ok(fixtures.some(fixture => fixture.length > 65536),
      "at least one fixture must cross the helper read-buffer boundary")
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true })
  }
})

test("cartridge fingerprint rejects symlinks, nonregular files, oversized stories, and bad headers", () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "lantern-fingerprint-reject-"))
  try {
    const valid = path.join(fixtureRoot, "valid.z3")
    const linked = path.join(fixtureRoot, "linked.z3")
    const fifo = path.join(fixtureRoot, "story.fifo")
    const oversized = path.join(fixtureRoot, "oversized.z3")
    const badHeader = path.join(fixtureRoot, "bad-header.z3")
    const short = path.join(fixtureRoot, "short.z3")

    const validBytes = Buffer.alloc(64, 0x41)
    validBytes[0] = 3
    fs.writeFileSync(valid, validBytes)
    fs.symlinkSync(valid, linked)
    assert.equal(spawnSync("mkfifo", [fifo]).status, 0)
    fs.writeFileSync(oversized, validBytes)
    fs.truncateSync(oversized, 128 * 1024 * 1024 + 1)
    fs.writeFileSync(badHeader, Buffer.alloc(64))
    fs.writeFileSync(short, Buffer.alloc(31, 3))

    for (const rejected of [linked, fixtureRoot, fifo, oversized, badHeader, short]) {
      const result = fingerprint(rejected)
      assert.equal(result.error, undefined, rejected)
      assert.notEqual(result.status, 0, rejected)
      assert.equal(result.stdout, "", rejected)
      assert.match(result.stderr, /^lantern-cartridge: /, rejected)
    }
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true })
  }
})

test("cartridge fingerprint treats digest output failure as fatal", () => {
  const sink = fs.openSync("/dev/full", "w")
  try {
    const result = fingerprint(path.join(root, "games/zork1.z3"), {
      stdio: ["ignore", sink, "pipe"]
    })
    assert.equal(result.error, undefined)
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /lantern-cartridge: could not write cartridge fingerprint/)
  } finally {
    fs.closeSync(sink)
  }
})

test("fingerprint command is documented and rebuilt without a crypto dependency", () => {
  const source = fs.readFileSync(path.join(root, "bin/lantern-cartridge.c"), "utf8")
  const build = fs.readFileSync(path.join(root, "scripts/build-cartridge-helper"), "utf8")
  const documentation = fs.readFileSync(path.join(root, "docs/cartridge-helper.md"), "utf8")
  const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8")
  const usage = spawnSync(helper, [], { encoding: "utf8" })

  assert.notEqual(usage.status, 0)
  assert.match(usage.stderr, /lantern-cartridge fingerprint-zmachine STORY/)
  assert.match(source, /fingerprint_zmachine\(argv\[2\]\)/)
  assert.match(source, /int fd = open_story\(path, FORMAT_ZMACHINE, &version, &size\)/)
  assert.match(source, /struct sha256_context/)
  assert.match(source, /printf\("%02x", digest\[i\]\) < 0/)
  assert.match(source, /putchar\('\\n'\) == EOF \|\| fflush\(stdout\) == EOF \|\| ferror\(stdout\)/)
  assert.doesNotMatch(source, /#include\s*[<"]openssl|EVP_|SHA256_/)
  assert.match(build, /gcc -std=c11/)
  assert.match(documentation, /fingerprint-zmachine STORY/)
  assert.match(documentation, /exactly one lowercase 64-character SHA-256 digest followed by a newline/)
  assert.match(workflow, /\.\/scripts\/build-cartridge-helper "\$RUNNER_TEMP\/lantern-cartridge"/)
  assert.match(workflow, /cmp --silent bin\/lantern-cartridge "\$RUNNER_TEMP\/lantern-cartridge"/)
})
