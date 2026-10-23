#!/usr/bin/env python3
"""Send raw incrementing bytes from Raspberry Pi GPIO14/TXD0."""

import argparse
import sys
import time

import serial


def byte_value(text: str) -> int:
    try:
        value = int(text, 0)
    except ValueError:
        # Also accept bare hexadecimal tokens used by connection.json, e.g. AA.
        value = int(text, 16)
    if not 0 <= value <= 255:
        raise argparse.ArgumentTypeError("value must be in range 0..255")
    return value


def nonnegative_float(text: str) -> float:
    value = float(text)
    if value < 0:
        raise argparse.ArgumentTypeError("interval must be >= 0")
    return value


def nonnegative_int(text: str) -> int:
    value = int(text)
    if value < 0:
        raise argparse.ArgumentTypeError("count must be >= 0")
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send raw bytes to the ACG525 UART forwarder")
    parser.add_argument("--port", default="/dev/serial0")
    parser.add_argument("--start", type=byte_value, default=0)
    parser.add_argument("--count", type=nonnegative_int, default=0,
                        help="0 means run until Ctrl+C")
    parser.add_argument("--interval", type=nonnegative_float, default=0.5)
    parser.add_argument("--values", default="",
                        help="comma-separated raw byte values, e.g. 55,AA,00,FF")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    port = None
    failed = False
    try:
        port = serial.Serial(
            port=args.port,
            baudrate=115200,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1.0,
            write_timeout=1.0,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        )
        values = []
        if args.values:
            try:
                values = [byte_value(part.strip()) for part in args.values.split(",")]
            except ValueError as exc:
                raise ValueError(f"invalid --values list: {exc}") from exc
            if not values:
                raise ValueError("--values must contain at least one byte")
        value = args.start
        index = 0
        limit = len(values) if values else args.count
        while (limit == 0) or (index < limit):
            if values:
                value = values[index]
            port.write(bytes([value]))
            port.flush()
            timestamp = time.strftime("%H:%M:%S") + f".{int(time.time_ns() / 1_000_000) % 1000:03d}"
            print(f"[{timestamp}] TX index={index} value=0x{value:02X} decimal={value}")
            value = (value + 1) & 0xFF
            index += 1
            if args.interval:
                time.sleep(args.interval)
    except KeyboardInterrupt:
        print("User interrupted")
    except (serial.SerialException, serial.SerialTimeoutException, OSError) as exc:
        print(f"Serial error on {args.port}: {exc}", file=sys.stderr)
        failed = True
    finally:
        if port is not None and port.is_open:
            port.close()
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
