#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"; work="$(mktemp -d /tmp/cpt-upload-ios.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/Handler" "$work/Tests/HandlerTests"
cp "$root/Tests/CPTUploadHandler/Package.swift" "$work/Package.swift"
cp "$root/Tests/CPTUploadHandler/Stubs.swift" "$work/Sources/Handler/"
cp "$root/Tests/CPTUploadHandler/HandlerTests.swift" "$work/Tests/HandlerTests/"
cp "$root/Tests/CPTUploadHandler/CharacterizationStorageTests.swift" "$work/Tests/HandlerTests/"
cp "$root/GeoSome/Features/CPTRecommendation/Components/CPTRecommendedPointSheetView.swift" "$work/Sources/Handler/"
cp "$root/Tests/SketchLogicRecovery/SketchUIRegressionTests.swift" "$work/Tests/HandlerTests/"
# Offscreen ImageRenderer cannot draw the platform ScrollView. Adapt only the
# test container; keep all production inner content/styles unchanged.
sed -e 's/struct CPTRecommendedPointSheetView: View/struct RecoveredSketchContent: View/' -e 's/ScrollView(.vertical, showsIndicators: false) {/Group {/' "$root/GeoSome/Features/CPTRecommendation/Components/CPTRecommendedPointSheetView.swift" > "$work/Sources/Handler/RecoveredSketchContent.swift"
cp "$root/GeoSome/Features/CPTRecommendation/Models/StratigraphicCharacterization.swift" "$work/Sources/Handler/"
cp "$root/GeoSome/Features/CPTRecommendation/Components/StratigraphicCharacterizationView.swift" "$work/Sources/Handler/"
printf 'null' > "$work/Tests/HandlerTests/stop-sync-snapshot.json"
cp "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicStop.swift" "$work/Sources/Handler/"
cp "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicHistory.swift" "$work/Sources/Handler/"
for path in GeoSome/Features/CPTRecommendation/ViewModels/CPTRecommendationViewModel.swift GeoSome/Features/CPTRecommendation/Models/CPTData.swift GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyHistory.swift GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift GeoSome/Features/BoundaryCreation/Models/BoundaryPoint.swift GeoSome/Features/Project/Models/Project.swift GeoSome/Features/Project/ViewModels/ProjectViewModel.swift; do cp "$root/$path" "$work/Sources/Handler/"; done
python3 - "$root" "$work" <<'PYHELPER'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
source=(root/'GeoSome/Features/Result/Components/ResultLeftPlaceholderSheetView.swift').read_text()
(work/'Sources/Handler/ExistingSheetSizing.swift').write_text(source[:source.index('struct LegendMapItem:')])
view=(root/'GeoSome/Features/CPTRecommendation/Views/CPTRecommendationView.swift').read_text()
start=view.index('  private var isPracticalStop:')
end=view.index('  private var activeSheetDetents:',start)
body=view[start:end].replace('private var ', 'var ')
destination=view[view.index('  private var activeSheetDestination:'):start].replace('private var ', 'var ')
(work/'Sources/Handler/RecommendedBindingProbe.swift').write_text('import SwiftUI\n@MainActor struct RecommendedBindingProbe {\n var viewModel: CPTRecommendationViewModel\n'+destination+body+'\n}\n')
PYHELPER
cd "$work"
set +e
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -scheme CPTUploadHandler -destination 'platform=iOS Simulator,id=B400B9AE-DCB2-480A-9561-1584D167E7A2' -resultBundlePath "$work/results.xcresult" test
result_code=$?
set -e
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path "$work/results.xcresult" --format json

if [[ -n "${CPT_TEST_ARTIFACTS_DIR:-}" ]]; then
  mkdir -p "$CPT_TEST_ARTIFACTS_DIR"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool export attachments --path "$work/results.xcresult" --output-path "$CPT_TEST_ARTIFACTS_DIR/rendered/$(basename "$work")" > "$CPT_TEST_ARTIFACTS_DIR/attachments-export.json"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path "$work/results.xcresult" --format json > "$CPT_TEST_ARTIFACTS_DIR/test-summary.json"
fi
exit "$result_code"
