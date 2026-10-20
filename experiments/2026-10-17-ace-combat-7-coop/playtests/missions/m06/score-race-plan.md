# Mission 06 score race: plan for the next session

Written 19 Oct 2026 from a brainstorm with the owner. Read with `notes.md` (same folder) and
workbench.md section 15 (end).

## Priority: make the bot stronger, not the level easier (the owner, 19 Oct)

The bot is a test tool: Claude, other AIs and modders use it to test their own AC7 modifications,
so it must give useful data when objectives, enemy counts or positions, or the geography change.
Every solution is judged first by "would this still work if a mod moved or changed it?".

- **Read it live, never hard-code it.** Targets, points, objectives, zones, threats, terrain and
  structures come from the running game each time (as `KillBountyScore`, the HUD score goal, the
  combat zone, TGT and protect marks, the ray vision already do). No coordinates, routes or target
  lists written for one level, except as test cases.
- **Switch behaviours on by what the game shows, not by per-mission plans.** Score mode turns on
  whenever the HUD shows a score goal; the same for other phase rules (stealth when radar areas are
  active, protect when an ally carries the protect mark). `plan.txt` files stay for experiments and
  for genuinely scripted moments, not for routine behaviour.
- **Classify by game data, not by names.** Drones, helicopters, bombers and low-value targets are
  recognised today by name fragments, which modded enemies will not share. Use the game's flags and
  measured behaviour (air/ground/sea flags, speed, turn rate, health, weapons, size).
- **Planners run inside the bot.** The kill-chain lane planner works from the live `scorePts`. The
  Mission 04 radar-avoiding route and the tunnel approach were made by hand or offline; the native
  versions are an in-bot route planner from live radar areas, and a "find the passage" skill that
  scans a structure with rays, finds the opening and its axis, and plans its own approach.
- **Simulators tune general rules, not one layout.** The offline targeting simulator must run many
  varied scenarios (random clusters, other enemy counts and terrain) plus the real missions as test
  cases; parameters count as good only if they hold across all of them.
- **Report general data.** The time breakdown, kill rates per kind, failure reasons and the
  activation log are the kind of output a modder needs; make them standard in every report.

The kill-chaining fixes and the lane planner below are general by construction (live positions, the
weapon's real lock cone and reload). Where an item below is level-specific, it is marked so.

## The problem in numbers

- Phase 1 needs **24,000 points in 15 minutes** (HUD `ScoreInfo`, status `hud_score`/`score_goal`).
  About 30,000 exist: area A near the start (3 Tu-160 at 1,200, F-16s, about 5,000), area B (the
  anti-air cluster, helicopters, then 11 drones at 350, about 11,000), area C in the west (two
  harbours with 17 ships, Gripens, SAMs, sphere-triggered fighter waves, about 8,000). Points per
  kill: `GameObject.KillBountyScore`. 24,000 means clearing nearly everything.
- Best: **about 14,000** (Typhoon, LAAM, campaign parts, `fly attack score`). Runs vary by about 2,000.
- Where the best run's 15 minutes went: **45% target within 3 km but over 45 degrees off the nose**
  (turning back, orbiting, sweep run-ins with the target to the side), 15% target ahead not yet
  locked, **11% locked**, 10% missile breaks, 18% transit. 53 kills; a player makes 80+.
- Standard missile (Typhoon, base values; the copy's parts improve lock speed, lock range, reload):
  lock cone **32.5 degrees**, lock range **2.0 km**, 2 loaded, **5.5 s** reload each, 40 damage.
  Most ground targets have **40 health**: one missile, one kill. The cap is roughly 20 shots a
  minute; the bot fires 4-6.

## Diagnosis (the owner's words: "a huge time sink in trying to get the perfect dive")

The bot still steers *at its current target*. Ground attacks follow a run-in, dive, pull-out,
extend pattern (`groundRun`), and sweeps (`sweepRun`) steer for a cluster's middle while the
target choice (`nearestEnemy`) is by points, so the target is often to the side. Every target that
falls outside the cone costs a loop. It should be the other way round: **the flight path is chosen
for the targets it will bring into the cone, and the target is whatever is in the cone.**

## Fixes (do these first)

1. **Fire from the cone, don't set up dives.** A locked target within 30 degrees and lock range gets
   a missile at once. No minimum dive, no run-in height rule in score mode. Keep only safety limits
   (above 120 m, pull out before 400 m from the ground ahead).
2. **Chain targets.** After each launch at a one-shot target (health no more than damage; the
   `pendingShot` logic exists), immediately select the next target from **inside the cone only**
   (within 30 degrees, 0.6 km to lock range), smallest angle first, ties by points, and select it
   with the game's `SelectTarget` straight away so its lock builds while the first missile flies.
   With both missiles gone, keep selecting (locks build during reload).
3. **No orbiting.** A target within 1.5 km and more than 45 degrees off the nose is dropped for 10 s
   (`c.skip`); it comes back on a later pass.
4. **Low passes.** Over clusters fly 250-350 m above the ground: a target 2 km out is then 7-10
   degrees below the nose, inside the cone; from 1,000 m it is 27 degrees down (the 90-second tank
   episode in the best run). Today's sweeps fly 450 m.
5. **Aggressive turning (score phases only):**
   - big-turn mode from 8 degrees off (now 12), full aileron to the bank, full pull;
   - high-G turn for any turn over 45 degrees above 450 km/h (now: over 50 degrees above 500);
   - about 600 km/h inside a cluster (turn radius grows with the square of speed), full
     throttle between clusters (already in);
   - higher steering gains (`pd` for elev/side) when the target is within 3 km;
   - start turning toward the next target as soon as the current missile is away (anticipate),
     not when the target dies.
6. **Breaks:** stay at 200 m predicted miss (120 m got the plane shot down), but in score mode try a
   smaller jink plus flares instead of the full break when the predicted miss is 120-200 m.

## Punches (bigger bets, in order of expected value)

1. **Lane planner (the core change).** Every 0.5 s, for headings across plus or minus 90 degrees
   of now (15-degree steps; pitch to stay 250-350 m up): simulate the next 8 s (turn-in time at
   the measured turn rate, then straight), count the points of targets that enter the lock cone
   inside lock range, given the missiles loaded and the reload clock. Fly the heading with the most
   points per second; hysteresis so it does not dither; target = the cone pick from fix 2. Uses the
   existing `scorePts` list (positions and bounty of lockable ground targets). Air targets keep the
   current pursuit logic (bombers with the LAAM first).
2. **Offline targeting simulator, for general rules.** Python: target layouts (Mission 06's dumped
   from the game as one case, plus generated ones: random clusters, rows, scattered targets, other
   counts and spacings), plane turn and roll rates fitted from the flight CSVs in
   `C:\AC7-Coop-Game\UserProfile\pilot\flight-*.csv` (and from other planes when flown), lock cone,
   range and lock time, missile reload and flight time, all read from the weapon data. Replay 15
   minutes in seconds; tune the lane planner's general parameters until they do well across all
   scenarios (not only Mission 06), then fly. (Same idea as `tools\vision-sim.lua`, which got the
   tunnel test through.)
3. **Row passes.** For each cluster, the long axis of its targets (principal axis); approach along it
   so targets arrive in the cone one after another. Can be a bonus term in the lane planner.
4. **Weapons.** (a) The 8AGM's salvo: make it wait for four locks (it fired at one or two); find how
   the game accumulates multi-locks (seeker states, `MultipleLockOnMaxNum`). (b) One sortie with the
   F-15E's TLS laser (needs "hold fire while the beam crosses targets" behaviour), the likely best
   weapon for rows of ground targets. The F-15E's multiplayer parts are already cleared.
5. **Faster test loop.** Judge changes by kills per minute while inside a cluster and by the time
   breakdown (`<3 km off-nose`, locked, breaks, transit), computed automatically for each run (make
   the one-off analysis in this session a tool). Run the first 8 minutes only (pause menu restart
   from checkpoint) instead of waiting for the 15-minute timeout.

6. **Generality work alongside (from the priority above).** Score mode on from the HUD's score goal
   (drop `fly attack score` from Mission 06's plan once that works); drone/helicopter/bomber
   recognition by game data instead of name lists; kill-time learning per measured class instead
   of per name. Later: the in-bot "find the passage" skill to replace the hand-made tunnel route
   (level-specific today: `m06-tunnel-approach.csv`, the coordinates in `notes.md`).

## What not to repeat

Base-first targeting with the 8AGM (3,480); the F-22A with XSDB (no LAAM for the bombers, 4,450 at
6.5 min); breaks only within 120 m (shot down); the gun parts swap (about 12,000, no clear gain);
hot reloads with CoopNetCheckMod loaded (crash; it is now off).

## Success criteria

Phase 1 cleared on Ace; then the rest of Long Day and the campaign onward with
`tools\campaign.py run playtests\orders\campaign-ace.yaml`. Intermediate: in-cluster kill rate
from about 4 a minute to 10+, locked share of time from 11% to 30%+, the off-nose share under 25%.

## Practical notes

- Code: `mods\CoopPilotMod\Scripts\main.lua`, functions `nearestEnemy` (target score),
  `combatStep` (selection, sweep pick, firing, one-shot), `groundRun`, `sweepRun`, the steering
  block (`ap.big`, `pd`), the throttle block; `vision.lua` for obstacle sensing.
- Loadout in the copy's save: Typhoon with Queen's Custom, missile reload, lock speed, lock range,
  homing, power, special reload, Onboard Self-Defense Jammer; LAAM. `mission.txt` names plane and
  special; parts stay in the save (the hangar parts page is learned: `campaign.py --hangar`, the
  scratch scripts `fit-plane.py`/`clear-mp.py` pattern: 250 ms key presses, Standby items by their
  description).
- Rules: only `C:\AC7-Coop-Game`; `tools\compare-saves.ps1` after every run; Mod Loader only with
  `--game "C:\AC7-Coop-Game"`, copy stays Vanilla/Default; IN-USE note while driving; game window
  in front; don't drive while the owner uses the PC; Playground commits as Claude with the
  Co-Authored-By line.

## What came of it (19 Oct 2026, evening session)

Built (details: `notes.md` here, workbench section 16):
- Fixes 1-3 (fire from the cone, chain targets with `SelectTarget` right after a launch, no
  orbiting) and punch 1 (the lane planner) as `lanes.lua`; punch 2 (the offline simulator,
  `tools\lane-sim.py`, six generated layout kinds with varied planes and missiles, plus this
  mission's dumped layout as one test case); punch 5 (the automatic time breakdown and general
  numbers in every report, `tools\run-stats.py`; the 8.5-minute test order).
- Fix 4 (low passes): pass height 250 m; it took two steering fixes before the plane really flew
  low (hard turns climbed; now slicing turns).
- Fix 5 (aggressive turning): bank-to-turn with an immediate pull, high-G on every big turn,
  braking into turns above 850 km/h (the owner, watching: "the tightest possible turn ... at
  maximum speed and ferocity").
- Fix 6 (breaks): replaced at the owner's request by a defensive attack (keep attacking, turned
  across the missile's line); full breaks only in a missile's last 2.5 s if it is still on course,
  or with health under 40.
- Generality items: score mode from the HUD; kinds from game data; kill times per kind from game
  data; the activation log in every report. Not done: the in-bot "find the passage" skill.
- Punch 4a tried (the 8AGM with the lanes, salvos held for more locks); 4b (the F-15E's TLS) not.

Results: kill rates up (best full phase 6.4 kills a minute against 3.4; the locked share 25-28%
against 11%), but every full phase so far ended at 10,700-13,400 points or with the plane shot
down; see the table in `notes.md`.
