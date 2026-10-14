# Automap runtime fixtures

Fixtures are recorded output from Lantern's bundled Frotz 2.55 running its bundled Zork I Release 119 / serial 880429 with `-q -m -w 76`. They preserve raw prompt/status framing before presentation cleanup. `.commands` files give one logical command per framed output turn; startup has no command.

The death replay was captured during 0.2.0 review with:

```text
north
east
open window
in
west
move rug
open trap door
down
north
north
north
north
quit
y
```

`y` answers quit confirmation and does not produce a separate status frame. The recorded grue death moves the player from the Troll Room to Forest and deducts ten points. Frotz prints the post-death status before the death banner, so waiting for the banner alone would already have drawn a false route. The integration conservatively reacquires location on any score or move-counter decrease; the death replay asserts no compass edge is added on that turn. Randomized death/resurrection behavior may differ in a fresh run; tests replay the committed observation rather than assuming deterministic live death.

## Authoritative room-ID fixtures

`zork1-room-id-long-play.raw` and its `.commands` capture the patched runtime with `LANTERN_ROOM_EVENTS=1`: 31 rendered status frames, nine distinct room IDs, fifteen distinct directed routes. The legacy coordinate model made fourteen nodes for this same route. Room IDs 32/87 are different Forests; IDs 128/160 are different Clearings. Repeated `w,n,e,s` loops must reuse nodes/connections and increase traversal counts. Both native input and room records are on stdout; no side-channel scheduling or hidden game command is involved.

`zork1-room-id-death.raw` replays `zork1-death.commands` with the patched runtime and fixed seed `-s 1`. The Cellar (33) to Forest (87) resurrection reports a ten-point score decrease before death prose. There must be no 33-to-87 compass edge; subsequent observed Forest-to-Clearing traversal remains valid. The input records include confirmation replies, unlike the original status-only fixture.

The suite also executes fresh native quit-cancellation, restart, forward-move-count restore, and 1,600-move loop runs. The actual Quickshell Panel harness plays the 30-move fixture route and verifies nine nodes, fifteen routes, a reused persisted edge's count, and absence of metadata in the visible transcript.

No precomputed room graph is used by the application. Renderer preview graphs are synthetic and do not supply gameplay observations.
