#!/usr/bin/env python3
"""LAN-only FPGA IDS dashboard: MOD1/FTR2 transmit and ACK1/IDS1 receive."""
from __future__ import annotations
import argparse, csv, json, socket, struct, threading, time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"model"/"node_rom.mem"; CLASS_MAP=ROOT.parents[1]/"sw"/"tree"/"dt_fpga_flow28_fixed"/"class_map.json"
LABEL_TO_ID={str(k).lower():int(v) for k,v in json.loads(CLASS_MAP.read_text(encoding="utf-8")).items()}
state={"lan":{"bound":False,"result_port":55003,"target":"255.255.255.255","fpga_port":55002,"rx_packets":0,"parse_errors":0},
 "model":{"uploading":False,"ready":False,"words":0,"version":None,"transfer_id":0,"note":"Upload model over LAN before sending records."},
 "dataset":None,"events":deque(maxlen=300),
 "metrics":{"results":0,"alerts":0,"last_class":None,"last_leaf":None,"last_steps":None,"last_sequence":None,"last_version":None,"fpga_accepted":0,"fpga_dropped":0},
 "benchmark":{"active":False,"status":"idle","note":"Upload CSV then model.","planned":0,"sent":0,"received":0,"correct":0,"incorrect":0,"unmatched":0,"pending":0,"input_rate":None,"result_rate":None,"accuracy":None,"started":None,"finished":None}}
lock=threading.RLock(); udp=None; expected={}
def event(kind,**data):
 with lock: state["events"].appendleft({"time":time.strftime("%H:%M:%S"),"kind":kind,**data})
def bind_udp(port):
 global udp
 if udp: return
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1); s.bind(("0.0.0.0",port)); s.settimeout(.5); udp=s
 state["lan"].update(bound=True,result_port=port); event("lan_receiver_ready",port=port); threading.Thread(target=receive_loop,daemon=True).start()
def send(payload,target,port):
 if not udp: raise RuntimeError("LAN UDP receiver is not running")
 udp.sendto(payload,(target,port))
def parse_reply(data,addr):
 if len(data)>=23 and data[:4]==b"IDS1":
  seq=struct.unpack_from("<I",data,4)[0]; cls=data[8]; leaf=int.from_bytes(data[9:11],"big"); steps=data[11]; err=data[12]; version=int.from_bytes(data[13:15],"big"); accepted=int.from_bytes(data[15:19],"big"); dropped=int.from_bytes(data[19:23],"big")
  with lock:
   m=state["metrics"]; m.update(results=m["results"]+1,last_class=cls,last_leaf=leaf,last_steps=steps,last_sequence=seq,last_version=version,fpga_accepted=accepted,fpga_dropped=dropped)
   if cls!=LABEL_TO_ID["normal"]:m["alerts"]+=1
   b=state["benchmark"]
   if b["active"]:
    label=expected.pop(seq,None)
    if label is None:b["unmatched"]+=1
    else:
     b["received"]+=1; b["correct"]+=int(cls==label); b["incorrect"]+=int(cls!=label); b["pending"]=len(expected)
     if not expected: finish_benchmark("complete")
  event("ids_result",sequence=seq,class_id=cls,leaf=leaf,steps=steps,error=err,source=addr[0])
 elif len(data)>=17 and data[:4]==b"ACK1":
  ready=bool(data[4]); words=int.from_bytes(data[5:7],"big"); version=int.from_bytes(data[7:9],"big"); accepted=int.from_bytes(data[9:13],"big"); dropped=int.from_bytes(data[13:17],"big")
  with lock: state["model"].update(uploading=False,ready=ready and words==1273,words=words,version=version,note=("FPGA ACK received: model active." if ready and words==1273 else f"FPGA rejected model: accepted {words}/1273 words.")); state["metrics"].update(fpga_accepted=accepted,fpga_dropped=dropped)
  event("model_ack",ready=ready,words=words,version=version,source=addr[0])
 else:
  with lock:state["lan"]["parse_errors"]+=1
  event("unknown_udp_reply",bytes=len(data),source=addr[0])
def receive_loop():
 while True:
  try:data,addr=udp.recvfrom(2048); state["lan"]["rx_packets"]+=1; parse_reply(data,addr)
  except socket.timeout:continue
  except OSError:return
  except Exception as exc:event("receiver_error",detail=str(exc))
def finish_benchmark(status):
 b=state["benchmark"]; now=time.time(); elapsed=max(now-(b["started"] or now),1e-6); b["active"]=False;b["finished"]=now;b["status"]=status;b["pending"]=len(expected);b["input_rate"]=round(b["sent"]/elapsed,2);b["result_rate"]=round(b["received"]/elapsed,2); n=b["correct"]+b["incorrect"];b["accuracy"]=round(100*b["correct"]/n,4) if n else None;b["note"]="Valid when pending=0, unmatched=0 and FPGA dropped=0.";event("benchmark_"+status,sent=b["sent"],received=b["received"])
def parse_row(row):
 cells=[x.strip() for x in row if x.strip()]
 if not cells or cells[0].lower() in ("label","class","class_id","target"):return None
 if len(cells)==29:
  key=cells[0].lower(); label=LABEL_TO_ID.get(key)
  if label is None: label=int(cells[0],0)
  cells=cells[1:]
 elif len(cells)==28:label=None
 else:raise ValueError("each row requires label,f0,...,f27 or f0,...,f27")
 values=[int(x,0) for x in cells]
 if len(values)!=28 or any(x<0 or x>0xffffffff for x in values):raise ValueError("features must be 28 uint32 values")
 return label,values
def load_csv(data):
 text=data.decode("utf-8-sig"); rows=[]; invalid=0
 for row in csv.reader(text.splitlines()):
  try:
   item=parse_row(row)
   if item:rows.append(item)
  except Exception:invalid+=1
 if not rows:raise ValueError("CSV has no valid rows")
 with lock:state["dataset"]=rows
 event("csv_loaded",rows=len(rows),invalid=invalid,labels=all(x[0] is not None for x in rows))
 return {"valid_rows":len(rows),"invalid_rows":invalid,"labels_available":all(x[0] is not None for x in rows)}
def upload_model(target,port,rate):
 with lock:
  if state["model"]["uploading"]:raise RuntimeError("model upload is already active")
  ticket=state["model"]["transfer_id"]+1
  state["model"].update(uploading=True,ready=False,words=0,transfer_id=ticket,note="Sending 1,273 BRAM words over LAN; waiting for ACK1 (timeout: 3 s after commit).")
 def worker():
  try:
   words=[int(x.strip(),16) for x in MODEL.read_text(encoding="ascii").splitlines() if x.strip()]
   if len(words)!=1273:raise ValueError("node_rom.mem must contain 1273 words")
   send(b"MOD1\x01",target,port); interval=1.0/rate; deadline=time.perf_counter()
   for address,word in enumerate(words):
    send(b"MOD1\x02"+struct.pack("<H",address)+struct.pack("<Q",word),target,port); deadline+=interval; sleep=deadline-time.perf_counter()
    if sleep>0:time.sleep(sleep)
   send(b"MOD1\x03",target,port); event("model_commit_sent",target=target,words=len(words))
   deadline=time.monotonic()+3.0
   while time.monotonic()<deadline:
    with lock:
     if state["model"]["transfer_id"]!=ticket or state["model"]["ready"]: return
    time.sleep(.05)
   with lock:
    if state["model"]["transfer_id"]==ticket and state["model"]["uploading"]:
     state["model"].update(uploading=False,note="No ACK1 after 3 s. Check: new LAN bitstream, LED1=RX, LED2=model-ready, LED3=TX reply, target broadcast/IP and Windows firewall UDP 55003.")
     event("model_ack_timeout",target=target)
  except Exception as exc:
   with lock:state["model"].update(uploading=False,ready=False,note="Model upload failed: "+str(exc))
   event("model_upload_error",detail=str(exc))
 threading.Thread(target=worker,daemon=True).start(); event("model_upload_started",target=target,rate=rate)
 return {"status":"model_upload_started","expect":"Waiting for ACK1 from FPGA over LAN."}
def stream_rows(target,port,rate):
 with lock:
  rows=state["dataset"]
  if not rows:raise RuntimeError("Upload CSV first")
  if not state["model"]["ready"]:raise RuntimeError("Wait for FPGA ACK1 model confirmation")
  if state["benchmark"]["active"]:raise RuntimeError("benchmark already active")
  expected.clear(); b=state["benchmark"];b.update(active=True,status="sending",note="FTR2 streaming; matching IDS1 by sequence ID.",planned=len(rows),sent=0,received=0,correct=0,incorrect=0,unmatched=0,pending=0,input_rate=None,result_rate=None,accuracy=None,started=time.time(),finished=None)
 def worker():
  try:
   interval=1.0/rate; deadline=time.perf_counter()
   for seq,(label,features) in enumerate(rows):
    with lock:expected[seq]=label
    send(b"FTR2"+struct.pack("<I",seq)+struct.pack("<28I",*features),target,port)
    with lock:b=state["benchmark"];b["sent"]+=1;b["pending"]=len(expected)
    deadline+=interval; sleep=deadline-time.perf_counter()
    if sleep>0:time.sleep(sleep)
   with lock:
    b=state["benchmark"]
    if b["active"]:b["status"]="awaiting_results";b["note"]="All FTR2 frames sent; waiting for IDS1 replies."
   event("feature_stream_sent",records=len(rows),target=target)
  except Exception as exc:
   with lock:state["benchmark"].update(active=False,status="error",note=str(exc))
   event("feature_stream_error",detail=str(exc))
 threading.Thread(target=worker,daemon=True).start(); return {"status":"benchmark_started","records":len(rows),"rate":rate}
def send_one(target,port,features):
 if len(features)!=28 or any(type(x)is not int or x<0 or x>0xffffffff for x in features):raise ValueError("exactly 28 uint32 values required")
 if not state["model"]["ready"]:raise RuntimeError("Wait for model ACK1")
 seq=0xffffffff;send(b"FTR2"+struct.pack("<I",seq)+struct.pack("<28I",*features),target,port);event("single_frame_sent",sequence=seq,target=target);return {"status":"sent","sequence":seq}
def clear_session():
 with lock:
  expected.clear();state["dataset"]=None;state["events"].clear();state["metrics"]={"results":0,"alerts":0,"last_class":None,"last_leaf":None,"last_steps":None,"last_sequence":None,"last_version":None,"fpga_accepted":0,"fpga_dropped":0};state["model"]={"uploading":False,"ready":False,"words":0,"version":None,"transfer_id":state["model"]["transfer_id"]+1,"note":"Session cleared; upload model over LAN."};state["benchmark"]={"active":False,"status":"idle","note":"Session cleared.","planned":0,"sent":0,"received":0,"correct":0,"incorrect":0,"unmatched":0,"pending":0,"input_rate":None,"result_rate":None,"accuracy":None,"started":None,"finished":None}
 event("session_cleared");return {"status":"cleared"}

PAGE='''<!doctype html><meta charset="utf-8"><title>FPGA IDS LAN Core</title><style>:root{--b:#08111b;--p:#102234;--l:#2b4d68;--a:#37aaff}*{box-sizing:border-box}body{margin:0;background:var(--b);color:#edf6fc;font:15px system-ui}.shell{max-width:1180px;margin:auto;padding:28px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}.card{background:var(--p);border:1px solid var(--l);border-radius:12px;padding:16px}.wide{grid-column:span 3}h1{margin:0}h2{font-size:18px;margin:0 0 8px;color:var(--a)}p,small{color:#a9c1d2}label{display:block;margin-top:8px;color:#a9c1d2}input,textarea{width:100%;padding:9px;background:#081521;color:#fff;border:1px solid var(--l);border-radius:6px}textarea{height:68px}button{margin-top:12px;padding:10px 13px;border:0;border-radius:6px;background:var(--a);font-weight:700}button:disabled{opacity:.4}.metrics{display:grid;grid-template-columns:repeat(6,1fr);gap:8px}.metric{background:#081521;border-radius:7px;padding:10px}.metric small{display:block}.metric b{font-size:20px}pre{white-space:pre-wrap;height:180px;overflow:auto;background:#081521;padding:10px}@media(max-width:760px){.grid{grid-template-columns:1fr}.wide{grid-column:span 1}.metrics{grid-template-columns:repeat(2,1fr)}}</style><main class=shell><h1>FPGA IDS — LAN only</h1><p>FTR2 input · IDS1 result · MOD1 upload / ACK1 confirmation</p><button onclick="clearAll()">Clear dashboard session</button><section class=grid><article class=card><h2>1. Model over LAN</h2><label>FPGA IP / broadcast</label><input id=target value="255.255.255.255"><label>FPGA UDP port</label><input id=port value=55002><label>Model packets/s</label><input id=modelrate value=3000><button id=modelBtn onclick="model()">Upload model</button><p id=model></p></article><article class=card><h2>2. Test CSV</h2><small>label,f0,...,f27 or f0,...,f27</small><input id=file type=file accept=.csv><button onclick="csvup()">Upload CSV</button><p id=csv></p></article><article class=card><h2>3. LAN benchmark</h2><label>Records/s</label><input id=rate value=10000><button id=start onclick="start()">Start benchmark</button><p id=run></p></article><article class="card wide"><h2>Performance / accuracy</h2><div class=metrics><div class=metric><small>Planned</small><b id=planned>0</b></div><div class=metric><small>Sent</small><b id=sent>0</b></div><div class=metric><small>IDS1 RX</small><b id=received>0</b></div><div class=metric><small>Accuracy</small><b id=accuracy>—</b></div><div class=metric><small>Input rate</small><b id=inrate>—</b></div><div class=metric><small>FPGA drops</small><b id=drops>0</b></div></div><p id=last></p></article><article class="card wide"><h2>Send one frame</h2><textarea id=one>0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0</textarea><button id=onebtn onclick="one()">Send FTR2 frame</button></article><article class="card wide"><h2>LAN event log</h2><pre id=events></pre></article></section></main><script>const $=x=>document.getElementById(x);async function api(u,o={}){let r=await fetch(u,{method:'POST',...o}),x=await r.json();if(!r.ok)throw Error(x.error);return x}async function model(){try{await api('/api/model',{headers:{'content-type':'application/json'},body:JSON.stringify(cfg())})}catch(e){alert(e)}}async function csvup(){try{let f=$('file').files[0];if(!f)throw Error('Choose CSV');let x=await api('/api/csv',{headers:{'content-type':'application/octet-stream'},body:await f.arrayBuffer()});alert('Loaded '+x.valid_rows+' rows')}catch(e){alert(e)}}function cfg(){return {target:$('target').value,port:+$('port').value,rate:+$('rate').value,modelrate:+$('modelrate').value}}async function start(){try{await api('/api/start',{headers:{'content-type':'application/json'},body:JSON.stringify(cfg())})}catch(e){alert(e)}}async function one(){try{let f=$('one').value.split(',').map(x=>Number(x.trim()));await api('/api/one',{headers:{'content-type':'application/json'},body:JSON.stringify({...cfg(),features:f})})}catch(e){alert(e)}}async function clearAll(){if(confirm('Clear dashboard session? FPGA BRAM is unchanged.'))await api('/api/clear')}function v(i,x){$(i).textContent=x??'—'}async function tick(){let x=await fetch('/api/state').then(r=>r.json()),b=x.benchmark,m=x.metrics;$('model').textContent=x.model.note;$('csv').textContent=x.dataset?x.dataset.rows+' rows loaded':'No CSV';$('run').textContent=b.status+' — '+b.note;v('planned',b.planned);v('sent',b.sent);v('received',b.received);v('accuracy',b.accuracy===null?null:b.accuracy+'%');v('inrate',b.input_rate===null?null:b.input_rate+'/s');v('drops',m.fpga_dropped);$('last').textContent='Last IDS1: seq '+m.last_sequence+' | class '+m.last_class+' | leaf '+m.last_leaf+' | steps '+m.last_steps+' | FPGA accepted '+m.fpga_accepted;$('events').textContent=x.events.map(e=>'['+e.time+'] '+e.kind+' '+JSON.stringify(e)).join('\\n');$('start').disabled=!x.model.ready||b.active;$('onebtn').disabled=!x.model.ready;$('modelBtn').disabled=x.model.uploading}setInterval(tick,500);tick()</script>'''
class Handler(BaseHTTPRequestHandler):
 def reply(self,code,data,content="application/json"):
  body=data.encode() if isinstance(data,str) else json.dumps(data).encode();self.send_response(code);self.send_header("Content-Type",content+"; charset=utf-8");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):
  if self.path=="/":self.reply(200,PAGE,"text/html")
  elif self.path=="/api/state":
   with lock:view={**state,"dataset":({"rows":len(state["dataset"]),"labels":all(row[0] is not None for row in state["dataset"])} if state["dataset"] else None),"events":list(state["events"])}
   self.reply(200,view)
  else:self.reply(404,{"error":"not found"})
 def do_POST(self):
  try:
   size=int(self.headers.get("Content-Length","0"));data=self.rfile.read(size)
   if self.path=="/api/csv":out=load_csv(data)
   elif self.path=="/api/clear":out=clear_session()
   else:
    q=json.loads(data or b"{}");target=str(q.get("target","255.255.255.255"));port=int(q.get("port",55002));rate=float(q.get("rate",10000));
    if not target or not 1<=port<=65535 or rate<=0:raise ValueError("invalid LAN configuration")
    if self.path=="/api/model":out=upload_model(target,port,float(q.get("modelrate",3000)))
    elif self.path=="/api/start":out=stream_rows(target,port,rate)
    elif self.path=="/api/one":out=send_one(target,port,q.get("features",[]))
    else:raise ValueError("not found")
   self.reply(200,out)
  except Exception as exc:self.reply(409,{"error":str(exc)})
 def log_message(self,*args):pass
def main():
 p=argparse.ArgumentParser();p.add_argument("--http-port",type=int,default=8081);p.add_argument("--result-port",type=int,default=55003);a=p.parse_args();bind_udp(a.result_port);print(f"Dashboard: http://127.0.0.1:{a.http_port} | UDP result port: {a.result_port}");ThreadingHTTPServer(("127.0.0.1",a.http_port),Handler).serve_forever()
if __name__=="__main__":main()
