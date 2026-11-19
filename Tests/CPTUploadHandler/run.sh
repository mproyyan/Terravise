#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"; work="$(mktemp -d /tmp/cpt-upload-ios.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/Handler" "$work/Tests/HandlerTests"
cp "$root/Tests/CPTUploadHandler/Package.swift" "$work/Package.swift"
cp "$root/Tests/CPTUploadHandler/Stubs.swift" "$work/Sources/Handler/"
cp "$root/Tests/CPTUploadHandler/HandlerTests.swift" "$work/Tests/HandlerTests/"
for path in GeoSome/Features/CPTRecommendation/ViewModels/CPTRecommendationViewModel.swift GeoSome/Features/CPTRecommendation/Models/CPTData.swift GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyHistory.swift GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift GeoSome/Features/BoundaryCreation/Models/BoundaryPoint.swift GeoSome/Features/Project/Models/Project.swift GeoSome/Features/Project/ViewModels/ProjectViewModel.swift; do cp "$root/$path" "$work/Sources/Handler/"; done
cd "$work"
set +e
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -scheme CPTUploadHandler -destination 'platform=iOS Simulator,id=B400B9AE-DCB2-480A-9561-1584D167E7A2' -resultBundlePath "$work/results.xcresult" test
result_code=$?
set -e
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path "$work/results.xcresult" --format json

exit "$result_code"
