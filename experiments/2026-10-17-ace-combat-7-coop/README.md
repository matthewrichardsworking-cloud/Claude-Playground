# Ace Combat 7 co-op: project folder

Goal: you and a friend fly Ace Combat 7 together against computer-controlled enemies,
ideally through the story campaign.

**Status (18 Oct 2026, 01:25):** plan made, the workbench (step 0) set up, and the
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
| [workbench.md](workbench.md) | **Read this next.** What step 0 set up, what each test showed, what happened to your saves, and the rules for test runs. |
| [identity.md](identity.md) | Your exact game build: Steam build 9855922, the exe's SHA-256, Unreal Engine 4.18.2. |
| [research.md](research.md) | What already exists (no co-op mod anywhere), how AC7's online matches work (player-hosted over Steam), the tools we can build on, and what to check by hand on Nexus Mods. |
| `tools\` | `start-copy.ps1` (starts the copy with its own save folder, backing up your saves first), `backup-saves.ps1`, `compare-saves.ps1` (checks your real save folder against the latest backup), `game-input.ps1` (presses keys in the copy and takes pictures of its window, so a session can drive the menus without you), and `read-crash-dump.py` / `read-crash-dump-details.py` (read a crash dump of the game and say where it died), and `read-game-code.py` (reads the running copy's code out of memory and names functions, calls and strings; workbench section 8). |
| `code\` | Bytes and listings of single functions read from the running copy (never shared), and [snl-map.md](code/snl-map.md), the first map of the game's online layer. |
| `mods\` | Copies of the UE4SS scripts written for the copy. `CoopSecondCopyMod` watches the second copy's save and load calls and tries the game's developer save switches (workbench section 6). `CoopFlightLabMod` records your plane's flight to a file and drives an AI plane along a recording, the first co-op building block (workbench section 7). |
| `pictures\` | Screenshots from the copy, for example the puppet plane flying ahead-right of the player (18 Oct). |
| `backups\` | A dated copy of your save and settings folder from before each test run. |
| `inherited\` | The earlier AC7 Mod Loader source, mission-script tools and research, copied out of the Claude app's hidden storage. [What was left out](inherited/LEFT-OUT.md). |
| `downloads\` | PM-UE4SS as downloaded from GitHub, checksum checked. |
| `dumps\` | UE4SS's object dump (the game's list of classes and functions) and a crash dump from the two-copies test. |
| [drafts/claim-issue.md](drafts/claim-issue.md) | Draft of Co-op Anything's "claim a game" issue. Not posted. |
| [drafts/directory-entry.yaml](drafts/directory-entry.yaml) | Draft directory entry for Co-op Anything, checked against its rules. Not sent. |
| `pg\` | A working copy of your Claude-Playground repo, used to update `LOG.md` and the AC7 experiment note. |

## Next step

**Wait for layer10_love's co-op mod, then try it in the copy** (research.md section 5,
and the task card for it). They take the route our plan set aside, the game's own
online layer, and say it is about 95% working with a release due 18 Oct. If it is
stable, this project turns into testing and helping that mod. Our own route stays as
the fallback: the flight lab (workbench section 7) can fly a mission, record your plane
and make another plane follow the recording to within centimetres, straight and in
turns; the next pieces on that route would be missiles against the puppet and the
network feed in place of the file. Two copies on one PC can't get past the title
screen, so any two-player test needs a second PC (workbench section 6).

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
- Unchanged: the real install, mods, Mod Loader and saves are never touched; nothing
  goes online except private rooms with people running the same mod, and only with
  your OK; nothing is posted without your OK; test runs still go through
  `tools\start-copy.ps1` and `tools\compare-saves.ps1`.
