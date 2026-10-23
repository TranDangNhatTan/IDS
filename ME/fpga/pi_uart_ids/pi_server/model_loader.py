"""Fixed node_rom.hex validation and v2 transactional model upload."""
from __future__ import annotations
from pathlib import Path
from protocol import NODE_COUNT, ProtocolError, image_crc32, model_begin_payload, model_write_payload, model_commit_payload, MODEL_BEGIN, MODEL_BEGIN_ACK, MODEL_WRITE, MODEL_WRITE_ACK, MODEL_COMMIT, MODEL_COMMIT_ACK, decode_model_ack, decode_write_ack

def load_model(path: str | Path) -> list[int]:
    path=Path(path); lines=path.read_text(encoding="ascii").splitlines()
    if len(lines)!=NODE_COUNT: raise ProtocolError(f"{path.name}: need {NODE_COUNT} lines, got {len(lines)}")
    words=[]
    for number,line in enumerate(lines,1):
        value=line.strip()
        if len(value)!=16 or any(c not in "0123456789abcdefABCDEF" for c in value): raise ProtocolError(f"line {number}: expected 16 hex digits")
        words.append(int(value,16))
    return words

class ModelLoader:
    def __init__(self, uart, version:int, progress, event): self.uart,self.version,self.progress,self.event=uart,version,progress,event
    def upload(self, path):
        words=load_model(path); crc=image_crc32(words); self.progress("validating",0,NODE_COUNT,crc)
        begin=decode_model_ack(self.uart.request(MODEL_BEGIN,model_begin_payload(crc,self.version),MODEL_BEGIN_ACK))
        if begin["status"]: raise ProtocolError("MODEL_BEGIN rejected: "+begin["status_name"])
        self.progress("uploading",begin["accepted_count"],NODE_COUNT,crc)
        for index,word in enumerate(words):
            ack=decode_write_ack(self.uart.request(MODEL_WRITE,model_write_payload(index,word),MODEL_WRITE_ACK))
            if ack["status"] or ack["node_index"]!=index: raise ProtocolError(f"node {index} rejected: {ack['status_name']}")
            if index%8==7 or index==NODE_COUNT-1:self.progress("uploading",ack["accepted_count"],NODE_COUNT,crc)
        commit=decode_model_ack(self.uart.request(MODEL_COMMIT,model_commit_payload(crc,self.version),MODEL_COMMIT_ACK))
        if commit["status"] or commit["accepted_count"]!=NODE_COUNT: raise ProtocolError("MODEL_COMMIT rejected: "+commit["status_name"])
        self.progress("active",NODE_COUNT,NODE_COUNT,crc,commit["model_version"]); return commit
