#!/usr/bin/env python3
"""
Generate RTL static parameter assets from legacy ECE5775 model data.

Outputs:
  - hardware/rtl/include/cnn_static_params_legacy.svh
  - hardware/rtl/tb/data/cifar_test_q8_100.mem
  - hardware/rtl/tb/data/cifar_test_hls_pred_100.mem
  - hardware/rtl/tb/data/legacy_quant_report.json

Implemented calibration improvements:
  - Per-output-channel/per-neuron weight quantization (conv/fc)
  - Activation-scale calibration from dataset percentiles
  - Shift auto-sweep around calibrated initial shifts
  - Integer inference path matches RTL signed round-to-nearest right-shift
"""

from __future__ import annotations

import itertools
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view


@dataclass(frozen=True)
class Paths:
    project_root: Path
    weight_root: Path
    test_root: Path
    data2_dir: Path
    test_data_file: Path
    include_out: Path
    shift_include_out: Path
    q8_test_mem_out: Path
    hls_pred_mem_out: Path
    hls_float_pred_mem_out: Path
    report_out: Path


def load_csv_floats(path: Path, expected_count: int) -> np.ndarray:
    text = path.read_text(encoding="utf-8").replace("\n", " ").replace("\r", " ")
    vals = [float(tok) for tok in text.split(",") if tok.strip()]
    if len(vals) != expected_count:
        raise ValueError(f"{path} count mismatch: got {len(vals)} expected {expected_count}")
    return np.asarray(vals, dtype=np.float32)


def pool2(arr: np.ndarray) -> np.ndarray:
    # CHW -> C(H/2)(W/2)
    c, h, w = arr.shape
    return arr.reshape(c, h // 2, 2, w // 2, 2).max(axis=(2, 4))


def conv_float(inp: np.ndarray, weight: np.ndarray, bias: np.ndarray) -> np.ndarray:
    # inp: C,H,W ; weight: N,C,K,K
    win = sliding_window_view(inp, (weight.shape[2], weight.shape[3]), axis=(1, 2))
    out = np.einsum("nckl,cxykl->nxy", weight, win, optimize=True)
    out += bias[:, None, None]
    return out


def forward_float(
    sample: np.ndarray,
    conv1_w: np.ndarray,
    conv1_b: np.ndarray,
    conv2_w: np.ndarray,
    conv2_b: np.ndarray,
    fc1_w: np.ndarray,
    fc1_b: np.ndarray,
    fc2_w: np.ndarray,
    fc2_b: np.ndarray,
    fc3_w: np.ndarray,
    fc3_b: np.ndarray,
) -> dict:
    x = sample.reshape(3, 32, 32)
    c1 = np.maximum(conv_float(x, conv1_w, conv1_b), 0.0)
    p1 = pool2(c1)
    c2 = np.maximum(conv_float(p1, conv2_w, conv2_b), 0.0)
    p2 = pool2(c2)
    f1 = np.maximum(fc1_w @ p2.reshape(-1) + fc1_b, 0.0)
    f2 = np.maximum(fc2_w @ f1 + fc2_b, 0.0)
    f3 = fc3_w @ f2 + fc3_b
    return {
        "pred": int(f3[1] > f3[0]),
        "p1": p1,
        "p2": p2,
        "f1": f1,
        "f2": f2,
    }


def percentile_scale(vals: np.ndarray, percentile: float = 99.5) -> float:
    vmax = float(np.percentile(np.abs(vals), percentile))
    if vmax < 1e-9:
        return 1.0
    return 127.0 / vmax


def quantize_weights_per_output(weights: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    flat = weights.reshape(weights.shape[0], -1)
    max_abs = np.max(np.abs(flat), axis=1)
    scales = np.where(max_abs > 1e-9, 127.0 / max_abs, 1.0).astype(np.float64)
    reshape = (weights.shape[0],) + (1,) * (weights.ndim - 1)
    q = np.clip(np.round(weights * scales.reshape(reshape)), -128, 127).astype(np.int16)
    return q, scales


def quantize_bias_per_output(bias: np.ndarray, input_scale: float, weight_scales: np.ndarray) -> np.ndarray:
    return np.round(bias * input_scale * weight_scales).astype(np.int64)


def arshift_round_signed(x: np.ndarray, shift: int) -> np.ndarray:
    if shift <= 0:
        return x
    pos_off = 1 << (shift - 1)
    neg_off = pos_off - 1
    return np.where(x >= 0, (x + pos_off) >> shift, (x + neg_off) >> shift)


def conv_int(inp: np.ndarray, weight: np.ndarray, bias: np.ndarray, shift: int) -> np.ndarray:
    win = sliding_window_view(inp, (weight.shape[2], weight.shape[3]), axis=(1, 2)).astype(np.int32)
    out = np.einsum("nckl,cxykl->nxy", weight.astype(np.int32), win, optimize=True).astype(np.int64)
    out += bias[:, None, None]
    out = arshift_round_signed(out, shift)
    out = np.clip(out, 0, 127).astype(np.int16)
    return out


def dense_int(inp: np.ndarray, weight: np.ndarray, bias: np.ndarray, shift: int, relu: bool, final: bool) -> np.ndarray:
    out = (weight.astype(np.int32) @ inp.astype(np.int32)).astype(np.int64) + bias
    if final:
        return np.clip(out, -2147483648, 2147483647).astype(np.int64)
    out = arshift_round_signed(out, shift)
    if relu:
        out = np.maximum(out, 0)
    return np.clip(out, -128, 127).astype(np.int16)


def infer_int_q(sample_q: np.ndarray, q: dict, shifts: Sequence[int]) -> int:
    x = sample_q.reshape(3, 32, 32).astype(np.int16)
    c1 = conv_int(x, q["conv1_w"], q["conv1_b"], shifts[0])
    p1 = pool2(c1)
    c2 = conv_int(p1, q["conv2_w"], q["conv2_b"], shifts[1])
    p2 = pool2(c2)
    f1 = dense_int(p2.reshape(-1), q["fc1_w"], q["fc1_b"], shifts[2], relu=True, final=False)
    f2 = dense_int(f1, q["fc2_w"], q["fc2_b"], shifts[3], relu=True, final=False)
    f3 = dense_int(f2, q["fc3_w"], q["fc3_b"], 0, relu=False, final=True)
    return int(f3[1] > f3[0])


def estimate_shift(in_scale: float, med_w_scale: float, out_scale: float, lo: int, hi: int) -> int:
    ratio = (in_scale * med_w_scale) / max(out_scale, 1e-9)
    if ratio <= 1.0:
        return lo
    raw = int(round(math.log2(ratio)))
    return int(max(lo, min(hi, raw)))


def eval_match(
    shifts: Sequence[int],
    q: dict,
    q8_inputs: np.ndarray,
    hls_preds: np.ndarray,
    sample_indices: np.ndarray,
) -> float:
    preds = np.asarray([infer_int_q(q8_inputs[i], q, shifts) for i in sample_indices], dtype=np.int32)
    return float(np.mean(preds == hls_preds[sample_indices]))


def format_sv_int_array(vals: Iterable[int], width: int) -> str:
    vals = list(vals)
    chunks = []
    line: List[str] = []
    for idx, v in enumerate(vals):
        iv = int(v)
        if iv < 0:
            line.append(f"-{width}'sd{abs(iv)}")
        else:
            line.append(f"{width}'sd{iv}")
        if (idx + 1) % 16 == 0:
            chunks.append("  " + ", ".join(line))
            line = []
    if line:
        chunks.append("  " + ", ".join(line))
    return "{\n" + ",\n".join(chunks) + "\n}"


def write_sv_include(paths: Paths, q: dict, shifts: Sequence[int]) -> None:
    c1w = q["conv1_w"].reshape(-1).astype(np.int16)
    c2w = q["conv2_w"].reshape(-1).astype(np.int16)
    f1w = q["fc1_w"].reshape(-1).astype(np.int16)
    f2w = q["fc2_w"].reshape(-1).astype(np.int16)
    f3w = q["fc3_w"].reshape(-1).astype(np.int16)

    c1b = q["conv1_b"].astype(np.int64)
    c2b = q["conv2_b"].astype(np.int64)
    f1b = q["fc1_b"].astype(np.int64)
    f2b = q["fc2_b"].astype(np.int64)
    f3b = q["fc3_b"].astype(np.int64)

    text = f"""`ifndef CNN_STATIC_PARAMS_LEGACY_SVH
`define CNN_STATIC_PARAMS_LEGACY_SVH

localparam int LEGACY_SHIFT_CONV1 = {int(shifts[0])};
localparam int LEGACY_SHIFT_CONV2 = {int(shifts[1])};
localparam int LEGACY_SHIFT_FC1   = {int(shifts[2])};
localparam int LEGACY_SHIFT_FC2   = {int(shifts[3])};

localparam logic signed [DATA_W-1:0] LEGACY_CONV1_W [0:449] = {format_sv_int_array(c1w, 8)};
localparam logic signed [DATA_W-1:0] LEGACY_CONV2_W [0:2399] = {format_sv_int_array(c2w, 8)};
localparam logic signed [DATA_W-1:0] LEGACY_FC1_W   [0:47999] = {format_sv_int_array(f1w, 8)};
localparam logic signed [DATA_W-1:0] LEGACY_FC2_W   [0:10079] = {format_sv_int_array(f2w, 8)};
localparam logic signed [DATA_W-1:0] LEGACY_FC3_W   [0:167] = {format_sv_int_array(f3w, 8)};

localparam logic signed [ACC_W-1:0] LEGACY_CONV1_B [0:5] = {format_sv_int_array(c1b, 32)};
localparam logic signed [ACC_W-1:0] LEGACY_CONV2_B [0:15] = {format_sv_int_array(c2b, 32)};
localparam logic signed [ACC_W-1:0] LEGACY_FC1_B   [0:119] = {format_sv_int_array(f1b, 32)};
localparam logic signed [ACC_W-1:0] LEGACY_FC2_B   [0:83] = {format_sv_int_array(f2b, 32)};
localparam logic signed [ACC_W-1:0] LEGACY_FC3_B   [0:1] = {format_sv_int_array(f3b, 32)};

`endif
"""
    paths.include_out.parent.mkdir(parents=True, exist_ok=True)
    paths.include_out.write_text(text, encoding="utf-8")


def write_shift_include(paths: Paths, shifts: Sequence[int]) -> None:
    text = f"""`ifndef CNN_STATIC_LEGACY_SHIFTS_SVH
`define CNN_STATIC_LEGACY_SHIFTS_SVH

localparam int LEGACY_TB_SHIFT_CONV1 = {int(shifts[0])};
localparam int LEGACY_TB_SHIFT_CONV2 = {int(shifts[1])};
localparam int LEGACY_TB_SHIFT_FC1   = {int(shifts[2])};
localparam int LEGACY_TB_SHIFT_FC2   = {int(shifts[3])};

`endif
"""
    paths.shift_include_out.parent.mkdir(parents=True, exist_ok=True)
    paths.shift_include_out.write_text(text, encoding="utf-8")


def write_mem_files(
    paths: Paths,
    q8_inputs: np.ndarray,
    expected_preds: np.ndarray,
    hls_float_preds: np.ndarray | None = None,
) -> None:
    paths.q8_test_mem_out.parent.mkdir(parents=True, exist_ok=True)
    with paths.q8_test_mem_out.open("w", encoding="utf-8") as f:
        flat = q8_inputs.reshape(-1).astype(np.int16)
        for v in flat:
            f.write(f"{int(v) & 0xFF:02x}\n")

    with paths.hls_pred_mem_out.open("w", encoding="utf-8") as f:
        for p in expected_preds.astype(np.uint32).tolist():
            f.write(f"{int(p)}\n")

    if hls_float_preds is not None:
        with paths.hls_float_pred_mem_out.open("w", encoding="utf-8") as f:
            for p in hls_float_preds.astype(np.uint32).tolist():
                f.write(f"{int(p)}\n")


def testset_score(root: Path) -> int:
    data_path = root / "test_data2" / "test_data.dat"
    label_path = root / "test_data2" / "test_labels.csv"
    meta_path = root / "test_data2" / "dataset_meta.json"
    score = 0

    if data_path.is_file() and label_path.is_file():
        score += 2
    else:
        return score

    try:
        data_lines = [ln for ln in data_path.read_text(encoding="utf-8").strip().splitlines() if ln.strip()]
        if len(data_lines) >= 100:
            score += 1
        first_cols = len([x for x in data_lines[0].split(",") if x.strip()])
        if first_cols == 3072:
            score += 1
    except Exception:
        return score

    try:
        labels = [float(x.strip()) for x in label_path.read_text(encoding="utf-8").strip().splitlines() if x.strip()]
        unique = set(labels)
        if len(unique) > 1:
            score += 3
        elif len(unique) == 1:
            score -= 2
    except Exception:
        return score

    if meta_path.is_file():
        score += 2
    return score


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    legacy_candidates = [
        project_root / "legacy_src" / "ece5775_final_proj" / "car_truck_accel" / "ecelinux",
    ]
    existing = [p for p in legacy_candidates if p.is_dir()]
    if not existing:
        raise FileNotFoundError(
            "Could not find legacy ecelinux directory. Checked:\n  - "
            + "\n  - ".join(str(p) for p in legacy_candidates)
        )

    weight_root = next((p for p in existing if (p / "data2").is_dir()), existing[0])
    weight_override = os.environ.get("U55C_LEGACY_WEIGHT_ROOT", "").strip()
    if weight_override:
        candidate = Path(weight_override)
        if not (candidate / "data2").is_dir():
            raise FileNotFoundError(f"U55C_LEGACY_WEIGHT_ROOT missing data2/: {candidate}")
        weight_root = candidate

    scored = sorted(((testset_score(p), p) for p in existing), key=lambda x: x[0], reverse=True)
    test_root = scored[0][1]
    test_override = os.environ.get("U55C_LEGACY_TEST_ROOT", "").strip()
    if test_override:
        candidate = Path(test_override)
        if not (candidate / "test_data2" / "test_data.dat").is_file():
            raise FileNotFoundError(f"U55C_LEGACY_TEST_ROOT missing test_data2/test_data.dat: {candidate}")
        test_root = candidate

    paths = Paths(
        project_root=project_root,
        weight_root=weight_root,
        test_root=test_root,
        data2_dir=weight_root / "data2",
        test_data_file=test_root / "test_data2" / "test_data.dat",
        include_out=project_root / "hardware" / "rtl" / "include" / "cnn_static_params_legacy.svh",
        shift_include_out=project_root / "hardware" / "rtl" / "include" / "cnn_static_legacy_shifts.svh",
        q8_test_mem_out=project_root / "hardware" / "rtl" / "tb" / "data" / "cifar_test_q8_100.mem",
        hls_pred_mem_out=project_root / "hardware" / "rtl" / "tb" / "data" / "cifar_test_hls_pred_100.mem",
        hls_float_pred_mem_out=project_root / "hardware" / "rtl" / "tb" / "data" / "cifar_test_hls_float_pred_100.mem",
        report_out=project_root / "hardware" / "rtl" / "tb" / "data" / "legacy_quant_report.json",
    )

    conv1_w = load_csv_floats(paths.data2_dir / "conv1_weight", 450).reshape(6, 3, 5, 5)
    conv1_b = load_csv_floats(paths.data2_dir / "conv1_bias", 6)
    conv2_w = load_csv_floats(paths.data2_dir / "conv2_weight", 2400).reshape(16, 6, 5, 5)
    conv2_b = load_csv_floats(paths.data2_dir / "conv2_bias", 16)
    fc1_w = load_csv_floats(paths.data2_dir / "fc1_weight", 48000).reshape(120, 400)
    fc1_b = load_csv_floats(paths.data2_dir / "fc1_bias", 120)
    fc2_w = load_csv_floats(paths.data2_dir / "fc2_weight", 10080).reshape(84, 120)
    fc2_b = load_csv_floats(paths.data2_dir / "fc2_bias", 84)
    fc3_w = load_csv_floats(paths.data2_dir / "fc3_weight", 168).reshape(2, 84)
    fc3_b = load_csv_floats(paths.data2_dir / "fc3_bias", 2)

    samples = np.asarray(
        [[float(x) for x in line.split(",")] for line in paths.test_data_file.read_text(encoding="utf-8").strip().splitlines()],
        dtype=np.float32,
    )
    num_samples = min(100, samples.shape[0])
    samples = samples[:num_samples]

    # Float reference predictions + activation statistics for scale calibration.
    hls_preds = []
    p1_vals: List[np.ndarray] = []
    p2_vals: List[np.ndarray] = []
    f1_vals: List[np.ndarray] = []
    f2_vals: List[np.ndarray] = []

    for s in samples:
        fwd = forward_float(s, conv1_w, conv1_b, conv2_w, conv2_b, fc1_w, fc1_b, fc2_w, fc2_b, fc3_w, fc3_b)
        hls_preds.append(fwd["pred"])
        p1_vals.append(fwd["p1"].reshape(-1))
        p2_vals.append(fwd["p2"].reshape(-1))
        f1_vals.append(fwd["f1"].reshape(-1))
        f2_vals.append(fwd["f2"].reshape(-1))

    hls_preds = np.asarray(hls_preds, dtype=np.int32)

    activation_scales = {
        "input": percentile_scale(samples.reshape(-1), percentile=99.9),
        "p1": percentile_scale(np.concatenate(p1_vals), percentile=99.5),
        "p2": percentile_scale(np.concatenate(p2_vals), percentile=99.5),
        "f1": percentile_scale(np.concatenate(f1_vals), percentile=99.5),
        "f2": percentile_scale(np.concatenate(f2_vals), percentile=99.5),
    }

    q_conv1_w, sw_conv1 = quantize_weights_per_output(conv1_w)
    q_conv2_w, sw_conv2 = quantize_weights_per_output(conv2_w)
    q_fc1_w, sw_fc1 = quantize_weights_per_output(fc1_w)
    q_fc2_w, sw_fc2 = quantize_weights_per_output(fc2_w)
    q_fc3_w, sw_fc3 = quantize_weights_per_output(fc3_w)

    q = {
        "input_scale": activation_scales["input"],
        "conv1_w": q_conv1_w,
        "conv2_w": q_conv2_w,
        "fc1_w": q_fc1_w,
        "fc2_w": q_fc2_w,
        "fc3_w": q_fc3_w,
        "conv1_b": quantize_bias_per_output(conv1_b, activation_scales["input"], sw_conv1),
        "conv2_b": quantize_bias_per_output(conv2_b, activation_scales["p1"], sw_conv2),
        "fc1_b": quantize_bias_per_output(fc1_b, activation_scales["p2"], sw_fc1),
        "fc2_b": quantize_bias_per_output(fc2_b, activation_scales["f1"], sw_fc2),
        "fc3_b": quantize_bias_per_output(fc3_b, activation_scales["f2"], sw_fc3),
    }

    min_shift = int(os.environ.get("U55C_SHIFT_MIN", "0"))
    max_shift = int(os.environ.get("U55C_SHIFT_MAX", "12"))
    sweep_radius = int(os.environ.get("U55C_SHIFT_SWEEP_RADIUS", "2"))
    sweep_samples = int(os.environ.get("U55C_SHIFT_SWEEP_SAMPLES", "40"))
    top_n = int(os.environ.get("U55C_SHIFT_SWEEP_TOPN", "12"))

    init_shifts = [
        estimate_shift(activation_scales["input"], float(np.median(sw_conv1)), activation_scales["p1"], min_shift, max_shift),
        estimate_shift(activation_scales["p1"], float(np.median(sw_conv2)), activation_scales["p2"], min_shift, max_shift),
        estimate_shift(activation_scales["p2"], float(np.median(sw_fc1)), activation_scales["f1"], min_shift, max_shift),
        estimate_shift(activation_scales["f1"], float(np.median(sw_fc2)), activation_scales["f2"], min_shift, max_shift),
    ]

    q8_inputs = np.clip(np.round(samples * activation_scales["input"]), -128, 127).astype(np.int16)

    def shift_range(center: int) -> List[int]:
        lo = max(min_shift, center - sweep_radius)
        hi = min(max_shift, center + sweep_radius)
        return list(range(lo, hi + 1))

    ranges = [shift_range(s) for s in init_shifts]
    calib_count = max(1, min(num_samples, sweep_samples))
    calib_idx = np.arange(calib_count, dtype=np.int32)

    sweep_records: List[Tuple[Tuple[int, int, int, int], float]] = []
    if sweep_radius > 0:
        for cand in itertools.product(*ranges):
            m = eval_match(cand, q, q8_inputs, hls_preds, calib_idx)
            sweep_records.append((cand, m))
        sweep_records.sort(key=lambda x: x[1], reverse=True)
        shortlist = [cand for cand, _ in sweep_records[: max(1, top_n)]]
    else:
        shortlist = [tuple(init_shifts)]

    full_idx = np.arange(num_samples, dtype=np.int32)
    best_shifts = tuple(init_shifts)
    best_match = -1.0
    for cand in shortlist:
        m = eval_match(cand, q, q8_inputs, hls_preds, full_idx)
        if m > best_match:
            best_match = m
            best_shifts = cand

    rtl_preds = np.asarray([infer_int_q(q8_inputs[i], q, best_shifts) for i in range(num_samples)], dtype=np.int32)
    match = float(np.mean(rtl_preds == hls_preds))

    expected_source = os.environ.get("U55C_RTL_TB_EXPECTED_SOURCE", "quantized").strip().lower()
    if expected_source in ("float", "hls_float", "hls"):
        expected_preds = hls_preds
        expected_source = "hls_float"
    else:
        expected_preds = rtl_preds
        expected_source = "quantized"

    write_sv_include(paths, q, best_shifts)
    write_shift_include(paths, best_shifts)
    write_mem_files(paths, q8_inputs, expected_preds.astype(np.uint32), hls_preds.astype(np.uint32))

    report = {
        "num_samples": int(num_samples),
        "match_vs_hls_float": match,
        "tb_expected_pred_source": expected_source,
        "tb_expected_match_vs_rtl": float(np.mean(expected_preds == rtl_preds)),
        "tb_expected_match_vs_hls_float": float(np.mean(expected_preds == hls_preds)),
        "weight_root": str(paths.weight_root),
        "test_root": str(paths.test_root),
        "testset_scores": {str(path): int(score) for score, path in scored},
        "shifts": {
            "conv1": int(best_shifts[0]),
            "conv2": int(best_shifts[1]),
            "fc1": int(best_shifts[2]),
            "fc2": int(best_shifts[3]),
        },
        "init_shifts": {
            "conv1": int(init_shifts[0]),
            "conv2": int(init_shifts[1]),
            "fc1": int(init_shifts[2]),
            "fc2": int(init_shifts[3]),
        },
        "activation_scales": activation_scales,
        "weight_scale_stats": {
            "conv1": {"min": float(np.min(sw_conv1)), "median": float(np.median(sw_conv1)), "max": float(np.max(sw_conv1))},
            "conv2": {"min": float(np.min(sw_conv2)), "median": float(np.median(sw_conv2)), "max": float(np.max(sw_conv2))},
            "fc1": {"min": float(np.min(sw_fc1)), "median": float(np.median(sw_fc1)), "max": float(np.max(sw_fc1))},
            "fc2": {"min": float(np.min(sw_fc2)), "median": float(np.median(sw_fc2)), "max": float(np.max(sw_fc2))},
            "fc3": {"min": float(np.min(sw_fc3)), "median": float(np.median(sw_fc3)), "max": float(np.max(sw_fc3))},
        },
        "weight_scales": {
            "conv1": sw_conv1.tolist(),
            "conv2": sw_conv2.tolist(),
            "fc1": sw_fc1.tolist(),
            "fc2": sw_fc2.tolist(),
            "fc3": sw_fc3.tolist(),
        },
        "shift_sweep": {
            "radius": int(sweep_radius),
            "calibration_samples": int(calib_count),
            "ranges": {
                "conv1": ranges[0],
                "conv2": ranges[1],
                "fc1": ranges[2],
                "fc2": ranges[3],
            },
            "tested_candidates": int(len(sweep_records)),
            "best_calibration_match": float(sweep_records[0][1]) if sweep_records else None,
            "top_candidates": [
                {
                    "shifts": {
                        "conv1": int(c[0]),
                        "conv2": int(c[1]),
                        "fc1": int(c[2]),
                        "fc2": int(c[3]),
                    },
                    "calibration_match": float(m),
                }
                for c, m in sweep_records[: min(10, len(sweep_records))]
            ],
        },
    }
    paths.report_out.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"[ok] wrote {paths.include_out}")
    print(f"[ok] wrote {paths.shift_include_out}")
    print(f"[ok] wrote {paths.q8_test_mem_out}")
    print(f"[ok] wrote {paths.hls_pred_mem_out}")
    print(f"[ok] wrote {paths.hls_float_pred_mem_out}")
    print(f"[ok] wrote {paths.report_out}")
    print(f"[info] TB expected prediction source: {expected_source}")
    print(f"[info] init shifts: {init_shifts}")
    print(f"[info] selected shifts: {list(best_shifts)}")
    print(f"[info] quantized RTL class-match vs float HLS on {num_samples} samples: {match:.3f}")


if __name__ == "__main__":
    main()
