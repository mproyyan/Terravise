#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
work="$(mktemp -d /tmp/bearing-relative-contract.XXXXXX)"
fixtures="$HOME/Developer/cpt_super_learn/research_archive/terravise_experiments/Tests/Fixtures/BearingUncertaintyV3Parity.json"
source="$root/GeoSome/Features/CPTRecommendation/Services"
xcrun --sdk macosx swiftc -parse-as-library \
  "$root/Tests/BearingRelativeUncertaintyAvailability/ModelContractTests.swift" \
  "$source/BearingDepthUncertaintyModel.swift" "$source/BearingUncertaintyFlexibleV2.swift" \
  "$source/BearingUncertaintyV3Model.swift" -o "$work/model-contract"
"$work/model-contract" "$root/GeoSome/Features/CPTRecommendation/Resources/BearingUncertaintyV3/bearing_uncertainty_v3.json" "$fixtures"
