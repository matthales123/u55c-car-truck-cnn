#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/webapp_car_truck"
VENV_DIR="$APP_DIR/.venv"
WEB_PORT="${CAR_TRUCK_WEB_PORT:-9895}"

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install -r "$APP_DIR/requirements-web.txt" >/dev/null

exec env WEB_PORT="$WEB_PORT" python3 "$APP_DIR/server.py"
