(function () {
  const cfg = window.PROJECT_UI_CONFIG || {};
  const themeKey = cfg.themeKey || 'u55c_project_theme';

  const tabButtons = Array.from(document.querySelectorAll('.tab'));
  const tabPanels = Array.from(document.querySelectorAll('.tab-panel'));
  const themeToggle = document.getElementById('theme-toggle');

  const docsSelect = document.getElementById('docs-select');
  const docsRender = document.getElementById('docs-render');
  const docsMeta = document.getElementById('docs-meta');
  const docsToc = document.getElementById('docs-toc');

  const diagramSvg = document.getElementById('diagram-svg');
  const blockDetails = document.getElementById('block-details');
  const flowNotes = document.getElementById('flow-notes');
  const backBtn = document.getElementById('diagram-back-btn');
  const zoomOutBtn = document.getElementById('diagram-zoom-out-btn');
  const zoomInBtn = document.getElementById('diagram-zoom-in-btn');
  const resetBtn = document.getElementById('diagram-reset-btn');
  const breadcrumbEl = document.getElementById('diagram-breadcrumb');
  const zoomReadout = document.getElementById('diagram-zoom-readout');

  const DIAGRAM_MIN_SCALE = 0.02;
  const DIAGRAM_MAX_SCALE = 5.0;
  const DIAGRAM_FIT_MAX_SCALE = 3.2;

  const groupColors = {
    software: '#0f766e',
    platform: '#1d4ed8',
    memory: '#0ea5a6',
    control: '#b45309',
    datapath: '#16a34a',
    compute: '#9333ea',
    observability: '#475569',
    internals: '#9d174d',
  };

  const state = {
    docs: [],
    docsSelectBound: false,
    diagramModel: null,
    viewStack: [],
    panGroup: null,
    scale: 1.0,
    tx: 0,
    ty: 0,
    dragging: false,
    lastX: 0,
    lastY: 0,
    fitRaf: 0,
  };

  function esc(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function slugify(text) {
    return String(text || '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'section';
  }

  function applyTheme(theme) {
    const resolved = theme === 'dark' ? 'dark' : 'light';
    document.body.setAttribute('data-theme', resolved);
    if (themeToggle) {
      themeToggle.textContent = resolved === 'dark' ? 'Light Mode' : 'Dark Mode';
    }
    localStorage.setItem(themeKey, resolved);
    if (state.diagramModel) {
      drawCurrentDiagramView();
    }
  }

  function initTheme() {
    const saved = localStorage.getItem(themeKey);
    applyTheme(saved === 'dark' ? 'dark' : 'light');
    if (themeToggle) {
      themeToggle.addEventListener('click', () => {
        const next = document.body.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        applyTheme(next);
      });
    }
  }

  function setActiveTab(tabKey) {
    tabButtons.forEach((btn) => btn.classList.toggle('active', btn.dataset.tab === tabKey));
    tabPanels.forEach((panel) => panel.classList.toggle('active', panel.id === `tab-${tabKey}`));

    if (tabKey === 'docs') {
      loadDocsList({ preserveSelection: true, autoLoadSelected: true }).catch((err) => {
        if (docsMeta) docsMeta.textContent = `ERROR: ${err.message}`;
      });
    }

    if (tabKey === 'diagram') {
      loadDiagram().then(() => {
        scheduleDiagramFit();
      }).catch((err) => {
        if (flowNotes) flowNotes.textContent = `ERROR: ${err.message}`;
      });
    }
  }

  function initTabs() {
    tabButtons.forEach((button) => {
      button.addEventListener('click', () => setActiveTab(button.dataset.tab));
    });
  }

  async function apiJson(path, options = {}) {
    const resp = await fetch(path, options);
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new Error(data.detail || `${resp.status} ${resp.statusText}`);
    }
    return data;
  }

  function ensureHeadingIds(container) {
    const headings = Array.from(container.querySelectorAll('h1, h2, h3, h4'));
    const used = new Set();

    headings.forEach((h) => {
      if (!h.id) {
        let base = slugify(h.textContent || 'section');
        let id = base;
        let suffix = 2;
        while (used.has(id)) {
          id = `${base}-${suffix}`;
          suffix += 1;
        }
        h.id = id;
      }
      used.add(h.id);
    });

    return headings;
  }

  function scrollDocHeadingIntoView(id) {
    if (!docsRender || !id) return;

    let selector = `#${id}`;
    if (typeof CSS !== 'undefined' && CSS.escape) {
      selector = `#${CSS.escape(id)}`;
    }

    const heading = docsRender.querySelector(selector);
    if (!heading) return;

    const top = heading.offsetTop - 8;
    docsRender.scrollTo({ top, behavior: 'smooth' });
  }

  function renderDocsToc(headings) {
    if (!docsToc) return;

    if (!headings.length) {
      docsToc.innerHTML = '<p class="hint">No section headings found in this document.</p>';
      return;
    }

    const links = headings.map((h) => {
      const level = Number(h.tagName.slice(1));
      return `<a class="toc-link level-${level}" href="#${esc(h.id)}" data-doc-anchor="${esc(h.id)}">${esc(h.textContent || h.id)}</a>`;
    }).join('');

    docsToc.innerHTML = `<nav class="docs-toc-list">${links}</nav>`;

    docsToc.querySelectorAll('[data-doc-anchor]').forEach((link) => {
      link.addEventListener('click', (evt) => {
        evt.preventDefault();
        const id = link.getAttribute('data-doc-anchor');
        scrollDocHeadingIntoView(id);
      });
    });
  }

  async function loadDoc(key) {
    if (!key || !docsRender || !docsMeta) return;
    docsMeta.textContent = `Loading ${key}...`;

    const data = await apiJson('/api/docs/read', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key }),
    });

    docsRender.innerHTML = data.content_html || `<pre>${esc(data.content || '')}</pre>`;
    const headings = ensureHeadingIds(docsRender);
    renderDocsToc(headings);
    docsMeta.textContent = `Loaded ${data.title || key}`;
  }

  async function loadDocsList({ preserveSelection = true, autoLoadSelected = false } = {}) {
    if (!docsSelect || !docsRender || !docsMeta) return;

    const previous = preserveSelection ? docsSelect.value : '';
    docsMeta.textContent = 'Loading docs...';

    const data = await apiJson('/api/docs/list');
    state.docs = Array.isArray(data.docs) ? data.docs : [];

    docsSelect.innerHTML = state.docs
      .map((d) => `<option value="${esc(d.key)}">${esc(d.title || d.key)}</option>`)
      .join('');

    if (!state.docsSelectBound) {
      docsSelect.addEventListener('change', () => {
        loadDoc(docsSelect.value).catch((err) => {
          if (docsMeta) docsMeta.textContent = `ERROR: ${err.message}`;
        });
      });
      state.docsSelectBound = true;
    }

    if (!state.docs.length) {
      docsRender.innerHTML = '<p class="hint">No public documents found for this project.</p>';
      renderDocsToc([]);
      docsMeta.textContent = 'No docs available.';
      return;
    }

    if (previous && state.docs.some((d) => d.key === previous)) {
      docsSelect.value = previous;
    }

    if (!docsSelect.value) {
      docsSelect.value = state.docs[0].key;
    }

    docsMeta.textContent = `${state.docs.length} documents available.`;

    if (autoLoadSelected) {
      await loadDoc(docsSelect.value);
    }
  }

  function currentViewId() {
    return state.viewStack[state.viewStack.length - 1] || '';
  }

  function resolveDiagramView(id) {
    if (!state.diagramModel || !id) return null;
    return state.diagramModel.views?.[id] || null;
  }

  function currentView() {
    return resolveDiagramView(currentViewId());
  }

  function applyDiagramTransform() {
    if (!state.panGroup) return;
    state.panGroup.setAttribute('transform', `translate(${state.tx},${state.ty}) scale(${state.scale})`);
    if (zoomReadout) {
      zoomReadout.textContent = `${Math.round(state.scale * 100)}%`;
    }
  }

  function updateDiagramBreadcrumb() {
    if (!breadcrumbEl || !backBtn) return;
    if (!state.diagramModel || !state.viewStack.length) {
      breadcrumbEl.textContent = '';
      backBtn.disabled = true;
      return;
    }

    const labels = state.viewStack
      .map((id) => resolveDiagramView(id))
      .filter(Boolean)
      .map((v) => v.title || v.id || 'view');

    breadcrumbEl.textContent = labels.join(' / ');
    backBtn.disabled = state.viewStack.length <= 1;
  }

  function renderFlowNotes(view, selectedNode = null) {
    if (!flowNotes) return;
    flowNotes.innerHTML = '';

    const addNote = (noteText) => {
      const li = document.createElement('li');
      li.textContent = noteText;
      flowNotes.appendChild(li);
    };

    if (selectedNode && Array.isArray(selectedNode.notes) && selectedNode.notes.length) {
      selectedNode.notes.forEach(addNote);
      return;
    }

    if (Array.isArray(view?.notes) && view.notes.length) {
      view.notes.forEach(addNote);
      return;
    }

    (view?.edges || []).forEach((edge) => {
      addNote(`${edge.from} -> ${edge.to}${edge.label ? ` (${edge.label})` : ''}`);
    });
  }

  function setNodeDetails(node) {
    if (!blockDetails) return;
    const drillHint = node.drill_to
      ? `<p><strong>Double-click to drill into:</strong> ${esc(node.drill_to)}</p>`
      : '';

    blockDetails.innerHTML = `
      <h3>${esc(node.label || node.id)}</h3>
      ${node.subtitle ? `<p><strong>${esc(node.subtitle)}</strong></p>` : ''}
      <p>${esc(node.details || 'No additional details provided.')}</p>
      ${drillHint}
    `;
  }

  function addWrappedSvgText(parent, {
    x,
    y,
    text,
    fontSize = 14,
    fontWeight = '400',
    fill = '#1f2937',
    maxWidth = 220,
    lineHeight = 1.25,
    maxLines = 8,
  }) {
    const node = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    node.setAttribute('x', String(x));
    node.setAttribute('y', String(y));
    node.setAttribute('font-size', String(fontSize));
    node.setAttribute('font-weight', String(fontWeight));
    node.setAttribute('fill', fill);

    const words = String(text || '').split(/\s+/).filter(Boolean);
    if (!words.length) {
      parent.appendChild(node);
      return y;
    }

    const approxChars = Math.max(8, Math.floor(maxWidth / (fontSize * 0.57)));
    const lines = [];
    let cur = words[0];

    for (let i = 1; i < words.length; i++) {
      const candidate = `${cur} ${words[i]}`;
      if (candidate.length <= approxChars) {
        cur = candidate;
      } else {
        lines.push(cur);
        cur = words[i];
      }
    }
    lines.push(cur);

    if (lines.length > maxLines) {
      lines.length = maxLines;
      const last = lines[maxLines - 1];
      lines[maxLines - 1] = last.length > 1 ? `${last.slice(0, Math.max(1, last.length - 1))}…` : '…';
    }

    lines.forEach((line, idx) => {
      const tspan = document.createElementNS('http://www.w3.org/2000/svg', 'tspan');
      tspan.setAttribute('x', String(x));
      tspan.setAttribute('dy', idx === 0 ? '0' : `${fontSize * lineHeight}`);
      tspan.textContent = line;
      node.appendChild(tspan);
    });

    parent.appendChild(node);
    return y + ((lines.length - 1) * fontSize * lineHeight);
  }

  function edgeAnchor(from, to) {
    const fx = from.x + (from.w / 2);
    const fy = from.y + (from.h / 2);
    const tx = to.x + (to.w / 2);
    const ty = to.y + (to.h / 2);
    const dx = tx - fx;
    const dy = ty - fy;

    if (Math.abs(dx) >= Math.abs(dy)) {
      if (dx >= 0) {
        return {
          orientation: 'horizontal',
          x1: from.x + from.w,
          y1: fy,
          x2: to.x,
          y2: ty,
        };
      }
      return {
        orientation: 'horizontal',
        x1: from.x,
        y1: fy,
        x2: to.x + to.w,
        y2: ty,
      };
    }

    if (dy >= 0) {
      return {
        orientation: 'vertical',
        x1: fx,
        y1: from.y + from.h,
        x2: tx,
        y2: to.y,
      };
    }

    return {
      orientation: 'vertical',
      x1: fx,
      y1: from.y,
      x2: tx,
      y2: to.y + to.h,
    };
  }

  function orthogonalPath(anchors) {
    const { orientation, x1, y1, x2, y2 } = anchors;
    if (orientation === 'horizontal') {
      const midX = Math.round((x1 + x2) / 2);
      const pathLen = Math.abs(midX - x1) + Math.abs(y2 - y1) + Math.abs(x2 - midX);
      return {
        d: `M ${x1} ${y1} L ${midX} ${y1} L ${midX} ${y2} L ${x2} ${y2}`,
        labelX: midX + 4,
        labelY: Math.round((y1 + y2) / 2) - 6,
        pathLen,
      };
    }

    const midY = Math.round((y1 + y2) / 2);
    const pathLen = Math.abs(midY - y1) + Math.abs(x2 - x1) + Math.abs(y2 - midY);
    return {
      d: `M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}`,
      labelX: Math.round((x1 + x2) / 2) + 4,
      labelY: midY - 6,
      pathLen,
    };
  }

  function fitDiagramToViewport(padding = 26) {
    if (!state.panGroup || !diagramSvg) return false;

    const svgRect = diagramSvg.getBoundingClientRect();
    if (!svgRect.width || !svgRect.height) return false;

    const prevTransform = state.panGroup.getAttribute('transform');
    let bbox = null;

    try {
      state.panGroup.removeAttribute('transform');
      bbox = state.panGroup.getBBox();
    } catch (_) {
      bbox = null;
    } finally {
      if (prevTransform) {
        state.panGroup.setAttribute('transform', prevTransform);
      } else {
        state.panGroup.removeAttribute('transform');
      }
    }

    if (!bbox || !Number.isFinite(bbox.width) || !Number.isFinite(bbox.height) || bbox.width <= 0 || bbox.height <= 0) {
      return false;
    }

    const availW = Math.max(40, svgRect.width - (2 * padding));
    const availH = Math.max(40, svgRect.height - (2 * padding));
    const sx = availW / bbox.width;
    const sy = availH / bbox.height;

    state.scale = Math.min(DIAGRAM_FIT_MAX_SCALE, Math.max(DIAGRAM_MIN_SCALE, Math.min(sx, sy)));
    state.tx = padding + ((availW - (bbox.width * state.scale)) / 2) - (bbox.x * state.scale);
    state.ty = padding + ((availH - (bbox.height * state.scale)) / 2) - (bbox.y * state.scale);

    applyDiagramTransform();
    return true;
  }

  function isDiagramViewReady() {
    if (!state.diagramModel) return false;
    const panel = document.getElementById('tab-diagram');
    if (!panel || !panel.classList.contains('active')) return false;
    const rect = diagramSvg.getBoundingClientRect();
    return rect.width > 2 && rect.height > 2;
  }

  function scheduleDiagramFit(padding = 26, maxAttempts = 12) {
    if (!diagramSvg) return;
    if (state.fitRaf) {
      cancelAnimationFrame(state.fitRaf);
      state.fitRaf = 0;
    }

    const attemptFit = (attempt) => {
      state.fitRaf = 0;
      if (!state.panGroup) return;

      if (!isDiagramViewReady()) {
        if (attempt < maxAttempts) {
          state.fitRaf = requestAnimationFrame(() => attemptFit(attempt + 1));
        }
        return;
      }

      if (!fitDiagramToViewport(padding) && attempt < maxAttempts) {
        state.fitRaf = requestAnimationFrame(() => attemptFit(attempt + 1));
      }
    };

    state.fitRaf = requestAnimationFrame(() => attemptFit(0));
  }

  function clientToDiagramUnits(clientX, clientY) {
    if (!diagramSvg) return null;
    const ctm = diagramSvg.getScreenCTM();
    if (!ctm) return null;
    const pt = diagramSvg.createSVGPoint();
    pt.x = clientX;
    pt.y = clientY;
    const inv = ctm.inverse();
    const p = pt.matrixTransform(inv);
    return { x: p.x, y: p.y };
  }

  function getDiagramViewportCenterUnits() {
    const vb = diagramSvg && diagramSvg.viewBox ? diagramSvg.viewBox.baseVal : null;
    if (!vb || !Number.isFinite(vb.width) || !Number.isFinite(vb.height)) {
      return { x: 600, y: 350 };
    }
    return { x: vb.x + (vb.width / 2), y: vb.y + (vb.height / 2) };
  }

  function zoomDiagramAt(zoomFactor, anchorInUnits) {
    if (!state.panGroup) return;

    const prevScale = state.scale;
    const nextScale = Math.max(DIAGRAM_MIN_SCALE, Math.min(DIAGRAM_MAX_SCALE, prevScale * zoomFactor));
    if (Math.abs(nextScale - prevScale) < 1e-6) return;

    const anchor = anchorInUnits || getDiagramViewportCenterUnits();
    const ax = anchor.x;
    const ay = anchor.y;
    const worldX = (ax - state.tx) / prevScale;
    const worldY = (ay - state.ty) / prevScale;

    state.scale = nextScale;
    state.tx = ax - (worldX * state.scale);
    state.ty = ay - (worldY * state.scale);
    applyDiagramTransform();
  }

  function drawCurrentDiagramView() {
    const view = currentView();
    if (!view || !diagramSvg) return;

    const dark = document.body.getAttribute('data-theme') === 'dark';
    const edgeColor = dark ? '#96a8b7' : '#54646d';
    const edgeLabelColor = dark ? '#cbd9e3' : '#36454f';
    const nodeFill = dark ? '#0f1922' : '#ffffff';
    const labelColor = dark ? '#f0f7fc' : '#1f2937';
    const subtitleColor = dark ? '#9db1bf' : '#475569';
    const groupColorFallback = dark ? '#8fb3c9' : '#334155';

    diagramSvg.innerHTML = '';

    const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    defs.innerHTML = `
      <marker id="arrow" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
        <polygon points="0 0, 10 3.5, 0 7" fill="${edgeColor}"></polygon>
      </marker>
    `;
    diagramSvg.appendChild(defs);

    state.panGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    diagramSvg.appendChild(state.panGroup);

    const edgesGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    const nodesGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    state.panGroup.appendChild(edgesGroup);
    state.panGroup.appendChild(nodesGroup);

    const nodeById = {};
    (view.nodes || []).forEach((n) => {
      nodeById[n.id] = n;
    });

    (view.edges || []).forEach((edge) => {
      const from = nodeById[edge.from];
      const to = nodeById[edge.to];
      if (!from || !to) return;

      const route = orthogonalPath(edgeAnchor(from, to));

      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', route.d);
      path.setAttribute('stroke', edgeColor);
      path.setAttribute('stroke-width', '2.5');
      path.setAttribute('fill', 'none');
      path.setAttribute('marker-end', 'url(#arrow)');
      edgesGroup.appendChild(path);

      const showLabel = Boolean(edge.label) && (edge.always_label || (edge.show_label !== false && route.pathLen >= 170));
      if (showLabel) {
        const label = document.createElementNS('http://www.w3.org/2000/svg', 'text');
        label.setAttribute('x', String(route.labelX));
        label.setAttribute('y', String(route.labelY));
        label.setAttribute('font-size', '13');
        label.setAttribute('fill', edgeLabelColor);
        label.setAttribute('text-anchor', 'start');
        label.textContent = edge.label;
        edgesGroup.appendChild(label);
      }
    });

    (view.nodes || []).forEach((node, idx) => {
      const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      g.classList.add('node');
      g.style.cursor = 'pointer';

      const stroke = groupColors[node.group] || groupColorFallback;

      const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x', String(node.x));
      rect.setAttribute('y', String(node.y));
      rect.setAttribute('width', String(node.w));
      rect.setAttribute('height', String(node.h));
      rect.setAttribute('rx', '12');
      rect.setAttribute('fill', nodeFill);
      rect.setAttribute('stroke', stroke);
      rect.setAttribute('stroke-width', '3');
      g.appendChild(rect);

      const showTag = node.w >= 130 && node.h >= 92;
      const maxTextWidth = Math.max(80, node.w - 24);
      const textClipId = `nodeclip-${currentViewId()}-${idx}`.replace(/[^a-zA-Z0-9_-]/g, '_');

      const clip = document.createElementNS('http://www.w3.org/2000/svg', 'clipPath');
      clip.setAttribute('id', textClipId);
      const clipRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      clipRect.setAttribute('x', String(node.x + 10));
      clipRect.setAttribute('y', String(node.y + 8));
      clipRect.setAttribute('width', String(Math.max(30, node.w - 20)));
      clipRect.setAttribute('height', String(Math.max(30, node.h - (showTag ? 26 : 14))));
      clip.appendChild(clipRect);
      defs.appendChild(clip);

      const textGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      textGroup.setAttribute('clip-path', `url(#${textClipId})`);
      g.appendChild(textGroup);

      const labelMaxLines = Math.max(1, Math.floor((node.h * 0.55) / (17 * 1.2)));
      let lastY = addWrappedSvgText(textGroup, {
        x: node.x + 12,
        y: node.y + 27,
        text: node.label || node.id,
        fontSize: 17,
        fontWeight: '700',
        fill: labelColor,
        maxWidth: maxTextWidth,
        lineHeight: 1.2,
        maxLines: labelMaxLines,
      });

      if (node.subtitle) {
        const remainingPx = Math.max(14, (node.y + node.h - (showTag ? 24 : 10)) - (lastY + 14));
        const subtitleMaxLines = Math.max(1, Math.floor(remainingPx / (12 * 1.2)));
        lastY = addWrappedSvgText(textGroup, {
          x: node.x + 12,
          y: lastY + 17,
          text: node.subtitle,
          fontSize: 12,
          fill: subtitleColor,
          maxWidth: maxTextWidth,
          lineHeight: 1.2,
          maxLines: subtitleMaxLines,
        });
      }

      if (showTag) {
        const tag = document.createElementNS('http://www.w3.org/2000/svg', 'text');
        tag.setAttribute('x', String(node.x + 12));
        tag.setAttribute('y', String(node.y + node.h - 12));
        tag.setAttribute('font-size', '11');
        tag.setAttribute('fill', subtitleColor);
        tag.textContent = node.group + (node.drill_to ? ' • double-click to drill' : '');
        g.appendChild(tag);
      }

      g.addEventListener('click', (evt) => {
        evt.stopPropagation();
        setNodeDetails(node);
        renderFlowNotes(view, node);
      });

      g.addEventListener('dblclick', (evt) => {
        evt.stopPropagation();
        if (node.drill_to && resolveDiagramView(node.drill_to)) {
          state.viewStack.push(node.drill_to);
          drawCurrentDiagramView();
        }
      });

      nodesGroup.appendChild(g);
    });

    diagramSvg.onclick = () => {
      if (blockDetails) {
        blockDetails.innerHTML = `<h3>${esc(view.title || 'Diagram')}</h3><p>${esc(view.description || 'Click a block to inspect implementation details.')}</p>`;
      }
      renderFlowNotes(view, null);
    };

    if (blockDetails) {
      blockDetails.innerHTML = `<h3>${esc(view.title || 'Diagram')}</h3><p>${esc(view.description || 'Click a block to inspect implementation details.')}</p>`;
    }

    updateDiagramBreadcrumb();
    renderFlowNotes(view, null);

    state.scale = 1.0;
    state.tx = 0;
    state.ty = 0;
    applyDiagramTransform();
    scheduleDiagramFit();
  }

  function bindDiagramInteractions() {
    if (!diagramSvg) return;

    diagramSvg.addEventListener('wheel', (evt) => {
      evt.preventDefault();
      const anchor = clientToDiagramUnits(evt.clientX, evt.clientY) || getDiagramViewportCenterUnits();
      const zoomFactor = evt.deltaY < 0 ? 1.12 : 0.89;
      zoomDiagramAt(zoomFactor, anchor);
    }, { passive: false });

    diagramSvg.addEventListener('mousedown', (evt) => {
      state.dragging = true;
      state.lastX = evt.clientX;
      state.lastY = evt.clientY;
    });

    window.addEventListener('mouseup', () => {
      state.dragging = false;
    });

    window.addEventListener('mousemove', (evt) => {
      if (!state.dragging || !diagramSvg) return;
      const rect = diagramSvg.getBoundingClientRect();
      const vb = diagramSvg.viewBox ? diagramSvg.viewBox.baseVal : null;
      if (!rect.width || !rect.height || !vb || !Number.isFinite(vb.width) || !Number.isFinite(vb.height)) return;

      const sx = vb.width / rect.width;
      const sy = vb.height / rect.height;
      state.tx += (evt.clientX - state.lastX) * sx;
      state.ty += (evt.clientY - state.lastY) * sy;
      state.lastX = evt.clientX;
      state.lastY = evt.clientY;
      applyDiagramTransform();
    });

    if (backBtn) {
      backBtn.addEventListener('click', () => {
        if (state.viewStack.length <= 1) return;
        state.viewStack.pop();
        drawCurrentDiagramView();
      });
    }

    if (zoomInBtn) {
      zoomInBtn.addEventListener('click', () => {
        zoomDiagramAt(1.15, getDiagramViewportCenterUnits());
      });
    }

    if (zoomOutBtn) {
      zoomOutBtn.addEventListener('click', () => {
        zoomDiagramAt(0.87, getDiagramViewportCenterUnits());
      });
    }

    if (resetBtn) {
      resetBtn.addEventListener('click', () => {
        if (!fitDiagramToViewport()) {
          scheduleDiagramFit();
        }
      });
    }

    window.addEventListener('resize', () => {
      if (!state.diagramModel) return;
      scheduleDiagramFit();
    });
  }

  async function loadDiagram() {
    if (!diagramSvg) return;

    if (!state.diagramModel) {
      const data = await apiJson('/api/diagram');
      state.diagramModel = data;
      state.viewStack = [data.root_view || 'top'];
      drawCurrentDiagramView();
      return;
    }

    if (!state.viewStack.length) {
      state.viewStack = [state.diagramModel.root_view || 'top'];
      drawCurrentDiagramView();
      return;
    }

    drawCurrentDiagramView();
  }

  function init() {
    initTheme();
    initTabs();
    bindDiagramInteractions();
  }

  window.initProjectUI = init;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
