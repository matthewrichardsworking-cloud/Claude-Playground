# Log

Newest first. One short entry per session.

## 2026-10-19: Ace Combat 7 co-op, playtest bot phase 4: lock problem solved, Ace campaign under way

- Owner's OK (18 Oct): fly the AC7 story campaign on Ace with the bot, start to finish, no
  further input. All in the game copy; real install and saves untouched (checked).
- The lock problem from phase 3: read the game's own lock code from the running copy (two
  read-only commands added to read-game-code.py: `peek`, `vtslot`). A target only gets a lock
  "seeker" through the game's own SelectTarget (what Tab calls) or its per-frame loop; the bot
  wrote SelectedTarget directly, which skipped that. Now it calls NextTarget + SelectTarget(true).
  Mission 14 Hard: SAMs and reinforcements that never locked all locked and fell (27 kills);
  still lost on time against the waves. Also new: a read-only memory read in the C++ add-on
  (lock-on mark at +0x6C0, seeker state), `locks` / `actors` orders.
- New campaign driver (tools/campaign.py): Restart Story, difficulty, movie skips (F1),
  briefings, hangar plane/weapon by name (the save has the Typhoon with LAAM/8AGM/HCAA), the
  mission with retries, replay skip (Enter twice), results, NEXT MISSION; a report per mission
  and playtests/campaign-ace.md.
- Results so far (Ace): Missions 01 and 02 first try (no damage), 03 on attempt 2 (protect the
  retreating allies), 04 Rescue on the second sortie (a 128 km route around 79 radar spheres
  from a new planner, flown unseen; drones, an escort), 05 444 on the second sortie with the
  LAAM (mission targets first; no damage). Mission 06 Long Day in progress (phase 1 is timed
  on damage to the enemy base; now the 8AGM with a base-first plan).
- Owner's vision tests (vision.lua, ray fans through the C++ trace): test 1, a surprise
  fly-through of the Space Elevator's base, passed 13 m from the aim point with no contact.
  Test 2, the Mission 06 tunnel (35 m high, 1.3 km, bent): the first real try did not go in
  (room for the wings was judged by neighbouring grid rays, so a 36 m mouth looked shut from
  400 m); fixed with plane-sized parallel "tube" rays, and a new in-game simulator
  (tools/vision-sim.lua) now flies a simple plane through the real tunnel centred. Not flown
  for real yet.
- Two copy restarts were my doing (UE4SS's reload-all-mods crashed the game mid-mission; an
  eval of every property of the mission object hung the script): new code now goes in only at
  restarts, plus a `module vision|route` reload order. Saves checked each time, unchanged.
  Write-up: workbench section 15.

## 2026-10-18/19: Ace Combat 7 co-op, playtest bot phase 3: terrain and mission gimmicks

- Owner's request: the bot should see terrain and physical objects and adapt to missions'
  special rules; prove it on Mission 14 (Cape Rainy Assault: night canyon, 550 m ceiling,
  ~70 sweeping searchlights). All in the game copy; Double Trigger switched off there with
  the owner's OK; the real install untouched; saves checked after every run.
- Built: the engine's own line trace called from the C++ add-on (1.4 us per ray, ~600x the
  script route); terrain survey and height map; canyon route planners (2D and 3D); a canyon
  route-following controller; searchlight sweeps read from the game and recorded; live beam
  dodging (speed/height/sideways, four times a second); radio hook, mini-game skip, the
  game's real ceiling via a hook; runner plans per mission; menu selection checked by reading
  the game.
- Owner's tactical ideas built in: protect the landing party first (threat-to-allies
  weighting, direct target selection); one missile per target when one suffices, then
  switch at once (34 such shots in one run, 21 kills).
- Results: the canyon on Hard cleared at the first try in 4 of 6 cold starts (both misses
  the same searchlight, fixed). Base attack: the landing team now lands in about half the
  attempts; the mission is not completed because the reinforcement wave and some SAM sites
  never lock, although the game lists them as normal targets (stealth, identification,
  detection, line of sight, ammo, selection, mission lock marks all ruled out). Four game
  crashes traced to reading freed objects after checkpoint restarts; none after the fix.
- Next: a separate session flies the Ace campaign from the start (owner's OK), taking the
  lock problem first. Write-up: workbench section 14 of the experiment.

## 2026-10-19: F.E.A.R. / LithTech playbook + GOG setup

- Owner confirmed F.E.A.R. is **GOG** (DRM-free), and that the official **F.E.A.R. Public Tools v1.08 SDK**
  is in their PC `Claude Tools` folder (not logged here before; cloud can't see it — a PC session should
  confirm the path). Studied the public references read-only; wrote the first LithTech playbook anywhere:
  `experiments/2026-10-19-fear-lithtech/` (README, playbook.md, setup.md). Nothing installed.
- GOG matters: DRM-free, exe already Large Address Aware, so the Steam 4GB/LAA-strip prompt never appears
  and there's nothing to strip (verified in EchoPatch's LAAPatcher). GOG-only gotcha: `dxwrapper.ini`
  `LimitPerFrameFPS` caps at 60 — set to 0 or the fix pack's smoothness fixes stay off.
- Routes: (1) EchoPatch fix pack (GPL-3, 4.3.0, officially supports GOG Platinum — two files by FEAR.exe);
  (2) data/archive edits via the SDK's GDBEdit/ArchiveEdit (+ loose-file/`-archcfg` override, no open
  repacker); (3) the SDK game source (ObjectDLL GOAP AI, ClientShellDLL) — **blocked by a VC7.1/VS2003 ABI
  requirement** for the DLLs; (4) custom MinHook proxy-DLL hooks, but no GOG address map is published.
- Honest: F.E.A.R. retail had **no co-op** (CServerMissionMgr only; NOLF2's CoopMissionMgr is the template) —
  co-op is an unbuilt source-level job. `.world00p` level objects are readable via io_scene_jupex (MIT,
  Amphos); AI nav mesh is not. Archives read by Game Extractor; SDK EULA keeps SDK-derived code off the repo.
- Credits/licences in the folder. Hands-on work is for a PC session (game + SDK live there).

## 2026-10-19: game-file toolbox (UAssetGUI, Game Extractor, apitrace)

- Next shortlist cluster: three read-only file tools for the PC. Studied in the sandbox;
  `experiments/2026-10-19-game-file-tools/` has setup + usage. No plugins to pin (plain downloads).
- UAssetGUI (atenfyr, MIT, v1.1.0, needs .NET Desktop Runtime 8.0): reads/edits Unreal `.uasset`, converts
  to/from JSON, and has built-in **AC7 asset decryption**. Trap recorded: opening an AC7 asset in the GUI
  decrypts it **in-situ** (overwrites the file) — always work on copies, never the live install. CLI `tojson`
  does not auto-decrypt AC7.
- Game Extractor (wattostudios, GPL-2, v3.16.0008, bundles its own Java): opens game archives; reads
  F.E.A.R.'s `.Arch00` by name; AC7 `.pak` generically. Headless `-list -format JSON` / `-extract`; neither
  modifies the source. Avoid the GUI "replace" path. Pin >= .0008 (path-traversal fix in .0007).
- apitrace (MIT, v14.0): records a game's graphics calls (F.E.A.R. = 32-bit D3D9, win32 `d3d9.dll` wrapper)
  and `apitrace dump` reads the trace to text (runs even in the cloud). Record offline single-player only —
  a wrapper DLL beside a game reads like tampering to anti-cheat.
- None publishes a checksum; download from official pages only. All read/convert/trace only.

## 2026-10-19: assimilated WinDbg and Detect It Easy (the two "do next" tools)

- From the shortlist. Both run on the PC, not the cloud. Studied read-only in the sandbox;
  `experiments/2026-10-19-windbg-and-die/` has the setup and guardrails.
- `svnscha/mcp-windbg` (MIT, crash-dump + live WinDbg over MCP) pinned in `.claude-plugin/marketplace.json`
  at commit `48e4350d`, and enabled in `.claude/settings.json`. Its plugin lives in a subfolder of its repo,
  so the catalog entry uses the **git-subdir** source type (not `github` + `path`, which silently ignores the
  path and installs an empty plugin — learned the hard way; confirmed git-subdir installs correctly here).
  It runs `mcp-windbg@1.5.1` and needs WinDbg + uv on the PC.
- Guardrail: the three kernel-debugging tools (`open_kd_session`, `open_kd_dump`, `run_kd_command`) are denied
  repo-wide in settings (`mcp__mcp-windbg__...`) — kernel debugging can freeze the PC. User-mode live
  debugging stays on, with a documented rule never to dump a DRM-protected game's memory to disk.
- Detect It Easy (`horsicq/Detect-It-Easy`, MIT, release 3.21): no plugin, a portable `diec.exe` download.
  Setup note + a recon convention: `diec -j Game.exe` first on any game; a packer/DRM hit means hands-off the
  exe, a clean compiler/engine means proceed. Identify-only, never unpacks.
- Couldn't confirm the WinDbg server actually connects (needs Windows + WinDbg; cloud has neither). Plugin
  resolution and config placement are verified; the connection check happens on the PC.

## 2026-10-19: which GitHub repos to bring in next (AC7, F.E.A.R., future games)

- The owner asked what else to assimilate, for modding many games: AC7 now, F.E.A.R. (LithTech Jupiter EX)
  next. No earlier F.E.A.R. notes exist in the Playground. Research workflow (9 search angles, 68 repos
  vetted, ranked, then challenged by skeptics): `experiments/2026-10-19-repo-shortlist/`. Nothing installed.
- Do next: `svnscha/mcp-windbg` (crash files and live debugging for Claude) and `horsicq/Detect-It-Easy`
  (names a game's copy protection before anyone touches it). For AC7: `CreeperUX/AC7-Integrated-Mod` (MIT)
  maps where AC7 reads analog flight input on build 9855922, the reason the bot's Input* writes did nothing.
- F.E.A.R. trap: on the Steam copy, EchoPatch's first-run "large memory" offer strips SteamStub (DRM
  removal); FEAR-MORE needs that stripped exe. The GOG copy is DRM-free. Asked the owner which they own.
- Gaps: no LithTech toolkit or playbook anywhere; no F.E.A.R. co-op source; no maintained virtual gamepad.
- The container restarted mid-workflow; the disk survived, and `resumeFromRunId` reused the 6 finished agents.

## 2026-10-18: universal-modder, reviewed and hooked up

- The owner asked for a review of [universal-modder](https://github.com/rehan-remade/universal-modder) (MIT:
  game-modding skills, the `um` CLI, 265 agent-written field notes) and for it to be wired in. Everything is
  in `experiments/2026-10-18-universal-modder/`.
- Wiring: a repo-root plugin catalog (`.claude-plugin/marketplace.json`) pins it to the reviewed commit
  `6a8865ae`; `.claude/settings.json` marks it wanted, so PC sessions offer it (each PC installs it once).
  Cloud sessions ignore repo-enabled plugins, so they need two setup-script lines (`setup.md`). Tested here:
  a new Claude Code process got all 12 skills, 3 agents and `um`; their suite passes (163 passed, 1 skipped).
- Review (36-agent workflow): 153 findings, 73 confirmed by a second agent. Best part: the knowledge base and
  its note format. Worst: `um publish check` and `um kb pr` let secrets and private files through while
  reporting success; mouse clicks from `um win drive` can land in other windows (the one high finding).
  Its Unreal guide would have misled the AC7 work in five places.
- On the PC the owner's AC7 rules beat the toolkit's (no private code dumps, start the copy only with
  `start-copy.ps1`, `um win drive --no-retry`): `setup.md`, "Where the Playground's rules win". Our AC7
  lessons are drafted as one of their field notes (passes `um kb check`, not submitted).
- Snags: `claude plugin marketplace remove` run inside the repo also emptied the repo's settings file (CI's
  `check.sh` now catches that); `claude -p` test runs share the parent session's environment file (start them
  with `env -u CLAUDE_CODE_SESSION_ID`); a 4-core container runs two workflow agents at a time.

## 2026-10-18: Ace Combat 7 co-op, Double Trigger in the owner's real install (one-time exception)

- The owner lifted the "never touch the real install" rule for this one install, asking for
  a backup first and proof that Vanilla mode can remove it. The rule stands otherwise.
- Backed up the real `ModLoader` folder in full (byte-checked), fingerprinted the 91 files
  in `~mods`, backed up the saves. The real loader exe was identical to the build the
  loader-DLL rule was added to; no library mod has a DLL; the loader reported everything
  in sync before the change.
- Replaced the real loader exe with the updated build (the old one would remove the DLL on
  its next apply), installed Double Trigger as mod 31: +1, 91 kept. Vanilla mode on removed
  all 92 files; off restored them, every `~mods` file identical by SHA-256. Not launched
  in the real install. Write-up: workbench section 13 of the experiment.

## 2026-10-18: Ace Combat 7 co-op, Double Trigger installed with AC7 Mod Loader and launched

- The owner asked to prepare, install (with AC7 Mod Loader) and launch Double Trigger. Done
  in the game copy, since the real install, its mods and its Mod Loader stay untouched.
  Write-up: workbench section 12 of the experiment.
- v0.1.0 downloaded from the GitHub release: checksums match, Windows Defender clean,
  unsigned as the author says. Kept outside the repo (no binaries pushed).
- The Mod Loader could only place `.pak` files and `Game\Content` files. A small rule
  (`LooseTargetFor`) now sends known loader DLLs (`dinput8.dll` etc.) at a mod's top level
  to the game folder; its existing backup and removal machinery does the rest. Unit tests
  pass. Installed with `--game C:\AC7-Coop-Game --install`. Vanilla mode removes and
  restores the DLL. `--game` keeps the loader's shared `gamepath.txt` untouched.
- Launched with `tools\start-copy.ps1` (the loader's own Launch goes through Steam, which
  starts the real install). The mod's log shows every start-up check passing; Multiplayer
  greyed out; F5 panel works. No lobby hosted. Real save unchanged. Left running for the
  owner.
- Known overlap: UE4SS reads keys straight from Windows, so F5 and F9 also reach
  `CoopFlightLabMod`; switch it off or move Double Trigger's `toggle_key` before co-op.

## 2026-10-18: Ace Combat 7 co-op, playtest bot phase 2: tracking, prediction, threats

- Owner's request: special weapons, incoming-missile paths, enemy paths and AI behaviour
  from the game's data plus live readings, acted on in real time; test on Mission 02.
  New `awareness.lua` in the pilot: tracks every enemy and missile; reads weapon and
  missile limits from class defaults (no game files unpacked), each enemy's limits, AI
  state (`EAIState`), tracking target and scripted route (spline); line-trace ground sensor
  (reported altitude is above the sea, not the ground).
- Behaviour: flares and break turns timed from each missile's time to impact; turn into an
  enemy on our tail; LAAM for targets 2-10 km away; attack runs on ground targets; skip
  objects the game won't select. Predictor scores several methods live and uses the best.
- Mission 02 bugs found and fixed: the air-only LAAM left armed hid every ground target
  from selection; circling buildings never got them onto the nose (attack runs fixed it);
  sea-level floor over hills meant terrain scrapes and a crash.
- Results: Mission 01 Ace completed first try, no damage. Mission 02 Hard validation run,
  untouched: completed first try in 14.9 min, 43 kills, no damage, 6 of 6 missiles at it
  lost lock. Predictions 2 s ahead: turning planes 52 m off with half the turn rate (straight
  line 81 m, full turn 92 m). Open: route-following group mixes slow and fast objects.

## 2026-10-18: Ace Combat 7 co-op, the playtest bot built: it completes Mission 01 alone

- Built the bot designed earlier the same day (owner: achievements don't matter). Pieces:
  `CoopPilotMod` (UE4SS Lua pilot: flies, fights, logs events/status/flight data, takes
  orders over the CoopNetMod socket), `CoopPadMod` (C++ add-on: keyboard presses from inside
  the game, only while its window is in front, watchdog lets go), `tools/pilot.py`,
  `tools/playtest.py` (runner: order file, menus, take-off, attack, retries, report, save
  check). Workbench section 10 has the details.
- What the tests showed: writing the plane's `Input*` values does nothing (rewritten every
  frame); UE4SS `LoopAsync` plus game hooks in one script race and crashed the game (fixed by
  running everything on the game thread); the game pauses whenever it loses the front; a
  stand-in `xinput1_3.dll` virtual gamepad never reaches the game because Steam's overlay
  answers gamepad reads itself; keyboard keys from inside the process work.
- The autopilot (bank toward the goal and pull, pulse keys for gentle input, ground and
  area-edge safety) was tuned in Free Flight. Combat: Tab target cycling, enemies told apart
  with the game's own `GetFaction`/`IsTGT`, lead aim, missiles on lock, gun close in, flares
  and a break on a "very near" warning.
- Results: Mission 01 Casual completed by hand-given orders (19 kills, no damage), then by
  the runner alone from a cold start, menus included, at the first attempt: 20 kills, 77
  missiles, no damage, score 12,400 (the owner's own best). Menu pages are recognised by
  their widgets (the Campaign submenu opens on the story save's "Continue", a trap the
  runner now detects and backs out of). Owner's real saves unchanged after every run.
- Not yet: plane choice, special weapons, ground attack, skipping the post-mission replay.
  Next, the owner's request: special weapons, incoming-missile path prediction, enemy path
  and AI-state prediction from the game's own data plus live readings.

## 2026-10-18: Ace Combat 7 co-op, reading layer10_love's released mod (Double Trigger)

- The co-op mod the owner had been told about came out: [Double Trigger v0.1.0](https://github.com/layer10-love/double-trigger)
  (MIT, full C++ source, one `dinput8.dll`). Cloned read-only into a scratch folder and
  read in full, nothing downloaded into the game copy, nothing run. The review is
  `experiments/2026-10-17-ace-combat-7-coop/double-trigger-review.md`.
- Verdict: two-player co-op for Free Missions on the game's own online layer (the route
  our plan set aside as hardest), host-authoritative with a private Steam P2P channel
  for the world state, 24k lines written in seven days, defensively built (byte checks on
  222 game functions before it does anything, per-feature fuses, friends-only lobbies
  only, the game's own online modes blocked while installed). Its own known-issues list
  is long and candid. It confirms our SNL map (`code/snl-map.md`) point for point.
- Checked read-only against the owner's game copy: the exe build stamp, the Steam
  library file's checksum and the absence of pirated-copy markers all pass the mod's own
  checks, and UE4SS in the copy uses a different loader file name, so no file clash.
  Two copies on one PC still can't work (the mod needs a real Steam connection).
- Reproduced the release's build ID (`6240b21f`) from the published source: the version
  stamp matches the code that is public.
- Next, needing the owner's OK: download the DLL (checksum published), dry-run it in the
  copy alone, then a two-player test with a Steam friend on a second PC. If it holds up,
  the project turns into testing and helping that mod.

## 2026-10-18: Ace Combat 7 co-op, design for a playtest bot

- The owner asked for a bot that plays missions in the game copy on a session's
  instructions (mission, plane, loadout, objective order), retries until it completes,
  and reports back. Design only, nothing built:
  `experiments/2026-10-17-ace-combat-7-coop/playtest-bot.md`.
- Split: a pilot inside the game (UE4SS Lua), a Python test runner outside (order, saves,
  menus, retries, report), a Claude session as test director, since Claude can't fly
  live. Modes: fair, assisted (invincible, steering by nudging) and skip-ahead.
- From the in-mission object dump: `PlayerPlane` has `InputPitch`/`InputRoll`/
  `InputThrottle` values (whether writing them steers the plane is the first test),
  `PlayerWeaponActivator` has missile/gun/flare press functions,
  `TargetSelectionComponent:SelectTarget`, `Mission` reports completed/failed/score and
  can skip mini-games, `NimbusGameInstance` has `SetMissionID` and `SetPlaneAndSWP`.
- Open question for the owner before any mission gets completed in the copy: Steam
  achievements would unlock on their real account.

## 2026-10-18: Ace Combat 7 co-op, a C++ add-on gives the scripts a network socket

- Built a C++ add-on for UE4SS on the owner's PC (experiment folder `cpp\`): CoopNetMod
  opens a UDP socket on the local address and hands every Lua script four functions to
  read the packets. UE4SS's own hello-world example was built first as proof. Both load
  in the game copy; a Python sender on the same PC delivers 40 packets a second and a
  script in the game reads each within 1 to 24 ms.
- The copy's UE4SS turned out to be the public UE4SS repository's commit 48e7edfe (1 Feb
  2026) built by Playmore; the add-ons are compiled against that commit's headers and
  linked against the copy's own UE4SS.dll (its export list turned into an import
  library), because the documented build needs a private Unreal-headers repository (an
  Epic-linked GitHub account) and Rust.
- The compiler (MSVC 14.44) and Windows SDK were fetched into a plain folder straight
  from Microsoft's own package list with every checksum verified and signatures checked,
  because the normal installer needs an administrator prompt the owner was not there to
  click. What, where, sizes, checksums and how to remove: `downloads\installed-tools.md`.
- Stretch goal reached: the flight lab's puppet plane now flies from the live packets
  (key F11), trimmed by 1 to 2 units (10 to 20 cm) per frame at 90 frames a second,
  100 ms behind the feed. Three detours recorded in workbench section 9: a recording
  with whole-second time stamps, the game clock costing 20 ms per read from a script and
  freezing after a reload, and a re-used plane with a dead engine.

## 2026-10-18: Ace Combat 7 co-op, a tool that reads the running copy's code

- New `tools/read-game-code.py` (Python, read-only process access, capstone 5.0.9 for
  the disassembly): opens the running game copy, finds the exe's live base, names
  functions from the UE4SS object dump (rebased automatically), from the game's own
  class data (2,335 functions by class and slot) and from strings, names Steam
  interface calls, finds every code reference to a string or address, and saves
  single functions only. One line: `python tools
ead-game-code.py read exe+0x1da3319`.
- Proved on the 17 Oct crash: the crash site is `SNL::PlatformUDPSocket` slot 5, the
  "is a Steam P2P packet waiting?" call, reading through a null `ISteamNetworking`
  pointer because `SteamAPI_Init` (called from Unreal's Steam start-up) fails in a
  second process.
- First map of the online layer in `code/snl-map.md`: `SNL_P2P_HOST` is the lobby
  member-data key that marks the host, `SNL_STEAMLOBBY_OWNER_NAME` the lobby-data key
  with the host's name; session create/join/leave/search/invite functions named; the
  save path builds `SaveGames/<SteamID>` only after a valid `GetSteamID`; SNL's
  messages are Steam P2P packets on a channel; 33 session message types listed. Two
  leads: `[SNLMultiplayer] VersionIntNumber` and a developer switch "Apply multiplayer
  parameters to campaign". Workbench section 8. The copy's bytes stay local.

## 2026-10-18: Ace Combat 7 co-op, the owner widens the rules

- The owner decided the rules had kept the project from the route the other modder
  took, and added an addendum (project README, mirrored in workbench, plan and
  research): sessions may read the running game copy's code in memory for analysis
  and may build a C++ add-on for UE4SS, installing the free developer tools that
  needs from official pages with sizes and checksums recorded. A complete unscrambled
  exe on disk, sharing it, changing the game's own checks, and anything online outside
  private rooms stay off limits.
- Two sessions started on it: a Python tool that reads named functions out of the
  running copy and maps the online layer's entry points, and a C++ UE4SS add-on with a
  UDP socket as the basis of the live position feed.

## 2026-10-18: Ace Combat 7 co-op, someone else is about to release one

- The owner found a Reddit post by layer10_love (r/acecombat, 15 Oct) showing a working
  co-op mod, and chatted with the author: it reuses the game's own SNL peer-to-peer
  layer over Steam with a custom channel for the rest, "about 95% working", release
  promised for 18 Oct. That is the route our plan set aside as hardest (it needs the
  game's compiled code, which we don't read). Reddit blocks automated reads; the owner
  saved the page as HTML and it was read from that.
- Decision: wait for the release, read it, try it in the copy; if stable, switch to
  testing and helping it rather than finishing our own less thorough version. Our
  puppet work stays as the fallback. Written into the experiment's `research.md`
  (section 5), `plan.md` (update at the top) and the project README.

## 2026-10-18: Ace Combat 7 co-op, a puppet plane flies a recorded flight

- The owner asked for work to carry on while they were away and gave a standing
  go-ahead for anything in the game windows. A session drove one copy from the title
  screen into a mission (menus, cutscene and briefing skipped with key presses through
  `game-input.ps1`, which now sends key chords such as Ctrl+P for UE4SS hot reload),
  took an in-mission object dump, and built `CoopFlightLabMod`: F7 records the player's
  plane about 40 times a second to a file, F4 takes the nearest AI plane, switches its
  AI off and puts it where the recording says every frame.
- Result: the puppet held its place next to the player to the unit for a 32-second
  replay. Between frames its own flight engine carries it in the right direction, so
  each update corrects only 3 to 4 game units (about 30 to 40 cm). That is the shape a
  network feed will need. Positions and rotations can be passed as plain Lua tables.
  The game's `SetFELocationAndRotation` does nothing visible; `K2_TeleportTo` and
  `SetBehaviorActive(false)` are the levers.
- Round 2 (same night, 00:51 to 01:20): a plane the mission has not activated can be
  switched on with the game's `SetActive` and used as the puppet; matching the puppet's
  speed to the recording cut the per-frame correction from about 50 units to 0.2; a
  recording with real rolls and a hard pull replayed with about 6 units of correction
  per frame. Flying from a session works with held keys (A/D roll, S pull). Still open:
  missiles against a puppet, a video of it in motion, and the network feed.
  Details in the experiment's `workbench.md`, section 7; script in `mods/`; four
  screenshots in `pictures/`.

## 2026-10-17: Ace Combat 7 co-op, a script can't get the second copy past the title

- Question from the previous entry: can a UE4SS script in the second copy skip the save
  step and get past the title screen? **No.** Read both crash dumps with a small Python
  tool (`experiments/2026-10-17-ace-combat-7-coop/tools/read-crash-dump.py`): the game
  dies on a helper thread reading address zero, right after asking Steam's library for
  its table of Steam connections, and in the second copy that table is completely empty.
  So the second copy never gets a working link to Steam and crashes on its first use of
  Steam networking; the save step just comes before it. A script works above that level
  and can't fill the table or stop the thread. Steam's own logs treat the second process
  as an extra window of the game already running.
- The game's leftover developer commands (the `SNL_` ones, the save switches) are empty
  in this build: 215 of the 494 cheat-manager commands point at one and the same bit of
  code, the rest grouped by the kind of value they take. Calling them does nothing, so
  the plan's "fake session" solo-test idea is off too.
- Built and tested the script anyway: `CoopSecondCopyMod` tells the copies apart by
  their user folder, stays quiet in the first copy, and in the second logs every
  save/load call and calls the three save switches. With the owner's go-ahead (now a
  standing one for anything in the game windows), Enter was pressed in the second copy
  with the script armed: same crash, third identical dump, none of the twelve watched
  save/load functions was ever called, switches changed nothing. The real save folder
  was unchanged after every run (five backups). Details in the experiment's
  `workbench.md`, section 6; the dump-reading tool and the script are in its `tools/`
  and `mods/` folders.

## 2026-10-17: Ace Combat 7 co-op, the copy gets its own save folder

- The game asks Windows for the user's "Local AppData" folder and keeps saves and
  settings there, so the copy shared the real folder. `tools\start-copy.ps1` now tells
  the game process it starts (and nothing else) that the user folder is
  `C:\AC7-Coop-Game\UserProfile`; the game then uses
  `UserProfile\AppData\Local\BANDAI NAMCO Entertainment\ACE COMBAT 7` for everything.
  Checked first with a small PowerShell test, then two title-screen runs: ten settings
  files written there, nothing in the real folder, SHA-256 of the real folder equal to
  the backup both times. First launch seeds the folder with the owner's settings and
  save (read only). Then proved with the owner flying a mission and quitting through
  the menu: the save landed in the copy's folder, the real folder's 13 files were
  byte-for-byte unchanged, Steam Cloud uploaded nothing.
- The game ignores Unreal's own `-UserDir=` switch (tested), like `-windowed` before, so
  command-line options are a dead end for this game.
- Steam itself syncs the real save on every exit of anything labelled app 502500; at
  22:34 it uploaded the restored original save, so Steam Cloud is back to the 10 Oct
  file.
- UE4SS crashed (fault in `UE4SS.dll`) while the game was closing after that run, two
  seconds after the save was written. Harmless for saves; expect a "stopped working" box
  on quitting now and then. Dump kept in the project's `dumps\` folder.
- New `tools\game-input.ps1`: finds the copy's game window, presses keys in it and takes
  pictures of it, so a session can drive the menus itself. Tested without the owner:
  Enter at the title, down to Quit Game, Yes; the copy saved into its own folder and
  closed; real folder unchanged. **Standing permission from the owner:** sessions may
  start the copy, press Enter, use the menus and quit from the main menu without
  asking. Copies of all four scripts are in the experiment's `tools/` folder.
- Two copies retried with `-Second` (own folder, smaller window, seeded save): the
  second copy can't read the seeded save ("error loading data" loop), and with the seed
  removed it creates a new save in the no-identity place and crashes one second later at
  the same fault address as on the first try. So the shared folder wasn't the cause: a
  second instance gets no Steam identity. Next idea: a UE4SS script that skips the save
  step in the second copy. Details in
  `experiments/2026-10-17-ace-combat-7-coop/workbench.md`, test 2 and section 4.

## 2026-10-17: Ace Combat 7 co-op, workbench (step 0)

- Plain game copy at `C:\AC7-Coop-Game` (65.7 GB, no mods), exe SHA-256 matches
  identity.md. PM-UE4SS-ZR1903 downloaded from GitHub (SHA-256 matches GitHub's
  digest) and installed in the copy only. Earlier Mod Loader and Kismet tools copied
  out of the app's private storage into `AC7-Coop\inherited` (built .paks left out).
- Started plainly, the copy hands off to Steam (`steam://run/502500`), which starts the
  real install. Setting `SteamAppId=502500` for the launch (what Steam does itself) makes
  the copy run from its own folder. `-windowed` is ignored.
- UE4SS loads, finds UE 4.18 once SteamStub has unpacked, opens its console and writes
  the object dump (game module "Nimbus"; `SNL_*` dev commands are reflected functions).
- Two copies at once: both reach the title screen, but the second crashes creating save
  data (likely no Steam user for it, shared save folder). The copy shares the real save
  folder: quitting through the menu rewrote the real save (restored from backup). Stay on
  the title screen; give the copy its own save folder before step 1. Details in
  `experiments/2026-10-17-ace-combat-7-coop/workbench.md`.

## 2026-10-17: Ace Combat 7 co-op, bearings and plan

- On the PC, following Co-op Anything's `coop-triage`. Both MCP tools connected.
  Build: Steam 9855922, `Ace7Game.exe` SHA-256 `c7da97f5...e558f4f`, UE 4.18.2
  (from the exe's version info). Read-only throughout: nothing changed in the
  install, mods, mod loader or saves, nothing downloaded.
- Still no co-op or AI-in-multiplayer mod anywhere, and no Ace Combat issue or PR in
  Co-op Anything. Online play is player-hosted, peer to peer over Steam (lobbies,
  SteamNetDriver with relay, Bandai's "SNL" layer with host migration). No
  third-party anti-cheat and no VAC, but the game runs its own online cheat checks.
- The exe's code section is scrambled by SteamStub on disk, so Ghidra can't read it;
  unscrambling is off limits. UE4SS (AC7 build: GitHub `Playmore-ModdingConcepts/PM-UE4SS`)
  is the way in.
- Head start found: a 6 Oct session built the owner's AC7 Mod Loader, plus Python
  tools that decrypt AC7's paks and rewrite mission Kismet bytecode ("Horde Mode",
  "Double Enemy Aircraft"). Copies of the tools sit in `ModLoader\library\<mod>\rebuild\`;
  the full source is only in the Claude app's private scratch storage, so copy it out.
- Plan: two single-player games kept in step (puppet planes, host-run enemies) over
  bending the game's online mode. Ladder, tests, unknowns and the proposed game copy
  (`C:\AC7-Coop-Game`, 65.7 GB) in `experiments/2026-10-17-ace-combat-7-coop/plan.md`.
  Ace Combat 8 is installed too and has official online co-op against AI.

## 2026-10-17: health check of the PC setup

- Re-checked everything from the entries below; it all still works. `claude mcp
  list` (2.1.299) shows `rea` and `coop-anything` connected, `rea doctor
  --provider ghidra` is healthy, and `rea analyze whoami.exe` through Ghidra
  took 57 seconds (341 functions). Python, Java 21 and Node are the expected
  versions. Commands and results in `experiments/2026-10-17-pc-health-check/`.
- Claude Code's PowerShell tool starts with `-NoProfile`, so `rea doctor` run
  there says `GHIDRA_INSTALL_DIR` isn't set. Wrap it in `powershell.exe
  -Command "..."` to load the profile. The MCP server has its own env and is fine.
- Correction: `core.longpaths` alone isn't enough to clone into a session
  folder. Its real path is 203 characters and git's https helper allows about
  220 for the `.git` path, so `Claude-Playground` failed with "'$GIT_DIR' too
  big" and `pg` worked. Use `git clone -c core.longpaths=true <url> pg` so the
  setting stays in the clone; with `git -c ... clone` later commits fail with
  "Filename too long". `%APPDATA%\Claude` itself is in the app's private storage.
- With the owner's OK, rebuilt JapaneseTutor's venv on Python 3.13: old
  `.venv` to the Recycle Bin, 17 wheels downloaded and checked against PyPI's
  SHA-256, then its own `setup_env.py` installed from only those files. All 22
  tests in `tests\test_core.py` pass.
- Still open: stable-diffusion-webui's venv points at the removed Python 3.10,
  and the Recycle Bin holds 13.4 GB of leftovers (C: limit about 46 GB).
- Wrote `Desktop\Claude Tools\START-HERE.md`, a plain-language guide to each
  tool with checks and fixes. README.txt stays the detailed list.

## 2026-10-17: REA and Ghidra running on the PC, Co-op Anything added

- First session on the owner's PC itself (Claude Code in the Claude desktop
  app). Everything went into `%USERPROFILE%\Desktop\Claude Tools`: Ghidra
  12.1.4, Temurin JDK 21, Node.js 24.22.0, and REA 6.5.0 from npm. Java and Node
  are portable zips, each checked against its published SHA-256, so there are no
  installers and nothing on the system PATH.
- REA is registered with Claude Code (`~/.claude.json`, backup beside it) and its
  skill is installed. `rea doctor` passes every Ghidra check, and a real
  `rea analyze` of `whoami.exe` through Ghidra took 55 seconds. A PowerShell
  profile puts `rea` on PATH in new terminal windows.
- Snags: the desktop app is the Microsoft Store build, which redirects AppData,
  so session folders have very long real paths and git needs
  `-c core.longpaths=true` to clone there. REA can't register the desktop chat
  app from inside it. A git clone of REA lacks the Windows native parts; the npm
  package has them.
- Cloned Co-op Anything next to them; notes in
  `experiments/2026-10-17-coop-anything/`. After the owner restarted the app,
  its MCP server was connected too: a Python 3.13 venv in `Claude Tools` with
  PyYAML, registered at user level. `claude mcp list` shows it and REA as
  connected, and REA's tools now load in new sessions. The `claude` command
  isn't on PATH; the app keeps it under `%APPDATA%\Claude\claude-code\<version>\`.
- Python: the owner's PC Guardian session had swapped the end-of-life Python 3.10
  for 3.13.15 (winget), leaving 3.10's packages behind. This session installed
  Python 3.15.0 for all users from python.org (checksum and signature checked);
  it's now the default `python`, with 3.13 kept because PyTorch has no 3.15 builds
  yet. The 3.10 leftovers, pip's cache and the dead `Claude Tools\python-env`
  went to the Recycle Bin (13.7 GB). Two venvs still point at the missing 3.10:
  JapaneseTutor's (can be rebuilt) and stable-diffusion-webui's (needs 3.10).
- Watch out: inside the Store build of the Claude app, new files under AppData
  (except Temp) get redirected into the app's private storage, where other
  programs can't see them. Install for all users, and keep virtual environments
  in normal folders. The Recycle Bin was over its size limit; check it before
  recycling anything big, or Windows quietly purges the oldest items.

## 2026-10-17: Ghidra notes and home setup guide

- Same session as the REA entry below. The owner asked to add Ghidra too, and
  plans to put both tools in a "Claude Tools" folder on their desktop.
  Notes plus step-by-step PC setup are in `experiments/2026-10-17-ghidra/`.
- Newest Ghidra is 12.1.4, which is exactly what REA was tested with. Ghidra's
  repo is huge; a sparse clone (`--filter=blob:none --sparse`) of just the
  docs took seconds.
- Told the owner REA isn't a folder (it installs through Node.js), and that
  Claude Code has to run on the PC to use either tool. If a session starts on
  the PC, `home-setup.md` step 5 is the next thing to do.

## 2026-10-17: read through REA

- The owner asked for a quick study of [REA](https://github.com/morluto/rea), a
  reverse-engineering toolkit for AI agents (MIT). Notes are in
  `experiments/2026-10-17-rea-reverse-engineering-tool/`.
- Cloning a public repo for reading still works with no setup.
- The session's safety check blocked running it with `npx` (code downloaded
  from the internet). Reading was fine. To try it, get the owner's go-ahead
  first; the JavaScript analyzer is the easy test since it needs no decompiler.

## 2026-10-17: BIOS update, CPU fan error

- The owner updated their PC's BIOS and got "CPU Fan Error" at startup. Walked
  them through the fix using photos of the screen. Notes on the PC and the fix
  are in `experiments/2026-10-17-bios-cpu-fan-error/`.
- Cause: the cooler is on the AIO_PUMP header and CPU_FAN is empty, and the
  update reset the setting that had been hiding the warning. The fix was to set
  Q-Fan Control to Auto, then the CPU fan low limit to Ignore.
- Sending photos of the screen worked well. The owner followed the BIOS steps
  without trouble once each one named the exact on-screen label.
- A research workflow pulled ASUS's own manuals as PDFs with curl. ASUS's site
  works; the ROG forum, Corsair, and Reddit block automated reads.

## 2026-10-17: Ace Combat 7 co-op research

- The owner found [Co-op Anything](https://github.com/cranebeaker/coop-anything), a
  playbook for adding co-op to single-player games (MIT license). Public repos
  clone fine for reading with no setup.
- Researched Ace Combat 7 co-op: nobody has done it. Notes and sources are in
  `experiments/2026-10-17-ace-combat-7-coop/`. Nexus Mods blocks automated page
  reads, so mod details there came from search snippets only.
- Hands-on game modding can't happen in the cloud workspace (no games, no
  Windows). It would need Claude Code on the owner's PC.
- Tidied `CLAUDE.md`: moved a stray line and added rules for borrowing from
  other projects.

## 2026-10-16: repo setup

- Connected GitHub. Reads worked at first, but pushes and issue creation got 403s
  until the Claude GitHub App was installed on the repo. Both work now.
- Tested an issue end to end (#1: create, comment, close).
- Added the layout, `CLAUDE.md`, this log, and a CI workflow that runs each
  experiment's `check.sh`. `experiments/_template/` doubles as the CI smoke test.
- Created `main`. The owner gave standing permission to merge freely (recorded in
  `CLAUDE.md`). If `main` isn't the default branch yet, the owner has to switch it
  under Settings → General → Default branch; the tools here can't do that.
- First CI run passed.
- The owner asked for plain-language explanations; they're new to programming
  and IT. Added a "Talking to the owner" section to `CLAUDE.md`.
