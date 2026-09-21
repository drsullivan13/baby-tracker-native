# Verification record — September 21, 2026

Verified locally with Xcode 27:

- Unsigned iPhone target builds successfully.
- 28 domain/persistence tests pass, including exact Date round trips, duplicate-safe import, concurrent revisions, tombstones, stopped timers, calendar boundaries, and conflict versions that preserve inherited deletion.
- Production Network-framework transport passes synthetic mutual-confirmation, encrypted 200/300 KB chunked transfer, pinned reconnect, incompatible-version rejection, wrong-secret rejection, and failed-save/no-success-ACK checks.
- Two separate on-disk Core Data stores exchange synthetic data over that transport; independent additions, offline concurrent edits, conflict resolution, cross-peer timer stopping, exact reopen, and repeated snapshots converge without duplicate operations.
- Simulator UI tests pass bottle/diaper logging and persisted history after relaunch, plus sleep timer start/stop, completed-record editing, and preservation of stopped state after relaunch. Privacy onboarding was exercised on an empty simulator during the same verification session. The retained [dashboard screenshot](screenshots/synthetic-dashboard.png) contains synthetic data only.
- Original legacy ZIP validated in memory: 39 records, expected types/amounts/timestamps, stable import identifiers and lossless snapshot round trip. No real history was staged or installed.

The UI test run emitted an Xcode simulator diagnostics-collection warning about locating simctl after the test passed. Full accessibility, every editing flow, hardware Keychain, local-network/camera permission behavior, physical radio discovery, free signing renewal, and two-phone installation/import remain on the physical acceptance checklist.

This is a development build, not a completed two-phone rollout. See [device acceptance](DEVICE-ACCEPTANCE.md).

## First physical install

Dan’s iPhone has Developer Mode enabled. A signed build using Personal Team `68WZL8DZXC` installed successfully through devicectl. `codesign --verify --deep --strict` passed, and the provisioning profile includes this phone and expires September 28, 2026 at 16:09:09 UTC. Initial launch was rejected pending on-phone developer-profile trust. No real data was imported. The second phone is deferred at Dan’s request.

## Build 2 — icon and backup instructions

Signed iPhone and simulator builds pass. Installed over the existing app and successfully launched on Dan’s phone. Opaque 1024×1024 generated icon is compiled into the app bundle; decoded bundled icon inspected at 120×120. Empty simulator onboarding visually checked with BabyLogo and numbered instructions sourced from https://support.apple.com/en-us/108922. Privacy acknowledgment remains required; no real records imported.

## Build 3 — native UI redesign

The redesigned source passes 31 domain/persistence tests. On the compact iPhone 17e simulator, all seven UI tests pass across the final suite and a targeted conflict-selection rerun: empty onboarding, history/editors/restore/conflict resolution, tracker edit/archive and invalid-feed alert, both logging/timer regressions, core screen walkthrough, and accessibility XXXL walkthrough. The full final suite originally exposed a conflict-row tap-area regression; adding a full-width, minimum-44-point content shape fixed it, and the affected test passed on rerun.

Synthetic screenshots were visually reviewed for Today, logging sheets, selected-day History and averages/trends, editors, onboarding, trackers, settings, pairing, deleted records, conflicts and validation alerts. Extra-large text controls stack or use native menus; tall content scrolls behind the native translucent bars. This is not exhaustive VoiceOver, landscape, camera, local-network permission, or two-phone hardware acceptance.

The root now shows errors in a dismissible banner while modal forms own their alert presentation, fixing a verified invalid-bottle alert failure. Simulator fixtures have a separate temporary store and are compiled only for debug simulators. No real history was used in the audit.

Build 3 signed successfully after Mac unlock. The final incremental build included the conflict hit-region fix; `codesign --verify --deep --strict` passed and the bundle version was verified as 3. CoreDevice confirmed installation over the existing `com.dansullivan.babytracker` app on Dan’s iPhone, then confirmed successful launch. No uninstall, store reset, or import was performed. This verifies device delivery; it does not establish two-phone acceptance or independently verify the contents/count of personal records.
