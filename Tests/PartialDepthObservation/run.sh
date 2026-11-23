#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d /tmp/terravise-partial-depth-tests.XXXXXX)"
input="${1:-$work/empty-projects.json}"
output="${2:-$work/results.json}"
if [[ $# -eq 0 ]]; then printf '[]' > "$input"; fi
TERRAVISE_RUNTIME_PROJECTS_FILE="$input" TERRAVISE_DIAG_ENTRY="$root/Tests/PartialDepthObservation/main.swift" TERRAVISE_DIAG_OUTPUT="$output" bash "$root/Tests/CPTProductionReplay/run_runtime_diagnosis.sh"
printf 'Partial-depth regression results: %s\n' "$output"
