#!/usr/bin/env python3
"""Run benchmark sweeps using the C++ host runtime."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Dict, List


def read_env_file(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def shell_split_words(value: str) -> List[str]:
    return shlex.split(value) if value else []


def parse_args(defaults: Dict[str, str], root_dir: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="U55C benchmark sweep runner")
    parser.add_argument("--mode", choices=["dry-run", "hw"], default=defaults.get("U55C_SWEEP_MODE", "dry-run"))
    parser.add_argument(
        "--sizes",
        nargs="+",
        type=int,
        default=[int(x) for x in shell_split_words(defaults.get("U55C_SWEEP_SIZES", "65536 262144 1048576"))],
        help="Element counts to benchmark",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=int(defaults.get("U55C_SWEEP_ITERATIONS", defaults.get("U55C_DEFAULT_ITERATIONS", "10"))),
    )
    parser.add_argument("--kernel", default=defaults.get("U55C_KERNEL_NAME", "vector_add"))
    parser.add_argument("--device", type=int, default=int(defaults.get("U55C_DEVICE_INDEX", "0")))
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument(
        "--timeout-sec",
        type=int,
        default=int(defaults.get("U55C_CMD_TIMEOUT_SEC", "600")),
        help="Per benchmark invocation timeout in seconds (0 disables timeout)",
    )
    parser.add_argument("--xclbin", default=defaults.get("U55C_XCLBIN", ""))
    parser.add_argument(
        "--csv",
        default=str(root_dir / "results" / "benchmark_latest.csv"),
        help="Output CSV path (append mode)",
    )
    parser.add_argument(
        "--build-host",
        action="store_true",
        default=True,
        help="Build host executable before running (default: on)",
    )
    parser.add_argument(
        "--no-build-host",
        dest="build_host",
        action="store_false",
        help="Skip host build step",
    )
    return parser.parse_args()


def main() -> int:
    root_dir = Path(__file__).resolve().parents[2]
    defaults = read_env_file(root_dir / "config" / "project.env")
    args = parse_args(defaults, root_dir)

    build_script = root_dir / "scripts" / "build_host.sh"
    bench_bin = root_dir / "build" / "host" / "u55c_bench"

    if args.build_host:
        subprocess.run([str(build_script)], cwd=root_dir, check=True)

    if not bench_bin.exists():
        raise FileNotFoundError(f"host binary not found: {bench_bin}")

    csv_path = Path(args.csv)
    if not csv_path.is_absolute():
        csv_path = root_dir / csv_path
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    if args.mode == "hw" and not args.xclbin:
        raise ValueError("hardware mode requires --xclbin or U55C_XCLBIN in config/project.env")

    for n in args.sizes:
        cmd = [
            str(bench_bin),
            "--mode",
            args.mode,
            "--kernel",
            args.kernel,
            "--device",
            str(args.device),
            "--elements",
            str(n),
            "--iterations",
            str(args.iterations),
            "--seed",
            str(args.seed),
            "--csv",
            str(csv_path),
        ]
        if args.mode == "hw":
            cmd.extend(["--xclbin", args.xclbin])

        print("RUN:", " ".join(shlex.quote(x) for x in cmd), flush=True)
        try:
            subprocess.run(
                cmd,
                cwd=root_dir,
                check=True,
                timeout=None if args.timeout_sec <= 0 else args.timeout_sec,
            )
        except subprocess.TimeoutExpired as exc:
            raise TimeoutError(
                f"benchmark timed out after {args.timeout_sec}s for elements={n}; "
                "consider lowering size/iterations or checking kernel/runtime health"
            ) from exc

    print(f"Wrote benchmark CSV: {csv_path}")
    print("To plot:", sys.executable, "host/python/plot_results.py --csv", csv_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
