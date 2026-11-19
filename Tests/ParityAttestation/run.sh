#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d /tmp/terravise-attestation.XXXXXX)"
trap 'rm -rf "$work"' EXIT
app="$work/Test.app/Contents"; mkdir -p "$app/MacOS" "$app/Resources"
source_app=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/GeoSome.app/CPTParityAttestation.json' -print -quit | xargs dirname)
cp "$source_app/CPTParityAttestation.json" "$source_app/UncertaintyV3.json" "$source_app/SufficiencyV3_2.json" "$app/Resources/"
cp -R "$source_app/SchemaGAN_V4_2_Flexible.mlmodelc" "$app/Resources/"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc "$root/Tests/ParityAttestation/main.swift" "$root/GeoSome/Features/CPTRecommendation/Models/CPTData.swift" "$root/GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift" "$root/GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift" "$root/GeoSome/Features/CPTRecommendation/Services/CPTPipelineParityAttestation.swift" -o "$app/MacOS/Test"
"$app/MacOS/Test" "$root/Tests/PipelineParity/attested_fixture.json"
