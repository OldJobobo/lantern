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

1. **Pinned native rebuilds:** Docker socket access is denied. Hardened cartridge/map helpers were rebuilt with local GCC 16.2.1 for behavioral testing, and their checksums reflect these candidate artifacts. They are not the pinned GCC 14.2.0 artifacts promised for release. Once Docker is accessible, run all four native build scripts plus the bounded-reader build, replace changed binaries, refresh checksums, rerun the full suite, and confirm a second pinned rebuild compares byte-for-byte. Do not bypass or weaken CI correspondence checks.
2. **Remote release CI:** not run, because no branch has been pushed. Validate the updated Qt installation/job and privileged ownership test in CI before tagging. Publishing, pushing, and tagging are not performed by this execution.
3. **Host acceptance beyond the isolated harness:** verify installed-plugin upgrade from v0.1.7 with real existing saves/configuration, compositor window placement, manual drag/pan/zoom at all scales, rapid keyboard switching, actual audio audition, file-picker cancellation, and interrupted native-window closure. The harness verifies real QML and engines but does not substitute for all installed-shell behavior. Live config/install mutation requires approval.
4. **Broader inference field testing:** death/restart/restore and duplicate-label cases have fixtures/model coverage, but gameplay through loops, maze regions, and repeated labels still needs a sustained Zork I acceptance session. Other-game observers are explicitly deferred, not unfinished release promises.

- Local candidate commit: `14121e2` (`Prepare Lantern 0.2.0 release candidate`). A single atomic integration commit keeps Panel references and their new components/helpers together; it includes the original unpublished engine and automap work plus reviewed fixes. No `[verified]` release label is claimed.
- Generated unified patches retain upstream context whitespace verbatim; Git whitespace attributes exclude only their context-prefix trailing-space/space-before-tab warnings rather than altering corresponding-source patches.

**Current disposition:** integrated, improved, locally tested 0.2.0 candidate; not releasable until the blockers above are satisfied. No push, tag, installed-config mutation, or published release created.
