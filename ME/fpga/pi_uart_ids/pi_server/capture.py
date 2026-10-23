"""AF_PACKET capture and strict Ethernet/IPv4/UDP/IDSRAW1 validation."""
from __future__ import annotations
import socket, struct
from features import PacketRecord

class CaptureError(ValueError): pass

def parse_ethernet_frame(frame: bytes, interface: str) -> PacketRecord | None:
    try:
        if len(frame) < 14 or struct.unpack("!H", frame[12:14])[0] != 0x0800: return None
        ip = frame[14:]; ihl = (ip[0] & 15) * 4
        if len(ip) < 20 or ip[0] >> 4 != 4 or ihl < 20 or len(ip) < ihl + 8 or ip[9] != 17: return None
        total = struct.unpack("!H", ip[2:4])[0]
        if total < ihl + 8 or len(ip) < total: return None
        udp = ip[ihl:total]; _, dst_port, udp_len, _ = struct.unpack("!HHHH", udp[:8])
        if dst_port != 40000 or udp_len < 19 or udp_len > len(udp): return None
        payload = udp[8:udp_len]
        if payload[:7] != b"IDSRAW1": return None
        sequence, = struct.unpack("<I", payload[7:11])
        return PacketRecord(sequence, socket.inet_ntoa(ip[12:16]), socket.inet_ntoa(ip[16:20]),
                            struct.unpack("!H", udp[:2])[0], dst_port, payload[11:], len(frame))
    except (IndexError, struct.error): return None

class EthernetCapture:
    def __init__(self, interface: str, promiscuous: bool, on_record, on_error):
        self.interface, self.promiscuous, self.on_record, self.on_error = interface, promiscuous, on_record, on_error
        self.sock = None
    def open(self):
        """Open before the server starts so privilege errors are actionable."""
        try:
            sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(3))
            sock.bind((self.interface, 0))
        except PermissionError as error:
            raise CaptureError("raw Ethernet capture needs CAP_NET_RAW; see README") from error
        except OSError as error:
            raise CaptureError(f"cannot open {self.interface}: {error}") from error
        if self.promiscuous:
            # packet_mreq: ifindex, PACKET_MR_PROMISC, address length, address.
            membership = struct.pack("IHH8s", socket.if_nametoindex(self.interface), 1, 0, b"\0" * 8)
            sock.setsockopt(263, 1, membership)  # SOL_PACKET / PACKET_ADD_MEMBERSHIP
        self.sock = sock
    def run(self):
        if self.sock is None: self.open()
        while True:
            try:
                record = parse_ethernet_frame(self.sock.recv(65535), self.interface)
                if record: self.on_record(record)
            except Exception as error: self.on_error(error)
