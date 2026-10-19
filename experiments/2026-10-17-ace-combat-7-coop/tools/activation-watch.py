"""Watch which enemy groups the mission switches on, and where the plane was at that moment.

    python tools\\activation-watch.py [seconds between looks, default 10]

Every few seconds it asks the pilot (eval) for each group of enemies with points (name
without its number: AreaB_Add2_F04, P2_Drone1, ...) how many are active of how many, and
prints a line whenever a group's active count changes, with the plane's position (km) and
the mission's phase clock. Written 19 Oct 2026 for Mission 06 (Long Day), where most of the
points come in waves that only appear when something wakes them.
"""

import json
import os
import socket
import sys
import time

OUT = r"C:\AC7-Coop-Game\UserProfile\pilot"
ADDR = ("127.0.0.1", 27777)

CODE = ('local g={} for _,o in ipairs(FindAllOf("GameObject") or {}) do pcall(function() '
        'if o:IsValid() and o:GetFaction()==0 and (o.KillBountyScore or 0)>0 then '
        'local k=(objName(o):gsub("_%d+$","")) local e=g[k] or {0,0,0} e[2]=e[2]+1 '
        'if o.bIsActivated and o:IsAlive() then e[1]=e[1]+1 end if not o:IsAlive() then e[3]=e[3]+1 end g[k]=e end end) end '
        'local out={} for k,e in pairs(g) do out[#out+1]=k.."="..e[1].."/"..e[2].."/"..e[3] end return "ACTW "..table.concat(out,";")')


def send(line):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(("PILOT " + line).encode("utf-8"), ADDR)
    s.close()


def status():
    try:
        with open(os.path.join(OUT, "status.json"), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def last_result(since):
    path = os.path.join(OUT, "pilot.log")
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(since)
            data = f.read()
    except OSError:
        return None
    for line in reversed(data.splitlines()):
        if "eval -> ACTW " in line:
            return line.split("eval -> ACTW ", 1)[1]
    return None


def main(argv):
    gap = float(argv[0]) if argv else 10.0
    prev = {}
    while True:
        try:
            size = os.path.getsize(os.path.join(OUT, "pilot.log"))
        except OSError:
            size = 0
        send("eval " + CODE)
        time.sleep(1.5)
        res = last_result(size)
        s = status()
        if res:
            now = {}
            for part in res.split(";"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    a, n, dead = (int(x) for x in v.split("/"))
                    now[k] = (a, n, dead)
            changes = []
            for k, (a, n, dead) in sorted(now.items()):
                pa = prev.get(k, (None, None, None))[0]
                if pa is None and prev:
                    changes.append(f"{k} {a}/{n} (new)")
                elif pa is not None and a > pa:
                    changes.append(f"{k} {pa}->{a}/{n} active")
            if changes or not prev:
                where = "plane at (%.1f, %.1f) km, %.0f m" % ((s.get("x") or 0) / 10000, (s.get("y") or 0) / 10000, s.get("alt_m") or 0)
                head = time.strftime("%H:%M:%S") + " phase left %s s, score %s; %s" % (round(s.get("phase_left_s") or 0), s.get("hud_score"), where)
                if not prev:
                    act = [f"{k} {a}/{n}" for k, (a, n, d) in sorted(now.items()) if a > 0]
                    print(head + " | active at start of watch: " + ", ".join(act), flush=True)
                else:
                    print(head + " | " + ", ".join(changes), flush=True)
            prev = now
        time.sleep(max(0.5, gap - 1.5))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
