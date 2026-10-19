# Which GitHub repos to bring in next

**Status:** research done, nothing installed yet. The owner picks what to assimilate.

The owner asked which other GitHub projects the Playground should take in, the way universal-modder was
(read it, check the licence, judge it against the owner's rules, wire it in if it earns it). The aim is
modding many PC games with Claude: Ace Combat 7 now, F.E.A.R. next (the Playground had no notes on F.E.A.R.
before this), and others later.

## How it was done

A research workflow on 19 Oct 2026 (24 agents). Nine search agents each took one angle: Ace Combat and
flight games; F.E.A.R. and other mid-2000s PC games; Unreal Engine; Unity, .NET and Godot; general Windows
modding plumbing; open-source co-op mods; reverse-engineering tools Claude can drive; game-playing AI; add-ons
for Claude itself. They found 68 repos not already in the Playground. Vetting agents then checked each one's
licence, latest commit, what it would really give us, and any clash with the owner's rules. A ranking agent
picked 16, and two skeptic agents argued against each pick; three were dropped and seven moved down a tier.
The table of all 68 is in [all-candidates.md](all-candidates.md).

Licences matter here. MIT and Apache allow copying code in with credit. GPL allows using the tool and
reading the code, but not copying its code into our MIT-style folders. No licence means read only.

## The recommendations

### Do next (small, and useful for every game)

| Repo | What you'd get | The catch |
|---|---|---|
| `svnscha/mcp-windbg` (MIT) | Claude can open Windows crash files and debug a running game with Microsoft's own debugger: which line of which of our mods broke, with real names instead of addresses. Works for 64-bit AC7 and 32-bit F.E.A.R. | Needs Microsoft's free WinDbg on the PC. Its kernel-debugging tools must stay switched off (they need the PC started in a special mode), and it must never save a full memory copy of a copy-protected game, which would write the unprotected code to disk. |
| `horsicq/Detect-It-Easy` (MIT) | A one-second check of a game's program that names its copy protection and compiler. A session then knows straight away that it must work in memory only, which guards the no-DRM-removal rule on every new game. | Identification only. The signature list updates almost daily, so point it at a current copy rather than the last release. |

### Worth it when the matching work starts

| Repo | For | What you'd get | The catch |
|---|---|---|---|
| `CreeperUX/AC7-Integrated-Mod` (MIT) | AC7 bot and puppet planes | The only public map of where AC7 reads the flight stick on your exact game version, plus a small model of how the player's plane responds. The bot could steer smoothly instead of tapping keys, and puppet planes could move more naturally between updates. | Copy the code with credit; don't install its release (it brings its own launcher and updater). The bot already wins missions with key taps, so this is polish, not a rescue. Its keys clash with our flight-lab mod and Double Trigger. |
| `littleRabbit94/ue4ss-bridge` (MIT) | Any Unreal game, AC7 included | Claude can ask the running game questions live (where's that missile, what's this enemy doing) instead of writing and reloading a throwaway mod each time. | Its main loop uses the same kind of background timer that crashed AC7 for us; it needs that fixed before use, and it should run read-only. One author, untested on AC7. |
| `Wemino/EchoPatch` (GPL-3.0) | F.E.A.R. | The standard F.E.A.R. fix pack for modern PCs (HUD scaling, high frame rates, controllers) and the best guide to how the game's engine can be hooked. | **On the Steam copy, its first-run "large memory" offer strips Steam's copy protection**, which your rules forbid. It must be switched off in its settings file before the first launch, and a missing or reset settings file switches it back on. On the GOG copy, which has no copy protection, there's no problem. |
| `wattostudios/GameExtractor` (GPL-2.0) | F.E.A.R. and about 1,950 other games | Opens game archive files from the command line and copies files out without changing the originals. | Read-only use only (never its "replace" mode). A free script for the QuickBMS tool, which universal-modder already uses, also reads F.E.A.R.'s archives, so this is for breadth rather than F.E.A.R. alone. |
| `apitrace/apitrace` (MIT) | F.E.A.R. and other DirectX 8/9-era games | Records every drawing command an older game makes, so Claude can see how it draws its HUD and world. The usual frame-capture tool can't open games that old. | Replaying and inspecting recordings needs Windows; the cloud can only list them. |
| `atenfyr/UAssetAPI` / UAssetGUI (MIT) | Unreal games | The standard reader and writer for Unreal game files; it already handles AC7's extra encryption. A second opinion when your own AC7 tools misbehave. | Needs Microsoft's .NET Desktop Runtime installed. Its command-line mode is bare: it prints nothing and hides errors, so results must be checked. |
| `anthropics/claude-plugins-official` (Apache-2.0) | Claude's own coding | Official add-ons that check Lua, C++ and Python as Claude writes them, so fewer mod builds break. | The add-ons only describe language checkers; the checkers themselves have to be installed on the PC. Modest gain. |

### Read only, don't install

| Repo | Why it's worth reading | Why only reading |
|---|---|---|
| `katana-steel/lithtech` (no licence) | Monolith's own game code for F.E.A.R. and No One Lives Forever 2, including NOLF2's built-in co-op mission mode: the clearest model for F.E.A.R. co-op. | No licence, so nothing can be copied. The F.E.A.R. part is the official modding kit, which reportedly ships with the Steam edition (`extras\fear_publictools_108.exe`), so the PC can read the licensed original instead. |
| `Five-Damned-Dollarz/io_scene_jupex` (MIT) | The only open reader for F.E.A.R.'s level files (enemies, spawn points, doors, triggers). | Small and two years old; worth about 75 lines when a F.E.A.R. level tool is actually needed. |
| `WerWolv/ImHex` (GPL-2.0) | A hex viewer that lays out the structure of unknown game files. | Overlaps what sessions already do with small Python readers. Keep for a tough format puzzle. |
| `snowyegret23/UnityInfoMCP` (MIT) | Lets Claude see inside a running Unity game. | No Unity game is on the list yet; revisit when one is. |

### Dropped after the skeptics

- `trumank/jmap`: UE4SS, which we already have, gained the same dump in August.
- `exraven99-design/PWCoop` (co-op for Project Wingman): everything worth borrowing is already in Double
  Trigger or our own AC7 notes.
- `DR-89/fear-vr`: better F.E.A.R. references cover each part.

## Turned down because of your rules

These are the projects someone might expect on a list like this. Each crosses a line.

- **Goldberg Steam emulator (`gbe_fork`) and Nucleus Co-op:** the usual way to run two copies of a game on
  one PC, but they fake Steam, which counts as a piracy tool. Nucleus Co-op bundles the emulator.
- **Steamless:** removes Steam's copy protection. Several other tools quietly lead to it.
- **FEAR-MORE (a big F.E.A.R. upgrade):** its docs are good reading, but on Steam it only runs on a
  program with the copy protection stripped.
- **A F.E.A.R. co-op server mod (`Vityacv/fearservmod`):** no licence, swaps in No-CD programs and uses fake CD keys.
- **Special K:** has an opt-in switch to bypass online DRM checks and turns on per-game DRM workarounds itself.
- **Widescreen Fixes Pack:** includes a copy-protection bypass for at least one game. Read its Condemned fix
  (same engine as F.E.A.R.) as a pattern only.
- **A Cheat Engine bridge and an x64dbg bridge for Claude:** the first needs a kernel driver that comes with a
  blue-screen warning; the second advertises getting past anti-debugging and anti-cheat and saving unpacked
  programs to disk.
- **`uevr-mcp` and `bepinex-mcp`:** their in-game servers take commands with no password (one even offers a
  public internet link), so a web page or another machine could run code inside the game.
- **Skyrim Together:** fine to read later for open-world co-op ideas, but its launcher loads the game
  program into itself, which comes too close to the no-unpacking rule on protected games.
- Several "AC7 trainer" and "AC7 codex" repos look like cracks or malware bait.

## Gaps nobody covers

- **No LithTech toolkit exists.** universal-modder has no LithTech page and nobody has published one. A
  F.E.A.R. guide would have to be written by us, from EchoPatch, Monolith's SDK and the readable sources above.
- **No F.E.A.R. co-op mod has usable source.** The old ones are closed downloads; a new one would be built
  on Monolith's official SDK (whose licence limits sharing SDK-derived code).
- **F.E.A.R. game code needs a 2003-era Microsoft compiler** to match the game; the alternative is a bridge
  of our own that avoids the mismatch.
- **No open tool repacks F.E.A.R.'s archives.** The game can load loose folders instead.
- **AC7's enemy flight model isn't documented anywhere**, so the bot's prediction error on turning enemies
  has only general fixes.
- **No maintained virtual-gamepad driver** for any game; the old one was retired in 2023.
- **No ready, rule-safe way to find an Unreal game's archive key in memory.** universal-modder's own route
  reads the protected program on disk.
- **No co-op playbook** in universal-modder; the references exist, the guide doesn't.

## A question for the owner

**Is your F.E.A.R. on Steam or GOG?** The GOG version has no copy protection, so most F.E.A.R. fixes and
mods can be used within your rules. On Steam, several popular ones would strip Steam's protection, which
the rules forbid, and each needs care.
