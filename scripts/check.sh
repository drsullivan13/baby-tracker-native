#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift test
xcodebuild -project BabyTracker.xcodeproj -scheme 'Baby Tracker' \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/baby-tracker-build \
  CODE_SIGNING_ALLOWED=NO build
swiftc -swift-version 5 -D TRANSPORT_TESTING -o /tmp/baby-tracker-transport-probe \
  Sources/BabyTrackerApp/NearbySync.swift scripts/TransportProbe.swift
/tmp/baby-tracker-transport-probe
