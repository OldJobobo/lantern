# LANTERN

LANTERN is a standalone Omarchy Quattro panel for playing Z-machine interactive fiction inside a restrained early-1980s monochrome CRT.

It is deliberately small: the bundled Frotz interpreter runs the game; LANTERN supplies the panel, phosphor display, command entry, history, and session persistence while the Omarchy shell remains alive.

## Install

```bash
omarchy plugin add https://github.com/OldJobobo/lantern.git --enable
```

That is the complete installation. LANTERN includes its own `dfrotz` runtime and an MIT-licensed copy of Zork I. It does not run an installer, use sudo, download assets on first launch, or require a separate package.

Summon it with:

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

Supported phosphor values are `amber`, `green`, and `white`.

## Controls

- **Enter:** submit command
- **Up/Down:** command history
- **Close:** hide LANTERN while leaving the game process alive

Frotz save and restore access is restricted to:

```text
${XDG_STATE_HOME:-~/.local/state}/lantern/saves
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
```

Static validation is not a substitute for opening the panel in a live Quattro shell. Release verification includes a fresh `omarchy plugin add` installation and live gameplay smoke on Omarchy.

## Development

Quattro installs third-party plugins as ordinary Git checkouts under:

```text
~/.config/omarchy/plugins/jobo.lantern
```

The manifest identity and repository layout must remain compatible with that exact destination.

## License

LANTERN's original code is MIT licensed. See [`LICENSE`](LICENSE). Bundled components retain the licenses listed above.
