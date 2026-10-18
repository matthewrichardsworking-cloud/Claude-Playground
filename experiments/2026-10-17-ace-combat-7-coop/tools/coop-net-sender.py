#!/usr/bin/env python3
r"""Send a recorded flight to the game as UDP packets, one text line per packet.

This stands in for the other player's PC: it reads one of the flight recordings the
CoopFlightLabMod made (dumps\2026-10-18_flight-recordings\flight-*.csv) and sends the
plane's position and attitude to 127.0.0.1 port 27777, where the CoopNetMod add-on in the
game copy listens. Each packet is one line of text:

    time,x,y,z,pitch,yaw,roll

Packets go out at a steady rate (40 per second unless --rate says otherwise); positions
between two recorded samples are interpolated so the stream is smooth whatever rate the
recording had. Nothing leaves this PC: the destination is the local address.

    python -I tools\coop-net-sender.py                       # newest recording, 40 Hz, once
    python -I tools\coop-net-sender.py path\to\flight.csv --rate 40 --loop
    python -I tools\coop-net-sender.py --duration 10         # stop after 10 seconds
"""
import argparse
import math
import socket
import sys
import time
from pathlib import Path

DEFAULT_DIR = Path(__file__).resolve().parent.parent / "dumps" / "2026-10-18_flight-recordings"


def load(path: Path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        header = f.readline()
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 7:
                continue
            try:
                rows.append(tuple(float(v) for v in parts[:7]))
            except ValueError:
                continue
    if len(rows) < 2:
        raise SystemExit(f"{path}: fewer than two usable rows")
    return rows


def lerp(a, b, f):
    return a + (b - a) * f


def lerp_angle(a, b, f):
    """Shortest way round for degrees, so -179 to +179 does not swing through 0."""
    d = (b - a + 180.0) % 360.0 - 180.0
    r = a + d * f
    return (r + 180.0) % 360.0 - 180.0


def sample(rows, t, i):
    """Position at recording time t, interpolated between rows i and i+1 (i advanced as needed)."""
    while i + 1 < len(rows) - 1 and rows[i + 1][0] <= t:
        i += 1
    a, b = rows[i], rows[i + 1]
    f = (t - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
    f = min(1.0, max(0.0, f))
    return (t,
            lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f),
            lerp_angle(a[4], b[4], f), lerp_angle(a[5], b[5], f), lerp_angle(a[6], b[6], f)), i


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recording", nargs="?", help="flight-*.csv to send (default: newest in dumps\\2026-10-18_flight-recordings)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=27777)
    ap.add_argument("--rate", type=float, default=40.0, help="packets per second (default 40)")
    ap.add_argument("--loop", action="store_true", help="start again from the beginning when the recording ends")
    ap.add_argument("--duration", type=float, default=0.0, help="stop after this many seconds (0 = whole recording)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    if a.recording:
        path = Path(a.recording)
    else:
        files = sorted(DEFAULT_DIR.glob("flight-*.csv"))
        if not files:
            raise SystemExit(f"no flight-*.csv in {DEFAULT_DIR}")
        path = files[-1]
    rows = load(path)
    t0, t1 = rows[0][0], rows[-1][0]
    print(f"sending {path.name}: {len(rows)} samples, {t1 - t0:.1f} s of flight, {a.rate:g} packets/s to {a.host}:{a.port}"
          + (", looping" if a.loop else ""), flush=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dest = (a.host, a.port)
    period = 1.0 / a.rate
    start = time.perf_counter()
    sent = 0
    next_report = 5.0
    try:
        while True:
            i = 0
            pass_start = time.perf_counter()
            n = 0
            while True:
                t = t0 + n * period
                if t > t1:
                    break
                s, i = sample(rows, t, i)
                line = "%.3f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f\n" % s
                # pace against the wall clock, not against sleep drift
                due = pass_start + n * period
                delay = due - time.perf_counter()
                if delay > 0:
                    time.sleep(delay)
                sock.sendto(line.encode("ascii"), dest)
                sent += 1
                n += 1
                elapsed = time.perf_counter() - start
                if a.duration and elapsed >= a.duration:
                    raise KeyboardInterrupt
                if not a.quiet and elapsed >= next_report:
                    print(f"  {sent} packets in {elapsed:.1f} s ({sent / elapsed:.1f}/s), last: {line.strip()}", flush=True)
                    next_report += 5.0
            if not a.loop:
                break
    except KeyboardInterrupt:
        pass
    elapsed = time.perf_counter() - start
    print(f"done: {sent} packets in {elapsed:.1f} s ({sent / max(elapsed, 1e-9):.1f}/s)", flush=True)


if __name__ == "__main__":
    main()
