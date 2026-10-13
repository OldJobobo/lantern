# ScottFree runtime provenance

Lantern bundles a terminal-safe build of ScottFree 1.14 from:

- Upstream: <https://github.com/cspiegel/scottfree-glk>
- Pinned commit: `b69a8498ce440a6519798fedbee14a96b0c8ea22`
- Upstream archive: `source/scottfree-glk-b69a8498.tar.gz`
- License: GPL-2.0-or-later (`COPYING`)

The upstream Glk port normally links a full Glk implementation. Lantern applies `lantern-safety.patch` to bound database dimensions, strings, references, exits, and item locations, then compiles it with the small GPL-compatible adapter under `stdio-glk/`. The adapter implements only the Glk calls used by the pinned source, maps the inline `-w` interface to stdin/stdout, and confines prompted save filenames to the save root supplied by Lantern. The resulting executable dynamically depends only on glibc.

No original Scott Adams adventure database is included. The interpreter license grants no rights to the separately copyrighted games; users must import legally obtained TRS-80-format `.dat` files.

Rebuild and verify:

```bash
./scripts/build-scottfree /tmp/scottfree
cmp runtime/x86_64-linux/scottfree /tmp/scottfree
ldd /tmp/scottfree
```
