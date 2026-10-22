"""Receive and validate UDP packets sent by udp_sender."""

from __future__ import annotations

import argparse
import socket
import time

from .protocol import decode_packet, make_payload


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Receive FPGA bridge test traffic and report loss/CRC errors."
    )
    parser.add_argument("--bind", default="0.0.0.0", help="local IPv4 address")
    parser.add_argument("--port", type=int, default=5001, help="UDP port (5001)")
    parser.add_argument(
        "--expected", type=int, default=0, help="stop after this many unique packets"
    )
    parser.add_argument(
        "--idle-timeout",
        type=float,
        default=5.0,
        help="stop this many seconds after the last received packet",
    )
    parser.add_argument(
        "--verify-pattern",
        action="store_true",
        help="also compare payload with sender's deterministic byte pattern",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.port < 1 or args.port > 65535:
        raise SystemExit("--port must be in range 1..65535")
    if args.expected < 0 or args.idle_timeout <= 0:
        raise SystemExit("--expected must be >= 0 and --idle-timeout must be > 0")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    try:
        sock.bind((args.bind, args.port))
    except OSError as error:
        sock.close()
        if getattr(error, "winerror", None) == 10048:
            print(
                f"ERROR: UDP port {args.port} is already in use.\n"
                "A receiver may already be running in another terminal. "
                "Close it with Ctrl+C, or use the same alternative --port "
                "on both receiver and sender.\n"
                "Check it with:\n"
                f"  python -m ME.sw.ethernet_test.check_ethernet --port {args.port}"
            )
            return 2
        print(f"ERROR: cannot listen on {args.bind}:{args.port}: {error}")
        return 2
    sock.settimeout(0.5)

    print(f"Listening on {args.bind}:{args.port}")
    print("Start the sender on the other computer. Press Ctrl+C to stop.")

    session_id: int | None = None
    peer = None
    seen: set[int] = set()
    duplicates = 0
    malformed = 0
    crc_errors = 0
    pattern_errors = 0
    udp_bytes = 0
    first_time: float | None = None
    last_time: float | None = None

    try:
        while True:
            try:
                packet, address = sock.recvfrom(65_535)
            except socket.timeout:
                if last_time is not None and time.perf_counter() - last_time >= args.idle_timeout:
                    break
                continue

            now = time.perf_counter()
            try:
                session, sequence, _sent_ns, payload, crc_ok = decode_packet(packet)
            except ValueError as error:
                malformed += 1
                print(f"Malformed packet from {address}: {error}")
                continue

            if session_id is None:
                session_id = session
                peer = address
                first_time = now
                print(f"Receiving session={session_id:016x} from {peer[0]}:{peer[1]}")
            elif session != session_id:
                print(f"Ignoring another session {session:016x} from {address}")
                continue

            last_time = now
            udp_bytes += len(packet)
            if sequence in seen:
                duplicates += 1
            else:
                seen.add(sequence)
            if not crc_ok:
                crc_errors += 1
            if args.verify_pattern and payload != make_payload(sequence, len(payload)):
                pattern_errors += 1

            if args.expected and len(seen) >= args.expected:
                break
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        sock.close()

    if not seen:
        print("No valid test packet received.")
        return 2

    duration = max((last_time or 0.0) - (first_time or 0.0), 1e-9)
    expected_range = args.expected if args.expected else max(seen) + 1
    missing = max(expected_range - len(seen), 0)
    loss_percent = missing * 100.0 / expected_range
    print("\nResult")
    print(f"  peer             : {peer[0]}:{peer[1]}")
    print(f"  unique packets   : {len(seen)}")
    print(f"  missing packets  : {missing} ({loss_percent:.3f}%)")
    print(f"  duplicate packets: {duplicates}")
    print(f"  malformed packets: {malformed}")
    print(f"  CRC errors       : {crc_errors}")
    print(f"  pattern errors   : {pattern_errors}")
    print(f"  receive rate     : {udp_bytes * 8 / duration / 1e6:.3f} Mbps")

    return 0 if not (missing or malformed or crc_errors or pattern_errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
