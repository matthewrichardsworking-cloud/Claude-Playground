"""Copy this project's notes, tools, mod scripts, add-on sources and test reports into the
Playground clone (AC7-Coop\\pg\\experiments\\2026-10-17-ace-combat-7-coop), the way earlier
sessions did by hand. It never copies game code bytes (code\\*.bin / *.txt listings: read from
the game's memory, never shared), backups, dumps, downloads, pictures, flight logs or pilot logs.

    python tools\\sync-playground.py          copy, then show `git status` of the clone
    python tools\\sync-playground.py --dry    only list what would change

Committing and pushing stay a separate, deliberate step (fetch and rebase first: other
sessions push to the Playground too).
"""

import filecmp
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEST = os.path.join(ROOT, "pg", "experiments", "2026-10-17-ace-combat-7-coop")

PATTERNS = [
    "README.md", "workbench.md", "playtest-bot.md", "plan.md", "research.md", "identity.md",
    "double-trigger-review.md", "code/snl-map.md",
    "tools/*.py", "tools/*.ps1",
    "mods/CoopPilotMod/Scripts/*.lua",
    "cpp/README.md", "cpp/build.ps1", "cpp/make-implib.py", "cpp/CoopPadMod/*.cpp", "cpp/CoopPadMod/*.hpp",
    "cpp/CoopNetMod/*.cpp", "cpp/CoopNetMod/*.hpp",
    "playtests/orders/*", "playtests/campaign-*.md",
    "playtests/missions/*.json", "playtests/missions/*/*.txt", "playtests/missions/*/*.csv",
    "playtests/missions/*/*.json", "playtests/missions/*/*.png", "playtests/missions/*/*.md",
    "playtests/2026-*/report.md", "playtests/2026-*/events.jsonl", "playtests/2026-*/order.yaml",
    "playtests/2026-*/saves-check.txt", "playtests/2026-*/pictures/results.png",
]
SKIP_BIG = 12 * 1024 * 1024          # nothing over 12 MB (raw searchlight recordings)


def main(argv):
    dry = "--dry" in argv
    changed = 0
    for pat in PATTERNS:
        for src in glob.glob(os.path.join(ROOT, pat)):
            if not os.path.isfile(src) or os.path.getsize(src) > SKIP_BIG:
                continue
            rel = os.path.relpath(src, ROOT)
            if rel.startswith("code") and not rel.endswith("snl-map.md"):
                continue
            base = os.path.basename(rel)
            if base.startswith("lights-recording") or base.startswith("survey-50m"):
                continue          # raw recordings and old surveys stay local (10+ MB each)
            dst = os.path.join(DEST, rel)
            if os.path.exists(dst) and filecmp.cmp(src, dst, shallow=False):
                continue
            changed += 1
            print(("would copy " if dry else "copy ") + rel)
            if not dry:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
    print(f"{changed} file(s) {'would change' if dry else 'copied'}")
    if not dry:
        subprocess.run(["git", "-C", os.path.join(ROOT, "pg"), "status", "--short"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
