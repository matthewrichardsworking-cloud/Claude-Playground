#!/usr/bin/env bash
# Runs in CI. Offline on purpose: a slow GitHub or a change upstream must not turn every build red.
# Checks that the repo's plugin catalog and project settings agree, that the pinned commit is the one this
# folder's README says was reviewed, and that the field-note draft has every key the template asks for and
# no template text left.
set -euo pipefail
python3 - <<'EOF'
import json, re, sys

def fail(msg):
    print("FAIL:", msg)
    sys.exit(1)

cat = json.load(open("../../.claude-plugin/marketplace.json"))
settings = json.load(open("../../.claude/settings.json"))
readme = open("README.md", encoding="utf-8").read()

name = cat.get("name")
plugins = {p["name"]: p for p in cat.get("plugins", [])}
um = plugins.get("universal-modder") or fail("catalog has no universal-modder entry")
src = um["source"]
if src.get("source") != "github" or src.get("repo") != "rehan-remade/universal-modder":
    fail(f"unexpected source {src}")
sha = src.get("sha", "")
if not re.fullmatch(r"[0-9a-f]{40}", sha):
    fail(f"sha must be a full 40-character lowercase commit, got {sha!r}")
if sha not in readme:
    fail(f"pinned commit {sha} is not the one README.md says was reviewed")

mk = settings.get("extraKnownMarketplaces", {}).get(name) or fail(f"settings don't declare marketplace {name!r}")
if mk["source"] != {"source": "github", "repo": "matthewrichardsworking-cloud/Claude-Playground"}:
    fail(f"settings point marketplace {name!r} somewhere else: {mk['source']}")
enabled = settings.get("enabledPlugins", {}).get(f"universal-modder@{name}")
if not isinstance(enabled, bool):
    fail(f"settings have no true/false entry for universal-modder@{name} (turning it off means false, not deleting it)")

note = open("field-note-ace-combat-7.md", encoding="utf-8").read()
m = re.match(r"---\n(.*?)\n---\n", note, re.S) or fail("field note has no frontmatter")
keys = {line.split(":", 1)[0] for line in m.group(1).splitlines() if re.match(r"^[a-z_]+:", line)}
want = {"kind", "title", "game", "games_also", "game_version", "platform", "engine", "route", "tools",
        "anti_cheat", "status", "agents", "humans", "date", "links", "tags"}
if want - keys:
    fail(f"field note is missing keys: {sorted(want - keys)}")
# The same placeholders upstream's `um kb check` looks for (um/kb.py, commit 6a8865ae).
for ph in ("FILL IN", "Two to four sentences:", "Numbered; each one symptom", "What you saw. **Cause:** what it really was"):
    if ph in note:
        fail(f"field note still has template text: {ph!r}")

state = "on" if enabled else "off"
print(f"ok: universal-modder pinned at {sha[:12]} in catalog {name!r}, turned {state} in project settings; "
      "field note has every key and no template text")
EOF
