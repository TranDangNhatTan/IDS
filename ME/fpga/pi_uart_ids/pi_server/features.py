"""The sole packet-to-model mapping, matched to the FPGA resource RTL.

Each accepted IDSRAW1 UDP datagram is one synthetic closed UDP flow.  Features
0..8 match ``ids_flow_table_resource.v`` and 9..27 exactly match
``ids_history_window_bram.v:emit_result``.  Rates use Q0.16 round-half-up,
like the hardware (ties-to-even never arises here because the hardware uses
integer arithmetic with the quotient LSB rule; use the same expression below).
The values returned are *already encoded*: f4=/4 and f5=/64, then all fields
are capped by ``ids_feature_quantizer.v``.
"""
from __future__ import annotations
from collections import defaultdict, deque
from dataclasses import dataclass
from time import monotonic

CAPS = (16744,3,70,11,240748,3309,1,3,1,511,100,*([65535]*8),253,255,*([65535]*8))

def _cap(index: int, value: int) -> int: return min(max(0, int(value)), CAPS[index])
def _q016(n: int, d: int) -> int:
    """RTL ratio_q016: saturation and round-to-nearest, ties-to-even."""
    if d <= 0: return 0
    if n >= d: return 65535
    quotient, remainder = divmod(n * 65535, d)
    if remainder * 2 > d or (remainder * 2 == d and quotient & 1): quotient += 1
    return min(65535, quotient)

@dataclass
class PacketRecord:
    sequence: int; src_ip: str; dst_ip: str; src_port: int; dst_port: int; payload: bytes; frame_len: int

class FeatureMapper:
    """Bounded 256-event history, which is the FPGA history-window depth."""
    def __init__(self): self.history = deque(maxlen=256)
    def map(self, p: PacketRecord) -> list[int]:
        now = int(monotonic()); service, flag = _service(p.dst_port), 1  # UDP is OTH in ids_packet_parser.v
        h = list(self.history)
        recent = [x for x in h if now >= x[0] and now - x[0] <= 2]
        same_host = [x for x in h if x[1].dst_ip == p.dst_ip]
        same_service = [x for x in h if x[2] == service]
        recent_host = [x for x in recent if x[1].dst_ip == p.dst_ip]
        recent_service = [x for x in recent if x[2] == service]
        # UDP has neither TCP S-error nor R-error flag, so all those counters are zero.
        time_count, time_srv_count = len(recent_host), len(recent_service)
        host_count, host_srv_count = len(same_host), sum(x[2] == service for x in same_host)
        time_same_srv = sum(x[2] == service for x in recent_host)
        time_diff_srv = time_count - time_same_srv
        time_srv_diff_host = sum(x[1].dst_ip != p.dst_ip for x in recent_service)
        all_srv_diff_host = sum(x[1].dst_ip != p.dst_ip for x in same_service)
        host_same_src_port = sum(x[1].src_port == p.src_port for x in same_host)
        raw = [0, 3, service, flag, p.frame_len, 0, 0, 0, 0,
               time_count, time_srv_count, 0, 0, 0, 0,
               _q016(time_same_srv, time_count), _q016(time_diff_srv, time_count), _q016(time_srv_diff_host, time_srv_count),
               host_count, host_srv_count, _q016(host_srv_count, host_count), _q016(host_count-host_srv_count, host_count),
               _q016(host_same_src_port, host_count), _q016(all_srv_diff_host, len(same_service)),
               0, 0, 0, 0]
        self.history.append((now, p, service, flag))
        # RTL's two special scalings happen here and nowhere else.
        raw[4] >>= 2; raw[5] >>= 6
        return [_cap(i, value) for i, value in enumerate(raw)]

def _service(port: int) -> int:
    # Exact ids_packet_parser.v port_to_service mapping, including UDP/53 special case.
    return {20:21, 21:20, 22:57, 23:61, 25:55, 53:13, 80:25, 110:48, 143:29, 443:27}.get(port, 45)
