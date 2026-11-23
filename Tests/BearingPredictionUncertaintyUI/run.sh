#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d /tmp/bearing-presentation.XXXXXX)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
artifacts="${TERRAVISE_TEST_ARTIFACTS_DIR:-$(mktemp -d /tmp/terravise-bearingpredictionuncertaintyui-artifacts.XXXXXX)}"
mkdir -p "$artifacts"
mkdir -p "$work/Sources/BearingPresentation" "$work/Tests/BearingPresentationTests"
cat > "$work/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BearingPresentation", platforms: [.iOS("27.0")], products: [.library(name: "BearingPresentation", targets: ["BearingPresentation"])], targets: [.target(name: "BearingPresentation"), .testTarget(name: "BearingPresentationTests", dependencies: ["BearingPresentation"])], swiftLanguageModes: [.v5])
PACKAGE
source="$root/GeoSome/Features/Result/Components/ResultBearingLayerSheetView.swift"
cp "$source" "$work/Sources/BearingPresentation/"
# ImageRenderer cannot render platform ScrollView offscreen. Adapt ONLY the
# test container, preserving every production content/style modifier.
sed -e 's/struct ResultBearingLayerSheetView: View/struct BearingRenderContent: View/' -e 's/ScrollView(.vertical, showsIndicators: false) {/Group {/' "$source" > "$work/Sources/BearingPresentation/BearingRenderContent.swift"
cp "$root/Tests/BearingPredictionUncertaintyUI/PresentationTests.swift" "$work/Tests/BearingPresentationTests/"
cd "$work"
set +e
xcodebuild -quiet -scheme BearingPresentation -destination 'platform=iOS Simulator,id=B400B9AE-DCB2-480A-9561-1584D167E7A2' -resultBundlePath "$work/results.xcresult" test > "$artifacts/test.log" 2>&1
result_code=$?
set -e
xcrun xcresulttool get test-results summary --path "$work/results.xcresult" --format json > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$work/results.xcresult" --output-path "$artifacts/rendered/$(basename "$work")" > "$artifacts/attachments-export.json"
printf '%s\n' "$work" > "$artifacts/test-work-directory.txt"
cat "$artifacts/test-summary.json"
exit "$result_code"
