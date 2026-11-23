#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"; work="$(mktemp -d /tmp/cpt-coordinator-runtime.XXXXXX)"; trap 'rm -rf "$work"' EXIT
app="$work/Test.app/Contents"; mkdir -p "$app/MacOS" "$app/Resources"
source_app=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/GeoSome.app/CPTParityAttestation.json' -print -quit | xargs dirname)
for f in CPTParityAttestation.json UncertaintyV3.json SufficiencyV3_2.json SufficiencyV32FeatureParity.json SchemaGAN_V4_2_Flexible.mlmodelc DQN_V4_6_A.mlmodelc QCFS_CNN_V3.mlmodelc; do cp -R "$source_app/$f" "$app/Resources/"; done
schemas=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Intermediates.noindex/GeoSome.build/Debug-iphonesimulator/GeoSome.build/DerivedSources/CoreMLGenerated/SchemaGAN_V4_2_Flexible/SchemaGAN_V4_2_Flexible.swift' -print -quit)
dqn=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Intermediates.noindex/GeoSome.build/Debug-iphonesimulator/GeoSome.build/DerivedSources/CoreMLGenerated/DQN_V4_6_A/DQN_V4_6_A.swift' -print -quit)
files=(GeoSome/Features/CPTRecommendation/Models/CPTData.swift GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift GeoSome/Features/CPTRecommendation/Services/SchemaGANService.swift GeoSome/Features/CPTRecommendation/Services/UncertaintySufficiencyService.swift GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyHistory.swift GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyDispatch.swift GeoSome/Features/CPTRecommendation/Services/CPTPipelineParityAttestation.swift GeoSome/Features/CPTRecommendation/Services/CPTPipelineCoordinator.swift GeoSome/Features/CPTRecommendation/Services/QCFSInferenceService.swift GeoSome/Features/CPTRecommendation/Services/DQNFeatureBuilder.swift GeoSome/Features/CPTRecommendation/Services/BearingRuleService.swift GeoSome/Features/CPTRecommendation/Services/BearingRuleEngine.swift GeoSome/Features/BoundaryCreation/Models/BoundaryPoint.swift GeoSome/Features/Project/Models/Project.swift)
for i in "${!files[@]}"; do files[$i]="$root/${files[$i]}"; done
"$HOME/Developer/cpt_super_learn/cpt/bin/python" "$root/Tests/DynamicStopReplay/prepare.py" "$work/fixture.json"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -D DEBUG -D CPT_SYNTHETIC_REPLAY "$root/Tests/DynamicStopReplay/main.swift" "${files[@]}" "$schemas" "$dqn" -o "$app/MacOS/Test"
"$app/MacOS/Test" "$work/fixture.json"
