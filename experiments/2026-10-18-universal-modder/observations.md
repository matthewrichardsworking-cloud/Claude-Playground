# universal-modder: observations

Review of [rehan-remade/universal-modder](https://github.com/rehan-remade/universal-modder) at commit
`6a8865ae171b406f50892c7f46fc5f45655269eb` (17 Oct 2026). Plain-language summary in [README.md](README.md);
this file has the detail, for later sessions and for anyone reporting things upstream.

## How the review was done

- **By hand in this session:** installed it as a Claude Code plugin, ran their test suite and their own CI
  checks, ran `claude plugin validate`, ran `um scan` on a fake Ace Combat 7 folder, wrote our field-note
  draft with `um kb new` and checked it with `um kb check`.
- **A review workflow:** eleven reader agents, one per part of the repo (main skill and safety rules, engine
  guides, the other skills in two groups, the `um` core, `um` media tools, `um win` and its PowerShell, the
  plugin packaging, the knowledge base, the example mods, fit with the Playground). Each read its part and ran
  what it could in a scratch folder. One checker agent per part then went through every medium or high finding
  and tried to reproduce it and to knock it down; anything still rated high got a second, separate skeptic.
  A completeness critic then picked three gaps (the OpenCode plugin, `um render3d`, `um kb pr`), each with its
  own reader and checker. 36 agents in all; none failed.
- **Result:** 153 findings. 73 confirmed by a checker, 71 low-severity ones left as the reader reported them,
  9 plain observations. No checker rejected a finding outright, but they lowered the severity of 34 of them,
  each by one step (15 from high to medium, 19 from medium to low). Exactly one finding is still rated high after the second skeptic.
- **Limits:** this is a Linux container. Nothing that needs Windows or a game was run (the `um win` findings
  come from reading the code, plus stand-ins for the parts that could be imitated). Codex, Cursor, Gemini
  CLI and Copilot were not installed; OpenCode was, in a sandbox, by the gap reader.

## Verdict

A serious, well-made toolkit with honest docs and good habits, and with safety nets that are thinner than the
docs suggest. The main skill's loop is sound and every command and file it cites exists. The knowledge base is
the most valuable part: 265 notes with exact versions, how each result was checked, and numbered gotchas, and
its index is generated and checked by CI. Most problems fall into three groups:

1. **The checking tools promise more than they do.** `um publish check` and `um kb pr` are presented as the
   guard against shipping game files, decompiled code, secrets and private material. Both have easy ways to
   let those through while reporting success.
2. **The Windows input tool's safety rule has holes.** "Input only reaches the game" holds for keyboard input,
   but not for mouse clicks, and the default retry takes the focus back from the user.
3. **The rules are written in several places, in slightly different words**, and a few of those versions
   contradict each other.

For the Playground it is a useful library to read from and a good field-note format. It doesn't replace our
own Ace Combat 7 tools, and in a few places it would steer a session into breaking the owner's AC7 rules
(see "What it means for the Playground").

## Worth borrowing

- **The field-note format.** Exact build, route and the routes rejected, how you knew it worked, what you did
  *not* check, gotchas as symptom → cause → fix. Our AC7 draft fits it with no strain.
- **Evidence labels.** Several notes and guides tag each claim as verified in game, checked statically, or
  unverified, with the build it was checked on (`isaac.md`; the STALKER 2 note's `[kit]/[observed]/[inference]`;
  `knowledge/techniques/evidence-levels-for-mashup-claims.md`: only a real run supports "working").
- **Generated, CI-checked index.** `INDEX.md` and `index.json` are built from note headers, and CI fails when
  `INDEX.md` drifts (it doesn't check `index.json`, a low finding). Rebuilding both matched all 265 notes exactly.
- **Defaults that do nothing until told.** `um backup restore` and `um kb pr` are dry runs until `--yes`;
  restore snapshots the current state first; backups never overwrite each other.
- **Key handling in `um fal`.** The key goes to `secret-tool` on stdin, never on a command line; the plain-file
  fallback is created owner-only before the first byte is written; manifests never record it. The one leak
  found: the key follows a redirect to another host (low, `um/fal.py:276`).
- **Hard-won rules with the reason attached** (the GTA V focus-steal close call, `pkill -f` matching the agent's
  own shell, crash reporters blocking a Steam relaunch), placed where the agent will see them, including in
  `um scan`'s report.
- **Small Windows-proofing habits.** `.gitattributes` pins LF for shell scripts and CRLF for `.cmd`, with the
  reason; the ffmpeg download is checksum-checked and its docstring says honestly what that does and doesn't
  protect against; CI actions are pinned to full commit hashes.
- **The Shadow of War offline-mode example** is a careful model for keeping a game's online services offline
  without touching its DRM: an in-process WinHTTP stand-in that opens no port and validates every object id.

## The problems that matter most

All confirmed by a checker. Severity after checking.

### The checking tools let things through

- **`um publish check` reports PASS when `--game` isn't a real folder** (medium; `um/publish.py:62`). A typo,
  a quoted `~/...` path (the skill writes it quoted, and quotes stop `~` expanding) or a Windows path on Linux
  means the game-file comparison silently compares against nothing.
- **Its secret scan only opens files with listed extensions** (medium; `um/publish.py:91`). Keys in
  `.env.local`, `gradle.properties`, `.kts`, `.mjs`, extension-less files or UTF-16 text pass. Common
  mod-world credentials (Discord bot tokens and webhooks, Google `AIza` keys) aren't in its patterns at all.
- **Decompiled code is only ever a warning**, and the fingerprints miss the common cases: ILSpy/dnSpy C#,
  CFR's real header, Forge SRG names (medium; `um/publish.py:34-37`). Assets extracted from `.pak`/`.assets`
  files never match the install byte for byte, so they pass too. It also ignores git history, while the skill
  says to commit every step (medium; `um/publish.py:41`).
- **`um kb pr`, the one command that publishes as the user, can publish far more than the note**
  (gap reader, ran it end to end against a fake GitHub):
  - it branches from whatever is checked out, so unpushed local commits go into the public PR (`um/kb.py:390`);
  - it commits with no file list, so anything already staged goes too (`um/kb.py:392`);
  - every file in the note's `media/` folder goes, unchecked for secrets or size, and photos keep their
    EXIF data, GPS position included (`um/kb.py:384`, `:391`);
  - it drops `kb check`'s warnings and still ticks "no decompiled code" in the PR body for the user
    (`um/kb.py:375`);
  - it rebuilds the index from every note on disk, so drafts never meant for sharing get listed (`um/kb.py:404`);
  - the dry run the human approves hides most of this (`um/kb.py:400`), and the clone is left on the PR branch,
    so the next PR stacks on it.
- **The OpenCode plugin's tool never asks OpenCode for permission** (medium; `plugins/opencode/index.ts:152`):
  `ask` rules are ignored, so `um kb pr --yes`, `um win kill` or paid fal jobs run with no prompt.

### Windows input (from reading the code; not run on Windows)

- **Mouse clicks can land in another app** (the one finding still rated **high**; `um/ps1/WinDrive.ps1:189`).
  The safety check looks at which window is in front, but a click goes to whatever window is under the
  cursor. A point outside the game's window, or a window floating over it, gets the click; that app comes to
  the front, the button-up is then refused, and the left button stays held.
- **`um win drive` takes the focus back by default** (medium; `um/win.py:401`). When the user has switched
  away, the tool taps Alt into the app they're using, pulls the game to the front and replays the command;
  `--no-retry` turns this off but no skill mentions it. This is the situation the toolkit's own GTA V
  incident warns about.
- **The target is matched by process name only** (medium; `um/ps1/WinDrive.ps1:86`): two `java` processes, or
  two copies of a game, both pass.

### Data-handling bugs

- **`um backup restore` goes to the wrong folder when the backup was made from a relative or `~` path**, and
  reports success (medium; `um/backup.py:73`).
- **`um win reg set` says "backup:" even when the backup failed**, then changes the registry
  (medium; `um/win.py:455`).
- **Repeat generations overwrite earlier paid outputs**, and the manifest then points at the wrong file
  (medium; `um/sprixen.py:333`, `um/fal.py`). A dropped connection while waiting on a paid fal job crashes
  without printing the request id needed to fetch the result later (medium; `um/fal.py:282`).
- **The launchers run `python -m um` from the current folder** (medium; `bin/um:15`), so a file named like a
  standard Python module (`json.py`) in a downloaded game or mod folder runs as code when you run `um` there.

### Rules that disagree with each other

- "Never disable anti-cheat; use only the official offline option" sits next to an endorsed Elden Ring route
  through a third-party launcher "with EAC disabled" (medium; `skills/mod-any-game/SKILL.md:162`).
- The reverse-engineering skill links a 1 GB archive of old forum attachments as a source of tools; the research
  skill forbids fetching exactly that (medium; `skills/reverse-engineering/SKILL.md:78`).
- `publish-mod` says "MIT/Apache is common" with no word on ports, while `port-a-mod` says a port keeps the
  original's licence (medium; `skills/publish-mod/SKILL.md:46`).
- The multiplayer line is worded four ways across AGENTS.md, README, the skill and CONTRIBUTING (low).
- In a Claude Code plugin install, `CLAUDE.md` (and the AGENTS.md rules it pulls in) is not loaded; Claude Code's
  validator says so (found by hand, not by the checkers). Plugin users meet the rules only through the skills.

### The Unreal guide, measured against Ace Combat 7

The guide points to the right main route (UE4SS Lua and its object dump, which is what carried our AC7 work),
but assumes a modern game with a standard layout. On AC7 it would have been wrong on:

- the pak version: its one packing command hard-codes V11; UE 4.18 uses V4 (medium; `unreal.md:33`);
- recognising the game: `um scan` and the guide expect `Binaries/Win64/*-Shipping.exe`, so AC7 gets "Unreal,
  70%" and no version, though `++UE4+Release-4.18` is in the exe (medium; `unreal.md:3`, `um/scan.py:554`);
- the save folder: one template path, no publisher folder, no per-SteamID folder, no Steam Cloud warning
  (medium; `unreal.md:6`);
- reading the exe: nothing says SteamStub or Denuvo leave the code scrambled on disk (low; `unreal.md:45`);
- C++ mods: listed as routine, with no word on the Epic-linked GitHub account, Rust and exact-build matching
  the documented build needs (low; `unreal.md:20`).

Its knowledge base also has a UE4SS note that calls a game function from `LoopAsync`, which runs off the game
thread; the same mistake crashed our AC7 bot (medium;
`knowledge/games/webcam-behind-the-screen/runtime-cheat-menu-for-money-subscribers-and-needs-via-ue4ss.md:98`).
Our field-note draft records the fix.

### Other confirmed bugs, briefly

- `um video beats` is off by up to 2.5% in tempo and half a beat in phase; contact-sheet labels are about half
  an interval early (`um/video.py:166`, `:100`).
- `um sprite seamless` leaves seams in the middle of each tile edge; `um sprite frames --kind bob` wraps a pixel
  row from top to bottom (`um/sprite.py:265`, `:221`).
- `um render3d --engine eevee --shadows` writes an opaque grey square as the shadow pass; `--ambient` barely
  changes anything (`um/blender/render_sprites.py:60`, `:98`). Otherwise render3d checked out on real Blender
  4.5 and 5.2, frame for frame.
- `um fal key clear` says "nothing to remove" and leaves the key active on Windows and macOS (`um/fal.py:243`).
- Codex and Cursor plugin installs never send the fal key (`mcp.json:7`); the Gemini extension loads the
  clone-only AGENTS.md into every Gemini session (low).
- In a plugin install, `um kb new` writes notes into the plugin's own cache folder (`um/kb.py:51`).
- Examples: the GTA × Minecraft link listens on 127.0.0.1 with no token and no Origin check, so a web page could
  drive both games (medium; `examples/minecraft-gta5-passthrough/.../HostLink.java:36`); its `install.sh
  --remove` deletes a user's own ScriptHookV and ReShade files; the Shadow of War log that recovery depends on
  is wiped on every launch.

## What it means for the Playground

| What | Meaning here |
|---|---|
| Overlap with our AC7 tools | `um backup` does what `backup-saves.ps1` + `compare-saves.ps1` do; `um win shot/drive` what `game-input.ps1` does, plus an "is the user idle?" check ours lacks. `um win record` + `um video` would close AC7's open "video of the puppet" item. |
| Prior art we didn't use | The knowledge base already had co-op notes before our AC7 plan: the Assassin's Creed IV puppet and UDP notes and a "how multiplayer mods sync the world" technique note. |
| Rules that clash with the owner's AC7 rules | Their safety page allows "a private dump" of a DRM-unpacked exe; the AC7 addendum forbids saving whole code sections or an unscrambled exe, even privately. `um win launch --steam 502500`, or launching the copy's exe by path, starts the real modded install. The owner's AC7 rules win in both cases (setup.md says so). |
| PC snags | `um win setup` downloads a daily ffmpeg build into `%LOCALAPPDATA%`, which the Store-app Claude hides; the hook's PATH line reaches Bash but not PowerShell; the default `python` 3.15 lacks some packages. Details and fixes in setup.md. |
| Cost of turning it on repo-wide | Every PC session in the repo gets the hook, a fal connection that fails without a key, and about 2,800 tokens of skill descriptions. Worth it while game modding is what the Playground mostly does; easy to turn off (setup.md). |
| `um publish check` on the Playground | 0 failures, 6 warnings: the name of the owner's Windows user folder appears in `ace-combat-7-coop/workbench.md`, `tools/playtest.py` and four `saves-check.txt` reports. Low risk (the GitHub name already shows the same first name), left as is. |

## Found by hand in this session

- `claude plugin validate` passes with three warnings: no version in `.claude-plugin/plugin.json` (Claude Code
  then versions it by commit), no version in the marketplace entry, and `CLAUDE.md` not loaded for plugins.
- The first `um` run from the plugin folder creates a `.venv` and a fresh `uv.lock` there (none is committed
  upstream, so library versions float). The installed plugin came to 113 MB.
- The SessionStart hook keeps the first `um` path written to a session's environment file, without checking it
  is the current install (seen after a reinstall; setup.md gotcha 3).
- `um scan` on an AC7-shaped folder: "Unreal Engine [70%]", UE4SS found, no version, no DRM note, no save folder.
- Two Claude Code gotchas unrelated to the plugin, in setup.md: `marketplace remove` run inside a repo also
  strips that repo's settings file; `claude -p` test runs share the parent session's environment file.

## Not done

- **Nothing reported upstream.** Filing issues is outward-facing and the owner's call. If the owner wants it:
  their `SECURITY.md` asks for private reporting (GitHub's "Report a vulnerability") for the input,
  key-leak and `kb pr` findings; the rest could be ordinary issues.
- **The field-note draft wasn't submitted.** If it ever is, don't use `um kb pr` from a working clone (see
  above): use a fresh fork with only the note, and only with the owner's OK.
- No Windows or in-game tests; no Codex, Cursor, Gemini CLI or Copilot installs.

## Appendix: every finding

Generated from the review's output. **Severity** is after checking (the reader's own rating in brackets when the checker changed it). **confirmed** means a separate agent reproduced or traced it; *not re-checked* items are low-severity ones only the reader looked at (most readers ran them, but nobody tried to disprove them). Paths are in the upstream repo unless marked Playground.


### mod-any-game skill, safety rules, case studies

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | um publish check silently PASSes when --game is not an existing folder (quoted ~ path, Windows path on Linux, typo, exe path) | `um/publish.py:62` |
| medium | confirmed | Docs say publish check blocks decompiled code and catches extracted assets; it does neither for the common cases | `skills/mod-any-game/references/safety.md:46` |
| medium | confirmed | Anti-cheat rule contradicts the endorsed Elden Ring route (ModEngine2/me3 'EAC disabled') | `skills/mod-any-game/SKILL.md:162` |
| medium | confirmed | um win drive takes the game's focus back by default and can leave it topmost, against the documented input rules (which also disagree with each other) | `um/win.py:401` |
| medium | confirmed | Publish check ignores git history, while the skill tells agents to commit every step in the mod's repo | `um/publish.py:41` |
| low (medium) | confirmed | The multiplayer and cheats line is worded four different ways across AGENTS.md, README, SKILL/safety and CONTRIBUTING | `AGENTS.md:48` |
| low (medium) | confirmed | um backup restore leaves an installed loader in place unless --clean is passed, and no doc mentions --clean | `skills/mod-any-game/SKILL.md:166` |
| low (medium) | confirmed | The kill-by-PID rule can't be followed for windowless processes: um win ps hides them | `um/win.py:179` |
| low | not re-checked | um win reg set reports a backup it never checks, and the .reg file can't undo values it adds | `um/win.py:455` |
| low | not re-checked | MODLOG.md placement is unspecified and publish check misses common user-path forms and Steam IDs | `skills/mod-any-game/SKILL.md:52` |
| low | not re-checked | um win kill crashes with a Python traceback off Windows/WSL; the PID rule names only a Windows tool | `um/win.py:195` |
| low | not re-checked | Main skill never points to the game-research-websearch skill, and the project count disagrees | `skills/mod-any-game/SKILL.md:37` |

### engine playbooks

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium | confirmed | repak example hard-codes pak V11; older UE4 games need another version | `skills/mod-any-game/references/engines/unreal.md:33` |
| medium | confirmed | Engine recognition and version read assume a Binaries/Win64 *-Shipping.exe | `skills/mod-any-game/references/engines/unreal.md:3` |
| medium | confirmed | Save and config path template is wrong for many UE games; no Steam Cloud or lab isolation advice | `skills/mod-any-game/references/engines/unreal.md:6` |
| low (medium) | confirmed | No warning that SteamStub/Denuvo hides the exe's code from Ghidra and AESDumpster | `skills/mod-any-game/references/engines/unreal.md:45` |
| low (medium) | confirmed | 'C++ mods for heavier work' leaves out what the UE4SS C++ route costs | `skills/mod-any-game/references/engines/unreal.md:20` |
| low | not re-checked | UE4SS install layout mixes up versions (xinput1_3 with a ue4ss/ folder) | `skills/mod-any-game/references/engines/unreal.md:10` |
| low | not re-checked | FModel/UAssetGUI advice leaves out .usmap mappings for UE 4.26+/UE5 | `skills/mod-any-game/references/engines/unreal.md:29` |
| low | not re-checked | 'UE 4.26+ and UE5 use IoStore' contradicts the repo's own Half Sword note | `skills/mod-any-game/references/engines/unreal.md:4` |
| low | not re-checked | um scan sends Frostbite, CryEngine and Cocos games to native.md, which covers none of them | `um/scan.py:488` |
| low | not re-checked | 'fmodel-mcp' named with no owner or URL; at least 8 unrelated repos share the name | `skills/mod-any-game/references/engines/unreal.md:47` |
| info | observation | Pitfalls say nothing on co-op/online layers, second instances or UE4SS threading (AC7 lessons) | `skills/mod-any-game/references/engines/unreal.md:50` |

### skills: game-recon, game-research-websearch, reverse-engineering, game-automation, showcase-video

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | `um win drive` steals focus by default, breaking game-automation's own input-safety rule | `skills/game-automation/SKILL.md:44` |
| medium | confirmed | reverse-engineering points at the XeNTaX attachments dump; the research skill bans fetching forum attachments | `skills/reverse-engineering/SKILL.md:78` |
| medium | confirmed | showcase-video's Windows-path commands fail from WSL: `first-frame` silently says 0.0, `mux` crashes | `skills/showcase-video/SKILL.md:24` |
| medium | confirmed | 'Multiply coordinates back x3' is off by about 1%, and wrong under Windows display scaling | `skills/game-automation/SKILL.md:49` |
| low (medium) | confirmed | unpack_upk.py chunk-table search accepts false positives on small single-chunk packages | `skills/reverse-engineering/references/ue3-packages/unpack_upk.py:59` |
| low (medium) | confirmed | `um video first-frame` returns 0.0 on failure, the same answer as 'gameplay starts at 0' | `um/video.py:145` |
| low | not re-checked | game-recon description contains `<game>` placeholders, which Anthropic's skill rules reject | `skills/game-recon/SKILL.md:3` |
| low | not re-checked | Documented `uv run --python 3.12 ... unpack_upk.py` deletes and rebuilds the repo's .venv | `skills/reverse-engineering/references/ue3-packages/README.md:44` |
| low | not re-checked | Linux/Wayland advice: grim doesn't work on GNOME or KDE, and Linux input has no focus guard | `skills/game-automation/SKILL.md:100` |
| low | not re-checked | Skill's first recording command crashes when C:\caps doesn't exist | `um/win.py:350` |
| low | not re-checked | `um video --help` (which the skill cites for the full format) gives the wrong recorder file names | `um/video.py:7` |
| low | not re-checked | Wayback CDX example returns the oldest 50 rows, not 'every snapshot' or recent ones | `skills/game-research-websearch/SKILL.md:49` |

### skills: fal-assets, asset-pipeline, mashup-mods, publish-mod, port-a-mod, share-field-notes

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | publish check passes leaked keys in .env.local, gradle.properties, .kts, .mjs and any file without an extension | `um/publish.py:91` |
| medium | confirmed | Decompiled-code check misses CFR's real header and SRG names, the exact output port-a-mod prescribes | `um/publish.py:37` |
| medium | confirmed | publish-mod ignores port licensing; 'MIT/Apache is common' conflicts with port-a-mod's hard rules | `skills/publish-mod/SKILL.md:46` |
| low (medium) | confirmed | port-a-mod's worked example keeps the decompile in the port's own repo, right after saying not to | `skills/port-a-mod/SKILL.md:78` |
| low (medium) | confirmed | share-field-notes' no-clone install cannot write, index or PR a note | `skills/share-field-notes/SKILL.md:13` |
| low | not re-checked | um kb check passes an untouched technique-note scaffold | `um/kb.py:253` |
| low | not re-checked | fal credit check accepts any 'fal' substring (Fallout, fallback, false) | `um/publish.py:111` |
| low | not re-checked | fal-assets lists fal-ai/meshy/v5/remesh, which fal no longer serves | `skills/fal-assets/SKILL.md:83` |
| low | not re-checked | Documented frames/*.png glob packs 10+ frames out of order | `skills/asset-pipeline/SKILL.md:34` |
| low | not re-checked | fal_manifest.jsonl records public fal-storage URLs of every uploaded input, and the skills say to keep it with the assets | `skills/fal-assets/SKILL.md:127` |
| low | not re-checked | Raw knowledge/... paths in mashup-mods and port-a-mod only resolve in a clone | `skills/mashup-mods/SKILL.md:21` |
| low | not re-checked | `um fal run key=@file` only uploads keys ending in url/urls; others send the literal '@file' | `um/fal.py:430` |

### um CLI core: cli, common, scan, kb, backup, publish

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | backup restore/diff go to the wrong folder when the snapshot was made from a relative or ~ path, and report success | `um/backup.py:73` |
| medium (high) | confirmed | publish check skips secret scanning for .env.local, extension-less key files, .config and UTF-16 files, then prints PASS | `um/publish.py:91` |
| medium | confirmed | Both launchers run `python -m um` from the caller's folder, so a planted .py there runs on every um command | `bin/um:15` |
| medium | confirmed | In a plugin install, `um kb new` writes notes into the plugin's own folder, and `kb pr` regenerates the index and runs git there | `um/kb.py:51` |
| medium | confirmed | Known-game matching by substring gives sequels and spin-offs the original's route; for Silksong it also hides the engine route | `um/scan.py:847` |
| medium | confirmed | Secret patterns miss the credentials most often found in game mods (Discord bot tokens and webhooks, Google API keys, etc.) | `um/publish.py:22` |
| medium | confirmed | publish WARN checks: ILSpy/dnSpy C# passes, escaped Windows user paths are missed, and the fal credit check accepts 'Fallout' | `um/publish.py:34` |
| low (medium) | confirmed | Game-name lookup: a query with no ASCII letters or digits (e.g. a CJK name) matches an arbitrary game, and ambiguous queries are picked silently | `um/scan.py:186` |
| low | not re-checked | Default backup name is the folder's basename, so games sharing a save-folder name (Unreal's 'Saved') share one history | `um/backup.py:48` |
| low | not re-checked | bin/um creates .venv and an unpinned uv.lock inside the install folder, and a read-only install fails outright | `bin/um:15` |
| low | not re-checked | Anti-cheat globs: 'ace-base' flags ordinary asset names, and a BattlEye client that sits only in a subfolder is missed | `um/scan.py:333` |
| low | not re-checked | kb pr commits every file in the note folder's media/ without any size check | `um/kb.py:384` |

### um CLI media: fal, comfy, sprixen, sprite, render3d, video

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | Repeat generations silently overwrite earlier paid outputs, and the manifest then points at the wrong asset | `um/sprixen.py:333` |
| medium | confirmed | fal/comfy HTTP layer crashes on connection drops, timeouts and non-JSON replies; a crash while polling a paid job loses its request ID | `um/fal.py:282` |
| medium | confirmed | `um video beats` tempo is off by up to 2.5% and the first beat by up to half a beat, so beat-locked cuts drift off the grid | `um/video.py:166` |
| medium | confirmed | Contact-sheet timestamps are about every/2 seconds early, so in-points picked from the sheet are wrong | `um/video.py:100` |
| medium | confirmed | `um fal key clear` says 'nothing to remove' and leaves the key active on hosts without a keyring (Windows, macOS, WSL) | `um/fal.py:243` |
| medium | confirmed | `um sprite seamless` leaves hard seams at the middle of every tile edge | `um/sprite.py:265` |
| medium | confirmed | `um sprite frames --kind bob` wraps a row from one edge to the other (feet appear above the head) | `um/sprite.py:221` |
| low | not re-checked | Cost safety: job submit is re-POSTed up to 4 times on 5xx, and no recipe shows or records a price | `um/fal.py:284` |
| low | not re-checked | API keys follow cross-host redirects (urllib copies Authorization), and Sprixen accepts an http:// base URL | `um/fal.py:276` |
| low | not re-checked | Default `fill: blur` fails for small output sizes, including --preview of a 640x360 EDL | `um/video.py:330` |
| low | not re-checked | Palette ops: pixelate spends a palette slot on transparent pixels, and snap_palette needs about 1.6 GB for a 1024x1024 image | `um/sprite.py:147` |
| low | not re-checked | `um sprite slice` silently drops empty frames, changing frame count and numbering | `um/sprite.py:209` |

### um win and the PowerShell tools

| Severity | Status | Finding | Where |
|---|---|---|---|
| high | confirmed | Clicks and wheel input are checked against the foreground window, but mouse input goes to the window under the cursor | `um/ps1/WinDrive.ps1:189` |
| medium (high) | confirmed | WinDrive identifies the target only by process name, so another process with the same name passes the safety check | `um/ps1/WinDrive.ps1:86` |
| medium (high) | confirmed | Under WSL, `um win record --out <Linux path>` writes the timing JSON and log to an oddly named file in the current folder and falsely warns that no frames were captured | `um/win.py:317` |
| medium | confirmed | Focus taps Alt into whatever app is in front, and Drive automatically takes the foreground back whenever it drifts, replaying half-finished commands | `um/win.py:401` |
| medium | confirmed | If audio capture fails, nothing reports it: the run still says '(+ audio)' and the JSON points at a missing audio file | `um/win.py:344` |
| medium | confirmed | `um win reg set` prints 'backup:' and makes the change even when the backup failed, and the backup can't undo a newly added value | `um/win.py:455` |
| low (medium) | confirmed | A refused key-up or button-up leaves keys and mouse buttons held down, which affects the app that now has focus | `um/ps1/WinDrive.ps1:216` |
| low (medium) | confirmed | Typed text containing a newline or carriage return runs as extra WinDrive commands and shifts every later reply by one | `um/win.py:428` |
| low | not re-checked | launch passes paths and arguments through cmd.exe, so &, ^ and %VAR% in them are interpreted when they contain no space | `um/win.py:211` |
| low | not re-checked | `um win kill` and `um win reg` exit 0 when the Windows tool fails | `um/win.py:196` |
| low | not re-checked | Window selectors are pasted unescaped into the ffmpeg filter string, and --exe means different things on different paths | `um/win.py:223` |
| info | observation | The C# lives in an expandable PowerShell here-string, so any `$` added later would be silently rewritten | `um/ps1/WinDrive.ps1:31` |

### plugin packaging, hooks, MCP configs, agents, CI

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium | confirmed | Codex and Cursor plugin installs never send FAL_KEY to the fal MCP server | `mcp.json:7` |
| low (medium) | confirmed | Gemini extension injects clone-only AGENTS.md into every Gemini session | `gemini-extension.json:5` |
| low | not re-checked | SessionStart hook is redundant for plugin installs and runs unpinned code from main every session | `hooks/hooks.json:9` |
| low | not re-checked | .claude-plugin/plugin.json has no version while every other manifest says 0.2.0 | `.claude-plugin/plugin.json:2` |
| low | not re-checked | uv.lock is gitignored, so CI and every install resolve dependencies fresh from PyPI | `.gitignore:4` |
| low | not re-checked | Hook writes the root path unescaped into a file Claude Code sources before each Bash call | `hooks/add-to-path.sh:9` |
| low | not re-checked | Hook's env line is not a plain assignment, so PowerShell commands lose every hook's env vars | `hooks/add-to-path.sh:9` |
| low | not re-checked | Duplicate marker doesn't stop duplicates across the plugin and clone hooks | `hooks/add-to-path.sh:8` |
| low | not re-checked | test.yml declares no token permissions and keeps checkout credentials | `.github/workflows/test.yml:2` |
| info | observation | Claude Code could prompt for and store the fal key itself (userConfig), as the Gemini manifest already does | `.mcp.json:7` |
| info | observation | Subagents inherit every tool; 'never touches the game' is prose-only | `agents/mod-offline-worker.md:3` |
| info | observation | marketplace.json $schema URL serves an HTML page, not a JSON schema | `.claude-plugin/marketplace.json:2` |

### knowledge base

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium | confirmed | WebCam UE4SS note tells readers to call a game function from LoopAsync, which runs off the game thread | `knowledge/games/webcam-behind-the-screen/runtime-cheat-menu-for-money-subscribers-and-needs-via-ue4ss.md:98` |
| medium | confirmed | Wukong note says there is no prior art for render injection into any UE5 game, but UEVR is exactly that | `knowledge/games/black-myth-wukong/reshade-depth-dead-end.md:195` |
| low (medium) | confirmed | TDU2-on-Linux note is labelled 'working' with no real run, and its version field says 'see note' | `knowledge/games/test-drive-unlimited-2/running-tdu2-on-modern-linux.md:12` |
| low | not re-checked | Bannerlord notes don't use the 'bannerlord' engine key, so an engine filter finds none of them | `knowledge/games/mount-and-blade-ii-bannerlord/bannercraft-minecraft-gameplay-bridge.md:8` |
| low | not re-checked | The focus-pause gotcha gives only a UE console variable and doesn't link the KB's own UE fix | `knowledge/techniques/driving-real-games-safely.md:48` |
| low | not re-checked | kb check --index never checks index.json, the file the README tells tool-less agents to fetch | `um/kb.py:472` |
| low | not re-checked | The user-path leak check misses common forms | `um/kb.py:270` |
| low | not re-checked | The two warnings come from links to skills/, which break outside a clone (including the sync cache) | `knowledge/techniques/running-windows-dx11-dx12-games-on-apple-silicon.md:437` |
| low | not re-checked | 16 notes don't name the model, though contributors must name agent and model | `knowledge/games/elden-ring/sunless-shadow-slave-in-elden-ring-params-native-dll-retextu.md:19` |
| low | not re-checked | The `um kb --help` example points at a note that doesn't exist | `um/kb.py:5` |
| info | observation | 'Mashups live under the host game' isn't followed, and one game name is non-standard | `knowledge/README.md:10` |

### example mods

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | GTA x Minecraft link has no token and no Origin check: any web page can drive both games | `examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/HostLink.java:36` |
| medium | confirmed | GTA install.sh replaces, then --remove deletes, a user's own ScriptHookV, ASI loader and ReShade headers | `examples/minecraft-gta5-passthrough/gta/install.sh:54` |
| medium | confirmed | Shadow of War: orc recovery from OfflineMode.log fails after any restart (log is truncated on every launch) | `examples/shadow-of-war-offline-mode/src/offline.c:445` |
| low (medium) | confirmed | Shadow of War build fails on common MinGW-w64 toolchains despite 'Any MinGW-w64 GCC' | `examples/shadow-of-war-offline-mode/src/offline.c:441` |
| low | not re-checked | Shadow of War wallet serves any slug from a hand-editable, live-reloaded text file | `examples/shadow-of-war-offline-mode/src/responder.c:218` |
| low | not re-checked | Shadow of War: closing a request handle during a callback on another thread double-frees it | `examples/shadow-of-war-offline-mode/src/offline.c:399` |
| low | not re-checked | GTA plugin's WebSocket client trusts the frame length from whatever listens on 25599 | `examples/minecraft-gta5-passthrough/gta/src/ws.cpp:204` |
| low | not re-checked | Terraria reference AgentBridge: tokenless loopback socket that tolerates junk lines (cross-protocol from a browser) | `examples/terraria-tmodloader/reference/AgentBridge.cs:64` |
| low | not re-checked | Agent docs don't list the Shadow of War example, though it says agents must install it first | `AGENTS.md:43` |

### fit with the Playground repo and its tools

| Severity | Status | Finding | Where |
|---|---|---|---|
| low (medium) | confirmed | universal-modder allows a private dump of a DRM-unpacked exe, which the owner forbade for AC7 | `skills/mod-any-game/references/safety.md:24` |
| low (medium) | confirmed | `um win launch` would start the owner's real, modded AC7 install instead of the copy | `um/win.py:199` |
| low (medium) | confirmed | Playground setup.md's pip fallback for `um` would install into the Store app's hidden AppData (fixed in this session: setup.md now keeps installs out of AppData) | `Playground: experiments/2026-10-18-universal-modder/setup.md:65` |
| low (medium) | confirmed | `um win setup` puts ffmpeg and its tools in %LOCALAPPDATA%, which the Store app hides, and has no ask step | `um/win.py:61` |
| low | not re-checked | The SessionStart hook's PATH line can't reach PowerShell, and it blocks every other hook's variables from reaching it | `hooks/add-to-path.sh:9` |
| low | not re-checked | um scan and the Unreal playbook don't spot AC7's layout or its SteamStub-scrambled exe | `um/scan.py:554` |
| low | not re-checked | The reverse-engineering skill doesn't know REA, so a PC session may install a second Ghidra bridge | `skills/reverse-engineering/SKILL.md:34` |
| low | not re-checked | The Playground's own input tool pulls AC7 to the front without checking whether the owner is typing | `Playground: experiments/2026-10-17-ace-combat-7-coop/tools/game-input.ps1:128` |
| low | not re-checked | Cloning universal-modder into a PC session folder would hit the same path-length failure as Claude-Playground | `Playground: LOG.md`, 2026-10-17 health-check entry |
| info | observation | um's publish lint finds the owner's Windows user folder in 6 files of the public Playground | `Playground: experiments/2026-10-17-ace-combat-7-coop/workbench.md:44` |
| info | observation | Turning the plugin on for the whole repo adds its hook, the fal connection and the modding loop to every Playground session | `Playground: .claude/settings.json:11` |

### gap: opencode-plugin-unchecked

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | um_run never asks OpenCode for permission, so risky um commands run even when the user's rules say ask | `plugins/opencode/index.ts:152` |
| medium | confirmed | Child stdin is left as an open pipe, so commands that prompt for input hang the session until interrupted | `plugins/opencode/index.ts:81` |
| low | not re-checked | In OpenCode 2 the tool is only reachable through Code Mode, and its description is cut to 120 characters, dropping the group list the test protects | `plugins/opencode/index.ts:137` |
| low | not re-checked | peerDependencies "@opencode/plugin": "*" makes plugin install pull 273 packages / 183 MB for a 7 KB plugin | `plugins/opencode/package.json:10` |
| low | not re-checked | The only plugin test is a regex. Nothing type-checks or loads index.ts, though both are cheap | `tests/test_opencode_plugin.py:27` |

### gap: render3d-never-run

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium | confirmed | --engine eevee --shadows writes an opaque grey square as the 'shadow-only' pass | `um/blender/render_sprites.py:60` |
| medium | confirmed | --ambient barely changes brightness: it scales Blender's default 0.05 grey world colour | `um/blender/render_sprites.py:98` |
| low | not re-checked | SKILL.md side-view example drops --forward-yaw, so a Trellis GLB renders front/back instead of right/left | `skills/asset-pipeline/SKILL.md:50` |
| low | not re-checked | --samples is ignored by EEVEE but reported as used | `um/render3d.py:87` |
| low | not re-checked | Mistyped motion names silently render still frames | `um/render3d.py:61` |
| low | not re-checked | World.use_nodes is deprecated and will break the script on Blender 6.0 | `um/blender/render_sprites.py:97` |
| low | not re-checked | AoE2 preview sheet clips hovering units (drone tops cut off) | `examples/aoe2-de-civ/make_sprites.py:145` |
| low | not re-checked | A temp JSON config is leaked on every render | `um/render3d.py:84` |
| low | not re-checked | A wrong BLENDER path gives a raw traceback, after the output folder was already created | `um/render3d.py:46` |
| info | observation | render3d has no automated test; CI only runs --help | `.github/workflows/test.yml:22` |

### gap: kb-pr-publish-path

| Severity | Status | Finding | Where |
|---|---|---|---|
| medium (high) | confirmed | kb pr branches from current HEAD, so unpushed local commits are pushed and land in the public PR | `um/kb.py:390` |
| medium (high) | confirmed | `git commit -m` with no pathspec commits whatever the user already had staged | `um/kb.py:392` |
| medium (high) | confirmed | Every file in media/ is published unchecked: secrets in text files, oversize files, dotfiles, other notes' media | `um/kb.py:384` |
| medium (high) | confirmed | Images are published with their EXIF intact (GPS position, camera, author name); nothing strips or checks it | `um/kb.py:391` |
| medium (high) | confirmed | kb pr throws away kb check's warnings, so pasted decompiler output and absolute user paths are published silently, and the PR body ticks "no decompiled code" anyway | `um/kb.py:375` |
| medium | confirmed | INDEX.md and index.json are rebuilt from every local note, so untracked drafts' full front matter is published | `um/kb.py:404` |
| medium | confirmed | The dry run the human approves hides the media list and PR body, and says nothing about commits or staged files | `um/kb.py:400` |
| medium | confirmed | kb pr leaves the clone on the kb/ branch, so the next kb pr stacks the previous PR (and its leaks) into the new one | `um/kb.py:390` |
| medium | confirmed | In a plugin install the "run inside a clone" guard never fires: kb new writes notes into the plugin cache and kb pr edits it, then fails with a git error | `um/kb.py:370` |
| low | not re-checked | No rollback on a mid-way failure: the clone is left on a new branch with staged or modified index files, and a retry dies on "branch already exists" | `um/kb.py:416` |
| low | not re-checked | Every kb PR commits the generated index, so two PRs that merge cleanly leave main's INDEX.md stale and CI red | `um/kb.py:391` |
| low | not re-checked | The user-path regex misses common forms: lowercase drives, JSON-escaped backslashes, macOS names with digits or dots, uppercase Linux names | `um/kb.py:270` |
