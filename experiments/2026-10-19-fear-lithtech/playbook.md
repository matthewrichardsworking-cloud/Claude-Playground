# LithTech Jupiter EX playbook (F.E.A.R.)

An engine playbook in the shape of universal-modder's, for a game family neither it nor the Playground
covered. Written for a session doing the work, from a read-only study (19 Oct 2026). Facts flagged
*unverified* were single-source or couldn't be checked from Linux.

## Identify

A LithTech **Jupiter EX** game (F.E.A.R. 2005, Extraction Point, Perseus Mandate; Condemned; the engine is a
cousin of NOLF2's LithTech) is recognisable from the install folder alone:

- `FEAR.exe` (expansions: `FEARXP.exe`, `FEARXP2.exe`), several large **`.Arch00`** files (packed content),
  a plain-text **`Default.archcfg`** (the list of those archives and their load order), and compiled levels
  ending **`.world00p`**. The GOG build also ships a **`dxwrapper.ini`**.
- Internally it's **client/server even in single-player**: launching a level starts a local server and a
  local client in one process that talk over serialized messages. So the real rules — AI, damage, difficulty
  — live **server-side** (the server game DLL).

**The owner's build: GOG "F.E.A.R. Platinum", v1.08.** DRM-free and already Large Address Aware (verified in
EchoPatch's `include/LAAPatcher.hpp`, which writes nothing when the exe is already LAA and has no SecuROM
`.bind` section — the GOG case). Tools tell builds apart by the exe's PE **TimeDateStamp** and/or SHA-256;
GOG and Steam share the 1.08 timestamps but differ by hash, so a hash-keyed Steam-only tool may not recognise
GOG. GOG launches `FEAR.exe` directly (Steam uses `steam.exe -applaunch 21090`).

## Routes (ranked, easiest first)

All routes are read-the-files or hook-the-process; nothing strips protection (GOG has none).

1. **Runtime patch — start here.** A single fix-pack DLL that modernises the game in memory, no game file
   changed. Reference: **EchoPatch** (GPL-3.0, release 4.3.0, 3 Oct 2026), which officially supports the GOG
   Platinum build and both expansions. Drop two files next to `FEAR.exe`; see setup.md. This is the honest
   ceiling for "run and look better."
2. **Data / archive editing — no programming, needs the SDK's data tool.** Most balance/content mods edit
   data, not code. Weapon stats are records under `Arsenal/Weapons` in the game database; AI/difficulty
   tuning lives there too; models/textures/sounds are swappable. The database ships compiled as
   `FEAR.Gamdb00p`; edit the readable source `FEAR.Gamdb00s` and recompile with the SDK's **GDBEdit**, then
   either pack into a new `.Arch00` with the SDK's **ArchiveEdit** and list it last in `Default.archcfg`, or
   use the loose-file override (next section). Moderate effort.
3. **Official SDK / source — the big one.** The **F.E.A.R. Public Tools v1.08** SDK (~640 MB; default install
   `C:\Program Files (x86)\Sierra\FEAR Public Tools` — **the owner has it in their `Claude Tools` folder**)
   carries the game's own source: the server DLL (`ObjectDLL` — objects, rules, the GOAP AI, the player), the
   client DLL (`ClientShellDLL` — HUD/menus/input), the `ClientFX` effects system, and the world editor. With
   it you can rebuild the game DLLs or build new levels. High effort, with a real toolchain blocker (Pitfall
   2). EULA: non-commercial F.E.A.R. mods; **SDK-derived source and game assets stay off the public repo.**
   Use the official SDK, not a fan "Public Tools v2" repack that strips the SDK's own protection.
4. **Write your own hook — for a programmer, later.** A proxy/wrapper DLL plus signature-checked MinHook
   hooking. Open references: EchoPatch (GPL-3) and **F.E.A.R. VR** (DR-89, MIT). Catch: addresses are
   per-build and **no GOG address map is published**, so they'd have to be found against the owner's exe.

**No open tooling for:** an `.Arch00` writer (use the loose-file / `-archcfg` override instead of repacking);
F.E.A.R. co-op (none exists — see Pitfall below); a GOG-specific hook-address table.

## Read the game

You can inspect almost everything without the game running and without changing an original file.

- **Archives (`.Arch00`).** The bulk content (textures, models, sounds, materials, the compiled `.world00p`
  levels, FX) sits in `.Arch00` containers, internally tagged **"LTAR"** (signature `4C 54 41 52 03 00 00 00`
  = "LTAR" + version 3 — *unverified, single-source*). `Default.archcfg` (plain text, game root) sets which
  load and in what priority. Extract with **Game Extractor** (already set up in the Playground's
  `2026-10-19-game-file-tools` — its plugin names F.E.A.R. directly), Dragon UnPACKer, or QuickBMS (a current
  public LithTech `.bms` script is *unverified*). No reliable open repacker, so to **add** content you add a
  higher-priority layer, not rebuild a stock archive: launch with `-archcfg <path>` pointing at a copy of
  `Default.archcfg` with your folder appended last, plus `-userdirectory <path>` to redirect saves — the GOG
  install stays untouched. (Loose-file override is community practice, *not proven from source*.)
- **Levels (`.world00p`).** A compiled level; its version number must equal **113**. Four sections: BSP
  collision geometry, the visible render mesh (with external `.Mat00` materials), a sector/portal visibility
  section, and a **blind-data** section holding the AI nav mesh. The MIT addon **io_scene_jupex** (Amphos)
  reads the header, collision, render mesh, and — most usefully — the full **object list**: every entity
  (player/AI spawn, trigger, light, door, pickup) is a `WorldObject` with a `type_name` and typed properties
  (`Name`, `Pos`, `Rotation`, scripting `CommandString`s, …). **Still opaque:** the sector/portal data and
  the whole blind-data block including the AI nav mesh.
- **Game database (`.Gamdb00p`).** Values live in a compiled binary DB (confirmed in the source:
  `ProfileDatabase/Defaults.Gamdb00p`). Edit the readable `FEAR.Gamdb00s`, recompile with GDBEdit.
- **Engine source — understanding only.** A Jupiter EX source mirror exists (Katana fork) but carries **no
  licence** and every Monolith file is "(c) 1997-2004 Monolith, All Rights Reserved" — read to understand,
  copy nothing. From it: the game is a server DLL (`CGameServerShell`, engine `IServerShell` v4) + a client
  DLL (`CGameClientShell`) + effects; there are **three** distinct "console" systems (engine cvars; the
  in-level trigger/event scripting `CommandMgr`; and `SCMD` remote admin) — don't conflate them; the AI is a
  **GOAP** planner (`AIAStarPlanner` running A* over `AIGoal*`/`AIAction*` classes), all server-side and
  data-driven. The buildable source is the official SDK, under its EULA.
- **In-memory inspection.** The discipline both EchoPatch and F.E.A.R. VR follow is *verify before you
  touch*: find the module, validate its PE headers (MZ/PE, 32-bit x86, expected build timestamp and image
  size), compute `base + known offset`, compare the bytes there against an expected pattern, and only then
  hook (MinHook trampoline) or overwrite (NOP via `VirtualProtect`). Every address is specific to one
  compiled binary.

## Pitfalls

1. **Hook addresses are build-specific.** A raw offset/pattern that works on the Steam exe can crash or
   silently no-op on GOG (different hash, same 1.08 timestamp). EchoPatch copes by supporting a fixed set of
   known builds (GOG included) and cleanly rejecting anything else. F.E.A.R. VR's client-side hooks live in
   the store-independent `GameOrig.dll` and should carry to GOG, but its exe-keyed "HID fix" stays off on an
   unrecognised build (its README lists GOG as "should work, untested"). Treat any raw offset as unverified
   until checked against the actual GOG binary.
2. **The 2003-compiler / ABI blocker (Route 3).** The retail game DLLs were built with Visual C++ 7.1 (VS
   2003). The engine passes whole C++ objects across the DLL boundary, so a rebuilt `ObjectDLL`/
   `ClientShellDLL` must match that old compiler's ABI or the retail exe will load it and then corrupt/crash
   on the first cross-module call. Use a VC7.1-compatible toolchain or do real porting. The Katana GPL engine
   is a separate modern rebuild and does **not** produce drop-in DLLs for the retail/GOG exe.
3. **Archive/database gotchas.** No dependable open `.Arch00` writer → prefer the loose-file/`-archcfg`
   override. Don't confuse `FEAR.Gamdb00s` (editable source) with `FEAR.Gamdb00p` (compiled) — editing the
   source without recompiling does nothing. Two mods that each ship a full `FEAR.Gamdb00p` conflict (last
   archive in `Default.archcfg` wins); merge or pick one.
4. **The GOG 60-fps cap is real and manual.** GOG's bundled `dxwrapper` caps the game at 60 fps; until
   `LimitPerFrameFPS` is set from 60 to 0 in `dxwrapper.ini`, that overrides EchoPatch's limiter and its
   high-frame-rate fixes can't fully take effect. Steam has no such bundled cap — GOG-only.
5. **Licence/legal limits** (none stop the owner modding their own copy; they limit copying/sharing): Katana
   engine source — no licence, read-only; EchoPatch — GPL-3 (borrowing its code into a distributed project
   forces GPL-3 + source + notices); io_scene_jupex and F.E.A.R. VR — MIT (reusable with the notice kept and
   credit to Amphos / the F.E.A.R. VR contributors); the official SDK — EULA, non-commercial F.E.A.R. mods,
   no redistributing Monolith source or shipping game assets.
6. **Not fully verified** (flagged honestly): the `.world00p` extension is confirmed from io_scene_jupex, not
   the Katana source; the AI nav mesh / blind-data block is parsed by no open tool; a current public QuickBMS
   `.Arch00` script is unconfirmed; the loose-file override is community practice, not proven from source; and
   every "it loads/works" claim about EchoPatch and F.E.A.R. VR is from their source and READMEs, read on
   Linux, not from running them.
