#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="$ROOT_DIR/host/python/requirements.txt"

AUTO_INSTALL=true
SETUP_PYTHON=true
RUN_SMOKE=true
CHECK_ONLY=false

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --check-only      Check dependencies only (no installs)
  --no-auto-install Do not install missing system packages
  --no-python       Skip Python virtualenv and pip install
  --skip-smoke      Skip dry-run correctness smoke test
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=true
      AUTO_INSTALL=false
      SETUP_PYTHON=false
      RUN_SMOKE=false
      shift
      ;;
    --no-auto-install)
      AUTO_INSTALL=false
      shift
      ;;
    --no-python)
      SETUP_PYTHON=false
      shift
      ;;
    --skip-smoke)
      RUN_SMOKE=false
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

log() {
  echo "[bootstrap] $*"
}

warn() {
  echo "[bootstrap] WARNING: $*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

has_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$ROOT_DIR/.venv/bin/$tool" ]]; then
    return 0
  fi
  return 1
}

load_project_env() {
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/config/project.env"
  set +a
}

install_xilinx_user_wrappers() {
  load_project_env

  local vivado_settings="${VIVADO_SETTINGS:-}"
  local vitis_settings="${VITIS_SETTINGS:-}"
  local vivado_root=""
  local vitis_root=""
  local vivado_lmutil_dir=""
  local vivado_lmutil=""
  local user_bin="$HOME/.local/bin"

  if [[ -n "$vivado_settings" && -f "$vivado_settings" ]]; then
    vivado_root="$(cd "$(dirname "$vivado_settings")" && pwd)"
    vivado_lmutil_dir="$vivado_root/bin/unwrapped/lnx64.o"
    vivado_lmutil="$vivado_lmutil_dir/lmutil"
  fi
  if [[ -n "$vitis_settings" && -f "$vitis_settings" ]]; then
    vitis_root="$(cd "$(dirname "$vitis_settings")" && pwd)"
  fi

  mkdir -p "$user_bin"

  if [[ -x "$vivado_lmutil" ]]; then
    cat > "$user_bin/lmutil" <<EOF
#!/usr/bin/env bash
exec "$vivado_lmutil" "\$@"
EOF
    chmod +x "$user_bin/lmutil"
    log "Installed lmutil wrapper: $user_bin/lmutil -> $vivado_lmutil"
  else
    warn "Vivado lmutil not found; skipped lmutil wrapper install"
  fi

  if [[ -n "$vivado_root" && -x "$vivado_root/bin/vivado" && -f "$vivado_settings" ]]; then
    cat > "$user_bin/vivado" <<EOF
#!/usr/bin/env bash
unset LM_LICENSE_FILE MGLS_LICENSE_FILE QUARTUS_LM_LICENSE_FILE
unset XILINXD_LICENSE_FILE XILINX_LICENSE_FILE
source "$vivado_settings"
export PATH="$vivado_lmutil_dir:\$PATH"
exec "$vivado_root/bin/vivado" "\$@"
EOF
    chmod +x "$user_bin/vivado"
    log "Installed Vivado wrapper: $user_bin/vivado"
  else
    warn "Vivado settings/tool not found; skipped Vivado wrapper install"
  fi

  if [[ -n "$vivado_root" && -x "$vivado_root/bin/vlm" && -f "$vivado_settings" ]]; then
    cat > "$user_bin/vlm" <<EOF
#!/usr/bin/env bash
unset LM_LICENSE_FILE MGLS_LICENSE_FILE QUARTUS_LM_LICENSE_FILE
unset XILINXD_LICENSE_FILE XILINX_LICENSE_FILE
source "$vivado_settings"
export PATH="$vivado_lmutil_dir:\$PATH"
exec "$vivado_root/bin/vlm" "\$@"
EOF
    chmod +x "$user_bin/vlm"
    log "Installed Vivado License Manager wrapper: $user_bin/vlm"
  fi

  if [[ -n "$vitis_root" && -x "$vitis_root/ide/electron-app/lnx64/vitis-ide" && -f "$vitis_settings" ]]; then
    cat > "$user_bin/vitis" <<EOF
#!/usr/bin/env bash
unset LM_LICENSE_FILE MGLS_LICENSE_FILE QUARTUS_LM_LICENSE_FILE
unset XILINXD_LICENSE_FILE XILINX_LICENSE_FILE
source "$vitis_settings"
export PATH="$vivado_lmutil_dir:\$PATH"
exec "$vitis_root/ide/electron-app/lnx64/vitis-ide" "\$@"
EOF
    chmod +x "$user_bin/vitis"
    log "Installed Vitis wrapper: $user_bin/vitis"
  else
    warn "Vitis settings/tool not found; skipped Vitis wrapper install"
  fi
}

has_tool_in_settings() {
  local settings_path="$1"
  local tool="$2"
  if [[ ! -f "$settings_path" ]]; then
    return 1
  fi

  bash -c '
    set -euo pipefail
    export PYTHONPATH="${PYTHONPATH:-}"
    export MATLABPATH="${MATLABPATH:-}"
    source "$1" >/dev/null 2>&1
    command -v "$2" >/dev/null 2>&1
  ' _ "$settings_path" "$tool"
}

platform_xpfm_exists() {
  local platform_name="$1"
  local -a repos=()
  local -a from_env=()
  local repo_paths_raw="${PLATFORM_REPO_PATHS:-}"

  repos+=("/opt/xilinx/platforms")
  if [[ -n "$repo_paths_raw" ]]; then
    IFS=':' read -r -a from_env <<< "$repo_paths_raw"
    repos+=("${from_env[@]}")
  fi

  for repo in "${repos[@]}"; do
    [[ -n "$repo" ]] || continue
    [[ -d "$repo" ]] || continue
    if [[ -f "$repo/$platform_name/$platform_name.xpfm" || -f "$repo/$platform_name.xpfm" ]]; then
      return 0
    fi
  done

  return 1
}

platform_available() {
  local platform_name="$1"
  if [[ -z "$platform_name" ]]; then
    return 1
  fi

  if has_cmd platforminfo; then
    platforminfo --list 2>/dev/null | grep -F "\"baseName\": \"$platform_name\"" >/dev/null 2>&1
    return $?
  fi

  if [[ -n "${VITIS_SETTINGS:-}" && -f "${VITIS_SETTINGS}" ]]; then
    if bash -c '
      set -euo pipefail
      export PYTHONPATH="${PYTHONPATH:-}"
      export MATLABPATH="${MATLABPATH:-}"
      source "$1" >/dev/null 2>&1
      platforminfo --list 2>/dev/null
    ' _ "$VITIS_SETTINGS" | grep -F "\"baseName\": \"$platform_name\"" >/dev/null 2>&1; then
      return 0
    fi
  fi

  platform_xpfm_exists "$platform_name"
  return $?
}

install_system_packages() {
  local -a pkgs=(build-essential cmake make python3 python3-pip python3-venv)

  if ! has_cmd apt-get; then
    warn "apt-get not found; cannot auto-install system packages on this OS."
    return 1
  fi

  local -a prefix=()
  if [[ "$(id -u)" -ne 0 ]]; then
    if has_cmd sudo; then
      prefix=(sudo)
    else
      warn "sudo not available and not running as root; cannot install system packages."
      return 1
    fi
  fi

  log "Installing system packages: ${pkgs[*]}"
  "${prefix[@]}" apt-get update
  "${prefix[@]}" apt-get install -y "${pkgs[@]}"
}

check_required_commands() {
  local -a required=(bash make g++ python3 cmake)
  local -a recommended=()
  local -a missing_required=()
  local -a missing_recommended=()

  for cmd in "${required[@]}"; do
    if ! has_tool "$cmd"; then
      missing_required+=("$cmd")
    fi
  done

  if [[ ${#missing_required[@]} -gt 0 ]]; then
    warn "Missing required commands: ${missing_required[*]}"
    return 1
  fi

  for cmd in "${recommended[@]}"; do
    if ! has_tool "$cmd"; then
      missing_recommended+=("$cmd")
    fi
  done

  if [[ ${#missing_recommended[@]} -gt 0 ]]; then
    warn "Missing recommended commands: ${missing_recommended[*]}"
  fi

  return 0
}

check_toolchain_hints() {
  load_project_env

  if [[ -n "${VITIS_SETTINGS:-}" && -f "${VITIS_SETTINGS}" ]]; then
    log "Found Vitis settings: ${VITIS_SETTINGS}"
  else
    warn "Vitis settings not found at VITIS_SETTINGS=${VITIS_SETTINGS:-unset}"
  fi

  if [[ -n "${VIVADO_SETTINGS:-}" && -f "${VIVADO_SETTINGS}" ]]; then
    log "Found Vivado settings: ${VIVADO_SETTINGS}"
  else
    warn "Vivado settings not found at VIVADO_SETTINGS=${VIVADO_SETTINGS:-unset}"
  fi

  if has_cmd v++; then
    log "Found v++ in PATH"
  elif [[ -n "${VITIS_SETTINGS:-}" ]] && has_tool_in_settings "${VITIS_SETTINGS}" v++; then
    log "Found v++ via VITIS_SETTINGS"
  else
    warn "v++ not found in PATH (needed for xo/xclbin build)"
  fi

  if has_cmd vitis_hls || has_cmd vitis-run; then
    log "Found Vitis HLS command in PATH"
  elif [[ -n "${VITIS_SETTINGS:-}" ]] && (has_tool_in_settings "${VITIS_SETTINGS}" vitis_hls || has_tool_in_settings "${VITIS_SETTINGS}" vitis-run); then
    log "Found Vitis HLS command via VITIS_SETTINGS"
  else
    warn "vitis_hls/vitis-run not found in PATH"
  fi

  if has_cmd vivado; then
    log "Found vivado in PATH"
  elif [[ -n "${VIVADO_SETTINGS:-}" ]] && has_tool_in_settings "${VIVADO_SETTINGS}" vivado; then
    log "Found vivado via VIVADO_SETTINGS"
  else
    warn "vivado not found in PATH"
  fi

  if has_cmd lmutil; then
    local lmutil_path
    lmutil_path="$(command -v lmutil)"
    case "$lmutil_path" in
      "$HOME/.local/bin/lmutil"|*/Xilinx/*/lmutil)
        log "Found Xilinx lmutil in PATH: $lmutil_path"
        ;;
      *)
        warn "lmutil resolves to non-Xilinx binary: $lmutil_path"
        warn "Vivado License Manager diagnostics can fail in this state."
        ;;
    esac
  else
    warn "lmutil not found in PATH"
  fi

  if platform_available "${U55C_PLATFORM:-}"; then
    log "Found configured platform: ${U55C_PLATFORM}"
  else
    warn "Configured U55C platform not found in platform repos: ${U55C_PLATFORM:-unset}"
  fi

  local board_repo_raw="${U55C_BOARD_REPO_PATHS:-/opt/xilinx/board_files/u55c:$HOME/xilinx_board_files/u55c}"
  local -a board_repo_candidates=()
  local -a board_repo_found=()
  IFS=':' read -r -a board_repo_candidates <<< "$board_repo_raw"
  for repo in "${board_repo_candidates[@]}"; do
    [[ -n "$repo" ]] || continue
    if [[ -d "$repo" ]]; then
      board_repo_found+=("$repo")
    fi
  done
  if [[ ${#board_repo_found[@]} -gt 0 ]]; then
    log "Found board repo path(s): ${board_repo_found[*]}"
  else
    warn "No configured board repo directories found (checked: $board_repo_raw)"
  fi
}

setup_python_venv() {
  if ! has_cmd python3; then
    warn "python3 not found; cannot create virtualenv"
    return 1
  fi

  if [[ ! -d "$ROOT_DIR/.venv" ]]; then
    log "Creating Python virtualenv at $ROOT_DIR/.venv"
    python3 -m venv "$ROOT_DIR/.venv"
  fi

  local py_bin="$ROOT_DIR/.venv/bin/python"
  if [[ ! -x "$py_bin" ]]; then
    warn "virtualenv python not found at $py_bin"
    return 1
  fi

  log "Installing Python dependencies from $REQ_FILE"
  "$py_bin" -m pip install --upgrade pip
  "$py_bin" -m pip install -r "$REQ_FILE"

  if ! has_tool cmake; then
    log "Installing local cmake into virtualenv"
    "$py_bin" -m pip install cmake
  fi
}

run_checks_only() {
  log "Running dependency checks (check-only mode)"
  if ! check_required_commands; then
    return 1
  fi
  check_toolchain_hints
  log "Dependency checks completed"
}

if $CHECK_ONLY; then
  run_checks_only
  exit 0
fi

if ! check_required_commands; then
  if $AUTO_INSTALL; then
    if ! install_system_packages; then
      warn "System package install failed; trying local Python-based fallback."
    fi
  else
    warn "Auto-install is disabled and required commands are missing."
    exit 1
  fi
fi

if $SETUP_PYTHON; then
  setup_python_venv
fi

install_xilinx_user_wrappers
check_required_commands
check_toolchain_hints

if $RUN_SMOKE; then
  log "Running dry-run smoke test"
  "$ROOT_DIR/scripts/run_correctness.sh"
fi

log "Bootstrap complete"
