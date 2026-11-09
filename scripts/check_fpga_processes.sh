#!/usr/bin/env bash
set -euo pipefail

PATTERN='vivado|vitis|v\+\+|vpl|system_link|xelab|xsim|xsc'

echo "[check_fpga_processes] active FPGA tool processes matching: $PATTERN"
ps -ef | rg -n "$PATTERN" | rg -v "rg -n" || true
