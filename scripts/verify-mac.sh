#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Native verification requires macOS with Xcode."
  exit 1
fi
xcodebuild -version
swift test
RHYTHM_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rhythm-build.XXXXXX")"
xcodebuild -quiet -project Rhythm.xcodeproj -scheme Rhythm -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$RHYTHM_BUILD_DIR" CODE_SIGNING_ALLOWED=NO build
echo "Build files: $RHYTHM_BUILD_DIR"
echo "Simulator build passed. Real-device authorization and data checks are still required."
