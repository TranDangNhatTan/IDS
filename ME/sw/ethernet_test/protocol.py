"""Packet format shared by the UDP sender and receiver."""

from __future__ import annotations

import struct
import zlib

MAGIC = b"FNET"
VERSION = 1
HEADER = struct.Struct("!4sB3xQQQII")
MAX_UDP_PACKET = 65_507


def make_payload(sequence: int, size: int) -> bytes:
    """Create deterministic data so payload corruption can be detected."""
    pattern = bytes(range(256))
    offset = sequence & 0xFF
    rotated = pattern[offset:] + pattern[:offset]
    repeats, remainder = divmod(size, len(rotated))
    return rotated * repeats + rotated[:remainder]


def encode_packet(session: int, sequence: int, sent_ns: int, payload: bytes) -> bytes:
    checksum = zlib.crc32(payload) & 0xFFFFFFFF
    return HEADER.pack(
        MAGIC, VERSION, session, sequence, sent_ns, len(payload), checksum
    ) + payload


def decode_packet(packet: bytes) -> tuple[int, int, int, bytes, bool]:
    if len(packet) < HEADER.size:
        raise ValueError("packet shorter than test header")

    magic, version, session, sequence, sent_ns, payload_size, expected_crc = (
        HEADER.unpack_from(packet)
    )
    if magic != MAGIC:
        raise ValueError("incorrect packet magic")
    if version != VERSION:
        raise ValueError(f"unsupported protocol version {version}")

    payload = packet[HEADER.size:]
    if len(payload) != payload_size:
        raise ValueError(
            f"payload length mismatch: header={payload_size}, actual={len(payload)}"
        )

    actual_crc = zlib.crc32(payload) & 0xFFFFFFFF
    return session, sequence, sent_ns, payload, actual_crc == expected_crc
