"""Standalone preflight check for machine B Ethernet configuration."""

from __future__ import annotations

import argparse
import re
import socket
import subprocess


def command_text(command: list[str]) -> str:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter", default="Ethernet")
    parser.add_argument("--local-ip", default="192.168.50.2")
    parser.add_argument("--sender-ip", default="192.168.50.1")
    parser.add_argument("--port", type=int, default=55001)
    args = parser.parse_args()

    print("=== Adapter status ===")
    netsh = command_text(["netsh", "interface", "show", "interface"])
    selected_line = None
    for line in netsh.splitlines():
        if re.search(rf"\s{re.escape(args.adapter)}\s*$", line, re.IGNORECASE):
            selected_line = line.strip()
            print(selected_line)
            break
    if selected_line is None:
        print(f"FAIL: adapter '{args.adapter}' not found.")
        return 2
    connected = bool(re.search(r"\bConnected\b", selected_line, re.IGNORECASE))
    print("PASS: physical link connected." if connected else "FAIL: physical link disconnected.")

    print("\n=== IPv4 configuration ===")
    ipconfig = command_text(["ipconfig"])
    has_ip = args.local_ip in ipconfig
    print(f"PASS: found {args.local_ip}." if has_ip else f"FAIL: {args.local_ip} is not configured.")

    print(f"\n=== UDP port {args.port} ===")
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    port_free = False
    try:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        probe.bind((args.local_ip, args.port))
        port_free = True
        print("PASS: UDP port is free.")
    except OSError as error:
        print(f"FAIL: cannot use UDP port: {error}")
    finally:
        probe.close()

    print(f"\n=== Ping machine A: {args.sender_ip} ===")
    ping = subprocess.run(
        ["ping", "-n", "2", "-w", "1000", args.sender_ip],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    print(ping.stdout.rstrip())
    ping_ok = ping.returncode == 0
    print("PASS: machine A responds." if ping_ok else "FAIL: no ping response.")
    return 0 if connected and has_ip and port_free and ping_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
