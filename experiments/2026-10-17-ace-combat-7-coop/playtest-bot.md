# Playtest bot: design

Written 18 Oct 2026 as a design; **built and working the same afternoon** (workbench.md
section 10). It builds on what the workbench already proved (sections 5, 7 and 9).

## Status (20 Oct 2026, afternoon): the plane, the ground and where to attack from

- **The plane, measured** (`tools\aircraft-model.py` -> `playtests\aircraft\typhoon.json`, now
  also `dv_by_kmh`: speed change by 30-degree climb band and 200 km/h speed band together): the
  turn rate 37-43 deg/s at 300-1,600 km/h; the brake 46-130 m/s each second held level but only
  holding the speed in a 30-60 degree dive.
- **Manoeuvre planner** (`maneuver.lua`): the wanted way flown ahead 5 s in that model (its
  speed table now speed-aware for the brake, learned in flight by speed too) and traced against
  the ground (engine line traces), with 50 alternatives when it would hit; held 1.5 s; margin 80
  m (60, which the wargame allowed, hit a rock pillar the survey's 50 m grid smooths away). Events
  `maneuver`.
- **Attack lines** (`approach.lua`, called from `groundRun` outside score phases): the target's
  visibility map (16 directions x 10-80 degrees, 3 km, from 3 m above it); a usable line (clear,
  10 degrees lower clear, a side neighbour clear); the line the plane is on soonest (`M.cost`:
  the way to the approach point 3 km out, the climb, the turns at the measured rate); held unless
  another is 4 s sooner, plus half the seconds held (up to 12); flown with a carrot 800 m down the
  line (straight for the approach point until 2.5 km from it), back in a turn radius past the
  gate (2.2 km) after a pass; an aim more than 80 degrees off is a level turn toward its side,
  unless steeper than 70 degrees (then dived at); a target in sight ahead is attacked on the line
  the plane is on ("direct"); a line blocked from the plane inside the gate for a second is
  dropped for 30 s. 650 km/h before lines of 35 degrees or more (the brake cannot slow the dive).
  Events `attack_line`, `on_line`, `line_blocked`.
- **Shooting**: a lock the game holds on another ground enemy in reach and in sight is taken
  when the game would not select or lock the bot's own target, at most once in 5 s (event
  `take_lock`; taken any time, it flip-flopped 143 times in Mission 08's truck phase); while every shot at a kind of target has missed, the learned range cap is
  no nearer than 2 km and there is no learned minimum range at all (an ace dodged them all: first
  the cap fell to 1.3 km and the bot held fire for six minutes; then the minimum rose to 2.2 km,
  above the cap, and it could not fire while locked on him at 0.8-1.8 km).
- **Missiles** (`awareness.lua` `A.minDodge`, the owner's advice): the defensive attack turns off
  the attack only by the smallest angle (0-35 degrees) that the missile, flown ahead chasing the
  plane within its own turn rate, misses by 120 m; for one missile it only grows; 12 degrees for a
  missile from the target dived at on its line when nothing clears it; no last-instant full break
  for a missile a small dodge was found to clear. `A.dodgeScale` widens
  every dodge 2.5% while more than a tenth of the last ten dodged missiles hit, a hit counted only
  when the damage is the missile's (10 or more at once, within 0.3 s before to 0.5 s after its
  end, the missile last seen within 200 m, the plane over 30 m above the ground). Events `dodge`,
  `dodge_scale`.
- **Fighters in score phases**: the commitment to an aircraft after the plane (the furball rule) is
  taken only while the air targets pay at least half the lanes' points a second, or below half
  health (event `furball_declined`; Mission 08: 90 s on F-15Cs for 850 points had cost a phase).
- **What dies with a kill** (`killTally.chainNote` / `chainValue` in main.lua, from the death
  hook): per class, the kills, the candidates within 400 m of each, and the points of enemies the
  bot did not fire at that died within 1.5 s and 400 m; points per neighbour times a target's live
  neighbours is added to its value in the lanes once the class has three kills (Mission 08: 44% of
  a 21,750 score was tanks set off by the ones hit).
- **Escort**: an enemy chasing an ally that lost health in the last 10 s counts 4 times (each
  ally's health is read every scan; weighting by distance to the chased ally was tried and made
  the bot switch among far UAVs); a close drone the plane is opening out from stays its target.
- **Caution trimmed** (the owner: safety near the minimum plus a little, skill over timidity):
  the 550 km/h cap after an obstacle lasts 4 s with the planner (was 20); full throttle in any
  fight to a target more than 6 km away within 30 degrees of the nose.
- **Runner**: after an attempt stopped by its time limit, the pause menu's Restart from
  checkpoint and its YES (`playtest.restart_from_checkpoint`), waiting until the game runs.
- **Wargame** (`tools\maneuver-sim.py`): Mission 07's 17 ground targets where the game has them,
  ten-minute flights, the next target nearest, a one-second lock; flags `SIM_LINE`, `SIM_PICK`,
  `SIM_SHORTOUT`, `SIM_LOCKR`, `SIM_DG`, `SIM_DA`, `SIM_FARA`, `SIM_STEEP`, `SIM_WIDE`,
  `SIM_WORKERS`, `SIM_DUR`.

## Status (20 Oct 2026, 09:30): Mission 06 cleared; vertical attacks and the return line

- **Vertical attacks** (`lanes.lua` `L.simulateDive`, `L.pullNeed`; `main.lua` `diveAim`,
  `pullOutAim`): for the three most valuable close targets outside the cone, straight down onto
  each (with 450 m of air and the target 20 degrees or more below) and up and over first (for one
  behind), simulated in 3D at the measured turn rate with the shots on the way and the pull-out;
  flown with the roll-and-pull mode at any height, braking to 450 km/h going down; the pull-out
  the shorter way (pulling through when the canopy faces that way), with the ground along it
  traced; the ground check during it the pull-out arc (60% of the measured turn rate, a reaction
  and a half roll, 150 m floor, 25% margin), the straight lines kept while the nose is less than
  30 degrees down. Events `dive`, `dive_end`.
- **Return line** (`gimmicks.lua` `G.returnLine`; `main.lua` lanePlan and apStep;
  `tools\playtest.py` `resupply_keys`): go when the fight's own rate says the missiles (or the
  special weapon, with aircraft worth 1,500 points flying) run out more than the detour before
  the end, or health is under 40%; fly over the line; the runner presses Esc, Enter, Up, Enter,
  Esc. Events `resupply`, `resupply_landing`, `resupply_done`. The phase clock stops meanwhile.
- **Missile economy** from 1.1 times what is left again; spare LAAMs make air targets count 1.5
  times against the lanes.
- **Result**: Mission 06's phase 1 won with 24,480 (rank A); on to Mission 07.
- **Mission 07 (terrain), first day**: slow to 550 km/h for 20 s after each obstacle the vision
  net reports (`ap.visBlockedAt`); among obstacles the ground runs leave the cloud-base cap; a
  ground run with rock in the line (one `Aware.losBlocked` trace, inside the turn-back distance)
  extends, comes back from 1,600 m diving up to about 40 degrees, and only then sets the target
  aside (event `run_blocked`). Not cleared; still missing: turning away from walls too tall to
  climb, cruising above the highest ground around, steep attacks on canyon targets outside the
  lanes (`playtests\missions\m07\notes.md`).

## Status (20 Oct 2026, 06:30): missiles and minutes run out together

- **Hurt aircraft**: the air pick's kill time is scaled by the target's health left
  (`GetHealth` / `GetMaxHealth`, at least 0.25); the leaving rule asks a 20% margin over the air
  target here, as a best-group move does. The opening's three bombers now always fall.
- **Missile economy**: forecast from the whole fight's launch rate, acting only past 1.3 times
  what is left (3-10 standard missiles left at the end, from 11-51).
- **Drones**: a drone as the target is not an engagement (moves and lanes go on; air shots and
  the gun take it in passing). The group-of-planes air rate uses each plane's own kill time.
- **Special weapon surplus** (`c.spSurplus`, event `special_surplus`): when more is left than the
  fight's rate would use in the time left (by 30%, and 2 more), air shots take any aircraft up to
  50 degrees off.
- **Result**: Mission 06 attempts 18,780-22,000; best still 23,200. With both weapons used up,
  about 25,500 is the loadout's ceiling.

## Status (20 Oct 2026, 03:00): missiles that hit; Mission 06 at up to 23,200

- **Moving between areas** (latest): a "leaving rule" from foraging theory (leave a place once its
  last minute paid under half of the fight's average; go to the best group of 2,000+ points 8 km
  or more away and keep going until there; not back to a place left in the last 3 minutes). Best
  attempt 23,200 of the 24,000 needed. Kills are now counted afresh after a checkpoint restart.

- **Waste found and fixed** (general, not level-specific): fire key still down while the next
  target was selected (a quarter of the missiles flew unguided; the selection now waits 0.25 s);
  no line-of-sight check (one ray trace before every shot now, `Aware.losBlocked`); the missile
  tracker missed reused missile objects (now ends and re-launches are seen); learned agility
  counted presses, not missiles that flew. Standard missiles at ground targets: about 60% hits
  before, 92 of 94 after.
- **Weapons**: missile discipline (no more missiles in the air at a target than its health
  needs), the LAAM first for anything in the air and an "air shot in passing" while the lanes are
  flown, learned firing distances at both ends per weapon and kind, a missile economy for timed
  phases, the gun measured (`guntest` order, `gunnery.lua`: strafing pass, bullet tracking,
  learned zeroing, a short gun "snap" in the lanes).
- **Decisions**: honest kill times per kind (failed engagements included), area moves judged at
  the best minute's pace and kept once started, a committed "furball" target for an aircraft that
  has just fired at the plane from close by (the owner's request).
- **Report numbers added**: ammunition left at 5/10/15 minutes, missiles by outcome (targets that
  died or survived), missiles followed and unguided, held shots (discipline, line of sight), air
  shots, furballs, gun bursts and where the bullets went, learned kill times.
- **Result**: Mission 06's score race from about 13,000 to 21,900-21,990 in full phases; not
  cleared yet (24,000 needed).

## Status (19 Oct 2026, evening): kill chaining with the lane planner

- **How it attacks ground targets now** (`lanes.lua`): the flight path is chosen for the targets
  it brings into the lock cone (21 manoeuvres flown 12 s ahead in a model of the plane and the
  missile, twice a second), the target is whatever is in the cone nearest the nose, and the next
  one is selected right after each launch. Tuned with `tools\lane-sim.py` over six kinds of
  generated layouts with varied planes and missiles (10.1 against 6.1 kills a minute for the old
  nose-on attack); Mission 06's real layout is one test case among them.
- **General, read live** (the owner's priority): score mode from the HUD's score goal; enemy
  kinds from the game's class tree, flags and numbers (no name lists); turn rate, lock time,
  reload and missile ranges measured on itself in flight; the next group of targets chosen by
  points per second including the flight there, judged by the points really scored.
- **Flying** (the owner's advice while watching): bank-to-turn with an immediate pull and the
  high-G turn on every big turn, slicing turns down when too high, brakes into turns above 850
  km/h, full throttle toward a group until 5 km out; a **defensive attack** instead of breaking
  off (keeps attacking, turned up to 35 degrees across the missile's line, flares, high-G; a hard
  dodge only at the last instant or with health under 40); threats first (anything that fired a
  missile at it counts 2.5 times its points).
- **Data in every report** (`tools\run-stats.py`): time split frame by frame, kills a minute
  overall and while engaged, kills and points by kind, own missile hits by weapon and range,
  locks, chained picks, defensive attacks and breaks, the planner audit, what it learned about
  itself, steering summary, HUD score every 30 s, the activation log.
- **The pilot keeps flying through its own script errors** (keys let go, error logged, loop
  kept), after one bad line crashed a test plane.

## Status (19 Oct 2026, 14:05): tunnel test passed; Mission 06 still open

- **Vision test 2 passed:** through Mission 06's tunnel on live rays (try 10: 1.6 m from the aim
  point, the whole bore in 10.5 s, out and away; one 24-point scrape at the last bend). What made
  it work: the approach flown as a route (`fly route`, then the fly-through when it ends), travel
  orders that use their own floor for the ground ahead, corridor following in `vision.lua`, and
  the hand-over to the fight only once clear. `module vision` reloads just the vision file.
- **Mission 06:** score race unchanged (best about 14,000 of 24,000).

## Status (19 Oct 2026, 10:20): stopped at Mission 06's score race

- **Campaign on Ace:** 01-05 completed; 06 Long Day not (phase 1 needs 24,000 points in 15
  minutes; best about 14,000).
- **New for score phases** (`fly attack score`): points per second (each enemy's own bounty,
  `KillBountyScore`, against travel time and a learned time to kill its kind), dense areas and
  whole areas weighted, sweeps through ground clusters (nose on the nearest target in the cone,
  pass, short loop), give-up on targets that stop taking damage, fewer missile breaks, full
  throttle and high-G turns. Everywhere: the game's `CombatZone` box is kept to; flares outside
  the fight; drones never with the LAAM or beyond 2.2 km; a drone on the tail gets a hard turn.
- **Loadout:** parts are now part of a mission's setup (the campaign hangar's parts page is
  learned; `--hangar` stops the driver there). The owner's multiplayer parts were taking 7 of
  8 slots on most planes, inert in the vanilla copy; cleared on five planes.
- **Tools:** `tools\activation-watch.py` (which enemy groups the mission switches on, and
  where the plane was), `tools\stunt.py` (line up and fly through a point), `tools\vision-sim.lua`
  (simulate a plane through real geometry with the real rays), the HUD's score goal in the
  status.

## Status (19 Oct 2026, 05:25): the Ace campaign at Mission 06

- **Completed on Ace:** Missions 01 to 05 (`playtests\campaign-ace.md`). Mission 05 taught it
  to put the mission's own targets (TGT) first; Mission 06 Long Day is in progress (phase 1 is
  timed on damage to the enemy base; flown now with the 8AGM and a base-first plan, the
  `focus` words in `playtests\missions\m06\plan.txt`).
- **New tonight:** flares in every mode that is not the fight (routes, fly-to, stunts); with a
  drone on its tail it turns hard into it instead of opening out; the vision layer measures
  room for the plane in metres (four parallel rays around a direction) instead of by the
  neighbouring grid rays; `tools\stunt.py` lines the plane up with lead points and sends a
  fly-through with live vision; `tools\vision-sim.lua` flies a simple simulated plane through
  real geometry with the real rays, inside the running game, to test vision before flying;
  `module vision|route` reloads those two files without UE4SS's reload of all mods (which
  crashed the game once mid-mission).
- **Your tunnel test (vision test 2):** first real try did not go in (the old room check saw
  the 36 m mouth as shut from 400 m); the simulator now gets through centred; next real try
  when a phase allows the 4-minute detour.

## Status (19 Oct 2026, 01:15): phase 4, the Ace campaign

- **The lock problem is solved** (workbench section 15). The bot used to write its chosen
  target straight into the game's "selected target" field; the game's own lock "seekers" are
  only handed a target by the game's own select call (what Tab does), so targets the game's
  cycle never offered never locked. Now the bot selects through that call. In Mission 14 on
  Hard the SAM sites and the reinforcement vehicles that never locked last night all locked and
  fell (27 kills in the best attempt); what is left there is speed against the waves.
- New readings: each target's lock-on mark (read from memory by a new read-only call in the
  C++ add-on), its "mission special object" flag, each lock seeker's target and state; menu
  titles and the selected item's description, yes/no dialogs and their selected option, the
  hangar's plane and special weapon under the cursor. A `locks` order lists every enemy with
  what decides whether it can be locked.
- **The story campaign runs**: `python tools\campaign.py run playtests\orders\campaign-ace.yaml`
  drives Restart Story / Continue, the difficulty list, movie skips (F1), briefings, the
  operation map, the hangar (plane and special weapon by name, per mission in
  `playtests\missions\mNN\mission.txt`), the take-off and the mission with its retries, and
  writes one report per mission plus a line in `playtests\campaign-ace.md`. The story was
  restarted on Ace at 01:06 (the copy's own save only).
- **3D vision** (`vision.lua`, for your Mission 04 and 06 tests): a fan of 165 rays twenty
  times a second, free directions with room for the wings, and corridor centring between
  walls; switched on with `vision on` in a fly order. **Vision test 1 done (Mission 04):** a
  surprise fly-through of the Space Elevator's base, beside the tower and under the lowest ring,
  passed 13 m from the chosen point with no contact. The same rays now also guard the fight mode
  against structures.
- **Campaign so far (Ace):** Missions 01 and 02 first try, 03 on attempt 2, 04 Rescue on the
  second sortie (a 128 km stealth route between 79 radar spheres, planned by the new
  `tools\route-avoid.py`, flown unseen twice; then drones, an escort and the Arsenal Bird's
  drones). What the bot learned on the way: protect the allies a mission highlights, chase
  what chases them, escort, use a "better air-to-air" special (HCAA), shoot agile drones only
  from 1.3 km out, never split-S near the ground, skip landing mini-games once the approach
  begins.

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
