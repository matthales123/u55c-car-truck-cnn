#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

CSV_PATH="$ROOT_DIR/results/benchmark_latest.csv"

"$PYTHON_BIN" "$ROOT_DIR/host/python/run_benchmark.py" \
  --mode "${U55C_SWEEP_MODE:-dry-run}" \
  --sizes ${U55C_SWEEP_SIZES:-"65536 262144 1048576 4194304"} \
  --iterations "${U55C_SWEEP_ITERATIONS:-10}" \
  --timeout-sec "${U55C_CMD_TIMEOUT_SEC:-600}" \
  --kernel "${U55C_KERNEL_NAME:-vector_add}" \
  --device "${U55C_DEVICE_INDEX:-0}" \
  --xclbin "${U55C_XCLBIN:-}" \
  --csv "$CSV_PATH"

if "$PYTHON_BIN" -c "import matplotlib.pyplot" >/dev/null 2>&1; then
  "$PYTHON_BIN" "$ROOT_DIR/host/python/plot_results.py" \
    --csv "$CSV_PATH" \
    --out "$ROOT_DIR/results/benchmark_latest.png"
else
  echo "WARNING: matplotlib is not installed; skipping plot generation." >&2
  echo "Install with: $PYTHON_BIN -m pip install -r $ROOT_DIR/host/python/requirements.txt" >&2
fi
