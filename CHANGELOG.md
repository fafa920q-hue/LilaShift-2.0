# Changelog

English | [简体中文](CHANGELOG_ZH-CN.md)

## [Unreleased]

### Added

- Add SnapshotTesting UI regression tests for the key SwiftUI cards (preset catalog, smart fault diagnosis, personalization center, system health score — unread and populated states, fixed 390×844 layout, light traits) plus text snapshots of the deterministic data feeding the diagnostics card (battery unknown/known, connection not-read/read, cache entries from a fixed directory). The DiagnosticsExpansionCard itself has no image snapshot on purpose: its cache section renders live container sizes that vary with test execution order. Snapshot references are recorded on the first CI run (`record: .missing`) into `tests/__Snapshots__/ViewSnapshotTests/` and must be committed in a follow-up; see `docs/SNAPSHOT_TESTING.md`.
- Add SwiftLint with a minimal rule set (`.swiftlint.yml`, only rules the current codebase already passes) and a SwiftLint CI workflow that runs on every PR to `main`.
- Add the release system: `GestaltX/ReleaseNotes.swift` (version parsing/validation and Markdown rendering), `scripts/prepare-release.py` (validates and optionally bumps the version in the Xcode project, renders release notes from a PR list, verifies the IPA and records its SHA-256), and a `workflow_dispatch`-only Prepare Draft Release workflow that builds the IPA and creates a DRAFT GitHub Release (never published automatically, fails loudly if the tag already exists).

## [1.0.7] - 2026-11-13 - LilaShift 2.0

Build `11130112`. Full-source LilaShift 2.0 project (this repository), based on upstream GestaltX v1.0.7 plus PR #126.

### Added

- Add China Unlock, a one-tap setup for compatible China-mainland iPhones with eSIM hardware: it stages the eSIM cache flags, the U.S. region code (`LL`, sales region untouched) and six Apple Intelligence presets (Apple Intelligence, Audio Intelligence, Personal Translator, Photos Clean Up, Handwriting Synthesis, always-listening Hey Siri) as nine staged changes for review before applying. If the eSIM cache layout cannot be verified, staging stops for the whole group and shows the reason; region code and AI remain settable through their individual presets. One-tap restore reverts all nine items to their recorded originals.
- Redesign the Tools home, preset group pages and change review in Liquid Glass: a shared glass component system (`GlassBackground`, `GlassCard`, `GlassButton` styles, `GlassFeatureRow`, `GlassCategoryTile`, `GlassStatusBadge`, `GlassBottomBar`) built on the native iOS 26 `glassEffect` / `GlassEffectContainer` APIs with a Material fallback, Reduce Transparency / Reduce Motion / Dynamic Type support, and light/dark mode; a China Unlock status card with live eSIM, region-code and Apple Intelligence status, grouped preset categories, per-preset status with a pending-changes count, and a change-confirmation page that summarizes the China Unlock items with before/after values and technical details. The bottom tab bar stays the native iOS 26 glass tab bar.
- Restyle the Liquid Glass theme in light lavender (#F6F3FF page background, #EAE1FF glass, #8652DC primary purple): a light-purple glass unlock card and category tiles, purple-gradient primary buttons and a light-purple glass tab bar; dark mode keeps a readable deep-plum glass theme. Add a live author badge, read-progress cards driven by the real read state (indeterminate — the upstream read path reports no numeric progress, so no percentage is invented) and an apply-progress card (backup → write → verify → done) driven by the real write flow observed through the session log.
- Add an Open Source & Acknowledgements section to About: the original project GestaltX by huamidev, the enhanced version maintained by @steam8871, the GNU GPL v3.0 license and the original project URL, with in-app license text and source links; original contributor acknowledgements are unchanged.
- Harden the write path, learned from Erosion-CN (no code copied): in-place writes with `F_FULLFSYNC` and full read-back verification plus in-place rollback, runtime dynamic resolution of the eSIM cache layout, a diff preview before applying, a dual-vault backup with a factory vault that survives uninstall/reinstall, a region-mode choice (region code only, or full US `LL` + `LL/A`), and a 4-factor Apple Intelligence checkup with slot-level conflict guards.
- Rebrand the app as LilaShift (Chinese name 紫序) and use a cat photo as the app icon.

### Changed

- Keep the iOS 27.3 container-discovery fix and diagnostic logging from 1.0.7, including the Share Log entry.

### Fixed

- Fix container discovery on iOS 27.3 so wallpaper and App Launch Images can locate their containers again.

## [1.0.6] - 2026-11-12

Build `11122300`.

### Added

- Add custom lock screen text in System Settings, applied without restarting the device.
- Add Wallpaper Settings for importing, applying and removing wallpaper packs, including `.tendies` and `.zip` import through the share extension.
- Add App Launch Images with custom photos, full-resolution saving to Photos, automatic backups and restore.
- Add Japanese localization based on [@kagithu](https://github.com/kagithu)'s contribution, with missing strings completed ([#124](https://github.com/huamidev/GestaltX/issues/124)).
- Add the iPhone Air Dynamic Island layout ([#105](https://github.com/huamidev/GestaltX/pull/105)).

### Changed

- Add a symbol to Discard Changes. Apply Changes and Discard Changes now turn gray when there are no pending changes.

### Fixed

- Preserve device-specific On-Device Siri capability values instead of overwriting them with a generic value, which could revert the Apple Intelligence Siri interface ([#102](https://github.com/huamidev/GestaltX/pull/102), [#98](https://github.com/huamidev/GestaltX/issues/98)).
- Improve shared-import cancellation and temporary-file cleanup.

**Full Changelog**: https://github.com/huamidev/GestaltX/compare/v1.0.5...v1.0.6

## [1.0.5] - 2026-11-11

Build `11111140`.

### Added

- Spanish localization, bringing the app to nine supported locales ([#97](https://github.com/huamidev/GestaltX/pull/97)).
- iPhone Air model presets ([#92](https://github.com/huamidev/GestaltX/pull/92)) and a Japanese README ([#83](https://github.com/huamidev/GestaltX/pull/83)).

### Changed

- About now lists the supported OS as iOS / iPadOS 27.x. Installation remains
  available on 26.x, where on-device MobileGestalt access is marked unsupported.
- Updated Korean translations ([#84](https://github.com/huamidev/GestaltX/pull/84)) and corrected mixed-language text in
  Traditional Chinese and other locales ([#61](https://github.com/huamidev/GestaltX/pull/61)).
- Renamed the Chinese Photos Clean Up preset to “照片消除”.
- Corrected the Internal Build label and added confirmation before enabling
  this system-wide flag ([#60](https://github.com/huamidev/GestaltX/pull/60)).

### Fixed

- Device access preserves existing App Group cache contents ([#55](https://github.com/huamidev/GestaltX/pull/55)).
- Reverting Dynamic Island restores its layout together with its capability
  flag, without discarding unrelated staged artwork changes ([#58](https://github.com/huamidev/GestaltX/pull/58)).
- Original-value recovery now checks the cache generation and layout, keeps
  unavailable originals distinct from missing fields, and avoids repeatedly
  reading old backup history ([#65](https://github.com/huamidev/GestaltX/pull/65), [#66](https://github.com/huamidev/GestaltX/pull/66)).
- Restoring an unchanged backup skips unnecessary device writes ([#69](https://github.com/huamidev/GestaltX/pull/69)).
  Failed backup deletions remain retryable ([#70](https://github.com/huamidev/GestaltX/pull/70)), and local backup
  replacement clears inherited device-ownership status ([#64](https://github.com/huamidev/GestaltX/pull/64)).
- Exports of verified device backups carry device-bound proof ([#59](https://github.com/huamidev/GestaltX/pull/59)).
  Temporary export files are removed after sharing or cancellation ([#62](https://github.com/huamidev/GestaltX/pull/62)).
- Direct file imports are captured before confirmation is deferred ([#63](https://github.com/huamidev/GestaltX/pull/63)),
  and coordinated reads run off the main thread ([#75](https://github.com/huamidev/GestaltX/pull/75)). Temporary provider
  failures ([#74](https://github.com/huamidev/GestaltX/pull/74)) or one inaccessible App Group ([#71](https://github.com/huamidev/GestaltX/pull/71)) no longer block
  other queued imports.
- Shared import handling checks container boundaries, rejects symlink paths,
  bounds filename metadata, and cleans abandoned files without interrupting
  active writers ([#72](https://github.com/huamidev/GestaltX/pull/72), [#73](https://github.com/huamidev/GestaltX/pull/73), [#76](https://github.com/huamidev/GestaltX/pull/76)).
- Device identity changes are rejected before system writes ([#67](https://github.com/huamidev/GestaltX/pull/67)).
  Duplicate cache descriptors are validated ([#56](https://github.com/huamidev/GestaltX/pull/56)), and unchanged NaN
  values compare consistently ([#68](https://github.com/huamidev/GestaltX/pull/68)).

### Download and signing

- Some users report incomplete downloads with Safari on iOS 27. If an IPA is
  reported as damaged or cannot be extracted, download it again; it may take
  several attempts. Try another browser if the issue persists. This has not
  been confirmed as a Safari or iOS defect.
- Re-sign with a certificate and profile containing at least one usable App
  Group. Keep the share extension and configure a common App Group for both
  the app and extension.

**Full Changelog**: https://github.com/huamidev/GestaltX/compare/v1.0.4...v1.0.5

## [1.0.4] - 2026-11-10

Build `11101436`.

### Added

- WAPI preset under **Device → Presets**: disable the WAPI regulatory flag or
  restore the recorded original value. The cached Boolean is resolved from the
  device's own MobileGestalt image instead of a hard-coded slot (#30).
- Per-device originals for the WAPI flag. The value survives edits, app
  restarts, journal migration, and is restored together with the other cached
  options (#30).
- New display presets: high-luminance Always-On Display, AOD flipbook and its
  entry count, HDR photo display, wallpaper parallax control, and experimental
  PWM and DisplayPort capability flags.
- New device presets: Collision SOS, Audio Mix, and Spatial FaceTime audio.
- New intelligence presets: on-device Siri, Audio Intelligence, Personal
  Translator, Photos Clean Up, Handwriting Synthesis, and always-listening Hey
  Siri. These remain capability flags; hardware and region still decide what
  actually runs.
- Korean localization, bringing the app to eight supported languages (#24).
- CI now builds an ad-hoc signed IPA automatically and uploads it as an
  artifact; tag and release runs also attach it to the matching release.

### Changed

- Additional Options and the WAPI row are shown directly in
  **Device → Presets**. The hidden ten-tap unlock on the About version string
  was removed.
- Restore and open actions are disabled while the current document has staged
  edits. Save or discard them first instead of silently losing the changes
  (#37).
- Version bumped to 1.0.4 (`CURRENT_PROJECT_VERSION` 11101436). README version
  badges and the build date were updated.
- All new user-facing strings are localized in the eight supported languages
  (English, Simplified Chinese, Traditional Chinese for Taiwan and Hong Kong,
  Vietnamese, Russian, Persian, and Korean) (#30, #38).

### Fixed

- Device access now falls back across every signed App Group instead of
  trusting the first one. This fixes the `MobileGestalt access was denied`
  error on builds signed with a certificate that carries multiple App Groups
  (#47).
- Field editing preserves exact 64-bit integers, including unsigned values
  above `Int64.max`. Read-back comparison no longer aliases `UInt64.max` with
  `-1` (#31).
- Opening a field and applying it unchanged no longer re-parses its display
  text, preserving sub-millisecond `Date` precision and nested values in
  arrays and dictionaries (#34).
- Malformed `ArtworkTraits` values are no longer replaced or lost when a model
  name or Dynamic Island layout preset is applied. The UI explains that the
  field must be fixed in MG Control first (#38).
- Device backup restores reject a different `CacheUUID`, `CacheVersion`, or
  `CacheData` length before any write, instead of restoring an incompatible
  cache layout (#32).
- Saved backups are verified against their recorded size and SHA-256 digest
  before reuse. Legacy backups without a digest remain readable (#33).
- Shared plist imports reject FIFOs, sockets, directories, and symlinks instead
  of blocking on them, while still accepting regular files (#35).
- File Provider imports coordinate their reads, so placeholders are
  materialized and concurrent changes cannot corrupt the read (#39).
- Cancelling the share extension now resumes a stalled provider continuation
  and cancels the underlying `Progress`, instead of hanging the extension
  (#36).
- Rejecting or confirming one shared plist no longer leaves later queued
  imports waiting for another foreground event. Invalid entries are skipped
  and the queue continues in order (#40).
- Backup restore now validates the saved layout before creating a recovery
  backup or journal entry, so a rejected restore has no side effects (#32).

### Security

- Backup integrity uses a persisted SHA-256 digest. A same-size replacement
  with another valid plist is detected (#33).
- Inbox scans and imports open files with `O_NOFOLLOW` and require a regular
  file descriptor, preventing named-pipe and symlink tricks (#35).

**Full Changelog**: https://github.com/huamidev/GestaltX/compare/v1.0.3...v1.0.4

[1.0.6]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.6
[1.0.5]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.5
[1.0.4]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.4
