#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
PROBE_DIR="$(mktemp -d /tmp/babytracker-probe.XXXXXX)"
trap 'rm -rf "$PROBE_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name BabyTrackerDomain \
  Sources/BabyTrackerDomain/*.swift -emit-module-path "$PROBE_DIR/BabyTrackerDomain.swiftmodule" \
  -o "$PROBE_DIR/libBabyTrackerDomain.dylib" -Xlinker -install_name -Xlinker '@rpath/libBabyTrackerDomain.dylib'
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name BabyTrackerPersistence \
  -I "$PROBE_DIR" -L "$PROBE_DIR" -lBabyTrackerDomain Sources/BabyTrackerPersistence/*.swift \
  -emit-module-path "$PROBE_DIR/BabyTrackerPersistence.swiftmodule" \
  -o "$PROBE_DIR/libBabyTrackerPersistence.dylib" -Xlinker -install_name -Xlinker '@rpath/libBabyTrackerPersistence.dylib'
xcrun swiftc -swift-version 5 -D TRANSPORT_TESTING -I "$PROBE_DIR" -L "$PROBE_DIR" \
  -lBabyTrackerDomain -lBabyTrackerPersistence -Xlinker -rpath -Xlinker "$PROBE_DIR" \
  Sources/BabyTrackerApp/NearbySync.swift scripts/IntegrationProbe.swift -o "$PROBE_DIR/probe"
"$PROBE_DIR/probe"
