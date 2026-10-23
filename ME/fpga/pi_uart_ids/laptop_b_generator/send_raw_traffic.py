#!/usr/bin/env python3
"""
Laptop B — Raw Ethernet/IPv4/UDP traffic generator for Pi IDS testing.

Builds and sends Ethernet -> IPv4 -> UDP packets to the Pi's MAC/IP on UDP
port 40000.  Payload format (from PROTOCOL_CONTRACT.md):

    ASCII "IDSRAW1" (7 bytes) | sequence:u32-le | test bytes

This module can be used as a library (background thread with cancel event
and progress callbacks) or run standalone from the CLI.
"""

import argparse
import json
import os
import re
import struct
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

try:
    from scapy.all import (
        Ether,
        IP,
        UDP,
        Raw,
        conf,
        get_if_list,
        get_if_hwaddr,
        get_if_addr,
        sendp,
        IFACES,
    )
except ImportError:
    print("[ERROR] scapy is not installed. Run: pip install scapy")
    sys.exit(1)

# ──────────────────────── Constants ────────────────────────────────────────
MARKER = b"IDSRAW1"          # 7-byte ASCII marker
DST_PORT = 40000             # Fixed by protocol contract
DEFAULT_CONFIG = "config.json"


# ──────────────────────── Validation helpers ──────────────────────────────
_MAC_RE = re.compile(r"^([0-9a-fA-F]{2}[:\-]){5}[0-9a-fA-F]{2}$")
_IP_RE  = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"
)


def validate_mac(mac: str) -> bool:
    """Return True if *mac* looks like a valid MAC address."""
    return bool(_MAC_RE.match(mac))


def validate_ip(ip: str) -> bool:
    """Return True if *ip* is a dotted-quad IPv4 address."""
    return bool(_IP_RE.match(ip))


# ──────────────────────── Config dataclass ────────────────────────────────
@dataclass
class GeneratorConfig:
    interface: str = "Ethernet"
    pi_mac: str = "dc:a6:32:00:00:00"
    pi_ip: str = "192.168.1.100"
    dst_port: int = DST_PORT
    src_ip: str = ""
    src_mac: str = ""
    packet_count: int = 10
    rate_pps: float = 5.0
    payload_size: int = 64
    start_sequence: int = 1
    web_server_port: int = 5000

    # ── I/O ────────────────────────────────────────────────────────────
    @classmethod
    def from_file(cls, path: str) -> "GeneratorConfig":
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})

    def to_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.__dataclass_fields__}

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=4)

    # ── Validation ─────────────────────────────────────────────────────
    def validate(self) -> List[str]:
        """Return list of validation error strings (empty == OK)."""
        errors: List[str] = []
        if not validate_mac(self.pi_mac):
            errors.append(f"Invalid Pi MAC address: {self.pi_mac}")
        if not validate_ip(self.pi_ip):
            errors.append(f"Invalid Pi IP address: {self.pi_ip}")
        if self.dst_port != DST_PORT:
            errors.append(
                f"Destination port must be {DST_PORT} (got {self.dst_port})"
            )
        if self.rate_pps <= 0:
            errors.append(f"Rate must be > 0 pps (got {self.rate_pps})")
        if self.packet_count < 1:
            errors.append(f"Packet count must be >= 1 (got {self.packet_count})")
        if self.payload_size < len(MARKER) + 4:
            errors.append(
                f"Payload size must be >= {len(MARKER) + 4} bytes "
                f"(marker + seq); got {self.payload_size}"
            )
        return errors


# ──────────────────────── Interface discovery ─────────────────────────────
@dataclass
class InterfaceInfo:
    name: str = ""
    description: str = ""
    mac: str = ""
    ip: str = ""

def list_interfaces() -> List[InterfaceInfo]:
    """Return all Scapy-visible network interfaces."""
    result: List[InterfaceInfo] = []
    try:
        for iface_name in sorted(IFACES.keys()):
            iface_obj = IFACES[iface_name]
            info = InterfaceInfo(
                name=getattr(iface_obj, "name", str(iface_name)),
                description=getattr(iface_obj, "description", ""),
                mac=getattr(iface_obj, "mac", ""),
                ip=getattr(iface_obj, "ip", ""),
            )
            result.append(info)
    except Exception:
        # Fallback – simple list
        for name in get_if_list():
            try:
                mac = get_if_hwaddr(name)
            except Exception:
                mac = ""
            try:
                ip = get_if_addr(name)
            except Exception:
                ip = ""
            result.append(InterfaceInfo(name=name, mac=mac, ip=ip))
    return result


# ──────────────────────── Packet builder ──────────────────────────────────
def build_payload(sequence: int, payload_size: int) -> bytes:
    """
    Build the UDP payload per PROTOCOL_CONTRACT.md:
        IDSRAW1 (7 B) | sequence:u32-le | deterministic test bytes
    """
    header = MARKER + struct.pack("<I", sequence)
    fill_len = max(0, payload_size - len(header))
    # Deterministic fill: repeating 0x00..0xFF seeded by sequence
    fill = bytes([(sequence + i) & 0xFF for i in range(fill_len)])
    return header + fill


def build_packet(
    cfg: GeneratorConfig,
    sequence: int,
    src_mac: str = "",
    src_ip: str = "",
) -> "Ether":
    """Build a single Ether/IP/UDP/Raw packet ready for sendp()."""
    payload = build_payload(sequence, cfg.payload_size)
    pkt = (
        Ether(src=src_mac or cfg.src_mac or None, dst=cfg.pi_mac)
        / IP(src=src_ip or cfg.src_ip or None, dst=cfg.pi_ip)
        / UDP(sport=12345, dport=cfg.dst_port)
        / Raw(load=payload)
    )
    return pkt


def decode_packet(pkt) -> Dict:
    """Return a JSON-friendly dict with decoded layers for dry-run display."""
    info: Dict = {"layers": [], "hex": bytes(pkt).hex(), "size": len(pkt)}
    for layer in pkt.layers():
        l = pkt.getlayer(layer)
        if l is None:
            continue
        fields = {}
        for fname in l.fields_desc:
            val = l.getfieldval(fname.name)
            if isinstance(val, bytes):
                val = val.hex()
            fields[fname.name] = str(val)
        info["layers"].append({"name": layer.__name__, "fields": fields})
    # Decode our custom payload
    raw_layer = pkt.getlayer(Raw)
    if raw_layer:
        data = bytes(raw_layer)
        payload_info: Dict = {"raw_hex": data.hex()}
        if data[:7] == MARKER:
            payload_info["marker"] = data[:7].decode("ascii")
            if len(data) >= 11:
                payload_info["sequence"] = struct.unpack("<I", data[7:11])[0]
                payload_info["test_bytes_hex"] = data[11:].hex()
                payload_info["test_bytes_len"] = len(data) - 11
        info["payload"] = payload_info
    return info


# ──────────────────────── Transmission engine ─────────────────────────────
@dataclass
class TransmitStatus:
    running: bool = False
    sent: int = 0
    total: int = 0
    errors: List[str] = field(default_factory=list)
    log: List[Dict] = field(default_factory=list)
    start_time: float = 0.0
    end_time: float = 0.0

    def progress_pct(self) -> float:
        if self.total == 0:
            return 0.0
        return round(100.0 * self.sent / self.total, 1)

    def to_dict(self) -> dict:
        return {
            "running": self.running,
            "sent": self.sent,
            "total": self.total,
            "progress_pct": self.progress_pct(),
            "errors": list(self.errors),
            "log": list(self.log[-200:]),  # Keep last 200 entries
            "elapsed": round(
                (self.end_time or time.time()) - self.start_time, 2
            )
            if self.start_time
            else 0.0,
        }


class TrafficGenerator:
    """Thread-safe traffic generator with cancel support."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._cancel = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self.status = TransmitStatus()

    # ── Public API ─────────────────────────────────────────────────────
    def is_running(self) -> bool:
        with self._lock:
            return self.status.running

    def get_status(self) -> dict:
        with self._lock:
            return self.status.to_dict()

    def stop(self) -> None:
        self._cancel.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3.0)

    def start(
        self,
        cfg: GeneratorConfig,
        count: Optional[int] = None,
        rate: Optional[float] = None,
        start_seq: Optional[int] = None,
        on_progress: Optional[Callable[[int, int], None]] = None,
    ) -> Tuple[bool, str]:
        """
        Launch a background sending thread.
        Returns (ok, message).
        """
        if self.is_running():
            return False, "Transmission already in progress."

        errors = cfg.validate()
        if errors:
            return False, "; ".join(errors)

        total = count if count is not None else cfg.packet_count
        send_rate = rate if rate is not None else cfg.rate_pps
        seq = start_seq if start_seq is not None else cfg.start_sequence

        self._cancel.clear()
        with self._lock:
            self.status = TransmitStatus(
                running=True, total=total, start_time=time.time()
            )

        self._thread = threading.Thread(
            target=self._send_loop,
            args=(cfg, total, send_rate, seq, on_progress),
            daemon=True,
        )
        self._thread.start()
        return True, f"Sending {total} packets at {send_rate} pps …"

    # ── Internal ───────────────────────────────────────────────────────
    def _send_loop(
        self,
        cfg: GeneratorConfig,
        total: int,
        rate: float,
        start_seq: int,
        on_progress: Optional[Callable],
    ) -> None:
        interval = 1.0 / rate
        try:
            # Resolve source MAC/IP from interface if not specified
            src_mac = cfg.src_mac
            src_ip = cfg.src_ip
            if not src_mac:
                try:
                    src_mac = get_if_hwaddr(cfg.interface)
                except Exception:
                    pass
            if not src_ip:
                try:
                    src_ip = get_if_addr(cfg.interface)
                except Exception:
                    pass

            for i in range(total):
                if self._cancel.is_set():
                    with self._lock:
                        self.status.errors.append("Transmission cancelled by user.")
                    break

                seq = start_seq + i
                pkt = build_packet(cfg, seq, src_mac=src_mac, src_ip=src_ip)

                try:
                    sendp(pkt, iface=cfg.interface, verbose=False)
                    log_entry = {
                        "time": time.strftime("%H:%M:%S"),
                        "seq": seq,
                        "size": len(pkt),
                        "hex_preview": bytes(pkt)[:24].hex(),
                        "status": "OK",
                    }
                except Exception as exc:
                    log_entry = {
                        "time": time.strftime("%H:%M:%S"),
                        "seq": seq,
                        "size": 0,
                        "hex_preview": "",
                        "status": f"ERROR: {exc}",
                    }
                    with self._lock:
                        self.status.errors.append(str(exc))

                with self._lock:
                    self.status.sent = i + 1
                    self.status.log.append(log_entry)

                if on_progress:
                    try:
                        on_progress(i + 1, total)
                    except Exception:
                        pass

                # Rate limit (skip sleep on last packet)
                if i < total - 1 and not self._cancel.is_set():
                    self._cancel.wait(timeout=interval)

        except Exception as exc:
            with self._lock:
                self.status.errors.append(f"Fatal: {exc}")
        finally:
            with self._lock:
                self.status.running = False
                self.status.end_time = time.time()


# ──────────────────────── Network diagnostics ─────────────────────────────
def check_admin() -> bool:
    """Return True if the current process has Administrator rights (Windows)."""
    if os.name != "nt":
        return os.geteuid() == 0  # type: ignore[attr-defined]
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
    except Exception:
        return False


def check_npcap() -> bool:
    """Return True if Npcap / WinPcap DLL is loadable."""
    try:
        if os.name == "nt":
            npcap_dir = os.path.join(
                os.environ.get("SystemRoot", r"C:\Windows"),
                "System32", "Npcap",
            )
            return os.path.isdir(npcap_dir)
        return True  # Linux / macOS don't need Npcap
    except Exception:
        return False


def ping_host(ip: str, count: int = 2, timeout: int = 2) -> bool:
    """Return True if *ip* responds to ICMP ping."""
    try:
        if os.name == "nt":
            cmd = ["ping", "-n", str(count), "-w", str(timeout * 1000), ip]
        else:
            cmd = ["ping", "-c", str(count), "-W", str(timeout), ip]
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout * count + 5
        )
        return result.returncode == 0
    except Exception:
        return False


def probe_pi_dashboard(ip: str, port: int = 8080, timeout: int = 3) -> bool:
    """Return True if http://<ip>:<port> responds."""
    try:
        import urllib.request
        url = f"http://{ip}:{port}/"
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=timeout):
            return True
    except Exception:
        return False


def run_diagnostics(cfg: GeneratorConfig) -> Dict:
    """Run all pre-flight checks and return results dict."""
    return {
        "admin": check_admin(),
        "npcap": check_npcap(),
        "ping": ping_host(cfg.pi_ip),
        "pi_dashboard": probe_pi_dashboard(cfg.pi_ip),
        "pi_ip": cfg.pi_ip,
    }


# ──────────────────────── CLI ─────────────────────────────────────────────
def cli_main() -> None:
    parser = argparse.ArgumentParser(
        description="Laptop B raw traffic generator for Pi IDS"
    )
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG,
        help="Path to config.json (default: %(default)s)",
    )
    parser.add_argument("--count", type=int, help="Number of packets to send")
    parser.add_argument("--rate", type=float, help="Packets per second")
    parser.add_argument("--start-sequence", type=int, help="Starting sequence number")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Build and display one packet without sending",
    )
    parser.add_argument(
        "--verify-network",
        action="store_true",
        help="Run network diagnostics and exit",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        config_path = Path(__file__).parent / DEFAULT_CONFIG
    cfg = GeneratorConfig.from_file(str(config_path))

    # Override from CLI
    if args.count is not None:
        cfg.packet_count = args.count
    if args.rate is not None:
        cfg.rate_pps = args.rate
    if args.start_sequence is not None:
        cfg.start_sequence = args.start_sequence

    # Diagnostics
    if args.verify_network:
        print("Running network diagnostics …")
        diag = run_diagnostics(cfg)
        for k, v in diag.items():
            icon = "✔" if v else "✘"
            if k == "pi_ip":
                print(f"  Pi IP: {v}")
            else:
                print(f"  {icon} {k}: {v}")
        sys.exit(0 if all(diag[k] for k in ("admin", "npcap", "ping")) else 1)

    # Dry-run
    if args.dry_run:
        pkt = build_packet(cfg, cfg.start_sequence)
        info = decode_packet(pkt)
        print("=== Dry-Run Packet ===")
        for layer in info["layers"]:
            print(f"\n[{layer['name']}]")
            for fname, fval in layer["fields"].items():
                print(f"  {fname}: {fval}")
        if "payload" in info:
            print("\n[IDS Payload]")
            for k, v in info["payload"].items():
                print(f"  {k}: {v}")
        print(f"\nTotal frame size: {info['size']} bytes")
        print(f"Hex dump: {info['hex']}")
        return

    # Validation
    errors = cfg.validate()
    if errors:
        for e in errors:
            print(f"[ERROR] {e}")
        sys.exit(1)

    if not check_admin():
        print("[WARNING] Not running as Administrator — sending may fail.")
    if not check_npcap():
        print("[WARNING] Npcap not found — raw packet sending may fail.")

    # Send
    gen = TrafficGenerator()

    def on_progress(sent: int, total: int) -> None:
        pct = 100.0 * sent / total
        bar = "█" * int(pct / 2.5) + "░" * (40 - int(pct / 2.5))
        print(f"\r  [{bar}] {sent}/{total} ({pct:.1f}%)", end="", flush=True)

    print(
        f"Sending {cfg.packet_count} packets to {cfg.pi_ip} "
        f"(MAC {cfg.pi_mac}) at {cfg.rate_pps} pps …"
    )
    ok, msg = gen.start(cfg, on_progress=on_progress)
    if not ok:
        print(f"\n[ERROR] {msg}")
        sys.exit(1)

    # Wait for completion
    try:
        while gen.is_running():
            time.sleep(0.2)
    except KeyboardInterrupt:
        gen.stop()
        print("\n[CANCELLED]")
        sys.exit(130)

    status = gen.get_status()
    print(f"\n\nDone — {status['sent']}/{status['total']} packets sent "
          f"in {status['elapsed']}s")
    if status["errors"]:
        print("Errors:")
        for e in status["errors"]:
            print(f"  • {e}")
    print(
        "\n⚠  End-to-End PASS requires matching Pi dashboard / "
        "FPGA classification results at http://<pi-ip>:8080."
    )


if __name__ == "__main__":
    cli_main()
