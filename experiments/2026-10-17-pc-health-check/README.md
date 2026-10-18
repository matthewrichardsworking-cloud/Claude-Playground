# Health check of the PC setup

**Status:** worked. Everything set up on 17 Oct 2026 still runs.

The owner asked a Claude Code session on the PC to re-check what the earlier
sessions installed (REA, Ghidra, Co-op Anything, Python, Java, Node), changing
nothing. This is the recipe for doing that again, plus what turned up. The
owner's plain-language version is `Desktop\Claude Tools\START-HERE.md` on the
PC. There's no `check.sh`: every check needs the PC, and CI runs in the cloud.

## The checks

Run from Claude Code in the desktop app. `T` is `%USERPROFILE%\Desktop\Claude Tools`.

| What | Command | Result on 17 Oct |
|---|---|---|
| Tools in session | look for `mcp__rea__*` and `mcp__coop-anything__*` | both present (REA connects a few seconds late; search for it before saying it's missing) |
| MCP health | newest `%APPDATA%\Claude\claude-code\<ver>\<hash>\claude.exe mcp list` | 2.1.299: `rea` and `coop-anything` Connected |
| REA + Ghidra | `powershell.exe -Command "rea doctor --provider ghidra"` | `healthy: true`, Ghidra 12.1.4, JDK 21.0.12.1 |
| Real analysis | `powershell.exe -Command "rea analyze C:\Windows\System32\whoami.exe --provider ghidra --json"` | 57 s, 341 functions, 308 strings, 9 sections |
| Co-op Anything | `search_directory` "deus ex", `list_docs` | 5 entries; 19 playbook pages, 6 game write-ups, 12 skills |
| Python | `python --version`, `py --list`, `pip --version` | 3.15.0; 3.15 and 3.13; pip 26.2.1 (3.15) |
| Java | `T\jdk-21\bin\java.exe -version` | Temurin 21.0.12.1+1. Plain `java` is still Oracle 8u503 |
| Node | `T\node\node.exe --version` | v24.22.0 |
| Old venvs | read each `pyvenv.cfg`, run its `Scripts\python.exe --version` | both `home = ...\Python\Python310` (3.10.6); "No Python at ..." |
| Recycle Bin | Shell.Application namespace 10, plus `HKCU\...\Explorer\BitBucket\Volume\*\MaxCapacity` | 6 items from 17 Oct, 14,353,736,185 bytes (13.37 GiB, which Windows shows as GB); C: limit 47,476 MB |

## Things that tripped me up

- **The PowerShell tool skips the profile.** It runs `powershell.exe
  -NoProfile`, and the owner's profile is what sets `GHIDRA_INSTALL_DIR` and
  `JAVA_HOME` and puts `T\node` on PATH. So `T\node\rea.cmd doctor` straight
  from the tool reports Ghidra as missing. Wrapping the command in
  `powershell.exe -Command "..."` loads the profile (execution policy is
  Bypass at machine level, so it runs). The MCP server is unaffected because
  `~/.claude.json` gives it the same two variables.
- **Clone into a short folder name.** `git -c core.longpaths=true clone ...
  Claude-Playground` failed with "'$GIT_DIR' too big". Git on Windows refuses a
  `.git` path longer than about 220 characters (PATH_MAX minus 40) in the https
  helper, whatever `core.longpaths` says. The session folder's real path is 203
  characters, so `Claude-Playground\.git` came to 226 and `pg\.git` to 211.
  Put the `-c` after `clone` (`git clone -c core.longpaths=true <url> pg`) so
  it's saved in the clone's config. With `git -c ... clone` it applies to the
  clone only, and the first `git add` fails with "Filename too long" because
  paths under `.git\objects` pass 260 characters.
- **`%APPDATA%\Claude` is itself redirected.** It resolves to
  `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude`, so
  claude.exe and the session folders aren't at the `%APPDATA%` path for programs
  outside the app. START-HERE.md uses the `Packages` path so the owner's own
  PowerShell window finds claude.exe.
- **Doctor's other warnings are optional extras.** Hopper, IDA and jadx aren't
  installed, and REA isn't registered with the desktop chat app (only with
  Claude Code). That's why `environment_healthy` is false while the Ghidra
  scope is healthy.

## Left as it was

The owner asked for these to be confirmed, not fixed:

- `Claude Apps\JapaneseTutor\.venv` (55 MB) needs only `anthropic` and
  `pillow`. Rebuilding it means moving the old `.venv` out first (its
  site-packages hold 3.10 builds that pip would count as installed), then
  `py -3.13 setup_env.py`. 3.13 is the safe choice until those packages ship
  3.15 builds.
- `Desktop Icons\stable-diffusion-webui` is an AUTOMATIC1111 checkout from Oct
  2022 with a 4.5 GB venv, and needs Python 3.10 exactly. Options: restore
  `Python310` from the Recycle Bin, install 3.10 for all users, or move to a
  maintained fork. The owner decides.
- The Recycle Bin items stay. The earlier log said 13.7 GB; it's 13.37 GiB.
