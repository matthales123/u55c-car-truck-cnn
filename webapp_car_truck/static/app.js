const imagesInput = document.getElementById('images');
const benchItersInput = document.getElementById('bench-iters');
const seedInput = document.getElementById('seed');
const runCpuBtn = document.getElementById('run-cpu-btn');
const runFpgaBtn = document.getElementById('run-fpga-btn');
const runCompareBtn = document.getElementById('run-compare-btn');
const labMeta = document.getElementById('lab-meta');
const cpuSummary = document.getElementById('cpu-summary');
const fpgaSummary = document.getElementById('fpga-summary');
const compareSummary = document.getElementById('compare-summary');
const sampleCanvas = document.getElementById('sample-canvas');
const sampleIndexInput = document.getElementById('sample-index');
const samplePrevBtn = document.getElementById('sample-prev-btn');
const sampleNextBtn = document.getElementById('sample-next-btn');
const sampleLoadBtn = document.getElementById('sample-load-btn');
const sampleMeta = document.getElementById('sample-meta');
const inferCpuBtn = document.getElementById('infer-cpu-btn');
const inferFpgaBtn = document.getElementById('infer-fpga-btn');
const inferBothBtn = document.getElementById('infer-both-btn');
const inferSummary = document.getElementById('infer-summary');

const benchMode = document.getElementById('bench-mode');
const elementsInput = document.getElementById('elements');
const iterationsInput = document.getElementById('iterations');
const deviceInput = document.getElementById('device');
const kernelInput = document.getElementById('kernel');
const xclbinInput = document.getElementById('xclbin');
const statusBtn = document.getElementById('status-btn');
const programBtn = document.getElementById('program-btn');
const benchBtn = document.getElementById('bench-btn');
const logEl = document.getElementById('runtime-log');
const finalIterationBanner = document.getElementById('final-iteration-banner');

function appendLog(msg) {
  const now = new Date().toLocaleTimeString();
  logEl.textContent = `[${now}] ${msg}\n${logEl.textContent}`.slice(0, 50000);
}

function updateFinalIterationBanner(finalData) {
  if (!finalIterationBanner) {
    return;
  }
  if (!finalData || finalData.ok === false) {
    finalIterationBanner.hidden = true;
    return;
  }
  const summary = finalData.summary || {};
  const speedup = Number(summary.best_speedup_x || 0);
  const speedupText = Number.isFinite(speedup) && speedup > 0 ? `${speedup.toFixed(3)}x` : 'n/a';
  const profile = summary.selected_profile || 'n/a';
  finalIterationBanner.textContent =
    `Final iteration selected: ${profile} | Best CPU vs FPGA speedup: ${speedupText}`;
  finalIterationBanner.hidden = false;
}

async function api(path, payload = null) {
  const resp = await fetch(path, {
    method: payload ? 'POST' : 'GET',
    headers: payload ? { 'Content-Type': 'application/json' } : undefined,
    body: payload ? JSON.stringify(payload) : undefined,
  });

  const raw = await resp.text();
  let data = {};
  if (raw) {
    try {
      data = JSON.parse(raw);
    } catch (_err) {
      data = { detail: raw.slice(0, 500) };
    }
  }

  if (!resp.ok) {
    throw new Error(data.detail || data.message || `${resp.status} ${resp.statusText}`);
  }
  return data;
}

function prettyMetrics(metrics = {}) {
  const lines = Object.entries(metrics).map(([k, v]) => `- ${k}: ${v}`);
  return lines.length ? lines.join('\n') : '(no parsed metrics)';
}

const sampleCtx = sampleCanvas ? sampleCanvas.getContext('2d') : null;
let sampleCount = 0;
let activeSample = 0;

function clampSampleIndex(v) {
  if (sampleCount <= 0) {
    return 0;
  }
  if (v < 0) {
    return 0;
  }
  if (v >= sampleCount) {
    return sampleCount - 1;
  }
  return v;
}

function drawSampleRgb(rgbB64, width, height) {
  if (!sampleCtx) {
    return;
  }
  const raw = atob(rgbB64 || '');
  const rgb = new Uint8ClampedArray(raw.length);
  for (let i = 0; i < raw.length; i += 1) {
    rgb[i] = raw.charCodeAt(i);
  }
  const img = sampleCtx.createImageData(width, height);
  for (let i = 0, p = 0; i < rgb.length; i += 3, p += 4) {
    img.data[p] = rgb[i];
    img.data[p + 1] = rgb[i + 1];
    img.data[p + 2] = rgb[i + 2];
    img.data[p + 3] = 255;
  }
  sampleCtx.putImageData(img, 0, 0);
}

function formatInferenceLine(prefix, node, truthName) {
  if (!node) {
    return `${prefix}: n/a`;
  }
  const m = node.benchmark?.metrics || {};
  const total = Number(m.avg_total_ms || 0).toFixed(3);
  const kernel = Number(m.avg_kernel_ms || 0).toFixed(3);
  const pred = node.prediction_name || `class_${node.prediction_id}`;
  const match = node.matches_ground_truth ? 'match' : 'mismatch';
  return `${prefix}: predicted ${pred} (${node.prediction_id}) | truth ${truthName} | ${match} | total ${total} ms | kernel ${kernel} ms`;
}

function cpuModeForKernel() {
  const kernel = `${kernelInput.value || 'mlp_u55c'}`.trim() || 'mlp_u55c';
  return kernel.includes('mlp_u55c') ? 'cpu-ref' : 'dry-run';
}

function profilePayload(modeOverride = null) {
  const images = Math.max(1, Number(imagesInput.value || 100) | 0);
  const iterations = Math.max(1, Number(benchItersInput.value || 1) | 0);
  const seed = Number(seedInput.value || 1) | 0;
  return {
    mode: modeOverride || 'dry-run',
    elements: images,
    iterations,
    device: `${deviceInput.value || '0'}`.trim() || '0',
    kernel: `${kernelInput.value || 'mlp_u55c'}`.trim() || 'mlp_u55c',
    seed,
    xclbin_path: `${xclbinInput.value || ''}`.trim(),
    rebuild_host: false,
  };
}

async function runCpuProfile() {
  labMeta.textContent = 'Running CPU profile...';
  const data = await api('/api/benchmark', profilePayload(cpuModeForKernel()));
  cpuSummary.textContent = [
    `Status: ${data.ok ? 'OK' : 'FAILED'} (rc=${data.rc})`,
    `Command: ${data.cmd}`,
    `Summary: ${data.summary || '(none)'}`,
    '',
    'Parsed Metrics:',
    prettyMetrics(data.metrics),
    '',
    'Output Tail:',
    data.output_tail || '(none)',
  ].join('\n');
  labMeta.textContent = 'CPU profile complete.';
}

async function runFpgaProfile() {
  labMeta.textContent = 'Running FPGA profile...';
  const data = await api('/api/benchmark', profilePayload('hw'));
  fpgaSummary.textContent = [
    `Status: ${data.ok ? 'OK' : 'FAILED'} (rc=${data.rc})`,
    `Command: ${data.cmd}`,
    `Summary: ${data.summary || '(none)'}`,
    '',
    'Parsed Metrics:',
    prettyMetrics(data.metrics),
    '',
    'Output Tail:',
    data.output_tail || '(none)',
  ].join('\n');
  labMeta.textContent = 'FPGA profile complete.';
}

async function runCompare() {
  labMeta.textContent = 'Running CPU vs FPGA compare...';
  const images = Math.max(1, Number(imagesInput.value || 100) | 0);
  const iters = Math.max(1, Number(benchItersInput.value || 1) | 0);
  const payload = {
    images,
    iterations: iters,
    device: `${deviceInput.value || '0'}`.trim() || '0',
    kernel: `${kernelInput.value || 'mlp_u55c'}`.trim() || 'mlp_u55c',
    seed: Number(seedInput.value || 1) | 0,
    xclbin_path: `${xclbinInput.value || ''}`.trim(),
    rebuild_host: false,
  };
  const data = await api('/api/compare', payload);

  const speedup = data.speedup || {};
  compareSummary.textContent = [
    `Overall status: ${data.ok ? 'OK' : 'FAILED'}`,
    `Images: ${images}`,
    `Iterations: ${iters}`,
    `CPU mode: ${data.workload?.cpu_mode || 'dry-run'}`,
    `CPU total speedup vs FPGA: ${Number(speedup.total_x || 0).toFixed(3)}x`,
    `Kernel speedup: ${Number(speedup.kernel_x || 0).toFixed(3)}x`,
    '',
    'CPU Summary:',
    data.cpu?.summary || '(none)',
    '',
    'FPGA Summary:',
    data.fpga?.summary || '(none)',
  ].join('\n');

  if (data.cpu) {
    cpuSummary.textContent = [
      `Status: ${data.cpu.ok ? 'OK' : 'FAILED'} (rc=${data.cpu.rc})`,
      `Summary: ${data.cpu.summary || '(none)'}`,
      '',
      'Parsed Metrics:',
      prettyMetrics(data.cpu.metrics),
      '',
      'Output Tail:',
      data.cpu.output_tail || '(none)',
    ].join('\n');
  }
  if (data.fpga) {
    fpgaSummary.textContent = [
      `Status: ${data.fpga.ok ? 'OK' : 'FAILED'} (rc=${data.fpga.rc})`,
      `Summary: ${data.fpga.summary || '(none)'}`,
      '',
      'Parsed Metrics:',
      prettyMetrics(data.fpga.metrics),
      '',
      'Output Tail:',
      data.fpga.output_tail || '(none)',
    ].join('\n');
  }

  labMeta.textContent = 'Compare complete.';
}

async function loadSampleSummary() {
  const data = await api('/api/inference/summary');
  sampleCount = Number(data.sample_count || 0);
  if (sampleCount > 0) {
    sampleIndexInput.max = `${sampleCount - 1}`;
    activeSample = clampSampleIndex(Number(sampleIndexInput.value || 0) | 0);
    sampleIndexInput.value = `${activeSample}`;
  }
  sampleMeta.textContent = `Samples: ${sampleCount} | car ${data.class_counts?.car ?? 0}, truck ${data.class_counts?.truck ?? 0}`;
}

async function loadSample(index) {
  if (sampleCount <= 0) {
    sampleMeta.textContent = 'No inference dataset available.';
    return;
  }
  activeSample = clampSampleIndex(index);
  sampleIndexInput.value = `${activeSample}`;
  const data = await api(`/api/inference/sample/${activeSample}`);
  drawSampleRgb(data.rgb_b64, Number(data.width || 32), Number(data.height || 32));
  sampleMeta.textContent = `Sample ${data.sample_index} | ground truth: ${data.true_label_name} (${data.true_label_id})`;
}

async function runVisualInference(mode) {
  if (sampleCount <= 0) {
    sampleMeta.textContent = 'No inference dataset available.';
    return;
  }
  const payload = {
    sample_index: activeSample,
    mode,
    device: `${deviceInput.value || '0'}`.trim() || '0',
    kernel: `${kernelInput.value || 'mlp_u55c'}`.trim() || 'mlp_u55c',
    seed: Number(seedInput.value || 1) | 0,
    xclbin_path: `${xclbinInput.value || ''}`.trim(),
    rebuild_host: false,
  };
  labMeta.textContent = `Running ${mode.toUpperCase()} visual inference...`;
  const data = await api('/api/inference/predict', payload);
  drawSampleRgb(data.rgb_b64, Number(data.width || 32), Number(data.height || 32));
  sampleMeta.textContent = `Sample ${data.sample_index} | ground truth: ${data.true_label_name} (${data.true_label_id})`;
  inferSummary.textContent = [
    `Sample ${data.sample_index}`,
    `Ground truth: ${data.true_label_name} (${data.true_label_id})`,
    '',
    formatInferenceLine('CPU', data.predictions?.cpu, data.true_label_name),
    formatInferenceLine('FPGA', data.predictions?.fpga, data.true_label_name),
  ].join('\n');
  labMeta.textContent = 'Visual inference complete.';
}

async function runRuntimeBench() {
  const payload = {
    mode: `${benchMode.value || 'hw'}`.trim(),
    elements: Math.max(1, Number(elementsInput.value || 100) | 0),
    iterations: Math.max(1, Number(iterationsInput.value || 1) | 0),
    device: `${deviceInput.value || '0'}`.trim() || '0',
    kernel: `${kernelInput.value || 'mlp_u55c'}`.trim() || 'mlp_u55c',
    seed: Number(seedInput.value || 1) | 0,
    xclbin_path: `${xclbinInput.value || ''}`.trim(),
    rebuild_host: false,
  };
  appendLog(`Running benchmark (${payload.mode})...`);
  const data = await api('/api/benchmark', payload);
  appendLog(`Benchmark rc=${data.rc} | ${data.summary || 'no summary'}`);
  appendLog(data.output_tail || '(no output tail)');
}

async function loadHealth() {
  const data = await api('/api/health');
  appendLog(`App: ${data.app}`);
  appendLog(`Default kernel: ${data.default_kernel}`);
  appendLog(`Default xclbin: ${data.default_xclbin || '(unset)'}`);
  updateFinalIterationBanner(data.final_iteration || null);
}

runCpuBtn.addEventListener('click', () => {
  runCpuProfile().catch((err) => {
    labMeta.textContent = `CPU profile failed: ${err.message}`;
  });
});

runFpgaBtn.addEventListener('click', () => {
  runFpgaProfile().catch((err) => {
    labMeta.textContent = `FPGA profile failed: ${err.message}`;
  });
});

runCompareBtn.addEventListener('click', () => {
  runCompare().catch((err) => {
    labMeta.textContent = `Compare failed: ${err.message}`;
  });
});

samplePrevBtn.addEventListener('click', () => {
  loadSample(activeSample - 1).catch((err) => {
    sampleMeta.textContent = `Sample load failed: ${err.message}`;
  });
});

sampleNextBtn.addEventListener('click', () => {
  loadSample(activeSample + 1).catch((err) => {
    sampleMeta.textContent = `Sample load failed: ${err.message}`;
  });
});

sampleLoadBtn.addEventListener('click', () => {
  const idx = Number(sampleIndexInput.value || 0) | 0;
  loadSample(idx).catch((err) => {
    sampleMeta.textContent = `Sample load failed: ${err.message}`;
  });
});

inferCpuBtn.addEventListener('click', () => {
  runVisualInference('cpu').catch((err) => {
    labMeta.textContent = `CPU visual inference failed: ${err.message}`;
  });
});

inferFpgaBtn.addEventListener('click', () => {
  runVisualInference('fpga').catch((err) => {
    labMeta.textContent = `FPGA visual inference failed: ${err.message}`;
  });
});

inferBothBtn.addEventListener('click', () => {
  runVisualInference('both').catch((err) => {
    labMeta.textContent = `CPU+FPGA visual inference failed: ${err.message}`;
  });
});

statusBtn.addEventListener('click', () => {
  api('/api/fpga/status')
    .then((data) => {
      appendLog(`FPGA status rc=${data.rc}`);
      appendLog((data.output || '').split('\n').slice(-30).join('\n'));
    })
    .catch((err) => appendLog(`FPGA status failed: ${err.message}`));
});

programBtn.addEventListener('click', () => {
  api('/api/fpga/program', {
    device: `${deviceInput.value || '0'}`.trim() || '0',
    xclbin_path: `${xclbinInput.value || ''}`.trim(),
  })
    .then((data) => {
      appendLog(`Program rc=${data.rc} | device=${data.resolved_device}`);
      appendLog((data.output || '').split('\n').slice(-30).join('\n'));
    })
    .catch((err) => appendLog(`Program failed: ${err.message}`));
});

benchBtn.addEventListener('click', () => {
  runRuntimeBench().catch((err) => appendLog(`Benchmark failed: ${err.message}`));
});

loadHealth().catch((err) => appendLog(`Health check failed: ${err.message}`));
loadSampleSummary()
  .then(() => loadSample(activeSample))
  .catch((err) => {
    sampleMeta.textContent = `Inference dataset load failed: ${err.message}`;
  });
