const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const root = path.resolve(__dirname, "..")
const helper = path.join(root, "bin/window-state")

test("window state helper saves geometry and prepares an initial-placement rule", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "lantern-window-state-"))
  const fakeHyprctl = path.join(temp, "hyprctl")
  const statePath = path.join(temp, "window.json")
  const evalLog = path.join(temp, "eval.log")

  fs.writeFileSync(fakeHyprctl, `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "-j clients" ]]; then
  printf '%s\n' '[{"address":"0xabc","at":[2700,-600],"size":[1020,765],"monitor":2,"title":"Lantern — Interactive Fiction Terminal"}]'
elif [[ "$1 $2" == "-j monitors" ]]; then
  printf '%s\n' '[{"id":2,"name":"DP-3","x":2560,"y":-798,"width":2560,"height":1440,"scale":1,"transform":1,"reserved":[0,26,0,0],"activeWorkspace":{"id":6,"name":"6"}}]'
elif [[ "$1" == "eval" ]]; then
  printf '%s\n---\n' "$2" >>"${evalLog}"
else
  exit 64
fi
`)
  fs.chmodSync(fakeHyprctl, 0o755)

  const env = {
    ...process.env,
    HYPRCTL_BIN: fakeHyprctl,
    LANTERN_STATE_PATH: statePath
  }
  execFileSync(helper, ["save"], { env })
  assert.deepEqual(JSON.parse(fs.readFileSync(statePath, "utf8")), {
    version: 1,
    screen: "DP-3",
    x: 140,
    y: 198
  })
  assert.equal(fs.statSync(statePath).mode & 0o777, 0o600)

  execFileSync(helper, ["prepare"], { env })
  const prepared = fs.readFileSync(evalLog, "utf8")
  assert.match(prepared, /hl\.window_rule/)
  assert.match(prepared, /workspace = "6 silent"/)
  assert.match(prepared, /move = "140 198"/)
  assert.doesNotMatch(prepared, /hl\.dsp\.window\.move/)

  execFileSync(helper, ["clear"], { env })
  assert.match(fs.readFileSync(evalLog, "utf8"), /set_enabled\(false\)/)
})
