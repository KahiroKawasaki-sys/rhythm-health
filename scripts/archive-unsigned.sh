#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Release archive requires macOS with Xcode."
  exit 1
fi
RHYTHM_ARCHIVE_PATH="${RHYTHM_ARCHIVE_PATH:?Set an absolute archive output path}"
if [[ "$RHYTHM_ARCHIVE_PATH" != /* || -e "$RHYTHM_ARCHIVE_PATH" ]]; then
  echo "Archive output must be an absolute, unused path."
  exit 1
fi
xcodebuild -version
xcodebuild -quiet -project Rhythm.xcodeproj -scheme Rhythm -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$RHYTHM_ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO archive
python3 - "$RHYTHM_ARCHIVE_PATH" <<'PY'
from pathlib import Path
import plistlib, sys
archive = Path(sys.argv[1])
app = archive / "Products/Applications/Rhythm.app"
extension = app / "Extensions/RhythmScreenTime.appex"
with (app / "Info.plist").open("rb") as f:
    main = plistlib.load(f)
with (extension / "Info.plist").open("rb") as f:
    report = plistlib.load(f)
assert main["CFBundleIdentifier"] == "com.kawakahi.rhythm"
assert report["CFBundleIdentifier"] == "com.kawakahi.rhythm.ScreenTimeReport"
assert report["EXAppExtensionAttributes"]["EXExtensionPointIdentifier"] == "com.apple.deviceactivityui.report-extension"
assert "NSExtension" not in report
assert main["CFBundleVersion"] == report["CFBundleVersion"]
assert main["CFBundleShortVersionString"] == report["CFBundleShortVersionString"]
assert main["DTPlatformName"] == report["DTPlatformName"] == "iphoneos"
assert (app / main["CFBundleExecutable"]).is_file()
assert (extension / report["CFBundleExecutable"]).is_file()
print("Unsigned iPhoneOS release archive verified: app and report extension present, versions match.")
print("This archive is not installable. Signing, upload and real-device checks remain.")
PY
