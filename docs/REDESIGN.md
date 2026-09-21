# Native UI redesign

Updated September 21, 2026.

## What changed

- Introduced a reusable navy night palette with coral, gold, and teal accents, raised cards, rounded metrics, restrained serif display text, and shared form, button, section, and empty-state styles.
- Moved Feed, Diaper, and Sleep quick logging to the top of Today. Kept existing accessibility identifiers and all logging behavior.
- Added a prominent “So far today” summary for measured bottle volume, total feeds, wet diapers, dirty diapers, sleep, and total diapers. Active timers sit above the summary for easy stopping.
- Refined running timer cards and the bottle, nursing, diaper, sleep, and custom entry sheets for one-handed use and native 44-point-or-larger controls.
- Redesigned History around a clearly labeled selected-day summary, complete-day 7- and 30-day averages, explicit date ranges, and feeding trend bars for feed count and measured bottle volume.
- Split feeding trends into labeled feed-count and bottle-volume lanes with numeric scales, explicit units, readable dates, exact per-day accessibility values, feed-family colors, and truly empty zero-value bars.
- Made Today metrics, average metrics, and the three primary quick-log actions switch to a single vertical column at accessibility Dynamic Type sizes.
- Added a visible “Choose time” button to every custom tracker quick-log row while retaining tap-to-log-now behavior.
- Improved empty states and information hierarchy across onboarding, Today, History, custom trackers, settings, editing, Recently Deleted, conflict review, and pairing.
- Preserved custom-tracker averages, reversible deletion, conflict selection, import controls, nearby sync controls, and privacy acknowledgment gating.

## Statistics behavior

- Today remains a live, partial-day summary and says “through” the current time.
- Rolling averages include zero-log days but never include the current partial day. When History is set to today or a future date, the period ends yesterday.
- A selected past day is included as the final whole day in its rolling window.
- Feed averages separately calculate bottle and nursing counts. Diaper averages separately calculate wet and dirty counts, with a “both” diaper counted in both categories.
- Trend data is ordered from oldest to newest and uses the same completed-day range shown above it.

## Checks

- 31 domain and persistence tests passed, including completed-period arithmetic and calendar-boundary checks.
- Simulator builds succeeded. Logging/relaunch and stopped-sleep editing regressions passed.
- Synthetic UI walkthroughs passed onboarding, tracker editing/archive, invalid bottle recovery, and the primary dashboard, logging, History, settings and pairing surfaces.
- Accessibility XXXL walkthroughs passed Today and feed controls; the screenshots were reviewed alongside normal-size compact iPhone layouts.
- History editors, deleted-record restoration and conflict selection have dedicated synthetic UI coverage. Final conflict-selection rerun is recorded in [verification](VERIFICATION.md).
- Fixture data is isolated in a temporary simulator-only database and never uses family history. Fixtures are excluded from physical-device and release builds.

## Remaining limits

Physical phone signing/installation and two-phone radio/camera/permission acceptance are separate from simulator coverage. Large-text screenshots do not establish a complete VoiceOver or hardware accessibility audit. See [device acceptance](DEVICE-ACCEPTANCE.md).
