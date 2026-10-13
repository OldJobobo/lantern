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

No precomputed room graph is used by the application. Renderer preview graphs are synthetic and do not supply gameplay observations.
