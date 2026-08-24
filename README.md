# LANTERN

LANTERN is a standalone Omarchy Quattro plugin for playing Z-machine interactive fiction inside a restrained early-1980s monochrome CRT window.

It is deliberately small: the bundled Frotz interpreter runs the game; LANTERN supplies the panel, phosphor display, command entry, history, and session persistence while the Omarchy shell remains alive.

## Install

```bash
omarchy plugin add https://github.com/OldJobobo/lantern.git --enable
```

That is the complete installation. LANTERN includes its own `dfrotz` runtime and an MIT-licensed copy of Zork I. It does not run an installer, use sudo, download assets on first launch, or require a separate package.

Enabling LANTERN adds its amber lantern icon to the right side of the Omarchy bar. Click it to open or hide the terminal. You can also summon it from the command line:

```bash
omarchy-shell shell summon jobo.lantern '{}'
```

## Platform support

The bundled runtime currently supports **x86-64 glibc Linux**, matching current Omarchy systems. It has no dependencies beyond glibc.

## Games and appearance

Zork I is selected by default. You can summon another legally obtained `.z1`–`.z8`, `.zblorb`, or `.blorb` story by absolute path:

```bash
omarchy-shell shell summon jobo.lantern \
  '{"story":"/absolute/path/game.z5","phosphor":"green"}'
```

Supported phosphor values are `amber`, `green`, and `white`. The CRT shader is enabled by default; pass `"effects":false` for an undistorted, motion-free display:

```bash
omarchy-shell shell summon jobo.lantern \
  '{"effects":false,"phosphor":"amber"}'
```

## Controls

- **Bar icon:** open or hide LANTERN
- **Drag the top label strip:** move the terminal
- **Enter:** submit command
- **Up/Down:** command history
- **Escape:** hide LANTERN while leaving the game process alive

LANTERN remembers the window's monitor and monitor-relative position when it closes. Before the next window is mapped, it installs a temporary Hyprland initial-placement rule for that saved geometry, then removes the rule after creation. The window therefore starts at its persistent location rather than appearing at center and moving afterward. If the saved monitor is unavailable, the compositor's normal placement is left untouched.

The terminal uses a fixed 1020×765 logical-pixel window calibrated for Frotz's 76-column output. Transcript lines never soft-wrap and sit inside a curvature-safe inset so the illustrated tube edge cannot obscure them. The top label strip invokes native window movement. The illustrated bezel, tube well, glass lip, and distorted image share one shader-derived curved edge so the physical frame follows the CRT geometry.

Frotz save and restore access is restricted to:

```text
${XDG_STATE_HOME:-~/.local/state}/lantern/saves
```

Window geometry is stored separately at:

```text
${XDG_STATE_HOME:-~/.local/state}/lantern/window.json
```

## Bundled third-party software

LANTERN includes:

- Frotz 2.55 `dfrotz`, licensed under GPL-2.0-or-later
- Zork I from `historicalsource/zork1`, licensed under MIT

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), the complete corresponding Frotz source under `third_party/frotz/source/`, and the checksum inventory at `third_party/SHA256SUMS`.

The repository-level MIT license applies only to LANTERN's original QML, JavaScript, tests, and documentation. It does not relicense bundled third-party components.

## Validation

```bash
./tests/run
sha256sum -c third_party/SHA256SUMS
./tests/smoke-runtime
omarchy plugin validate .
qmlformat Panel.qml >/dev/null
/usr/lib/qt6/bin/qsb --qt6 -o /tmp/crt.frag.qsb shaders/crt.frag
```

The compiled `shaders/crt.frag.qsb` asset is loaded at runtime; rebuild it with Qt Shader Baker after changing `shaders/crt.frag`.

Static validation is not a substitute for opening the panel in a live Quattro shell. Release verification includes a fresh `omarchy plugin add` installation and live gameplay smoke on Omarchy.

## Development

Quattro installs third-party plugins as ordinary Git checkouts under:

```text
~/.config/omarchy/plugins/jobo.lantern
```

The manifest identity and repository layout must remain compatible with that exact destination.

## License

LANTERN's original code is MIT licensed. See [`LICENSE`](LICENSE). Bundled components retain the licenses listed above.
