# Open Adventure runtime provenance

Lantern bundles Open Adventure 1.22 from:

- Upstream: <https://gitlab.com/esr/open-adventure>
- Tag: `1.22`
- Peeled source commit: `e6160529e70a8c7a06b9a5f190d69aa35c4c62f5`
- Upstream archive: `source/open-adventure-1.22.tar.gz`
- License: BSD-2-Clause (`COPYING`)

The runtime is compiled with `scripts/build-open-adventure` in the same digest-pinned Debian Bookworm GCC container used by Lantern's native helpers. The checked-in `generated/dungeon.c` and `generated/dungeon.h` are the captured output of upstream's Python/PyYAML dungeon generator for the pinned source; their checksums are part of `third_party/SHA256SUMS`, so runtime reproduction does not depend on the host's Python environment. The build applies `lantern-terminal.patch`, which:

- replaces libedit with bounded stdio input so the binary depends only on glibc;
- suppresses process-side command echo because Lantern renders submitted commands;
- enables Open Adventure's supported `ADVENT_AUTOSAVE` mode; and
- fixes the upstream autosave build's `const FILE *` warning under `-Werror`.

The captured dungeon database was generated from upstream's `adventure.yaml` with upstream's `make_dungeon.py`, then compiled into the executable. No external story-data file is needed at runtime.

Rebuild and verify:

```bash
./scripts/build-open-adventure /tmp/advent
cmp runtime/x86_64-linux/advent /tmp/advent
ldd /tmp/advent
```

The expected dynamic dependency is only `libc.so.6` (plus the ELF loader and kernel-provided VDSO).
