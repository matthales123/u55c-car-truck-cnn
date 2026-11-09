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

# Avoid known XSim instability from host-side C compiler env pollution.
unset LIBRARY_PATH || true
unset C_INCLUDE_PATH || true
unset CPLUS_INCLUDE_PATH || true
unset CPATH || true

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
export U55C_XSIM_MT_LEVEL="${U55C_XSIM_MT_LEVEL:-off}"
export U55C_XSIM_INCREMENTAL="${U55C_XSIM_INCREMENTAL:-0}"
export U55C_XSIM_ELAB_DEBUG_LEVEL="${U55C_XSIM_ELAB_DEBUG_LEVEL:-off}"
export U55C_XSIM_ELAB_RELAX="${U55C_XSIM_ELAB_RELAX:-1}"
export U55C_XSIM_FORCE_NO_GLBL="${U55C_XSIM_FORCE_NO_GLBL:-0}"
export U55C_XELAB_MORE_OPTIONS="${U55C_XELAB_MORE_OPTIONS:---O0 --nosignalhandlers}"

cd "$RTL_DIR"
env -u LIBRARY_PATH \
    -u C_INCLUDE_PATH \
    -u CPLUS_INCLUDE_PATH \
    -u CPATH \
    vivado -mode batch -source scripts/sim.tcl
