#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${1:-$HOME/build/ece5775_car_truck_u55c_hls}"

mkdir -p "$WORKDIR"

rsync -a --delete \
  "$SCRIPT_DIR/mlp.cpp" \
  "$SCRIPT_DIR/mlp.h" \
  "$SCRIPT_DIR/layer.cpp" \
  "$SCRIPT_DIR/layer.h" \
  "$SCRIPT_DIR/model.h" \
  "$SCRIPT_DIR/typedefs.h" \
  "$SCRIPT_DIR/mlp_u55c_kernel.cpp" \
  "$SCRIPT_DIR/mlp_u55c_tb.cpp" \
  "$SCRIPT_DIR/run_u55c_hls.tcl" \
  "$SCRIPT_DIR/data2" \
  "$SCRIPT_DIR/test_data2" \
  "$WORKDIR/"

set +u
source /tools/Xilinx/2025.1/Vitis/settings64.sh
set -u

pushd "$WORKDIR" >/dev/null
vitis-run --mode hls --tcl run_u55c_hls.tcl
popd >/dev/null

echo "HLS run finished in: $WORKDIR"
