"""Standalone UDP receiver for machine B on the ACG525 onboard RJ45."""

from __future__ import annotations

import argparse
import socket
import struct
import time
import zlib

MAGIC = b"FNET"
VERSION = 1
HEADER = struct.Struct("!4sB3xQQQII")


def make_payload(sequence: int, size: int) -> bytes:
    pattern = bytes(range(256))
    offset = sequence & 0xFF
    rotated = pattern[offset:] + pattern[:offset]
    repeats, remainder = divmod(size, 256)
    return rotated * repeats + rotated[:remainder]


def decode_packet(packet: bytes) -> tuple[int, int, bytes, bool]:
    if len(packet) < HEADER.size:
        raise ValueError("packet shorter than test header")
    magic, version, session, sequence, _sent_ns, size, expected_crc = (
        HEADER.unpack_from(packet)
    )
    if magic != MAGIC or version != VERSION:
        raise ValueError("not an FPGA Ethernet test packet")
    payload = packet[HEADER.size:]
    if len(payload) != size:
        raise ValueError(f"payload length mismatch: expected={size}, actual={len(payload)}")
    crc_ok = (zlib.crc32(payload) & 0xFFFFFFFF) == expected_crc
    return session, sequence, payload, crc_ok


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Machine B receiver connected to the ACG525 onboard RJ45."
    )
    parser.add_argument("--local-ip", default="192.168.50.2")
    parser.add_argument("--port", type=int, default=55001)
    parser.add_argument("--expected", type=int, default=1000)
    parser.add_argument("--idle-timeout", type=float, default=5.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    try:
        sock.bind((args.local_ip, args.port))
    except OSError as error:
        sock.close()
        print(f"ERROR: cannot listen on {args.local_ip}:{args.port}: {error}")
        print("Set Ethernet IPv4 to 192.168.50.2/255.255.255.0, then try again.")
        return 2
    sock.settimeout(0.5)

    print("Machine B - ACG525 onboard Ethernet receiver")
    print(f"Listening on {args.local_ip}:{args.port}")
    print("Now start send_to_external_module.py on machine A.")
    print("Press Ctrl+C to stop.\n")

    session_id = None
    peer = None
    seen: set[int] = set()
    duplicates = malformed = crc_errors = pattern_errors = udp_bytes = 0
    first_time = last_time = None

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
                session, sequence, payload, crc_ok = decode_packet(packet)
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
                continue

            last_time = now
            udp_bytes += len(packet)
            if sequence in seen:
                duplicates += 1
            else:
                seen.add(sequence)
            if not crc_ok:
                crc_errors += 1
            if payload != make_payload(sequence, len(payload)):
                pattern_errors += 1

            if args.expected and len(seen) >= args.expected:
                break
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        sock.close()

    if not seen:
        print("No valid packet received.")
        return 2

    duration = max((last_time or 0.0) - (first_time or 0.0), 1e-9)
    expected = args.expected if args.expected else max(seen) + 1
    missing = max(expected - len(seen), 0)
    print("\n========== RESULT ==========")
    print(f"Peer              : {peer[0]}:{peer[1]}")
    print(f"Unique packets    : {len(seen)}")
    print(f"Missing packets   : {missing} ({missing * 100.0 / expected:.3f}%)")
    print(f"Duplicate packets : {duplicates}")
    print(f"Malformed packets : {malformed}")
    print(f"CRC errors        : {crc_errors}")
    print(f"Pattern errors    : {pattern_errors}")
    print(f"Receive rate      : {udp_bytes * 8 / duration / 1e6:.3f} Mbps")
    passed = not (missing or malformed or crc_errors or pattern_errors)
    print("TEST PASS" if passed else "TEST FAIL")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
