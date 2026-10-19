"""Hot-reload the pilot in the running copy (copy the scripts, Ctrl+P), wait until it says
"ready", then send it an order again (a reload forgets the order it was flying).

    python tools\reload-pilot.py                 reload, then "fly attack"
    python tools\reload-pilot.py fly route ...   reload, then this order
    python tools\reload-pilot.py --none          reload only (in menus)
"""
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import pilot  # noqa: E402

SRC = os.path.join(ROOT, "mods", "CoopPilotMod", "Scripts")
DST = r"C:\AC7-Coop-Game\ue4ss\Mods\CoopPilotMod\Scripts"


def main(argv):
    for name in os.listdir(SRC):
        if name.endswith(".lua"):
            shutil.copy2(os.path.join(SRC, name), os.path.join(DST, name))
    start = pilot.log_size()
    subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "game-input.ps1"), "-Keys", "Ctrl+P"],
                   capture_output=True, text=True)
    got = pilot.wait_for("ready (orders", 15, start)
    print("pilot reloaded" if got else "no 'ready' line within 15 s")
    if "--none" in argv:
        return 0
    words = argv[1:] or ["fly", "attack"]
    time.sleep(0.5)
    print("sent:", pilot.send(words))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
