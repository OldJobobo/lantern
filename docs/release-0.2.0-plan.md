# Lantern 0.2.0 release plan

## Goal and scope

Ship the multi-engine cartridge library and a trustworthy explorer map without regressing CRT controls, saves, or window behavior. Review and finish existing work in the main checkout and `.worktrees/automap-core`; do not reimplement it blindly.

Include Frotz, Open Adventure, ScottFree, managed imports, engine-specific saves, Adventure autosave, persistent automapping for verified Z-machine cartridges, accessible paper UI, reduced motion, quiet original paper sounds, and reproducible helpers/runtimes.

Defer ScottFree/Open Adventure automapping, manual map editing/hints, additional engines, and additional architectures. Engine support is not automap support. Narrow mapping to proven cartridges rather than weaken correctness.

## Execution phases and gates

1. **Preserve and reconcile.** Inventory tracked/untracked changes, binaries, fixtures, artwork, and agent artifacts. Preserve both dirty states; compare overlapping changes; establish `release/0.2.0`. Separate reviewable concerns: engine provenance, imports, inference, identity/persistence, and presentation. Gate: no existing work lost; all changes accounted for; development-only artifacts excluded.
2. **Native safety and packaging.** Audit cartridge/map helpers, call sites, ownership, symlinks/special files, size limits, atomicity, and races. Exercise invalid/cancelled/duplicate imports and unwritable directories. Verify corresponding source, licenses, checksums, pinned builds, and byte correspondence. Gate: adversarial tests and exact rebuilds pass; no proprietary Scott Adams databases bundled.
3. **Gameplay and saves.** Exercise every engine, imported stories, process lifecycle, menu transitions, saves/restore/cancellation/overwrite, Adventure checkpoint/resume, rapid switching, and pending-operation shutdown. Preserve v0.1.7 payload/config/save compatibility. Gate: launch/play/save-or-checkpoint/exit/resume works without leakage or stuck UI.
4. **Inference and persistence.** Review command/output pairing, framing, epochs, duplicate labels, darkness, failed moves, one-way routes, restore/restart/death, delayed/split output, schema corruption, queue saturation, interrupted writes, and switching cartridges. Explicitly restrict mapping availability to proven cartridges. Gate: no hidden commands, fabricated routes, cross-session writes, or launch blocking on corrupt state.
5. **Paper experience.** Standardize Ctrl+P. Verify CRT isolation, modal focus/draft restoration, Escape priority, pointer blocking, silent forced closure, dense graphs, labels, disconnected regions, pan/zoom/reset, all three scales. Add original quiet opening/closing audio, mute/volume, reduced motion, and accessible summary. Gate: real Quickshell behavior passes, not merely source-pattern assertions.
6. **Release candidate verification.** Improve executable integration tests; run tests, engine smoke, checksums, byte-for-byte rebuilds, QML/shader/plugin validation. Run wrong-owner tests in a suitable isolated environment. Verify fresh install, upgrade from v0.1.7, and live-shell regression. Gate: clean integrated CI and documented acceptance, no unresolved blockers. Candidate target: 0.2.0-rc.1.
7. **Documentation and release preparation.** Describe verified behavior/limits, update stale Proposed/F2 plan, document formats/paths/identity/reset/recovery, retain provenance/licenses, separate concept artwork from runtime assets, update previews and manifest 0.2.0. Gate: exact release contents match docs and tested commit. Publishing/tagging requires explicit approval.

## Priorities

1. Preserve/reconcile both dirty checkouts.
2. Prevent false map routes and stale-session writes.
3. Prove safe imports and engine-specific saves.
4. Verify actual QML UI and upgrade compatibility.
5. Reproducible packaging and truthful documentation.

## Execution record

- Initial baseline: published v0.1.7, local and remote main at 8721734. No additional commits on feat/automap-core; development exists as dirty files.
- Initial verification: main 30/30 tests, engine smoke and checksums pass; automap worktree 101 pass / 1 root-only ownership test skipped.
- Both original dirty states are preserved as inventories and tar archives in `.git/lantern-release-backups/`. The original automap worktree was not changed. Work was reconciled onto `release/0.2.0`; the automap checkout was a superset of main except main-only concept artwork, which is retained.
- Review fixes: bound cartridge copying to the initial source size and reject changed lengths; reject overflowing Scott header tokens; require private, user-owned import libraries; fsync the import directory; allow the safe v0.1.x mode-0755 shared state parent without changing its permissions while retaining private map storage; report map write failures.
- Runtime fixes: refresh the Memory Bank after directory creation and saves, because FolderListModel cannot watch an initially absent directory. Real Panel smoke verifies first saves are discoverable and loadable.
- Automap now enables only the fixture-proven exact Zork I fingerprint, including byte-identical imports. Unsupported games remain playable without mapping. A new real-runtime death fixture demonstrates status-before-death-banner ordering; score/move-counter decreases force reacquisition without a false resurrection edge.
- Added original reproducibly generated paper samples, device-independent sound request tests, mute/volume controls, and independent reduced motion. Removed unused host imports so the actual Panel can run in an isolated Quickshell harness.
- Added Qt interaction tests for Escape/focus/draft preservation, interrupted transitions, forced silent closure, all three scales, and audio policy. Added isolated real-Panel smoke covering every engine, save artifacts, save/load, map modality/no hidden turn, cumulative persistence/restart, and unsupported cartridges. This runs both offscreen and on native Wayland without issuing Hyprland commands or touching installed plugin state.
- Updated manifest to the working 0.2.0 target, README and helper caveats, mapping limits/recovery, and original plan status. Native Wayland capture verified the dense-map paper rendering; `assets/map-preview.png` is a synthetic renderer preview, not runtime map data. Archive exports omit design-only artwork and local coordination artifacts.
- CI now includes release branches, root-only ownership tests, pinned Qt 6.8.3 validation (QtQuick.Effects cannot rely on Ubuntu's old Qt), QML interaction tests, and existing pinned native artifact comparisons. These workflow changes have not yet run remotely.

## Verification results

- Node suite: **105 passed, 1 skipped, 0 failed** (106 tests). The skipped test needs permission to construct a wrong-owner file; CI now explicitly runs it as root against isolated fixtures.
- Qt QML suite: **8 passed, 0 failed**, with actual keyboard/focus, transitions, scale, and audio-policy behavior.
- Real Quickshell Panel: offscreen and native Wayland smoke pass for all engines, Frotz/ScottFree save and load, Adventure checkpoint, map persistence/restart, and unsupported-cartridge gating.
- Bundled runtime smoke, checksums, plugin manifest validation, QML parse checks, standalone map/audio qmllint, shader compilation, and whitespace checks pass locally.
- Native Wayland dense-map capture visually inspected. Software rendering does not render the shader-backed paper effect; an offscreen Vulkan attempt failed. No software-renderer support is claimed.

## Remaining release blockers and acceptance

1. **Pinned native rebuilds:** resolved locally on Neuromancer, where Docker is available. All six native build scripts (bounded reader, cartridge/map helpers, Frotz, Open Adventure, and ScottFree) were run in the digest-pinned GCC 14.2.0 container. The cartridge helper, map-state helper, and patched Frotz replaced their earlier local GCC 16.2.1 candidates and their checksums were refreshed; the other three already matched. A second pinned rebuild of each replaced artifact compared byte-for-byte, and the full suite was rerun against them. Remote CI must still confirm the same correspondence; do not bypass or weaken those checks.
2. **Remote release CI:** not run, because no branch has been pushed. Validate the updated Qt installation/job and privileged ownership test in CI before tagging. Publishing, pushing, and tagging are not performed by this execution.
3. **Host acceptance beyond the isolated harness:** verify installed-plugin upgrade from v0.1.7 with real existing saves/configuration, compositor window placement, manual drag/pan/zoom at all scales, rapid keyboard switching, actual audio audition, file-picker cancellation, and interrupted native-window closure. The harness verifies real QML and engines but does not substitute for all installed-shell behavior. Live config/install mutation requires approval.
4. **Broader inference field testing:** death/restart/restore and duplicate-label cases have fixtures/model coverage, but gameplay through loops, maze regions, and repeated labels still needs a sustained Zork I acceptance session. Other-game observers are explicitly deferred, not unfinished release promises.

- Local candidate commit: `14121e2` (`Prepare Lantern 0.2.0 release candidate`). A single atomic integration commit keeps Panel references and their new components/helpers together; it includes the original unpublished engine and automap work plus reviewed fixes. No `[verified]` release label is claimed.
- Generated unified patches retain upstream context whitespace verbatim; Git whitespace attributes exclude only their context-prefix trailing-space/space-before-tab warnings rather than altering corresponding-source patches.

**Disposition at initial integration:** locally tested candidate, not released. The subsequent `20facfa` dogfood deployment on Wintermute is recorded privately in `.git/lantern-release-backups/wintermute-dogfood-deployment.json`; no push, tag, or publication was performed.

## Post-dogfood room identity correction

Long-play diagnosis found a release blocker: 31 real-runtime frames visited nine actual rooms but the coordinate inferencer created fourteen map nodes. Zork paths are non-Euclidean, and distinct rooms share titles. The live mapper now uses authoritative Frotz room-object IDs exclusively; title and coordinates never select identity.

- The supplied GPL Frotz patch adds opt-in bounded room and completed-input records on stdout. This associates actual VM commands, identities, and status titles without pipe races, filename-dialog confusion, or hidden game input. Default stdout matches the original source build under a fixed random seed.
- `Panel.qml` uses only `reduceIdentifiedTurn`. New IDs require matching status metadata/title; already-known IDs remain recognizable when save/quit omits a title. Revisits reuse nodes and directed routes and increment traversal counts. Controls and decreasing score/moves reacquire without teleport edges. Historical `reduceTurn` remains for old inference fixtures; its previously unreachable ambiguous-navigation branch now has a regression assertion.
- Schema 2 and `<engine>-v2-<sha256>.json` preserve all legacy maps untouched. No unsafe name/coordinate migration or silent deletion is attempted. Current saves and settings remain independent of maps.
- Node suite: **116 passed, 1 ownership test skipped, 0 failed** (117 total). New coverage includes the nine-room/fifteen-route recorded replay, a 1,600-backtracking-move native run, renamed titles, repeated names, geometry collisions, malformed metadata, quit cancellation, restart, forward-move-count restore, and native death-status-before-prose behavior.
- Qt suite: **8 passed, 0 failed**. Actual Quickshell Panel smoke passes offscreen and native Wayland; it now plays the full 30-move regression route, checks nine nodes/fifteen routes, checks the persisted West-to-North edge's six traversals, and checks that metadata is absent from the transcript. All engine/save/restore/persistence gates still pass.
- Engine smoke, QML parse, manifest validation, checksums, JS LSP diagnostics, and whitespace checks pass. The Wintermute dogfood deployment used local GCC 16.2.1 native executables because Docker socket access was denied there; the working tree now carries the pinned GCC 14.2.0 rebuilds made on Neuromancer. CI verifies the exact patched Frotz artifact rather than merely compiling unmodified upstream source.

**Deployment gate:** after the user saved, returned to the menu, and approved installation, the corrected candidate (with its GCC 16.2.1 dogfood binaries) was copied into the installed Wintermute plugin. The installed plugin and Lantern data were backed up first, the copied files were byte-verified, and existing data files, including legacy maps, were confirmed unchanged. Live activation is not verified: a Frotz process started afterwards had no `LANTERN_ROOM_EVENTS` in its environment and only the legacy schema-1 map existed, so the shell most likely still holds the old cached Panel component. Do not restart or reload the shell over an unsaved game; coordinate activation with the user, then verify native metadata opt-in, room-ID nodes, schema-2 persistence, and legacy-map preservation. The installed copy does not yet contain the pinned rebuilds.

Verified live activation, remote CI/push approval, extended installed-shell/audio/maze acceptance, and publication approval remain release gates.
