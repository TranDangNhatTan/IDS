#!/usr/bin/env python3
"""
Laptop B — Visual Web Control Station for IDS traffic generator.

Flask web server providing a modern dashboard to configure, simulate,
inspect, and monitor raw packet transmissions to the Pi.

Run:  python app.py
Open:  http://localhost:5000
"""

import json
import os
import sys
from pathlib import Path

from flask import Flask, jsonify, request, render_template_string

# Add parent dir so we can import our generator module
sys.path.insert(0, str(Path(__file__).parent))
from send_raw_traffic import (
    GeneratorConfig,
    TrafficGenerator,
    build_packet,
    decode_packet,
    list_interfaces,
    run_diagnostics,
    check_admin,
    check_npcap,
    DST_PORT,
)

# ──────────────────────── App setup ───────────────────────────────────────
app = Flask(__name__)

CONFIG_PATH = str(Path(__file__).parent / "config.json")

# Load or create default config
if os.path.exists(CONFIG_PATH):
    _cfg = GeneratorConfig.from_file(CONFIG_PATH)
else:
    _cfg = GeneratorConfig()
    _cfg.save(CONFIG_PATH)

_generator = TrafficGenerator()


# ──────────────────────── REST API ────────────────────────────────────────
@app.route("/api/config", methods=["GET"])
def api_get_config():
    """Return current config and detected adapters."""
    adapters = [
        {"name": i.name, "description": i.description, "mac": i.mac, "ip": i.ip}
        for i in list_interfaces()
    ]
    return jsonify({"config": _cfg.to_dict(), "adapters": adapters})


@app.route("/api/config", methods=["POST"])
def api_set_config():
    """Update runtime config fields."""
    global _cfg
    data = request.get_json(force=True)
    for key, val in data.items():
        if key in GeneratorConfig.__dataclass_fields__:
            expected_type = type(getattr(_cfg, key))
            try:
                setattr(_cfg, key, expected_type(val))
            except (ValueError, TypeError):
                pass
    # Force dst_port
    _cfg.dst_port = DST_PORT
    _cfg.save(CONFIG_PATH)
    return jsonify({"ok": True, "config": _cfg.to_dict()})


@app.route("/api/interfaces", methods=["GET"])
def api_interfaces():
    """List detected network adapters."""
    ifaces = [
        {"name": i.name, "description": i.description, "mac": i.mac, "ip": i.ip}
        for i in list_interfaces()
    ]
    return jsonify({"interfaces": ifaces})


@app.route("/api/verify", methods=["POST"])
def api_verify():
    """Run network diagnostics."""
    diag = run_diagnostics(_cfg)
    return jsonify(diag)


@app.route("/api/dry-run", methods=["POST"])
def api_dry_run():
    """Build a sample frame and return decoded info without sending."""
    data = request.get_json(force=True) if request.is_json else {}
    seq = data.get("start_sequence", _cfg.start_sequence)
    payload_size = data.get("payload_size", _cfg.payload_size)

    temp_cfg = GeneratorConfig(**_cfg.to_dict())
    temp_cfg.payload_size = int(payload_size)
    pkt = build_packet(temp_cfg, int(seq))
    info = decode_packet(pkt)
    # Add formatted hex dump
    raw = bytes(pkt)
    lines = []
    for offset in range(0, len(raw), 16):
        chunk = raw[offset : offset + 16]
        hex_part = " ".join(f"{b:02x}" for b in chunk)
        ascii_part = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{offset:04x}  {hex_part:<48s}  {ascii_part}")
    info["hex_dump"] = "\n".join(lines)
    return jsonify(info)


@app.route("/api/send", methods=["POST"])
def api_send():
    """Start packet transmission."""
    data = request.get_json(force=True) if request.is_json else {}
    count = int(data.get("count", _cfg.packet_count))
    rate = float(data.get("rate", _cfg.rate_pps))
    start_seq = int(data.get("start_sequence", _cfg.start_sequence))
    ok, msg = _generator.start(_cfg, count=count, rate=rate, start_seq=start_seq)
    return jsonify({"ok": ok, "message": msg})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    """Stop active transmission immediately."""
    _generator.stop()
    return jsonify({"ok": True, "message": "Stop signal sent."})


@app.route("/api/status", methods=["GET"])
def api_status():
    """Return live transmission status."""
    return jsonify(_generator.get_status())


# ──────────────────────── Dashboard HTML ──────────────────────────────────
DASHBOARD_HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>IDS Traffic Generator — Laptop B</title>
<style>
:root {
    --bg: #0f1117;
    --surface: #1a1d28;
    --surface2: #232736;
    --border: #2d3148;
    --text: #e1e4ed;
    --text2: #8b90a5;
    --accent: #6c7cff;
    --accent-hover: #8a96ff;
    --green: #3dd68c;
    --red: #ff5c72;
    --orange: #ffaa44;
    --font: 'Segoe UI', system-ui, -apple-system, sans-serif;
    --mono: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
    --radius: 12px;
}
* { margin:0; padding:0; box-sizing:border-box; }
body {
    font-family: var(--font);
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    padding: 0;
}
.header {
    background: linear-gradient(135deg, #1a1d28 0%, #232736 100%);
    border-bottom: 1px solid var(--border);
    padding: 20px 32px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    position: sticky;
    top: 0;
    z-index: 100;
}
.header h1 {
    font-size: 1.3rem;
    font-weight: 600;
    letter-spacing: -0.02em;
}
.header h1 span { color: var(--accent); }
.health-badges {
    display: flex;
    gap: 10px;
}
.badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    border-radius: 20px;
    font-size: 0.75rem;
    font-weight: 500;
    background: var(--surface2);
    border: 1px solid var(--border);
}
.badge .dot {
    width: 8px; height: 8px;
    border-radius: 50%;
    background: var(--text2);
}
.badge.ok .dot { background: var(--green); }
.badge.fail .dot { background: var(--red); }
.badge.warn .dot { background: var(--orange); }
.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 24px;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
}
@media (max-width: 900px) { .container { grid-template-columns: 1fr; } }
.card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
}
.card-title {
    font-size: 0.85rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text2);
    margin-bottom: 16px;
    display: flex;
    align-items: center;
    gap: 8px;
}
.card-title .icon { font-size: 1.1rem; }
.full-width { grid-column: 1 / -1; }
label {
    display: block;
    font-size: 0.8rem;
    color: var(--text2);
    margin-bottom: 4px;
    font-weight: 500;
}
input, select {
    width: 100%;
    padding: 8px 12px;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: var(--surface2);
    color: var(--text);
    font-size: 0.85rem;
    font-family: var(--font);
    outline: none;
    transition: border-color 0.2s;
}
input:focus, select:focus { border-color: var(--accent); }
input[type="range"] {
    -webkit-appearance: none;
    height: 6px;
    background: var(--border);
    border-radius: 3px;
    border: none;
    padding: 0;
}
input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 18px; height: 18px;
    border-radius: 50%;
    background: var(--accent);
    cursor: pointer;
}
.form-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
}
.form-row { margin-bottom: 12px; }
.range-val {
    font-family: var(--mono);
    font-size: 0.9rem;
    color: var(--accent);
    font-weight: 600;
}
button {
    padding: 10px 20px;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: var(--surface2);
    color: var(--text);
    font-size: 0.85rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s;
    font-family: var(--font);
}
button:hover { background: var(--border); }
button.primary {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
}
button.primary:hover { background: var(--accent-hover); }
button.danger {
    background: var(--red);
    border-color: var(--red);
    color: #fff;
}
button.danger:hover { opacity: 0.85; }
.btn-group {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    margin-top: 12px;
}
.progress-container {
    margin-top: 16px;
}
.progress-bar-bg {
    width: 100%;
    height: 10px;
    background: var(--surface2);
    border-radius: 5px;
    overflow: hidden;
}
.progress-bar {
    height: 100%;
    background: linear-gradient(90deg, var(--accent), var(--green));
    border-radius: 5px;
    transition: width 0.3s;
    width: 0%;
}
.progress-text {
    font-family: var(--mono);
    font-size: 0.8rem;
    color: var(--text2);
    margin-top: 6px;
}
.log-container {
    max-height: 400px;
    overflow-y: auto;
    font-family: var(--mono);
    font-size: 0.75rem;
    line-height: 1.8;
    background: var(--bg);
    border-radius: 8px;
    padding: 12px;
    border: 1px solid var(--border);
}
.log-container::-webkit-scrollbar { width: 6px; }
.log-container::-webkit-scrollbar-track { background: transparent; }
.log-container::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
.log-entry {
    display: grid;
    grid-template-columns: 70px 60px 50px 1fr 60px;
    gap: 8px;
    padding: 2px 0;
    border-bottom: 1px solid var(--border);
}
.log-entry:last-child { border-bottom: none; }
.log-entry .time { color: var(--text2); }
.log-entry .seq { color: var(--accent); }
.log-entry .size { color: var(--text2); }
.log-entry .hex { color: var(--text); opacity: 0.6; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.log-entry .status-ok { color: var(--green); }
.log-entry .status-err { color: var(--red); }
.hexdump {
    font-family: var(--mono);
    font-size: 0.75rem;
    line-height: 1.6;
    background: var(--bg);
    border-radius: 8px;
    padding: 12px;
    border: 1px solid var(--border);
    white-space: pre;
    overflow-x: auto;
    max-height: 350px;
    overflow-y: auto;
    color: var(--text2);
}
.diag-result {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 0;
    border-bottom: 1px solid var(--border);
    font-size: 0.85rem;
}
.diag-result:last-child { border-bottom: none; }
.diag-icon { font-size: 1.1rem; }
.diag-ok { color: var(--green); }
.diag-fail { color: var(--red); }
.src-info {
    font-family: var(--mono);
    font-size: 0.8rem;
    color: var(--text2);
    padding: 6px 0;
}
.warning-banner {
    background: rgba(255,170,68,0.1);
    border: 1px solid var(--orange);
    border-radius: 8px;
    padding: 10px 16px;
    font-size: 0.8rem;
    color: var(--orange);
    margin-bottom: 12px;
    display: none;
}
</style>
</head>
<body>

<div class="header">
    <h1>🛡️ IDS <span>Traffic Generator</span> — Laptop B</h1>
    <div class="health-badges">
        <div class="badge" id="badge-npcap"><span class="dot"></span>Npcap</div>
        <div class="badge" id="badge-admin"><span class="dot"></span>Admin</div>
        <div class="badge" id="badge-pi"><span class="dot"></span>Pi Reachable</div>
    </div>
</div>

<div class="container">

    <!-- Adapter & Target Config -->
    <div class="card">
        <div class="card-title"><span class="icon">🔌</span> Adapter &amp; Target Configuration</div>
        <div id="warning-banner" class="warning-banner">
            ⚠ Not running as Administrator or Npcap not found. Sending may fail.
        </div>
        <div class="form-row">
            <label>Network Adapter</label>
            <select id="sel-iface"></select>
        </div>
        <div class="form-grid">
            <div>
                <label>Pi MAC Address</label>
                <input type="text" id="inp-pi-mac" placeholder="dc:a6:32:xx:xx:xx">
            </div>
            <div>
                <label>Pi IP Address</label>
                <input type="text" id="inp-pi-ip" placeholder="192.168.1.100">
            </div>
        </div>
        <div class="src-info" id="src-info">Source: auto-detect</div>
        <button onclick="saveConfig()" style="margin-top:8px">💾 Save Config</button>
    </div>

    <!-- Simulation Controls -->
    <div class="card">
        <div class="card-title"><span class="icon">🎛️</span> Simulation Controls</div>
        <div class="form-row">
            <label>Packet Count: <span class="range-val" id="lbl-count">10</span></label>
            <input type="range" id="rng-count" min="1" max="1000" value="10"
                   oninput="document.getElementById('lbl-count').textContent=this.value">
        </div>
        <div class="form-row">
            <label>Rate (pps): <span class="range-val" id="lbl-rate">5.0</span></label>
            <input type="range" id="rng-rate" min="0.5" max="50" step="0.5" value="5"
                   oninput="document.getElementById('lbl-rate').textContent=parseFloat(this.value).toFixed(1)">
        </div>
        <div class="form-grid">
            <div>
                <label>Start Sequence</label>
                <input type="number" id="inp-start-seq" value="1" min="0">
            </div>
            <div>
                <label>Payload Size (bytes)</label>
                <input type="number" id="inp-payload-size" value="64" min="11">
            </div>
        </div>
        <div class="btn-group">
            <button class="primary" onclick="sendTraffic()">▶ Send Traffic</button>
            <button class="danger" onclick="stopTraffic()">⏹ Stop</button>
            <button onclick="dryRun()">🔍 Dry-Run</button>
            <button onclick="runDiagnostics()">🩺 Diagnostics</button>
            <button onclick="openPiDashboard()">🌐 Pi Dashboard</button>
        </div>
        <div class="progress-container" id="progress-area" style="display:none">
            <div class="progress-bar-bg"><div class="progress-bar" id="progress-bar"></div></div>
            <div class="progress-text" id="progress-text">0 / 0 (0%)</div>
        </div>
    </div>

    <!-- Dry-Run / Diagnostics Output -->
    <div class="card" id="card-inspect" style="display:none">
        <div class="card-title"><span class="icon">🔬</span> <span id="inspect-title">Packet Inspection</span></div>
        <div class="hexdump" id="inspect-output"></div>
    </div>

    <!-- Live Packet Log -->
    <div class="card full-width">
        <div class="card-title"><span class="icon">📡</span> Live Packet Log</div>
        <div class="log-container" id="packet-log">
            <div class="log-entry" style="font-weight:600;color:var(--text2)">
                <span>Time</span><span>Seq</span><span>Size</span><span>Hex Preview</span><span>Status</span>
            </div>
        </div>
    </div>

    <!-- End-to-End Notice -->
    <div class="card full-width" style="text-align:center;color:var(--orange);font-size:0.85rem;">
        ⚠ End-to-End PASS requires matching Pi dashboard / FPGA classification results at
        <a href="#" id="link-pi-dash" style="color:var(--accent)" target="_blank">http://&lt;pi-ip&gt;:8080</a>
    </div>
</div>

<script>
const API = '';
let pollTimer = null;
let lastLogLen = 0;

// ── Init ──
window.addEventListener('DOMContentLoaded', async () => {
    await loadConfig();
    runQuickHealth();
});

async function loadConfig() {
    try {
        const r = await fetch(API + '/api/config');
        const d = await r.json();
        const c = d.config;
        document.getElementById('inp-pi-mac').value = c.pi_mac || '';
        document.getElementById('inp-pi-ip').value = c.pi_ip || '';
        document.getElementById('rng-count').value = c.packet_count || 10;
        document.getElementById('lbl-count').textContent = c.packet_count || 10;
        document.getElementById('rng-rate').value = c.rate_pps || 5;
        document.getElementById('lbl-rate').textContent = parseFloat(c.rate_pps || 5).toFixed(1);
        document.getElementById('inp-start-seq').value = c.start_sequence || 1;
        document.getElementById('inp-payload-size').value = c.payload_size || 64;
        // Populate interface selector
        const sel = document.getElementById('sel-iface');
        sel.innerHTML = '';
        (d.adapters || []).forEach(a => {
            const opt = document.createElement('option');
            opt.value = a.name;
            opt.textContent = a.description ? `${a.name} — ${a.description}` : a.name;
            if (a.name === c.interface) opt.selected = true;
            sel.appendChild(opt);
        });
        // Source info
        const selIface = (d.adapters || []).find(a => a.name === c.interface) || {};
        document.getElementById('src-info').textContent =
            `Source: MAC ${selIface.mac || c.src_mac || 'auto'}  |  IP ${selIface.ip || c.src_ip || 'auto'}`;
        // Pi Dashboard link
        const piUrl = `http://${c.pi_ip}:8080`;
        document.getElementById('link-pi-dash').href = piUrl;
        document.getElementById('link-pi-dash').textContent = piUrl;
    } catch (e) {
        console.error('loadConfig', e);
    }
}

async function saveConfig() {
    const body = {
        interface: document.getElementById('sel-iface').value,
        pi_mac: document.getElementById('inp-pi-mac').value.trim(),
        pi_ip: document.getElementById('inp-pi-ip').value.trim(),
        packet_count: parseInt(document.getElementById('rng-count').value),
        rate_pps: parseFloat(document.getElementById('rng-rate').value),
        start_sequence: parseInt(document.getElementById('inp-start-seq').value),
        payload_size: parseInt(document.getElementById('inp-payload-size').value),
    };
    await fetch(API + '/api/config', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) });
    await loadConfig();
}

async function runQuickHealth() {
    try {
        const r = await fetch(API + '/api/verify', { method:'POST' });
        const d = await r.json();
        setBadge('badge-npcap', d.npcap);
        setBadge('badge-admin', d.admin);
        setBadge('badge-pi', d.ping);
        if (!d.admin || !d.npcap) {
            document.getElementById('warning-banner').style.display = 'block';
        }
    } catch(e) {}
}

function setBadge(id, ok) {
    const el = document.getElementById(id);
    el.classList.remove('ok','fail','warn');
    el.classList.add(ok ? 'ok' : 'fail');
}

async function sendTraffic() {
    await saveConfig();
    const body = {
        count: parseInt(document.getElementById('rng-count').value),
        rate: parseFloat(document.getElementById('rng-rate').value),
        start_sequence: parseInt(document.getElementById('inp-start-seq').value),
    };
    const r = await fetch(API + '/api/send', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) });
    const d = await r.json();
    if (!d.ok) { alert(d.message); return; }
    lastLogLen = 0;
    document.getElementById('progress-area').style.display = 'block';
    startPolling();
}

async function stopTraffic() {
    await fetch(API + '/api/stop', { method:'POST' });
}

function startPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(pollStatus, 400);
}

async function pollStatus() {
    try {
        const r = await fetch(API + '/api/status');
        const d = await r.json();
        // Update progress
        document.getElementById('progress-bar').style.width = d.progress_pct + '%';
        document.getElementById('progress-text').textContent =
            `${d.sent} / ${d.total} (${d.progress_pct}%)  —  ${d.elapsed}s elapsed`;
        // Update log
        const logEl = document.getElementById('packet-log');
        const newEntries = (d.log || []).slice(lastLogLen);
        newEntries.forEach(e => {
            const row = document.createElement('div');
            row.className = 'log-entry';
            const statusCls = (e.status === 'OK') ? 'status-ok' : 'status-err';
            row.innerHTML = `<span class="time">${e.time}</span><span class="seq">${e.seq}</span><span class="size">${e.size}B</span><span class="hex">${e.hex_preview}</span><span class="${statusCls}">${e.status}</span>`;
            logEl.appendChild(row);
        });
        lastLogLen = (d.log || []).length;
        if (newEntries.length) logEl.scrollTop = logEl.scrollHeight;
        if (!d.running) {
            clearInterval(pollTimer);
            pollTimer = null;
        }
    } catch(e) {}
}

async function dryRun() {
    await saveConfig();
    const body = {
        start_sequence: parseInt(document.getElementById('inp-start-seq').value),
        payload_size: parseInt(document.getElementById('inp-payload-size').value),
    };
    const r = await fetch(API + '/api/dry-run', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) });
    const d = await r.json();
    let out = '';
    (d.layers || []).forEach(l => {
        out += `\n━━ ${l.name} ━━\n`;
        for (const [k,v] of Object.entries(l.fields)) out += `  ${k}: ${v}\n`;
    });
    if (d.payload) {
        out += `\n━━ IDS Payload ━━\n`;
        for (const [k,v] of Object.entries(d.payload)) out += `  ${k}: ${v}\n`;
    }
    out += `\nFrame size: ${d.size} bytes\n\n`;
    out += d.hex_dump || d.hex || '';
    showInspect('🔍 Dry-Run Packet Inspection', out);
}

async function runDiagnostics() {
    const r = await fetch(API + '/api/verify', { method:'POST' });
    const d = await r.json();
    let out = '';
    out += `${d.admin ? '✅' : '❌'} Administrator Privileges: ${d.admin}\n`;
    out += `${d.npcap ? '✅' : '❌'} Npcap Driver: ${d.npcap}\n`;
    out += `${d.ping  ? '✅' : '❌'} Pi Reachable (ping ${d.pi_ip}): ${d.ping}\n`;
    out += `${d.pi_dashboard ? '✅' : '❌'} Pi Dashboard (http://${d.pi_ip}:8080): ${d.pi_dashboard}\n`;
    setBadge('badge-npcap', d.npcap);
    setBadge('badge-admin', d.admin);
    setBadge('badge-pi', d.ping);
    if (!d.admin || !d.npcap) document.getElementById('warning-banner').style.display = 'block';
    else document.getElementById('warning-banner').style.display = 'none';
    showInspect('🩺 Network Diagnostics', out);
}

function showInspect(title, text) {
    document.getElementById('card-inspect').style.display = 'block';
    document.getElementById('inspect-title').textContent = title;
    document.getElementById('inspect-output').textContent = text;
}

function openPiDashboard() {
    const ip = document.getElementById('inp-pi-ip').value.trim() || '192.168.1.100';
    window.open(`http://${ip}:8080`, '_blank');
}
</script>

</body>
</html>'''


@app.route("/")
def index():
    return render_template_string(DASHBOARD_HTML)


# ──────────────────────── Main ────────────────────────────────────────────
if __name__ == "__main__":
    port = _cfg.web_server_port or 5000
    print(f"\n  🛡️  IDS Traffic Generator — Laptop B")
    print(f"  Dashboard: http://127.0.0.1:{port}")
    print(f"  Pi target: {_cfg.pi_ip} ({_cfg.pi_mac})")
    if not check_admin():
        print("  ⚠  WARNING: Not running as Administrator — raw sending may fail.")
    if not check_npcap():
        print("  ⚠  WARNING: Npcap not detected — raw sending may fail.")
    print()
    app.run(host="0.0.0.0", port=port, debug=False)
