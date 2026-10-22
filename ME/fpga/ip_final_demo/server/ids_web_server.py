#!/usr/bin/env python3
"""No-dependency local dashboard for the inline FPGA IDS demo.

Run: python ids_web_server.py --port COM17
Open: http://127.0.0.1:8080
Install pyserial once for real UART: python -m pip install pyserial
"""
from __future__ import annotations
import argparse, csv, json, queue, threading, time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "model" / "node_rom.mem"
state = {"connected": False, "port": None, "baud": 115200, "events": deque(maxlen=200),
         "metrics": {"results": 0, "alerts": 0, "last_class": None, "last_leaf": None,
                     "last_steps": None, "model_version": None, "active_bank": None}}
serial_handle = None
serial_lock = threading.Lock()

def add_event(kind: str, **data: object) -> None:
    state["events"].appendleft({"time": time.strftime("%H:%M:%S"), "kind": kind, **data})

def ingest_line(raw: str) -> None:
    # FPGA line format: IDS,<class hex>,<leaf hex>,<steps hex>,<error>,<bank>,<version hex>
    fields = raw.strip().split(",")
    if len(fields) == 7 and fields[0] == "IDS":
        try:
            event = {"class_id": int(fields[1], 16), "leaf": int(fields[2], 16),
                     "steps": int(fields[3], 16), "error": int(fields[4], 16),
                     "bank": int(fields[5]), "version": int(fields[6], 16)}
        except ValueError:
            add_event("malformed", line=raw); return
        metric = state["metrics"]; metric["results"] += 1
        metric.update(last_class=event["class_id"], last_leaf=event["leaf"], last_steps=event["steps"],
                      model_version=event["version"], active_bank=event["bank"])
        if event["class_id"] != 18: metric["alerts"] += 1
        add_event("classification", **event)
    else:
        add_event("uart", line=raw.strip())

def serial_worker(port: str, baud: int) -> None:
    global serial_handle
    try:
        import serial  # type: ignore
        ser = serial.Serial(port, baudrate=baud, timeout=0.25)
        with serial_lock: serial_handle = ser
        state.update(connected=True, port=port, baud=baud); add_event("connected", port=port)
        while True:
            line = ser.readline().decode("ascii", errors="replace")
            if line: ingest_line(line)
    except Exception as exc:
        state["connected"] = False; add_event("serial_error", detail=str(exc))
    finally:
        with serial_lock: serial_handle = None

def frame(command: int, payload: bytes = b"") -> bytes:
    checksum = command
    for b in payload: checksum ^= b
    return b"\xA5\x5A" + bytes([command]) + payload + bytes([checksum])

def upload_model() -> dict[str, object]:
    if not MODEL.exists(): raise FileNotFoundError(MODEL)
    with serial_lock:
        if serial_handle is None: raise RuntimeError("UART is not connected")
        words = [line.strip() for line in MODEL.read_text(encoding="ascii").splitlines() if line.strip()]
        if len(words) != 1273: raise ValueError(f"expected 1273 model words, got {len(words)}")
        serial_handle.write(frame(0x12))
        for address, word in enumerate(words):
            # RTL protocol stores payload byte 0 as word bits [7:0].
            data = int(word, 16).to_bytes(8, "little")
            payload = address.to_bytes(2, "little") + data
            serial_handle.write(frame(0x10, payload))
        serial_handle.write(frame(0x11))
        serial_handle.flush()
    add_event("model_upload_requested", words=len(words))
    return {"queued_words": len(words), "protocol": "begin / write inactive bank / activate"}

PAGE = b'''<!doctype html><meta charset="utf-8"><title>FPGA IDS</title><style>body{font:15px system-ui;margin:2rem;background:#101820;color:#e8f1f2}button{padding:.5rem}pre{background:#172a32;padding:1rem;overflow:auto}</style><h1>FPGA Inline IDS</h1><p id="connection"></p><button onclick="fetch('/api/model/upload',{method:'POST'}).then(r=>r.json()).then(alert)">Upload node_rom.mem</button><h2>Metrics</h2><pre id="metrics"></pre><h2>UART events</h2><pre id="events"></pre><script>async function tick(){let s=await fetch('/api/state').then(r=>r.json());connection.textContent='UART: '+(s.connected?'connected '+s.port:'disconnected');metrics.textContent=JSON.stringify(s.metrics,null,2);events.textContent=s.events.map(x=>JSON.stringify(x)).join('\n')}setInterval(tick,700);tick()</script>'''
class Handler(BaseHTTPRequestHandler):
    def reply(self, code: int, payload: object, content="application/json") -> None:
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code); self.send_header("Content-Type", content); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if urlparse(self.path).path == "/api/state": self.reply(200, {**state, "events": list(state["events"])})
        elif urlparse(self.path).path == "/": self.reply(200, PAGE, "text/html; charset=utf-8")
        else: self.reply(404, {"error": "not found"})
    def do_POST(self):
        if urlparse(self.path).path == "/api/model/upload":
            try: self.reply(200, upload_model())
            except Exception as exc: self.reply(409, {"error": str(exc)})
        else: self.reply(404, {"error": "not found"})
    def log_message(self, *_): pass
def main() -> None:
    p=argparse.ArgumentParser(); p.add_argument("--port", help="UART COM port, e.g. COM17"); p.add_argument("--baud",type=int,default=115200); p.add_argument("--listen",default="127.0.0.1"); p.add_argument("--http-port",type=int,default=8080); a=p.parse_args()
    if a.port: threading.Thread(target=serial_worker,args=(a.port,a.baud),daemon=True).start()
    httpd=ThreadingHTTPServer((a.listen,a.http_port),Handler); print(f"Dashboard: http://{a.listen}:{a.http_port}"); httpd.serve_forever()
if __name__ == "__main__": main()

