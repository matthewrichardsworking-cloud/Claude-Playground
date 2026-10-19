"""Send the playtest bot through a structure on the spot (the owner's vision tests).

    python tools\\stunt.py --name "VISION TEST 2" --lead X Y Z [--lead X Y Z ...]
                           --through X Y Z [--speed 450] [--floor 10] [--lead-within 1500]

All coordinates in game units (10 cm), z too. The lead points line the plane up: it flies to
each in turn ("fly to X Y Z"), the next order going out when it is within --lead-within
metres (horizontally). Then "fly to X Y Z through vision on speed S floor F then attack":
from there on the pilot steers with its live rays only (vision.lua). The script watches
events.jsonl (stunt_done, vision, ground_recovery, beyond_pullout, route_done, damage) and
status.json (health, in_tunnel, height), and after route_done sends a fresh "fly attack"
(the stunt's low floor must not carry over into the fight). Prints a short account.
"""

import argparse
import json
import math
import os
import socket
import sys
import time

OUT = r"C:\AC7-Coop-Game\UserProfile\pilot"
ADDR = ("127.0.0.1", 27777)


def send(words):
    line = "PILOT " + " ".join(str(w) for w in words)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(line.encode("utf-8"), ADDR)
    s.close()
    print(time.strftime("%H:%M:%S"), "->", line[6:], flush=True)


def status():
    try:
        with open(os.path.join(OUT, "status.json"), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


class Events:
    def __init__(self):
        self.path = os.path.join(OUT, "events.jsonl")
        try:
            self.pos = os.path.getsize(self.path)
        except OSError:
            self.pos = 0

    def new(self):
        out = []
        try:
            with open(self.path, "r", encoding="utf-8", errors="replace") as f:
                f.seek(self.pos)
                data = f.read()
                # keep a half-written last line for next time
                cut = data.rfind("\n") + 1
                self.pos += len(data[:cut].encode("utf-8"))
            for line in data[:cut].splitlines():
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
        except OSError:
            pass
        return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="STUNT")
    ap.add_argument("--lead", nargs=3, type=float, action="append", default=[])
    ap.add_argument("--through", nargs=3, type=float, required=True)
    ap.add_argument("--speed", type=float, default=450)
    ap.add_argument("--lead-speed", type=float, default=650)
    ap.add_argument("--floor", type=float, default=10)
    ap.add_argument("--lead-floor", type=float, default=60)
    ap.add_argument("--lead-within", type=float, default=1500, help="metres")
    ap.add_argument("--timeout", type=float, default=420, help="seconds for the whole stunt")
    ap.add_argument("--min-health", type=float, default=60,
                    help="call it off on the way in when health falls below this (19 Oct: two missiles took 80 in 20 s)")
    a = ap.parse_args(argv)

    ev = Events()
    t0 = time.time()
    send(["mark", a.name, "start"])
    s = status()
    if not s or not s.get("started") or s.get("failed") or s.get("completed"):
        print("no mission in flight; nothing sent")
        return 1
    health0 = s.get("health")
    if health0 is not None and health0 < a.min_health:
        print("health %s is below %s; not starting" % (health0, a.min_health))
        return 1

    def abort(why):
        print(time.strftime("%H:%M:%S"), "ABORT:", why, flush=True)
        send(["mark", a.name, "aborted:", why])
        send(["fly", "attack"])
        return 2

    # 1. the lead points
    for k, (x, y, z) in enumerate(a.lead):
        send(["fly", "to", int(x), int(y), int(z), "speed", int(a.lead_speed), "floor", int(a.lead_floor)])
        while True:
            if time.time() - t0 > a.timeout:
                return abort("timed out on lead point %d" % (k + 1))
            s = status()
            for e in ev.new():
                if e.get("kind") == "beyond_pullout":
                    return abort("the lead point is outside the mission area")
            if s:
                if s.get("failed") or s.get("completed"):
                    return abort("the mission ended")
                if s.get("health") is not None and s["health"] < a.min_health:
                    return abort("health %s on the way in" % s["health"])
                d = math.hypot(s["x"] - x, s["y"] - y) / 10
                if d < a.lead_within:
                    print(time.strftime("%H:%M:%S"), "lead point %d: %.0f m away, %.0f m up, %.0f km/h" % (k + 1, d, s.get("alt_m", 0), s.get("kmh", 0)), flush=True)
                    break
            time.sleep(0.25)

    # 2. the stunt itself: live vision only from here
    x, y, z = a.through
    send(["mark", a.name, "through order"])
    send(["fly", "to", int(x), int(y), int(z), "through", "vision", "on", "speed", int(a.speed), "floor", int(a.floor), "then", "attack"])
    closest, passed, done_at = 1e18, None, None
    tunnel_in, tunnel_out, low, hp_min = None, None, 1e9, health0
    visions = []
    while True:
        if time.time() - t0 > a.timeout:
            return abort("timed out in the stunt")
        s = status()
        for e in ev.new():
            k = e.get("kind")
            if k == "stunt_done":
                passed = e
                print(time.strftime("%H:%M:%S"), "THROUGH: closest %.1f m, damage %s" % (e.get("closest_m", -1), e.get("damage")), flush=True)
            elif k == "vision":
                visions.append(e)
                print(time.strftime("%H:%M:%S"), "  ", e.get("text", "")[:200], flush=True)
            elif k in ("ground_recovery", "beyond_pullout", "crash", "death", "damage", "hit") and (k != "death" or e.get("who", "").startswith("AcePlayer")):
                print(time.strftime("%H:%M:%S"), "  event", k, json.dumps(e)[:200], flush=True)
            elif k == "route_done":
                done_at = time.time()
        if s:
            hp = s.get("health")
            if hp is not None and hp_min is not None and hp < hp_min:
                hp_min = hp
                print(time.strftime("%H:%M:%S"), "  health %s" % hp, flush=True)
            d = math.sqrt((s["x"] - x) ** 2 + (s["y"] - y) ** 2 + (s["z"] - z) ** 2) / 10
            closest = min(closest, d)
            if s.get("in_tunnel") and not tunnel_in:
                tunnel_in = time.time()
                print(time.strftime("%H:%M:%S"), "  in the tunnel (game's own flag), %.0f m up, %.0f km/h" % (s.get("alt_m", 0), s.get("kmh", 0)), flush=True)
            if tunnel_in and not s.get("in_tunnel") and not tunnel_out:
                tunnel_out = time.time()
                print(time.strftime("%H:%M:%S"), "  out of the tunnel after %.1f s, %.0f m up" % (tunnel_out - tunnel_in, s.get("alt_m", 0)), flush=True)
            if s.get("failed"):
                print(time.strftime("%H:%M:%S"), "MISSION FAILED during the stunt (crash?)", flush=True)
                send(["mark", a.name, "failed"])
                break
        if done_at:
            send(["mark", a.name, "done"])
            send(["fly", "attack"])
            break
        time.sleep(0.1)
    print("summary: through=%s closest=%.1f m, tunnel %s, health %s -> %s, vision notes %d" % (
        "yes" if passed else "no", closest, "%.1f s" % (tunnel_out - tunnel_in) if tunnel_in and tunnel_out else ("entered" if tunnel_in else "not entered"),
        health0, hp_min, len(visions)), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
