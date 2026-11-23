#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d /tmp/terravise-coordinator.XXXXXX)"
trap 'rm -rf "$work"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -D CPT_COORDINATOR_TEST -parse-as-library "$root/Tests/SufficiencyCoordinator/main.swift" "$root/GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyHistory.swift" "$root/GeoSome/Features/CPTRecommendation/Services/CPTSufficiencyDispatch.swift" -o "$work/test"
"$work/test"
