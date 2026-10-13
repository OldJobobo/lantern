# Automap state helper

`bin/lantern-map-state` is a standalone x86-64 Linux helper built from the reviewed `bin/lantern-map-state.c`. `Panel.qml` invokes it directly with fixed operation, engine, and fingerprint arguments; map JSON is written only through standard input and persistence failures remain nonfatal to cartridge launch and play.

The current host integration supports the Z-machine observer, cumulative map persistence, the paper overlay, plain-text accessibility summary, and `accessibility.reduce_motion`. Paper sound assets and playback remain deferred; `MapOverlay.transitionSoundRequested` stays available for that later audio seam.

## State boundary

`Automap.toPersistentState(state)` returns only cumulative graph truth:

- `schemaVersion`
- cartridge engine and SHA-256 identity
- confirmed nodes and directed edges
- deterministic layout seed and positions
- `turn`

The turn counter is persisted deliberately so hydrated sessions continue monotonic `firstSeen` and `lastSeen` timestamps. `currentNodeId`, `candidateNodeIds`, and `resyncRequired` are never serialized. `Automap.hydratePersistentState()` restores `turn` and graph truth but sets no current room and requires fresh confirmed location evidence before another route can be drawn.

## CLI

The helper accepts exactly one operation plus an engine and lowercase SHA-256 key:

```text
lantern-map-state read  <engine> <sha256>
lantern-map-state write <engine> <sha256>
lantern-map-state reset <engine> <sha256>
```

`write` accepts JSON only through standard input. `read` writes validated JSON to standard output. `reset` removes only the exact validated key. Missing, corrupt, future-version, unsafe, or oversized state returns nonzero and is recoverable by the caller.

State files are located at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/lantern/maps/<engine>-<sha256>.json
```

The helper bounds state to 2 MiB, 4,096 nodes, 16,384 edges, 128-byte decoded UTF-8 labels, 96-byte commands, and schema version 1. Persistent cartridge identity requires a nonempty validated engine and exactly 64 lowercase hexadecimal SHA-256 characters. JSON strings accept only strict RFC 3629 UTF-8; `\uXXXX` escapes are decoded to UTF-8 with valid surrogate pairs combined and lone surrogates rejected. Labels reject C0 and DEL controls and the ECMAScript whitespace/line-terminator set at label boundaries while allowing those Unicode spaces internally.

It validates cartridge/key agreement, references, coordinates, timestamps, duplicate identities and edges, ownership, regular-file type, symlinks, and file modes. Persisted edge commands are limited to 96 decoded UTF-8 bytes and normalize only ASCII space and tab before matching movement grammar; transient input normalization remains separate. Schema numbers use exact JSON numeric grammar up to the overall state-size bound and are accepted only when their parsed Number value is an in-range integer, so equivalent spellings such as `2.0`, `2e0`, and `-0` are valid where their resulting value satisfies the field constraint.

Writes use a mode-0600 temporary file, `fsync`, atomic `rename`, and directory `fsync`; the `maps` directory must remain owned by the current user at mode 0700 for every operation. The shared `lantern` parent may retain mode 0755 from v0.1.x, but must be user-owned and not group/world-writable. Existing directories are never chmodded during upgrade. Reset succeeds without a file only when the hierarchy is genuinely absent; unsafe hierarchy errors remain nonzero.

When `XDG_STATE_HOME` is unset, the helper opens `HOME` without following symlinks and traverses or creates `.local/state` one component at a time with `openat` and `O_NOFOLLOW`. Newly created state directories use mode 0700, and each parent directory is synchronized after creation before the state file is published.

## Reproducible build

Build the shipped helper from the repository root:

```bash
./scripts/build-map-state-helper
```

**Candidate caveat:** the 0.2.0 compatibility fix was rebuilt locally with GCC 16.2.1 because Docker access was denied. The checksum records that test artifact. A replacement from the pinned build and byte-for-byte verification are required before release.

The script uses the same pinned `gcc:14.2.0-bookworm` linux/amd64 image and hardened PIE, full-RELRO, stack-protection, fortify, stripped-metadata, and omitted-build-ID settings as the existing bounded reader build. `third_party/SHA256SUMS` records the reviewed C source and shipped binary so the existing artifact verification detects drift.
