# LANTERN implementation plan

## Goal
Create a standalone Omarchy Quattro `panel` plugin that runs Z-machine games inside a restrained early-1980s monochrome CRT interface.

## Product boundary
- A summoned, fixed 1020×765 CRT window sized for curvature-safe, unwrapped 76-column Frotz output and movable through the native compositor.
- Authentic transcript, command input, command history, phosphor palette, scanlines, bloom, vignette, subtle noise.
- Frotz remains the game engine; LANTERN does not reinterpret game prose.
- No network access, AI, map, inventory dashboard, audio, or bundled unlicensed stories.

## Architecture
- `manifest.json`: third-party panel contract, id `jobo.lantern`.
- `Panel.qml`: fixed `FloatingWindow`, lifecycle `open`/`close`, native system movement, persisted monitor-relative geometry, direct `dfrotz` process with stdin enabled.
- `Model.js`: pure tested text normalization, transcript bounding, game path validation, and command history.
- Self-contained release: signed Arch `dfrotz` x86-64 binary, complete corresponding Frotz source, and MIT-licensed Zork I story bundled in the plugin checkout.
- Optional user-owned stories can be supplied by absolute path in the summon payload.
- Saves restricted to `${XDG_STATE_HOME:-~/.local/state}/lantern/saves` using `dfrotz -R`.

## TDD slices
1. RED/GREEN model behavior: normalize commands/output, bound transcript, navigate command history.
2. RED/GREEN manifest and source contract: valid panel declaration, required lifecycle/process/security properties, bundled executable/story, license files, source archive, and verified checksums.
3. Implement QML CRT panel against current Quattro APIs.
4. Validate on Neuromancer/static tooling and Wintermute/live shell separately.

## Risks
- The bundled `dfrotz` build supports x86-64 glibc Linux; reject or clearly report unsupported runtime environments.
- Frotz and Zork remain under their upstream licenses; preserve notices, complete corresponding source, build provenance, and checksum inventory.
- Split line output may omit Frotz's non-newline prompt; LANTERN renders its own prompt and command echo.
- Escape or the bar toggle hides the panel but deliberately leaves the session alive; shell/plugin reload ends it.
- The plugin must not use an exclusive-keyboard layer surface; the normal window leaves the workstation accessible.
- Window geometry is stored under XDG state and restored with a temporary pre-map Hyprland initial-placement rule; post-map movement is not acceptable. Missing saved outputs fall back to compositor placement.
- CRT dimensions stay fixed so shader curvature remains calibrated and all 76 Frotz columns fit without soft wrapping.
- The fragment shader owns the illustrated bezel edge, tube well, curved glass lip, and distorted image using one warped coordinate system, preventing frame/distortion drift.
- Story filenames and game output are untrusted display text and must use plain-text rendering.

## Validation gates
- Node model/contract tests pass.
- `omarchy plugin validate` passes on Wintermute.
- `qmlformat` parses QML on Wintermute.
- Live plugin rescan/enable/summon succeeds.
- Real Zork command produces authentic Frotz output in the live panel/session.
