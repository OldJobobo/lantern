# Explorer Automap Plan

## Status

Implemented in the unpublished 0.2.0 candidate, with conservative scope: only the exact bundled Zork I content fingerprint (including byte-identical imports) enables mapping. Engine-neutral inference, bounded persistence, the Ctrl+P paper overlay, accessible summary, reduced motion, and original travel sounds are present. Other-engine observers and manual editing remain deferred. See `release-0.2.0-plan.md` for executed validation and release blockers.

The sections below retain the original design rationale and delivery phases; they are not a claim that every proposed future capability ships in 0.2.0. The live overlay uses a 914×682 logical surface at x=46, y=29, and closes at x=-854; these supersede the earlier recommended dimensions below.

Design references:

- `assets/map-concept-closed.png`
- `assets/map-concept-open.png`
- `assets/old-graph-paper.png`
- `assets/zork-rough-map.png`

The concept images are visual references, not production UI assets. The live map must be generated dynamically from observed play.

## Product direction

The map should feel like a physical worksheet stored beside the CRT rather than another terminal screen. It slides in from the left above the glass and hardware controls, retains a neutral paper palette in every phosphor mode, and is never processed by the CRT shader.

Recommended MVP decisions:

- Toggle the map with `Ctrl+P` and a clickable `MAP / CTRL+P` paper tab.
- Keep one cumulative explorer map per cartridge, independent of save slots.
- Reveal only confirmed rooms and traversed connections.
- Begin with bundled Z-machine games, using Zork I as the proof case.
- Use separate quiet opening and closing paper sounds.
- Support independent mute and reduced-motion settings.
- Initially provide only a map reset control; manual graph editing can follow later.

## Architecture

### Engine observers and shared reducer

Lantern cannot reliably map every engine with one prose parser:

- Frotz exposes room names through its status line.
- ScottFree emits a room heading structurally associated with `Obvious exits`.
- Open Adventure often emits prose descriptions without stable room headings.

Use engine-specific observers feeding one engine-neutral graph reducer:

```text
command submitted
    ↓
engine observer buffers raw output
    ↓
high-confidence location observation
    ↓
shared graph reducer
    ↓
persistent explorer map
```

Suggested files:

```text
Automap.js
MapOverlay.qml
MapCanvas.qml
```

`Automap.js` should expose testable pure functions for:

- movement normalization;
- engine observer selection;
- raw turn observation;
- room identity resolution;
- directed edge creation;
- restore, restart, undo, and death handling;
- deterministic graph layout; and
- state validation and serialization.

Feed observers bounded raw output before `Model.cleanOutput()` changes prompts and whitespace. Do not derive map events from the presentation transcript.

### Conservative movement inference

Recognize only exact movement commands:

```text
n, north, go north
ne, northeast
s, south
e, east
w, west
u, up
d, down
in, out
```

Reject ambiguous commands such as:

```text
look north
ask troll about north
north then east
```

Rules:

- A confirmed different destination after an exact movement command creates a directed traversed edge.
- Observing the same location creates no edge.
- `restore`, `load`, `undo`, restart, and death clear pending movement and reacquire the current location without drawing an edge.
- A nonmovement location change may create an unplaced transition, never a fabricated compass route.
- Never issue a hidden `LOOK`; it may consume turns or change game behavior.
- Never assume a route is reversible.
- Never merge rooms solely because their labels match.
- A timeout may close an output buffer but must not establish a room by itself.
- Ambiguous output leaves the confirmed graph unchanged.

Engine-agnostic behavior means a shared reducer with replaceable observers, not a universal prose regex.

### State model

Persist cumulative graph truth, not pending turn buffers or the presentation transcript.

```json
{
  "schemaVersion": 1,
  "cartridge": {
    "engine": "zmachine",
    "sha256": "..."
  },
  "nodes": [
    {
      "id": "room-17",
      "label": "Forest",
      "confidence": "confirmed",
      "firstSeen": 12,
      "lastSeen": 41
    }
  ],
  "edges": [
    {
      "from": "room-12",
      "to": "room-17",
      "direction": "north",
      "command": "n",
      "confirmed": true,
      "traversals": 2
    }
  ],
  "layout": {
    "seed": 18273,
    "positions": {}
  }
}
```

Node IDs are generated identities, not room labels. Resolve repeated labels through known source, direction, description evidence, and existing adjacent nodes. Preserve ambiguity rather than merging uncertain rooms.

Keep the active `currentNode` session-local. A persisted last location is only a startup hint until the engine emits fresh evidence.

### Cartridge identity and persistence

Current imported cartridge IDs are filename-derived and can collide or change after a rename. Persistent maps must use engine plus content fingerprint.

Store maps under:

```text
${XDG_STATE_HOME:-~/.local/state}/lantern/maps/<engine>-<sha256>.json
```

Use a small audited native helper instead of shell-built writes or direct unbounded QML file access. The helper should:

- accept only fixed read/write operations and a validated fingerprint key;
- accept JSON through stdin rather than argv;
- reject symlinks, non-regular files, wrong ownership, unsupported schemas, and oversized state;
- bound node count, edge count, and all strings;
- create the directory as `0700` and state files as `0600`;
- write to a temporary file and atomically rename it; and
- treat corrupt or future-version state as recoverable and never block game launch.

Suggested limits:

- 2 MiB state file;
- 4,096 nodes;
- 16,384 edges; and
- 128 characters per room label.

Debounce writes instead of saving after every output line.

## Presentation

### Runtime rendering

Use `assets/old-graph-paper.png` as the blank live surface. `assets/zork-rough-map.png` demonstrates the desired style but must not supply runtime room content.

Render the live graph using QML Canvas or equivalent native QML primitives. Use deterministic seeded variations for box corners, route strokes, label rotation, and graphite wear. The map must look hand drawn without visibly changing every time it opens.

Do not generate executable QML or SVG from story output. Render only bounded plain text with `Text.PlainText` semantics.

### Visual grammar

- **Visited room:** solid irregular graphite enclosure with uppercase label.
- **Current room:** visited treatment plus inner outline, pencil notch, and literal `HERE` annotation.
- **Confirmed traversal:** solid graphite route.
- **One-way traversal:** destination arrowhead.
- **Vertical traversal:** `U` or `D` beside the line.
- **Confirmed but unexplored exit:** dashed stub ending in `?`, only when an observer can prove the exit exists.
- **Uncertain inference:** hidden in the MVP.
- **Automatic notes:** factual observations only. Do not invent hints such as “bring sword” or “open grating.”

Use a fixed physical palette independent of phosphor selection:

- Paper: `#D8D1BE`
- Primary graphite: `#423E38`
- Secondary graphite: `#5B5349`
- Grid blue: `#7898A8` at roughly 20–24% opacity
- Shadow: black at roughly 38%

### Map viewport

Large maps need an internal viewport rather than perpetual auto-shrinking:

- Arrow keys pan by 32 logical pixels.
- Shift+Arrow pans by 96 logical pixels.
- `+` and `-` zoom from approximately 0.8× to 1.4×.
- `0` recenters the current room at 1×.
- Pointer drag pans.
- Ctrl+wheel zooms around the pointer.
- Preserve pan and zoom for the current cartridge session.
- If the full graph fits, center it and clamp panning.

Graph truth must remain stable even when automatic geometry is imperfect. One-way routes, loops, vertical movement, teleports, and maze-like areas are normal.

## Overlay interaction

### Layering

Place `MapOverlay.qml` above the CRT shader and hardware shelf, as a sibling overlay in the physical terminal surface. Do not place it inside `crtContent` or `ShaderEffectSource`.

Recommended stack:

1. existing CRT content and shader;
2. CRT-only modal scrim;
3. full-window pointer blocker;
4. paper shadow;
5. paper and map content; and
6. exposed top window-drag strip.

The transcript may continue rendering behind the map, but the paper must not receive scanlines, curvature, bloom, channel glitches, phosphor color, or brightness changes.

### Geometry

Logical geometry on the existing 1020×765 base surface:

- paper size: approximately 854×640;
- open position: `x: 76`, `y: 50`;
- closed position: `x: -824`;
- visible closed tab: 30 px;
- minimum invisible tab hit target: 44×44 logical px; and
- open rotation: approximately 1.4° clockwise.

The complete logical surface scales uniformly with the existing 1×, 1.25×, and 1.5× window modes. Animation duration remains constant across scales.

### Controls and focus

Add `MAP / CTRL+P` as the first game action button. Do not reuse `Ctrl+M`, which already returns to the cartridge menu.

The map is available only when:

- `viewMode === "game"`;
- the engine process is running;
- no save/load overlay is open; and
- the cartridge has a supported map observer.

Unsupported cartridges show `MAP --` with an explanatory tooltip.

When opening:

1. preserve the command draft and prior focus;
2. immediately disable game input and hardware controls below the paper;
3. move focus into a modal map `FocusScope`; and
4. retain transcript output received while the map is open.

While open:

- Ctrl+P and Escape close the map;
- pointer interaction does not pass through to CRT or hardware controls;
- room marks remain informational rather than pretending to be buttons; and
- only real actions such as `CENTER`, `RESET VIEW`, and `CLOSE` participate in keyboard focus.

When closing:

- preserve map pan and zoom;
- restore the command draft and command focus; and
- do not discard transcript output received while open.

Returning to the launcher, ejecting a cartridge, ending the process, hiding Lantern, or closing the native window forces the map closed silently.

Escape closes the map before retaining its existing behavior of closing Lantern.

Rapid Ctrl+P presses should reverse the active transition from its current position rather than restart or snap. Ignore key auto-repeat.

## Motion

Use a four-state controller: `closed`, `opening`, `open`, and `closing`.

Opening choreography:

1. At 0–90 ms, capture input, raise a CRT-only scrim to 18%, and build the paper shadow.
2. From 0–340 ms, move the paper to `x: 84` with `OutCubic` while rotating from roughly 0.3° to 1.65°.
3. From 340–420 ms, settle 8 px to `x: 76` and 1.4° with `OutQuad`.

Closing choreography:

- Run approximately 340 ms with `InOutCubic`.
- Fade scrim and shadow during the final 140 ms.
- Return rotation toward 0.3° before only the aligned tab remains visible.

Interrupted transitions use distance-proportional timing between approximately 120 and 420 ms and omit the opening recoil.

Reduced-motion mode applies immediate property changes with no slide, recoil, rotation animation, scrim fade, or paper sound.

## Paper sound and accessibility

Qt Multimedia `SoundEffect` is available on the target system. Add two short original mono samples:

```text
assets/paper-map-open.wav
assets/paper-map-close.wav
```

Recommended behavior:

- open sample: restrained paper-on-painted-metal slide, approximately 420 ms;
- close sample: shorter reverse slide, approximately 320 ms;
- default gain: `0.18`;
- no loop, exaggerated crumpling, or reverb;
- play only for user-initiated transitions;
- do not play during startup, forced cartridge exit, initial rendering, pan, or zoom;
- never stack samples; and
- fail silently if audio initialization or an asset is unavailable.

Implemented settings:

```toml
[audio]
mute = false
paper_volume = 0.18

[accessibility]
reduce_motion = false
```

Reduced motion and mute are independent, although reduced motion suppresses map travel sounds because no physical travel occurs. Existing `display.effects=false` controls CRT effects only; paper reduced motion remains an independent explicit setting.

Provide a plain-text accessible summary containing current room, confirmed exits, and visited-room count. Do not rely exclusively on the visual Canvas.

## Delivery phases

### Phase 1: inference harness

- Add pure movement normalization, observer, reducer, and replay APIs.
- Capture bounded transcript fixtures from real runtimes.
- Implement high-confidence Frotz status-line observation.
- Add no map UI yet.

### Phase 2: Zork I proof

Verify:

- West, North, South, and Behind House traversal;
- Kitchen, Attic, Living Room, and Cellar traversal;
- failed movement;
- repeated room names;
- one-way movement;
- nonmovement location changes; and
- restore/load resynchronization.

### Phase 3: safe persistence

- Add content fingerprints.
- Add the bounded atomic map-state helper.
- Add schema and corruption handling.
- Initially ship persistence behind a configuration flag if observer confidence still needs field validation.

### Phase 4: physical paper UI

- Add `MapOverlay.qml` and `MapCanvas.qml`.
- Add the closed paper tab and `MAP / CTRL+P` button.
- Add modal focus behavior, pointer blocking, slide motion, dynamic map rendering, pan, and zoom.

### Phase 5: sound and accessibility

- Add original opening and closing samples.
- Add mute, volume, and reduced-motion settings.
- Add the accessible map summary.

### Phase 6: additional engines

- Add a ScottFree observer.
- Investigate an explicit Open Adventure adapter or high-confidence location event seam.
- Keep unsupported cartridges explicit rather than guessing.
- Consider manual notes and graph correction only after confirmed mapping is stable.

## Test plan

### Pure model tests

Table-test exact movement grammar, including abbreviations, diagonal movement, `in`, `out`, `up`, and `down`. Confirm that conversational, compound, and look-direction commands are rejected.

Replay golden turn fixtures covering:

- startup output;
- successful movement;
- failed movement;
- darkness;
- chunk-split output;
- delayed output;
- same-named rooms;
- one-way edges;
- teleports;
- restore/load;
- undo/restart/death; and
- prose containing room-like lines.

Reducer tests must cover:

- deterministic IDs and layout;
- idempotent replay;
- no fabricated reverse edges;
- ambiguity preservation;
- bounded labels and graph size; and
- the invariant that uncertain observations never increase confirmed node or edge counts.

### Persistence helper tests

Model these after the existing bounded-reader security tests:

- symlink rejection;
- FIFO and special-file rejection;
- oversized state rejection;
- corrupt JSON;
- traversal or malformed fingerprint keys;
- ownership and permissions;
- interrupted writes;
- atomic replacement; and
- schema migration or future-schema refusal.

### Integration tests

Verify:

- shortcut priority and key-repeat suppression;
- Escape closes the map before Lantern;
- focus and command draft restoration;
- map unavailability in the launcher and save/load overlay;
- forced silent closure on process exit;
- animation end states at 1×, 1.25×, and 1.5×;
- scale changes while open;
- no engine command is written by opening the map;
- no move count changes when opening the map; and
- sound-request signals are injectable and testable without requiring an audio device.

## Acceptance criteria

- Opening the map never sends a game command or increases the move count.
- Only visited rooms and confirmed routes appear.
- A failed move creates no edge.
- Restore/load never creates a false route.
- Duplicate room names remain distinguishable.
- Maps survive Lantern restarts and remain isolated by cartridge fingerprint.
- Corrupt map state never blocks a game from launching.
- Escape closes the map before closing Lantern.
- Map focus prevents commands and hardware interactions beneath it.
- Paper color and content remain outside every CRT effect.
- Motion and layout work at all three supported window scales.
- Missing audio degrades silently.
- Reduced-motion and mute settings are respected.
- Existing save, load, menu, launcher, CRT, and window controls continue working.

## Principal risk

The difficult part is trustworthy location inference, not drawing the map. Prove the Frotz observer and graph reducer against recorded Zork output before treating the animated paper overlay as a production feature.
