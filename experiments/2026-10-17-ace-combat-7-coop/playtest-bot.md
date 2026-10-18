# Playtest bot: design

Written 18 Oct 2026. A design only: nothing in it has been built yet. It builds on what
the workbench already proved (workbench.md sections 5, 7 and 9).

## What it is

A test pilot that lives in the game copy. A Claude session hands it a **test order**
("Mission 5, Normal, F-22A with QAAMs, radar sites first, up to 10 tries"). The bot
starts the copy, gets into the mission, flies and fights in real time, retries when it
fails, and hands back a **test report**: what happened, when, and why, with the raw
flight data next to it.

Claude itself can't fly the plane live: each Claude step takes seconds, and a jet needs
decisions many times a second. So the work is split three ways:

| Part | Where it runs | Its job |
|---|---|---|
| **The pilot** | Inside the game, as a UE4SS Lua mod (`CoopPilotMod`) | Looks at the plane and the battlefield 30 to 60 times a second, decides what to do, works the controls and the weapons, and writes down what happens. |
| **The test runner** | Outside the game, a Python program (`tools\playtest.py`) | Reads the test order, backs up saves, starts the copy, drives the menus, passes the order to the pilot, watches for crashes and time limits, retries, closes the copy, checks your real saves, and writes the report. |
| **The test director** | A Claude session | Writes the order, starts the runner, reads the report, changes the order or the pilot's tactics, runs it again. |

## A test order

A small text file Claude writes. Every line is optional except the mission.

```yaml
mission: 5                  # campaign number, or a DLC name such as "SP Mission 01"
difficulty: normal          # casual, normal, hard, ace
plane: F-22A
special_weapon: QAAM
mode: fair                  # fair, assisted or skip-ahead (see below)
targets_first: [radar]      # objective order: target types, names or areas, in order
start_at_phase: 1           # for testing one part of a mission
stop_after_phase: 2
tactics:
  cruise_altitude_m: 1500
  stay_below_radar: true
attempts: 10                # keep trying until it completes, at most this often
time_limit_min: 25          # per attempt
record: [flight, events, pictures]
```

## What comes back

One folder per test, `playtests\<date>_<mission>_<name>\`:

- `report.md`: in plain language. Did it complete, after how many tries, how long each
  took, score and kills, where and why each failed try ended ("shot down by a Su-30
  missile at 06:12, phase 2, 31% health before the hit"), which objective took longest,
  anything odd (stuck phase, a target that never appeared, a crash).
- `events.jsonl`: one line per event, with the time: phase started or cleared,
  checkpoint, target locked, missile fired, hit or missed, kill (who killed what), damage
  taken and from what, flares, missile warnings, radio lines, warnings (stall, altitude,
  leaving the area), mission accomplished or failed, game crash.
- `flight.csv`: ten times a second: position, heading, pitch, roll, speed, altitude,
  health, weapons left, selected and locked target, nearest threat.
- `pictures\`: the game window at key moments (each phase start, each death, the
  result screen).
- `order.yaml` (the order as run) and `saves-check.txt` (your real save folder compared
  with the backup taken before the test).

## How the pilot flies

Three ways to work the controls, best first. The first build step tests which one works.

1. **Writing the plane's own control values.** The player's plane (`PlayerPlane`) has
   `InputPitch`, `InputRoll`, `InputLeftYaw`, `InputRightYaw`, `InputThrottle` and
   `InputBrake` values, plus switches that turn your controls on and off
   (`bEnableMovmentInput`, `bEnableWeaponInput`). If the plane reads those values every
   frame, the pilot can move a virtual stick smoothly, like a gamepad, without any
   window needing to be in front. **Unproven:** the game may overwrite them from your
   keyboard and controller every frame, or they may only drive animations.
2. **Pressing keys** through `tools\game-input.ps1`, as already done on 18 Oct (A/D roll,
   S pull). Proven, but on/off only, so flying is jerkier, and the game window has to be
   in front.
3. **Steering by nudging the plane**, the way the puppet plane is flown: the game's own
   flight engine keeps the plane flying, and the pilot turns it a little each frame
   towards where it should point. Proven on AI planes. It isn't how a human flies, so
   it's only used in the "assisted" and "skip-ahead" modes.

Weapons and targets don't need any of this. The game exposes them directly:
`MainWeaponPressed`/`Released` (missiles), `MachineGunPressed`/`Released` (gun),
`FlarePressed`, `ToggleSpecial` (special weapon), the weapon counts,
`TargetSelectionComponent:SelectTarget`, `GetSelectedTarget` and
`GetAllLockedOnTargets`.

## How the pilot decides

A simple set of states, checked many times a second:

- **Take-off**: skipped where the game allows (`Mission:SkipMiniGame`), otherwise full
  throttle and a gentle climb.
- **Travel**: fly towards the next target from the order, at the order's altitude,
  inside the combat area (the plane reports `IsBeyondPulloutLine`,
  `IsOverRestrictedAltitude`, `IsInRadarArea`, `IsInJammingArea`, `IsInTunnel`).
- **Attack an air target**: aim slightly ahead of the target (lead pursuit), fire a
  missile pair when locked and in range, wait for the result, gun when close.
- **Attack a ground or sea target**: line up from a distance, shallow dive, fire when
  locked, pull up early.
- **Defend**: on a missile warning, flares and a hard break turn; with a pursuer behind,
  turn hard and climb or dive.
- **Stay alive**: an altitude floor with a pull-up well before the ground, speed above
  stall, back into the combat area before the countdown ends.
- **Mission rules**: a short note per mission for its special mechanics (for example
  "stay under 500 m in phase 2", "this target only takes damage from behind"). Notes
  grow as tests teach the bot about each mission.

All the information it needs is already readable: every plane and ground unit is a
`GameObject` with position, health, speed, callsign, side and whether it's active, and
the mission reports its phase, time left, score and kills (`Mission:GetKillStat`,
`GetMissionScore_S`, `IsMissionCompleted`, `IsMissionFailed`). The mission's own event
system (`MissionEventListener`: phase start, unit destroyed, player dead, mission
accomplished or failed, radio line started) is what the event log listens to.

## Three modes

| Mode | What's different | Good for |
|---|---|---|
| **fair** | Plays by the same rules as you: no invincibility, normal ammo, real controls (way 1 or 2 above). | Testing difficulty, balance and how a mission feels. Will fail sometimes, which is what the retries are for. |
| **assisted** | The plane can't be destroyed (`SetIsInvincible`, already proven on AI planes), unlimited missiles if the game's switch works, steering by nudging. | Getting through a mission reliably to test its scripted events, triggers, radio and co-op syncing. |
| **skip-ahead** | Reaches a later part fast: phase skip if the game's leftover switch still works, otherwise destroying the current objective's targets directly. | Testing one particular part of a long mission. |

Many of the game's developer commands are empty in this build (workbench section 6:
351 of 494 point at blank stubs). Some test helpers have promising names
(`SkipToPhase`, `TogglePlayerInvincible`, `TogglePlayerWeaponUnlimited`,
`ToggleForceSkipIGC` for cutscenes, `ToggleForceSkipMiniGame`, `ThreeTimesFaster`).
Each one is tried once and noted as working or empty. The design doesn't rely on any of
them.

## Getting into a mission and retrying

- **The menu route is already proven** (workbench section 7): title, Campaign, mission
  list, difficulty, about 70 single Escape presses through the briefing, Mission Prep,
  aircraft, special weapon, Sortie. The runner follows the same route, reading a picture
  of the window after each step to check it's where it expects to be.
- **A faster route to try**: the game's own `NimbusGameInstance:SetMissionID` and
  `SetPlaneAndSWP` (plane and special weapon), and the player controller's
  `SetIsSkipIGC` (skip cutscenes). If those work, choosing the plane and skipping the
  briefing becomes one script call instead of a page of key presses.
- **Planes**: the copy's save is a copy of yours, so the planes and weapons you've
  unlocked are available. Whether other planes can be forced in is a test.
- **Retry**: after "Mission Failed", either "Retry from checkpoint" (about 25 s, proven)
  or back to the mission list and start again (the runner picks per order). After a game
  crash the runner restarts the copy and carries on, up to the attempt limit.

## Honest view

- **Assisted mode on most missions: realistic.** The parts are mostly proven (reading
  the battlefield, steering a plane, invincibility, menus); it's mainly assembly.
- **Fair mode on Casual and Normal for straightforward missions: realistic but slower.**
  A rule-based pilot with good aim and missile timing can win many fights. How well
  depends on how the control test (way 1) turns out.
- **Fair mode on Hard and Ace, against named aces and in the unusual missions: a long
  way off.** Those need careful tuning per mission, and some may never be worth it.
  Assisted mode covers them for testing purposes.
- **Rough size:** a first useful version (assisted mode, one mission start to finish,
  with the report) in two or three sessions; fair mode and more missions after that, a
  little at a time.

## One thing to decide first: Steam achievements

The copy runs under your Steam account, and the game awards Steam achievements when
missions are completed (its settings list 49 achievement slots). A bot that completes missions in
the copy could unlock achievements on your real Steam profile that you didn't earn
yourself. Choices:

- **Allow it.** Simplest. Anything unlocked is permanent unless reset with a separate
  tool.
- **Try to block them.** A script may be able to stop the game reaching Steam's
  achievement calls. Unproven; until it's proven, no mission gets completed in the copy.
- **Only test missions you've already completed** in your real game, where the
  achievement is already yours. Doesn't help with ranks or difficulty-level achievements.

No mission has been completed in the copy so far, so nothing has been unlocked yet.

## Build order

Each stage gets tested in the copy before the next one starts.

1. **Control test** (one short session): in Mission 01 or SP Mission 01 on Casual, write
   `InputPitch`/`InputRoll` every frame and see whether the plane responds. Try weapon
   presses and `SelectTarget`. Try the promising developer switches once each.
2. **Sensors and logger**: the event log and flight log from a mission you fly (or the
   bot flies straight). Report format settled.
3. **Pilot, basic flying**: fly to a point, hold altitude and speed, turn smoothly,
   don't hit the ground.
4. **Pilot, fighting**: one enemy plane on Casual, then a group, then ground targets.
5. **Test runner**: reads an order, backs up saves, starts the copy, menu route, retry
   loop, crash recovery, save check, report.
6. **Assisted mode, one whole mission**, start to finish, report in hand.
7. **Fair mode**, then more missions and their notes.

## Ground rules it follows

- Only the copy at `C:\AC7-Coop-Game`, started through `tools\start-copy.ps1` (saves
  backed up first), with `tools\compare-saves.ps1` after every test.
- Single-player only. The bot never goes online and never touches the game's online
  modes or their cheat checks.
- One copy at a time, with the `IN-USE-game-copy.md` marker while it runs.
- Your standing permission covers starting the copy, playing missions in it and adding
  UE4SS Lua mods. Extending the C++ add-on (so the pilot can also send live data out)
  is covered by your 18 Oct addendum. Anything beyond that gets asked first.
