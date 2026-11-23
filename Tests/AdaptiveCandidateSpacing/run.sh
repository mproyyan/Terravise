#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
input="${1:?Provide existing actual projects.json snapshot}"
output="${2:-/tmp/terravise-adaptive-spacing-results.json}"
TERRAVISE_RUNTIME_PROJECTS_FILE="$input" TERRAVISE_DIAG_ENTRY="$root/Tests/AdaptiveCandidateSpacing/main.swift" TERRAVISE_DIAG_OUTPUT="$output" bash "$root/Tests/CPTProductionReplay/run_runtime_diagnosis.sh"
