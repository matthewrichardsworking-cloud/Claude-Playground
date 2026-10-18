# Plan: Ace Combat 7 co-op, easiest step first

Written 17 Oct 2026. Each step has to work and be tested before the next one starts.
Every step ends with something you can actually play.

**Update, 18 Oct 2026.** Two things changed the picture since this was written:

1. **Someone else is about to release a co-op mod that takes Route A** (the game's own
   online layer, see research.md section 5). Decision: wait for that release, read it,
   and try it in the copy before building further here. If it is stable, the better use
   of this project is testing and helping that mod rather than finishing a second,
   less thorough one. Everything below stays as the fallback plan.
2. **Step 0 is done and step 1's first item works** (workbench.md sections 4 to 7): the
   copy has its own save folder, a session can fly a mission in it, and a puppet plane
   follows a recorded flight to within centimetres, straight and in turns. Two copies on
   one PC cannot get past the title screen (the second never gets a Steam connection),
   so the network tests in step 1 need a second PC, and the game's leftover developer
   commands turned out to be empty in this build (step 0 test 4).

## A few words used below

- **Host**: the PC whose game is "in charge". It decides where enemies are and what
  happens in the mission. The other player is the **client**.
- **Sync** (synchronise): keep the two games showing the same thing.
- **Puppet**: a plane in your game that isn't flown by you or by the game's AI, but
  moved by position updates arriving over the internet from the other player.
- **Latency**: the delay for data to get from one PC to the other, usually 20 to 150
  milliseconds between friends.
- **UE4SS**: a free add-on that runs inside Unreal Engine games and lets mods run Lua
  scripts (a simple programming language) or C++ code while the game plays.
- **Mission script**: the instructions inside each mission that spawn enemies, start
  radio lines, move to the next phase and decide when you've won. Unreal calls them
  Blueprints.

## Two ways to build it

**Route A: use the game's own online mode.** Make a private Team Deathmatch room, put
both of you on one team, and have the host's game spawn AI enemy planes. The game's own
online layer would then have to send those planes to the other player. It was never
built to do that, the exe's code can't be read to find out how (Steam keeps it
scrambled on disk), and the game's own cheat checks watch online matches.

**Route B: two single-player games kept in step.** This is Co-op Anything's standard
method (Super Mario 64's sm64coopdx works this way). You each start the same
single-player mission. Our mod connects the two games, puts each player's plane into
the other's game as a puppet, and makes the host's game the boss of the enemies: the
client's enemies copy the host's, hits are reported to the host, and the host announces
kills.

**Recommendation: Route B, after a short Route A check.** Route B is more work up
front, but the same design carries straight into campaign missions (steps 2 and 3),
stays away from the game's online rooms and cheat checks, and can probably be tested
with two copies on this one PC. The Route A check is cheap: spawn one AI plane in a
private room and see whether your friend's game shows it. If it does, that changes the
plan for step 1, and I'll come back to you.

## Step 0: set up a safe workbench (this PC, offline)

What it needs:

- **A copy of the game, without your mods.** Proposed place: `C:\AC7-Coop-Game`.
  Space needed: **65.7 GB** (Windows Explorer shows it as 61.2 GB). Drive C: would go
  from about 317 GB free to about 251 GB free. I suggest C: rather than D: because D:
  is the external USB SanDisk drive: it can be unplugged mid-test, and its format
  (exFAT) can't do the "hard links" your mod loader uses. D: works too if you'd rather
  keep the space on C: (373 GB free there). The copy leaves out `~mods` and
  `ModLoader`; your real install, mods and mod loader aren't touched.
- **A save backup before every session.** The copy uses the same save folder as your
  real game (`%LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 7`, 0.7 MB), and
  Steam Cloud syncs it. So before each test run I copy that folder into
  `backups\` here, dated. If anything goes wrong, it goes back exactly as it was.
- **The earlier tools, moved into this folder.** AC7 Mod Loader's source, the mission
  script tools and their research notes are only in the Claude app's hidden storage.
  Copy (not move) them here.
- **UE4SS for AC7 (PM-UE4SS)**, downloaded from its
  [GitHub releases page](https://github.com/Playmore-ModdingConcepts/PM-UE4SS/releases),
  checksum checked, installed into the copy only. I'll ask before downloading.

Tools: Co-op Anything (method), PM-UE4SS, the earlier Python tools, REA (reading dump
files and logs).

How we test it:

1. The copy starts from its own folder with Steam open, and it really is the copy that
   runs (the window shows no mods, and the game's log is written by the copy). Risk:
   Steam might start your real install instead.
2. **Can two copies run at once on this PC?** Start the copy twice; both should reach
   the main menu. Lower graphics settings and windowed mode will help.
3. UE4SS loads, its console opens, and the reflection dump (the game's own list of
   every class and function) gets written. That list is our map of the game.
4. Try a few of the leftover developer commands, offline only (for example the one that
   arranges windows).

## Step 1: co-op skirmish against AI (ladder rung 2)

Goal: you and your friend fly one map together against waves of AI enemies. The
obvious candidate is your own **Horde Mode** (Mission 01 as endless waves), because
spawning the waves already works.

What it needs, in order:

1. **Puppet plane, no network yet.** In the copy, spawn a friendly plane and move it
   along a recorded flight path instead of letting the AI fly it.
   Test: it flies smoothly at full speed, doesn't fight anyone, and the game doesn't
   crash in 30 minutes.
2. **Connection between two copies on this PC.** Each game sends its own plane's
   position about 30 times a second; the other game moves the puppet. The game guesses
   ahead between updates, because a jet covers about 30 m in a tenth of a second.
   Test: in two windows side by side, each puppet follows the other window's plane; we
   measure the gap in metres.
3. **Host-run enemies.** Only the host's game spawns and flies enemies. The client's
   game hides its own AI and copies the host's enemy positions. When the client hits an
   enemy, it tells the host; the host decides, then announces the kill.
   Test: both windows show the same enemies in the same places (both games write
   positions to a log every few seconds and a script compares them); a kill in either
   window shows up in both; wave and round counters match.
4. **With your friend, over the internet.** Our mod connects through Steam's relay (no
   router changes, nobody has to share an IP address), only to the Steam friend you
   pick, so it's private by design. I'll ask before anything goes online. Your friend
   needs their own copy of AC7 and exactly the same mod files (we compare checksums).
   Test: three full Horde rounds together, then a 30-minute session with no crash and no
   drift between the two games.

Likely extra tools: a C++ add-on for UE4SS for the networking part, because Lua scripts
in UE4SS can't talk to the network on their own. That means installing Microsoft's free
C++ compiler (Visual Studio Build Tools, several GB), and possibly linking a GitHub
account to Epic Games to get Unreal's source headers. Both need your OK.

## Step 2: one campaign mission together (ladder rung 3)

Goal: play one real story mission start to finish, both of you, and both get "Mission
Accomplished".

Which mission: a short, mostly air-to-air one, picked after reading its mission script
with the earlier tools (Mission 01 and a few others are already decoded).

New things to sync on top of step 1:

- Mission phases, objectives, score and the timer (the host's game decides, the client
  follows).
- Radio lines: each game plays them itself when the host says so.
- Briefing and cutscenes: each player watches their own; the host waits until both are
  ready.
- Take-off, landing and refuelling parts: probably skipped for player 2 at first.
- Mission success, failure, checkpoint restarts and quitting.

How we test it: two copies on this PC for daily work, then with your friend. Pass
means three clean run-throughs together, kills by either player count, both games end
at the same moment, nothing gets stuck.

## Step 3: the whole campaign (ladder rung 4)

20 story missions plus 3 DLC missions. Many have their own special rules (staying under
radar, giant flying superweapons, swarms of drones, bad weather, boss aircraft).
Each mission is its own small project with its own test run. Progress saves: only the
host's save counts at first; the client's game doesn't save campaign progress.

How we test it: a checklist per mission (start, every phase, end, restart), played on
two copies here and then with your friend. Missions get switched on one at a time as
they pass.

## Can two copies run on this one PC?

- **For our own co-op mod (Route B): no, as it turned out** (step 0 test 2, 17 Oct). Both
  copies reach the title screen, but Steam gives only the first running copy its
  connection; the second has no Steam identity, can't use its save and crashes at the
  first use of Steam networking. A UE4SS script can't change that (workbench.md
  section 6). Development happens in one copy; two-game tests need a second PC.
- **For the game's own online mode (Route A): no.** Its online play runs through your
  Steam account, one Steam account can't be in a match with itself, and Steam runs only
  one account per PC. The tools that get around this (Nucleus Co-op, Goldberg) swap the
  game's Steam file for a fake one, which is too close to getting around copy
  protection, so we won't use them.
- **The real tests with your friend always need two PCs and two Steam accounts that each
  own the game.**

## Biggest unknowns

1. **Smooth puppets at jet speed.** Planes move about 300 m every second. Guessing ahead
   between updates has to be good enough that missiles lock on and hit what you see.
2. **Control over AI planes at run time.** Horde Mode spawns planes through mission
   scripts, which is promising. We still need to stop the client's own AI and move its
   enemies from the host's data without the game fighting back.
3. **Working without the exe's code.** We can see the game's reflection catalogue, not
   its native code (Steam keeps that scrambled on disk, and we won't unscramble it). If
   something we need isn't in the catalogue, we may have to find another way round or
   drop that feature.
4. **The copy starting on its own**, and saves being shared with your real game.
5. **Two copies on one PC.** If that fails, every network test needs your friend.
6. **The C++ build tools.** Setting up UE4SS's C++ mod kit can be fiddly.
7. **The AC7 build of UE4SS** may have bugs on this exact game build.
8. Route A only: whether the game's online layer can carry AI planes at all, and whether
   its cheat checks kick a modded player.

## Honest view

- **Co-op skirmish (step 1): realistic, but not easy.** I'd expect many sessions, likely
  a few weeks of evenings, and there's a real chance of hitting a wall at the
  enemy-sync stage. Your earlier Horde Mode work is a genuine head start.
- **One campaign mission (step 2): plausible if step 1 works.** The new work is mission
  logic, which the earlier tools can already read.
- **Full campaign (step 3): a long shot.** Comparable projects by experienced modders
  took months: Lies of P co-op went from boss fights in December 2025 to the full
  campaign in June 2026, and BioShock Together is still an alpha. Expect missions to
  arrive one at a time over months, and some may never work well.
- Each step gives you something playable, so stopping after step 1 or 2 still leaves a
  working co-op mode.
- If the main goal is flying with your friend against AI soon, **Ace Combat 8's Co-Op
  Assault already does that** (it's installed on this PC). It doesn't have a co-op
  campaign, though, which keeps this project worth trying.

## Things I'll ask you before doing

- Making the 65.7 GB copy (and where it goes). (Done 17 Oct.)
- Downloading PM-UE4SS (and later any other tool), with checksums checked. (Done 17 Oct.)
- Installing the C++ compiler, or linking any account. **Changed 18 Oct:** the free
  developer tools for a C++ UE4SS add-on may be installed without asking, from official
  pages, with sizes and checksums recorded (README, "Addendum"). Linking an account
  (for example GitHub to Epic for Unreal's source) still needs your OK.
- Anything that goes online, every time.
- Posting anything, including Co-op Anything's "claim a game" issue (draft in
  `drafts/claim-issue.md`).

**Addendum, 18 Oct 2026.** "Working without the exe's code" (unknown 3 above) is no
longer a hard limit: sessions may read the running game's code in memory for
analysis. A complete unscrambled exe on disk, sharing it, and changing the game's own
checks stay off limits. Full text in the README.
