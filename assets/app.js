/* --  State -- */
let selectedDump  = null;
let selectedModel = null;

/* --  Helpers -- */
function formatBytes(bytes) {
  if (bytes < 1024)      return bytes + ' B';
  if (bytes < 1024 ** 2) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1024 ** 3) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  return (bytes / 1024 ** 3).toFixed(2) + ' GB';
}

function showError(msg) {
  const el = document.getElementById('error-block');
  el.textContent = '[ ERR ] ' + msg;
  el.classList.add('visible');
}
function hideError() {
  document.getElementById('error-block').classList.remove('visible');
}
function clearResults() {
  document.getElementById('results').classList.remove('visible');
  hideError();
}

/* --  Drag-and-drop helpers -- */
function cardDragOver(e, cardId) {
  e.preventDefault();
  document.getElementById(cardId).classList.add('dragover');
}
function cardDragLeave(cardId) {
  document.getElementById(cardId).classList.remove('dragover');
}
function cardDrop(e, type) {
  e.preventDefault();
  const cardId = type === 'dump' ? 'dump-card' : 'model-card';
  document.getElementById(cardId).classList.remove('dragover');
  const file = e.dataTransfer.files[0];
  if (!file) return;
  if (type === 'dump')  setDump(file);
  else                  setModel(file);
}

/* --  Dump file -- */
function setDump(file) {
  selectedDump = file;
  document.getElementById('dump-card').classList.add('has-file');
  document.getElementById('dump-strip-name').textContent = file.name;
  document.getElementById('dump-strip-size').textContent = formatBytes(file.size);
  document.getElementById('dump-strip').classList.add('visible');
  document.getElementById('analyze-btn').disabled = false;
  clearResults();
}

function removeDump(e) {
  e.stopPropagation();
  selectedDump = null;
  document.getElementById('file-input').value = '';
  document.getElementById('dump-card').classList.remove('has-file');
  document.getElementById('dump-strip').classList.remove('visible');
  document.getElementById('analyze-btn').disabled = true;
  clearResults();
}

/* --  Model file -- */
function setModel(file) {
  selectedModel = file;
  document.getElementById('model-card').classList.add('has-file');
  document.getElementById('model-strip-name').textContent = file.name;
  document.getElementById('model-strip-size').textContent = formatBytes(file.size);
  document.getElementById('model-strip').classList.add('visible');
}

function removeModel(e) {
  e.stopPropagation();
  selectedModel = null;
  document.getElementById('model-input').value = '';
  document.getElementById('model-card').classList.remove('has-file');
  document.getElementById('model-strip').classList.remove('visible');
}

/* --  Analysis -- */
async function runAnalysis() {
  if (!selectedDump) return;

  const btn = document.getElementById('analyze-btn');
  btn.disabled = true;
  btn.classList.add('scanning');
  document.getElementById('btn-label').textContent = 'SCANNING…';
  clearResults();

  const wrap  = document.getElementById('progress-wrap');
  const bar   = document.getElementById('progress-bar');
  const pct   = document.getElementById('progress-pct');
  const stage = document.getElementById('progress-stage');
  const steps = document.getElementById('progress-steps');
  bar.style.width   = '0%';
  pct.textContent   = '0%';
  stage.textContent = 'INITIALIZING';
  steps.innerHTML   = '';
  wrap.classList.add('visible');

  const formData = new FormData();
  formData.append('dump', selectedDump);
  if (selectedModel) {
    formData.append('model_file', selectedModel);
  }

  const stepEls = {};

  try {
    const resp = await fetch('/analyze', { method: 'POST', body: formData });

    if (!resp.ok) {
      const err = await resp.json().catch(() => ({ detail: 'Unknown error' }));
      showError(err.detail || 'Analysis failed.');
      return;
    }

    const reader  = resp.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });

      const messages = buf.split('\n\n');
      buf = messages.pop();

      for (const msg of messages) {
        const line = msg.trim();
        if (!line.startsWith('data:')) continue;

        let payload;
        try { payload = JSON.parse(line.slice(5).trim()); }
        catch { continue; }

        if (payload.type === 'error') {
          showError(payload.detail);
          break;
        }

        if (payload.type === 'progress') {
          const { step, total, label } = payload;
          const pctVal = Math.round((step / total) * 100);

          bar.style.width   = pctVal + '%';
          pct.textContent   = pctVal + '%';
          stage.textContent = label.toUpperCase();

          Object.values(stepEls).forEach(el => {
            if (el.classList.contains('active')) {
              el.classList.remove('active');
              el.classList.add('done');
              const icon = el.querySelector('.step-icon');
              icon.classList.remove('spin');
              icon.textContent = '\u2713';
            }
          });

          const el = document.createElement('div');
          el.className = 'progress-step active';
          el.innerHTML = `<div class="step-icon spin"></div><span>${label}</span>`;
          steps.appendChild(el);
          requestAnimationFrame(() => el.classList.add('visible'));
          stepEls[label] = el;
        }

        if (payload.type === 'result') {
          bar.style.width   = '100%';
          pct.textContent   = '100%';
          stage.textContent = 'COMPLETE';

          Object.values(stepEls).forEach(el => {
            el.classList.remove('active');
            el.classList.add('done');
            const icon = el.querySelector('.step-icon');
            icon.classList.remove('spin');
            icon.textContent = '\u2713';
          });

          setTimeout(() => {
            wrap.classList.remove('visible');
            renderResults(payload);
          }, 600);
        }
      }
    }
  } catch (err) {
    showError('Network error: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.classList.remove('scanning');
    document.getElementById('btn-label').textContent = 'SCAN MEMORY DUMP';
  }
}

/* --  Render results -- */
function renderResults(data) {
  const verdictEl = document.getElementById('results-verdict');
  if (data.any_detected) {
    verdictEl.textContent = '!  THREATS DETECTED';
    verdictEl.className   = 'results-verdict threat';
  } else {
    verdictEl.textContent = 'v  NO THREATS FOUND';
    verdictEl.className   = 'results-verdict clean';
  }
  document.getElementById('results-filename').textContent = data.filename;

  const grid = document.getElementById('threat-grid');
  grid.innerHTML = '';
  for (const t of data.threats) {
    const cls    = t.detected ? 'detected'      : 'clean';
    const status = t.detected ? 'DETECTED'      : 'CLEAR';
    const badge  = t.detected ? 'HIGH SEVERITY' : 'NO MATCH';
    grid.innerHTML += `
      <div class="threat-card ${cls}">
        <div class="threat-card-label">${t.label}</div>
        <div class="threat-card-status">${status}</div>
        <div><span class="threat-badge">${badge}</span></div>
      </div>`;
  }

  const LABELS = {
    hidden_module_count: 'Hidden Modules',
    has_injection:       'Code Injection Marker',
    high_port_listeners: 'High-Risk Port (4444) Listeners',
    total_sockets:       'Total Sockets',
  };
  const table = document.getElementById('features-table');
  table.innerHTML = '';
  for (const [key, val] of Object.entries(data.features)) {
    table.innerHTML += `
      <tr>
        <td>${LABELS[key] || key}</td>
        <td>${val === -1 ? 'N/A' : val}</td>
      </tr>`;
  }

  document.getElementById('results').classList.add('visible');
}

/* --  Attach event listeners after DOM is ready -- */
document.addEventListener('DOMContentLoaded', () => {
  const fileInput = document.getElementById('file-input');
  if (fileInput) {
    fileInput.addEventListener('change', () => {
      if (fileInput.files && fileInput.files[0]) setDump(fileInput.files[0]);
    });
  }

  const modelInput = document.getElementById('model-input');
  if (modelInput) {
    modelInput.addEventListener('change', () => {
      if (modelInput.files && modelInput.files[0]) setModel(modelInput.files[0]);
    });
  }
});
