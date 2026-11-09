#!/usr/bin/env python3
from __future__ import annotations

import base64
import csv
import html
import os
import re
import shlex
import struct
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

try:
    import markdown as markdown_lib
except Exception:  # pragma: no cover
    markdown_lib = None

APP_NAME = "U55C CIFAR Car-vs-Truck Lab"
ROOT_DIR = Path(__file__).resolve().parents[1]
STATIC_DIR = Path(__file__).resolve().parent / "static"
PROJECT_ENV = ROOT_DIR / "config" / "project.env"
README_ROOT = ROOT_DIR / "README"
TOP_README = ROOT_DIR / "README.md"
README_ASSETS = README_ROOT / "assets"
BENCH_BIN = ROOT_DIR / "build" / "host" / "u55c_bench"
BUILD_HOST_SCRIPT = ROOT_DIR / "scripts" / "build_host.sh"
XRT_SMI = os.environ.get("WEB_XRT_SMI", "/opt/xilinx/xrt/bin/xrt-smi")
LEGACY_ECELINUX_DIR = ROOT_DIR / "legacy_src" / "ece5775_final_proj" / "car_truck_accel" / "ecelinux"
TEST_DATA_CSV = LEGACY_ECELINUX_DIR / "test_data2" / "test_data.dat"
TEST_LABELS_CSV = LEGACY_ECELINUX_DIR / "test_data2" / "test_labels.csv"
TEST_META_JSON = LEGACY_ECELINUX_DIR / "test_data2" / "dataset_meta.json"
CIFAR_IMAGE_SIDE = 32
IMG_ELEMS = 3072
FINAL_ITERATION_MARKER = ROOT_DIR / "results" / "final_iteration.json"

_INFER_SAMPLES: List[List[float]] | None = None
_INFER_LABELS: List[int] | None = None
_INFER_META: Dict[str, Any] | None = None


class BenchmarkRequest(BaseModel):
    mode: str = "hw"
    elements: int = Field(default=100, ge=1, le=5_000_000)
    iterations: int = Field(default=1, ge=1, le=10_000)
    device: str = "0"
    kernel: str = "mlp_u55c"
    seed: int = 1
    xclbin_path: str = ""
    input_f32_bin: str = ""
    output_u32_bin: str = ""
    rebuild_host: bool = False


class CompareRequest(BaseModel):
    images: int = Field(default=100, ge=1, le=100_000)
    iterations: int = Field(default=1, ge=1, le=10_000)
    device: str = "0"
    kernel: str = "mlp_u55c"
    seed: int = 1
    xclbin_path: str = ""
    rebuild_host: bool = False


class ProgramRequest(BaseModel):
    xclbin_path: str = ""
    device: str = "0"


class DocRequest(BaseModel):
    key: str


class InferenceRequest(BaseModel):
    sample_index: int = Field(default=0, ge=0, le=100_000)
    mode: str = "both"
    device: str = "0"
    kernel: str = "mlp_u55c"
    seed: int = 1
    xclbin_path: str = ""
    rebuild_host: bool = False


app = FastAPI(title=APP_NAME)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
if README_ASSETS.exists():
    app.mount("/README/assets", StaticFiles(directory=str(README_ASSETS)), name="readme_assets")


def read_project_env() -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not PROJECT_ENV.exists():
        return values
    for raw in PROJECT_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def startup_gate_state() -> Dict[str, Any]:
    status_raw = os.environ.get("WEBAPP_STARTUP_GATE_STATUS", "ok").strip().lower()
    message = os.environ.get("WEBAPP_STARTUP_GATE_MESSAGE", "").strip()
    rc_raw = os.environ.get("WEBAPP_STARTUP_GATE_RC", "0").strip()

    status = status_raw if status_raw in {"ok", "warn", "skipped"} else "unknown"
    try:
        rc: Optional[int] = int(rc_raw)
    except ValueError:
        rc = None

    return {
        "status": status,
        "message": message,
        "rc": rc,
    }


def resolve_project_path(path_value: str) -> Path:
    expanded = Path(os.path.expandvars(os.path.expanduser(path_value)))
    if expanded.is_absolute():
        return expanded
    return (ROOT_DIR / expanded).resolve()


def default_xclbin_from_env(env_cfg: Dict[str, str]) -> str:
    base_path_raw = env_cfg.get("U55C_XCLBIN", "").strip()
    if base_path_raw:
        return str(resolve_project_path(base_path_raw))
    return ""


def run_command(cmd: List[str], timeout_s: int = 180) -> Dict[str, Any]:
    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_s,
        check=False,
    )
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return {
        "ok": proc.returncode == 0,
        "rc": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "cmd": " ".join(shlex.quote(x) for x in cmd),
        "output": proc.stdout,
    }


def ensure_host_binary(rebuild: bool) -> None:
    if rebuild or not BENCH_BIN.exists():
        proc = run_command([str(BUILD_HOST_SCRIPT)], timeout_s=600)
        if not proc["ok"]:
            tail = "\n".join(proc["output"].splitlines()[-40:])
            raise HTTPException(status_code=500, detail=f"host build failed (rc={proc['rc']})\n{tail}")


def parse_bench_summary(text: str) -> Dict[str, Any]:
    lines = [line.strip() for line in text.splitlines() if line.strip().startswith("mode=")]
    if not lines:
        return {"summary_line": "", "metrics": {}}
    summary = lines[-1]
    metrics: Dict[str, Any] = {}
    for token in summary.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        raw = value.strip().strip(",")
        if re.fullmatch(r"[-+]?\d+", raw):
            metrics[key] = int(raw)
        elif re.fullmatch(r"[-+]?\d*\.\d+", raw):
            metrics[key] = float(raw)
        else:
            metrics[key] = raw
    return {"summary_line": summary, "metrics": metrics}


def cpu_mode_for_kernel(kernel_name: str) -> str:
    # Use the real CPU reference path for CNN kernels.
    return "cpu-ref" if "mlp_u55c" in kernel_name else "dry-run"


def label_name(label_id: int) -> str:
    if label_id == 0:
        return "car"
    if label_id == 1:
        return "truck"
    return f"class_{label_id}"


def _default_norm() -> Dict[str, List[float]]:
    return {"mean": [0.4914, 0.4822, 0.4465], "std": [0.2023, 0.1994, 0.2010]}


def load_inference_dataset() -> tuple[List[List[float]], List[int], Dict[str, Any]]:
    global _INFER_SAMPLES, _INFER_LABELS, _INFER_META
    if _INFER_SAMPLES is not None and _INFER_LABELS is not None and _INFER_META is not None:
        return _INFER_SAMPLES, _INFER_LABELS, _INFER_META

    if not TEST_DATA_CSV.exists() or not TEST_LABELS_CSV.exists():
        raise HTTPException(
            status_code=404,
            detail=f"inference dataset not found ({TEST_DATA_CSV} / {TEST_LABELS_CSV})",
        )

    samples: List[List[float]] = []
    with TEST_DATA_CSV.open("r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            values = [float(v) for v in row]
            if len(values) != IMG_ELEMS:
                raise HTTPException(
                    status_code=500,
                    detail=f"invalid sample length {len(values)} in {TEST_DATA_CSV} (expected {IMG_ELEMS})",
                )
            samples.append(values)

    labels: List[int] = []
    with TEST_LABELS_CSV.open("r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            labels.append(int(float(row[0])))

    if len(samples) != len(labels):
        raise HTTPException(
            status_code=500,
            detail=f"dataset length mismatch: {len(samples)} samples vs {len(labels)} labels",
        )

    meta: Dict[str, Any] = {}
    if TEST_META_JSON.exists():
        import json

        try:
            meta = json.loads(TEST_META_JSON.read_text(encoding="utf-8"))
        except Exception:
            meta = {}
    norm = meta.get("normalization")
    if not isinstance(norm, dict) or "mean" not in norm or "std" not in norm:
        meta["normalization"] = _default_norm()

    _INFER_SAMPLES = samples
    _INFER_LABELS = labels
    _INFER_META = meta
    return samples, labels, meta


def denorm_to_rgb(sample: List[float], mean: List[float], std: List[float]) -> bytes:
    # sample layout is channel-first: R[1024], G[1024], B[1024]
    out = bytearray(CIFAR_IMAGE_SIDE * CIFAR_IMAGE_SIDE * 3)
    for idx in range(CIFAR_IMAGE_SIDE * CIFAR_IMAGE_SIDE):
        for c in range(3):
            v = sample[c * 1024 + idx] * std[c] + mean[c]
            pix = int(round(v * 255.0))
            if pix < 0:
                pix = 0
            elif pix > 255:
                pix = 255
            out[idx * 3 + c] = pix
    return bytes(out)


def write_sample_f32(path: Path, sample: List[float]) -> None:
    blob = struct.pack(f"<{len(sample)}f", *sample)
    path.write_bytes(blob)


def read_prediction_u32(path: Path) -> int:
    raw = path.read_bytes()
    if len(raw) < 4:
        raise HTTPException(status_code=500, detail=f"prediction output missing/short: {path}")
    return int(struct.unpack_from("<I", raw, 0)[0])


def resolve_program_device(device: str) -> str:
    candidate = device.strip()
    if re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]", candidate):
        return candidate
    if candidate.isdigit():
        probe = run_command([XRT_SMI, "examine"], timeout_s=30)
        if probe["ok"]:
            bdfs = re.findall(r"\[([0-9A-Fa-f:.]+)\]", probe["output"])
            idx = int(candidate)
            if idx < len(bdfs):
                return bdfs[idx]
    return candidate


def docs_catalog() -> Dict[str, Path]:
    docs: Dict[str, Path] = {}
    hidden_docs = {
        "RUNBOOK.md",
        "WEBAPP.md",
        "TESTS.md",
        "SETUP.md",
        "INTERNAL_MILESTONES.md",
        "PORTING_PLAN.md",
    }
    if TOP_README.exists():
        docs["README.md"] = TOP_README
    if README_ROOT.exists():
        for p in sorted(README_ROOT.glob("*.md")):
            if p.name in hidden_docs:
                continue
            docs[f"README/{p.name}"] = p
    return docs


def markdown_to_html(text: str) -> str:
    if markdown_lib is None:
        return f"<pre>{html.escape(text)}</pre>"
    return markdown_lib.markdown(
        text,
        extensions=["extra", "fenced_code", "tables", "toc", "sane_lists"],
        output_format="html5",
    )


def block_diagram_data() -> Dict[str, Any]:
    return {
        "root_view": "top",
        "views": {
            "top": {
                "id": "top",
                "title": "Car-vs-Truck CNN Accelerator Top-Level",
                "description": "CIFAR sample batching, host orchestration, and FPGA kernel execution flow.",
                "notes": [
                    "Host layer prepares sample batches and launches kernel runs.",
                    "Kernel reads image vectors and produces predicted class labels.",
                    "Runtime captures transfer and kernel timing for CPU/FPGA comparison.",
                ],
                "nodes": [
                    {
                        "id": "ui",
                        "label": "Web + Host Control",
                        "subtitle": "images / iterations / mode",
                        "x": 40,
                        "y": 80,
                        "w": 240,
                        "h": 110,
                        "group": "software",
                        "details": "Collects workload inputs and invokes CPU and FPGA profiling paths.",
                    },
                    {
                        "id": "dataset",
                        "label": "CIFAR Dataset + Preprocess",
                        "subtitle": "car/truck samples",
                        "x": 320,
                        "y": 80,
                        "w": 260,
                        "h": 110,
                        "group": "software",
                        "details": "Loads prepared car/truck vectors from project dataset assets.",
                    },
                    {
                        "id": "xrt",
                        "label": "XRT Runtime",
                        "subtitle": "program + launch",
                        "x": 620,
                        "y": 80,
                        "w": 220,
                        "h": 110,
                        "group": "platform",
                        "details": "Programs xclbin and dispatches mlp_u55c kernel commands.",
                    },
                    {
                        "id": "hbm",
                        "label": "HBM Buffers",
                        "subtitle": "images + predictions",
                        "x": 880,
                        "y": 60,
                        "w": 260,
                        "h": 150,
                        "group": "memory",
                        "details": "Input image vectors and output labels are staged through HBM memory.",
                        "drill_to": "memory_path",
                    },
                    {
                        "id": "kernel",
                        "label": "mlp_u55c Kernel",
                        "subtitle": "CNN inference engine",
                        "x": 520,
                        "y": 280,
                        "w": 300,
                        "h": 150,
                        "group": "compute",
                        "details": "Executes batched inference and writes predicted class IDs.",
                        "drill_to": "kernel_core",
                    },
                    {
                        "id": "metrics",
                        "label": "CPU/FPGA Compare",
                        "subtitle": "speedup + transfer timing",
                        "x": 180,
                        "y": 300,
                        "w": 280,
                        "h": 130,
                        "group": "observability",
                        "details": "Reports total time, kernel time, and end-to-end speedup metrics.",
                    },
                ],
                "edges": [
                    {"from": "ui", "to": "dataset", "label": "workload config"},
                    {"from": "dataset", "to": "xrt", "label": "input buffers"},
                    {"from": "xrt", "to": "hbm", "label": "H2D / D2H"},
                    {"from": "hbm", "to": "kernel", "label": "image vectors"},
                    {"from": "kernel", "to": "hbm", "label": "predictions"},
                    {"from": "kernel", "to": "metrics", "label": "FPGA timing"},
                    {"from": "ui", "to": "metrics", "label": "CPU baseline"},
                ],
            },
            "kernel_core": {
                "id": "kernel_core",
                "title": "Kernel Datapath",
                "description": "Core compute stages for batched inference.",
                "notes": [
                    "Sample vectors are loaded per image from global memory.",
                    "Feature and dense layers run in sequence inside kernel datapath.",
                    "Predicted class ID is emitted to output memory.",
                ],
                "nodes": [
                    {
                        "id": "load",
                        "label": "Input Loader",
                        "subtitle": "3072-float image",
                        "x": 80,
                        "y": 210,
                        "w": 230,
                        "h": 120,
                        "group": "datapath",
                        "details": "Reads one image vector from memory with burst transactions.",
                    },
                    {
                        "id": "compute",
                        "label": "CNN Compute",
                        "subtitle": "conv + dense stages",
                        "x": 380,
                        "y": 190,
                        "w": 280,
                        "h": 150,
                        "group": "compute",
                        "details": "Runs fixed-parameter network layers and derives logits.",
                    },
                    {
                        "id": "write",
                        "label": "Prediction Writer",
                        "subtitle": "class output",
                        "x": 740,
                        "y": 210,
                        "w": 240,
                        "h": 120,
                        "group": "memory",
                        "details": "Commits predicted class index to output buffer.",
                    },
                ],
                "edges": [
                    {"from": "load", "to": "compute", "label": "sample vector"},
                    {"from": "compute", "to": "write", "label": "class ID"},
                ],
            },
            "memory_path": {
                "id": "memory_path",
                "title": "Memory Path",
                "description": "Input/output memory layout for inference execution.",
                "notes": [
                    "Input image vectors are read from contiguous HBM address space.",
                    "Prediction outputs are written as compact class IDs.",
                ],
                "nodes": [
                    {
                        "id": "img",
                        "label": "HBM[0] images",
                        "x": 120,
                        "y": 140,
                        "w": 280,
                        "h": 120,
                        "group": "memory",
                        "details": "Batched CIFAR vectors consumed by the kernel.",
                    },
                    {
                        "id": "pred",
                        "label": "HBM[1] predictions",
                        "x": 520,
                        "y": 140,
                        "w": 280,
                        "h": 120,
                        "group": "memory",
                        "details": "Kernel output labels transferred back to host.",
                    },
                ],
                "edges": [
                    {"from": "img", "to": "pred", "label": "inference batch flow"},
                ],
            },
        },
    }


@app.get("/")
def root() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def api_health() -> Dict[str, Any]:
    env = read_project_env()
    gate = startup_gate_state()
    final_iteration: Dict[str, Any] | None = None
    if FINAL_ITERATION_MARKER.exists():
        try:
            import json

            final_iteration = json.loads(FINAL_ITERATION_MARKER.read_text(encoding="utf-8"))
        except Exception:
            final_iteration = {
                "ok": False,
                "detail": f"failed to parse marker: {FINAL_ITERATION_MARKER}",
            }
    return {
        "ok": True,
        "app": APP_NAME,
        "project_root": str(ROOT_DIR),
        "default_kernel": env.get("U55C_KERNEL_NAME", "mlp_u55c"),
        "default_xclbin": default_xclbin_from_env(env),
        "final_iteration": final_iteration,
        "startup_gate": gate,
    }


@app.get("/api/docs/list")
def api_docs_list() -> Dict[str, Any]:
    docs = docs_catalog()
    return {
        "ok": True,
        "docs": [{"key": key, "title": key} for key in docs],
    }


@app.post("/api/docs/read")
def api_docs_read(req: DocRequest) -> Dict[str, Any]:
    docs = docs_catalog()
    if req.key not in docs:
        raise HTTPException(status_code=404, detail=f"document not found: {req.key}")
    path = docs[req.key]
    content = path.read_text(encoding="utf-8", errors="replace")
    return {
        "ok": True,
        "key": req.key,
        "title": req.key,
        "content": content,
        "content_html": markdown_to_html(content),
    }


@app.get("/api/diagram")
def api_diagram() -> Dict[str, Any]:
    return block_diagram_data()


@app.post("/api/benchmark")
def api_benchmark(req: BenchmarkRequest) -> Dict[str, Any]:
    mode = req.mode.strip().lower()
    if mode not in ("dry-run", "cpu-ref", "hw"):
        raise HTTPException(status_code=400, detail="mode must be dry-run, cpu-ref, or hw")

    ensure_host_binary(req.rebuild_host)

    env_cfg = read_project_env()
    xclbin_candidate = req.xclbin_path.strip() or default_xclbin_from_env(env_cfg)
    resolved_xclbin = ""
    resolved_input = ""
    resolved_output = ""

    if mode == "hw":
        if not xclbin_candidate:
            raise HTTPException(status_code=400, detail="xclbin path is required in hw mode")
        xclbin = resolve_project_path(xclbin_candidate)
        if not xclbin.exists():
            raise HTTPException(status_code=404, detail=f"xclbin not found: {xclbin}")
        resolved_xclbin = str(xclbin)

    if req.input_f32_bin.strip():
        input_path = resolve_project_path(req.input_f32_bin.strip())
        if not input_path.exists():
            raise HTTPException(status_code=404, detail=f"input_f32_bin not found: {input_path}")
        resolved_input = str(input_path)

    if req.output_u32_bin.strip():
        output_path = resolve_project_path(req.output_u32_bin.strip())
        output_path.parent.mkdir(parents=True, exist_ok=True)
        resolved_output = str(output_path)

    cmd = [
        str(BENCH_BIN),
        "--mode",
        mode,
        "--kernel",
        req.kernel,
        "--device",
        req.device,
        "--elements",
        str(req.elements),
        "--iterations",
        str(req.iterations),
        "--seed",
        str(req.seed),
    ]
    if mode == "hw":
        cmd.extend(["--xclbin", resolved_xclbin])
    if resolved_input:
        cmd.extend(["--input-f32-bin", resolved_input])
    if resolved_output:
        cmd.extend(["--output-u32-bin", resolved_output])

    result = run_command(cmd, timeout_s=7200)
    parsed = parse_bench_summary(result["output"])
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "cmd": result["cmd"],
        "summary": parsed["summary_line"],
        "metrics": parsed["metrics"],
        "input_f32_bin": resolved_input,
        "output_u32_bin": resolved_output,
        "output_tail": "\n".join(result["output"].splitlines()[-40:]),
    }


@app.post("/api/compare")
def api_compare(req: CompareRequest) -> Dict[str, Any]:
    ensure_host_binary(req.rebuild_host)

    base_kwargs = {
        "elements": req.images,
        "iterations": req.iterations,
        "device": req.device,
        "kernel": req.kernel,
        "seed": req.seed,
        "xclbin_path": req.xclbin_path,
        "rebuild_host": False,
    }

    cpu_mode = cpu_mode_for_kernel(req.kernel)
    cpu = api_benchmark(BenchmarkRequest(mode=cpu_mode, **base_kwargs))
    fpga = api_benchmark(BenchmarkRequest(mode="hw", **base_kwargs))

    cpu_metrics = cpu.get("metrics", {})
    fpga_metrics = fpga.get("metrics", {})

    cpu_total = float(cpu_metrics.get("avg_total_ms", 0.0) or 0.0)
    fpga_total = float(fpga_metrics.get("avg_total_ms", 0.0) or 0.0)
    cpu_kernel = float(cpu_metrics.get("avg_kernel_ms", 0.0) or 0.0)
    fpga_kernel = float(fpga_metrics.get("avg_kernel_ms", 0.0) or 0.0)

    return {
        "ok": bool(cpu.get("ok") and fpga.get("ok")),
        "workload": {
            "images": req.images,
            "iterations": req.iterations,
            "kernel": req.kernel,
            "device": req.device,
            "seed": req.seed,
            "cpu_mode": cpu_mode,
        },
        "cpu": cpu,
        "fpga": fpga,
        "speedup": {
            "total_x": (cpu_total / fpga_total) if fpga_total > 0.0 else 0.0,
            "kernel_x": (cpu_kernel / fpga_kernel) if fpga_kernel > 0.0 else 0.0,
        },
    }


@app.get("/api/inference/summary")
def api_inference_summary() -> Dict[str, Any]:
    samples, labels, meta = load_inference_dataset()
    car_count = sum(1 for x in labels if x == 0)
    truck_count = sum(1 for x in labels if x == 1)
    return {
        "ok": True,
        "sample_count": len(samples),
        "class_counts": {"car": car_count, "truck": truck_count},
        "image_shape": {"height": CIFAR_IMAGE_SIDE, "width": CIFAR_IMAGE_SIDE, "channels": 3},
        "normalization": meta.get("normalization", _default_norm()),
    }


@app.get("/api/inference/sample/{sample_index}")
def api_inference_sample(sample_index: int) -> Dict[str, Any]:
    samples, labels, meta = load_inference_dataset()
    if sample_index < 0 or sample_index >= len(samples):
        raise HTTPException(status_code=400, detail=f"sample_index out of range: {sample_index}")

    sample = samples[sample_index]
    true_label = labels[sample_index]
    norm = meta.get("normalization", _default_norm())
    mean = [float(v) for v in norm.get("mean", _default_norm()["mean"])]
    std = [float(v) for v in norm.get("std", _default_norm()["std"])]
    rgb = denorm_to_rgb(sample, mean, std)
    rgb_b64 = base64.b64encode(rgb).decode("ascii")

    return {
        "ok": True,
        "sample_index": sample_index,
        "true_label_id": true_label,
        "true_label_name": label_name(true_label),
        "height": CIFAR_IMAGE_SIDE,
        "width": CIFAR_IMAGE_SIDE,
        "rgb_b64": rgb_b64,
    }


@app.post("/api/inference/predict")
def api_inference_predict(req: InferenceRequest) -> Dict[str, Any]:
    mode = req.mode.strip().lower()
    if mode not in ("cpu", "fpga", "both"):
        raise HTTPException(status_code=400, detail="mode must be cpu, fpga, or both")

    samples, labels, meta = load_inference_dataset()
    if req.sample_index < 0 or req.sample_index >= len(samples):
        raise HTTPException(status_code=400, detail=f"sample_index out of range: {req.sample_index}")

    ensure_host_binary(req.rebuild_host)

    sample = samples[req.sample_index]
    true_label = labels[req.sample_index]
    norm = meta.get("normalization", _default_norm())
    mean = [float(v) for v in norm.get("mean", _default_norm()["mean"])]
    std = [float(v) for v in norm.get("std", _default_norm()["std"])]
    rgb = denorm_to_rgb(sample, mean, std)
    rgb_b64 = base64.b64encode(rgb).decode("ascii")

    def run_one(exec_mode: str) -> Dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="u55c_infer_") as tmpdir:
            tmp = Path(tmpdir)
            input_path = tmp / "sample_input.f32.bin"
            output_path = tmp / "sample_output.u32.bin"
            write_sample_f32(input_path, sample)

            bench = api_benchmark(
                BenchmarkRequest(
                    mode=exec_mode,
                    elements=1,
                    iterations=1,
                    device=req.device,
                    kernel=req.kernel,
                    seed=req.seed,
                    xclbin_path=req.xclbin_path,
                    input_f32_bin=str(input_path),
                    output_u32_bin=str(output_path),
                    rebuild_host=False,
                )
            )
            if not bench.get("ok"):
                raise HTTPException(
                    status_code=500,
                    detail=f"inference failed in mode={exec_mode}: {bench.get('output_tail', '')}",
                )
            pred_id = read_prediction_u32(output_path)
            return {
                "mode": exec_mode,
                "prediction_id": pred_id,
                "prediction_name": label_name(pred_id),
                "matches_ground_truth": pred_id == true_label,
                "benchmark": bench,
            }

    predictions: Dict[str, Any] = {}
    if mode in ("cpu", "both"):
        cpu_exec_mode = cpu_mode_for_kernel(req.kernel)
        predictions["cpu"] = run_one(cpu_exec_mode)
    if mode in ("fpga", "both"):
        predictions["fpga"] = run_one("hw")

    return {
        "ok": True,
        "sample_index": req.sample_index,
        "true_label_id": true_label,
        "true_label_name": label_name(true_label),
        "height": CIFAR_IMAGE_SIDE,
        "width": CIFAR_IMAGE_SIDE,
        "rgb_b64": rgb_b64,
        "predictions": predictions,
    }


@app.get("/api/fpga/status")
def api_fpga_status() -> Dict[str, Any]:
    if not Path(XRT_SMI).exists():
        raise HTTPException(status_code=500, detail=f"xrt-smi not found at {XRT_SMI}")
    result = run_command([XRT_SMI, "examine"], timeout_s=120)
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "output": result["output"],
    }


@app.post("/api/fpga/program")
def api_fpga_program(req: ProgramRequest) -> Dict[str, Any]:
    env_cfg = read_project_env()
    xclbin_candidate = req.xclbin_path.strip() or default_xclbin_from_env(env_cfg)
    if not xclbin_candidate:
        raise HTTPException(status_code=400, detail="xclbin path is required")

    xclbin = resolve_project_path(xclbin_candidate)
    if not xclbin.exists():
        raise HTTPException(status_code=404, detail=f"xclbin not found: {xclbin}")
    if xclbin.suffix != ".xclbin":
        raise HTTPException(status_code=400, detail="program path must end in .xclbin")

    program_device = resolve_program_device(req.device)
    cmd = [XRT_SMI, "--batch", "program", "--device", program_device, "--user", str(xclbin)]
    result = run_command(cmd, timeout_s=600)
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "cmd": result["cmd"],
        "resolved_device": program_device,
        "output": result["output"],
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("WEB_PORT", "9895"))
    uvicorn.run(app, host="0.0.0.0", port=port)
