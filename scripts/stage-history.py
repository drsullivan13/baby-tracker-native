#!/usr/bin/env python3
"""Stage a local legacy ZIP directly into an installed app's private container.
Never prints record contents and never copies records into this repository.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("zip", type=Path)
parser.add_argument("--device", required=True, help="Connected iPhone UDID from xcrun devicectl list devices")
parser.add_argument("--bundle-id", default="com.dansullivan.babytracker")
parser.add_argument("--backup-disabled", action="store_true", help="Confirm cloud backup has been disabled for this app on this phone")
args = parser.parse_args()
if not args.backup_disabled:
    parser.error("Verify the phone's cloud-backup setting first, then pass --backup-disabled.")
with zipfile.ZipFile(args.zip) as archive:
    info = archive.getinfo("baby-tracker/data/records.json")
    if info.file_size > 16 * 1024 * 1024:
        parser.error("History is larger than the supported import limit.")
    raw = archive.read(info)
    value = json.loads(raw)
    records = value.get("activities") if isinstance(value, dict) else value
    if not isinstance(records, list):
        parser.error("The archive does not contain a legacy activity list.")
# TemporaryDirectory uses local OS temp storage, not Documents/iCloud Drive.
with tempfile.TemporaryDirectory(prefix="baby-tracker-import-") as temp:
    path = Path(temp) / "records.json"
    path.write_bytes(raw)
    path.chmod(0o600)
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    subprocess.run([
        "xcrun", "devicectl", "device", "copy", "to", "--device", args.device,
        "--source", str(path), "--destination", "Library/Application Support/Imports/records.json",
        "--domain-type", "appDataContainer", "--domain-identifier", args.bundle_id
    ], env=env, check=True)
print(f"Staged {len(records)} records locally. In Baby Tracker, open Settings → Import staged history.")
print("Staging is not import confirmation. Verify the app's import result and history before syncing.")
