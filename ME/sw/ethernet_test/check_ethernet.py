"""Check Windows Ethernet link, IPv4 setup, UDP port and optional peer ping."""

from __future__ import annotations

import argparse
import re
import socket
import subprocess
import sys


def run_text(command: list[str]) -> str:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout + result.stderr


def list_interfaces() -> list[tuple[str, str, str, str]]:
    output = run_text(["netsh", "interface", "show", "interface"])
    interfaces: list[tuple[str, str, str, str]] = []
    pattern = re.compile(
        r"^\s*(Enabled|Disabled)\s+(Connected|Disconnected)\s+"
        r"(Dedicated|Loopback)\s+(.+?)\s*$",
        re.IGNORECASE,
    )
    for line in output.splitlines():
        match = pattern.match(line)
        if match:
            interfaces.append(tuple(match.groups()))
    return interfaces


def ipv4_for_adapter(adapter_name: str) -> list[str]:
    output = run_text(["ipconfig"])
    current_name = ""
    addresses: list[str] = []
    header = re.compile(r"^[^:]*adapter\s+(.+):\s*$", re.IGNORECASE)
    ipv4 = re.compile(
        r"(?:IPv4 Address|Autoconfiguration IPv4 Address)[^:]*:\s*"
        r"([0-9]+(?:\.[0-9]+){3})",
        re.IGNORECASE,
    )
    for line in output.splitlines():
        match = header.match(line.strip())
        if match:
            current_name = match.group(1).strip()
            continue
        match = ipv4.search(line)
        if match and current_name.casefold() == adapter_name.casefold():
            addresses.append(match.group(1))
    return addresses


def udp_port_owner(port: int) -> tuple[bool, str | None]:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        probe.bind(("0.0.0.0", port))
        return True, None
    except OSError:
        output = run_text(["netstat", "-ano", "-p", "udp"])
        owner = None
        endpoint = re.compile(rf"^\s*UDP\s+\S*:{port}\s+\S+\s+(\d+)\s*$")
        for line in output.splitlines():
            match = endpoint.match(line)
            if match:
                pid = match.group(1)
                task = run_text(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"])
                owner = f"PID {pid}: {task.strip()}"
                break
        return False, owner
    finally:
        probe.close()


def ping_peer(target: str) -> bool:
    result = subprocess.run(
        ["ping", "-n", "2", "-w", "1000", target],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    print(result.stdout.rstrip())
    return result.returncode == 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check the Windows Ethernet link used by the FPGA bridge."
    )
    parser.add_argument(
        "--adapter", default="Ethernet", help="Windows interface name (Ethernet)"
    )
    parser.add_argument("--port", type=int, default=5001, help="UDP receive port")
    parser.add_argument("--target", help="IPv4 address of the other test computer")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("--port must be in range 1..65535")

    print("=== Network interfaces ===")
    interfaces = list_interfaces()
    if not interfaces:
        print("Could not read interfaces from netsh.")
        return 2

    selected = None
    for admin, state, kind, name in interfaces:
        marker = "*" if name.casefold() == args.adapter.casefold() else " "
        print(f"{marker} {name}: admin={admin}, link={state}, type={kind}")
        if marker == "*":
            selected = (admin, state, kind, name)

    failed = False
    print(f"\n=== Selected adapter: {args.adapter} ===")
    if selected is None:
        print("FAIL: adapter not found. Use --adapter with a name shown above.")
        return 2
    if selected[1].casefold() != "connected":
        print("FAIL: physical Ethernet link is disconnected.")
        failed = True
    else:
        print("PASS: physical Ethernet link is connected.")

    addresses = ipv4_for_adapter(selected[3])
    if not addresses:
        print("FAIL: no IPv4 address found on this adapter.")
        failed = True
    else:
        print(f"IPv4: {', '.join(addresses)}")
        if all(address.startswith("169.254.") for address in addresses):
            print(
                "WARN: 169.254.x.x is an automatic address. Set static IPv4 "
                "addresses in the same subnet on both computers."
            )

    print(f"\n=== UDP port {args.port} ===")
    available, owner = udp_port_owner(args.port)
    if available:
        print("FREE: receiver can use this port.")
    else:
        print("BUSY: another process is already using this port.")
        if owner:
            print(owner)
        print("Close the old receiver with Ctrl+C or choose another port.")

    if args.target:
        print(f"\n=== Ping {args.target} ===")
        if ping_peer(args.target):
            print("PASS: the other computer responds to ping.")
        else:
            print(
                "FAIL: no ping response. Check both IPv4 addresses, firewall, "
                "cables, PHY link LEDs and the FPGA bitstream."
            )
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
