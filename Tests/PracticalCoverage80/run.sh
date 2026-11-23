#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d /tmp/terravise-practical80-parity.XXXXXX)"
"$HOME/Developer/cpt_super_learn/cpt/bin/python" "$root/Tests/PracticalCoverage80/prepare.py" "$work/fixtures.jsonl"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -O -parse-as-library "$root/Tests/PracticalCoverage80/main.swift" "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicStop.swift" "$root/GeoSome/Features/CPTRecommendation/Services/StratigraphicHistory.swift" -o "$work/parity"
"$work/parity" "$work/fixtures.jsonl" "$work/parity.json"
echo "Existing-state parity results: $work"
