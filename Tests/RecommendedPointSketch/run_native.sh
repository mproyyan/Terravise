#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
work="$(mktemp -d /tmp/bearing-native.XXXXXX)"
app="$work/BearingSheetVerification.app"
artifacts="${TERRAVISE_TEST_ARTIFACTS_DIR:-$(mktemp -d /tmp/terravise-recommendedpointsketch-artifacts.XXXXXX)}"
mkdir -p "$artifacts"
mkdir -p "$app"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.terravise.recommended-sheet-verification</string><key>CFBundleExecutable</key><string>BearingSheetVerification</string><key>CFBundleName</key><string>BearingSheetVerification</string><key>CFBundleVersion</key><string>1</string><key>CFBundlePackageType</key><string>APPL</string><key>MinimumOSVersion</key><string>27.0</string><key>UIDeviceFamily</key><array><integer>2</integer></array><key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict><key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
python3 "$root/Tests/RecommendedPointSketch/prepare_native.py" "$work"
xcrun swiftc -parse-as-library -target arm64-apple-ios27.0-simulator -sdk "$sdk" \
  "$root/GeoSome/Features/CPTRecommendation/Components/CPTRecommendedPointSheetView.swift" \
  "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicStop.swift" \
  "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicHistory.swift" \
  "$root/GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift" \
  "$work/ExistingSheetSizing.swift" "$work/Dependencies.swift" "$work/NativeSheetApp.swift" -o "$app/BearingSheetVerification"

codesign --force --sign - "$app" > "$artifacts/native-sign.log" 2>&1
xcrun simctl install booted "$app"
run="$(basename "$work")"
for mode in stop continue empty; do
  xcrun simctl launch --terminate-running-process booted com.terravise.recommended-sheet-verification --run-id "$run" --mode "$mode"
  data="$(xcrun simctl get_app_container booted com.terravise.recommended-sheet-verification data)"
  for attempt in {1..15}; do
    if [[ -f "$data/Documents/$run-$mode.json" ]]; then break; fi
    sleep 1
  done
  cp "$data/Documents/$run-$mode.json" "$artifacts/native-$mode.json"
  cp "$data/Documents/$run-$mode.png" "$artifacts/native-$mode.png"
done
python3 - "$artifacts" <<'PYVERIFY'
import json,sys
from pathlib import Path
for mode in ['stop','continue','empty']:
    r=json.loads((Path(sys.argv[1])/f'native-{mode}.json').read_text())
    print(json.dumps(r))
    assert r['pass'], r
PYVERIFY
xcrun simctl terminate booted com.terravise.recommended-sheet-verification
