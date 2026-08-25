# Bounded reader build provenance

Lantern ships `bin/read-bounded-file`, an x86-64 Linux executable built from the reviewed `bin/read-bounded-file.c` source. The helper atomically opens and validates mutable configuration and theme files before returning their contents to the long-lived shell.

## Reproducible toolchain

The executable is built by [`scripts/build-bounded-reader`](../scripts/build-bounded-reader) with:

- Docker image `gcc:14.2.0-bookworm`
- pinned linux/amd64 image digest `sha256:82549aa8f90ada3236a8be70c74543132a76662ef33f0c3271ed802b81584a82`
- GCC 14.2.0
- `SOURCE_DATE_EPOCH=0`
- an omitted ELF build ID and stripped debug metadata
- PIE, full RELRO, immediate binding, stack protection, and fortified libc calls

Rebuild the shipped artifact from the repository root:

```bash
./scripts/build-bounded-reader
```

The script mounts the repository read-only, writes through a temporary output, and atomically replaces the destination only after compilation succeeds.

## Verification

`third_party/SHA256SUMS` records both the reviewed C source and the exact executable distributed to users. CI runs the pinned build script into a temporary path, compares that result byte-for-byte with `bin/read-bounded-file`, and then verifies the checksum inventory. A source change, toolchain change, compiler flag change, or executable replacement therefore fails CI until the reviewed artifact and inventory are deliberately regenerated together.
