# Third-party notices

All original LANTERN code and materials—including QML, JavaScript, C source, shell scripts, tests, and documentation—are licensed under the repository-level MIT license. The bundled interpreter and stories retain their own licenses.

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

Checksums for the distributed upstream artifacts are recorded in `third_party/SHA256SUMS`.
