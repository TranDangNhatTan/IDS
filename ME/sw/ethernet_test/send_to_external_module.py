"""Machine A tool: send traffic into the external LAN8720 port."""

from __future__ import annotations

import argparse

from . import udp_sender


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Send validated UDP traffic from machine A through the external "
            "LAN8720 module toward machine B on the ACG525 onboard RJ45."
        )
    )
    parser.add_argument(
        "--local-ip", default="192.168.50.1", help="IPv4 of this machine"
    )
    parser.add_argument(
        "--receiver-ip", default="192.168.50.2", help="IPv4 of machine B"
    )
    parser.add_argument("--port", type=int, default=55001, help="UDP port")
    parser.add_argument("--count", type=int, default=1000, help="packets to send")
    parser.add_argument(
        "--payload-size", type=int, default=1400, help="test bytes per packet"
    )
    parser.add_argument(
        "--rate-mbps", type=float, default=10.0, help="requested UDP test rate"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print("Machine A: external LAN8720 sender")
    print(
        f"Path: {args.local_ip} -> LAN8720 -> FPGA -> onboard RJ45 "
        f"-> {args.receiver_ip}"
    )
    print("Start receive_from_onboard_port.py on machine B first.\n")
    return udp_sender.main(
        [
            "--host",
            args.receiver_ip,
            "--bind",
            args.local_ip,
            "--port",
            str(args.port),
            "--count",
            str(args.count),
            "--payload-size",
            str(args.payload_size),
            "--rate-mbps",
            str(args.rate_mbps),
        ]
    )


if __name__ == "__main__":
    raise SystemExit(main())
