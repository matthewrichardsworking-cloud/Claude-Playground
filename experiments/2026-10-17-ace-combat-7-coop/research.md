# Research: existing work, and how AC7's online play works

Done 17 Oct 2026. Builds on the earlier note in the Playground repo
(`experiments/2026-10-17-ace-combat-7-coop`). Short version first, details below.

## Short version

- **Nobody has made Ace Combat 7 co-op**, and nobody has published a mod that puts AI
  enemies into an online match. Co-op Anything has no entry, issue or pull request for
  any Ace Combat game.
- **Online matches are hosted by a player's PC, not by Bandai Namco's servers.** One
  player's game is the "host" (it runs the match), the others connect to it through
  Steam. If the host leaves, the game moves the match to another player ("host
  migration"). Steam relays the traffic when two PCs can't reach each other directly.
- **You already have a head start.** An earlier Claude session (6 Oct) built your AC7
  Mod Loader plus home-made tools that read and rewrite AC7's mission scripts. Your
  "Horde Mode" and "Double Enemy Aircraft" mods were made with them. Spawning waves of
  AI enemy planes already works in single-player.
- **Ace Combat 8 (on this PC since 2 Oct 2026) has official co-op against AI**
  ("Co-Op Assault", teams of four), but no co-op campaign.

## 1. Searched, and what turned up

Searched on 17 Oct 2026:

- Co-op Anything directory: "ace combat", "flight", "wingman": nothing.
- Co-op Anything GitHub issues and pull requests for "ace combat": 0 results.
- Web: AC7 co-op mod / PvE / AI enemies in multiplayer; AC7 UE4SS; AC7 Horde Mode;
  AC7 multiplayer hosting and host migration; Selatapura MP; two copies of AC7 on one
  PC; AC7 multiplayer mods on GitHub; Nucleus Co-op handler for AC7; Project Wingman
  co-op (another Unreal Engine 4 jet game); Ace Combat 8 co-op.

Found:

| What | Where | What it means for us |
|---|---|---|
| No co-op mod of any kind for AC7 | all of the above | Build from scratch (Co-op Anything's `coop-build-from-zero` path). |
| **Mostly Passive Enemy AI** | [ModDB](https://www.moddb.com/games/ace-combat-7/addons/mostly-passive-enemyai) | Changes enemy AI in single-player; its page says multiplayer is not affected. Shows AI settings are moddable, nothing more. |
| **Selatapura MP** | [Nexus 1436](https://www.nexusmods.com/acecombat7skiesunknown/mods/1436) (last updated May 2026 per search results) | Puts a campaign map into online matches. Nothing found says it adds AI. **Needs a manual check** (Nexus blocks automated reading), see "For you to check" below. |
| **PM-UE4SS**, the AC7 build of UE4SS (a scripting add-on for Unreal games) | [GitHub: Playmore-ModdingConcepts/PM-UE4SS](https://github.com/Playmore-ModdingConcepts/PM-UE4SS), also [Nexus 2474](https://www.nexusmods.com/acecombat7skiesunknown/mods/2474) and [ModDB](https://www.moddb.com/downloads/unreal-engine-scripting-system-ac7) | Our main tool for hands-on work. The GitHub page has one release, "(Playmore) - Unreal Engine 4 Scripting System", published 13 March by Rythus711, 3 files. That's the official download page to use later. Nothing downloaded yet. |
| Playmore modding project | [ModDB](https://www.moddb.com/mods/playmore) (blocks automated reading) | Search snippets say its author edits mission scripts and is working on "custom mission actors and events". Same kind of work as your Horde Mode. Worth contacting later. |
| NimbusModManager | [GitHub: M4rkoza7/NimbusModManager](https://github.com/M4rkoza7/NimbusModManager) | Another AC7 mod manager, handles UE4SS mods. Not needed: you have your own. |
| Nucleus Co-op (runs several copies of a game on one PC for split screen) | [splitscreen.me](https://splitscreen.me/docs/faq) | No AC7 handler found. It works by swapping the game's Steam file for a fake one, which is too close to getting around copy protection, so we won't use it. |
| Project Wingman | search | No co-op mod either; it's single-player only. |
| **Ace Combat 8: Wings of Theve** | [Bandai Namco](https://www.bandainamcoent.com/games/ace-combat-8), [Ace Combat Wiki](https://acecombat.wiki.gg/wiki/Co-Op_Assault) | Released 2 Oct 2026 on Unreal Engine 5. Its online part has "Co-Op Assault" (two teams of four against computer enemies, also competing on score) and "Co-Op Warfare" (players and computer units together). The campaign is single-player only. |

## 2. How AC7's online matches work

Evidence from the game itself (read-only checks of the exe and of the game's config
files inside its data packs), plus one Steam forum thread.

- **Steam is the online service.** The config sets Steam as the online platform and
  uses Unreal's Steam network driver (the part that carries game data between PCs),
  with plain internet connections as a fallback.
- **Player-hosted, peer to peer.** "Peer to peer" means the players' PCs talk to each
  other directly instead of through a company server. The exe contains Bandai Namco's
  own multiplayer layer, called "SNL", with a "P2P session" protocol, a named host
  ("SNL_P2P_HOST") and a full host-migration system. A player in a
  [Steam thread](https://steamcommunity.com/app/502500/discussions/0/3468352315395862922)
  also mentions the host role moving to them.
- **Lobbies are Steam lobbies.** Rooms, invites, kicks and chat go through Steam's lobby
  system. Steam relays traffic when needed (`bAllowP2PPacketRelay=true`), so nobody has
  to open ports on their router.
- **No sign of Bandai Namco game servers.** The only web addresses in the exe are
  Epic's crash-report address and an official AC7 web page.
- **The game has its own cheat checks for online play.** The exe names tests for
  plane health, ammo, weapon damage, plane location and "cheating properties", plus an
  automatic kick system. They're probably run by the host. A co-op mod that changes
  how planes behave inside an online match could trip them. We will not switch them
  off; if they get in the way, I'll ask you first.
- **Modes and maps.** Game modes in the exe: lobby, Battle Royale ("DeathMatch"),
  Team Deathmatch, and the single-player modes. There are six online maps (mp01 to
  mp06, each with a Battle Royale and a Team Deathmatch version; a seventh is disabled
  in the config).
- **Leftover developer commands.** The exe still names about 80 developer commands for
  the online layer, for example forcing a mission complete, faking an online session,
  a network delay simulator, and "SNL_ArrangeWindows", which suggests the developers
  ran several game windows on one PC. Released games usually can't run these, but
  UE4SS can sometimes reach them. Worth trying in the workbench step.

## 3. What a co-op mod can build on

- **UE4SS (PM-UE4SS build).** Loads inside the game. Runs Lua scripts (a simple
  programming language) and C++ add-ons, and can dump the game's "reflection" catalogue:
  the list of every class, setting and function the engine knows about by name. That
  catalogue is our map of the game.
- **Your earlier tools** (written by a Claude session on 6 Oct, kept with the Horde Mode
  and Double Enemy Aircraft mods in `ModLoader\library\<mod>\rebuild\`):
  `ac7pak.py` (reads AC7's encrypted data packs), `uepkg.py` (reads and rewrites game
  assets), `kismet.py` and `kasm.py` (read and write mission-script code, which Unreal
  calls "Kismet" or Blueprint bytecode), `build_horde.py` (builds Horde Mode). The full
  source of AC7 Mod Loader, these tools and their research notes are in the Claude app's
  private storage (`...\LocalCache\Roaming\Claude\scratch-workspaces\...\scratch-2026-10-06-29080e`).
  Because that storage is hidden and could be lost if the app is reinstalled, the first
  hands-on step copies them into this folder.
- **Mission script functions already decoded** by those tools, for example
  `StartMissionPhase`, `ActivateUnit`, `RestoreUnit`, `GetPlayerPlane`,
  `RequestPlayRadio`, `ModifyHealth`. Plane classes in the exe: `APlane` (all planes),
  `APlayerPlane` (yours), `AAIPlane` (computer-flown).
- **Ghidra and REA, with a limit.** Steam's wrapper keeps the exe's code scrambled on
  disk, so Ghidra can't read the game's code from the file. Unscrambling it would be
  getting around copy protection, so we won't. REA and Ghidra stay useful for reading
  the dump files, other DLLs and data. Most Unreal modding never needs the exe's code,
  because UE4SS works from the reflection catalogue instead.

## 4. For you to check by hand (sites that block automated reading)

On [Selatapura MP (Nexus 1436)](https://www.nexusmods.com/acecombat7skiesunknown/mods/1436)
and [Selatapura Hellscape MP (Nexus 1625)](https://www.nexusmods.com/acecombat7skiesunknown/mods/1625):

1. Description tab: does it say anything about AI planes, enemies, ground targets or
   "PvE"? Does it say how it works (replaces a multiplayer map, or adds a new one)?
2. Posts tab (the comments): search the page (Ctrl+F) for "AI", "enemy", "co-op",
   "coop" and "PvE". Note anything the author says about trying AI.
3. The author's name, and whether they link a Discord server.

On the [Playmore page on ModDB](https://www.moddb.com/mods/playmore): is there anything
about multiplayer, or a Discord server link?

## Sources

- [Twinfinite: AC7 co-op and multiplayer](https://twinfinite.net/guides/ace-combat-7-co-op-multiplayer-what-need-know/)
- [Steam: "Does this game allow PvE co-op in any way?"](https://steamcommunity.com/app/502500/discussions/0/3387282447741691991/)
- [Steam: room settings and host migration](https://steamcommunity.com/app/502500/discussions/0/3468352315395862922)
- [Steam store page for AC7](https://store.steampowered.com/app/502500/) (features: single-player, online PvP, Steam Cloud, Family Sharing; no anti-cheat listed)
- [ModDB: Mostly Passive Enemy AI](https://www.moddb.com/games/ace-combat-7/addons/mostly-passive-enemyai)
- [Nexus: Selatapura MP](https://www.nexusmods.com/acecombat7skiesunknown/mods/1436)
- [GitHub: PM-UE4SS](https://github.com/Playmore-ModdingConcepts/PM-UE4SS) and its [releases](https://github.com/Playmore-ModdingConcepts/PM-UE4SS/releases)
- [Nexus: UE4SS for AC7](https://www.nexusmods.com/acecombat7skiesunknown/mods/2474)
- [ModDB: Playmore](https://www.moddb.com/mods/playmore)
- [GitHub: NimbusModManager](https://github.com/M4rkoza7/NimbusModManager)
- [Nucleus Co-op FAQ](https://splitscreen.me/docs/faq)
- [Ace Combat Wiki: Co-Op Assault](https://acecombat.wiki.gg/wiki/Co-Op_Assault) and [Ace Combat 8](https://acecombat.wiki.gg/wiki/Ace_Combat_8:_Wings_of_Theve)
- [Bandai Namco: Ace Combat 8 multiplayer reveal](https://www.bandainamcoent.com/news/ace-combat-8-wings-of-theve-multiplayer-reveal)
- [Co-op Anything](https://github.com/cranebeaker/coop-anything) (MIT, by cranebeaker): triage, build-from-zero, networking and tools playbooks
