# Workbench (step 0): what was set up and what the tests showed

Done 17 Oct 2026, 20:50 to 22:15, with you watching the game windows. Updated the same
evening, 22:20 to 22:50: the copy now has **its own save folder** (section 4 below).
Updated again 23:30 to 23:55: whether a UE4SS script can get the second copy past the
title screen (section 6: it can't, and the crash dumps say why).

## Short version

| Test | Result |
|---|---|
| Copy of the game made and checked | **Yes.** `C:\AC7-Coop-Game`, 133 files, 65.7 GB. `Ace7Game.exe`'s SHA-256 matches [identity.md](identity.md) exactly. |
| 1. Does the copy start from its own folder? | **Yes, but only when started the way Steam starts games.** Started plainly, it hands itself to Steam and Steam starts your *real* install. With Steam's app label set for that one launch, the copy itself runs and reaches the main menu. |
| 2. Can two copies run at once? | **Not yet.** Both start and reach the title screen, but the second one crashes when it tries to create save data. Retried at 23:07 with each copy in its own save folder: same crash, same place in the game's code. The cause is that a second copy gets no Steam identity, not the shared folder. |
| 3. Does UE4SS load, open its console and write the object dump? | **Yes, all three.** It found Unreal Engine 4.18 within a second; the console opened; the dump (the game's catalogue of classes and functions) is 30.9 MB. |
| 4. Can the copy keep its saves and settings away from your real ones? | **Yes, proved.** Started with `tools\start-copy.ps1`, the copy reads and writes `C:\AC7-Coop-Game\UserProfile\...` only. Two title-screen runs and then a full run with you (a mission, then "save and end" through the menu) wrote the save and settings there and nothing in your real folder, checked by checksums every time. |
| 6. Can a UE4SS script get the second copy past the title screen? | **No.** Both crash dumps show the second copy never gets a working link to Steam (its table of Steam connections is empty), and it dies the first time it tries to use Steam's networking, which happens right after the save step. The save step is not the cause, a script can't fill that table, and the game's developer save switches are empty leftovers in this build. Details in section 6. |

## What's where

| Thing | Where |
|---|---|
| The plain game copy (no mods, no Mod Loader) | `C:\AC7-Coop-Game` |
| **The copy's own saves and settings** | `C:\AC7-Coop-Game\UserProfile\AppData\Local\BANDAI NAMCO Entertainment\ACE COMBAT 7\` (a second copy uses `UserProfile2`) |
| UE4SS (PM-UE4SS-ZR1903), in the copy only | `C:\AC7-Coop-Game\dwmapi.dll` and `C:\AC7-Coop-Game\ue4ss\` |
| The download, kept as it came | `downloads\PM-UE4SS-ZR1903\` (zip, SHA-256 `8a9574f8c0ddd79b709213547f4ac4d927c14cf0d02be2c503ac9885aa096f13`, same as GitHub shows) |
| Save backups, one per test run | `backups\<date_time>\` |
| The earlier Mod Loader and mission-script tools | `inherited\` (see [inherited/LEFT-OUT.md](inherited/LEFT-OUT.md)) |
| Object dump and UE4SS log from the test | `dumps\2026-10-17_ue4ss-title-screen\` |
| The second copy's crash dump | `dumps\2026-10-17_second-copy-crash\` |
| The crash dump from UE4SS crashing as the copy closed after the mission run | `dumps\2026-10-17_mission-run-exit-crash\` |
| The second copy's crash dump from the retry (23:14) | `dumps\2026-10-17_second-copy-crash-retry\` |
| Back up saves | `tools\backup-saves.ps1` |
| Start the copy (backs up saves first, gives the copy its own save folder) | `tools\start-copy.ps1` |
| Check your real save folder against the latest backup | `tools\compare-saves.ps1` |
| Press keys in the copy and take pictures of its window (so a session can drive the menus) | `tools\game-input.ps1` |
| Read a crash dump of the game: where it died, which game function that is near | `tools\read-crash-dump.py` and `tools\read-crash-dump-details.py` (section 6) |
| The UE4SS script for the second copy (watches save/load calls, tries the developer save switches) | `C:\AC7-Coop-Game\ue4ss\Mods\CoopSecondCopyMod\`, copy in `mods\CoopSecondCopyMod\` |
| That script's own log from the second copy | `C:\AC7-Coop-Game\UserProfile2\coop-second-copy.log` |

To start the copy yourself: open Steam, then in PowerShell run

```
powershell -NoProfile -File "C:\Users\Matth\Claude Apps\AC7-Coop\tools\start-copy.ps1"
```

After a run, to make sure your real saves are untouched:

```
powershell -NoProfile -File "C:\Users\Matth\Claude Apps\AC7-Coop\tools\compare-saves.ps1"
```

## The copy

- Copied with `~mods` and `ModLoader` left out. Your real install wasn't changed.
- All 133 files arrived with the right names and sizes, and `Ace7Game.exe` matches the
  recorded checksum. (I checksummed the exe only, not all 65 GB; the copy tool reported
  no errors.)
- Drive C: went from 316.6 GB to 255.4 GB free.

## Test 1: does the copy start from its own folder?

- **Started plainly** (like double-clicking `Ace7Game.exe`), the copy doesn't run. It asks
  Steam to "run game 502500", and Steam then starts the game from your real install. Steam
  showed a box asking to allow the launch options; it was allowed, so your real game (with
  your mods) ran for 33 seconds at 21:37. Nothing in your save or settings folder changed
  that time.
- **Started with Steam's label.** When Steam starts a game it tells it "you are app 502500".
  Giving the copy that same label for one launch (`SteamAppId=502500`, no file written)
  made the copy run from `C:\AC7-Coop-Game` itself. Steam listed it as Ace Combat 7, its
  overlay attached, and it reached the main menu. Steam still has to be running and still
  checks you own the game; the copy protection runs as normal. `tools\start-copy.ps1`
  does this.
- The game ignores the usual "start in a window" options. Windowed mode had to be set in
  the game's Options, and that setting is shared with your real game (see "Left as you
  chose" below). The copy now has its own copy of that setting (section 4).

## Test 2: can two copies run at once?

- The second copy started fine while the first sat at the main menu. Both used about 1 GB
  of memory and Steam accepted both (Steam's own log shows it tracking both processes
  under the game's app number).
- When you pressed Enter on the second one's title screen, it said it was creating save
  data, wrote a **new** save file in the wrong place (`SaveGames\ACE7Save.sav`, outside
  your Steam-ID folder), and two seconds later crashed (a memory error inside the game,
  22:02:23). Steam's overlay also kept restarting for it.
- Likely reason: Steam gives your account to the first copy only, so the second one
  doesn't know who you are and thinks it has no save. Both copies also shared one save
  folder.
- **Retried at 23:07 to 23:15, with you at the keyboard, each copy in its own save
  folder** (section 4). Both reached the title screen again. The second copy (the smaller
  window) had a copy of your save in both places it might look. Pressing Enter gave "an
  error occurred when trying to load data, try again?", and "no" just went back to the
  title screen; the game never offered to make new save data while a file was there. With
  the file in the no-identity place set aside (renamed), the next Enter went the old way:
  it wrote a brand-new save there (`UserProfile2\...\SaveGames\ACE7Save.sav`, 234,893
  bytes, 23:14:35) and crashed one second later **at exactly the same place in the game's
  code as on the first try** (Windows logged the same fault address). The first copy sat
  at its title screen the whole time and was ended afterwards. Your real folder: unchanged
  (checksums equal to `backups\2026-10-17_2307`); Steam Cloud uploaded nothing.
- **What it means:** the shared save folder was *not* the cause. A second copy of the
  game on one PC doesn't get your Steam identity (Steam hands your account to the first
  copy), so it can't read your save (the save is tied to your identity), writes its own in
  the no-identity place, and then crashes in some step that needs the identity. Two copies
  on this PC still aren't usable past the title screen.
- **Ideas for later, in order** (all three looked at the same night, section 6):
  (1) a UE4SS script in the second copy that skips loading or creating save data
  altogether, since the crash comes right after the save step (can't be done, and
  wouldn't help: the crash isn't in the save step); (2) look at what the two crash dumps
  have in common (done: same cause, an empty Steam connection table); (3) if neither
  works, network tests need your friend's PC, and solo tests can use the game's leftover
  developer commands for a fake session (`SNL_EnableDebugFakeSession`, the network
  emulator) inside one copy (those commands turn out to be empty in this build).
- Small wrinkle for two-copy tests: both copies share the copy's `ue4ss\` folder, so
  they write the same UE4SS log file and load the same UE4SS mods.

## Test 3: UE4SS

- Loaded on every start: UE4SS 3.0.1 beta, the build made for older Unreal versions.
  Steam's wrapper keeps the game's code scrambled for the first second; UE4SS kept looking
  (13 tries) until it was unscrambled by Steam, then found everything it needs, including
  Unreal Engine 4.18.
- Its console window opened on top of the game. (I changed one setting in the copy's
  `ue4ss\UE4SS-settings.ini`, `GuiConsoleVisible = 1`, so it shows on start.)
- Pressing "Dump Objects & Properties" wrote `ue4ss\UE4SS_ObjectDump.txt` in about a
  second: 159,661 lines, 2,377 built-in classes and 6,033 functions. The game's own code
  is listed under the name **Nimbus**. Things we'll need later are in there:
  - the plane classes `PlayerPlane` and `AIPlane`,
  - the mission functions the earlier tools decoded (`StartMissionPhase`, `ActivateUnit`,
    `RestoreUnit`, `GetPlayerPlane`),
  - the leftover developer commands for the online layer as callable functions, for
    example `SNL_ArrangeWindows`, `SNL_EnablePlaneSync`, `SNL_EnableDebugFakeSession`,
    `SNL_ForceCompleteMission`, `SNL_InitializeNetworkEmulator`.
- Small things: four of UE4SS's hooks report "failed". They're the two the settings file
  switches off (`HookInitGameState = 0`, `HookEndPlay = 0`), so that's expected. UE4SS also
  made two empty folders in the copy (`Game\Content\Paks\LogicMods` and `~LogicMods`).
- The dump was taken at the title screen. A dump inside a mission will list more (mission
  scripts load with the mission).

## 4. The copy's own save folder (22:20 to 22:50)

**The problem.** The game asks Windows "where is this user's Local AppData folder?" and
keeps its saves and settings there, in `BANDAI NAMCO Entertainment\ACE COMBAT 7`. The copy
asked the same question and got the same answer as your real game, so both used one folder.

**What I looked at first.** The game's program still contains Unreal Engine's own
switches for moving that folder (`-UserDir=`, `-saveddirsuffix=`, `SaveToUserDir`), right
next to the game's own folder name. So the cheapest idea, a command-line switch, looked
possible. The game's catalogue (the UE4SS dump) also lists its save classes
(`NimbusSaveGame`, `SigmaSaveGame`, `MissionSaveGame`) and the Unreal save functions
(`SaveGameToSlot` and friends), so a UE4SS script could in principle have changed the
save's name on its way to disk. That would have been fiddly and would only have covered
saves, not settings.

**What works.** Windows lets each program be told separately where its user folders are:
a program started with a different "user profile" setting in its environment gets
different answers, and nothing else on the PC is affected. I checked this on your PC with
a small PowerShell test first (the answer followed the setting). `tools\start-copy.ps1`
now does exactly that for the game process it starts, pointing it at
`C:\AC7-Coop-Game\UserProfile`. The game then uses

```
C:\AC7-Coop-Game\UserProfile\AppData\Local\BANDAI NAMCO Entertainment\ACE COMBAT 7\
```

for everything: settings (`Config`), saves (`SaveGames\<your Steam ID>`), and even
Unreal's small `UnrealEngine\4.18` bookkeeping folder landed next to it. No Windows
setting, Steam setting, registry entry or file outside `C:\AC7-Coop-Game` was changed.
The setting is only given to that one game process, and the script puts the PowerShell
window's own settings back right after starting the game.

**First launch copies your settings and save in.** The first time, the script made the
folder and copied your current settings files and your save file (the 10 October save,
696,701 bytes) into it, reading your real files only. So the copy starts in windowed
mode like your real game and has your campaign progress. From then on the two sets of
files live separate lives: nothing the copy does can reach your real save, and your real
game never sees the copy's. Add `-NoSeed` to make an empty folder instead.

**Tested, 22:33 and 22:36, title screen only, you not needed:**

- Run 1 (own folder): within four seconds of starting, the game wrote all ten settings
  files into the copy's folder and nothing into yours. After 90 seconds at the title
  screen the process was ended. `compare-saves.ps1`: your real folder, all 13 files,
  same SHA-256 as the backup taken just before (`backups\2026-10-17_2233`).
- Run 2 (own folder plus Unreal's `-UserDir=UserData` switch): the game **ignored the
  switch** (no `UserData` folder appeared anywhere) and used the copy's folder again.
  Real folder unchanged (`backups\2026-10-17_2236`). So this game doesn't honour Unreal's
  standard command-line switches, which also explains why `-windowed` did nothing
  earlier. The `-saveddirsuffix=` switch wasn't tried: at best it would make a side folder
  inside or next to your real one.
- The copy's rewritten settings file is identical to yours, so it read its own copy and
  wrote it back as the game does on every start.

**Proved with you at the keyboard, 22:54 to 23:02.** You pressed Enter at the title,
flew a mission and quit through the menu. The copy wrote its save at 23:02:46 into its
own folder (`UserProfile\...\SaveGames\76561198126172633\ACE7Save.sav`, now 685,197
bytes, the size the game always writes at "save and end") and rewrote its settings
files there. Your real folder: all 13 files identical to the backup taken just before
(`backups\2026-10-17_2254`), nothing written there during the run, and Steam Cloud
reported "un-modified file", so it uploaded nothing. **The copy can no longer touch your
real save.**

One wrinkle from that run: two seconds after saving, while the game was closing, it
crashed, and Windows logged the fault inside `UE4SS.dll`, the modding add-on, not in the
game itself. Your saves were already on disk by then, and the earlier crash of the second
copy was in the game's own code, so this is a different, harmless thing: UE4SS sometimes
trips while a game shuts down. If a "stopped working" box appears when you quit the copy,
that is what it is. The dump is in `dumps\2026-10-17_mission-run-exit-crash\`.

**Steam Cloud, in plain words.** Steam itself, not the game, copies your save to Steam
Cloud. Its log shows it checks one file, your real
`SaveGames\76561198126172633\ACE7Save.sav`, every time anything labelled as Ace Combat 7
closes, including the copy. That is how the copy's menu quit at 22:05 got uploaded. When
the copy closed at 22:34, Steam saw that the real save had changed since its last upload
(because I had put the original back) and uploaded it: **Steam Cloud now holds your
original 10 October save again** (Steam's change number 73). From now on the copy never
changes the real file, so Steam finds nothing to upload after a copy run.

## 5. Claude can drive the copy's menus (23:20 to 23:30)

You asked for a way for sessions to "play" the copy without you pressing keys.
`tools\game-input.ps1` does it: it finds the copy's game window, brings it to the front,
presses keys in it (Enter, the arrows, Escape, letters and so on, each held briefly like
a real press) and takes a picture of the game window so the session can read the menu
before the next press. Tested end to end with you away from the keyboard: it pressed
Enter at the title, read the main menu from a picture (Campaign, Multiplayer, Data
Viewer, Steam Store, Options, Credits, Copyright, Quit Game), moved down to Quit Game,
answered "Yes" to "Are you sure you want to end the game?", and the copy saved into its
own folder and closed. Your real folder was unchanged (checksums equal to
`backups\2026-10-17_2323`).

- Keys only go to the copy's window (a window titled "ACE COMBAT" belonging to an
  `Ace7Game` process). With two copies running it uses the one started first unless
  told which (`-ProcessId`).
- Pictures are of the game window only, saved where the session asks; they are not
  sent anywhere unless a session chooses to show you one.
- The main menu's Quit Game asks "Are you sure?" with No selected, so quitting is
  Down ×7, Enter, Left, Enter. Loading the save after Enter at the title takes a few
  seconds; `-WaitMs` waits before the picture.
- UE4SS still tends to crash as the game closes after it has saved (section 4). The
  save is already on disk by then.

**Standing permission (your words, 17 Oct 2026):** sessions may start the copy, press
Enter at the title, use the menus and quit from the main menu themselves, without asking
you each time. Later the same night you widened it: "You always have my go-ahead to pass
the title screen or do anything else you want in the game windows." So anything inside
the copies' game windows, including the second copy, is fine without asking. Going
online, touching the real install, installing, downloading or posting still need your OK.

## 6. Can a UE4SS script get the second copy past the title screen? (23:30 to 23:55)

**Short answer: no.** The second copy's problem sits below anything a UE4SS script can
reach, and the two crash dumps show exactly what it is.

**What the crash dumps say.** I read both dumps (`dumps\2026-10-17_second-copy-crash`
and `...-retry`) with a small Python tool written for it (`tools\read-crash-dump.py`).
They tell the same story, byte for byte:

- The game died reading from memory address zero (a "null pointer": it followed a link
  that pointed nowhere). This happened on a small helper thread, not on the main game
  thread.
- The instruction before the fault had just asked Steam's library for the game's table
  of Steam connections (the `SteamInternal_ContextInit` call in `steam_api64.dll`: one
  slot each for Steam's user, friends, stats, networking and so on). In the second copy
  **that table is completely empty**, every slot zero, in both dumps. The code took one
  slot (the one for Steam's networking) and tried to use it, and that is the crash.
- So the second copy never got a working link to Steam at all. The "save in the
  no-identity place" is a symptom of the same thing (without the link, the game doesn't
  know your Steam ID), and the save step merely comes right before the first use of
  Steam's networking. The save step is not the cause.
- Steam's own logs agree: the first copy was logged as "Game process added", the second
  only as "updated" (Steam saw it as another window of the game already running), and
  after Enter the Steam overlay tried to attach to the second copy every six seconds and
  gave up each time.

**Why a script can't fix it.**

- UE4SS scripts work with the game's Unreal objects and functions. The empty Steam table
  lives below that, in the game's own code and Steam's library. A script can't fill it,
  and it can't stop a helper thread the game starts itself.
- UE4SS can watch a built-in game function and even change what it reports back, but it
  can't stop the function from running. So "skip the save or load step" isn't on offer,
  and it wouldn't help anyway, because the crash isn't in that step.
- The developer save switches (`ToggleSaveLoadSimulatedMode`, `ToggleSaveLoadUIIgnore`,
  `SetSaveLoadSimulatedStatus`) exist only as names. In this build, 215 of the 494
  cheat-manager commands point at one and the same piece of code, 69 at another, 35 at a
  third and 32 at a fourth, grouped purely by what kind of value they take (nothing, a
  whole number, a decimal, a yes/no). That only happens when the commands' insides were
  removed for release and the empty leftovers were folded together. This covers the
  `SNL_` commands the plan hoped to use for solo tests (`SNL_ArrangeWindows`,
  `SNL_EnableDebugFakeSession`, `SNL_EnablePlaneSync`, `SNL_InitializeNetworkEmulator`):
  calling them does nothing. (Step 0's last test in plan.md is answered by this.)

**What was built and tested anyway, title screen only, 23:47 to 23:52, you not needed.**

- `ue4ss\Mods\CoopSecondCopyMod` (copy kept in `mods\`). Both copies load the same
  mods, so the script first looks at the user folder it was started with. In the first
  copy (or your real profile) it writes one line and does nothing. In the second copy
  (`UserProfile2`) it writes down every call to the game's twelve save and load functions
  (name, time, values) in `UserProfile2\coop-second-copy.log`, and a few seconds after
  the title screen is up it calls the three developer save switches. It never touches a
  save file itself.
- Run: first copy started 23:47:11 and sat at its title screen throughout; second copy
  started 23:48:27, restarted 23:50:38 after a small fix, title screen both times. The
  script stayed inactive in the first copy and armed itself in the second: all twelve
  functions hooked, the game's cheat manager found at the title screen, the three
  switches called without error (no visible effect, as expected from the above). Both
  copies were ended at the title screen at 23:52. Your real folder: unchanged against
  the three backups of the run (`2026-10-17_2347`, `_2348`, `_2350`).
- **Enter pressed in the second copy, with your go-ahead, 23:58.** Both copies were
  started again (23:55:59 and 23:56:55, title screens, script armed in the second, the
  three switches called at 23:57:05). Enter in the second copy at about 23:58:25: the
  title screen faded out normally (picture at four seconds: no "creating save data"
  message, no error box), and about ten seconds after Enter the copy was gone. Windows
  wrote a third crash dump (23:58:35, kept in `dumps\2026-10-17_second-copy-crash-with-
  script\`), and it is the same crash to the byte: same place in the game's code, same
  empty Steam table, same helper thread. Two things the script's log adds: **none of
  the twelve save and load functions it watched was called at all** (the game loads and
  saves through code that isn't reachable from a script), and no save file was written
  this time (the second copy quietly accepted the no-identity save it had made at
  23:14 and moved on, until the Steam step). The three developer switches changed
  nothing, as expected. First copy sat at its title screen throughout and was ended
  afterwards. Your real folder: unchanged (`backups\2026-10-17_2355` and `_2356`).

**What it means.** Two copies on one PC stop at the title screen, and no UE4SS script
changes that: the thing that's missing (a working Steam link in the second copy) is
below the level a script can touch, the crash is not in the save step, and the save
step itself doesn't even pass through anything a script can see. Network tests need
your friend's PC (or one copy here and one there). Everything else in the plan (one
copy with UE4SS, your own save folder, driving the menus from a session) still stands.

**The crash-dump tools.** `tools\read-crash-dump.py <dump> [objectdump] [exe base]`
prints where the game died, the registers, and the return addresses on the crashing
thread's stack, naming the nearest game function known from the UE4SS object dump (the
exe base address for that dump is in the UE4SS log, the `MainExe @ ...` line; it was
`7ff68a450000` for the dump in `dumps\2026-10-17_ue4ss-title-screen`).
`tools\read-crash-dump-details.py <dump>` adds the thread list, the Steam library
function called just before the fault, and the contents of the table it returned. Both
only read files; nothing is run.

## 7. The flight lab: a session flies a mission, records the plane, and drives a puppet plane (18 Oct, 00:15 to 00:50)

You asked for work that could go on while you were away. With your go-ahead for
anything in the game windows, one copy was started and driven from the title screen into
a mission (SP Mission 01, "Unexpected Visitor", Casual), and the first real co-op
building block was tried: **another plane made to fly exactly where a recording says**.
That is the heart of the plan, because in co-op your friend's plane would be shown in
your game the same way, from positions arriving over the network instead of from a file.

**What was built.** A second UE4SS script, `CoopFlightLabMod` (copy kept in `mods\`),
which is active in whichever copy loads it and never touches save files. It is driven
by keys, so a session can use it through `tools\game-input.ps1` without you:

| Key | What it does |
|---|---|
| F7 | Start or stop recording your plane: position, pitch/heading/roll and speed, about 40 times a second, to `UserProfile\flight-<date>.csv` |
| F4 | Start or stop the puppet: takes the nearest active AI plane, switches its own AI off, makes it invincible, and every frame puts it where the newest recording says, shifted so it starts ahead and to the right of your plane |
| F5 / F6 | One-off test: move the nearest AI plane next to your plane (F5 also switches its AI off first) |
| F8 | A status line in the UE4SS log: map, your plane, the twelve nearest AI planes (distance, active or not, callsign) |
| F9 | Write the UE4SS object dump (the game's catalogue of classes and functions) |

`tools\game-input.ps1` can now press key combinations such as `Ctrl+P` (UE4SS reloads
all scripts) and `Ctrl+J` (UE4SS object dump). Scripts can be edited while the game runs
and reloaded with Ctrl+P, which is how the lab was built in one sitting.

**Getting into a mission from a session.** Enter at the title; Campaign; the submenu
opens on Continue, so two Downs land on SP Mission; Casual; Enter on a mission; the
intro movie and the briefing are skipped one section at a time with Escape, Escape (the
first Escape shows SKIP, the second skips that section; it took about nine pairs); F1 on
the operation map goes to Mission Prep; Enter on Start Mission, Enter on the aircraft,
Enter on the special weapon, Enter on Sortie; about 45 seconds of loading. With no
hands on the controls the plane flies straight and leaves the combat area after two to
three minutes, which ends the mission; "Retry from checkpoint" puts it back in 25 s.

**What the in-mission object dump adds** (`dumps\2026-10-18_ue4ss-in-mission-ex01`,
175,745 lines against 159,661 at the title screen): the player's plane is a
`PlayerPlane` (here `AcePlayerPawn_typn_s03_C`, the Typhoon), the other planes are
`AIPlane` objects (150 in this mission, most of them parked until the mission activates
them), every plane descends from the game's `GameObject`, which has `bIsActivated`,
health, speed in km/h, callsign and `SetIsInvincible`, and planes belong to a `Unit`
that carries the side (`Faction`). AI planes offer `SetBehaviorActive(false)` to switch
their AI off, and the standard Unreal `K2_TeleportTo(position, rotation)` moves them.
The `SetFELocationAndRotation` functions looked promising but do nothing visible (FE is
most likely the plane's slot in a formation, not its flight engine).

**What the recorder showed.** 898 samples in 47 s on the first try (about 19 per
second), later about 40 per second. The Typhoon flew a dead-straight line at about
1,640 game units per second while the HUD showed 600 km/h, so one game unit is about
10 cm here if the HUD speed is true. Recordings are kept in
`dumps\2026-10-18_flight-recordings\`.

**What the puppet showed** (three runs, 00:38 to 00:45):

- A Lua table like `{X=…, Y=…, Z=…}` is accepted wherever the game wants a position or
  a rotation, so no special types are needed.
- With its AI switched off, an AI plane goes where it is put and stays put. The
  wingman "Count" (an F-15C) and, on one run, an enemy F-15E were used.
- Updated every 50 ms, the plane drifted about 95 units between updates; updated every
  frame (about 40 times a second), about 45 units. That drift is simply the plane's own
  flight engine carrying it forward at its own speed (650 km/h) between updates, in the
  right direction: after the first big move, each update only had to correct it by
  about 3 to 4 units, roughly 30 to 40 cm. In other words the puppet flies the path on
  its own and the script merely trims it, which is exactly what a network feed needs.
- Over the whole 32-second replay the puppet held its place to the unit: 2,500 units
  ahead, 800 to the right, 1 above your plane, at the end as at the start.
- Pictures: `pictures\2026-10-18_puppet-plane-6s.png` and `...-15s.png` show "Strider 2
  Count" sitting ahead-right of your plane, driven by the recording. (Both copies are
  there in full size and as small JPEGs.)

**Not tried yet:** whether missiles lock onto the puppet and whether it can be shot
(it was made invincible for the test), what it looks like in motion (pictures can't
show jitter; a short video next time), rotation smoothness in turns (the recording was
a straight line), and taking over a plane the mission has not activated yet (all tests
used already-active planes). The game's own save was written to the copy's folder when
the mission was quit; your real folder was checked afterwards, see below.

## Your saves: what happened

- Before every launch your save folder was backed up and checked (`backups\`, eight
  backups today).
- **The copy used to share your real save folder.** When I quit the copy through its menu
  ("Save and end your current game", 22:05), it rewrote your real save, and Steam Cloud
  uploaded it. The save is encrypted, so I couldn't see what changed; it was 11.5 KB
  smaller. With your OK I put the original back (the 10 Oct file, checksum matches this
  morning's backup). Steam Cloud got the original back at 22:34 (see above). The
  copy-written version is kept in `backups\2026-10-17_2206\`.
- Staying on the title screen and closing from there didn't touch the save. The game
  ignores the window's X and Escape at the title screen, so I ended the process instead.
  Nothing is loaded at that point.
- Since 22:33 the copy has its own save folder (section 4), so this can't happen again
  as long as the copy is started with `tools\start-copy.ps1`.

## Left as you chose

- **Windowed mode** is still on (1600×900 windowed instead of 1920×1080 full screen), so
  your real game will also open in a window. To undo it, set full screen in the game's
  Options, or ask me to copy `Config\GameUserSettings.ini` back from
  `backups\2026-10-17_2133\`. The copy has its own copy of this setting now, so changing
  one no longer changes the other.
- `Config\Engine.ini` has a block the game added that turns off the Sticky Keys shortcut.
  Harmless; the original is in the same backup.
- The stray save the crashed second copy made (`SaveGames\ACE7Save.sav`, not in your
  Steam-ID folder, not synced by Steam Cloud) is still there.

## Rules for test runs from now on

1. Steam open, then start the copy with `tools\start-copy.ps1` (it backs up your saves
   first and gives the copy its own save folder). Never start `Ace7Game.exe` in the copy
   any other way, and never with `-SharedUserFolder` unless the test is about the real
   folder and stays on the title screen.
2. Going past the title screen in the copy is now safe: the copy saves only to its own
   folder. `tools\compare-saves.ps1` is there whenever you want to check ("No change").
   Sessions may press Enter at the title, use the menus and quit from the main menu
   themselves with `tools\game-input.ps1` (section 5); they don't need to ask you for
   that.
3. A second copy is started with `-Second` and gets its own folder (`UserProfile2`) and a
   smaller window. It still crashes when it gets past the title screen (no working link
   to Steam, section 6), so a second copy is only good for title-screen tests.

## Must-do before step 1

- **Own save folder for the copy: done and proved** (section 4).
- **Two copies at once:** can't be made to work with a script (section 6): the second
  copy never gets a working link to Steam and dies on its first use of Steam networking.
  Network tests need a second PC.
- plan.md's step 0 test 4 (developer commands offline, such as `SNL_ArrangeWindows`):
  answered without a run. The commands are empty leftovers in this build (section 6).
