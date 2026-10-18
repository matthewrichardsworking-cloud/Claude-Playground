---
kind: game
title: UE4SS Lua test pilot and a puppet plane for co-op groundwork
game: 'ACE COMBAT 7: SKIES UNKNOWN'
games_also: []
game_version: 'Steam build 9855922, game 2.2.1.16, Unreal Engine 4.18.2'
platform: windows
engine: unreal
route: loader-api
tools: ['UE4SS (PM-UE4SS-ZR1903, Playmore build of UE4SS commit 48e7edfe)', 'MSVC 14.44 + Windows SDK', 'Python 3 + capstone 5.0.9', 'PowerShell']
anti_cheat: 'No third-party anti-cheat; the game runs its own cheat checks in online matches. Everything here stayed offline, in a separate copy of the game.'
status: in-progress
agents:
- Claude Code
humans: []
date: '2026-10-18'
links: []
tags: [ue4ss, ue4-18, steamstub, puppet-plane, playtest-bot, save-isolation, second-instance, cpp-mod, keyboard-input]
---
# UE4SS Lua test pilot and a puppet plane for co-op groundwork

> Groundwork for two-player co-op in Ace Combat 7, done in a plain copy of the game with UE4SS. A Lua
> "pilot" flies and fights by itself and completed Mission 01 (Casual and Ace) and Mission 02 (Hard) with no
> damage; an AI plane can be made to fly a recorded or live-streamed flight path to within a few centimetres;
> a small C++ UE4SS add-on gives Lua a UDP socket. Two copies of the game on one PC don't work (no Steam
> identity for the second). All verified in the running game; co-op itself is not built.

## Setup
- Steam, app 502500, build 9855922, game version 2.2.1.16, Unreal Engine 4.18.2, Windows 11.
- The main program is `Ace7Game.exe` in the game's top folder. There is no `Binaries\Win64\*-Shipping.exe`,
  so tools that look for one (including `um scan` at commit 6a8865ae) report Unreal with no version.
- 12 encrypted `.pak` files, pak format version 4. Steamworks SDK 1.39.
- UE4SS: Playmore's AC7 build `PM-UE4SS-ZR1903` from GitHub, which is the public UE4SS repository's commit
  48e7edfe (1 Feb 2026). Installed as `dwmapi.dll` plus `ue4ss\` in a full copy of the game folder, never in the
  real install.
- For the C++ add-on: MSVC 14.44 and a Windows SDK in a plain folder (no admin installer), compiled against
  that UE4SS commit's headers and linked against the copy's own `UE4SS.dll` through an import library made
  from its export list. The documented UE4SS C++ build needs a private Unreal-headers repository and Rust;
  this sidesteps both.

## Route and why
`loader-api`: UE4SS Lua for game logic, a C++ UE4SS add-on where Lua can't reach (sockets, keyboard input
from inside the process). The exe's code section is scrambled on disk by Steam's DRM wrapper (SteamStub,
the `.bind` section), so a decompiler can't read the file, and unscrambling it is off limits. Everything was
learned from the running game instead: UE4SS object dumps for class and function names, and a read-only
process reader for the few places where the reflected names weren't enough. The game's own online mode
(player-hosted, peer to peer over Steam) was set aside as the hardest route; a third-party co-op mod that
does take that route was released while this work was going on.

## How the game works (what we had to learn)
- Game module "Nimbus". Useful reflected classes: `PlayerPlane`, `PlayerWeaponActivator` (missile, gun and
  flare press functions), `TargetSelectionComponent:SelectTarget`, `Mission` (completed / failed / score, and
  can skip mini-games), `NimbusGameInstance` (`SetMissionID`, `SetPlaneAndSWP`). Enemy and ally are told apart
  with the game's own `GetFaction` and `IsTGT`.
- An AI plane can be turned into a puppet: `SetBehaviorActive(false)` switches its AI off and `K2_TeleportTo`
  moves it every frame. `SetFELocationAndRotation` does nothing visible. A plane the mission hasn't activated
  can be switched on with `SetActive` and used.
- Between frames the puppet's own flight model carries it forward, so each frame only corrects a little.
  Matching its speed to the recording cut the per-frame correction from about 50 units to 0.2.
- The reported altitude is height above the sea, not above the ground; terrain clearance needs a line trace.
- The online layer ("SNL") sends its messages as Steam P2P packets. The lobby marks the host with member data
  `SNL_P2P_HOST`.
- The `SNL_*` and save-switch developer commands on the cheat manager are empty in this build: 215 of 494
  commands point at the same do-nothing function.
- Saves and settings live under the user's Local AppData folder (`BANDAI NAMCO Entertainment\ACE COMBAT 7`),
  found by asking Windows for that folder at runtime.

## Build steps
1. Copy the whole game folder somewhere else and check the exe's SHA-256 against the original.
2. Install UE4SS into the copy only (`dwmapi.dll` + `ue4ss\`).
3. Start the copy with `SteamAppId=502500` set in the environment of the launch, and with the game process's
   user-profile folder pointed at a folder inside the copy, so it gets its own saves (see gotchas 1 and 3).
4. Lua mods go in `ue4ss\Mods\<Name>\Scripts\main.lua`, listed in `mods.txt`.

## Verification
- The pilot completed Mission 01 Casual from a cold start, menus included, at the first attempt (20 kills, no
  damage, score 12,400), then Mission 01 Ace and Mission 02 Hard (14.9 min, 43 kills, no damage, 6 of 6
  missiles fired at it lost their lock). The oracle is the game's own `Mission` object reporting completion
  plus the event log the pilot writes.
- Puppet: a 32-second recording replayed with the puppet held to the unit; from live UDP packets at 90 fps it
  was trimmed 1 to 2 units (10 to 20 cm) per frame, 100 ms behind the feed. Packets reach Lua 1 to 24 ms after
  sending.
- Save isolation: SHA-256 of every file in the real save folder compared before and after each run.
- Not verified: anything with two players, Steam Cloud behaviour beyond the runs above, other game builds.

## Gotchas
1. **Started directly, the copy hands off to Steam, which starts the real install.** **Cause:** the exe asks
   Steam to relaunch it. **Fix:** set `SteamAppId=502500` in the environment of the launch (what Steam itself
   does).
2. **`-windowed` and `-UserDir=` do nothing.** **Cause:** this game ignores them. **Fix:** don't rely on
   command-line switches; change the process environment instead.
3. **The copy rewrote the real save.** **Cause:** the save folder comes from Windows' Local AppData lookup,
   shared by both installs. **Fix:** start the game process with its user-profile folder pointed inside the
   copy; it then creates and uses its own `AppData\Local\...` there. Steam Cloud still syncs the real save
   whenever anything labelled app 502500 exits, so keep a backup anyway.
4. **A second copy crashes on the title screen.** **Cause:** `SteamAPI_Init` fails in a second process, the
   game's socket code then reads through a null `ISteamNetworking` pointer. No script can fix this. **Fix:** use
   a second PC for two-player tests.
5. **Writing the plane's `InputPitch`/`InputRoll`/`InputThrottle` does nothing.** **Cause:** rewritten every
   frame from the real input. **Fix:** press keyboard keys from inside the process (C++ add-on), with a watchdog
   that lets go.
6. **A stand-in `xinput1_3.dll` gamepad never reaches the game.** **Cause:** Steam's overlay answers gamepad
   reads itself. **Fix:** keyboard input from inside the process (gotcha 5).
7. **The game pauses whenever its window loses focus.** **Fix:** only send input while the game window is in
   front, and expect timers to stop when it isn't.
8. **The game crashed three seconds in with a UE4SS `LoopAsync` timer and game hooks in one script.**
   **Cause:** `LoopAsync` runs the script on a second thread while hooks run it on the game thread, with no
   lock between them. **Fix:** run everything on the game thread (`LoopInGameThreadWithDelay`); no crash in
   about 90 minutes of flying after that.
9. **`GetTimeSeconds` cost about 20 ms per call from Lua, and after a Ctrl+P reload inside a mission it stood
   still.** A script reading it once per packet dropped to 10 frames a second. **Fix:** pace live code with
   `os.clock`.
10. **The pilot scraped hills and crashed.** **Cause:** altitude is above sea level (see above). **Fix:** line
    trace to the ground.
11. **Ground targets couldn't be selected.** **Cause:** with the air-only LAAM special weapon armed, the game
    hides ground targets from selection. **Fix:** go back to standard missiles when nothing is selectable, and
    don't arm the LAAM when ground targets are the job.
12. **The menu runner got lost in the Campaign submenu.** **Cause:** it opens on the story save's "Continue".
    **Fix:** recognise menu pages by their widgets and back out of that one.
13. **UE4SS sometimes crashes while the game is closing** (fault in `UE4SS.dll`, seconds after the save is
    written). Harmless for saves; expect a "stopped working" box now and then.

## Assets
None.

## Cost and time
About two days of sessions (17 and 18 Oct 2026).

## Open questions
- Two-player tests on two PCs, with the puppet fed from the network instead of the same PC.
- Whether the released co-op mod (Double Trigger, MIT) is the better base; it uses the online layer above.
