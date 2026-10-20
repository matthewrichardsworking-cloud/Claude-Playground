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
| F4 | Start or stop the puppet: takes the nearest active AI plane, switches its own AI off, makes it invincible, sets its speed to the recording's, and every frame puts it where the newest recording says, shifted so it starts ahead and to the right of your plane |
| F3 | Same, but with the nearest plane the mission has *not* activated yet (switched on first) |
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
used already-active planes).

**Closing the run (00:47 to 00:49).** Quit Mission from the pause menu, back to the main
menu, Quit Game. The copy wrote its own save at 00:48:47 (685,197 bytes, in
`UserProfile\...\SaveGames\<your Steam ID>\`), then the usual UE4SS crash while closing
(same place in `UE4SS.dll` as on 17 Oct, harmless). Your real folder: unchanged
(`backups\2026-10-18_0019`, all 13 files the same SHA-256).

**Round 2 (00:51 to 01:20): three of the open questions answered.**

- **A plane the mission hasn't activated can be used.** Pressing F3 takes the nearest
  *unactivated* AI plane (one parked and waiting for its cue in the mission script),
  switches it on with the game's own `SetActive(true, false)`, and drives it. It worked
  first time on an enemy Rafale and then on an enemy F/A-18F: both appeared ahead-right
  of your plane and flew the recording (picture
  `pictures\2026-10-18_puppet-unactivated-plane.png`). So your friend's plane does not
  have to be one of the mission's own cast.
- **Matching the puppet's speed makes the trimming almost vanish.** The Rafale's own
  engine ran at 1,300 km/h, so each frame it overshot by about 50 units and had to be
  pulled back. Telling the plane the recording's speed (its `OverrideNormalSpeed` and
  `OverrideMaxSpeed` values plus the game's `AutopilotAdjustSpeed`) brought the
  correction down to **0.2 units per frame**, about 2 cm: the game's own flight engine
  then flies the path by itself and the script only nudges it. All replay keys do this
  now.
- **Turns work too.** A 20-second recording with real stick input (roll, a hard pull,
  roll back: heading swung 33 degrees, pitch from -34 to +24, the plane went inverted)
  was replayed through an enemy F-4E. Correction per frame rose to about 6 units (60
  cm), with one worst trim of 79 units during the roll-over; the puppet followed the
  manoeuvre and ended up where the recording said. Picture:
  `pictures\2026-10-18_puppet-turn-10s.png`.
- Flying the plane from a session works with held keys: A/D roll, S pulls up, through
  `game-input.ps1 -HoldMs`. The pull put the plane into enemy fire and it was shot down
  (51% damage, then "mission failed"), which also showed that the game's "mission
  failed" screen leads back to the mission list on Enter, not to a retry.
- Menu lesson: the briefing's SKIP advances one spoken line at a time. About 70 single
  Escape presses 1.3 s apart get through it; paired presses miss half the time.

**Still open:** missiles against a puppet (the HUD does treat an enemy puppet as a
target), what the puppet looks like in motion (needs a short video), and the step that
turns all this into co-op: sending the recording live over the network instead of
reading it from a file.

Round 2 was closed the same way at 01:20 (Quit Mission, Quit Game; the copy's own save
written 01:20:11). Your real folder: unchanged (`backups\2026-10-18_0051`, all 13 files
the same SHA-256).

## 8. Reading the running copy's code: a tool, the crash site named, and a first map of the online layer (18 Oct, 06:40 to 07:15)

With your addendum (README, "Addendum") in force, a session built
`tools\read-game-code.py`: a Python tool that opens the **running** copy with read
rights only, finds where Windows loaded the exe this time (the "base address", different
each boot), and reads the game's code out of memory, where Steam's wrapper has already
unscrambled it. It never writes into the game (there is no write call in the file) and
it refuses any `Ace7Game.exe` that is not the copy's. It only saves the bytes of single
functions (`code\<name>.bin`, with a readable listing next to it in `code\<name>.txt`),
never whole sections, as the addendum requires. The listing is made with the `capstone`
disassembler (installed from PyPI with pip, version 5.0.9; without it the tool still
prints hex). Names come from three places: the UE4SS object dump (the tool works out the
dump's base address by itself and shifts every address to the live one), the game's own
class data (712 class names, which name 2,335 functions by class and position in the
class's function table), and the strings a function uses. Steam calls are named too.

One command line, with the copy at its title screen:

    python tools\read-game-code.py read exe+0x1da3319

prints the function around the crash site of 17 Oct with every call named. Other forms:
`refs SNL_P2P_HOST` (which functions use a string or address), `strings Lobby` (search
the game's text), `class P2PSession` (a class's function table), `name exe+0x...`,
`info`. The copy is started with `tools\start-copy.ps1` as always; Steam was not running
this morning, so the session started it (silently) first.

**What it found** (details and tables in [code\snl-map.md](code/snl-map.md)):

- The crash site is `SNL::PlatformUDPSocket` function 5, "is a Steam P2P packet
  waiting?": it asks Steam for the interface table, takes the networking slot, and
  dies reading the function table of a null pointer, exactly as section 6 said. The
  caller is the socket's receive step on an SNL worker thread. The pointer is null
  because `SteamAPI_Init`, called by Unreal's Steam start-up code (`exe+0x211cbb0`),
  fails in a second process.
- `SNL_P2P_HOST` is a Steam lobby **member-data** key: the session update writes `1`
  into the host's entry, and the members are read to find the host (fallback: Steam's
  lobby owner). `SNL_STEAMLOBBY_OWNER_NAME` is a lobby-data key carrying the host's
  name, set when the session publishes its properties and read by the session search.
  Create, join, leave, list members, invite and the session search are all named now.
- The save path: the Steam ID comes from `ISteamUser::GetSteamID`, is checked for
  validity, and only then becomes the `SaveGames\<ID>\` folder; otherwise the file goes
  to `SaveGames\<name>.sav`, the no-identity save the second copy wrote.
- SNL's messages are Steam P2P packets on a channel number; the 33 session protocol
  message types (join, add/remove session client or object, object update, host
  migration, keep-alive, time sync, events) are listed by class name in the map.
- Two leads for later: the game reads an online version number
  (`[SNLMultiplayer] VersionIntNumber`) that decides who can see whose sessions, and the
  developers' debug menu has a switch "Apply multiplayer parameters to campaign".

Run: copy started 06:53:12 (backup `2026-10-18_0653`), title screen only, quit from the
main menu (Quit Game, Yes) at 07:08:33, the copy's own save written in its own folder.
`tools\compare-saves.ps1` afterwards: no change, all 13 files of your real folder have
the same SHA-256 as the backup. Nothing was written into the game's memory or files.

## 9. A C++ add-on gives the scripts a network socket, and the puppet flies from live packets (18 Oct, 06:45 to 07:45)

The second thing your addendum allowed: a C++ add-on for UE4SS. UE4SS's scripts (Lua)
cannot open a network connection, and the co-op plan needs exactly that: your friend's
plane positions arriving live instead of being read from a file (section 7). So a small
piece had to be written in C++, the language UE4SS itself is written in, and compiled
into a DLL that UE4SS loads next to the scripts. Done, proved at the title screen, and
the puppet from section 7 now flies from live packets too.

**What was installed, and where.** Details with sizes and checksums in
[downloads\installed-tools.md](downloads/installed-tools.md); the short version:

- Microsoft's C++ compiler (MSVC 14.44, the one in Visual Studio 2022 17.14) and the
  Windows 11 SDK, in `C:\AC7-Coop-Tools` (1.3 GB). The normal installer needs the
  blue administrator prompt that only you can click and you were away, so a script
  (`tools\fetch-msvc-portable.py`) downloaded the same packages the installer would,
  from Microsoft's own download servers, checked every file against the checksum in
  Microsoft's package list, and unpacked them into that folder. Nothing was registered
  with Windows: deleting the folder removes it. Every compiler program and installer
  carries a valid Microsoft digital signature (checked). The installer itself was
  downloaded too but never run (`downloads\vs_BuildTools\`), in case you prefer the
  standard way later.
- The UE4SS source code, at the exact version in the copy, in `cpp\RE-UE4SS` (35 MB),
  and a small text-formatting library it needs, in `cpp\third\fmt` (4 MB). Both are
  plain git clones from GitHub, no account needed.
- Nothing else: CMake, xmake and Rust, which UE4SS's own build uses, turned out not to
  be needed (below). Python 3.15 and Git were already here.

**Which UE4SS the copy runs** ([cpp\README.md](cpp/README.md) has the full story). The
copy's UE4SS log says "v3.0.1 Beta, Git SHA 48e7edfe, LessEqual421 Shipping, MSVC".
That commit is in the public UE4SS repository (1 February 2026, on its main branch),
and the Playmore build in the copy was made from it on 24 February with MSVC 14.44, so
the matching source and the matching compiler were both available. "LessEqual421" is
UE4SS's flavour for games on old Unreal versions (AC7 is 4.18), and an add-on has to be
built with the same flavour and the same C++ runtime, which these were.

**How the add-on was built, and why not the documented way.** UE4SS's guide says: clone
UE4SS, build the whole of it together with your add-on. Two things in the repository
rule that out here: its Unreal headers live in a *private* repository that only opens to
a GitHub account linked to an Epic Games account (the rules say to ask you before
linking accounts, and it is not needed for this), and building UE4SS itself also needs
the Rust toolchain. An add-on does not need UE4SS rebuilt, though. It needs UE4SS's
headers (the public part is enough for a socket add-on), the right compiler settings
(copied from UE4SS's own build files), and a list of the functions inside the copy's
`UE4SS.dll` for the linker, which `cpp\make-implib.py` reads out of that very DLL
(4,087 functions). One header that drags in the private ones was replaced by a copy of
just the few lines needed (`cpp\shim`). `cpp\build.ps1` does all of it and, with
`-Install`, puts the result into the copy. A check afterwards confirmed that every
function the new DLLs call in `UE4SS.dll` exists there under exactly that name.

**Proof the toolchain matches: HelloMod.** UE4SS's guide has a hello-world example;
the two example add-ons that ship with UE4SS need the private headers, so the guide's
example was built instead (`cpp\HelloMod`). Installed as `Mods\HelloMod\dlls\main.dll`
with a line in `mods.txt`, the copy's log at 07:10:07 says:

    Starting C++ mod 'HelloMod'
    [HelloMod] HelloMod says hello (built Oct 18 2026 07:09:43)
    [HelloMod] Unreal is initialised; the mod is alive inside the game

**CoopNetMod: the socket.** `cpp\CoopNetMod` opens a UDP socket on this PC's local
address (127.0.0.1, port 27777) when UE4SS starts it, listens on its own thread, keeps
the newest 64 packets with their arrival times, and gives every Lua script four
functions: `CoopNet_Count()` (packets so far), `CoopNet_Latest()` (newest packet's
text, its number, and its age in milliseconds), `CoopNet_Since(n)` (the next packet
after number n, so a script can fetch everything it has not seen yet), and
`CoopNet_Status()`. A packet is one line of text, `time,x,y,z,pitch,yaw,roll`, the same
fields the recorder writes. It never sends anything and nothing outside this PC can
reach it. `tools\coop-net-sender.py` plays a recorded flight into that socket at 40
packets a second, standing in for your friend's PC. UE4SS's Ctrl+P reload unloads and
reloads the add-on cleanly (the socket closes and opens again).

**Packet test at the title screen (07:11).** A one-screen script,
`mods\CoopNetCheckMod`, prints the count once a second. With the sender running for 15
seconds (601 packets sent, 40.1 a second), the log showed `+40 in the last second` every
second, each newest packet 1 to 24 ms old when the script read it. That is the "done"
condition of this task: an add-on built here loads in the copy, and a script in the game
reads packets sent by a program on this PC.

**The stretch goal: the puppet from live packets (07:23 to 07:40, SP Mission 01).**
`CoopFlightLabMod` got a new key, **F11**, next to the existing ones: the same takeover
as F4 (nearest active AI plane, its own AI off, invincible, speed matched, put in place
every frame), but the positions come from the packets. The script plays 100 ms behind
the newest packet so there is always a next sample to interpolate towards, keeps its
playback clock from drifting against the feed, carries on along the last segment for up
to a quarter second if packets stop, and starts afresh if the feed's clock jumps back.
It logs the correction per frame and the delay, as F4 does. It took six runs to get
right, and the detours are worth knowing:

1. The first straight-line recording (`flight-…_003054.csv`, from the recorder's very
   first try) has time stamps with whole-second resolution, so sent as a feed it moves
   in one-second jumps (corrections of 1,500 units once a second). Only the later
   recordings are usable as feeds; the turn recording (`…_010436.csv`) was used.
2. `GetTimeSeconds`, the game clock the scripts use, costs about **20 ms per call**
   from a script, and after a Ctrl+P reload inside a mission it stood still (two
   readings 4 seconds apart gave the same value). The file replay (F4) survives that
   because it reads the clock once per frame; the live script read it once per packet
   and ground down to 10 frames a second with its playback clock frozen. The live
   script now paces itself with the real-time clock (`os.clock`), which is what the
   packets' times are in anyway. (The recorder still uses the game clock; worth
   changing before the next recordings.)
3. Re-using a plane that an earlier run had left with its AI off made it fly with a
   dead engine, so the script had to move it the whole way each frame (18 units a
   frame). A fresh plane fixed it.

The clean run (07:38:51, an enemy F/A-18F as puppet, the 20-second turn recording fed
at 40 packets a second, 804 packets):

- **90 frames a second** handled, every one a new rendered frame, 0.2 ms of work each.
- **Correction per frame 1 to 2.4 units** (10 to 24 cm) through the roll, the hard
  pull and the roll-back, over the whole 20 seconds (the file replay in section 7
  needed about 6 units a frame through the same manoeuvre at 40 frames a second).
  Worst single correction 92 units, right after the first packet.
- **Delay**: the puppet showed each position 99 ms after the packet arrived, by design
  (the 100 ms buffer); the packets themselves were 1 to 22 ms old when read. So the
  lag your friend would see is about 100 ms plus whatever the internet adds, and the
  buffer can be made smaller once a real connection's jitter is known.
- Speed matching followed the feed: the puppet's own engine ran at the feed's speed
  (600 km/h straight, down to 430 in the pull, 670 after), estimated from the last
  second of packets.
- Pictures: `pictures\2026-10-18_live-puppet-turn-6s.png` shows the F/A-18F low on the
  right, rolling, six seconds in; by 12 seconds the feed's pull had taken it out of the
  chase camera's view (`…-12s.png`). The title-screen check and the first runs are in
  `…_coopnet-title-screen.png` and `…_live-puppet-*.png`.

**Still open:** the feed over a real network (two PCs: the sender runs on the other
one, the add-on's listen address changes from 127.0.0.1 to the PC's own, a jitter
buffer sized to the measured connection); sending the player's own positions out (the
other direction of the same socket, a small addition to the add-on); and everything
section 7 listed (missiles against the puppet, video).

**Run and close.** The copy was started at 07:10:07 with `tools\start-copy.ps1` (backup
`2026-10-18_0710`, all checksums matching), after the code-reading session (section 8)
had finished with it. Title screen for the packet test, then SP Mission 01 as section 7
describes (the SP briefing needed about 210 single Escape presses, three times the
figure in section 7; the plane left the combat area once and was put back with "Retry
from checkpoint"). Quit Mission, main menu, Quit Game at 07:44:01; the copy wrote its
own save in its own folder (685,197 bytes). `tools\compare-saves.ps1` afterwards: no
change, all 13 files of your real folder have the same SHA-256 as the backup. The
in-use note was removed from the shared notes folder.

## 10. The playtest bot flies and fights: it completed Mission 01 by itself (18 Oct, 11:20 to 13:05)

You asked for a bot that plays missions for a session and reports back
([playtest-bot.md](playtest-bot.md)), and said Steam achievements don't matter (you have
nearly all of them). Built and tested the same day, in the copy only. **Result: the bot took
off, found and shot down all 19 enemy planes of Mission 01 (Casual) without taking a single
hit, and the game declared "mission accomplished".** It took two tries: the first was
stopped by a time limit in the session's own test order, not by the bot (details below).

**The pieces.**

| Piece | What it is |
|---|---|
| `CoopPilotMod` (UE4SS Lua script, copy in `mods\`) | The pilot. Reads the plane, the mission and every enemy many times a second, flies with the keyboard, fights, and writes `pilot.log`, `events.jsonl`, `status.json` and a flight log into `C:\AC7-Coop-Game\UserProfile\pilot\`. Takes orders as one-line packets through the CoopNetMod socket from section 9, so the game window never has to change for an order. |
| `CoopPadMod` (C++ add-on, `cpp\CoopPadMod`) | The pilot's hands: presses keyboard keys from inside the game process (Windows' `SendInput`), but **only while the game window is in front**, and lets go of everything as soon as it isn't, or when the script stops asking for 0.3 s. Also carries a virtual gamepad, which turned out to be unusable (below). |
| `tools\pilot.py` | Sends the pilot an order and reads its status and log, for a session. |
| `tools\playtest.py` | The test runner: reads a test order (`playtests\orders\*.yaml`), drives the menus into the mission, has the pilot take off and fight, retries after a failure, and writes the report folder (`playtests\<date>_<mission>_<name>\`). |
| `playtests\2026-10-18_1237_m01_first-run\` | The first run's report, events, flight logs and pictures. |

**What the tests showed, in the order they happened.**

1. **Writing the plane's control values does nothing** (way 1 of the design). The plane has
   `InputPitch`, `InputRoll`, `InputThrottle` and so on, but the game rewrites them from the
   keyboard and gamepad every frame, before the flight model reads them: a 19-second probe
   in the air (16 ways of writing them) moved the plane not at all, and a value written one
   frame was gone by the next in every case. The per-frame hook it tried
   (`PlayerPlane:FrameUpdate`) is never called through the script system.
2. **A crash, found and fixed.** The first version crashed the game three seconds into a
   test. UE4SS's own source shows why: `LoopAsync` timers run a script on a second thread
   while game hooks run the same script on the game's thread, with no lock between them.
   Everything in the pilot now runs on the game's thread (`LoopInGameThreadWithDelay`), and
   there was no crash after that in about 90 minutes of flying, including six script reloads.
3. **The game pauses itself whenever its window loses the front.** So a bot can only play
   while the game is in front, whatever it uses for controls.
4. **A virtual gamepad can't reach the game.** The plan was a stand-in `xinput1_3.dll` (the
   gamepad library) in the copy's folder, built and loaded fine, but the game never called
   it: **Steam's overlay** (`gameoverlayrenderer64.dll`) sits in between and answers the
   game's gamepad reads itself, as part of Steam Input. Getting past that would mean changing
   your Steam settings, which I didn't. The stand-in was taken out of the copy again (kept in
   `cpp\build\CoopPad\`, source in `cpp\CoopPad\`).
5. **Keyboard keys work**, pressed from inside the game. Key messages sent to the window
   (`PostMessage`) don't, even with the game in front: the game reads the keyboard at a lower
   level. Your bindings (Options > Keyboard): **pitch 1 (down) / 3 (up), roll A/D, yaw Q/E,
   throttle W/S**, missile Space, gun Left Ctrl, flare G, next target Tab, weapon C,
   high-G turn 2, autopilot Z. (The note in section 7 that "S pulls up" was a misreading: S is
   the brake; the plane was upside down at the time.)
6. **How the Typhoon answers the keys** (measured in Free Flight): roll up to about 160°
   a second and it keeps rolling (full aerobatic control, no bank limit); pitch up to about
   36° a second; both build up over about half a second after a key goes down and fade the
   same way after it comes up; yaw is gentle (about 4° a second). One game unit is 10 cm.
7. **Free Flight** (the last line of the Free Mission difficulty list) loads a mission's map
   with no enemies and **no briefing**, and puts the plane at 600 m, 600 km/h; a crash just
   puts it back. It's where the autopilot was tuned.
8. **The autopilot.** Every frame it works out where the goal lies in the plane's own frame
   (ahead, to the side, above). For a big turn it rolls until the goal is above the canopy and
   pulls; for small corrections it keeps the wings level and nudges the nose with pitch and
   rudder. Gentle inputs are made by pressing a key in a share of the frames. A safety layer
   climbs away when the plane is below 300 m or heading there within four seconds, and turns
   back when the plane crosses the mission area's edge. In Free Flight it took the plane from
   a tumbling dive (8,900 m, upside down, 1,700 km/h) to a steady heading within 4 seconds,
   held headings to within a degree, and made a 90° turn in 4 seconds.
9. **Fighting.** Targets are picked the way you would: Tab cycles them, and the pilot reads
   back which one the game selected. When nothing is selectable yet (enemies beyond radar
   range), it flies toward the nearest enemy from the game's own unit list, telling sides
   apart with each unit's `GetFaction` (0 = enemy, 1 = ally) and mission targets with
   `IsTGT`. It aims a little ahead of the target, chases at full speed beyond 3 km, fires a
   missile (Space) about once a second while the game shows a lock inside 3 km, fires the gun
   (Left Ctrl) inside 1 km when the target is within 5° of the nose, and on a missile warning
   drops a flare (G) and breaks hard for two seconds.
10. **Mission 01 on Casual** (Typhoon, LAAM): take-off by itself in 10 seconds; the first kill
    5 missiles at 2.8 to 2.4 km; then 19 kills in phase 2 (the run from its checkpoint),
    80 missiles, some gun, **no damage taken**, score 12,180 (the same as the second line of
    your own Mission 01 record), mission accomplished at 12:58. Pictures in `pictures\`
    (`2026-10-18_bot-m01-*`), report in `playtests\2026-10-18_1237_m01_first-run\report.md`.
    The first try ended at 4,880 points because the session's test order had a 400-second
    limit; the plane flew on unattended and left the area. The runner now gives the pilot
    open-ended orders and stops it itself.
11. **The mission's own events work as the log's backbone.** Hooks on the mission's handlers
    report phase start, phase cleared, mission accomplished, player down, out of the area,
    time out, objective failed and cutscenes; a hook on `GameObject:OnDeath` reports every
    death. The status file has the mission's score, kill count, time left and the
    accomplished/failed flags (after the mission ends both can read true; the events are the
    reliable signal).
12. **Developer cheats are empty.** Grouping the cheat manager's 494 commands by the code
    they run shows that every test helper the design hoped to try (`SkipToPhase`,
    `TogglePlayerInvincible`, `TogglePlayerWeaponUnlimited`, `ToggleForceSkipIGC`,
    `ThreeTimesFaster`, `KillTarget`, `CompleteMission`, and so on) is one of the shared
    empty stubs. One exception worth a later try: `DisableAIAttack` has its own code.
13. **Menus.** The Campaign submenu opens on "Continue", which goes straight into **your story
    save's current mission** ("Hush", on Ace); a Down pressed too soon after opening it is
    swallowed, which is how one test landed there (no harm: it only reached the briefing, and
    the copy has its own save). The runner now waits. Screens sometimes swallow an Enter at
    a slow change, so the runner presses Enter until the mission loads. After a failure the
    retry menu offers "Retry from checkpoint" (fast) and "Retry mission" (from the start, no
    briefing). After "mission accomplished" the game plays a replay of the whole mission;
    Enter only skips to the next camera shot.
14. **Weapons through the game's functions** (instead of keys): `FlarePressed` dropped a
    flare (4 to 3) and `ToggleSpecial` switched to the LAAM. Missiles and gun are unlimited on
    Casual, so their counts can't show a shot; the pilot uses the keys for them, which are
    proven.

15. **The test runner on its own, from a cold start (13:26 to 13:41).** `python
    tools\playtest.py run playtests\orders\m01-casual-runner-test.yaml` started the copy,
    drove every menu page, took off, flew and fought, and **completed Mission 01 on Casual
    at the first attempt: 10.4 minutes, 20 kills, 77 missiles, no damage, score 12,400**
    (the same as the best line of your own Mission 01 record). Two missile warnings came
    near the end; on "very near" it dropped a flare and broke, and the missile missed. Then
    it closed the copy and checked your saves (unchanged). Report:
    `playtests\2026-10-18_1326_m01_runner-test\report.md`. Its first try at 13:11 had
    failed in the menus (it pressed by timing alone, and the mission never loaded), which is
    what led to the page map below.
16. **The menu pages, recognised.** The menus all sit inside one front-screen widget, but
    each page is its own widget, so the pilot reports the visible one in `status.json`
    (`page`) and the runner checks every step: `CampaignMenuMain_C` (the Campaign submenu),
    `CampaignFreeMissionDifficulty_C`, `CampaignFreeMission_C` (the mission list),
    `CampaignMissionTitle_C` / `CampaignMV_C` / `CampaignBriefingMV_C` (the briefing),
    `CampaignBriefingMenu_C` (the operation map), `CampaignMenuActionSelect_C` (Mission
    Prep), `CampaignHangarAircraft_C`, `CampaignHangarWeapon_C`, `CampaignHangarReview_C`
    (Standby). If Enter on the Campaign submenu leads into the story mission instead, the
    runner backs out through Mission Prep > Quit Mission and tries again.

**Run and close.** The copy was started nine times, each through `tools\start-copy.ps1`
with a save backup first (`backups\2026-10-18_1128`, `_1137`, `_1157`, `_1159`, `_1202`,
`_1207`, `_1311`, `_1317`, `_1326`): once ending in the crash of point 2, the others closed
by ending the process (to install an add-on, to restart the menu route, or by the runner at
the end of a test). Two of them flew Mission 01 to the end. `tools\compare-saves.ps1` after
each: no change to your real save folder.

## 11. The bot's second phase: seeing the fight (18 Oct, 13:30 onwards)

Your request at 13:30: special weapons, the paths of incoming missiles, and enemy paths and
behaviour from the game's own data plus live readings, acted on in real time. And at 14:20:
test it on Mission 02 (aggressive enemies, ground targets, still short).

**The new piece: `mods\CoopPilotMod\Scripts\awareness.lua`**, loaded by the pilot. It keeps
a track of every enemy plane and every missile (recent positions, velocity, turn rate) and
reads their limits from the game:

- **Weapons, from their class defaults** (the values the game loads from its data files; no
  game file is unpacked): the Typhoon's standard missile locks within 2 km and 32.5° of the
  nose, turns at up to 40, carries two at a time and reloads in 5.5 s; its LAAM locks at up
  to 10 km within 27.5°, air targets only, double damage, two at a time, 8 s reload. On
  Casual the lock ranges are larger (the game has separate easy values).
- **Enemy planes**: top and lowest speed, turn and acceleration limits
  (`AIPlane:GetMaxSpeed`, `GetTurnSpeed`, ...), whether the mission counts them, **their AI
  state** (the game's `EAIState`: return to area, avoid obstacle, return to formation,
  special action, evade an attack, escape a pursuer, provoke, move away, pursue target,
  follow formation, patrol, idle), **who they are tracking**, and **the route a scripted
  plane is set to fly** (a curve in its `AIPathComp`; Mission 01's second bomber has a
  107 km one).
- **Enemy missiles**: speed, acceleration, turn limit, homing delay, fuse radius, the two
  warning radii (Mission 01's MiG missile: 2 km "near", 800 m "very near"), homing type
  (active radar, infrared, semi-active), and which plane it is homing on.
- **The ground**: line traces down from the plane and from where it will be in 1 to 4
  seconds, so ground safety uses real clearance. The altitude the game reports is height
  above the sea.

**Predictions.** Where an enemy will be: along its scripted route when it is following one,
otherwise a steady turn at the turn rate it shows now, capped at its limit. The pilot aims
at the meeting point (for its own speed when far, the gun's when close) and scores itself:
every half second it predicts each enemy 2 s ahead and, 2 s later, measures how far off it
was, per method, against a plain straight line. For each missile homing on us: distance,
time to impact, the miss distance if nothing changes, and how fast the line of sight
turns.

**Behaviour built on it.**

- **Missiles at us**: a flare about two seconds before impact (or inside the missile's own
  "very near" radius), and from four seconds out a break turn across the missile's line
  of approach (the turn it has to match hardest), with the high-G turn key for the last two
  and a half seconds. The game's own warning remains the fallback.
- **An enemy on our tail** (its AI tracking us, behind within 2 km): turn into it.
- **Special weapon**: switch to the LAAM for a target beyond the standard missile's lock
  range and inside the LAAM's; switch back when the target is close, out of range, or the
  LAAM is empty. A multi-lock special would be armed with two or more enemies in its cone,
  a ground-only special for a ground target.
- **Ground targets**: come in no lower than 600 m above the ground, dive no steeper than
  25°, pull out by 900 m.
- **Targets the game never lets you select** (Mission 02's radar): skipped after 10
  seconds close by.
- Real launches are counted from the ammunition (limited from Normal up).

**Tests so far.**

| Run | Result |
|---|---|
| Mission 01, Hard, 13:50 (tracker watching only) | Completed, 18 kills, no damage. One MiG missile at us from 1.9 km; the flare at 790 m broke its lock at once. |
| Mission 01, **Ace**, 14:03 (new tactics) | **Completed at the first attempt in 8.8 minutes** (Casual took 10.4: the LAAM takes targets at range), no damage. The LAAM was armed at 9.5 km each time and ran dry near the end; the bot noticed and went back to standard missiles. No enemy fired at us. |
| Mission 02, Hard, 14:16 | **Failed.** Two helicopter missiles (infrared, from 4 km): break turns from 3.5 s out, flares at 1.6 s and 1.0 s, both lost their lock (one 216 m away), no damage. But then five minutes circling a radar the game never offered as a target, diving at it and pulling out among hills: four 24-point hits at 190-340 m above the sea (terrain scrapes; the hills are higher than the old sea-level floor), then it flew into the ground. The runner's retry also failed (it pressed Enter during the "Mission failed" sequence, before the retry menu). Led to the ground sensor, the unselectable-target rule, the ground-attack approach and a patient retry. |
| Mission 02, Hard, 14:37 | Stopped by hand after 12 minutes: **no damage at all** (the ground sensor worked: it reads its real clearance, e.g. 430 m above ground at 505 m above the sea), but stuck at 7 kills over the enemy airbase, marking building after building "unselectable". |
| Mission 02, Hard, 14:55 | **Completed** (22 minutes; the session loaded three fixes into the running attempt and let it run past its 20-minute limit). 44 kills, 76 missiles (30 of them LAAMs), one 24-point hit. **Eight enemy missiles were aimed at the bot and all eight lost their lock** (break turn from about 4 s out, flares at about 2 s). Report: `playtests\2026-10-18_1451_m02_hard\report.md`. |

**What Mission 02 taught, and the fixes:**

1. **The LAAM hides ground targets.** It is air-only, and while it is armed the game offers
   only air targets for selection. The bot had switched to it for helicopters and never
   switched back, so for minutes the airbase was invisible to its targeting. Now: with
   nothing selected it returns to standard missiles, and it never arms the LAAM for a
   ground target.
2. **Ground objects need attack runs.** A building close below can't be brought onto the
   nose by circling. The bot now flies them as a pilot does: run in from 3.5 km at 600 m
   above the ground, a dive of at most 25°, pull out at 700 m, extend (fly away and climb)
   to 3.5 km, come back. It also keeps its chosen target instead of switching to whatever
   is nearest every two seconds.
3. **The heights are above the sea.** Over hills that is not the clearance; the line-trace
   ground sensor replaced it (no terrain hits after it went in).
4. **The predictor's first scores were honest bad news.** 2 s ahead, over 6,000 checks:
   planes on scripted routes 11 m off (a straight line: 9 m); turning planes 159 m off (a
   straight line: 134 m). Mission 02's enemy pilots keep changing how hard they turn, so
   carrying today's turn rate 2 s forward overshoots. The predictor now makes several
   guesses for every check (straight on, half the turn rate, the full turn rate, the route)
   and uses whichever has the smallest running error for that kind of flying, so it picks
   its own method from what the enemies actually do.

**The validation run, untouched by the session (15:19 to 15:38):** `python tools\playtest.py
run playtests\orders\m02-hard-validation.yaml` from a cold start: **Mission 02 on Hard
completed at the first attempt in 14.9 minutes, 43 kills, no damage at all**, then the
copy closed and your saves checked (unchanged). Report:
`playtests\2026-10-18_1519_m02_validation\report.md`.

- **Six enemy missiles aimed at the bot, six lost their lock**: four helicopters fired
  almost together from about 4.5 km, and three of those were broken off only 214-239 m
  away; a fighter's from 1.6 km and a drone's from 2.1 km broke off at about 940 m.
- **Predictions 2 s ahead** (7,400 checks): for turning planes **half the current turn
  rate was off by 52 m on average, against 81 m for a straight line and 92 m for the full
  turn rate**, and the guesses actually used averaged 54 m, close to the best. For planes
  on scripted routes the route guess averaged 7 m, but the self-choosing used the straight
  line too often (34 m): that group mixes slow ground vehicles with fast planes and should
  be split by speed. Not changed yet (the code stays as validated).

## 12. Double Trigger installed in the copy with AC7 Mod Loader (18 Oct, 16:40 to 16:50)

You asked for layer10_love's co-op mod to be prepared, installed with AC7 Mod Loader and
launched. It was done in the copy: your rules keep the real install, its mods and its Mod
Loader untouched, and asking to lift that would have held everything up.

**Download.** v0.1.0 from the release page into `downloads\double-trigger-v0.1.0\`; every
file matches the release's checksum list; Windows Defender found nothing. Details and
checksums in `downloads\installed-tools.md`.

**The Mod Loader needed one addition.** It could only place `.pak` files and loose files
under `Game\Content`, but Double Trigger is a code loader that has to sit next to
`Ace7Game.exe`. One rule was added to the loader's source (`inherited\AC7ModLoader\src\Core\ModManager.cs`,
`LooseTargetFor`): a file at the top of a mod named `dinput8.dll`, `dwmapi.dll`,
`version.dll`, `winmm.dll` or `xinput1_3.dll` goes into the game folder. Everything else
(backup of a file already there, removal on disable or Vanilla mode, the manifest) is the
loader's existing loose-file machinery. Five new unit tests pass along with the old ones
(`ac7ml-tests order`, `replace`). The new build is `inherited\AC7ModLoader\bin\AC7ModLoader.exe`;
the previous build is kept in `bin\previous-2026-10-06\`. The loader in your real install is
the old build and is unchanged.

**Package and install.** `mods\double-trigger-modloader\Double Trigger v0.1.0\` holds the
unchanged DLL, its two licence files and a short readme. Installed with the loader's own
command line, pointed only at the copy:

```
AC7ModLoader.exe --game "C:\AC7-Coop-Game" --install "...\mods\double-trigger-modloader\Double Trigger v0.1.0"
```

Result: "Installed Double Trigger v0.1.0 at load-order position 1 of 1; applied +1", and
`C:\AC7-Coop-Game\dinput8.dll` appeared (a hard link to the library copy, checksum
unchanged). The loader's data lives in `C:\AC7-Coop-Game\ModLoader\`. With `--game` the loader
does not write the one setting it shares between installs (`%APPDATA%\AC7ModLoader\gamepath.txt`,
which still names your real install, checked before and after). Vanilla mode on removed the
DLL and Vanilla mode off put it back, so the loader can switch the mod off for you.

**Launch.** Not through the loader's Launch button: that goes through Steam, and Steam would
start your real install. The copy was started with `tools\start-copy.ps1` as always (own save
folder, real save backed up first). Double Trigger's log (`C:\AC7-Coop-Game\ac7mp.log`) in
order: version `0.1.0+6240b21f`, game code decrypted after 1 s, "all game addresses check
out", Steam initialized, "online block in place", "copy check: Steam copy, owned", engine
hook running, "online gate: single player; starting", fixes installed, "overlay ready: F5".
No warnings or errors. At the main menu, Multiplayer is greyed out (the mod's online
block), and F5 opens the co-op panel with the version, your Steam name and a masked ID,
"Not in a co-op session", "Friends hosting co-op: none right now" and the Host, Invite
friends, Leave and status buttons. Pictures: `pictures\2026-10-18_double-trigger-*.png`.
No lobby was hosted (that is going online, which needs your OK). `tools\compare-saves.ps1`:
your real save unchanged. The copy was left running at the main menu for you.

**Living next to UE4SS.** UE4SS and all our add-ons loaded as before in the same run. Two
UE4SS lines say a hook "failed"; the same two appear in the 17 Oct log from before Double
Trigger existed, so they are not caused by it. One real overlap: UE4SS reads keys directly
from Windows, so F5 also reached `CoopFlightLabMod` ("no player plane", harmless at the
menus). In a mission, F5 (Double Trigger's panel) would also start the flight lab's puppet
teleport test, and F9 (Double Trigger's debug "publish plane") would also write a UE4SS
object dump. Before playing co-op in the copy, switch `CoopFlightLabMod` off in
`ue4ss\Mods\mods.txt` or set Double Trigger's `toggle_key` in `ac7mp.ini` to a free F key.
Not changed here: the mods are other sessions' work, and the game was running.

## 13. Double Trigger in your real install too (18 Oct, 16:50 to 16:55)

You lifted the "never touch the real install" rule for this one install, and asked for a
backup first and proof that Vanilla mode can remove it. The rule otherwise stands.

**Backups first** (`backups\2026-10-18_real-install-before-double-trigger\`): a full copy of
your real `ModLoader` folder (759 files, 1.6 GB, checked byte for byte against the original:
library, profile, settings, deploy record and the old loader exe), the SHA-256 of all 91
files in `Game\Content\Paks\~mods`, and a listing of the game folder. Your saves were backed
up as well (`backups\2026-10-18_1651`).

**Checks before changing anything.** Your real loader exe was byte-identical to the build the
change was made on, so the new one is exactly your loader plus the one rule from section 12.
None of your 30 library mods contains a DLL, so the new rule changes nothing for them. Asked
read-only, the loader reported your setup fully in sync (19 enabled mods, 91 files, nothing
pending, no stray files) and Vanilla mode off.

**Install.** The updated loader was copied over your real `ModLoader\AC7ModLoader.exe` (it has
to be the new one: the old build would quietly remove `dinput8.dll` the next time it applies,
because it does not know the file), then:
"Installed Double Trigger v0.1.0 at load-order position 31 of 31; applied +1 -0 =91". So
`ACE COMBAT 7\dinput8.dll` was added and your 91 mod files were left exactly as they were.

**Vanilla mode tested.** On: 92 files removed (all mods and Double Trigger), the game folder
plain. Off: all 92 back, `dinput8.dll` with its release checksum, and every one of the 91 mod
files under the same name with the same SHA-256 as before the install. Vanilla mode is off
again, the loader reports everything in sync (20 enabled mods, 92 files), and the shared
`gamepath.txt` still names your real install.

**Will it start there?** Not launched (you didn't ask). The mod's own checks were checked
read-only: your real exe is the build it expects, its Steam library file has the expected
checksum, and none of the pirated-copy marker files exist. The same DLL passed every check in
the copy (section 12). Your real install has no UE4SS, so the F5/F9 overlap from section 12
does not exist there.

**What changes for you when you play the real game:** Multiplayer in the main menu is greyed
out while the mod is installed; turn Vanilla mode on in the Mod Loader before playing the
game's own online modes, and off again for co-op. F5 opens the co-op panel. A co-op partner
needs the same `dinput8.dll` and, for a fair game, the same gameplay mods (see the
compatibility answer of 18 Oct: Skies Restored is the one of your 19 that edits mission maps).

**To undo it all:** in the Mod Loader, untick or remove Double Trigger (or turn on Vanilla
mode). To go back to the old loader exactly, copy the backup's `ModLoader\AC7ModLoader.exe`
over the real one after removing Double Trigger.

## 14. The bot sees terrain and mission gimmicks: Cape Rainy's canyon (18 Oct, 19:00 onwards)

Your request: the bot should see and react in real time to terrain and other physical
things, and adapt to missions' special rules; prove it on Mission 03 and on Mission 14
(Cape Rainy Assault: a narrow valley, an altitude limit, nets of moving searchlights);
then fly the campaign on Ace. Everything here was done in the copy. Double Trigger was
switched off in the copy (your OK, 20:20; Vanilla mode in the copy's own Mod Loader, so
`--vanilla off` puts it back); your real install was not touched.

**What Mission 14 turned out to be (read from the game, not guessed).**

- It opens with a night **aerial refuelling** mini-game. The mission's own
  `Mission:SkipMiniGame` skips it; the pilot now does that by itself on the tanker's first
  radio line (and for any other refuelling or landing mini-game).
- The pilot now **hears the radio**: a hook on the subtitle widget's
  `RadioMessageReceived` gives speaker and text of every line ("Keep altitude below 600
  meters", "Searchlight up ahead", "Strider 1, I need you take out those enemies at the
  LZ"). Every line goes into the event log.
- **The altitude ceiling** is 550 m, not the 600 m the radio and the pause screen announce:
  the mission hands it to the plane with `PlayerPlane:SetRestrictedAltitude(550)` (now
  hooked), the plane's `IsOverRestrictedAltitude` switches on at 550 m, and staying above
  it for a while fails the mission ("you've exceeded the altitude restriction... we've
  lost the element of surprise"). The pilot takes the game's figure over the radio's and
  also learns it from the flag.
- **The map** (pictures in `playtests\missions\m14\`): everything is 600 to 2,300 m high
  except one winding river canyon, 47 km from the start to the enemy base, 150 to 300 m
  wide in its middle stretch at the heights a plane may use.
- **73 searchlights** (`SystemObjectSearchLight`), about 60 along the canyon and the rest
  at the base, plus two on helicopters. Each has its own sweep: side to side (yaw) or up and
  down (pitch), between two ends, at 5 degrees a second (10 for a few), sometimes with a
  pause at each end. Its detection volume is a thin cone, 1.5 degrees either side of the
  beam (the collision mesh: 157 m wide at the end of a 3 km beam). The moment a beam touches
  the plane the light locks on and tracks it, and about two seconds later "Spotted enemy
  aircraft in the valley" fails the mission. The plane's own `IsInSearchLight` never
  reported it. They light up as the plane approaches; Hard and Casual sweeps are the same
  shape (Casual measured 4.7 degrees a second, Hard 5.0).
- **Phase 2** is the attack on the air base: six enemy Apaches hover over the landing zone
  where our transports (CH-47s) land, with AA guns and SAMs around; if the landing team is
  overrun ("This is taking too long... Our boys had to surrender") the mission fails, on
  Hard about three minutes into the phase.

**What was built.**

| Piece | What it does |
|---|---|
| Fast line traces (`cpp\CoopPadMod\trace.cpp`) | The engine's own line trace called directly from the C++ add-on (`CoopTrace_Line`, `CoopTrace_Ground`), through UE4SS's exported `UObject::ProcessEvent` with the parameter layout read from this build's object dump. **1.4 microseconds per trace** in flight, against 1.2 ms the same trace cost from a script: some 600 times faster, so the bot can afford thousands of rays a second. |
| Terrain survey (`survey` order) | While the game is paused (a menu), a grid of traces over the whole map into a CSV: 247,561 points at 50 m in 25 s. `tools\terrain-map.py` draws it (ceiling, searchlights, flights, routes). |
| Height map and look-ahead (`nav.lua`) | The survey (or live traces) as a height map; every 0.1 s the next 3.5 to 5 s of the path the plane would really fly is checked against the ground, the ceiling, other planes and the beams, and the nearest clear direction chosen if needed. |
| Route planners (`tools\route-plan.py`, `tools\route3d.py`, `tools\route-heights.py`) | The middle of the open corridor under the ceiling (A* on a distance-to-wall map), with speeds from bend radius and width; a 3D version that chooses where AND at what height to fly, avoiding squares no height keeps dark; a height smoother. |
| Beam sweeps (`gimmicks.lua`, `lights` order, `tools\beam-fans.py`) | Every searchlight's position, sweep, cone and reach read from the game; a recording of where each beam pointed ten times a second; from it each beam's two ends and speed, and for a helicopter's light a ring. |
| Route following (`route.lua`) | The pilot follows a planned route like a driver looking down the road; for canyons a gentler controller (bank follows the sideways error up to 72 degrees, never upside down), height followed 150 m ahead separately from steering. |
| **Live beam dodging** | Four times a second, for the next 2 km of route: where every nearby beam will point at the moment the plane reaches each point (its recorded sweep, its live place in it), for 63 combinations of speed (up to 200 km/h slower, 100 faster), height (40 m lower, 20 m higher) and a sideways shift (80 m either way, only where the walls leave room), starting from where the plane really is. The smallest change that keeps every point dark is flown. This is your "beams as moving terrain". |
| Failure report | When a phase fails: which searchlight was tracking the plane and how far inside its cone the plane was, which enemies were near. |
| Targets that matter | Enemies weighted by how close they are to our own ground units and transports (six times at 0 m), shooters before searchlights and fuel tanks, helicopters chased like planes. |
| Runner plans (`playtests\missions\m14\plan.txt`) | A mission's plan: files for the pilot, orders per phase, retry from the start or the checkpoint per phase. The runner also now selects missions by reading which one the list's cursor is on, checks the loaded level (`ms14`), and knows the game sometimes restarts a phase by itself. |

**What the tests showed, in order** (all in the copy, Mission 14).

1. Flying straight north at 1,400 m from the start: "exceeded the altitude restriction", and
   the ground there is 1,200 m: the canyon is the only way.
2. First canyon flights (Casual): the old ground-safety check looks straight ahead and sees
   the canyon wall in every bend, pulls up and flies into the wall; the old big-turn mode
   rolled the plane on its back in a climbing bend. Both replaced for route flying. Then
   **the whole 47.7 km canyon flown with no damage, phase 1 cleared**, all lights passed
   (19:58, Casual).
3. Phase 2 (Casual, twice): the base attack lost because the bot attacked searchlights and
   flew slow ground-attack runs at hovering helicopters while the landing team was overrun.
4. Hard: caught by searchlights at 8.8, 17, 18.3, 23, 28.2 and 40.3 km in successive tries,
   each one teaching something (a beam level with the route, a dip cut short by looking
   too far ahead, a helicopter's ring, a lamp passed at 74 m, a beam curtain crossed close
   to its lamp), plus a stall (a long full pull at 480 km/h in a 55 degree bank) and a
   too-eager stall guard that boosted the plane to 990 km/h (removed).
5. **Hard, 21:38: the whole canyon flown unseen and undamaged with live dodging** (speed
   changes, 40 m dips, 80 m sideways shifts past searchlights 21 and 22 and the dense nets
   at the base), phase 1 cleared. Phase 2 lost again; then the target weighting above.
6. Two game crashes during the base attack, both right after a target was destroyed, both
   inside UE4SS while a pilot script ran; since then an object's kind is worked out once
   and remembered, and the pilot touches nothing on the frame a kill is seen.
7. **Unattended runs from the title screen** (the runner with the plan file, 22:04 onwards):
   the canyon was cleared on Hard at the first try in 3 of the first 4 runs (22:04, 22:39,
   23:01; at 21:58 a searchlight caught the plane); the runner then retries phase 2 from its
   checkpoint. Phase 1 needs "Retry mission", not the checkpoint (after a
   checkpoint retry the refuelling starts again mid-canyon).
8. **Four game crashes** (20:10, 21:48, 22:17, 22:58), all in phase 2 after a checkpoint
   retry or a kill. The cause: a retry replaces the planes, enemies and lights with new
   ones, and the engine frees the old ones about a minute later; the pilot still held some
   and read them, which crashes the game past any error guard. Now every object is checked
   with UE4SS's `IsValid` (safe even on a freed object) before anything is read from it,
   and the pilot forgets everything it held whenever the plane changes or a phase restarts.
   **No crash since** (the 23:01 run: 8 phase 2 attempts and 23 minutes of fighting).
9. **Your two ideas for phase 2.** (a) Neutralise what threatens the landing party first:
   each enemy's value now counts how close it is to our ground units and transports (up to
   7 times), what it is (tanks, APCs, attack helicopters 1.6 times), whether it fired at us,
   and reinforcements ("zouen", the game's own word) 4 times; the bot then **selects the
   chosen enemy directly** (it writes the game's `SelectedTarget`, as a player would after
   pressing Tab until it comes up), keeps it at least 6 s, and drops it for a minute if it
   will not lock. (b) **One missile per target when one is enough**: the target's health
   is read before firing (Hard: helicopters, SAM sites, AA guns and APCs 40, tanks 60,
   fighters 80; a standard missile does 40, the LAAM 80); if one missile kills it, the
   target is set aside until the missile should arrive and the next one is selected at once
   for the second missile. In the 23:01 run: 34 one-missile shots, 21 of those targets
   destroyed (an Apache, a SAM site, a Harrier and an AA gun each went down to a single
   missile within 3 s of each other in attempt 4).
10. **How phase 2 really works** (attempt 4, 23:20 to 23:25, the best so far): the landing team
    cannot land while the Apaches at the landing zone are alive ("hostiles are still near the
    LZ! We can't make our approach!"); about 3.5 minutes after the phase starts the mission
    fails ("This is taking too long... surrounded"). In attempt 4 the bot destroyed three
    Apaches, two SAM sites and two jets in 3 minutes, and "Basilisk 1. Landing now! ... This
    base is ours for the taking!" followed. Then the **reinforcements** arrive ("We've engaged
    the enemy reinforcements"), and there are about 100 seconds to destroy them.
11. **Why so many targets "would not lock": still open.** In attempts 5 to 8 the bot spent
    minutes flying perfect attack runs at SAM sites (nose within 1 to 6 degrees, 2.4 km down to
    1 km) without ever getting a lock, while the SAMs shot it down to 7 health. Ruled out one by
    one by reading the game: the target's stealth (level 0 everywhere), visual identification
    (switched on in this mission: 1.8 s at 500 m up to 15 s at 3.5 km, 3.5 times faster within
    7 degrees of the nose, but every target was already identified), "needs detection" (off;
    every target reads as detected), invincibility, the game not counting them as targets (they
    are in its list of target candidates, none in its "untargetable" list), something in the
    way (a ray from the plane to each SAM was clear), the game changing the selection back
    (never), running out of missiles (over 100 left) and a lock height limit on the missile
    (none). The first suspect was **clouds**: the SAM locks that worked came with the plane 200
    to 430 m above the ground, the failed runs started 900 to 1,300 m up and dived through the
    patchy cloud layer at 350 to 1,050 m, and the game has lock states for "locking in cloud".
    So attack runs now stay under the lowest cloud the plane has met (learned from the game's
    own `IsInCloud`, or given in a plan: `cloudbase 350`), and that did bring a SAM down from
    200 m. But SAM_2 still did not lock from under the clouds (1.9 to 1.25 km, 1 to 2 degrees
    off the nose, 140 to 230 m up), nor did a reinforcement APC nose-on at 1.4 km. What was
    seen at that moment: the target selected, but **both of the game's lock "seekers" empty**
    (one per loaded missile; with a lock they hold the target). Calling the game's own
    `SelectTarget` did not fill them. A ray straight down onto each reinforcement vehicle hits
    something about 6 m above it (nothing above the SAMs), so those may be parked under
    shelters until they move. The next step is reading the game's own lock code (the
    `read-game-code.py` tool, workbench section 8) for what fills a seeker.
12. Also from attempts 5 to 8: the bot broke off its attack for every missile within 4 s, even
    those predicted to miss by 500 to 1,400 m (100 breaks, 374 flares in one run). Now it breaks
    only for a missile predicted to pass within 350 m (200 m on the last 2.5 km of an attack
    run; 250 m and 120 m were tried and cost 117 health in under three minutes), and fires
    flares only for a missile predicted within 200 m (on Hard they ran out 90 s into the base
    attack). It chased Apaches at 200 to 700 m, far off the nose, for minutes; now a
    helicopter that close and that far off the nose makes it open out to 1.6 km and come back
    nose-on. When the game's lock sits on a different enemy worth at least half the chosen
    one, it fires at that one instead of holding its missiles. A plan can name what matters
    most in a mission (`focus ah64_00,zouen`: 6 times the value; adding the SAM sites made the
    bot fly low runs into their fire and was dropped). The searchlight planner now picks the
    option with the most real clearance when none stays fully dark (at 23:49 it chose "no
    dip" 280 m from a lamp and climbed into the beam it was passing under).
13. **The last run (23:44 to 00:2x, 10 attempts) with all of the above.** The canyon: caught
    once more by searchlight 01 (fixed afterwards, see 12), then cleared at the next try in
    5 minutes. The base attack: the Apaches at the landing zone now go down to single LAAM shots
    from 2 to 3 km, and **the landing team landed in 3 of the first 6 attempts, 1.5 to 2
    minutes in** ("Strider 1! Target destroyed!", "Basilisk 1. Landing now! ... This base is
    ours for the taking!"), against once in the 8 attempts before. Each time the reinforcement
    wave then could not be stopped: its vehicles never locked, and the plane was shot down
    while trying (SAM sites and AA guns at low level; on Hard the flares ran out early until
    they were rationed). A 330 m ceiling for the whole fight (to stay under the clouds) was
    tried and removed: the ceiling keeper, made for level canyon flight, pushed a plane rolling
    in a dogfight into the ground (attempt 10). A hook on the mission's `SetHudBoxAttribute` (a mission can mark a
    target "cannot be locked", a fake box, or highlighted) caught the mission highlighting our
    own transports and landing team, but no "cannot be locked" mark on the SAMs or the
    reinforcements at the start of the phase. **Mission 14 on Hard is therefore not completed
    yet**; what stops it is the lock problem in 11, which the campaign session takes on first
    because any mission with targets like these would stop the bot the same way.

## 15. The Ace campaign session, part 1: the lock problem solved (19 Oct, 00:30 onwards)

Your OK of 18 Oct (22:5x): fly the story campaign on Ace from start to finish, improving the
bot as it goes, no further input from you. First the lock problem from section 14 (finding
11), because any mission with such targets would stop the bot. All of it in the copy.

**What the game's own code says** (read from the running copy with
`tools\read-game-code.py`, section 8; two small read-only commands were added to it: `peek`
shows the bytes of one live object, `vtslot` names the function behind an object's virtual
call). A missile can only lock a target that has a lock "seeker" on it, and the seeker gets
its target in exactly three places: when a weapon is switched, when the selection changes
through the game's own `SelectTarget` (what the Tab key calls), and in a per-frame loop over
the target candidates. Each place checks the same list: the target is alive, in range and
inside the lock cone, its lock-on mark (a hidden byte at +0x6C0 in every game object, the
value a mission sets with `SetHudBoxAttribute`) is not "lock-on impossible" or "fake", it is
not a "mission special object" (`bIsMissionSpecialObject`, a readable flag the last session
did not check), and the armed weapon can lock its kind (air or ground). `SelectTarget` also
does things the bot skipped: it checks the target may be selected (mark, stealth, health),
marks it as the player's target, files it in the target history, and hands it to the first
seeker at once. Its "forced" form skips a short wait between selections; the last session's
try used the unforced form, which returns at once inside that wait, so it did nothing.

**The cause.** Since 18 Oct the bot chose its target and wrote it straight into the game's
`SelectedTarget` field. The game then shows that target as selected, but none of the work
above happens, so a seeker only came onto it if the game's own selection or its per-frame
loop happened to pick the same target. Targets close to where the game's own Tab cycle would
go (an Apache on the nose) locked; targets it never offered (SAM_2 among the others, the
reinforcements arriving behind other targets) never got a seeker, which is exactly the "both
seekers empty" seen on 18 Oct. Clouds were not the cause.

**The fix** (`main.lua`): the chosen enemy is now selected the way Tab selects: the game's
`NextTarget` is set and `SelectTarget(true)` called. If the game refuses (a target it would
never let you select), the bot logs why and only then falls back to the old direct write so it
can still aim. New readings: a target's lock-on mark is read from memory (a new read-only
call in the C++ add-on, `CoopMem_Read`, through `ReadProcessMemory` on the game's own process,
so a bad address gives nothing instead of a crash; nothing is ever written), its mission
special flag, and where its lock point sits; the "not locked" line in the log now lists each
seeker's target and state (none, detecting, started, LOCKED, in cloud, jammed). Targets the
game can never lock are left out of the choice. A new `locks` order lists every enemy with
these facts.

**The test: Mission 14 on Hard, the same plan as last night** (00:43 to 00:57; report in
`playtests\2026-10-19_0044_m14_hard-locks\`). The canyon was cleared at the first try. Then:
the six Apaches at the landing zone were all down 47 s into the base attack (last night 1.5 to
2 minutes), SAM_2, SAM_3 and SAM_4 and three AA guns by 1 min 50 s, and **the reinforcements
locked and fell**: all seven of the first wave in 76 s, five of the six of the second wave.
At 6.5 minutes the landing team was "surrounded" with zouen2_Tank_1 and the third wave (two
APCs, two AA guns) left, so the attempt failed on time, not on locks. 27 kills, 24 of them
single-missile shots, 39 damage taken. None of the 155 enemies carries a "cannot be locked"
mark or the special flag. The one APC that stayed unlocked for a while was 1.8 to 2.3 km away
with the plane inside the cloud layer, which shortens the lock range by design
(`LockonRangeReductionInCloud`).

**What it means for the campaign:** the bot can now lock whatever the game lets a player
lock. What Mission 14 still asks for is speed against ground waves: each attack run costs
about 25 s (extend to 2.6 km, turn, run in), so the next work there is shorter turnarounds and
a plane or special weapon suited to ground targets. (A first change: while flying away from a
ground target to turn round, the bot may now switch to another target ahead.)

**The story campaign, as the driver sees it** (`tools\campaign.py`, learned 01:05 to 01:45 by
walking through it once by hand, then letting the driver do it):

| Screen | What the driver does |
|---|---|
| Campaign submenu (`CampaignMenuMain_C`) | Reads the selected item from the page's description ("Play campaign mode from the beginning using your completed game data" = RESTART STORY) and presses Up until the wanted one. |
| "Do you want to reset your campaign mode progress...? Your records and all items you have obtained will be saved." (`DialogWidget_C`) | YES only when the order says restart (once). The selected option is the one drawn at full brightness (the others at 0.4), which the pilot now reports. |
| Difficulty (`CampaignMenuDifficulty_C`) | To the top, then down to ACE ("The hardest difficulty level. Designed for true aces."). |
| Movies (`CampaignMV_C`, `CampaignMvNews_C`, ...) | Escape shows "F1 SKIP", F1 skips. |
| Mission title (`CampaignMissionTitle_C`: "MISSION 01 / Charge Assault"), briefing movie (`CampaignBriefingMV_C`) | Escape until the operation map, as in a free mission (32 to 39 presses). |
| Operation map, Mission Prep, hangar | F1, then START MISSION; the plane and special weapon the mission's `mission.txt` names, found by reading the game instance's selected plane number and weapon index, which follow the cursor (Typhoon = 123), and the plane's name on the page; Sortie. |
| The mission | `playtest.py`'s attempts and retries, with the mission's plan if it has one. Story missions can start on the runway (Mission 01): the take-off is flown. |
| Replay after "mission accomplished" (`ReplayWidget_C`) | One Enter shows "PRESS Enter TO SKIP", a second while it shows skips the whole replay. |
| MISSION RESULTS (`CampaignDebriefing_C`) | F1 skips the counting, a picture of the final numbers goes into the mission's report folder, Enter. |
| MISSION COMPLETE (`CampaignMenuNext_C`: NEXT MISSION / RETRY MISSION / QUIT MISSION) | NEXT MISSION, by its description "Proceed to the next mission." |

Any screen it does not know yet is photographed into `playtests\campaign-pictures\` with
the list of visible widgets, given a few seconds, then Enter. The pilot now names any visible
`Campaign...` page even when it is not in its list.

**The copy's hangar** (your save's planes and parts carry over): A-10C, F-2A, F-14D, F-15C,
F-15J, F-15E, F-16C, F/A-18F, F-22A, F-35C, YF-23, Mirage 2000-5, Rafale M, Typhoon and more
further down; the Typhoon is fitted with parts and offers LAAM, 8AGM (eight ground-attack
missiles at once) and HCAA. The bot is tuned for the Typhoon, so it flies the Typhoon with the
LAAM against planes and the 8AGM where ground targets matter.

**Campaign results so far (Ace, story mode):**

| Mission | Result | Notes |
|---|---|---|
| 01 Charge Assault | **Completed, attempt 1**, 7.6 min | Take-off from the runway flown; 18 destroyed (9 Tu-95, 8 MiG-21, 1 Tu-160), rank A, no damage. |
| 02 Charge the Enemy | **Completed, attempt 1**, 10.5 min | 37 kills, no damage; the 8AGM armed and fired by itself at ground targets in range. |
| 03 Two-pronged Strategy | **Completed, attempt 2** | Phase 3 asks to protect a retreating friendly squadron (Gargoyle) from drones; attempt 1 failed when one was shot down ("Retreating ally has been shot down!"). Two fixes, loaded into the running attempt: enemies whose AI is chasing one of our planes now count 3.5 times, and 7 times when the chased ally carries the mission's "highlighted" lock-on mark (2), which is how the game marks allies to protect (Mission 14 marks its landing team the same way). Attempt 2 cleared the phase. Then a landing mini-game ("Mage 2, land immediately"): the game's skip only takes once the tower says "cleared for approach", so the pilot now asks for the skip every 6 s during any landing or refuelling phase. |

**Mission 04 Rescue: a stealth run between radar spheres.** "If you're spotted, the mission is
over. Stay out of enemy radar. Use of weaponry is also strictly forbidden." The bot's ordinary
fight mode climbed and was spotted within 20 s. Read from the game: 87 `SystemObjectRadarArea`
objects, 79 of them active on Ace, each a sphere of 3.5 to 10 km radius sitting on the ground.
Measured: flying at 167 m straight at the centre of a 6 km one, the plane's own
`IsInRadarArea` came on at 5.97 km, and "We've been spotted!" followed 3 s later, so there is no
getting under them; the way is around. The mission's own trigger volumes show its intended
path (`Phase01_Sect1End`, `Phase01_branch_root`, `Phase01_Sect2End`) and the end of the phase:
`Phase01_Clear_Field`, a 14 km sphere by the Space Elevator. A new planner,
`tools\route-avoid.py`, finds the shortest way that keeps 500 m outside every active sphere
(A* on a 150 m grid, then straightened), and gives it heights 110 m over the highest ground
nearby from a 200 m terrain survey (48,464 traces in 16 s, made while the retry menu was
open): 128 km. `tools\terrain-map.py` now draws radar circles (`--radar`); the picture is
`playtests\missions\m04\m04-route.png`. **Flown at the first try: 12 minutes at 110 m, 1 to
40 m off the line, never inside a radar sphere, "Trigger, the first stage of the mission is
clear."** (A time limit runs during the phase: "Five minutes remaining" came at the 10-minute
mark, with the route 85% done.)

**Your vision test 1 (Mission 04, 02:40): a surprise stunt through the Space Elevator.** As
the test director I measured the elevator's base with rays first (horizontal rays from 1.5 km
out at ten heights and eight directions): a solid base disc about 530 m across up to about
100 m, the central tower about 45 m across, support legs on two opposite sides leaning in
from 750 m out at the bottom to 150 m at 1,800 m, a ring 525 m out at 350 m height and
another 330 m out at 700 m. Between the base and the first ring, 150 to 300 m up, the space is
open to the tower. Then, without any survey for the bot, the order: fly through the point
250 m beside the tower at 220 m height, vision on (`fly to X Y Z through vision on`). The bot
saw only its own rays (a fan of 165 every 50 ms, plus walls left/right/up/down): it flew in from
12 km out, measured the base below it (165 m down) and the ring above (83 to 113 m up), the
tower 95 m to its right at the closest, and **passed 13 m from the point with no contact**. The
29 damage on the way was anti-aircraft fire, not the structure.

What went wrong next, and the fixes: 3 s after passing through, the order handed over to the
fight mode while the plane was still inside the base, and the fight mode's "ground ahead"
check (traces from 3 km above each point the plane will reach) took the ring overhead for
rising ground and pulled up into it. The checkpoint retry then crashed into the structure
during an attack run on a SAM site next to it. Now: (1) after a fly-through the bot carries
straight on with vision for 1.5 km before switching; (2) the "ground ahead" check traces a
second time from just above the predicted point when the first trace hits above it, and treats
open space with ground below as an overhang, not ground; (3) **the fight mode has the vision
layer as a safety net**: when the way it wants to fly, or its present flight path, is blocked
within 3 seconds, it takes the nearest free direction (the normal controller keeps flying); (4)
a retry that starts at a checkpoint the mission plan has no orders for now gets a plain attack
order (it had none, and the plane flew on unattended).

**Mission 04, phase 3: 15 minutes against container-launched drones.** Lost twice on time, and
each loss taught something:

- With the 8AGM left over from Mission 02 (Mission 04 had no settings file at its first sortie)
  the bot shot single standard missiles from 2 km at agile drones: 16 kills in 15 minutes from 51
  missiles. Now drones (by name) are attacked from 1.4 km, nose-on, two missiles at a time.
- The Typhoon's HCAA, read from the game: 60 damage (standard 40), turns harder (47.5 against
  40), reloads in 3.5 s, 2.5 km lock range, air targets only, not multi-lock. The bot's weapon
  logic knew only long-range, multi-lock and ground-only specials, so it would never have armed
  it; a "better air-to-air missile" rule now arms it for anything in the air within its range.
  With it: 7 drones in the first 3.6 minutes.
- A split-S into the ground (upside down at 1,080 m after a missile break, the turn logic
  pulled through the bottom): below 1,500 m above ground the bot now rolls upright before
  pulling, and starts a pull-out from a dive by the room the dive really needs (a 5 g arc at
  that speed and angle, one second to react).
- **The last drones never came within reach.** "Three remaining!" came 4 minutes in, then
  nothing: the drones that count wait inside launch containers (hidden: no HUD box, "attack
  exception" flag), and the containers themselves are mission targets with the same
  exception flag. Since 18 Oct the bot skipped every exception-flagged object (from the wrong
  first theory about Mission 14's locks), so it never went for them; the game's own Tab still
  offered the containers. Now exception-flagged targets count like any other, and when nothing
  attackable is left the bot flies to the nearest hidden mission target, which is where the
  next drones come out. With four or fewer mission targets left, everything else counts almost
  nothing. With these the drone phase was cleared ("All UAVs have been splashed!") 7 minutes in.
- **Phase 4: escort the transport carrying President Harling ("Mother Goose One")**, which the
  mission marks with the "highlighted" lock-on mark. The drones that kill it appear about 80 s
  into the phase and need 15 to 35 s; twice the bot was 20 km away chasing an unrelated drone.
  Now enemies near a highlighted ally count up to 9 times (out to 5 km, at any speed; the old rule
  counted only slow ground allies), and with an ally to protect and nothing within 8 km of it the
  bot stays with the ally. The next try cleared the escort.
- **Phase 5: 3 minutes against the Arsenal Bird's drones around the hit transport.** The first
  try ran out of time with 88 missiles for 15 kills. The numbers settled the range question:
  missiles fired at drones from 1.5 to 2.1 km were followed by the kill 12 times in 23, from
  under 1.5 km 4 times in 247 (the drones out-turn a missile fired close, so the "closer" change
  above was wrong). Now missiles at drones only from 1.3 km to lock range, the gun inside that,
  and a drone that gets close and off the nose makes the bot open out to 1.8 km and come back.
  **Mission accomplished at the next try (03:59).**

| 04 Rescue | **Completed** (second sortie, 6th attempt; 03:59) | Stealth route flown unseen twice at the first try; phase 2 crashes into the elevator's structure fixed by the vision safety net; phases 3 to 5 needed the HCAA, the drone tactics, the exception-flag fix and the escort rule (above). |
| 05 444 | **Completed** (second sortie, 1st attempt; 04:35), 6.9 min, no damage, score 16,700 | The penal squadron. Take-off flown, the "no missiles, make noise" decoy phase flown with the gun, then bombers that must not get through (below). |
| 06 Long Day | **Not completed** (25 attempts, 19 Oct 04:38-10:18) | Phase 1 needs 24,000 points in 15 minutes; best about 14,000 (below). |

**Mission 05: bombers first.** "Shoot down everything carrying bombs!" The mission fails the
moment one bomber reaches the base ("Noli 1. Delivery complete."). Attempt 1 lost because the
bot fought the escorts that were chasing the other Spare planes (the rules from Mission 03 made
those worth 5 to 20 times a bomber) while the bombers flew on, and Bandog said so: "Spare 15,
what the hell are you doing? Attack!" Now the game's own mission-target flag (TGT on the HUD)
counts 4 times, and everything else a third while any mission target is alive, unless it shot
at us or chases an ally the mission marks to protect. Attempt 2 went for the bombers, but with
the HCAA (2.5 km) a Tu-160 pulled away from 3.9 to 5.4 km while escorts forced break turns, and
bombed the base. The second sortie with the LAAM (10 km lock range, four missiles at once)
cleared it at the first attempt with no damage.

**Mission 06 Long Day, and your vision test 2 (the tunnel).** (In progress; notes in
`playtests\missions\m06\notes.md`.) The tunnel: found by its game objects
(`MES_GEN_Tunnel_11`, and `TunnelEventVolume_1`, the volume behind the game's own "in tunnel"
flag), about 25 km west of the fighting. Measured with rays from inside: a bore 1.3 km long,
35 m from floor to roof, 85 to 100 m wide, bending about 50 m sideways; flat ground for 15 km
north of it, and south of it a hill that rises 200 m in the first 750 m.

- **Try 1 (04:47), called off on the way:** the pilot had no missile defence outside the fight
  mode, and two missiles took 80 health in 20 s. Now flares (no break turns, so a route or a
  stunt keeps its line) in every mode that is not the fight.
- **Try 2 (05:00), did not go in:** 400 m out the bot judged the mouth shut and pulled up over
  the hill. The fault was in my vision design: a direction counted only as far as its
  neighbouring rays (3 to 4 degrees away) also went, as room for the wings, which at 400 m is
  25 m to each side; the 36 m mouth spans 2.5 degrees each way. Then the stunt mode fed the
  vision's own choice back in as the wanted direction, and the plane drifted into a vertical
  climb to 11.7 km. Fixed: room for the plane is now measured in metres, with four rays
  parallel to a direction (7 m to each side, 4 m up and down); the exact wanted direction is
  always a candidate; after the pass the bot wants a 17-degree climb (the roof keeps it level
  until the exit).
- **A simulator for vision, inside the game** (`tools\vision-sim.lua`, run through the pilot's
  `eval`): a simple simulated plane (fixed speed, a turn-rate limit, steering lag) flies through
  the real geometry, sensing with the real rays. Through the tunnel at 450 km/h it now passes 2 m
  from the aim point, keeps 38-47 m from the side walls and 19-21 m from roof and floor, and
  clears the hill beyond by 40 m and more; also from 30 m off the line, at 550 km/h, and with a
  slower plane. (Wanting level flight after the exit, the clearance over the hill was only 8 m.)
  Not flown for real yet.

What went wrong in the mission itself, so far: a drone shot the plane down from 200 m behind
while the bot was "opening out" (flying straight away to get missile room); with a drone on its
tail it now turns hard into it instead. Phase 1 fails on time with "You haven't done enough
damage to the base!", and my first reading of that (attack the base: the 8AGM and a plan that
puts its buildings first) was wrong: 3,480 points in 9.5 minutes. The HUD shows the real goal,
`SCORE 003480/024000`: 24,000 points in 15 minutes. The points per kill sit in every game
object (`KillBountyScore`): drones 350 (23 of them), Tu-160 bombers 1,200, a named F-14D 1,300,
fighters 220 to 550, ground targets 120 to 200. So the points are in the air. New: a "score"
mode (`fly attack score`) that weighs every enemy by its points against the time to get it,
the LAAM again, and the HUD's score line and goal in the pilot's status.

Score mode, what each try showed (all on Ace, phase 1 of Mission 06; details in the mission's
notes): with the LAAM the three Tu-160s (3,600 points) fall in the first 3 minutes, but then
the rate drops to 600-700 points a minute, against the 1,600 needed. The numbers say why: the
Typhoon reloads its two standard missiles fast enough for about 20 shots a minute, and the bot
fired 4-6, because after each ground target it flew 2.6 km out before turning back, circled
targets too close to point at, chased one F-16C for 1.5 minutes, and broke away from missiles
predicted to miss by 300 m. The 8AGM try (salvos now held until its four locks are made) left
the bombers to standard missiles and chased one out of the combat zone, which fails the mission
("Stay within the operation area!"); the plane's own "beyond the pull-out line" flag never came
on. New rules for score phases: give up on a target after 35 s and 6 missiles if its health has
stopped falling; weigh each target by the points within 1.5 km of it; loops of 1.5 km instead
of 2.6; a close target far off the nose counts as needing a loop; breaks only for missiles
within 200 m while health is above 60. In every mode now: the game's `CombatZone` box is read
at the start (Mission 06: 60 by 60 km), targets within 2 km of its edge are left alone, and
within 4 km of the edge the plane turns back in.

**Sweeps.** The next step was structural: a player does not aim the plane at one ground target
at a time; he flies through a group and shoots what comes into the cone. Now, in score phases,
the bot flies at the points-weighted middle of the targets around its choice (550 m up, a
shallow dive to no lower than 300 m), takes on that pass whichever target is nearest the nose
(within 25 degrees and 1.9 km: the standard missile locks within 2.0 km and 32.5 degrees),
points at it until the lock builds, fires one missile, takes the next, carries on 1.5 km past
the middle and turns back. The first pass that worked killed 8 targets in 30 s. Bugs found on
the way: the two pass states switched every frame at 2 km (no time between them), the pass
picked houses that have points but no HUD box and no permission to engage (missiles cannot
lock them), and picks out to 2.4 km never locked. Drones are no longer shot at with the LAAM
or from beyond 2.2 km; targets are weighed by points per second, with each kind's time to kill
learned from the bot's own kills. Results, one full 15-minute phase each: 9,000, 8,600, 9,300,
10,460, **13,310** (46 kills), 10,600.

**Where 24,000 points would come from.** A watcher (`tools\activation-watch.py`) logs every group
of enemies as the mission switches it on, with the plane's position. Phase 1 has about 30,000
points in all: area A by the start (Tu-160s, F-16s, base, about 5,000), area B (the anti-air
cluster, helicopters, then 11 drones that switch on when the plane nears their trigger sphere,
about 11,000), area C in the west (two harbours with 17 ships, Gripens, SAMs, and fighter waves
that switch on when the plane flies into spheres there, about 8,000). The large `AreaA_Add` and
`AreaB_Add` fighter waves (about 10,000 more) never switched on in phase 1, not even after the
bot hit base A; they probably belong to later phases. So 24,000 means clearing nearly
everything in all three areas in 15 minutes, close to the best a Typhoon's missiles can do (two
loaded, 5.5 s reload each). The bot had hardly been to area C; it now also weighs targets by the
points in their whole area (6 km squares), and flies the 8AGM again, whose four-target salvos
add throughput on ground groups.

**Your advice of 08:0x, and the Typhoon's parts.** (1) Throttle: in score phases the bot now
holds full throttle whenever its target is more than 2.5 km away (it used to aim for 650-1,150
km/h and tap the throttle), flies its sweep passes at 650 km/h, and uses the high-G turn for any
big turn above 500 km/h. (2) Parts: the campaign hangar (Standby > SELECT PARTS; tabs OWNED,
BODY, ARMS, MISC, EQUIPPED, changed with Q/E) listed only Queen's Custom as fitted, yet all 8
slots were full: the other 7 were multiplayer parts from your real install's
"AllPartInCampaignMode2025v2" mod, invisible and inert in the vanilla copy (the 8AGM's hangar
count of 40 against the 24 it carried in flight showed one of them was doing nothing). As you
suggested: that mod's one file (305 KB) was read from your real install's Mod Loader library
(checksums before and after identical; nothing there was written), installed into the copy's
own loader (`--game "C:\AC7-Coop-Game" --install ...`) while the copy stayed in Vanilla mode, and
deployed alone through a new copy profile "PartsOnly" (`--profile PartsOnly --vanilla off`;
Double Trigger stayed off). With it the 7 showed (Light Blisk Lv. 2, Variable Cycle Engine
Lv. 2, ECU Software Update Lv. 2, New Aileron Actuators Lv. 3, and three Lv. 2 special-weapon
parts, all "Multiplayer only"); they were taken off and the hangar left, which saved. The copy
went back to `--profile Default --vanilla on` (the parts mod stays in the copy's library,
disabled). The Typhoon now carries Queen's Custom plus seven campaign parts: standard missile
reload time, lock-on speed, lock-on range, homing and power, special-weapon reload time, and
the Onboard Self-Defense Jammer (BODY 5/34, ARMS 32/34, MISC 9/34). The hangar also needed
longer key presses (250 ms; 80 ms presses were ignored for minutes) and a fix for its Standby
page, which the driver now handles. With this loadout and the full throttle: **about 14,000
points, 53 kills, the best run** (08:41). (3) Other aircraft: a survey of the owned planes'
special weapons (F-22A QAAM/XSDB/8AAM, F-35C SOD/4AAM/8AGM, F-15E 6AAM/SFFS/TLS, F-14D
LAAM/GPB/8AAM, F/A-18F QAAM/LASM/EML, A-10C UGB/RKT/4AGM, F-2A LASM/HVAA/RKT, F-15C
SASM/4AAM/PLSL, F-15J HCAA/SAAM/QAAM, F-16C 4AAM/GPB/SASM, YF-23 HVAA/4AAM/UGB, Mirage 2000-5
GPB/4AAM/LASM, Rafale M HCAA/LACM/LAAM, F-104C SAAM/GRKT/HPAA, Typhoon LAAM/8AGM/HCAA). The
multiplayer parts were cleared from the F-22A, F-35C, F-15E and F-14D too (same procedure, one
pass) and the F-22A got campaign parts. The F-22A with the XSDB flew well (the controller needed
no changes) but made only 4,450 in 6.5 minutes: without a LAAM the three Tu-160s took 3 minutes
of chasing. Back on the Typhoon, the two gun parts (radar lock, auto-strafing) in place of
missile homing and power gave about 12,000, within the run-to-run spread.

**Vision test 2, try 3** (10:15, with the tube rays and the climb-out fix): the plane reached its
second lead point 548 m up instead of 150 m and at 875 km/h, came down steeply toward the mouth
while braking, and 380 m out swerved from a way it judged blocked into the hillside beside the
mouth. The simulator gets through from a steady approach at tunnel height; the real approach
needs a third lead point at tunnel height about 2.5 km out, flown slowly. Not done yet.

**Vision test 2, later the same day (13:34): through the tunnel.** Three more tries showed the
problem was the approach, not the vision: "fly to" lead points reach their height only at the
point itself, and the ground check on such orders kept a fixed 150 m margin over the ground ahead
(now the order's own floor decides). With the approach flown as a route along the tunnel's line
(down to 104 m and 450 km/h, 1.2 km out), **the bot flew into the bore, passed 2.5 m from the aim
point and through the whole tunnel on its rays, 38-49 m from the walls and 17-23 m from roof and
floor, and out the far end.** One flaw: it handed back to the fight mode 15 s after the aim point,
still low in the cutting beyond the exit, and scraped the ground for 24 damage; it now hands back
only once clear.

Two more changes made it repeatable. The next try hit the wall at the bend just before the far
exit, because the vision only turned when the straight-ahead way was blocked; now, between walls,
it follows the corridor (a fan of level rays finds the deepest free direction ahead, and the
wanted direction is pulled toward it), so bends are taken early. And the lead-in waits until the
bot has fought off the start area's fighters. **Try 10 (14:02): in 1.6 m from the aim point, 10.5 s
through the whole bore, out at 113 m and away**, with one 24-point scrape at that last bend (9 m
from the wall). Your Mission 06 tunnel test is passed, with that one scrape to iron out.
Mission 06 itself: about 12,200 at best in this round (the score race is unchanged at about
12,000-14,000).

**Where the campaign stands (19 Oct 10:20, session stopped):** Missions 01-05 completed on Ace;
Mission 06 not (best 14,000 of the 24,000 points phase 1 needs, after about 6 hours and 25
attempts). The copy is closed, back in Vanilla mode with its Default profile (Double Trigger
off), your real saves and real install unchanged.

Two mistakes of mine cost two restarts of the copy, and changed how I work: (1) UE4SS's
"restart all mods" (Ctrl+P), used to load new script code, crashed the game in mid-mission at
04:53 (it had worked about ten times before); code now goes in only at a restart of the copy,
and a new `module vision` / `module route` order reloads just those files without touching the
other mods. (2) An `eval` that read every property of the mission object hung the pilot's
script at 05:14; such probes now get a narrower target. Your real saves were checked after
each (unchanged).

## 16. Kill chaining: the lane planner, and your aggression advice (19 Oct, 15:50 onwards)

The plan agreed with you that morning (`playtests\missions\m06\score-race-plan.md`), with your
rule first: the bot is a test tool for people testing their own changes to the game, so
everything has to work from what the game shows at the time, not from notes about one level.

**What changed in how it fights**

- **It flies for the cone, not at the target.** Twice a second the bot tries 21 manoeuvres
  (straight on, turns of 15 to 179 degrees each way, "run out, then turn back"), flies each 12
  seconds ahead in a small model of itself (its measured turn rate, how fast it rolls, its
  current bank) and of its missile (the lock cone and range the game reports, the lock time and
  reload it has measured on itself), and takes the one that brings the most points into the lock
  cone. The target is then simply whatever sits in the cone nearest the nose; right after each
  launch the next one is selected, so its lock builds while the first missile flies. No dives,
  no set-up runs. (`lanes.lua`; the "lanes".)
- **A simulator tuned it on many layouts, not this one** (`tools\lane-sim.py`): clusters, rows,
  scattered targets, a ring round a base, harbours, mixtures, each with a different plane and
  missile. Against the old way it killed 10.1 targets a minute instead of 6.1 and cleared 93% of
  a group in 3 minutes instead of 65%.
- **It reads more from the game.** Score mode switches itself on when the HUD shows a score goal
  (the mission plan no longer has to say so). What kind of enemy something is comes from the
  game's own class tree (plane, helicopter, ground vehicle), its large-plane flag and its numbers
  (the drones have the lowest top speed of any plane); a class that keeps dodging missiles is
  learned as agile. Its own missiles are followed to the end, so it learns from what range a
  weapon still hits.
- **Steering faults found and fixed** (they were there before the lanes too: your best run of
  the morning spent 69% of its time in hard turns and pulled in only 36% of that): a target
  behind or a little below the nose made it roll from wing to wing without pulling; hard turns
  always climbed, so it fought a kilometre above its targets; full throttle in a dive reached
  1,980 km/h where it can barely turn. Now it banks to the turn and pulls at once, uses the
  high-G turn on every big turn, brakes into a turn above 850 km/h, and slices down through its
  turns when it is too high.
- **Your advice while watching** ("more aggression and risk taking", "a defensive attack",
  "the tightest possible turn ... at maximum speed and ferocity", "neutralize the biggest
  threats first", "bombers over AA guns"): it no longer breaks off for a missile while it has
  something to attack; it keeps attacking, turned up to 35 degrees across the missile's line
  with the high-G turn and flares, and only dodges hard at the last instant or when badly hurt.
  It accelerates at full throttle toward a group until 5 km out. Anything that has fired a
  missile at it in the last minute (fighters, SAM sites, attack helicopters) is worth two and a
  half times its points, a plane chasing it twice; anti-aircraft guns count only their points.
  It leaves a place once the points it really scores there drop, for the next group.
- **Numbers in every report** (`tools\run-stats.py`, built into the report): where the time
  went, frame by frame (locked, target ahead, target off the nose, defending, breaking, transit);
  kills a minute; kills and points by kind; locks and their time; chained picks; how its own
  missiles did by range; the planner's promises against what it delivered; what it learned
  about itself; a steering summary; the HUD score every 30 seconds; and which enemies the
  mission switched on, when and where.

**What it scored** (phase 1 of Mission 06 on Ace, 24,000 points needed in 15 minutes; the
morning's best was about 14,000 with 3.4 kills a minute):

| Run | Points | Kills a minute (while engaged) | Locked | What it showed |
|---|---|---|---|---|
| First 8.5 minutes, tests 1-7 | 7,670 -> 10,230 at 8.5 min | 2.8 -> 4.7 (6.2) | 16% -> 28% | Each test found a fault (details in the Mission 06 notes); the morning's best had about 8,050 at that point. |
| Full phase 1 | 13,030 | 3.8 (4.7) | 19% | 12,010 at 10.5 minutes, then stuck four minutes in an anti-aircraft site; never went to the third area (about 8,600 points there). |
| Full phase 4 (aggressive) | 12,870, shot down at 8:43 | **6.4 (7.3)** | 25% | The pace 24,000 needs (9,330 at 5 minutes), but two missile hits from F-16s and gun chip damage. |
| Full phase 6 | 13,360, shot down at 14:30 | 4.5 (5.2) | 18% | Stayed 10.7 minutes in the second area; chose the third in the last minute. |
| Full phase 7 (fighters forced first) | 750 at 4 minutes, stopped | | | Four F-16s in a turning fight: it hits them when it fires (8 of 8) but rarely gets the shot; reverted to weighting them as threats. |
| Full phase 8 (final balance) | 10,710, shot down at 13:20 | 3.9 (4.8) | 24% | One F-16 missile hit, then 58 points of gun chip damage over the anti-aircraft sites. |
| 8AGM experiment | 4,280 at 5 minutes, stopped | 5.2 (8.9) | 12% | The best kill rate while engaged, but nearly every salvo went at one lock and only one bomber fell without the LAAM. |

Two bugs of mine on the way: a variable used one line before it was defined stopped the flight
loop and the plane crashed (the pilot now keeps flying through its own script errors, keys let
go and the error logged), and a first "learned agility" rule called the Tu-160 bomber a drone.
And one old bug found: the check "is this enemy chasing me" compared a short name with a full
one, so it had never been true since 18 Oct.

**Where Mission 06 stands:** not cleared, and so the story campaign is still stopped there (it
cannot skip a mission). The bot now kills almost twice as fast as this morning while it is
engaged, but over a whole phase it lands at the same 13,000-13,400, or is shot down: four F-16s
near the start put one or two missiles into it in most runs, and the anti-aircraft sites add a
steady trickle of damage that the more aggressive flying runs into. The run at your aggressive
settings had exactly the pace 24,000 needs for five minutes, then died. What is next, in order:
survive the F-16s (kill them with the LAAM before they turn in), close the gap between what the
planner promises and what the plane flies, reach the third area by about 9 minutes, and try the
8AGM as a second ground weapon. All runs, numbers and reasons: `playtests\missions\m06\notes.md`.
**Found afterwards, when you asked why it lags a human player:** the bot runs out of missiles. It
carries 112 standard missiles and used 1.6 to 2.3 per kill with almost no gun kills, so in every full
phase they ran low between minute 10 and 11.5 and the score stopped climbing; that is the 13,000
ceiling. A human uses about one missile per kill, the gun on trucks and guns, and a special weapon
suited to the ground targets. The analysis and the revised order of next steps (ammunition first):
`playtests\missions\m06\gap-analysis.md`. Reports now show the ammunition.
Your real saves were checked after every run (unchanged); the copy is closed, still in Vanilla
mode with its Default profile (the Mod Loader was not used).



## 17. The missiles were wasted, not too few (19-20 Oct, 19:30 onwards)

The gap analysis of section 16 said the bot ran out of its 112 standard missiles by minute 10-11.5
of Mission 06's score race. This session followed its order (ammunition first, then the opening
F-16s, then reaching the third area in time) and found that most of the "shortage" was waste the
bot could not see, because its missile tracker missed more than half its own missiles.

**What was wrong, in plain words**

- **A quarter of the standard missiles flew unguided.** In the lanes the bot chose its next
  target in the same instant it pressed fire, while the fire key was still down, so the game
  launched at the new target, which was not locked yet. Now the selection stays a quarter of a
  second after each press. Since then: none unguided.
- **Many of the rest hit the scenery.** With every missile followed, the misses turned out to end
  about 2 seconds out, short of the target, mostly from 1.6-2.2 km at a shallow angle. The bot now
  checks the line to the target with one ray trace before every shot (the fast traces of the C++
  add-on) and holds fire while terrain or a building is in the way. LAAMs fired at the bombers
  from 5-9 km had been flying into a hill 2.7 km in front of them. Standard missiles at ground
  targets went from about 60% hits to 92 of 94 and 72 of 73.
- **The missile tracker** missed more than half the bot's own missiles because the game reuses
  missile objects; it now notices a missile stopping (ended) and moving again (fired again).
- **One missile in the air per target is enough** when one kills it (missile discipline), and the
  LAAM goes first at anything in the air, the standard missiles kept for the ground.
- **A latent fault**: the "learned agility" rule counted fire presses, not missiles that flew, and
  twice made the F-16 count as a drone (fought by opening out, the LAAM withheld). It now uses the
  tracker's real outcomes.

**The gun** (your plan's first item): measured with a new `guntest` order and by following the
bot's own bullets, which are game objects. The bullets passed about 15 m above and 10 m right of
the target at 700-900 m; a correction learned from those passes centred them, and the gun then
made 5 kills in one phase (an F-16 among them). Useful in passing, not a main weapon. Houses and
other buildings without a target box never died in any run; not counted on.

**The opening F-16s**: an "air shot in passing" (an enemy plane in the LAAM's cone and range gets
one LAAM while the lanes fly on) killed all four by 4.6 minutes in the first run that had it, and
the opening has cost little health since.

**Result: from about 13,000 to about 22,000 points.** Two full phases with the fixed build made
21,900 and 21,990 (109 and 101 kills, 10 and 9 kills a minute while engaged, one missile per
kill; the earlier best was 13,360). You watched the end of the first and said it was the biggest
leap of the day.

**The last 2,000 points** went into finding where the remaining time is lost:

- Area B pays most between minutes 3 and 5; the bot stayed until minute 8-9, while area C, once
  reached, paid 1,000-1,400 points a minute. The way the bot judges "move on" was improved three
  times (a fresh area judged at the pace of its best minute, the "stay" rate corrected by how
  optimistic its own plans have been, a move kept through a short air fight), with mixed results.
- Watching, you saw it "indecisive" in the dogfights over area C and asked it to commit to the
  aircraft attacking it. The logs agreed (in its last minute 8 switches between ground and air
  targets, air shots that never fired, 10 full break turns). A committed "furball" target was
  added; first for any plane tracking it, which in three attempts cost area C's ground passes
  (3,900 points there against 6,850) without saving health; then narrowed to an aircraft that has
  fired at it from within 2.5 km in the last 15 seconds, the dogfight you described.
- Two more faults found on the way: a "ping-pong" between nearby groups (a move ended 6 km out, the
  plane drifted to 6.1 km and the move began again, seven times in 2.3 minutes; a place just
  arrived at is now not a destination for a minute), and drones out-rating the ground passes
  because they carried the bonus for having fired at the plane, while the bot could not kill them
  well (inside the missiles' minimum for drones and outside the gun's narrow window). Drones now
  count their plain points, and the gun has a wider window for them close in.

- **The leaving rule** (from foraging theory): leave a place once its last minute paid under half
  of the fight's average, for the best substantial group elsewhere, and keep going until there.
  The second area pays about 2,000 points a minute for two minutes and much less after; the rule
  moves the plane on at the right time. With it: 23,000 and 23,200 in two attempts (19,500-21,500
  in others), 800 short of the goal at best. Also fixed on the way: kills after a restart from a
  checkpoint were not counted (the enemies come back with the same names), which threw off every
  retry's rates.

**The early morning (05:00-06:30)**, four more general changes, each from one attempt's data:

- A bomber already hit counts as nearly dead: the bot now reads an aircraft's health from the game
  and rates a hurt one as quicker to finish. Before, it twice left the first area with two
  bombers (2,400 points) still flying; since, all three fell in every attempt.
- The missile economy had been too careful: every attempt ended with 11-51 unused missiles. Now
  they run out with the time (3-10 left), so the phase is limited by missiles and minutes together.
- A drone chasing the plane no longer holds it in a fight: one attempt fought the drone swarm for
  4.5 minutes at about 700 points a minute while a 3,050-point ground group waited 7 km away.
- LAAMs left over late in the phase are now spent on any aircraft in reach (one attempt ended with
  11 unused).

**Mission 06 cleared** (20 Oct, 09:26): 24,480 of 24,000, rank A, on the first attempt of the build
that had your two suggestions from the morning, then on to Mission 07 by itself.

- **Vertical attacks** (yours: a target "directly or almost directly beneath", a loop or a
  split-S onto it). The bot's planner only knew flat turns, and its controller flattened any aim
  behind the plane; it now also tries diving straight onto close targets below and pulling up and
  over onto ones behind, counting the shots each would give, and flies the best. While diving it
  launched 14-18 missiles a minute against about 9 otherwise. Two crashes on the way taught it the
  pull-out the shorter way (keep pulling through, as a split-S ends), to trace the ground along the
  pull-out, and that straight down needs 450 m of air and a target really below.
- **The return line** (you asked whether it knew): it did not. Explored by hand in the copy: Esc
  skips the landing, Enter keeps the special weapon, YES takes off, Esc skips the take-off, and the
  phase clock stands still the whole time, so a resupply costs only the flight. The bot now goes when
  its own firing rate says the missiles (or the LAAMs, with aircraft still flying) will run out
  well before the end, or when badly hurt. The clearing attempt used exactly its 112 missiles and
  did not need it; later missions may.
- The copy's graphics are turned down (your request): quality settings low, 60 fps cap, same
  resolution; only the copy's own settings file, re-applied at every restart.

**Mission 07 First Contact** (20 Oct, 09:29-10:06): not cleared in six attempts. It is a terrain
mission: radar and SAM sites in canyons among rock pillars and cliffs rising into a cloud base of
about 820-870 m, in rain. Four attempts ended against rock within 73-169 seconds. Three general
changes helped (slowing to 550 km/h near obstacles the vision net reports; not keeping under the
cloud base among them; not running in at a target with rock in the line, and coming back from
above); one attempt then lived 3.6 minutes with no damage to speak of. What is still missing (in
`playtests\missions\m07\notes.md`): turning away from walls too tall to climb, cruising above
the highest ground around rather than above the ground directly below, and steep attacks from
above on canyon targets outside score races. The session stopped there: the copy is closed, the
IN-USE note removed, and your real saves were checked after every run (unchanged).

**Where it stood before that** (20 Oct, 06:30): not cleared yet; best 23,200 of 24,000; this morning's attempts
19,620-22,000. Now that the missiles and the minutes run out together, about 25,500 points is
the most this loadout could make with nothing wasted, so 24,000 needs a nearly perfect phase. One
attempt swings by about 2,000 with the order the fights come in. The campaign order is retrying
Mission 06 by itself. Full numbers for every run are in `playtests\missions\m06\notes.md`. Your
real saves were checked after every run (unchanged); the copy stays in Vanilla mode with its
Default profile (the Mod Loader was not used).

## 18. Mission 07: knowing the plane, the ground and where to attack from (20 Oct, 10:20 onwards)

You asked for general improvement to the bot's pathfinding, manoeuvring, knowledge of its own
aircraft and how to use it, decision making and decisiveness, with Mission 07 as the test, and
for the generalised capabilities to be kept. Everything below reads the ground, the targets and
the plane from the game and the bot's own logs; nothing is written for Mission 07.

- **The plane, measured** (`tools\aircraft-model.py`, `playtests\aircraft\typhoon.json`, from 145
  flight logs): the flight path turns 37-43 degrees a second with a full pull at any speed from
  300 to 1,600 km/h, so the turn radius grows with speed (about 400 m at 850 km/h, 650 m at
  1,150); the roll is about 70 degrees a second typical, 130 at full stick; the throttle adds
  about 45 m/s each second at 600-1,200 km/h; the brake takes off 46-130 m/s each second held
  level (more the faster), but in a 30-60 degree dive it only holds the speed, so a steep dive is
  flown at the speed it starts with.
- **The manoeuvre planner** (`maneuver.lua`): four times a second the way the pilot wants to fly
  is flown ahead 5 seconds in that model and traced against the real ground with the engine's
  own line traces; if it would hit, or end where no pull-out is possible, about 50 other
  manoeuvres are tried the same way and the safe one closest to the wanted way is flown, held
  1.5 s (decisiveness: you had seen it hesitate at walls and in furballs). Over Mission 07's
  surveyed ground, in a wargame of two-minute attack flights (`tools\maneuver-sim.py`), 92% of
  flights crashed with no safety layer, 64% with the old straight-ray net, and about 1% with the
  planner, with more shots a minute.
- **Attack lines** (`approach.lua`): before attacking a ground target the bot works out where it
  can be seen from (rays out of the target in 16 directions at 10-80 degrees), picks the line it
  can be on soonest from its own turn rate and speed, flies onto it from outside and down it to the
  shot, and repositions out along it when it ends up inside; a target already in sight ahead is
  attacked from where the plane is. In the wargame over ten-minute flights at Mission 07's 17
  ground targets: 3.1-3.25 shots a minute against 1.1 for the entry-point runs it replaces. Two
  crash types the wargame found, and fixed: a turn back toward an aim behind the plane became a
  split-S (now a level turn toward its side), and the turn onto a line below is kept nearly level.
- **What you said while watching, built in**: a missile is met with the smallest change of the
  attack that it misses by, worked out in a flown-ahead model of it, and grown only while it is
  coming, so the attack is back on as soon as it passes; when dodged missiles still hit too often
  every dodge widens by 2.5% at a time, and only damage that a dodged missile really caused counts
  (not gunfire, lightning or a scrape). Your point that the bot looks into the distance and the sky
  where a player keeps the nose on the objective, and plays too safe: the long reposition legs
  out along a line are a tight turn back now, a target nearly straight below is dived at rather
  than circled (one attempt circled one for 160 s), the obstacle speed cap lasts 4 s instead of
  20, full throttle to anything far ahead in any fight, no full break for a missile a small dodge
  clears. Tried and taken back, with reasons in `playtests\missions\m07\notes.md`: a lower ground
  margin (a rock pillar the survey had smoothed away), a longer aim point onto lines, and weighting
  UAVs by how close they were to the plane they chased (it made the bot switch among far ones).
- **Shooting and decisions**: a lock the game offers on another ground enemy in reach is taken
  (the game would not select a SAM site in a canyon, but locked the AA gun beside it); misses at
  every range no longer narrow the missile's range (the cap had fallen to 1.3 km and the bot held
  fire at Mihaly for six minutes; then a learned minimum of 2.2 km sat above a 2 km cap, so it
  could not fire at all while locked on him); an enemy chasing an ally that is losing health counts four times; a close drone being
  opened out from stays the target.
- **Mission 07** (attempts and numbers in the notes): phase 1 (the four SAM and three radar sites
  in 10 minutes) went from 545 s with 72 health this morning to 531, 355, 474, 358 and 183 s at full
  health in the afternoon's builds; phase 2 (UAVs on the recon team, none to be lost) failed six
  times in a row while the target choice was being worked out, then was cleared in 347 s with no
  recon plane lost; phase 3 (the ace Mihaly in his Su-30SM) was cleared once the range limits no
  longer stopped it firing: he broke off after losing 120 of his 320 health. **Mission 07
  completed** at 13:38 on the first attempt of that build (22 minutes), and the campaign order went
  on to Mission 08 by itself.
- **Mission 08 Pipeline Destruction** (a score race: 22,000 points in about 5 minutes over oil
  tanks, facilities and four 500-point tankers; notes in `playtests\missions\m08\notes.md`), a
  mission the bot had never seen: 16,050 and 15,150 with the LAAM (time short, 50 missiles left),
  then with the 8AGM (`playtests\missions\m08\mission.txt`; the Typhoon's multi-target ground
  missile, the best engaged kill rate of Mission 06's tests) 21,750 (250 short), 19,370, 18,570,
  18,600, 21,490, 21,140 and then **22,690: phase 1 cleared** at 14:37.
  90 launches in 300 s is about what the two weapons' reloads allow, so the rest has to
  come from points per missile, and a finding there: of the 21,750 only 12,200 were the bot's own
  kills, 9,550 were tanks its hits set off. The pilot now learns per class of target what dies
  with a kill (points per neighbour within 400 m) and counts it in the lanes' values. Phase 2
  (fuel trucks escaping on split routes in a sandstorm, 10 minutes) failed on its first try: 7 of
  22 trucks, and the "take the game's lock" rule flip-flopped 143 times (now only for a target the
  game will not select, at most once in 5 s); on the second the plane was lost 6.5 minutes in,
  most likely colliding with a UAV it was chasing.
- **Next steps**: Mission 08's score phase was cleared twice in eleven tries (22,690 and 22,940); the clearest loss is
  the fighter rule (commit to aircraft after the plane, your Mission 06 advice), which in a score
  phase held the plane 90 s on F-15Cs for 850 points while the lanes' targets paid two to three
  times as much a second; weighing that commitment on points a second unless the plane's survival
  is at stake is the first thing to try. Then the endgame of a score phase (single high-value
  targets a few km off once the area near the plane is worked out), and phase 2's trucks. The
  wargame (`tools\maneuver-sim.py`) is good for terrain and approach geometry but smooths thin
  rock pillars away: margins it suggests need a live check.

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
4. **Addendum of 18 Oct 2026** (README, "Addendum"): reading the running copy's code in
   memory for analysis is allowed, and so is building a C++ add-on for UE4SS with the
   developer tools that needs. A full unscrambled exe on disk, sharing it, and changing
   the game's own checks stay off limits. Only one copy can usefully run at a time, so
   a session that is driving the copy leaves an `IN-USE-game-copy.md` note in the
   shared side-session notes folder and removes it when done; other sessions wait.

## Must-do before step 1

- **Own save folder for the copy: done and proved** (section 4).
- **Two copies at once:** can't be made to work with a script (section 6): the second
  copy never gets a working link to Steam and dies on its first use of Steam networking.
  Network tests need a second PC.
- plan.md's step 0 test 4 (developer commands offline, such as `SNL_ArrangeWindows`):
  answered without a run. The commands are empty leftovers in this build (section 6).
