#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
# shellcheck source=/dev/null
source "$ROOT_DIR/config/project.env"
set +a

usage() {
  cat <<USAGE
Usage: $0 [--target hw|hw_emu|sw_emu] [--kernel NAME] [--platform XPFM]

Builds an HLS xclbin using non-conflicting v++ job flags.
Job controls are read from config/project.env:
  U55C_HLS_JOBS
  U55C_VIVADO_SYNTH_JOBS
  U55C_VIVADO_IMPL_JOBS
(0 = auto)
USAGE
}

TARGET="${TARGET:-hw}"
KERNEL_NAME="${U55C_KERNEL_NAME:-vector_add}"
PLATFORM="${U55C_PLATFORM:-xilinx_u55c_gen3x16_xdma_3_202210_1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --kernel)
      KERNEL_NAME="${2:-}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

resolve_jobs() {
  local raw="$1"
  local auto
  auto="$(nproc)"
  if [[ "$auto" -gt 44 ]]; then
    auto=44
  fi
  if [[ -z "$raw" || "$raw" == "0" ]]; then
    echo "$auto"
  else
    echo "$raw"
  fi
}

HLS_JOBS="$(resolve_jobs "${U55C_HLS_JOBS:-0}")"
VIVADO_SYNTH_JOBS="$(resolve_jobs "${U55C_VIVADO_SYNTH_JOBS:-0}")"
VIVADO_IMPL_JOBS="$(resolve_jobs "${U55C_VIVADO_IMPL_JOBS:-0}")"

echo "[build_hls_xclbin] target=$TARGET kernel=$KERNEL_NAME platform=$PLATFORM"
echo "[build_hls_xclbin] hls_jobs=$HLS_JOBS synth_jobs=$VIVADO_SYNTH_JOBS impl_jobs=$VIVADO_IMPL_JOBS"

make -C "$ROOT_DIR/hardware/hls" \
  xclbin \
  TARGET="$TARGET" \
  KERNEL_NAME="$KERNEL_NAME" \
  PLATFORM="$PLATFORM" \
  HLS_JOBS="$HLS_JOBS" \
  VIVADO_SYNTH_JOBS="$VIVADO_SYNTH_JOBS" \
  VIVADO_IMPL_JOBS="$VIVADO_IMPL_JOBS"
