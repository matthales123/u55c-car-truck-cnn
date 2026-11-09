#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

IMG_ELEMS = 3072
REC_BYTES = 3073

AUTO_LABEL = 1
TRUCK_LABEL = 9

MEAN = [0.4914, 0.4822, 0.4465]
STD = [0.2023, 0.1994, 0.2010]


def normalize_record(raw: bytes) -> list[float]:
    assert len(raw) == IMG_ELEMS
    out = [0.0] * IMG_ELEMS
    for c in range(3):
        m = MEAN[c]
        s = STD[c]
        offset = c * 1024
        for i in range(1024):
            out[offset + i] = ((raw[offset + i] / 255.0) - m) / s
    return out


def iter_cifar_records(bin_path: Path):
    payload = bin_path.read_bytes()
    if len(payload) % REC_BYTES != 0:
        raise ValueError(f"Invalid CIFAR binary length for {bin_path}: {len(payload)}")

    count = len(payload) // REC_BYTES
    for idx in range(count):
        start = idx * REC_BYTES
        rec = payload[start : start + REC_BYTES]
        label = rec[0]
        pixels = rec[1:]
        yield label, pixels


def main() -> int:
    ap = argparse.ArgumentParser(description="Prepare car/truck CSV dataset from CIFAR-10 test batch")
    ap.add_argument("--cifar-bin", required=True, help="Path to cifar-10-batches-bin/test_batch.bin")
    ap.add_argument("--out-data", required=True, help="Output CSV for test_data.dat")
    ap.add_argument("--out-labels", required=True, help="Output CSV for test_labels.csv")
    ap.add_argument("--samples", type=int, default=100, help="Max number of car/truck samples to export")
    args = ap.parse_args()

    cifar_bin = Path(args.cifar_bin).resolve()
    out_data = Path(args.out_data).resolve()
    out_labels = Path(args.out_labels).resolve()
    out_data.parent.mkdir(parents=True, exist_ok=True)
    out_labels.parent.mkdir(parents=True, exist_ok=True)

    selected_data: list[list[float]] = []
    selected_labels: list[int] = []

    for label, pixels in iter_cifar_records(cifar_bin):
        if label not in (AUTO_LABEL, TRUCK_LABEL):
            continue
        mapped = 0 if label == AUTO_LABEL else 1
        selected_data.append(normalize_record(pixels))
        selected_labels.append(mapped)
        if len(selected_data) >= args.samples:
            break

    if not selected_data:
        raise RuntimeError("No car/truck samples found in CIFAR input")

    with out_data.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(selected_data)

    with out_labels.open("w", newline="") as f:
        writer = csv.writer(f)
        for v in selected_labels:
            writer.writerow([float(v)])

    meta = {
        "source": str(cifar_bin),
        "samples": len(selected_data),
        "class_map": {"automobile": 0, "truck": 1},
        "normalization": {"mean": MEAN, "std": STD},
    }
    meta_path = out_labels.parent / "dataset_meta.json"
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    print(f"Wrote {len(selected_data)} samples")
    print(f"data   : {out_data}")
    print(f"labels : {out_labels}")
    print(f"meta   : {meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
