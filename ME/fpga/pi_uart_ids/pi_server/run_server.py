from __future__ import annotations
import json, logging, sys, threading, time, tempfile
import socket
from collections import deque
from logging.handlers import RotatingFileHandler
from pathlib import Path
from datetime import datetime, timezone
from app import make_app
from capture import EthernetCapture
from features import FeatureMapper
from uart_client import UartClient
from model_loader import ModelLoader, load_model

ROOT = Path(__file__).resolve().parent
class State:
    def __init__(self):
        self.data = {"capture_count":0,"capture_bytes":0,"accepted_uart_records":0,"retries":0,"timeouts":0,"crc_errors":0,"result_count":0,"last_sequence":None,"class_id":None,"leaf_node":None,"step_count":None,"error_code":None,"model_version":None,"last_capture_at":None,"last_result_at":None,"last_source":None,"last_error":None,"fpga_trace":None,"model":{"state":"inactive","accepted_count":0,"node_count":1273,"crc32":None,"active_version":None,"detail":"Upload required after FPGA boot"},"connections":{"capture":{"state":"starting","label":"Starting","detail":"Opening raw Ethernet socket"},"uart":{"state":"starting","label":"Starting","detail":"Opening serial device"}}}
        self.lock=threading.Lock(); self.captures=deque(); self.results=deque(); self.events=deque(maxlen=30)
    def update(self, **items):
        with self.lock: self.data.update(items)
    def increment(self, name):
        with self.lock: self.data[name] += 1
    def capture(self, byte_count):
        with self.lock:
            self.data["capture_count"] += 1; self.data["capture_bytes"] += byte_count; self.captures.append((time.monotonic(), byte_count))
    def result(self):
        with self.lock:
            self.data["result_count"] += 1; self.data["accepted_uart_records"] += 1; self.results.append(time.monotonic())
    def event(self, message, level="info"):
        with self.lock: self.events.append({"time":datetime.now(timezone.utc).isoformat(),"message":message,"level":level})
    def snapshot(self):
        with self.lock:
            now=time.monotonic()
            while self.captures and self.captures[0][0] < now-10: self.captures.popleft()
            while self.results and self.results[0] < now-10: self.results.popleft()
            view=dict(self.data); view["connections"]={key:dict(value) for key,value in self.data["connections"].items()}; view["events"]=list(self.events)
            view["capture_rate_pps"]=len(self.captures)/10; view["result_rate_pps"]=len(self.results)/10; view["capture_bytes_per_second"]=sum(item[1] for item in self.captures)/10
            return view
class ModelService:
    def __init__(self, root, config, uart, state, event): self.root,self.config,self.uart,self.state,self.event=root,config,uart,state,event;self.lock=threading.Lock()
    def save_and_start(self, upload):
        if not self.lock.acquire(blocking=False): raise ValueError("model upload is already running")
        target=self.root/self.config["model_storage_path"];target.parent.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=target.parent,delete=False) as temp: upload.save(temp); temporary=Path(temp.name)
        try: load_model(temporary)
        except Exception: temporary.unlink(missing_ok=True);self.lock.release();raise
        temporary.replace(target); self.start(target,locked=True); return {"accepted":True,"message":"model stored; UART upload started"}
    def start(self,path=None,locked=False):
        if not locked and not self.lock.acquire(blocking=False): return False
        path=Path(path or self.root/self.config["model_path"])
        def progress(stage,count,total,crc,version=None): self.state.update(model={"state":stage,"accepted_count":count,"node_count":total,"crc32":f"{crc:08x}","active_version":version,"detail":f"{count}/{total} nodes"})
        def work():
            self.uart.model_active=False
            try:
                self.state.update(model={"state":"starting","accepted_count":0,"node_count":self.config["expected_node_count"],"crc32":None,"active_version":None,"detail":path.name})
                reply=ModelLoader(self.uart,self.config["model_version"],progress,self.event).upload(path);self.uart.model_active=True;self.event("model_active",version=reply["model_version"])
            except Exception as error:self.state.update(model={"state":"error","accepted_count":0,"node_count":self.config["expected_node_count"],"crc32":None,"active_version":None,"detail":str(error)});self.event("model_error",detail=str(error))
            finally:self.lock.release()
        threading.Thread(target=work,daemon=True).start();return True
def main():
    config = json.loads((ROOT / "config.json").read_text())
    log_file = ROOT / config["log_path"]; log_file.parent.mkdir(exist_ok=True)
    logger = logging.getLogger("pi_ids"); logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(log_file, maxBytes=config["log_max_bytes"], backupCount=config["log_backup_count"])
    handler.setFormatter(logging.Formatter("%(message)s")); logger.addHandler(handler)
    state, mapper = State(), FeatureMapper()
    def event(kind, **fields):
        logger.info(json.dumps({"time":datetime.now(timezone.utc).isoformat(),"event":kind,**fields}))
        level = "error" if "error" in kind or kind in ("uart_timeout", "uart_crc") else "warn" if kind == "uart_retry" else "info"
        state.event(kind.replace("_", " ") + (f": {fields['detail']}" if "detail" in fields else ""), level)
    def result(sequence, value, retries): state.result(); state.update(last_sequence=sequence,last_result_at=datetime.now(timezone.utc).isoformat(),**value); event("result",sequence=sequence,**value,retries=retries)
    def uart_error(kind, detail):
        if kind == "retry": state.increment("retries")
        elif kind == "timeout": state.increment("timeouts")
        elif kind == "crc": state.increment("crc_errors")
        if kind != "tx": state.update(last_error=detail)
        event("uart_"+kind,detail=detail)
    def uart_trace(value):
        state.update(fpga_trace=value)
        event("fpga_trace",detail=f"rx={value['rx_bytes']} frames={value['valid_frames']} flags=0x{value['error_flags']:02x} nodes={value['accepted_nodes']} upload_errors={value['upload_errors']}")
    uart = UartClient(config, result, uart_error, uart_trace)
    try: uart.open()
    except Exception as error: print(f"UART open failed ({config['uart_port']}): {error}", file=sys.stderr); return 2
    state.update(connections={**state.data["connections"], "uart":{"state":"connected","label":"Connected · 115200 8N1","detail":config["uart_port"]}})
    # Test this before starting Flask: a configured address must exist locally.
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.bind((config["pi_data_ip"], config["dashboard_port"])); probe.close()
    except OSError as error:
        print(f"Dashboard cannot bind {config['pi_data_ip']}:{config['dashboard_port']}: {error}. "
              "Set pi_data_ip to an address assigned on the Pi data interface, or assign that address first.", file=sys.stderr)
        return 3
    def record(packet):
        state.capture(packet.frame_len); state.update(last_sequence=packet.sequence,last_capture_at=datetime.now(timezone.utc).isoformat(),last_source=packet.src_ip); event("capture",sequence=packet.sequence,source=packet.src_ip)
        threading.Thread(target=uart.transact,args=(packet.sequence & 0xffff,mapper.map(packet)),daemon=True).start()
    def capture_error(error):
        state.update(connections={**state.data["connections"], "capture":{"state":"degraded","label":"Capture error","detail":str(error)}})
        event("capture_error",detail=str(error))
    capture = EthernetCapture(config["interface"], config["promiscuous_mode"], record, capture_error)
    try: capture.open()
    except Exception as error:
        print(f"Capture startup failed: {error}", file=sys.stderr)
        return 4
    state.update(connections={**state.data["connections"], "capture":{"state":"connected","label":"Listening · UDP 40000","detail":f"{config['interface']} · IDSRAW1"}})
    model_service = ModelService(ROOT, config, uart, state, event)
    if config.get("auto_load_model"): model_service.start()
    print(f"UART {config['uart_port']} at {config['baudrate']} 8N1; dashboard http://{config['pi_data_ip']}:{config['dashboard_port']}")
    threading.Thread(target=capture.run, daemon=True).start()
    make_app(state, model_service).run(host=config["pi_data_ip"], port=config["dashboard_port"], threaded=True)
if __name__ == "__main__": raise SystemExit(main())
