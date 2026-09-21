# Build and maintenance

Open `BabyTracker.xcodeproj` in Xcode. The shared scheme is **Baby Tracker**, with an iOS 18 minimum deployment target. The project has no third-party packages. Xcode 27 is installed on the development Mac; the active shell developer directory can still point to Command Line Tools, so set `DEVELOPER_DIR` for commands.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd BabyTrackerNative
swift test
python3 generate_project.py
xcodebuild -project BabyTracker.xcodeproj -scheme 'Baby Tracker' \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/baby-tracker-build \
  CODE_SIGNING_ALLOWED=NO build
```

`generate_project.py` recreates the project deterministically from source files. The generator preserves the configured Personal Team identifier `68WZL8DZXC`; other manual project settings may be reset when regenerating. The app bundle identifier must remain `com.dansullivan.babytracker` after the first install to preserve its data container across renewal.

`scripts/check.sh` runs domain/persistence tests, an unsigned iPhone build, and a synthetic local transport probe. The probe compiles the same transport source with `TRANSPORT_TESTING` to use in-memory test credentials rather than the real Keychain. That flag is not present in app build settings. It does not prove physical peer-to-peer Wi-Fi or hardware-backed Keychain behavior.

The shared Xcode scheme also includes UI smoke tests. Use a dedicated empty simulator; tests create synthetic tracker entries and exercise the privacy acknowledgment only in that simulator. Never run these tests against a phone containing real family records.

## Install and renew

1. Sign in under Xcode → Settings → Apple Accounts with your free Apple Account.
2. Choose your Personal Team under the app target’s Signing & Capabilities.
3. Connect/unlock the phone, trust the Mac, enable Developer Mode on the phone, and complete any restart/confirmation.
4. Select that phone as the run destination and run the **Baby Tracker** scheme. Repeat for the second phone.
5. Verify cloud-backup settings and complete the in-app privacy check before entering real data.
6. Approximately weekly, run/install over the existing app using the same team and bundle identifier. **Do not delete the app to renew.** If installation fails, retain the existing app/data and diagnose signing first.

An interactive guide for the human-only steps is `bash scripts/phone-setup.sh`. It never asks for an Apple password in the terminal.

## Historical import

The app ships empty. Open it once so its excluded private import directory is created. Verify backup settings, then stage the supplied ZIP from its existing local path:

```sh
python3 scripts/stage-history.py /absolute/path/baby-tracker-repo.zip \
  --device YOUR_CONNECTED_PHONE_UDID --backup-disabled
```

The helper extracts into a temporary local directory outside the repository, copies directly into the installed app’s private container through Xcode device services, and removes the Mac staging file. In the app, use Settings → Import staged history, inspect the result, then sync nearby. The app deletes the staged file after a successful import. Do not put real history into source, test fixtures, app resources, cloud folders, screenshots, or build logs.

## Architecture

- `BabyTrackerDomain`: Codable activity/tracker/operation types, pure validation/reduction, statistics, legacy import.
- `BabyTrackerPersistence`: a versioned programmatic Core Data model for immutable operations and local device/revision metadata. A sync receipt follows successful persistent-store commit.
- `BabyTrackerApp`: SwiftUI views plus foreground Network framework transport, QR scanning, nonsynchronizing Keychain credentials, and privacy onboarding.

Keep the existing model and operation schema readable when evolving them. Unsupported schemas must fail with an actionable message, never reset local history. Do not remove tombstones or conflict variants without a separately designed migration/acknowledgment policy.
