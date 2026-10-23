"""Strict codec for Pi–FPGA IDS protocol contract v2."""
from __future__ import annotations
import binascii
import struct
VERSION=2; MODEL_BEGIN,MODEL_WRITE,MODEL_COMMIT,MODEL_STATUS=1,2,3,4
MODEL_BEGIN_ACK,MODEL_WRITE_ACK,MODEL_COMMIT_ACK,MODEL_STATUS_REPLY=0x81,0x82,0x83,0x84
FEATURE_TYPE,RESULT_TYPE=0x10,0x20
FEATURE_COUNT,FEATURE_WIDTH,FEATURE_PAYLOAD_LEN,RESULT_PAYLOAD_LEN=28,22,77,7
NODE_COUNT,NODE_WORD_BYTES=1273,8; MAX_FEATURE=(1<<FEATURE_WIDTH)-1
PAYLOAD_LENGTHS={MODEL_BEGIN:8,MODEL_BEGIN_ACK:5,MODEL_WRITE:10,MODEL_WRITE_ACK:5,MODEL_COMMIT:6,MODEL_COMMIT_ACK:5,MODEL_STATUS:0,MODEL_STATUS_REPLY:5,FEATURE_TYPE:77,RESULT_TYPE:7}
STATUS={0:"OK",1:"BAD_STATE",2:"BAD_INDEX",3:"BAD_COUNT",4:"IMAGE_CRC",5:"BUSY",6:"UNSUPPORTED_VERSION"}
class ProtocolError(ValueError): pass
def crc16_ccitt_false(data:bytes)->int:
 crc=0xffff
 for byte in data:
  crc^=byte<<8
  for _ in range(8): crc=((crc<<1)^0x1021)&0xffff if crc&0x8000 else (crc<<1)&0xffff
 return crc
def cobs_encode(data:bytes)->bytes:
 out,at,code=bytearray(b"\0"),0,1
 for value in data:
  if value==0: out[at]=code;at=len(out);out.append(0);code=1
  else:
   out.append(value);code+=1
   if code==0xff: out[at]=code;at=len(out);out.append(0);code=1
 out[at]=code;return bytes(out)
def cobs_decode(data:bytes)->bytes:
 if not data: raise ProtocolError("empty COBS frame")
 out,index=bytearray(),0
 while index<len(data):
  code=data[index]
  if not code or index+code>len(data)+1: raise ProtocolError("invalid COBS")
  index+=1;out.extend(data[index:index+code-1]);index+=code-1
  if code!=0xff and index<len(data):out.append(0)
 return bytes(out)
def encode_frame(frame_type:int,sequence:int,payload:bytes)->bytes:
 if frame_type not in PAYLOAD_LENGTHS:raise ProtocolError("unsupported type")
 if not 0<=sequence<=0xffff:raise ProtocolError("sequence outside u16")
 if len(payload)!=PAYLOAD_LENGTHS[frame_type]:raise ProtocolError("invalid payload length")
 body=struct.pack("<BBHH",VERSION,frame_type,sequence,len(payload))+payload
 return cobs_encode(body+struct.pack("<H",crc16_ccitt_false(body)))+b"\0"
def decode_frame(wire:bytes)->tuple[int,int,bytes]:
 raw=cobs_decode(wire[:-1] if wire.endswith(b"\0") else wire)
 if len(raw)<8:raise ProtocolError("frame too short")
 version,frame_type,sequence,length=struct.unpack("<BBHH",raw[:6])
 if version!=VERSION:raise ProtocolError("unsupported version")
 if frame_type not in PAYLOAD_LENGTHS:raise ProtocolError("unsupported type")
 if length!=PAYLOAD_LENGTHS[frame_type] or len(raw)!=8+length:raise ProtocolError("invalid frame length")
 if crc16_ccitt_false(raw[:-2])!=struct.unpack("<H",raw[-2:])[0]:raise ProtocolError("CRC mismatch")
 return frame_type,sequence,raw[6:-2]
def pack_features(features:list[int])->bytes:
 if len(features)!=FEATURE_COUNT:raise ProtocolError("need exactly 28 features")
 stream=0
 for index,value in enumerate(features):
  if not isinstance(value,int) or not 0<=value<=MAX_FEATURE:raise ProtocolError(f"feature {index} outside unsigned 22-bit range")
  stream|=value<<(FEATURE_WIDTH*index)
 return stream.to_bytes(FEATURE_PAYLOAD_LEN,"little")
def unpack_features(payload:bytes)->list[int]:
 if len(payload)!=FEATURE_PAYLOAD_LEN:raise ProtocolError("FEATURE payload must be 77 bytes")
 stream=int.from_bytes(payload,"little");return [(stream>>(FEATURE_WIDTH*i))&MAX_FEATURE for i in range(FEATURE_COUNT)]
def image_crc32(words:list[int])->int:
 if len(words)!=NODE_COUNT:raise ProtocolError(f"model requires {NODE_COUNT} nodes")
 return binascii.crc32(b"".join(word.to_bytes(8,"little") for word in words))&0xffffffff
def model_begin_payload(crc32:int,version:int)->bytes:return struct.pack("<HIH",NODE_COUNT,crc32,version)
def model_write_payload(index:int,word:int)->bytes:
 if not 0<=index<NODE_COUNT or not 0<=word<1<<64:raise ProtocolError("invalid model node")
 return struct.pack("<HQ",index,word)
def model_commit_payload(crc32:int,version:int)->bytes:return struct.pack("<IH",crc32,version)
def decode_model_ack(payload:bytes)->dict:
 status,count,version=struct.unpack("<BHH",payload);return {"status":status,"status_name":STATUS.get(status,"UNKNOWN"),"accepted_count":count,"model_version":version}
def decode_write_ack(payload:bytes)->dict:
 status,index,count=struct.unpack("<BHH",payload);return {"status":status,"status_name":STATUS.get(status,"UNKNOWN"),"node_index":index,"accepted_count":count}
def decode_result(payload:bytes)->dict:
 class_id,leaf_node,step_count,error_code,model_version=struct.unpack("<BHBBH",payload);return {"class_id":class_id,"leaf_node":leaf_node,"step_count":step_count,"error_code":error_code,"model_version":model_version}
