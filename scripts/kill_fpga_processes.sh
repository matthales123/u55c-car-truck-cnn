#!/usr/bin/env bash
set -euo pipefail

YES=false
SIGKILL=false

usage() {
  cat <<USAGE
Usage: $0 [--yes] [--force]

Stops leftover FPGA tool processes from prior builds/runs.
  --yes    actually terminate (without this flag, script only prints matches)
  --force  after graceful TERM, send KILL to remaining matches
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      YES=true
      shift
      ;;
    --force)
      SIGKILL=true
      shift
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

PATTERN='vivado|vitis|v\+\+|vpl|system_link|xelab|xsim|xsc'

matches() {
  ps -ef | rg -n "$PATTERN" | rg -v "rg -n" || true
}

echo "[kill_fpga_processes] matches:"
matches

if ! $YES; then
  echo "[kill_fpga_processes] dry-run only. Re-run with --yes to terminate." 
  exit 0
fi

pkill -f -e -15 "$PATTERN" || true
sleep 1

echo "[kill_fpga_processes] remaining after TERM:"
matches

if $SIGKILL; then
  pkill -f -e -9 "$PATTERN" || true
  sleep 1
  echo "[kill_fpga_processes] remaining after KILL:"
  matches
fi
