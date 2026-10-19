# Playtest bot: design

Written 18 Oct 2026 as a design; **built and working the same afternoon** (workbench.md
section 10). It builds on what the workbench already proved (sections 5, 7 and 9).

## Status (19 Oct 2026, 00:20): phase 3, terrain and mission gimmicks

- **Your request (18 Oct, 19:00): see terrain and physical objects and adapt to missions'
  special rules; prove it on Mission 14 (Cape Rainy).** Built (workbench section 14): a
  terrain survey and height map from line traces, 600 times faster through the C++ add-on
  (1.4 microseconds a ray); route planners for a canyon under a ceiling; a route-following
  pilot for canyons; the mission's own objects read live (searchlights and their sweeps,
  the altitude ceiling the game sets, the radio, the marks a mission puts on targets); and
  **live beam dodging**: four times a second the pilot predicts where every nearby
  searchlight will point when it gets there and changes speed, height or line to stay dark.
- **Result: the bot flies Cape Rainy's 47 km night canyon on Hard** (unseen by about 70
  sweeping searchlights, under the 550 m limit, no damage) at the first try in 4 of 6 cold
  starts; both misses were the same searchlight, fixed at the end of the night.
- **The base attack (your two ideas built in):** targets valued by the threat to our landing
  party, chosen targets selected directly, one missile per target when one is enough and the
  next target chosen at once (34 such shots in one run, 21 kills), Apaches opened out from
  and come back at nose-on, breaks and flares only for missiles that would come close. The
  landing team now lands 1.5 to 2 minutes into the attack in half the attempts. **Not
  completed yet:** the reinforcement wave after the landing cannot be locked by the bot, nor
  some SAM sites, although the game lists them as normal targets (workbench 14, finding 11:
  everything ruled out so far, and the next step).
- Also new: mini-games (aerial refuelling) skipped with the game's own skip; every radio line
  logged; a failure report naming which searchlight or enemy caught the plane; menu choices
  checked by reading which mission is selected; four game crashes traced to holding on to
  game objects across a checkpoint restart, and none since the guard; plans per mission
  (`playtests\missions\m14\plan.txt`) with `focus` and `cloudbase` options.
- **Not built yet:** the story-mode flow for the campaign (cutscenes, results, debriefing,
  hangar), plane and weapon choice, 3D "vision" with ray fans for tunnels and structures
  (your Mission 04 and 06 tests). Next: a separate session runs the Ace campaign start to
  finish (your OK of 18 Oct, 22:5x), and takes the lock problem first.

## Status (18 Oct 2026, 13:45)

- **Working:** the bot took off, shot down all 19 enemy planes of Mission 01 on Casual
  without taking a hit, and the game declared "mission accomplished"
  (`playtests\2026-10-18_1237_m01_first-run\report.md`). Then the test runner did the whole
  thing on its own from a cold start: started the copy, drove every menu page, completed
  Mission 01 on Casual at the first attempt (20 kills, no damage, score 12,400, the same as
  your own best), closed the copy and checked your saves
  (`playtests\2026-10-18_1326_m01_runner-test\report.md`). Stages 1 to 5 of the build
  order are done.
- **To run a test:** `python tools\playtest.py run playtests\orders\m01-casual.yaml` (an
  example order, every option explained in it). Keep the game window in front while it
  runs.
- **Phase 2 (your request, 18 Oct 13:30), built the same afternoon** (workbench section
  11): a tracker (`awareness.lua`) that follows every enemy and every missile, reads their
  limits, AI state and scripted routes from the game, measures the real ground with line
  traces, predicts where enemies will be (picking its own method from how well each one
  has been doing) and works out each incoming missile's time to impact and miss distance.
  On it: flares and break turns timed from the tracker, turning into an enemy on our tail,
  the LAAM for targets 2-10 km away, attack runs on ground targets. Results: Mission 01
  on **Ace** completed at the first attempt with no damage; **Mission 02 on Hard
  completed**, 44 kills, one hit taken, **8 of 8 enemy missiles aimed at the bot lost
  their lock**.
- **Changed from the design:** the pilot flies with the **keyboard**, pressed from inside the
  game by a small C++ add-on (`CoopPadMod`), not by writing the plane's control values (the
  game overwrites those every frame) and not with a virtual gamepad (Steam's overlay keeps
  it from reaching the game). Consequence: **the game window must stay in front while a
  test runs**; the game pauses itself otherwise, and the add-on never presses a key into
  another window.
- **Not built yet:** choosing the plane and special weapon from an order (the copy's
  last-used setup flies), the assisted and skip-ahead modes (the developer switches they
  hoped for are empty in this build), objective order (`targets_first`), ground targets on
  purpose (the pilot attacks whatever the game lets it select, ground targets included, but
  has no dive-attack yet), per-mission notes, and getting past the replay that follows
  "mission accomplished" quickly.
- **Achievements:** your call on 18 Oct: no concern (you have nearly all of them).

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

## Steam achievements (decided)

The copy runs under your Steam account, so a mission the bot completes can unlock Steam
achievements on your profile. Your decision on 18 Oct 2026: not a concern, you already have
nearly all of them. The bot completed Mission 01 on Casual in the copy that day.

## Build order

Each stage gets tested in the copy before the next one starts.

1. **Control test** (one short session): in Mission 01 or SP Mission 01 on Casual, write
   `InputPitch`/`InputRoll` every frame and see whether the plane responds. Try weapon
   presses and `SelectTarget`. Try the promising developer switches once each.
   *Done 18 Oct: writing the values does nothing; keyboard keys from inside the game do;
   the developer switches are empty (workbench section 10).*
2. **Sensors and logger**: the event log and flight log from a mission you fly (or the
   bot flies straight). Report format settled. *Done 18 Oct.*
3. **Pilot, basic flying**: fly to a point, hold altitude and speed, turn smoothly,
   don't hit the ground. *Done 18 Oct, tuned in Free Flight.*
4. **Pilot, fighting**: one enemy plane on Casual, then a group, then ground targets.
   *Air targets done 18 Oct (Mission 01 Casual completed, 19 kills, no damage); ground
   targets not yet.*
5. **Test runner**: reads an order, backs up saves, starts the copy, menu route, retry
   loop, crash recovery, save check, report. *Written 18 Oct (`tools\playtest.py`); see the
   status above for how far it is tested.*
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
