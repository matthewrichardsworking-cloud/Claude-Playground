# Modding F.E.A.R. (LithTech Jupiter EX) — playbook and GOG setup

**Status:** studied; playbook and setup written. Nothing installed. The hands-on steps are for a session on
the owner's PC, where the game and the SDK live.

The owner owns **F.E.A.R. on GOG** and wants to mod it. No LithTech playbook existed anywhere (not in
universal-modder, not here), so this fills that gap: how the engine works, the realistic ways to mod it, how
to read the game's files, the traps, and a plain-steps setup for the GOG copy. Built from a read-only study of
the public references in the sandbox; the owner's own licensed SDK on the PC is the primary source for the
hands-on work (below).

## What this means for the owner, up front

- **GOG is the good case.** It's DRM-free, so nothing needs cracking or stripping — every mod route is just
  reading the game's own files or patching its running memory. The Steam "4GB/large-memory" prompt that I
  warned about earlier never appears on GOG, and there's nothing to switch off for it.
- **Start with the fix pack (EchoPatch).** Two files dropped next to the game modernise it (HUD scaling, FOV,
  high-frame-rate fixes, controller support, skip-intro, a dev console) with no change to any game file. It
  officially supports the GOG "F.E.A.R. Platinum" build. Ten minutes, fully reversible. Steps in
  [setup.md](setup.md).
- **One GOG-only step:** the GOG copy ships a wrapper that caps the game at 60 fps. Until you change one line
  in `dxwrapper.ini`, the fix pack's smoothness fixes can't fully kick in. setup.md walks through it.
- **Your SDK folder is the right source for the deep work.** You mentioned the F.E.A.R. SDK is in your
  `Claude Tools` folder — that's the official **F.E.A.R. Public Tools v1.08** kit (the level editor, the game
  source, the data tools). A PC session should use *that* licensed copy for anything beyond the fix pack,
  rather than the unlicensed source mirror on GitHub. Its licence (Monolith's EULA, non-commercial F.E.A.R.
  mods) means SDK-derived code stays on the PC and off this public repo. (From this cloud session I can't see
  that folder — it's on your PC — so a desktop session should confirm the exact path.)

## The honest limits

- **F.E.A.R. has no co-op to turn on.** The retail game shipped only competitive multiplayer; there's no
  co-op campaign code and no open source for one. Its sister game NOLF2 shows the pattern, but adding co-op to
  F.E.A.R.'s heavily-scripted single-player is an unbuilt, source-level project — a much bigger job than the
  Ace Combat co-op.
- **Deep code mods hit a compiler wall.** The game's own DLLs were built with a 2003-era Microsoft compiler;
  rebuilding them needs that toolchain or real porting work (detail in the playbook).
- **Some things have no open tooling:** no reliable open repacker for the game's archives (you add content as
  a higher-priority layer instead), and no published list of memory addresses for the GOG build (anything that
  patches the running game has to find them against your exact exe).

## Files

| File | What it is |
|---|---|
| [playbook.md](playbook.md) | The LithTech / F.E.A.R. engine playbook: Identify, Routes, Read the game, Pitfalls. For a session doing the work. |
| [setup.md](setup.md) | The EchoPatch-on-GOG install in plain steps, and a first small thing to try that proves the toolchain. |

## Credits

Built from reading, each under its own licence: **EchoPatch** (Wemino, GPL-3.0), **io_scene_jupex** (Amphos,
MIT — the F.E.A.R. level-format reader), **F.E.A.R. VR** (DR-89 and contributors, MIT — the in-memory hook
method), and Monolith's Jupiter EX source read for understanding only (the Katana mirror carries no licence
and is marked "all rights reserved", so nothing was copied from it). The official route is Monolith's F.E.A.R.
Public Tools SDK under its own EULA.
