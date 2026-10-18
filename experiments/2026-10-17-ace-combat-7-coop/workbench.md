# Workbench (step 0): what was set up and what the tests showed

Done 17 Oct 2026, 20:50 to 22:15, with you watching the game windows.

## Short version

| Test | Result |
|---|---|
| Copy of the game made and checked | **Yes.** `C:\AC7-Coop-Game`, 133 files, 65.7 GB. `Ace7Game.exe`'s SHA-256 matches [identity.md](identity.md) exactly. |
| 1. Does the copy start from its own folder? | **Yes, but only when started the way Steam starts games.** Started plainly, it hands itself to Steam and Steam starts your *real* install. With Steam's app label set for that one launch, the copy itself runs and reaches the main menu. |
| 2. Can two copies run at once? | **Not yet.** Both start and reach the title screen, but the second one crashed when it tried to create save data. |
| 3. Does UE4SS load, open its console and write the object dump? | **Yes, all three.** It found Unreal Engine 4.18 within a second; the console opened; the dump (the game's catalogue of classes and functions) is 30.9 MB. |

## What's where

| Thing | Where |
|---|---|
| The plain game copy (no mods, no Mod Loader) | `C:\AC7-Coop-Game` |
| UE4SS (PM-UE4SS-ZR1903), in the copy only | `C:\AC7-Coop-Game\dwmapi.dll` and `C:\AC7-Coop-Game\ue4ss\` |
| The download, kept as it came | `downloads\PM-UE4SS-ZR1903\` (zip, SHA-256 `8a9574f8c0ddd79b709213547f4ac4d927c14cf0d02be2c503ac9885aa096f13`, same as GitHub shows) |
| Save backups, one per test run | `backups\<date_time>\` |
| The earlier Mod Loader and mission-script tools | `inherited\` (see [inherited/LEFT-OUT.md](inherited/LEFT-OUT.md)) |
| Object dump and UE4SS log from the test | `dumps\2026-10-17_ue4ss-title-screen\` |
| The second copy's crash dump | `dumps\2026-10-17_second-copy-crash\` |
| Back up saves | `tools\backup-saves.ps1` |
| Start the copy (backs up saves first) | `tools\start-copy.ps1` |

To start the copy yourself: open Steam, then in PowerShell run

```
powershell -NoProfile -File "C:\Users\Matth\Claude Apps\AC7-Coop\tools\start-copy.ps1"
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
  chose" below).

## Test 2: can two copies run at once?

- The second copy started fine while the first sat at the main menu. Both used about 1 GB
  of memory and Steam accepted both.
- When you pressed Enter on the second one's title screen, it said it was creating save
  data, wrote a **new** save file in the wrong place (`SaveGames\ACE7Save.sav`, outside
  your Steam-ID folder), and two seconds later crashed (a memory error inside the game,
  22:02:23). Steam's overlay also kept restarting for it.
- Likely reason: Steam gives your account to the first copy only, so the second one
  doesn't know who you are and thinks it has no save. Both copies also share one save
  folder.
- **What it means:** two copies on this PC aren't usable yet. Ideas to try later: give the
  second copy its own save folder (for example through UE4SS), or stop it from loading a
  save at all. Until then, network tests between two copies here can't go past the title
  screen.

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

## Your saves: what happened

- Before every launch your save folder was backed up and checked (`backups\`, five
  backups today).
- **The copy shares your real save folder.** When I quit the copy through its menu
  ("Save and end your current game", 22:05), it rewrote your real save, and Steam Cloud
  uploaded it. The save is encrypted, so I couldn't see what changed; it was 11.5 KB
  smaller. With your OK I put the original back (the 10 Oct file, checksum matches this
  morning's backup). Steam will upload the restored file the next time your real game
  closes. The copy-written version is kept in `backups\2026-10-17_2206\`.
- Staying on the title screen and closing from there didn't touch the save. The game
  ignores the window's X and Escape at the title screen, so I ended the process instead.
  Nothing is loaded at that point.

## Left as you chose

- **Windowed mode** is still on (1600×900 windowed instead of 1920×1080 full screen), so
  your real game will also open in a window. To undo it, set full screen in the game's
  Options, or ask me to copy `Config\GameUserSettings.ini` back from
  `backups\2026-10-17_2133\`.
- `Config\Engine.ini` has a block the game added that turns off the Sticky Keys shortcut.
  Harmless; the original is in the same backup.
- The stray save the crashed second copy made (`SaveGames\ACE7Save.sav`, not in your
  Steam-ID folder, not synced by Steam Cloud) is still there.

## Rules for test runs from now on

1. Steam open, then start the copy with `tools\start-copy.ps1` (it backs up saves first).
2. Stay on the title screen unless a test needs more. Past it, the copy loads your real
   save and rewrites it when you quit. If a test has to go further, restore the save from
   that run's backup afterwards.
3. One copy at a time until the second-copy crash is solved.

## Must-do before step 1

- **Give the copy its own save folder**, so it can never write your real save and so two
  copies stop fighting over one. This also needs solving for two copies on one PC.
- Not tried yet: plan.md's step 0 test 4 (try a few developer commands offline, such as
  `SNL_ArrangeWindows`). UE4SS can now reach them.
