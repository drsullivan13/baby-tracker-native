# Baby Tracker — native iPhone app

SwiftUI app for two caregivers, with encrypted nearby synchronization and a private Core Data store on each phone. Requires iOS 18 or later. No backend, cloud database, account service, analytics, or export feature.

## Use

Open `BabyTracker.xcodeproj`, select the **Baby Tracker** scheme, choose your Personal Team, and run on each connected iPhone. Follow [setup and renewal](docs/DEVELOPMENT.md) for signing, Developer Mode, and historical import. Free signing requires approximately weekly renewal by installing over the existing app; do not delete it.

Complete the privacy check on each phone before entering real history. Pair in Settings using the QR code, compare the confirmation codes, and approve on both phones. Open both apps nearby to merge changes. Each phone can log offline, but updates do not travel between distant phones. See [privacy and recovery limitations](docs/PRIVACY.md).

The app supports bottle and nursing feeds, nursing/sleep timers, diapers, custom trackers, backdated edits, daily summaries, 7/30-day averages, retained conflicts, and reversible deletion. Today puts quick logging and daily totals first. History separates wet/dirty averages, measured bottle volume, and feeding trends across completed days. Large-text layouts use stacked controls and native menus. It ships empty; historical data is imported separately into the private app container after backup settings are checked.

See the [redesign notes](docs/REDESIGN.md) and [synthetic screen examples](docs/screenshots/redesign/).

## Verification

Run `scripts/check.sh` for domain/persistence tests, an unsigned iPhone build, and authenticated transport checks. Run `scripts/integration-check.sh` for two on-disk stores exchanging synthetic data over the production transport. Xcode also includes a simulator UI smoke test. Only synthetic data belongs in these tests.

These checks do not replace the [two-phone acceptance checklist](docs/DEVICE-ACCEPTANCE.md). Physical installation, nearby radio behavior, permissions, real import, and weekly renewal still require verification on the phones.

UI audit fixtures are available only in debug simulator builds with an explicit `--visual-audit-fixture` launch argument. They use a separate temporary database and preferences suite. They are excluded from physical-device and release builds.
