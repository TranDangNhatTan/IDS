from __future__ import annotations
import threading, time
import serial
from protocol import *

class UartClient:
    def __init__(self, config, on_result, on_error):
        self.config, self.on_result, self.on_error = config, on_result, on_error
        self.serial = None; self.lock = threading.Lock(); self.seen = set()
    def open(self):
        self.serial = serial.Serial(self.config["uart_port"], self.config["baudrate"], bytesize=8, parity="N", stopbits=1,
                                    timeout=0.05, xonxoff=False, rtscts=False, dsrdtr=False)
    def _read_frame(self, deadline):
        packet = bytearray()
        while time.monotonic() < deadline:
            byte = self.serial.read(1)
            if byte == b"\0":
                if packet: return bytes(packet)
            elif byte: packet.extend(byte)
        return None
    def transact(self, sequence: int, features: list[int]):
        if self.serial is None: raise RuntimeError("UART is not open")
        wire = encode_frame(FEATURE_TYPE, sequence, pack_features(features))
        with self.lock: # exactly one outstanding transaction
            # Sequence is u16 on the wire; permit its legitimate reuse after wrap.
            self.seen.discard(sequence)
            for attempt in range(self.config["uart_retry_limit"] + 1):
                self.serial.write(wire); self.serial.flush()
                deadline = time.monotonic() + self.config["uart_timeout_ms"] / 1000
                while (encoded := self._read_frame(deadline)) is not None:
                    try: frame_type, result_sequence, payload = decode_frame(encoded)
                    except ProtocolError as error: self.on_error("crc", str(error)); continue
                    if frame_type != RESULT_TYPE: self.on_error("protocol", "unexpected FEATURE from FPGA"); continue
                    if result_sequence != sequence: self.on_error("sequence", f"unexpected {result_sequence}"); continue
                    if result_sequence not in self.seen:
                        self.seen.add(result_sequence); self.on_result(result_sequence, decode_result(payload), attempt)
                    return True
                if attempt < self.config["uart_retry_limit"]: self.on_error("retry", f"sequence {sequence}, attempt {attempt + 1}")
            self.on_error("timeout", f"sequence {sequence}"); return False
