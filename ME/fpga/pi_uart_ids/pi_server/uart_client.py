from __future__ import annotations
import threading,time
import serial
from protocol import *
class UartClient:
 def __init__(self,config,on_result,on_error,on_trace=lambda _value:None):self.config,self.on_result,self.on_error,self.on_trace=config,on_result,on_error,on_trace;self.serial=None;self.lock=threading.Lock();self.next_sequence=0;self.model_active=False;self.seen=set()
 def open(self):self.serial=serial.Serial(self.config["uart_port"],self.config["baudrate"],bytesize=8,parity="N",stopbits=1,timeout=.05,xonxoff=False,rtscts=False,dsrdtr=False)
 def _read(self,deadline):
  packet=bytearray()
  while time.monotonic()<deadline:
   byte=self.serial.read(1)
   if byte==b"\0":
    if packet:return bytes(packet)
   elif byte:packet.extend(byte)
  return None
 def _sequence(self):self.next_sequence=(self.next_sequence+1)&0xffff;return self.next_sequence
 def request(self,kind,payload,expected,sequence=None):
  if self.serial is None:raise RuntimeError("UART is not open")
  with self.lock:
   sequence=self._sequence() if sequence is None else sequence;wire=encode_frame(kind,sequence,payload)
   for attempt in range(self.config["uart_retry_limit"]+1):
    self.on_error("tx",f"type=0x{kind:02x} seq={sequence} bytes={len(wire)} attempt={attempt+1}")
    self.serial.write(wire);self.serial.flush();deadline=time.monotonic()+self.config["uart_timeout_ms"]/1000
    while (encoded:=self._read(deadline)) is not None:
     try:reply,reply_sequence,body=decode_frame(encoded)
     except ProtocolError as error:self.on_error("crc",str(error));continue
     if reply==TRACE_TYPE:
      self.on_trace(decode_trace(body));continue
     if reply_sequence!=sequence:self.on_error("sequence",f"unexpected {reply_sequence}");continue
     if reply!=expected:self.on_error("protocol",f"expected 0x{expected:02x}, got 0x{reply:02x}");continue
     return body
    if attempt<self.config["uart_retry_limit"]:self.on_error("retry",f"sequence {sequence}, attempt {attempt+1}")
   self.on_error("timeout",f"sequence {sequence}");raise TimeoutError(f"UART request 0x{kind:02x} timed out")
 def transact(self,sequence,features):
  if not self.model_active:self.on_error("model","model inactive; FEATURE held");return False
  try:
   body=self.request(FEATURE_TYPE,pack_features(features),RESULT_TYPE,sequence)
   if sequence not in self.seen:self.seen.add(sequence);self.on_result(sequence,decode_result(body),0)
   return True
  except (ProtocolError,TimeoutError) as error:self.on_error("feature",str(error));return False
