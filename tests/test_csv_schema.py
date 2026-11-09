#!/usr/bin/env python3

from __future__ import annotations

import csv
import sys
from pathlib import Path


REQUIRED_COLUMNS = {
    "timestamp_utc",
    "mode",
    "kernel",
    "device",
    "elements",
    "iteration",
    "verify_ok",
    "h2d_ms",
    "kernel_ms",
    "d2h_ms",
    "total_ms",
    "throughput_gbps",
}


def main() -> int:
    if len(sys.argv) != 2:
      print("usage: test_csv_schema.py <csv_path>")
      return 2

    csv_path = Path(sys.argv[1])
    if not csv_path.exists():
        print(f"ERROR: CSV does not exist: {csv_path}")
        return 1

    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            print("ERROR: CSV has no header")
            return 1

        missing = REQUIRED_COLUMNS - set(reader.fieldnames)
        if missing:
            print(f"ERROR: CSV missing columns: {sorted(missing)}")
            return 1

        row_count = 0
        for row in reader:
            row_count += 1
            verify_ok = row.get("verify_ok", "")
            if verify_ok not in {"0", "1"}:
                print(f"ERROR: invalid verify_ok value '{verify_ok}'")
                return 1

        if row_count == 0:
            print("ERROR: CSV has header but no data rows")
            return 1

    print(f"CSV schema check PASS ({row_count} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
