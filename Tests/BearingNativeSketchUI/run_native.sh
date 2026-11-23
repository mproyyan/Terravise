#!/bin/bash
set -euo pipefail
# Bearing now uses the shared ResultAnalysis presentation; verify that actual path.
exec "$(cd "$(dirname "$0")/.." && pwd)/BearingSubsurfaceSheetReuse/run_native.sh"
