# Ace Combat 7: can it go co-op?

**Status:** research done, nothing built yet.

The question: can Ace Combat 7: Skies Unknown (PC, Steam, 2019) be played with a
friend, ideally the story campaign? Researched with the
[Co-op Anything](https://github.com/cranebeaker/coop-anything) playbook (MIT
license, by cranebeaker) as the guide.

## Short answer

Nobody has done it. The game isn't in Co-op Anything's directory of 230+ games,
and searching the web turned up no co-op campaign mod and no mod that adds AI
enemies to online play. It's possible in principle, but it would be a build from
scratch, and a big one.

## What the game has out of the box

- **Engine:** Unreal Engine 4. The exact version is unknown.
- **Online modes:** Battle Royale (8-player free-for-all) and Team Deathmatch
  (4v4), both player-versus-player. There's no campaign co-op and no mode where
  players team up against computer enemies. Team Deathmatch is the only way to
  fly on the same side as a friend.
- **Copy protection:** Denuvo was removed in October 2021, so there's nothing to
  get around there.
- **Anti-cheat:** none confirmed. Forum posts say it never had any, but that's
  unverified. Our rule doesn't change either way: mods stay out of public online
  matches.

## Pieces modders have already built

- **Campaign maps in multiplayer:** "Selatapura MP" and "Selatapura Hellscape MP"
  on Nexus Mods let players fly a campaign map in an online match. Nexus blocks
  automated page reads, so details come from search snippets only. Nothing
  suggests they add AI enemies, which makes them player-versus-player only.
- **Multiplayer parts in the campaign:** "All Parts in CampaignMode" goes the
  opposite direction.
- **Enemy AI edits:** "Mostly Passive Enemy AI" changes how enemy pilots behave.
  It's single-player only, but it shows the AI settings live in moddable files.
- **UE4SS:** a custom build for Ace Combat 7 is on Nexus. It's the scripting tool
  the Co-op Anything guide recommends for Unreal Engine 4 games, and it allows
  Lua and C++ script mods plus Blueprint mods.
- **Modding wiki and templates:** the community has a modding wiki with developer
  resources, including the Nimbus Project Template.
- **Split screen:** a YouTube video claims split-screen play. That's probably
  Nucleus Co-op running two copies of the online mode, since Nucleus needs the
  game's own multiplayer. Unverified: no Ace Combat handler turned up on the
  Nucleus handler hub.

## Why it's hard

Following Co-op Anything's triage: because the game ships a multiplayer mode, the
networking for player planes, weapons and damage already exists. Co-op means
making the single-player parts run over that networking: enemy planes and ground
targets, mission objectives and triggers, scripted events, radio chatter,
cutscenes, checkpoints, and the mission ending. None of that was built for two
players.

## A ladder, easiest first

1. **Fly campaign maps together.** Already exists (Selatapura MP), but it's
   player versus player.
2. **Co-op skirmish:** two players on a multiplayer map, with the host spawning
   AI enemy planes. This is the first real experiment, and it hinges on one
   unknown: whether AI planes work inside an online match at all.
3. **One campaign mission in co-op.**
4. **The full campaign.**

## What hands-on work would need

- A Windows PC with Ace Combat 7 on Steam. Every player needs their own copy.
- Claude Code running on that PC. The cloud workspace has no games and no
  screen.
- All work done on a copy of the game folder, never the real install or saves.
- Private lobbies only, never public matches.

## Unknowns

- Exact Unreal Engine version.
- Whether online matches are hosted by one player's PC or by Bandai Namco's
  servers.
- Whether the game's AI aircraft can be synced between two players.
- Whether a Nucleus Co-op handler exists.

## Next steps if we pick this up

- Read the Selatapura MP pages and comments on Nexus by hand (automated reads are
  blocked) and see whether its author has tried AI.
- Check the Ace Combat 7 modding wiki and community Discord for anyone working on
  PvE.
- Search the Nucleus handler hub (hub.splitscreen.me) for Ace Combat 7.

## Sources

- [Co-op Anything](https://github.com/cranebeaker/coop-anything): directory, triage and engine-family playbooks
- [Twinfinite: Ace Combat 7 co-op and multiplayer](https://twinfinite.net/guides/ace-combat-7-co-op-multiplayer-what-need-know/)
- [PlayStation Blog: multiplayer modes in full](https://blog.playstation.com/archive/2019/01/10/ace-combat-7-skies-unknowns-multiplayer-modes-detailed-in-full)
- [Steam: "Does this game allow PvE co-op in any way?"](https://steamcommunity.com/app/502500/discussions/0/3387282447741691991/)
- [Steam: 2-player co-op campaign request](https://steamcommunity.com/app/502500/discussions/0/3829691612504033035)
- [DSOGaming: Denuvo removed](https://www.dsogaming.com/news/bandai-namco-has-removed-denuvo-from-ace-combat-7-skies-unknown)
- [Nexus: Selatapura MP](https://www.nexusmods.com/acecombat7skiesunknown/mods/1436)
- [Nexus: Selatapura Hellscape MP](https://www.nexusmods.com/acecombat7skiesunknown/mods/1625)
- [Nexus: All Parts in CampaignMode](https://www.nexusmods.com/acecombat7skiesunknown/mods/623)
- [Nexus: Mostly Passive Enemy AI](https://www.nexusmods.com/acecombat7skiesunknown/mods/1449)
- [Nexus: Pre-Campaign mod (VR)](https://www.nexusmods.com/acecombat7skiesunknown/mods/3223)
- [TTFH/Ace-Combat-7-Mods](https://github.com/TTFH/Ace-Combat-7-Mods): older pak tools, marked deprecated by its author
- [YouTube: Ace Combat 7 split screen](https://www.youtube.com/watch?v=hrqXI2iRWd0)
- [Steam: anti-cheat discussion](https://steamcommunity.com/app/502500/discussions/0/3816292540678405043)
- [Nucleus Co-op FAQ](https://splitscreen.me/docs/faq)
