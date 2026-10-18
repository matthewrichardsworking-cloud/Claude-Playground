"""Talk to the playtest bot's pilot (CoopPilotMod) inside the running game copy.

The pilot takes orders as one-line UDP packets "PILOT <command> ..." through the
CoopNetMod add-on (127.0.0.1:27777, this PC only), and writes what it sees into
C:\\AC7-Coop-Game\\UserProfile\\pilot (pilot.log, status.json, events.jsonl).

    python tools\\pilot.py send probe controls     send an order
    python tools\\pilot.py send ping hello
    python tools\\pilot.py status                  print the newest snapshot
    python tools\\pilot.py log [N]                 last N lines of pilot.log (default 40)
    python tools\\pilot.py events [N]              last N events
    python tools\\pilot.py wait "text" [seconds]   wait until pilot.log gets a line containing text
"""

import json
import os
import socket
import sys
import time

OUT = r"C:\AC7-Coop-Game\UserProfile\pilot"
ADDR = ("127.0.0.1", 27777)


def send(words):
    line = "PILOT " + " ".join(words)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(line.encode("utf-8"), ADDR)
    s.close()
    return line


def tail(path, n):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.readlines()[-n:]
    except FileNotFoundError:
        return []


def log_size():
    try:
        return os.path.getsize(os.path.join(OUT, "pilot.log"))
    except OSError:
        return 0


def wait_for(text, seconds, start_at):
    """Wait until pilot.log, from byte start_at on, holds a line containing text."""
    path = os.path.join(OUT, "pilot.log")
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                f.seek(start_at)
                new = f.read()
            for line in new.splitlines():
                if text in line:
                    return new
        except FileNotFoundError:
            pass
        time.sleep(0.25)
    return None


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "send":
        print("sent:", send(argv[2:]))
    elif cmd == "status":
        try:
            with open(os.path.join(OUT, "status.json"), "r", encoding="utf-8") as f:
                s = json.load(f)
            age = time.time() - os.path.getmtime(os.path.join(OUT, "status.json"))
            print(f"(written {age:.1f} s ago)")
            for k in sorted(s):
                print(f"  {k}: {s[k]}")
        except FileNotFoundError:
            print("no status.json yet (is the copy running with CoopPilotMod?)")
    elif cmd == "log":
        n = int(argv[2]) if len(argv) > 2 else 40
        sys.stdout.write("".join(tail(os.path.join(OUT, "pilot.log"), n)))
    elif cmd == "events":
        n = int(argv[2]) if len(argv) > 2 else 20
        sys.stdout.write("".join(tail(os.path.join(OUT, "events.jsonl"), n)))
    elif cmd == "wait":
        text = argv[2]
        seconds = float(argv[3]) if len(argv) > 3 else 30
        got = wait_for(text, seconds, 0)
        print(got if got is not None else f"timed out after {seconds:.0f} s waiting for '{text}'")
        return 0 if got is not None else 2
    elif cmd == "do":
        # send an order and wait for a line with the given text: do "<wait text>" <seconds> <order...>
        text, seconds = argv[2], float(argv[3])
        start = log_size()
        print("sent:", send(argv[4:]))
        got = wait_for(text, seconds, start)
        sys.stdout.write(got if got is not None else f"timed out after {seconds:.0f} s waiting for '{text}'\n")
        return 0 if got is not None else 2
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
