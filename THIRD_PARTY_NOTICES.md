# Third-party notices

Original LANTERN code and materials are licensed under the repository-level MIT license except the ScottFree stdio adapter under `third_party/scottfree/stdio-glk/`, which is GPL-2.0-or-later for direct linkage with ScottFree. Bundled interpreters and stories retain their own licenses.

## Frotz 2.55 (`dfrotz`)

- Project: [Frotz](https://gitlab.com/DavidGriffith/frotz)
- Version/tag: `2.55`
- Upstream commit: `acf205585a9472d27c07c0fe62da4b8bc89d1ec7`
- License: GNU General Public License, version 2 or any later version
- Distributed file: `runtime/x86_64-linux/dfrotz`
- Complete corresponding source: `third_party/frotz/source/frotz-2.55.tar.gz`
- License text: `third_party/frotz/COPYING`
- Build and binary provenance: `third_party/frotz/BUILD.md`

The distributed executable is the unmodified `usr/bin/dfrotz` from Arch Linux package `frotz-dumb 2.55-1` for `x86_64`. LANTERN does not relicense it.

## Zork I

- Project: [historicalsource/zork1](https://github.com/historicalsource/zork1)
- Pinned commit: `97b7b3d68c075dd9af7da499c3e9690ada3471fd`
- Original game: Zork I by Infocom
- Repository license: MIT, copyright © 2025 Microsoft
- Distributed file: `games/zork1.z3`, copied unchanged from `COMPILED/zork1.z3`
- License text: `third_party/zork1/LICENSE`

## Zork II

- Project: [historicalsource/zork2](https://github.com/historicalsource/zork2)
- Pinned commit: `3da9661098809788a99cef00f00c865c6c204f96`
- Original game: Zork II by Infocom
- Repository license: MIT, copyright © 2025 Microsoft
- Distributed file: `games/zork2.z3`, copied unchanged from `COMPILED/zork2.z3`
- License text: `third_party/zork2/LICENSE`

## Zork III

- Project: [historicalsource/zork3](https://github.com/historicalsource/zork3)
- Pinned commit: `3ec9ed412b5f3cafe65d83c727d07db1fe4a86a8`
- Original game: Zork III by Infocom
- Repository license: MIT, copyright © 2025 Microsoft
- Distributed file: `games/zork3.z3`, copied unchanged from `COMPILED/zork3.z3`
- License text: `third_party/zork3/LICENSE`

The historical repositories note that their source snapshots may not exactly match production source arrangements. LANTERN distributes the compiled Z-machine files already present in those MIT-licensed repositories without modification; it does not claim to reproduce them from the surviving ZIL source.

## Open Adventure 1.22 (`advent`)

- Project: [Open Adventure](https://gitlab.com/esr/open-adventure)
- Version/tag: `1.22`
- Peeled source commit: `e6160529e70a8c7a06b9a5f190d69aa35c4c62f5`
- Original game: Adventure 2.5 by Will Crowther and Don Woods
- License: BSD-2-Clause
- Copyright notices: `(C) 1977, 2005 by Will Crowther and Don Woods`; `(C) Eric S. Raymond <esr@thyrsus.com>`
- Distributed file: `runtime/x86_64-linux/advent`
- Complete upstream source: `third_party/open-adventure/source/open-adventure-1.22.tar.gz`
- Lantern terminal patch: `third_party/open-adventure/lantern-terminal.patch`
- License text: `third_party/open-adventure/COPYING`
- Build and binary provenance: `third_party/open-adventure/BUILD.md`

Lantern's build replaces optional libedit input with stdio, suppresses process-side command echo, and enables upstream's autosave mode. The resulting executable contains the generated dungeon database and dynamically depends only on glibc.

## ScottFree 1.14 (`scottfree`)

- Project: [ScottFree Glk](https://github.com/cspiegel/scottfree-glk)
- Pinned commit: `b69a8498ce440a6519798fedbee14a96b0c8ea22`
- License: GPL-2.0-or-later
- Copyright notices: `(c) 1993, 1994, 1995 Swansea University Computer Society`; Glk portions copyright 2011 Chris Spiegel
- Distributed file: `runtime/x86_64-linux/scottfree`
- Complete upstream source: `third_party/scottfree/source/scottfree-glk-b69a8498.tar.gz`
- Lantern stdio adapter source: `third_party/scottfree/stdio-glk/`
- License text: `third_party/scottfree/COPYING`
- Build and binary provenance: `third_party/scottfree/BUILD.md`

The GPL license covers the interpreter, not Scott Adams' original adventure databases. Lantern distributes no original Scott Adams game data and claims no right to redistribute it. The `tests/fixtures/minimal-scott.dat` compatibility fixture contains only original Lantern test text.

Checksums for the distributed upstream artifacts and Lantern native helpers are recorded in `third_party/SHA256SUMS`.
