from __future__ import annotations

LOGS_PAGE_HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>LifeOrganize Backend Logs</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f3;
      --panel: #ffffff;
      --text: #121411;
      --muted: #72766f;
      --line: #dcdfd7;
      --accent: #0f8f94;
      --good: #0f7b45;
      --warn: #a46200;
      --bad: #bd2d2d;
      --terminal: #111713;
      --terminal-text: #e8eee8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background: var(--bg);
    }
    main {
      display: grid;
      grid-template-columns: 320px minmax(0, 1fr);
      min-height: 100vh;
    }
    aside {
      border-right: 1px solid var(--line);
      background: #fbfcf8;
      padding: 24px;
    }
    section {
      padding: 24px;
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    h1 {
      font-size: 26px;
      margin: 0 0 8px;
      letter-spacing: 0;
    }
    h2 {
      font-size: 15px;
      margin: 22px 0 10px;
      letter-spacing: 0;
    }
    p {
      color: var(--muted);
      line-height: 1.45;
      margin: 0;
    }
    label {
      color: var(--muted);
      display: block;
      font-size: 12px;
      font-weight: 700;
      margin: 14px 0 6px;
      text-transform: uppercase;
    }
    input, select, button {
      border-radius: 6px;
      border: 1px solid var(--line);
      font: inherit;
    }
    input, select {
      background: #fff;
      color: var(--text);
      padding: 10px 12px;
      width: 100%;
    }
    button {
      background: #fff;
      color: var(--text);
      cursor: pointer;
      font-weight: 700;
      padding: 10px 12px;
    }
    button.primary {
      background: var(--accent);
      border-color: var(--accent);
      color: white;
    }
    button:disabled { cursor: not-allowed; opacity: 0.5; }
    .button-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin-top: 10px;
    }
    .status-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(150px, 1fr));
      gap: 12px;
    }
    .metric {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px;
    }
    .metric span {
      color: var(--muted);
      display: block;
      font-size: 12px;
      font-weight: 700;
      margin-bottom: 6px;
      text-transform: uppercase;
    }
    .metric strong {
      font-size: 22px;
    }
    .toolbar {
      align-items: end;
      display: grid;
      grid-template-columns: minmax(220px, 1fr) 140px 140px;
      gap: 10px;
    }
    .log-panel {
      background: var(--terminal);
      border: 1px solid #29312d;
      border-radius: 8px;
      flex: 1;
      min-height: 460px;
      overflow: auto;
      padding: 14px;
    }
    .log-line {
      border-bottom: 1px solid rgba(255,255,255,0.05);
      color: var(--terminal-text);
      display: grid;
      font-family: "SF Mono", Menlo, Consolas, monospace;
      font-size: 12px;
      gap: 10px;
      grid-template-columns: 92px 70px 92px minmax(0, 1fr);
      line-height: 1.45;
      padding: 7px 0;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .log-line.error { color: #ffb4b4; }
    .log-line.warning { color: #ffd88c; }
    .log-time, .log-category, .log-level { color: #9aa59d; }
    .log-details { color: #9fd7cd; display: block; margin-top: 3px; }
    .pill {
      border-radius: 999px;
      display: inline-block;
      font-size: 12px;
      font-weight: 800;
      padding: 4px 8px;
    }
    .pill.live { background: #e8f7ef; color: var(--good); }
    .pill.closed { background: #f8e7e7; color: var(--bad); }
    .help {
      background: #eef6f7;
      border: 1px solid #c8e3e5;
      border-radius: 8px;
      color: #315e62;
      margin-top: 16px;
      padding: 12px;
    }
    @media (max-width: 900px) {
      main { grid-template-columns: 1fr; }
      aside { border-right: 0; border-bottom: 1px solid var(--line); }
      .status-grid { grid-template-columns: 1fr; }
      .toolbar { grid-template-columns: 1fr; }
      .log-line { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
<main>
  <aside>
    <h1>Backend Logs</h1>
    <p>Live LifeOrganize gateway events, request status, and OpenAI call metadata.</p>

    <label for="admin-key">Admin key</label>
    <input id="admin-key" type="password" autocomplete="off" placeholder="LIFE_ORGANIZE_ADMIN_API_KEY">
    <div class="button-row">
      <button class="primary" id="connect">Connect</button>
      <button id="disconnect">Disconnect</button>
    </div>

    <h2>Controls</h2>
    <div class="button-row">
      <button id="refresh">Refresh</button>
      <button id="clear">Clear Buffer</button>
    </div>
    <label for="marker">Marker</label>
    <input id="marker" type="text" placeholder="e.g. testing call tomorrow">
    <button id="mark" style="margin-top: 8px; width: 100%;">Add Marker</button>

    <div class="help">
      Raw user text, API keys, and OpenAI response bodies are not logged here. Use request IDs and timestamps for deeper provider tracing.
    </div>
  </aside>
  <section>
    <div class="status-grid">
      <div class="metric"><span>Stream</span><strong id="stream-state"><span class="pill closed">Disconnected</span></strong></div>
      <div class="metric"><span>Devices</span><strong id="devices">-</strong></div>
      <div class="metric"><span>Requests</span><strong id="requests">-</strong></div>
    </div>

    <div class="toolbar">
      <div>
        <label for="filter">Filter</label>
        <input id="filter" type="search" placeholder="openai, extraction, error, request id">
      </div>
      <div>
        <label for="category">Category</label>
        <select id="category">
          <option value="">All</option>
          <option value="request">request</option>
          <option value="openai">openai</option>
          <option value="admin">admin</option>
        </select>
      </div>
      <div>
        <label for="level">Level</label>
        <select id="level">
          <option value="">All</option>
          <option value="info">info</option>
          <option value="warning">warning</option>
          <option value="error">error</option>
        </select>
      </div>
    </div>

    <div class="log-panel" id="log-panel"></div>
  </section>
</main>
<script>
const keyInput = document.getElementById("admin-key");
const connectButton = document.getElementById("connect");
const disconnectButton = document.getElementById("disconnect");
const refreshButton = document.getElementById("refresh");
const clearButton = document.getElementById("clear");
const markerInput = document.getElementById("marker");
const markButton = document.getElementById("mark");
const filterInput = document.getElementById("filter");
const categoryInput = document.getElementById("category");
const levelInput = document.getElementById("level");
const logPanel = document.getElementById("log-panel");
const streamState = document.getElementById("stream-state");
const devicesMetric = document.getElementById("devices");
const requestsMetric = document.getElementById("requests");

let source = null;
let events = [];
keyInput.value = localStorage.getItem("lifeorganize-admin-key") || "";

function key() {
  return keyInput.value.trim();
}

function authHeaders() {
  return { "x-admin-api-key": key() };
}

function setState(live) {
  streamState.innerHTML = live
    ? '<span class="pill live">Live</span>'
    : '<span class="pill closed">Disconnected</span>';
}

function compactTime(timestamp) {
  const d = new Date(timestamp);
  return Number.isNaN(d.getTime()) ? timestamp : d.toLocaleTimeString();
}

function visibleEvents() {
  const q = filterInput.value.trim().toLowerCase();
  const category = categoryInput.value;
  const level = levelInput.value;
  return events.filter((event) => {
    if (category && event.category !== category) return false;
    if (level && event.level !== level) return false;
    if (!q) return true;
    return JSON.stringify(event).toLowerCase().includes(q);
  });
}

function render() {
  const rows = visibleEvents();
  logPanel.innerHTML = "";
  for (const event of rows) {
    const row = document.createElement("div");
    row.className = "log-line " + event.level;

    const time = document.createElement("span");
    time.className = "log-time";
    time.textContent = compactTime(event.timestamp);

    const level = document.createElement("span");
    level.className = "log-level";
    level.textContent = event.level;

    const category = document.createElement("span");
    category.className = "log-category";
    category.textContent = event.category;

    const body = document.createElement("span");
    body.textContent = event.message;
    const details = document.createElement("span");
    details.className = "log-details";
    details.textContent = Object.keys(event.details || {}).length
      ? JSON.stringify(event.details)
      : "";
    body.appendChild(details);

    row.append(time, level, category, body);
    logPanel.appendChild(row);
  }
  if (!rows.length) {
    logPanel.textContent = "No matching logs.";
  }
  logPanel.scrollTop = logPanel.scrollHeight;
}

function addEvent(event) {
  events = [...events.filter((item) => item.id !== event.id), event]
    .sort((a, b) => a.id - b.id)
    .slice(-500);
  render();
}

async function refreshUsage() {
  const res = await fetch("/api/admin/usage", { headers: authHeaders() });
  if (!res.ok) throw new Error("usage " + res.status);
  const data = await res.json();
  devicesMetric.textContent = data.devices;
  requestsMetric.textContent = data.requests;
}

async function refreshLogs() {
  const res = await fetch("/api/admin/logs?limit=250", { headers: authHeaders() });
  if (!res.ok) throw new Error("logs " + res.status);
  const data = await res.json();
  events = data.events || [];
  render();
}

async function refreshAll() {
  await Promise.all([refreshUsage(), refreshLogs()]);
}

function connect() {
  if (!key()) {
    alert("Enter the admin key first.");
    return;
  }
  localStorage.setItem("lifeorganize-admin-key", key());
  if (source) source.close();
  fetch("/api/admin/logs/session", {
    method: "POST",
    headers: authHeaders(),
  })
    .then((res) => {
      if (!res.ok) throw new Error("session " + res.status);
      source = new EventSource("/api/admin/logs/stream?limit=100");
      source.addEventListener("open", () => setState(true));
      source.addEventListener("error", () => setState(false));
      source.addEventListener("log", (message) => {
        addEvent(JSON.parse(message.data));
      });
      return refreshAll();
    })
    .catch((err) => addEvent({
      id: Date.now(),
      timestamp: new Date().toISOString(),
      level: "error",
      category: "admin",
      message: "Connect failed",
      details: { error: String(err) },
    }));
}

function disconnect() {
  if (source) source.close();
  source = null;
  setState(false);
}

async function postJSON(url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: { ...authHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(url + " " + res.status);
  return res.json();
}

connectButton.addEventListener("click", connect);
disconnectButton.addEventListener("click", disconnect);
refreshButton.addEventListener("click", () => refreshAll().catch(alert));
clearButton.addEventListener("click", async () => {
  await postJSON("/api/admin/logs/clear", {});
  await refreshLogs();
});
markButton.addEventListener("click", async () => {
  await postJSON("/api/admin/logs/mark", { label: markerInput.value || "Manual marker" });
  markerInput.value = "";
});
filterInput.addEventListener("input", render);
categoryInput.addEventListener("change", render);
levelInput.addEventListener("change", render);

if (key()) connect();
</script>
</body>
</html>
"""
