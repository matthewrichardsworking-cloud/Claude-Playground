#!/usr/bin/env bash
# Runs in CI. Offline on purpose. Checks that the mcp-windbg catalog entry, the repo settings and the
# kernel-tool deny-list all agree with each other and with the pin named in this folder's README.
set -euo pipefail
python3 - <<'EOF'
import json, re, sys

def fail(m):
    print("FAIL:", m); sys.exit(1)

cat = json.load(open("../../.claude-plugin/marketplace.json"))
settings = json.load(open("../../.claude/settings.json"))
readme = open("README.md", encoding="utf-8").read()
setup = open("setup.md", encoding="utf-8").read()

plugins = {p["name"]: p for p in cat.get("plugins", [])}
wb = plugins.get("mcp-windbg-uvx") or fail("catalog has no mcp-windbg-uvx entry")
src = wb["source"]
if src.get("source") != "git-subdir":
    fail(f"mcp-windbg-uvx must use the git-subdir source (a subdirectory plugin), got {src.get('source')!r}")
if "svnscha/mcp-windbg" not in src.get("url", ""):
    fail(f"mcp-windbg-uvx url is not svnscha/mcp-windbg: {src.get('url')!r}")
if src.get("path") != "plugins/mcp-windbg":
    fail(f"mcp-windbg-uvx path should be plugins/mcp-windbg, got {src.get('path')!r}")
sha = src.get("sha", "")
if not re.fullmatch(r"[0-9a-f]{40}", sha):
    fail(f"mcp-windbg-uvx sha must be a full 40-char lowercase commit, got {sha!r}")
if sha not in readme:
    fail("the pinned commit is not the one README.md records as reviewed")

if settings.get("enabledPlugins", {}).get("mcp-windbg-uvx@claude-playground") is not True:
    fail("settings.json does not enable mcp-windbg-uvx@claude-playground")

deny = set(settings.get("permissions", {}).get("deny", []))
need = {
    "mcp__mcp-windbg__open_kd_session",
    "mcp__mcp-windbg__open_kd_dump",
    "mcp__mcp-windbg__run_kd_command",
}
missing = need - deny
if missing:
    fail(f"the kernel-debugging tools must be denied in settings.json; missing: {sorted(missing)}")

# The universal-modder entry must survive untouched (this repo pins both in one catalog).
if "universal-modder" not in plugins:
    fail("the universal-modder catalog entry disappeared")

print(f"ok: mcp-windbg-uvx pinned (git-subdir) at {sha[:12]}, enabled, kernel tools denied; "
      "universal-modder still present")
EOF
