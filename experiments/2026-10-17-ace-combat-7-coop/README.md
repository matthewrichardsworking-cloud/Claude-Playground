# Ace Combat 7 co-op: project folder

Goal: you and a friend fly Ace Combat 7 together against computer-controlled enemies,
ideally through the story campaign.

**Status (19 Oct 2026, 19:20): faster kill chaining; Mission 06 still not cleared.** Following
the plan you agreed that morning, with your rule first (the bot is a test tool, so everything is
read live from the game, nothing written for one level), the bot now attacks ground targets the
way a player sweeps through them: it chooses its flight path for the targets that path brings
into the missile's lock cone and fires at whatever is there, picking the next target right after
each launch (a "lane planner", tuned in a new simulator on many invented layouts). Watching, you
asked for more aggression: it now turns as tight as it can with the high-G turn, accelerates
toward groups, keeps attacking while dodging missiles (a "defensive attack"), and weighs
anything that shoots at it as a priority. It kills almost twice as fast as in the morning while
engaged (best: 6.4 kills a minute over a phase, 7.3 while engaged), but whole phases still end
at 13,000-13,400 points or with the plane shot down (four F-16s near the start, and the
anti-aircraft sites' steady damage). So the campaign remains stopped at Mission 06; the next
steps are in workbench section 16 and `playtests\missions\m06\notes.md`. Every report now has
general numbers (where the time went, kill rates, hits by weapon and range, what the mission
switched on), the kind a modder needs. The copy is closed; your real saves are unchanged.

**Earlier (19 Oct 2026, 14:05): the Ace campaign stopped at Mission 06 Long Day; your tunnel test passed.** Missions
01 to 05 are completed on Ace. Mission 06's first phase is a score race: 24,000 points in 15
minutes (the HUD shows it; the radio only says "not enough damage to the base"), which means
destroying nearly everything in the mission's three areas. Over about 6 hours and 25 attempts
the bot went from about 7,800 to about 14,000 points: it now weighs targets by points per
second, sweeps through ground clusters shooting whatever comes into its cone, keeps to the
combat zone, flies full throttle in score phases (your advice), and carries campaign parts in
the slots that your multiplayer parts were occupying (cleared through the copy's own Mod
Loader, as you suggested; your real install was only read). Other planes were surveyed; the
F-22A with XSDB was worse here (no LAAM for the bombers). **Your tunnel test passes** (a later
round the same day, at your request for more cycles): the bot flies into Mission 06's tunnel 1.6 m
from the aim point, through the whole 1.3 km bore on its live rays alone, and out, with one small
scrape at the last bend. Details: workbench section 15, `playtests\missions\m06\notes.md`. The copy
is closed and back in Vanilla mode; your real saves are unchanged.

**Earlier (19 Oct 2026, 01:35): the Ace campaign is under way, and the lock problem is
solved.** On your OK the bot is flying the story campaign on Ace in the copy (the copy's own
story save was restarted; your real game is untouched). First the problem that stopped
Mission 14: the bot picked its targets by writing straight into the game's "selected target"
field, which skipped the step where the game hands the target to a missile's lock. It now
selects the way the Tab key does, and in Mission 14 on Hard every target that never locked
last night locked and fell (workbench section 15). A new campaign driver
(`tools\campaign.py`) takes the story from the menu through movies, briefings, the hangar
(plane and special weapon by name), the mission, the replay and the results to the next
mission. **Completed on Ace so far: Missions 01 (rank A, no damage), 02, 03 and 04 Rescue.**
Mission 04 was the hard one: a 128 km stealth flight between 79 radar zones (the bot planned
a route around them and flew it unseen), your first vision test (a surprise flight through
the Space Elevator's base, rays only: 13 m from the aim point, no contact), then drone swarms
and an escort that taught it several new tactics. Progress per mission:
`playtests\campaign-ace.md`; details in workbench section 15.

**Earlier (19 Oct 2026, 00:20): the playtest bot sees terrain and mission gimmicks.** On
your request it learned to fly Mission 14's 47 km night canyon on Hard by itself: under the
550 m limit the game really sets (the radio says 600), past about 70 sweeping searchlights
whose beams it predicts and dodges four times a second, using the game's own line traces
through the C++ add-on (1.4 microseconds a ray). It clears the canyon at the first try in 4 of
6 starts. In the base attack after it, your two ideas are in (go for what threatens the
landing party first; one missile per target when one is enough, then the next target at
once), and the landing team now lands in about half the attempts. The mission is not
completed yet: the enemy reinforcements that arrive after the landing, and some SAM sites,
never lock, although the game lists them as normal targets; what was ruled out is in
workbench section 14. Mission 03 was not flown on its own: it comes up in the campaign.
Next, on your OK of 18 Oct (22:5x): a separate session flies the Ace campaign from the start,
taking that lock problem first. All of it in the copy; Double Trigger is switched off there
(your OK, 20:20), your real install was not touched.

**Earlier (18 Oct 2026, 16:55): Double Trigger is in your real game too.** You lifted the
real-install rule for this one install. After a full backup, the updated Mod Loader
replaced your old one and installed Double Trigger as mod 31 of 31; your other mods were
left byte for byte as they were, and Vanilla mode was tested: it removes everything,
Double Trigger included, and puts every file back identical (workbench section 13). Use
Vanilla mode before the game's own online play. Not launched in the real install yet.

**Earlier (16:50): Double Trigger is installed in the copy and running.**
On your request it was downloaded (checksums match the release, Windows Defender found
nothing), packaged as a Mod Loader mod and installed into the copy with AC7 Mod Loader,
which needed a small addition to place a DLL next to the game's exe (workbench section
12). The copy started with it: every one of the mod's own start-up checks passed, the
main menu's Multiplayer entry is greyed out as intended, and F5 opens its co-op panel.
No lobby has been hosted. Your real install, its mods and its Mod Loader were not
touched, and your real save is unchanged.

**Earlier (18 Oct 2026, evening): layer10_love's co-op mod is out, and it is good.**
"Double Trigger" v0.1.0 (GitHub, MIT, full source, one `dinput8.dll`) does two-player
co-op for Free Missions on the game's own online layer, the route our plan set aside as
hardest. A full reading of its code is in [double-trigger-review.md](double-trigger-review.md):
carefully built, honest about its rough edges, and it should run in our copy.

**Also (18 Oct 2026, 13:45): the playtest bot works.** In the copy it took off, shot down
every enemy plane of Mission 01 (Casual) without taking a hit, and the game declared
"mission accomplished". The test runner then did it alone from a cold start, menus
included, at the first attempt (20 kills, score 12,400, the same as your own best;
[playtest-bot.md](playtest-bot.md), workbench section 10, reports in `playtests\`).
Its second phase the same afternoon (workbench section 11): it now tracks every enemy and
missile, predicts their paths from the game's own data and live readings, times flares
and break turns from that, uses the LAAM at range and flies proper attack runs on ground
targets. Mission 01 on Ace and Mission 02 on Hard both completed; on Mission 02, 8 of 8
enemy missiles fired at it lost their lock. It flies with the keyboard, pressed from inside
the game only while the game window is in front (the game pauses itself otherwise). It can
test Double Trigger's missions alone, too, once that mod is in the copy.

Earlier status (07:45): the network piece exists. A C++ add-on for UE4SS,
built on this PC (`cpp\`, workbench section 9), gives the scripts a network socket:
packets sent by a program on this PC reach a script in the game within 1 to 24 ms, and
the puppet plane from section 7 now flies from those live packets instead of from a
file, trimmed by 1 to 2 units (10 to 20 cm) per frame at 90 frames a second, 100 ms
behind the feed. Compiler and Windows SDK are in `C:\AC7-Coop-Tools` (what, where and
how to remove: `downloads\installed-tools.md`). Earlier status: plan made, the workbench (step 0) set up, and the
first building block of step 1 working: a session flew a mission in the copy, recorded
the player's plane and made an AI plane fly the recording, straight and in turns, with
the game's own flight engine doing the flying and the script only trimming it by a few
centimetres per frame. A plane the mission never activated can be used for this
(workbench section 7, pictures in `pictures\`). Earlier that night: There's a plain
copy of the game at `C:\AC7-Coop-Game` with UE4SS in it. The copy starts from its own
folder, UE4SS works, and since 22:33 the copy keeps its saves and settings in its own
folder (`C:\AC7-Coop-Game\UserProfile`), so it can no longer touch your real save
(proved by a mission run that quit through the menu: your real folder's checksums were
unchanged). Two copies at once still don't work, and a UE4SS script can't change that: the crash
dumps show the second copy never gets a working link to Steam and dies on its first
use of Steam networking, right after the save step (workbench section 6). The game's
leftover developer commands turn out to be empty in this build. Nothing co-op built yet. Your real
install, mods and Mod Loader weren't changed. Your save was rewritten once by the copy
earlier in the evening and has been put back from the backup, in Steam Cloud too
(details in [workbench.md](workbench.md)).

## What's here

| File | What it is |
|---|---|
| [plan.md](plan.md) | The step-by-step plan (workbench, co-op skirmish, one mission, full campaign), how each step gets tested, whether two copies can run on this PC, the biggest unknowns, and an honest view of the odds. |
| [playtest-bot.md](playtest-bot.md) | The test-pilot bot: a Claude session writes a test order (mission, difficulty, attempts, tactics), the bot flies it in the copy until it completes, and hands back a report and flight logs. Built 18 Oct; what works and what doesn't yet is at the top. |
| `playtests\` | The bot's test orders (`orders\`), per-mission plans and data (`missions\m14\`: the plan, terrain survey, canyon route, searchlight sweeps, maps), and one folder per test run with its report, events, flight logs and pictures. |
| [workbench.md](workbench.md) | **Read this next.** What step 0 set up, what each test showed, what happened to your saves, and the rules for test runs. |
| [identity.md](identity.md) | Your exact game build: Steam build 9855922, the exe's SHA-256, Unreal Engine 4.18.2. |
| [research.md](research.md) | What already exists (no co-op mod anywhere), how AC7's online matches work (player-hosted over Steam), the tools we can build on, and what to check by hand on Nexus Mods. |
| [double-trigger-review.md](double-trigger-review.md) | **Read this for the current direction.** A full reading of layer10_love's released co-op mod, Double Trigger v0.1.0 (18 Oct 2026): what it is, how it works, how it compares with our work, whether it will run in the copy (checked), its safety, its code quality, and the next steps. |
| `tools\` | `start-copy.ps1` (starts the copy with its own save folder, backing up your saves first), `backup-saves.ps1`, `compare-saves.ps1` (checks your real save folder against the latest backup), `game-input.ps1` (presses keys in the copy and takes pictures of its window, so a session can drive the menus without you), and `read-crash-dump.py` / `read-crash-dump-details.py` (read a crash dump of the game and say where it died), `read-game-code.py` (reads the running copy's code out of memory and names functions, calls and strings; workbench section 8), `coop-net-sender.py` (plays a recorded flight into the game as network packets, standing in for the other player's PC), `fetch-msvc-portable.py` (fetches Microsoft's compiler into a plain folder without an administrator prompt; section 9), and the playtest bot's `pilot.py` (sends the pilot an order, reads its status and log) and `playtest.py` (the test runner; section 10), plus its map tools from section 14: `terrain-map.py` (draws a terrain survey), `route-plan.py`, `route3d.py` and `route-heights.py` (plan a route through a canyon under a ceiling) and `beam-fans.py` (turns a searchlight recording into each beam's sweep); since section 16 `run-stats.py` (the general numbers of any test run: where the time went, kill rates, hits by weapon and range, what the mission switched on; built into every report) and `lane-sim.py` (the simulator that tunes the lane planner on many invented target layouts). |
| `code\` | Bytes and listings of single functions read from the running copy (never shared), and [snl-map.md](code/snl-map.md), the first map of the game's online layer. |
| `cpp\` | The C++ add-ons for UE4SS and how they are built: [cpp/README.md](cpp/README.md) (which UE4SS the copy runs, how its add-ons work, why the documented build route is closed and what was done instead), `build.ps1`, `CoopNetMod` (the UDP socket for the scripts), `CoopPadMod` (the playtest bot's hands: keyboard presses from inside the game, only while it is in front; section 10; and since section 14 its eyes: the engine's own line traces at 1.4 microseconds each, `trace.cpp`), `CoopPad` (a stand-in gamepad library, built and tried, not used: Steam's overlay keeps it from the game), `HelloMod` (UE4SS's own example, built first as proof), the UE4SS source at the copy's exact version (`RE-UE4SS`). Workbench section 9. |
| `mods\` | Copies of the UE4SS scripts written for the copy. `CoopSecondCopyMod` watches the second copy's save and load calls and tries the game's developer save switches (workbench section 6). `CoopFlightLabMod` records your plane's flight to a file and drives an AI plane along a recording (F4) or along live network packets (F11), the first co-op building blocks (workbench sections 7 and 9). `CoopNetCheckMod` prints the packet count once a second (the title-screen test). `CoopPilotMod` is the playtest bot's pilot: it flies, fights and logs (section 10), tracks enemies and missiles (`awareness.lua`, section 11), and since section 14 reads terrain, follows routes and dodges searchlights (`nav.lua`, `route.lua`, `gimmicks.lua`). Since section 16 it plans its attack runs with `lanes.lua` (the lane planner). `double-trigger-modloader\` holds Double Trigger v0.1.0 packaged for AC7 Mod Loader (section 12). |
| `pictures\` | Screenshots from the copy, for example the puppet plane flying ahead-right of the player (18 Oct). |
| `backups\` | A dated copy of your save and settings folder from before each test run. |
| `inherited\` | The earlier AC7 Mod Loader source, mission-script tools and research, copied out of the Claude app's hidden storage. [What was left out](inherited/LEFT-OUT.md). |
| `downloads\` | PM-UE4SS as downloaded from GitHub, checksum checked; the compiler packages from Microsoft (`msvc-portable\`, with the list of every file and its SHA-256); and [installed-tools.md](downloads/installed-tools.md), what was installed for the C++ add-on, where, how big, and how to remove it. |
| `dumps\` | UE4SS's object dump (the game's list of classes and functions) and a crash dump from the two-copies test. |
| [drafts/claim-issue.md](drafts/claim-issue.md) | Draft of Co-op Anything's "claim a game" issue. Not posted. |
| [drafts/directory-entry.yaml](drafts/directory-entry.yaml) | Draft directory entry for Co-op Anything, checked against its rules. Not sent. |
| `pg\` | A working copy of your Claude-Playground repo, used to update `LOG.md` and the AC7 experiment note. |

## Next step

**A two-player test of Double Trigger** (double-trigger-review.md section 9). It is
installed in the copy and starts cleanly (workbench section 12). What is left needs you:
a Steam friend with the game and the same `dinput8.dll` on their own PC, then Host and
Invite friends in the F5 panel, both pick the same Free Mission and difficulty, both
Sortie. Hosting a lobby is going online, so a session does it only with your OK. If it
holds up, this project turns into testing and helping that mod with exact bug reports. Our own
route stays as the fallback: the flight lab (workbench section 7) can fly a mission, record your plane
and make another plane follow the recording to within centimetres, straight and in
turns, and since section 9 it can do the same from live network packets. The next
pieces on that route would be the feed over a real connection between two PCs (the
add-on currently listens only on this PC), sending your own plane's positions out the
same way, and missiles against the puppet. Two copies on one PC can't get past the
title screen, so any two-player test needs a second PC (workbench section 6).

## Ground rules for this project

- Hands-on work only on the copy, never the real install, mods, mod loader or saves.
- Sessions may start the copy, press Enter at its title screen, use its menus and quit
  from the main menu by themselves (`tools\start-copy.ps1` and `tools\game-input.ps1`),
  without asking first. Your standing permission from 17 Oct 2026, widened the same
  night to anything at all inside the copies' game windows, second copy included.
- Ask before installing, downloading, deleting, changing settings, going online, or
  posting anything.
- Downloads only from official pages, checksums always checked.
- No getting around copy protection or anti-cheat. Private sessions only, never public
  matches.

### Addendum, 18 Oct 2026 (your decision: "allow greater liberties")

Where an older rule in any of these notes says otherwise, this addendum wins:

- **Sessions may read the running game's code in memory** to understand how it works,
  for example the online layer, the save path or a crash site: reading the copy's
  process while it runs, saving the bytes of particular functions for analysis, and
  disassembling them. Still off limits: saving whole code sections or a complete
  unscrambled exe to disk, sharing any of it, and changing the game's own checks.
- **Sessions may build a C++ add-on for UE4SS**, and may install the free developer
  tools that needs (Microsoft's Build Tools, CMake, Git, Python packages, the UE4SS
  source) from their official pages, with sizes and checksums written down in the
  notes. Tell you what was installed and where, so it can be removed.
- **One exception, 18 Oct 2026 16:50 (your words: "I'm lifting the 'never touch the real
  install' rule for this one install"):** Double Trigger was installed into the real game
  with the updated Mod Loader, after a backup (workbench section 13). That was a one-off;
  the rule below still holds for everything else.
- Unchanged: the real install, mods, Mod Loader and saves are never touched; nothing
  goes online except private rooms with people running the same mod, and only with
  your OK; nothing is posted without your OK; test runs still go through
  `tools\start-copy.ps1` and `tools\compare-saves.ps1`.
