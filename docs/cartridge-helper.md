# Cartridge helper

`bin/lantern-cartridge` is Lantern's bounded native boundary for importing, validating, and identifying user-supplied cartridge files.

## Commands

```text
lantern-cartridge import-zmachine SOURCE DIRECTORY
lantern-cartridge import-scott SOURCE DIRECTORY
lantern-cartridge check-zmachine STORY DIRECTORY
lantern-cartridge check-scott STORY DIRECTORY
lantern-cartridge fingerprint-zmachine STORY
```

`fingerprint-zmachine` opens the story with the same `O_NOFOLLOW`, regular-file, size, and Z-machine header checks used by import. It hashes the contents through that already-validated descriptor, using the helper's internal SHA-256 implementation with no additional runtime library. Successful output is exactly one lowercase 64-character SHA-256 digest followed by a newline. Validation or read failure produces no digest and exits nonzero.

The fingerprint is intended as stable cartridge identity for data such as cumulative automap state; filenames and launcher IDs are not content identities.

## Import safety

Imports reject symlinks and nonregular files, enforce format size limits, and copy through a private temporary file. The destination library must be user-owned at mode 0700. New files use mode 0600; duplicate names receive a suffix rather than overwriting an existing cartridge. Copies are bounded to the observed source size, reject a changed length, and synchronize the file and directory before reporting success.

Z-machine checks identify versions 1–8; ScottFree header checks reject overflowing integer tokens and bound database dimensions. These checks do not prove arbitrary native game data is harmless: runtime validation remains necessary, and callers should import only trusted, legally obtained games. The format check is not a process sandbox.

## Reproducible build

**Candidate caveat:** during 0.2.0 review the source was hardened and the binary rebuilt with local GCC 16.2.1 for testing. Docker access was denied. Replace it with the pinned build and update its checksum before release; byte-for-byte correspondence is not yet verified for this candidate.

From the repository root:

```bash
./scripts/build-cartridge-helper
```

The script builds the shipped x86-64 Linux helper in the pinned GCC container with PIE, full RELRO, stack protection, fortification, stripped metadata, and no build ID. CI rebuilds it byte-for-byte, and `third_party/SHA256SUMS` inventories both source and binary.
