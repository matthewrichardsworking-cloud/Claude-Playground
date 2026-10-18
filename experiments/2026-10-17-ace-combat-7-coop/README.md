# Ace Combat 7: can it go co-op?

**Status:** research done, plan made and the workbench set up (four sessions, 17 Oct
2026): a plain game copy with UE4SS that starts on its own, dumps the game's
catalogue, and keeps its saves and settings in its own folder so it can't touch the
owner's real save (proved at the title screen by checksums; a run into a mission is
still to be done). Two copies at once don't work yet. Nothing co-op built yet.

The question: can Ace Combat 7: Skies Unknown (PC, Steam, 2019) be played with a
friend against computer-controlled enemies, ideally the story campaign? Researched with
the [Co-op Anything](https://github.com/cranebeaker/coop-anything) playbook (MIT
license, by cranebeaker) as the guide.

The second session ran on the owner's PC with the game installed. Its notes are copied
here: [plan.md](plan.md), [research.md](research.md), [identity.md](identity.md). The
third set up the workbench and tested it, and the fourth gave the copy its own save
folder: [workbench.md](workbench.md). The working
copies live in the project folder `Claude Apps\AC7-Coop` on that PC.

## Short answer

Nobody has done it: no co-op mod, no mod that puts AI enemies into online play, and no
Ace Combat entry, issue or pull request in Co-op Anything. It's a build from scratch.
A co-op skirmish against AI waves looks realistic but not easy; the full campaign is a
long shot. The owner already has a head start: an earlier session built their mod
loader and a "Horde Mode" mod with tools that read and rewrite AC7's mission scripts.

## The game, checked on the owner's PC

- **Build:** Steam build 9855922, game version 2.2.1.16, `Ace7Game.exe` SHA-256
  `c7da97f5f8a807d4f1264adbb074146fcffe9bdc2ffa98791b822cd28e558f4f`.
- **Engine:** Unreal Engine **4.18.2** (from the exe's version info).
- **Online modes:** Battle Royale (8 players) and Team Deathmatch (4v4), both
  player-versus-player, on six maps. No mode with AI.
- **How online works:** player-hosted, peer to peer over Steam. Steam lobbies, Steam's
  network driver with relay, and Bandai Namco's own layer ("SNL") with a host and host
  migration. No sign of Bandai Namco game servers.
- **Copy protection:** Steam's own wrapper (SteamStub). The exe's code is scrambled on
  disk, so Ghidra can't read it from the file, and unscrambling it is off limits.
  Denuvo was removed in 2021.
- **Anti-cheat:** no third-party anti-cheat, and the Steam store page lists no VAC (the
  `bVACEnabled=1` in its config is Unreal's default). The game does run its own cheat
  checks in online matches (health, ammo, damage, position) with an automatic kick.
- **Ace Combat 8** (Oct 2026, Unreal Engine 5) has official co-op against AI online
  ("Co-Op Assault"), but no co-op campaign.

## Pieces modders have already built

- **PM-UE4SS:** the AC7 build of UE4SS (Lua and C++ scripting, reflection dumps), on
  [GitHub](https://github.com/Playmore-ModdingConcepts/PM-UE4SS) with one release, also
  on Nexus.
- **The owner's own tools** (6 Oct 2026, by a Claude session): AC7 Mod Loader, plus
  Python tools that read AC7's encrypted data packs and read and write mission-script
  (Kismet) bytecode. They built "Horde Mode" (Mission 01 as endless AI waves) and
  "Double Enemy Aircraft". So spawning AI planes already works in single-player.
- **Campaign maps in multiplayer:** "Selatapura MP" and "Selatapura Hellscape MP" on
  Nexus. Nothing found says they add AI. Nexus blocks automated reads, so the owner was
  asked to check by hand.
- **Enemy AI edits:** "Mostly Passive Enemy AI" (single-player only).
- **Nucleus Co-op:** no AC7 handler. Not usable here anyway: it swaps the game's Steam
  file for a fake one.

## The plan in one paragraph

Route B ("two single-player games kept in step", Co-op Anything's standard method):
each player runs the same single-player mission, a UE4SS mod connects the two games,
shows each player's plane in the other's game as a puppet, and lets the host's game run
the enemies. Before that, a short check of Route A (spawn AI in a private online room
and see whether the game syncs it). Ladder: workbench on a clean copy of the game, then
co-op Horde Mode, then one campaign mission, then the campaign. Details, tests and
unknowns are in [plan.md](plan.md).

## Unknowns

Resolved on 17 Oct: the engine version (4.18.2), and how online matches are hosted
(player PCs over Steam, not Bandai Namco servers). Nucleus handler: none found.

Still open:

- Smooth puppet planes at jet speed, with missiles locking on correctly.
- Taking over AI planes at run time on the client's game.
- How far UE4SS's reflection catalogue gets us, given that the exe's code can't be
  read.
- Whether the game copy starts on its own, and whether two copies run on one PC.
- Route A only: whether the game's own online layer can carry AI planes, and whether
  its cheat checks kick a modded player.

## Sources

- [Co-op Anything](https://github.com/cranebeaker/coop-anything): directory, triage, build-from-zero, networking and tools playbooks
- [Twinfinite: Ace Combat 7 co-op and multiplayer](https://twinfinite.net/guides/ace-combat-7-co-op-multiplayer-what-need-know/)
- [PlayStation Blog: multiplayer modes in full](https://blog.playstation.com/archive/2019/01/10/ace-combat-7-skies-unknowns-multiplayer-modes-detailed-in-full)
- [Steam: "Does this game allow PvE co-op in any way?"](https://steamcommunity.com/app/502500/discussions/0/3387282447741691991/)
- [Steam: 2-player co-op campaign request](https://steamcommunity.com/app/502500/discussions/0/3829691612504033035)
- [Steam: room settings and host migration](https://steamcommunity.com/app/502500/discussions/0/3468352315395862922)
- [Steam store page](https://store.steampowered.com/app/502500/)
- [DSOGaming: Denuvo removed](https://www.dsogaming.com/news/bandai-namco-has-removed-denuvo-from-ace-combat-7-skies-unknown)
- [GitHub: PM-UE4SS](https://github.com/Playmore-ModdingConcepts/PM-UE4SS)
- [Nexus: UE4SS for AC7](https://www.nexusmods.com/acecombat7skiesunknown/mods/2474)
- [Nexus: Selatapura MP](https://www.nexusmods.com/acecombat7skiesunknown/mods/1436)
- [Nexus: Selatapura Hellscape MP](https://www.nexusmods.com/acecombat7skiesunknown/mods/1625)
- [Nexus: All Parts in CampaignMode](https://www.nexusmods.com/acecombat7skiesunknown/mods/623)
- [ModDB: Mostly Passive Enemy AI](https://www.moddb.com/games/ace-combat-7/addons/mostly-passive-enemyai)
- [ModDB: Playmore](https://www.moddb.com/mods/playmore)
- [TTFH/Ace-Combat-7-Mods](https://github.com/TTFH/Ace-Combat-7-Mods): older pak tools, marked deprecated by its author
- [Nucleus Co-op FAQ](https://splitscreen.me/docs/faq)
- [Ace Combat Wiki: Co-Op Assault (AC8)](https://acecombat.wiki.gg/wiki/Co-Op_Assault)
