#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/bootstrap_deps.sh" --check-only
"$ROOT_DIR/scripts/run_correctness.sh"

echo "Setup check PASS"
