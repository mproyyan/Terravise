#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
research="${SCHEMAGAN_RESEARCH_ROOT:-$HOME/Developer/cpt_super_learn}"
work="$(mktemp -d /tmp/terravise-v32-parity.XXXXXX)"
trap 'rm -rf "$work"' EXIT
source="$root/GeoSome/Features/CPTRecommendation/Services/UncertaintySufficiencyService.swift"
feature="$root/GeoSome/Features/CPTRecommendation/Resources/SufficiencyV32FeatureParity.json"
inputs="$root/Tests/PipelineParity/V32/classifier_inputs.json"
model="$root/GeoSome/Features/CPTRecommendation/Resources/SufficiencyV3_2.json"
# DEBUG is scoped to this standalone test compiler invocation; it does not change app configuration.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -D DEBUG -parse-as-library "$root/Tests/PipelineParity/V32/main.swift" "$source" -o "$work/parity"
"$work/parity" "$feature" "$inputs" "$model" "$work/swift.json"
cd "$research"
"$research/cpt/bin/python" "$root/Tests/PipelineParity/V32/compare.py" "$feature" "$inputs" "$work/swift.json"
