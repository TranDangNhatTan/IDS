"""Machine B tool: receive traffic from the ACG525 onboard Ethernet port."""

from __future__ import annotations

import argparse

from . import udp_receiver


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Receive and validate traffic on machine B connected to the "
            "ACG525 onboard RJ45."
        )
    )
    parser.add_argument(
        "--local-ip", default="192.168.50.2", help="IPv4 of this machine"
    )
    parser.add_argument("--port", type=int, default=55001, help="UDP port")
    parser.add_argument(
        "--expected", type=int, default=1000, help="expected unique packets"
    )
    parser.add_argument(
        "--idle-timeout", type=float, default=5.0, help="seconds before summary"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print("Machine B: ACG525 onboard RJ45 receiver")
    print(f"Listening on {args.local_ip}:{args.port}\n")
    return udp_receiver.main(
        [
            "--bind",
            args.local_ip,
            "--port",
            str(args.port),
            "--expected",
            str(args.expected),
            "--idle-timeout",
            str(args.idle_timeout),
            "--verify-pattern",
        ]
    )


if __name__ == "__main__":
    raise SystemExit(main())
