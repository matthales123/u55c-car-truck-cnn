#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HLS_DIR="$ROOT_DIR/hardware/hls"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ -z "${VITIS_SETTINGS:-}" || ! -f "${VITIS_SETTINGS}" ]]; then
  echo "ERROR: set VITIS_SETTINGS in config/project.env (current: ${VITIS_SETTINGS:-unset})" >&2
  exit 1
fi

export PYTHONPATH="${PYTHONPATH:-}"
export MATLABPATH="${MATLABPATH:-}"
source "$VITIS_SETTINGS"

cd "$HLS_DIR"
if command -v vitis_hls >/dev/null 2>&1; then
  vitis_hls -f scripts/run_hls.tcl
elif command -v vitis-run >/dev/null 2>&1; then
  vitis-run --mode hls --tcl scripts/run_hls.tcl
else
  echo "ERROR: vitis_hls or vitis-run not found" >&2
  exit 1
fi
