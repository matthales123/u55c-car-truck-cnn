#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/host"
PREFERRED_CMAKE="$ROOT_DIR/.venv/bin/cmake"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ -x "$PREFERRED_CMAKE" ]]; then
  "$PREFERRED_CMAKE" -S "$ROOT_DIR/host/cpp" -B "$BUILD_DIR" \
    -DU55C_ENABLE_XRT="${U55C_ENABLE_XRT:-ON}" \
    -DU55C_ENABLE_CPU_REF="${U55C_ENABLE_CPU_REF:-ON}"
  "$PREFERRED_CMAKE" --build "$BUILD_DIR" -j"$(nproc)"
elif command -v cmake >/dev/null 2>&1; then
  cmake -S "$ROOT_DIR/host/cpp" -B "$BUILD_DIR" \
    -DU55C_ENABLE_XRT="${U55C_ENABLE_XRT:-ON}" \
    -DU55C_ENABLE_CPU_REF="${U55C_ENABLE_CPU_REF:-ON}"
  cmake --build "$BUILD_DIR" -j"$(nproc)"
elif command -v g++ >/dev/null 2>&1; then
  echo "WARNING: cmake not found. Falling back to direct g++ build (dry-run only)." >&2
  mkdir -p "$BUILD_DIR"
  g++ -std=c++17 -O2 -Wall -Wextra -Wpedantic \
    -I"$ROOT_DIR/host/cpp/include" \
    "$ROOT_DIR/host/cpp/src/main.cpp" \
    "$ROOT_DIR/host/cpp/src/runner.cpp" \
    "$ROOT_DIR/host/cpp/src/csv_logger.cpp" \
    "$ROOT_DIR/host/cpp/src/buffer_manager.cpp" \
    -o "$BUILD_DIR/u55c_bench"
else
  echo "ERROR: neither cmake nor g++ is available in PATH" >&2
  exit 1
fi
