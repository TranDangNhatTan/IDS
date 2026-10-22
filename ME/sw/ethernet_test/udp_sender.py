"""Send numbered and checksummed UDP packets through the FPGA bridge."""

from __future__ import annotations

import argparse
import secrets
import socket
import time

from .protocol import HEADER, MAX_UDP_PACKET, encode_packet, make_payload


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send test UDP traffic with sequence numbers and CRC32."
    )
    parser.add_argument("--host", required=True, help="IPv4 address of receiver")
    parser.add_argument("--port", type=int, default=5001, help="UDP port (5001)")
    parser.add_argument("--count", type=int, default=1000, help="packets to send")
    parser.add_argument(
        "--payload-size", type=int, default=1400, help="payload bytes per packet"
    )
    parser.add_argument(
        "--rate-mbps",
        type=float,
        default=10.0,
        help="approximate transmit rate; 0 sends without pacing",
    )
    parser.add_argument("--bind", help="optional local IPv4 address")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.count <= 0:
        raise SystemExit("--count must be greater than zero")
    if args.port < 1 or args.port > 65535:
        raise SystemExit("--port must be in range 1..65535")
    if args.payload_size < 0 or args.payload_size + HEADER.size > MAX_UDP_PACKET:
        raise SystemExit(
            f"--payload-size must be in range 0..{MAX_UDP_PACKET - HEADER.size}"
        )
    if args.rate_mbps < 0:
        raise SystemExit("--rate-mbps cannot be negative")

    destination = (args.host, args.port)
    session = secrets.randbits(64)
    bytes_sent = 0
    packet_wire_bytes = HEADER.size + args.payload_size + 28  # IPv4 + UDP
    interval = (
        packet_wire_bytes * 8.0 / (args.rate_mbps * 1_000_000.0)
        if args.rate_mbps > 0
        else 0.0
    )

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.bind:
        try:
            sock.bind((args.bind, 0))
        except OSError as exc:
            sock.close()
            print(f"ERROR: cannot use local IPv4 {args.bind}: {exc}")
            if getattr(exc, "winerror", None) == 10049:
                print(
                    f"Assign {args.bind}/24 to this machine's Ethernet adapter "
                    "and make sure its link status is Up."
                )
                print(
                    "Do not remove --bind: it prevents this test traffic from "
                    "being routed through Wi-Fi."
                )
            return 2

    print(
        f"Sending to {args.host}:{args.port}, packets={args.count}, "
        f"payload={args.payload_size} B, session={session:016x}"
    )
    started = time.perf_counter()
    next_send = started
    try:
        for sequence in range(args.count):
            payload = make_payload(sequence, args.payload_size)
            packet = encode_packet(session, sequence, time.time_ns(), payload)
            sock.sendto(packet, destination)
            bytes_sent += len(packet)

            if interval:
                next_send += interval
                remaining = next_send - time.perf_counter()
                if remaining > 0:
                    time.sleep(remaining)
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        sock.close()

    elapsed = max(time.perf_counter() - started, 1e-9)
    print(
        f"Done: sent={sequence + 1}, UDP_bytes={bytes_sent}, "
        f"elapsed={elapsed:.3f} s, rate={bytes_sent * 8 / elapsed / 1e6:.3f} Mbps"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
