#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${HOME}/Documents/Vitis/hls_new_project.sh"
if [[ ! -x "$SCRIPT_PATH" ]]; then
  echo "ERROR: expected generator script not found/executable: $SCRIPT_PATH" >&2
  exit 1
fi

exec "$SCRIPT_PATH"
