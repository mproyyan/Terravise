#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/../.." && pwd)"
research="${SCHEMAGAN_RESEARCH_ROOT:-$HOME/Developer/cpt_super_learn}"
fixture="${1:-/tmp/terravise-geosyn-00018/distributed_cpt3.json}"
work="$(mktemp -d /tmp/terravise-schemgan-parity.XXXXXX)"
trap 'rm -rf "$work"' EXIT
app="$work/Parity.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
model=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/GeoSome.app/SchemaGAN_V4_2_Flexible.mlmodelc' -print -quit)
wrapper=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Intermediates.noindex/GeoSome.build/Debug-iphonesimulator/GeoSome.build/DerivedSources/CoreMLGenerated/SchemaGAN_V4_2_Flexible/SchemaGAN_V4_2_Flexible.swift' -print -quit)
test -n "$model" && test -n "$wrapper"
cp -R "$model" "$app/Resources/"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -D SCHEMAGAN_PARITY_HARNESS "$app_root/Tests/SchemaGANParity/main.swift" "$app_root/GeoSome/Features/CPTRecommendation/Models/CPTData.swift" "$app_root/GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift" "$app_root/GeoSome/Features/CPTRecommendation/Services/UTMCoordinateConverter.swift" "$app_root/GeoSome/Features/CPTRecommendation/Services/SchemaGANService.swift" "$wrapper" -o "$app/MacOS/Parity"
"$app/MacOS/Parity" "$fixture" "$work/swift.json"
cd "$research"
PYTHONPATH="$research" "$research/cpt/bin/python" "$app_root/Tests/SchemaGANParity/compare.py" "$fixture" "$work/swift.json"
