#!/usr/bin/env python3
"""Direct FPGA LAN/UART probe; does not use the dashboard web server."""
from __future__ import annotations

import argparse
import socket
import struct
import sys
import threading
import time
from pathlib import Path

try:
    import serial
except ImportError:
    serial = None

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "model" / "node_rom.mem"


def uart_worker(port: str, stop: threading.Event, lines: list[str]) -> None:
    if not port:
        return
    if serial is None:
        print("UART_WARN pyserial is not installed", flush=True)
        return
    try:
        with serial.Serial(port, 115200, timeout=0.2) as stream:
            print(f"UART_OPEN {port} 115200-8-N-1", flush=True)
            while not stop.is_set():
                raw = stream.readline()
                if raw:
                    line = raw.decode("ascii", errors="replace").strip()
                    if line:
                        lines.append(line)
                        print(f"UART {line}", flush=True)
    except Exception as exc:
        print(f"UART_ERROR {exc}", flush=True)


def decode_reply(data: bytes, address: tuple[str, int]) -> str:
    if data.startswith(b"ACK1") and len(data) >= 17:
        ready = data[4]
        words = int.from_bytes(data[5:7], "big")
        version = int.from_bytes(data[7:9], "big")
        accepted = int.from_bytes(data[9:13], "big")
        dropped = int.from_bytes(data[13:17], "big")
        return f"ACK1 source={address[0]}:{address[1]} ready={ready} words={words} version={version} accepted={accepted} dropped={dropped}"
    if data.startswith(b"IDS1"):
        return f"IDS1 source={address[0]}:{address[1]} bytes={len(data)} payload={data.hex()}"
    return f"UNKNOWN source={address[0]}:{address[1]} bytes={len(data)} payload={data.hex()}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-ip", default="192.168.50.22")
    parser.add_argument("--target", default="192.168.50.255")
    parser.add_argument("--fpga-port", type=int, default=55002)
    parser.add_argument("--result-port", type=int, default=55003)
    parser.add_argument("--rate", type=float, default=200.0)
    parser.add_argument("--passes", type=int, default=2)
    parser.add_argument("--uart", default="COM17")
    parser.add_argument("--commit-retries", type=int, default=5)
    parser.add_argument("--jitter", type=float, default=0.0,
                        help="deterministic fractional pacing jitter (0..0.9) to sweep PHY sampling phase")
    parser.add_argument("--no-init", action="store_true",
                        help="continue filling missing model addresses without clearing FPGA state")
    parser.add_argument("--startup-delay", type=float, default=0.5,
                        help="seconds to capture UART before the first UDP packet")
    args = parser.parse_args()

    words = [int(line, 16) for line in MODEL.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(words) != 1273:
        raise RuntimeError(f"model contains {len(words)} words, expected 1273")

    stop_uart = threading.Event()
    uart_lines: list[str] = []
    uart_thread = threading.Thread(target=uart_worker, args=(args.uart, stop_uart, uart_lines), daemon=True)
    uart_thread.start()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.bind((args.local_ip, args.result_port))
    except OSError as exc:
        stop_uart.set()
        print(f"UDP_BIND_ERROR {args.local_ip}:{args.result_port}: {exc}", flush=True)
        return 2
    sock.settimeout(0.25)
    print(f"UDP_BOUND {args.local_ip}:{args.result_port}", flush=True)
    print(f"TARGET {args.target}:{args.fpga_port} rate={args.rate:g}/s passes={args.passes}", flush=True)

    interval = 1.0 / max(args.rate, 1.0)
    deadline = time.perf_counter()
    jitter_state = 0x13579BDF

    def paced_send(payload: bytes) -> None:
        nonlocal deadline, jitter_state
        sock.sendto(payload, (args.target, args.fpga_port))
        jitter_state = (1664525 * jitter_state + 1013904223) & 0xFFFFFFFF
        centered = ((jitter_state >> 8) / float(1 << 24)) * 2.0 - 1.0
        deadline += interval * (1.0 + max(0.0, min(args.jitter, 0.9)) * centered)
        remaining = deadline - time.perf_counter()
        if remaining > 0:
            time.sleep(remaining)

    print(f"STARTUP_WAIT seconds={args.startup_delay:g}", flush=True)
    time.sleep(max(args.startup_delay, 0.0))
    # Start pacing after the boot/link wait.  Keeping the pre-wait timestamp
    # here made every overdue packet transmit as a large initial burst.
    deadline = time.perf_counter()
    init_packets = 0
    if not args.no_init:
        for _ in range(3):
            paced_send(b"MOD1\x01")
            init_packets += 1
        print("TX INIT copies=3", flush=True)
    else:
        print("TX INIT skipped; continuing current FPGA model image", flush=True)

    sent = 0
    for pass_index in range(1, args.passes + 1):
        for address, word in enumerate(words):
            paced_send(b"MOD1\x02" + struct.pack("<H", address) + struct.pack("<Q", word))
            sent += 1
            if address % 256 == 255:
                print(f"TX PASS={pass_index}/{args.passes} address={address:04X}", flush=True)
        print(f"TX_PASS_DONE pass={pass_index}/{args.passes} words={len(words)}", flush=True)

    ack = False
    for attempt in range(1, args.commit_retries + 1):
        sock.sendto(b"MOD1\x03", (args.target, args.fpga_port))
        print(f"TX COMMIT attempt={attempt}", flush=True)
        limit = time.monotonic() + 1.5
        while time.monotonic() < limit:
            try:
                data, address = sock.recvfrom(2048)
            except socket.timeout:
                continue
            message = decode_reply(data, address)
            print(f"UDP_RX {message}", flush=True)
            if data.startswith(b"ACK1"):
                ack = True
                break
        if ack:
            break

    time.sleep(0.5)
    stop_uart.set()
    uart_thread.join(timeout=1.0)
    sock.close()
    last_uart = uart_lines[-1] if uart_lines else "none"
    print(f"SUMMARY tx_model_packets={sent + init_packets + args.commit_retries} ack={int(ack)} uart_lines={len(uart_lines)} last_uart={last_uart}", flush=True)
    return 0 if ack else 3


if __name__ == "__main__":
    sys.exit(main())
