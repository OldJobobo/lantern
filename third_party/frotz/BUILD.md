# Frotz binary provenance and corresponding source

Lantern distributes the dumb-terminal Frotz executable as `runtime/x86_64-linux/dfrotz`.

## Corresponding source

Upstream project:
https://gitlab.com/DavidGriffith/frotz

- Version/tag: `2.55`
- Commit: `acf205585a9472d27c07c0fe62da4b8bc89d1ec7`
- License: GPL-2.0-or-later; see `COPYING`
- Complete upstream source: `source/frotz-2.55.tar.gz`
- Lantern modification: `lantern-room-events.patch` (GPL-2.0-or-later)

The archive was generated using `git archive --format=tar.gz --prefix=frotz-2.55/` at that commit. Apply the supplied patch to obtain the complete corresponding source for the modified executable.

## Room observation protocol

Setting `LANTERN_ROOM_EVENTS=1` opts into V3 status observations. Default output is unchanged. Before the rendered status line, `z_show_status` flushes pending story output and writes an ASCII record-separator-delimited stdout line:

`RS + LANTERN_ROOM_V1 + space + room-object-id + space + signed-score + space + moves + US + newline`

RS is byte 0x1e; US is byte 0x1f. The object ID is read directly from global 0, the same object passed to `print_object` for the status title. Bounds are V3 object IDs 1–255, signed 16-bit score, and unsigned 16-bit moves. A preceding game or filename prompt may occur on the same line. Identity and title use the same ordered stdout stream, not independently scheduled stderr. No game commands or memory writes are added. Some commands such as quit produce an event without a rendered status title; clients must not carry their command forward to another event.

The dumb interface also emits `RS + LANTERN_INPUT_V1 + space + hex-encoded-command + US + newline` after completed VM line input. Commands are limited to 96 printable ASCII characters; `!` marks an unsupported/oversized/unterminated input instead of truncating it into a movement. This reports input already read by the interpreter, not synthesized input. Filename and overwrite dialogs are excluded. Quit/restart confirmation replies are included, so they cannot leave a client queue attached to a later movement. Prompts preceding metadata remain ordinary visible output.

Lantern enables this only for its fingerprint-verified Zork I cartridge. New IDs require the immediately following matching status title; already-recorded IDs can be recognized from authoritative metadata alone when save/quit omits that title. The client never merges by name or layout and hides metadata from the transcript. Other cartridges receive normal interpreter output.

## Rebuild and release gate

From the repository root:

```bash
./scripts/build-frotz
```

This extracts the archive, applies the patch and builds the dumb interface using digest-pinned GCC 14.2.0 Bookworm. Flags and the container digest are recorded in the script. The result depends only on glibc. Checksums include the archive, patch, script, and executable in `third_party/SHA256SUMS`.

**Current candidate:** built by `scripts/build-frotz` in the pinned container; a second pinned rebuild compared byte-for-byte and the checksum records that artifact. Remote CI has not yet repeated the comparison.

## Historical Arch provenance

The previously distributed unmodified executable came from signed Arch package `frotz-dumb 2.55-1` (x86_64), package SHA-256 `ee48d8bb470dc160da9521982c25c83a25f1f7b7c52a1817417ed531e09126af`. Its executable SHA-256 was `5da9c0887299187cebb643308ec24844115e1a52f61303a9090906114f139c8e`. The signature was verified with `pacman-key --verify` using key `89DB0CFD528EC1A92E0C11341736C918F59A5673` (Alexander Epaneshnikov). Its packaging recipe remains under `arch/` at commit `883616bcff7a79c626b6d5d09812db74d134bce5`; that recipe does not describe the new modified executable.
