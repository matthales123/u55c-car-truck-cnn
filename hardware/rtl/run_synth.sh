#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_DIR="$ROOT_DIR/hardware/rtl"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ -z "${VIVADO_SETTINGS:-}" || ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "ERROR: set VIVADO_SETTINGS in config/project.env (current: ${VIVADO_SETTINGS:-unset})" >&2
  exit 1
fi

export PYTHONPATH="${PYTHONPATH:-}"
export MATLABPATH="${MATLABPATH:-}"
source "$VIVADO_SETTINGS"

build_board_repo_paths() {
  local raw="${U55C_BOARD_REPO_PATHS:-}"
  if [[ -z "$raw" ]]; then
    raw="/opt/xilinx/board_files/u55c:$HOME/xilinx_board_files/u55c"
  fi

  local -a candidates=()
  local -a existing=()
  IFS=':' read -r -a candidates <<< "$raw"
  for repo in "${candidates[@]}"; do
    [[ -n "$repo" ]] || continue
    if [[ -d "$repo" ]]; then
      existing+=("$repo")
    fi
  done

  if [[ ${#existing[@]} -gt 0 ]]; then
    local joined=""
    for repo in "${existing[@]}"; do
      if [[ -z "$joined" ]]; then
        joined="$repo"
      else
        joined="${joined}:$repo"
      fi
    done
    printf '%s\n' "$joined"
  fi
}

U55C_EFFECTIVE_BOARD_REPO_PATHS="$(build_board_repo_paths)"
export U55C_EFFECTIVE_BOARD_REPO_PATHS

cd "$RTL_DIR"
vivado -mode batch -source scripts/synth.tcl
