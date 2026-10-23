"""Wire codec for protocol contract v1.  All integers are explicitly little endian."""
from __future__ import annotations
import struct

VERSION, FEATURE_TYPE, RESULT_TYPE = 1, 0x10, 0x20
FEATURE_COUNT, FEATURE_WIDTH, FEATURE_PAYLOAD_LEN, RESULT_PAYLOAD_LEN = 28, 22, 77, 7
MAX_FEATURE = (1 << FEATURE_WIDTH) - 1

class ProtocolError(ValueError): pass

def crc16_ccitt_false(data: bytes) -> int:
    crc = 0xffff
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xffff if crc & 0x8000 else (crc << 1) & 0xffff
    return crc

def cobs_encode(data: bytes) -> bytes:
    out, code_index, code = bytearray(b"\0"), 0, 1
    for value in data:
        if value == 0:
            out[code_index] = code; code_index = len(out); out.append(0); code = 1
        else:
            out.append(value); code += 1
            if code == 0xff:
                out[code_index] = code; code_index = len(out); out.append(0); code = 1
    out[code_index] = code
    return bytes(out)

def cobs_decode(data: bytes) -> bytes:
    if not data: raise ProtocolError("empty COBS frame")
    out, index = bytearray(), 0
    while index < len(data):
        code = data[index]
        if not code or index + code > len(data) + 1: raise ProtocolError("invalid COBS")
        index += 1; out.extend(data[index:index + code - 1]); index += code - 1
        if code != 0xff and index < len(data): out.append(0)
    return bytes(out)

def pack_features(features: list[int]) -> bytes:
    if len(features) != FEATURE_COUNT: raise ProtocolError("need exactly 28 features")
    stream = 0
    for index, value in enumerate(features):
        if not isinstance(value, int) or not 0 <= value <= MAX_FEATURE:
            raise ProtocolError(f"feature {index} outside unsigned 22-bit range")
        stream |= value << (FEATURE_WIDTH * index)
    return stream.to_bytes(FEATURE_PAYLOAD_LEN, "little")

def unpack_features(payload: bytes) -> list[int]:
    if len(payload) != FEATURE_PAYLOAD_LEN: raise ProtocolError("FEATURE payload must be 77 bytes")
    stream = int.from_bytes(payload, "little")
    return [(stream >> (FEATURE_WIDTH * i)) & MAX_FEATURE for i in range(FEATURE_COUNT)]

def encode_frame(frame_type: int, sequence: int, payload: bytes) -> bytes:
    if frame_type not in (FEATURE_TYPE, RESULT_TYPE): raise ProtocolError("unsupported frame type")
    if not 0 <= sequence <= 0xffff: raise ProtocolError("sequence outside u16")
    required = FEATURE_PAYLOAD_LEN if frame_type == FEATURE_TYPE else RESULT_PAYLOAD_LEN
    if len(payload) != required: raise ProtocolError("invalid payload length")
    body = struct.pack("<BBHH", VERSION, frame_type, sequence, len(payload)) + payload
    return cobs_encode(body + struct.pack("<H", crc16_ccitt_false(body))) + b"\0"

def decode_frame(wire: bytes) -> tuple[int, int, bytes]:
    if wire.endswith(b"\0"): wire = wire[:-1]
    raw = cobs_decode(wire)
    if len(raw) < 8: raise ProtocolError("frame too short")
    version, frame_type, sequence, length = struct.unpack("<BBHH", raw[:6])
    if version != VERSION: raise ProtocolError("unsupported version")
    if frame_type not in (FEATURE_TYPE, RESULT_TYPE): raise ProtocolError("unsupported type")
    required = FEATURE_PAYLOAD_LEN if frame_type == FEATURE_TYPE else RESULT_PAYLOAD_LEN
    if length != required or len(raw) != 6 + length + 2: raise ProtocolError("invalid frame length")
    expected, = struct.unpack("<H", raw[-2:])
    if crc16_ccitt_false(raw[:-2]) != expected: raise ProtocolError("CRC mismatch")
    return frame_type, sequence, raw[6:-2]

def decode_result(payload: bytes) -> dict:
    if len(payload) != RESULT_PAYLOAD_LEN: raise ProtocolError("RESULT payload must be 7 bytes")
    class_id, leaf_node, step_count, error_code, model_version = struct.unpack("<BHB BH", payload)
    return {"class_id": class_id, "leaf_node": leaf_node, "step_count": step_count,
            "error_code": error_code, "model_version": model_version}
