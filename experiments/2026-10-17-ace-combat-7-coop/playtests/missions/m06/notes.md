# Mission 06 Long Day (story, Ace), the bot's notes

Level `ms06`, the Space Elevator map again. Written 19 Oct 2026.

- Starts in the air; phase 1 has a time limit (`phase_left_s` in the status, about 15 minutes).
  Bandog sends the Spare squadron from one group of targets to the next ("The vehicles have
  been taken out. Move on to the next target."); fighters, AV-8Bs, helicopters (AH-64), SAM and
  AA sites, ground vehicles, a bomber that takes off ("Chase it down", then "The bomber has
  left the AO. Do not pursue").
- First try (LAAM): 27 kills and score 6,440 ten minutes in, 4 health lost in the fight.

## The tunnel (the owner's vision test 2)

Found by its game objects: `MES_GEN_Tunnel_11` (mesh, box 618 x 1396 x 48 m centred at
(-70933, -29420), 107 m up) and `TunnelEventVolume_1` (the volume behind the status flag
`in_tunnel`, box 507 x 1391 x 92 m at (-70937, -29450), 80 m up). About 25 km west of where
the fighting is. Measured with rays from inside (the `eval` probes, 19 Oct 04:3x):

- The axis: direction (0.28, 0.96) (north-north-east), through (-71107, -29450) in game units.
  Distances `s` below are metres along it, + toward the north portal; "R" is to the right
  looking north (direction (0.96, -0.28)).
- The bore: floor 85-86 m, roof 119-125 m (about 35 m of headroom), 85-100 m wide, about
  1.3 km long (roof from s -650 to s +700). It bends: the middle is 26 m R of the axis at
  s -750, 27 m left at s -150, back on the axis at s +600.

  | s (m) | -750 | -600 | -450 | -300 | -150 | 0 | 150 | 300 | 450 | 600 |
  |---|---|---|---|---|---|---|---|---|---|---|
  | wall R (m) | 77 | 58 | 37 | 19 | 16 | 22 | 28 | 34 | 40 | 44 |
  | wall L (m) | 25 | 31 | 51 | 69 | 70 | 66 | 60 | 53 | 48 | 41 |

- North side: flat ground at 80-90 m for 15 km out along the axis (the easy way in).
- South side: an open cut 50-100 m wide that bends right (toward R: 25 m R at s -800, 150-200 m
  R at s -1200, 300 m R at s -1400), between hills; straight on along the axis the ground rises
  to 113 m at s -1000, 156 m at s -1200, 284 m at s -1400 and 356 m at s -2000. Coming out
  southbound the plane has to climb hard (about 200 m in 750 m) or follow the cut.

### Attempt 1 (19 Oct 04:47): called off

`tools\stunt.py` (lead points s +12 km at 200 m and s +5.5 km at 150 m, then "fly to
(-69413, -23694, 103.5 m) through vision on speed 450 floor 10 then attack"). Called off on the
way to the first lead point: in "fly to" mode the pilot did not defend itself, and two missiles
took 80 health in 20 s (health 31). Fix: `transitDefence` in main.lua, flares in every mode
that is not the fight (no break turns, so a stunt or a canyon route keeps its line).

### Attempt 2 (19 Oct 05:00, run 2026-10-19_0457): did not go in

Started at the beginning of phase 1 with full health; lead points s +9 km (200 m) and s +4.5 km
(150 m) at 850 km/h, the through order 5.7 km out. Flares now came in transit (four missiles
flared away), but one missile and anti-aircraft fire on the approach took health from 120 to
69. **The bot did not enter the tunnel**: 400 m out it judged the way it wanted (straight at the
mouth) blocked and pulled up over the hill, passing 120 m from the aim point. Why: a direction
counted as free only as far as its neighbouring rays in the grid (3 to 4 degrees away) also
went, meant as room for the wings; at 400 m that is 25 m to each side, and a 36 m high mouth is
only 2.5 degrees each way, so the hillside around it made it look shut. Then a second fault:
after the pass the stunt mode fed the vision's own last choice back in as the wanted direction,
and the plane drifted into a vertical climb to 11.7 km before it was called off (the end check
counted only horizontal distance).

Fixes (vision.lua, main.lua): room for the plane is checked in metres, with four rays parallel
to a direction 7 m to each side and 4 m above and below, on the best few candidates and on the
exact wanted direction; after the pass the wanted direction is a 17 degree climb (the roof keeps
it level until the exit) and the stunt ends after 1.5 km in any direction or 15 s. Tested
without flying: `tools\vision-sim.lua` flies a simple simulated plane (fixed speed, turn rate
limit, steering lag) through the real geometry with the real rays, inside the running game.
At 450 km/h from 1.5 km out it passes 2 m from the aim point, stays 38-47 m from the side walls
and 19-21 m from roof and floor, and leaves over the hill 40 m and more above it; also from
30 m off the line and 25 m high, at 550 km/h, and with a slower, laggier plane (15 deg/s,
0.5 s). Wanting level flight after the pass, it cleared the hill by only 8 m.

## Phase 1 is won on points

- The radio only says "Spare Squadron! You haven't done enough damage to the base! Regular
  forces will have trouble attacking." The HUD says what is needed: `SCORE 003480/024000`
  (text block `ScoreInfo`, read 19 Oct 05:28): **24,000 points in 15 minutes**. The pilot now
  puts the HUD's score line and its goal in the status (`hud_score`, `score_goal`).
- The points per kill are in every game object (`GameObject.KillBountyScore`). Alive at 9.5
  minutes into one attempt (263 objects with a bounty, about 52,600 points on the enemy side):
  drones 350 (P2_Drone1-4, 23 of them), Tu-160 1,200 (3), the named F-14D 1,300, fighters
  220-550 (MiG-21 and F-4E 220, F-16C 400, Gripen 500, Mirage 2000 550), AH-64 and SAMs 200,
  AA guns, tanks, ships 150, trucks and BTRs 120.
- Tried: LAAM fighting planes, 7,840 points in 13 minutes (shot down at 14); 8AGM with the
  base first, 3,480 in 9.5 minutes. Now: LAAM and `fly attack score`, every enemy weighed by
  its points against the time to get it (ground targets a little less: an attack run takes
  longer than a missile at a plane).

### Score mode, tries (19 Oct)

| Run | Weapon, rules | Points | Notes |
|---|---|---|---|
| 05:39 | LAAM, score | 5,550 at 7 min | Tu-160s first (3,600 in 2 minutes), then a 1.5-minute duel with one F-16C (52 missiles), then 20 km to three AV-8Bs. Stopped for new rules. |
| 05:49 | LAAM, score + give up after 35 s and 6 missiles + points around each target | 7,960 at 9 min (about 11,500 expected at 15) | The give-up rule wrongly let go of two Tu-160s (they need many hits; it should look at whether the target's health is falling). At the anti-air cluster 600-700 points a minute: one missile per target, but the next target was often 1.2-1.6 km away and off the nose, so 40-50 s loops out and back. Ten break turns in five minutes for missiles predicted to miss by 290-350 m. |
| 06:01 | 8AGM, score + salvos held until four locks (at most 3 s, not inside 2 km) + breaks only for missiles within 200 m while health is above 60 + close, off-nose ground targets rated as needing a loop | 2,000 at 5 min, failed | Without the LAAM the Tu-160s needed standard missiles: 2 minutes of chasing, then the bot followed one out of the combat zone ("Spare 15! Stay within the operation area!") and the mission failed. The game's `CombatZone` box (60 x 60 km around (10, 0) km) is now read and kept to. |
| 06:11 | LAAM, score, zone guard, 1.5 km loops, give-up only while the target's health stalls | about 9,000 | 24 kills; three spells of 1.5-2 minutes without a kill. |
| 06:31 (attempts 1-2, code loaded in flight) | + sweeps through clusters (fly at the points-weighted middle, straight on 1.5 km, turn back) | 8,600 and 9,300 | The first sweep pass: 8 kills in 30 s. Then passes with nothing: the sweep steered at the middle, so each target slid off the nose before its lock built; next, the nose on the chosen target while it is within 45 degrees ahead. |
| 06:31 (attempts 3-4) | + on a pass, the target nearest the nose; no LAAM at drones, standard missiles at them from 1.3-2.2 km only; points per second with learned kill times; cluster bonus for ground only; then (attempt 4) picks within 1.9 km (the standard missile locks within 2.0 km, 32.5 degrees) and only lockable targets (the houses, 100 points each, have no HUD box and no permission to engage) | 10,460 and 13,310 | Best so far. 46 kills in attempt 4. |

**What the remaining points look like** (8.5 minutes into attempt 4, at 8,050 points): 14,790 points
lockable and active, **23,630 not yet active**: fighter waves `AreaA_Add1-4` (north), `AreaB_Add1-4`
(south-east), `AreaC_f16c/f04e/Mig21b` (west), drones `P2_Drone1-4`, the named F-14D. The mission has
three battle areas (`BattleAreaA` around (11, 15) km, `BattleAreaB` (17, -1) km, `BattleAreaC`
(-7, -2) km) with trigger volumes, and the bot fights mostly in B. Next: find what wakes the waves
(`tools\activation-watch.py` logs each group as it switches on, with the plane's position).

### Tunnel, attempt 3 (19 Oct 10:15): hit the hillside beside the mouth

With the tube vision and the climb-out fix, from the start of a checkpoint retry. The plane
reached the second lead point 548 m up instead of 150 m (and at 875 km/h), so the "through"
order began high and fast: a steep descent toward the mouth while braking to 450 km/h, still
above the roof line close in; 380 m out the vision found the wanted way blocked (379 m free,
446 m needed) and swerved (+22 degrees yaw, +20 pitch), into the hillside 118 m from the aim
point. Anti-aircraft fire on the way had taken 54 health. The simulator passes from a steady,
aligned approach at tunnel height; what is missing is that approach: a third lead point about
2.5 km out at 110 m on the axis, flown at 450 km/h, and the "through" order only from there
(and checking that each lead point's height is really reached before going on).

## Where Mission 06 stands (19 Oct 10:20, session stopped)

Not completed. Phase 1 needs 24,000 points in 15 minutes; the best run made about 14,000
(08:41: Typhoon, LAAM, seven campaign parts after the multiplayer parts were cleared, full
throttle in score phases). Runs vary by about 2,000. Ideas not yet tried: plan a route through
the three areas' clusters from the points map (A first for the bombers, then C's two harbours
and SAMs, then B), rather than choosing target by target; the F-15E's TLS laser or SFFS for
ground groups (needs new firing behaviour); a calmer, faster sweep with the gun parts (they
fired, but the run was not better); keeping the bot out of the drone duels until the ground
is cleared.

The Typhoon's parts in the copy's save at the end: Queen's Custom, Electronic Optical Hybrid
Sight (MSL), Multiple Enemy Detection Device (MSL), Infrared Seeker Cooling System, Multiple
Enemy Detection Device (Sp. W), Onboard Self-Defense Jammer, Auto-Strafing Machine Gun Device,
Machine Gun Radar Lock System. (The best run had Directional Proximity Fuze (MSL) and
Thrust-Adjusting Steering Device (MSL) in place of the two gun parts.)

## More cycles (19 Oct 12:10 onward, the owner: "keep going for a few more cycles")

Where the best run's 15 minutes went (one combat line a second, 890 lines): 45% with the target
within 3 km but more than 45 degrees off the nose (turning back after sweep passes, pursuing
planes, and sweep run-ins whose chosen target sat to the side), 15% target ahead but not yet
locked, 11% locked, 10% breaking away from missiles, 18% flying between areas. One tank was
chosen pass after pass for 90 s: from 600-1,100 m up the sweep's 19 degree dive limit never
brought it inside the missile's 32.5 degree lock cone. Changes: sweeps at 450 m, dives to about
30 degrees on the chosen target when there is height, the pass pick out to 40 degrees, the
outbound leg 1.1 km. A break only for missiles within 120 m (with the Jammer part) was tried and
reverted: shot down 8 minutes in, the last hit from a missile it had not broken for.

| Run | Points | Notes |
|---|---|---|
| 12:18 attempt 1 | 7,690 at 8 min, shot down | 120 m breaks (reverted). |
| 12:39 attempt 3 | about 12,200 | Lower sweeps, wider pick, shorter loop; within the usual range. |

Tunnel tries 4 and 5 (three lead points, the last 3 km out at 115 m): the plane still arrived
too high. Cause found in the flying, not the vision: on a "fly to" order the ground check
climbed whenever the lowest ground ahead was within 150 m (a fixed fight margin), so it could
not get below about 150-200 m over the flat approach; and the lead points carried a 60 m floor.
Now the travel orders use their own floor for that check, the last lead point is 2 km out at
108 m with a 15 m floor, and a lead point counts only within 35 m of its height. Try 5 passed
100 m from the aim point, 40 m above the roof line near the mouth, and climbed away unharmed.
The tunnel sits inside area C's anti-aircraft cover (one trigger is even named
"Tonnel_SAM_AtkArea"): every approach takes fire.

### Tunnel try 7 (19 Oct 13:34): through the tunnel

The approach as a route along the tunnel's line (`m06-tunnel-approach.csv`: from 10 km out at
200 m down to 1.2 km out at 104 m, slowing to 450 km/h; the route follower holds line and
height, which "fly to" lead points could not), then "fly to (P) through vision on" when the route
ended. (Order words are split on spaces, so the route file is read from the copy's pilot folder,
`C:\AC7-Coop-Game\UserProfile\pilot\missions\`.) The bot left the route at 104 m, entered the
bore at 490 km/h (the game's own "in tunnel" flag came on), **passed 2.5 m from the aim point,
and flew the bore on live rays alone: 38-49 m to the side walls, 17-23 m to roof and floor** (the
wanted 17-degree climb blocked by the roof, so it held level), and came out the far end. Then a
24-point scrape: the stunt handed back to the fight mode 15 s after the aim point, while the plane
was still 20 m up in the cutting beyond the exit with the hill ahead. Fixed: the hand-over now
waits until nothing is close above or beside and the plane is over 50 m up (40 s at most).

### Tunnel tries 8-10 (19 Oct 13:41-14:02): the full tunnel on live vision

- Try 8: called off on the approach route, missiles and anti-aircraft fire from full health to 5.
- Try 9: in at 0.9 m from the aim point, then into the wall at the bend before the far exit: the
  right wall closed from 47 m to 9 m and the vision only turned away once the straight-ahead way
  was blocked. Fix (vision.lua): **corridor following**. When walls are close on both sides (or
  above and below), a fan of level rays 30 degrees each side finds the deepest free direction,
  and the wanted direction is pulled 70% toward it, so a bend is taken while it is still far
  ahead. In the simulator a slow, laggy plane (10 deg/s, 0.7 s lag) now keeps at least 36 m from
  the walls. Loaded with the new `module vision` order (no full script reload).
- Try 10 (after 4 minutes of normal fighting, so the lead-in leg did not cross the start area's
  fighters): **in at 106 m and 490 km/h, 1.6 m from the aim point, 10.5 s through the whole bore,
  out at 113 m, climbed away, handed back to the fight once clear.** One 24-point scrape at the
  last bend just before the far exit (9 m from the right wall, 8 m from the roof). The 51 health
  lost on the run was anti-aircraft fire.

Remaining for a perfect run: a little more lead into that last bend (a stronger or earlier
corridor pull, or a lower speed inside the bore).

## The lane planner session (19 Oct 2026, 15:50 onward)

Following `score-race-plan.md` with the owner's generality rule first. What was built (all
general: live game data, nothing about this level):

- **Score mode switches on from the HUD** (a visible "SCORE x/y" goal), so `plan.txt` now only
  says `fly attack`. Seen working at once: "score mode ON: the HUD shows a score goal (000000/024000)".
- **Kinds from the game's data**: the native class each unit is built on (`AIPlane`, `AIHeli`,
  `AIGroundVehicle`), the large-plane flag (the Tu-160, and surprisingly the AV-8B too), and for
  drones (Mission 06's `common_uavc_C` carry no UAV component) the game's numbers: the lowest top
  speed of any plane (444 against 519-667) and 40 health; plus a learned rule (a class needing
  more than four times the hits its health asks for, per kill, counts as agile).
- **The lane planner** (`lanes.lua`, mirrored in `tools\lane-sim.py`): twice a second it flies 21
  manoeuvres forward 12 s in a model (turn rate measured in flight, 43-53 deg/s; roll rate and
  current bank; the missile's cone and range from the game; lock time learned from its own
  locks, median 0.3 s; reload learned from launches, 4.4 s with the parts) and flies the one
  that brings the most points into the lock cone; the target is whatever is in the cone,
  nearest the nose; after each launch the next is selected at once (the chain).
- **Where next**: groups of ground targets rated by points per second including the flight
  there and the clearing time at the measured kill rate; air targets rated the same way, with
  the planes flying together counted as one group (the three Tu-160s).
- **General numbers in every report** (`tools\run-stats.py`, built into the report writer):
  time split measured frame by frame, kills a minute (overall and while engaged), kills by kind,
  points, locks and their time, chained picks, breaks and jinks, the plan audit (shots the
  plans expected against launches), what the pilot learned (lock time, reload, turn rate), a
  steering summary from the flight log, the HUD score every 30 s, and the activation log (each
  class of enemy the mission switches on, where, and where the plane was).

**The simulator** (`tools\lane-sim.py`): 6 layout kinds (clusters, rows, scatter, ring,
harbour, mixed), 8 seeds each, the plane's turn and roll rate, the weapon's cone, range, reload
and lock time all varied per scenario. Lanes against the old nose-on attack: 10.1 against 6.1
kills a minute, 93% against 65% of the targets in 3 minutes. Tuning (coordinate descent, kept
only if better on average without hurting the weakest layout kind): discount 20 -> 8 s, pass
height 300 -> 200 m (flown at 250 for hills and flak), cone margin 3 -> 1 deg; a roll-aware turn
model added 4.5% (10% on the weakest kind). Mission 06's real layout at the start of phase 1
(`m06-targets-start.json`, dumped by the new `targets` order; a test case only): lanes 1,876
points a minute on the ground targets against 1,340 for the old way.

**Test runs** (first 8.5 minutes of phase 1, `playtests\orders\m06-lanes-test.yaml`; the old best
run had 8,050 at that point, 3.4 kills a minute, locked 13% of the time):

| Test | Points at 8.5 min | Kills a minute (engaged) | Locked | What it showed, what changed |
|---|---|---|---|---|
| 1 (16:18) | 7,670 | 2.8 (4.1) | 16% | Lanes on mid-attack on a locked Tu-160 (commitment rule added); on/off flipping (hysteresis); the order's 300 m floor kept every pass a ground recovery (lanes: 120 m floor). |
| 2 (16:32) | 9,240 | 4.2 (5.1) | 21% | 1,630 points a minute for 5 minutes, then 370 in the anti-air site; the steering never pulled in most turns. |
| 3 (16:45) | 2,000 | 0.8 | 10% | Broken by two changes of mine: the first learned-agility rule called the Tu-160 agile after one LAAM salvo, and a "level turns" patch made the steering worse. Both replaced. |
| 4 (16:56) | (cut at 3 min) | | | Bank-to-turn steering in: hard-turn time 46% (was 85%), pulling 55% of it (was 24-36%), past 95 degrees of bank 7% (was 22-37%). Showed a bomber chase at 1,980 km/h. |
| 5 (17:03) | 7,380 at 6.3 min, then shot down | 4.7 (6.2) | 26% | Best rates yet (9.2 missiles a minute; the plans 1.4 times optimistic); flew into a bridge: the safety net had chosen a way 3 degrees off its edge (now a three-times-wider tube that prefers climbing). |
| 6 (17:14) | 10,230 | 4.4 (5.8) | 20% | Best 8.5 minutes yet, no crash; 94 of 101 selected targets locked and fired at: the limit is geometry, a new target in the cone every 5 s. |
| full 1 (17:27) | **13,030 at 15:00** | 3.8 (4.7) | 19% | The same build over the whole phase: 12,010 at 10.5 min, then 4 minutes in an anti-aircraft site for 1,000 points; area C (6,650 ground points, 49 targets, and the Gripens) never visited; the 11 drones switched on at 9:00. |
| 7 (17:46) | 9,880 | 4.7 (5.9) | 28% | The owner's defensive attack (29 of them, 16 breaks), tighter turns, full throttle toward far groups: 20 damage only. The plane still flew a median 570 m above its pass height near area B: every kind of hard turn climbed (now slicing turns down). |
| full 3 (18:00) | (4,210 at 3:00) | | | Lost to a script error of mine at 3:20 (a variable used before it was defined); the flight loop now survives its own errors. |
| full 4 (18:08) | 12,870, shot down at 8:43 | **6.4 (7.3)** | 25% | The best pace of the day: 9,330 at 5:00 (the 1,870 a minute 24,000 needs), 10.3 missiles a minute. Two 40-point hits from F-16 missiles fired at 450-850 m, the first predicted within 14 m while the plane only "defended" (now a full break from 3 s for a missile on a collision course), then 30 points of gun chip damage (now the guns that hit it are marked as threats; under 35 health the passes go 200 m higher). |
| full 5 (18:20) | 6,330 at 5:06, stopped | 4.8 (6.4) | 27% | Another F-16 missile hit in minute 3 (predicted to miss by 199.8 m at 2.3 s, 38 m at 0.25 s); stopped to test fighters-first. |
| full 6 (18:29) | **13,360**, shot down at 14:30 | 4.5 (5.2) | 18% | 4 minutes in area A, the remaining 10.7 in area B at 765 points a minute; chose area C only in the last minute (the "leave when it stops paying" rule tightened to 1.15 times the last 60 s). |
| full 7 (18:47) | 750 at 4:00, stopped | 0.5 | 13% | Fighters forced first (after fixing the "who is chasing me" check, which had never worked): four F-16s in a turning fight, 1 killed, two 40-point hits. Reverted: fighters stay weighted as threats, not forced. |
| full 8 (18:54) | 10,710, shot down at 13:20 | 3.9 (4.8) | 24% | Late break rule (full break in a missile's last 2.5 s if still on course); one F-16 hit, then 58 points of gun chip damage. |
| 8AGM (19:12) | 4,280 at 5:00, stopped | 5.2 (**8.9**) | 12% | The 8AGM with the lanes: 14 of 15 salvos at one lock (the game adds no seekers the way the bot flies), yet the best engaged kill rate of the day and 1.1 missiles a kill; one bomber in 5 minutes without the LAAM, 39% transit. A lead, not a result. |

### Where it stands (19 Oct 2026, 19:20)

Not cleared. Every full phase on the new build ended at 10,700-13,400 points or shot down; the
morning's best was about 14,000 with 3.4 kills a minute. What the general numbers say:

- **Kill rate is up, not enough:** best full phase 6.4 kills a minute (7.3 while engaged), locked
  25-28% of the time (11% in the morning). 24,000 needs about 95 kills at the average 250 points:
  6.3 a minute for the whole 15 minutes, with no deaths. Run 4's pace would have made about 23,800.
- **Survival is the limit now:** four F-16s around the start fire a missile every 5-10 s; in most
  runs one or two hit (40 each) in minutes 2-4. Gun chip damage adds 30-60 over a phase in the
  anti-aircraft sites. Aggression (the owner's advice) raised the rate and the losses together.
- **The plan-reality gap:** the planner's plans promise 1.5-1.9 times the shots the plane fires.
  Measured causes found and fixed on the way: the plane flew 300-600 m above its pass height
  (turns climbed), the steering did not pull in half its hard-turn time. Not yet closed.
- **The area tour:** the bot clears area A (bombers, about 5,000) and stays in area B; area C's
  6,650 ground points and the Gripens (2,000) were never reached in time; the 11 drones (3,850)
  switch on at 9:00 between B and C.

**Found afterwards (19:40): the bot runs out of standard missiles.** 112 at the start, 1.6-2.3
per kill, under 20 left between minute 9.6 and 11.5 of every full phase, and the score flattens
from about minute 11 (one run ran dry at 11.6). That is the ~13,000 plateau. Full analysis and
the revised order of next steps: `gap-analysis.md` (ammunition economy first: gun kills on soft
targets, missile discipline, a ground special, then survival and the route). The reports now
show ammunition.

Earlier list, before that finding: (1) survive the F-16s (kill them with the LAAM while they are
still ahead and far, before they turn in; or leave area A faster); (2) close the plan-reality gap
(measure turn and lock performance per manoeuvre against the model; a lower, steadier pass);
(3) an area tour that reaches C by about 9 minutes; (4) the 8AGM as a second ground weapon
(the engaged rate says it is worth it) with the bombers taken first by standard missiles.


**The steering faults found on the way** (general, they were there before the lanes too: the
old best run spent 69% of its time in hard turns and pulled in only 36% of that): an aim behind
the plane asked for an inverted pull that the "no split-S near the ground" rule refused, so the
roll flipped from wing to wing (now a level turn the shorter way round); an aim a little below
the nose did the same (now bank-to-turn: the bank from the heading still to turn, at most
80-88 degrees, the pull once the bank is there); a big change of pitch high up went to the
small-corrections mode and just pushed (now rolled and pulled above 1,500 m); full throttle
toward a target far off the nose reached 1,980 km/h (now only with the target ahead).

## The ammunition session (19-20 Oct 2026, 19:30 onward)

Started from the gap analysis (`gap-analysis.md`): the bot ran out of its 112 standard missiles
by minute 10-11.5 at 1.6-2.3 missiles a kill. Order of work given: the ammunition economy (the
gun, missile discipline, an 8AGM loadout run), then the opening's F-16s, then a phase plan that
reaches area C. Everything below is general (live game data, nothing about this level).

### What the measurements showed

- **The gun.** A `guntest` order (gun only, attack runs carried in close) and a `gun_burst`
  event (the selected target's health before and after each burst). The missile attack runs
  never put the nose within 4 degrees of a ground target (300 m floor, dive limits), so the gun
  never fired. A low strafing pass (`gunnery.lua`) got about 15 damage per 0.8-1.9 s burst from
  1.0-1.2 km and none from 0.9-0.47 km. The bot's own bullets are game objects
  (`plwp_gun_x1_C`, reused by the game), so `gunnery.lua` now follows them and reports where they
  pass the target (`gun_bullets`): about 15 m above and 10 m right at 700-900 m, bullet speed
  about 1,300 m/s. A learned correction ("zeroing") from those passes brought the average to
  -1 m above, +2 m right in the sixth full phase, and the gun killed 5 targets there (an F-16
  among them: 60 health in half a second at 630 m). Not the main weapon, but no longer useless.
- **Houses and other buildings without a target box** (5,430 points): no house, hangar or water
  tower ever died in any run of 19 Oct (the OnDeath hook logs every death); the game marks them
  "permission to engage false, attack-targets exception true". A gun pass at one did not get in
  before the test ended. Not counted on.
- **The missile tracker missed more than half the bot's own missiles.** The game reuses its
  missile objects, so "a new object is a new launch" failed. Now an own missile that stops moving
  has ended, one that moves again has been fired again, and a missile may take its target a look
  later (`awareness.lua`). Every launch has been followed since.
- **Unguided launches: 23% of the standard missiles.** In the lanes the next target was selected
  in the same frame as the fire press, while the fire key was still down, so the game launched
  at the newly selected, unlocked target. The selection now stays 0.25 s after each press. Since
  then: none.
- **Misses were mostly no line of sight.** With every missile followed, the standard missile hit
  ground targets 24 of 29 times from under 1.6 km and 16 of 36 from 1.6-2.2 km, the misses ending
  about 2 s out, short of the target. The far LAAMs at the Tu-160s (5 of 35 hits from 4.4-9.5 km
  on 19 Oct, 12 of 12 from 1.4-4.4 km) ended halfway. A ray trace before each shot
  (`Aware.losBlocked`, the C++ add-on's fast traces) showed the bomber hidden by a hill 2.7 km in
  front of it. Now no missile is fired without a clear line (blocked more than 40 m short of a
  ground target, 60 m of one in the air); in the lanes the target is set aside for a second.
  Since then the standard missile hit ground targets 92 of 94 and 72 of 73 times.
- **Missile discipline**: no more missiles in the air at one target than its health needs
  (`hold_fire` events), so ten LAAMs no longer go at one bomber before the first has ended.
- **Learned firing distances**, both ends, per weapon and kind of target, faster than before
  (`rangeCap`: the split that best separates good shots from bad ones; `rangeFloor`: misses
  from close in). For ground targets a 60% hit rate is asked for.
- **Honest kill times**: the time spent per kind of target over the kills of that kind, the
  engagements that never ended in a kill included (the drones were rated at 35 s a kill and
  took the last five minutes of the third full phase for two kills).
- **The LAAM first for anything in the air** in a score phase (1.2 km to the learned far edge),
  the standard missiles kept for the ground; and **the air shot in passing**: an enemy plane
  inside the LAAM's cone and range while the lanes are flown is selected for a moment and gets
  one LAAM. All four of area A's F-16s fell this way by 4.6 minutes in the fourth full phase, and
  the bot was hardly hit in the opening since. Drones within 6 km too since run 6.
- **The missile economy**: when the standard missiles will not last the phase at the last two
  minutes' rate, only the best share of the shots on offer is taken (each target's value per
  missile: points, the share of its health one missile takes, the threat, the hit rate of its
  class in this fight). With the waste gone it rarely binds.
- **The area moves**: a move between areas is kept unless the place it passes is clearly better;
  only groups of 6 or more targets and 1,000 points count as destinations (a few leftovers rated
  high on points a second and twice called a 23 km move back after 4 s); the "stay" rate is
  checked against the points really scored here once the lanes have run 45 s.
- The 8AGM loadout run was not repeated: with the waste gone the standard missiles last the
  phase, and the LAAM's air shots are worth more (15 planes in the fourth full phase).

### Full phases (`m06-lanes-full.yaml`)

| Run | Build | Score at 15:00 | Kills (engaged a minute) | Missiles a kill | What it showed |
|---|---|---|---|---|---|
| 20:15 | discipline, LAAM first for the air, economy | 12,770 | 54 (4.1) | 1.7 | Standard missiles left at 10 min: 45 (ammunition no longer the cap); flat after 10 min chasing drones; 14 unguided. |
| 20:36 | + air shots, learned window, honest kill times | 12,130, shot down 13:13 | 47 (4.1) | 1.3 | 15 planes killed, area C early, 51 missiles left; worn down by gun chip damage at low health. |
| 20:54 | + line of sight, no reselection for 0.25 s | **21,900** | 109 (10.0) | 1.0 | Ground hits 92 of 94, none unguided; lost 1.5 min dithering on the move to area C; 11 LAAMs and all drones left. |
| 21:13 | + move commitment, LAAM at drones, gun snap | **21,990** | 101 (9.1) | 1.0 | 5 gun kills, bullets centred; minutes 6-10 in a picked-over area B at 500 a minute, then 1,400 a minute in C from 10.9 min. |

The 8.5-minute gun tests (19:46, 19:58) are in `campaign-lanes-test.md`.

### The campaign attempts (`campaign-ace.yaml`, from 21:30)

- **A latent fault: F-16s learned as "agile".** The learned-agility rule counted fire presses as
  missiles; a LAAM press with both rails reloading launches nothing, so after 12 presses for 2
  kills the F-16 class counted as agile and was fought like a drone (opened out from, the LAAM
  withheld): two missile hits and a stuck score in the first campaign attempt (stopped), and the
  same thing at 6.7 minutes in the 20:15 full phase. Now a class counts as agile only from the
  missiles that really flew at it (8 or more followed to their end, under 35% hitting).
- **Moving between areas.** Map of one attempt: area B paid about 5,000 points between minutes
  3 and 4.5 and about 2,000 in the 3.5 minutes after; area C came at minute 9 and paid 1,200-1,400
  a minute. Three causes, all fixed: a fresh group was rated at the fight's average time per kill
  (now the pace of its best minute); the "stay" rate was the plans' own, twice as optimistic as
  what they deliver (now scaled by the plan audit's delivered/promised ratio); an air fight on
  the way cancelled a move and its commitment (now a move taken up again within 30 s keeps it).
  Removing the 20% margin for starting a move sent the first decision of one attempt to area B
  instead of the bombers; the margin stays.
- **"Indecisive" in a furball** (the owner, watching the last minute of a shoot-down): in the
  last 75 s, 8 switches between the lanes and an air target, 3 LAAM air shots at drones that
  never fired (each a weapon switch and back), priority flipping between drones and a SAM site,
  and 10 full breaks (under 40 health every missile predicted within 350 m gets one; 15 missiles
  came at it that minute). Air shots now pause for 45 s at a kind of target after two tries
  without a missile away. The low-health break rule and the lanes/air switching remain open.

- **Committing in dogfights** (the owner, watching a later attempt: "it should be selecting a
  target like an enemy drone or F-16 or other fighter and aggressively committing ... prioritize
  kills ... especially against aircraft already dogfighting it"). A committed "furball" target:
  first any plane or drone tracking the bot within 3 km (kept at least 10 s). In area A it killed
  the four F-16s by 1.9 minutes; in area C the commitments to fighters and drones replaced the
  ground passes (3,900 points there against 6,850 in the 21,900 run; 45 standard missiles came
  home). Narrowed to an aircraft that fired at the bot from within 2.5 km in the last 15 s, then
  without the drones (20 commitments to a swarm of them held the plane four minutes short of
  area C), and dropped after 15 s without a missile fired or a gun hit. Evasion keeps the earlier
  rules outside such a fight; inside it only the last 1.5 s of a missile still on course get the
  full break.
- **A ping-pong between groups**: scaling the "stay" rate by the plans' optimism made every small
  group 6 km away worth a move; the move ended at 6 km, the plane drifted out to 6.1 km, and the
  move began again, seven times in 2.3 minutes. Now a place just arrived at is not a destination
  for a minute.
- **Drones**: they had the threat bonus (they fire), so they out-rated the ground passes, but a
  locked drone 7-17 degrees off at 500-1,000 m got neither a missile (inside the 1.3 km minimum
  for drones) nor the gun (5 degree window). Drones now count their plain points against the
  lanes, and the gun may fire at one inside 900 m within 7 degrees.

- **The 8AGM loadout run** (the gap analysis's item, 20 Oct 00:23, with the fixed build): 3,850
  points at 5:02, stopped. No bomber fell (standard missiles at planes hit 5 of 14 without the
  LAAM's reach), and even its ground minutes paid about 950 a minute against about 2,400 for the
  LAAM build's best ground minutes. With the waste gone the standard missiles last the phase
  anyway; the LAAM stays.
- **Move rules tried and taken out again**: a fresh group rated at the pace of the fight's best
  minute; the "stay" rate scaled by the plans' delivered/promised ratio; only groups more than 6
  km away as destinations. Each moved the plane on sooner but also to small groups, and the
  attempts with them scored 14,500-21,350 against 21,900-22,000 for the rules of the 20:54 and
  21:13 full phases, which are back (with the arrival memory against the ping-pong).

| Campaign attempt | Build (what was new) | Score at 15:00 | Notes |
|---|---|---|---|
| 21:33 | move commitment, drones by LAAM, gun snap | stopped at 5 min | F-16 learned "agile" (the press-counting fault) |
| 21:42 | + agility from real missiles | 21,350 | area C at 8.3 min |
| 22:00 | + best-minute pace | about 18,500, shot down 14:17 | |
| 22:17 | + no move margin | stopped at 8 min | skipped area A's bombers at the start |
| 22:29 | + plans' rate scaled by the audit | 16,140, shot down | the 6 km ping-pong begins |
| 22:48 | + furball (any plane tracking it) | 18,310 | C's ground passes lost to fights |
| 23:08 | + furball drop after 15 s, slower at drones | about 18,000 | |
| 23:27 | furball narrowed to aircraft that fired at it | 15,660 | drone swarm held it 4 min short of C |
| 23:46 | + no drones in the furball, arrival memory | 21,320 | |
| 00:05 | + drones at plain points, gun window | about 17,700 | |
| 00:32 | + destinations only beyond 6 km | about 14,500 | hopped between small groups |
| 00:51 | move rules back to the 21:13 ones | about 17,000 | 6 dogfight commitments in area C |
| 01:10 | furball only for attackers in front, dropped after 8 s | 20,210 and about 19,800 (two attempts) | |
| 01:44 | + the leaving rule (45 s, 60%) | stopped at 6.6 min | left area C 100 s after arriving |
| 01:52 | leaving rule at 90 s, 50%, no going back for 3 min | **about 23,000** (22,520 at 14:45) | left area B at 7.9 min; area C then paid about 1,500 a minute |

- **The leaving rule** (the marginal value theorem of foraging): leave a place once the last
  minute there paid under half of this fight's average points a second (after 90 s there and 2
  minutes of fight), for the best group of 2,000 points or more at least 8 km away, and keep
  going until arrived; never back toward a place left in the last 3 minutes; not if the phase
  ends before the flight and 90 s of work. General and live; the first full attempt with it made
  about 23,000, the best yet.
| 01:52 (attempt 2) | same | about 21,500 | kills on a retry not counted (names reused after a checkpoint restart); fixed |
| 02:29 | + kills counted afresh after a restart | **23,200** | A, then B for 1.5 min, C from 5.2 to 9.7 min, back to B; 101 kills, 11 standard missiles and no LAAMs left |
| 02:45 (attempt 2) | same | about 19,500 | lost most of its health by minute 9 |
| 03:00 (attempt 3) | same | 19,970, crashed at 14:15 | shot down in the drone swarm (they switch on at about minute 8-9 near area C) |
| 03:19 | + the nose flicks onto the plane during an air shot | about 19,500 | air shots fired 16 of 20 (about 1 in 5 before); two missile hits from area C's fighters (an F-16 from 360 m) |
| 03:52 | + air shots at threats first, up to 50 degrees off | 20,610; 22,490; 22,900; 13,480 (at 14:45, four attempts) | the fourth left area A at 2.3 min during the F-16 fight, two bombers (2,400 points) still flying |
| 04:57 | + no leaving while an air target here pays more than the group there | 20,190 | left area A at 2.75 min anyway: a bomber hit twice rated 18.1 points a second against the group's 18.2; the second attempt, 5,740 at 5 min after losing 55 health early, was stopped |
| 05:21 | + a hurt air target rated by its health left (the game's GetHealth over GetMaxHealth), 20% margin before leaving for a group, missile economy forecast from the whole fight | 19,620 | **10,760 at 5 min, the best opening yet** (all three bombers down by 2.5 min); then area C paid about 940 a minute: from minute 10.4 a drone after the plane counted as an engagement, so no move was weighed and it fought the swarm to the end at about 700 a minute, a 3,050-point ground group 7 km away; 21 standard missiles left |
| 05:41 | + a drone is not an engagement (taken in passing; moves still weighed), group air rate at each plane's own kill time, missile economy only past 1.3 times what is left | 22,000 | A for 3 min (all bombers and F-16s), B 3.5-8.4 min at about 1,500 a minute, C from 9 min; 110 kills, every standard missile at a target that died, **3 standard missiles left: ammunition now runs out with the time** |
| 05:57 (attempt 2) | same | 20,120 | an F-16 dogfight at 0.75 min came before the long LAAM shot at the first bomber (attempt 1 got it at 0.67), so area A took 4 minutes; 600 points in minutes 8-10 (the move to C); **11 LAAMs unused**, no drone shot at; 82 damage taken |
| 06:16 | + special weapon "use it or lose it": when more is left than the fight's rate would use in the time left (by 30%, and 2 more), air shots in passing take any aircraft up to 50 degrees off | 18,780 | the rule switched on at 7.96 min and LAAMs went at drones (3 of 4 fired), 5 left at the end; but a hard opening (2,000 points at 2 min, four starts of the move to area B pulled back by the bombers and F-16s) and heavy fire (66 break turns, 52 defensive attacks, 58 damage) |

### 20 Oct, 05:00-06:30: the morning's changes, and what the numbers say

- **A hurt aircraft is worth finishing**: the air target's kill time is scaled by its health left
  (the game's `GetHealth` over `GetMaxHealth`, 0.25 at least), and the leaving rule now asks the
  group elsewhere for the same 20% margin over the air target here as a best-group move does. In
  the two worst attempts before it the bot left area A with two bombers (2,400 points) flying; in
  every attempt since, all three fell.
- **Missile economy**: forecast from the whole fight's launch rate, and only past 1.3 times what is
  left. Every earlier attempt ended with 11-51 standard missiles; now 3-10. **The standard missiles
  and the time now run out together**, so a better phase needs more points per missile, not more
  shots.
- **Drones are not an engagement**: a drone as the target no longer stops the lanes and the moves
  (with it, one attempt fought the swarm for 4.5 minutes at about 700 points a minute while a
  3,050-point ground group waited 7 km away).
- **Special weapon surplus**: LAAMs left over widen the air shots (above).
- **The ceiling**: 112 standard missiles at about 95% kills on ground targets of about 140 points,
  and 30 LAAMs at about 70% on aircraft of about 450, make roughly 25,500 points with nothing
  wasted. 24,000 needs nearly every missile at a target worth its points, inside the 15 minutes.
  Attempts with the morning's builds: 19,620, 22,000, 20,120, 18,780. One attempt varies by about
  2,000 with the order the fights come in (an F-16 dogfight before or after the first long LAAM
  shot at a bomber, whether area C's fighters switch on), more than any one change since 03:00.

- **Air shots that fire**: with the plane flying its ground lane through an air shot, 4 of 5 at
  drones 17-23 degrees off never fired (the drone left the LAAM's cone before the lock). Now the
  nose turns onto the target for those few seconds: 16 of 20 fired in the next attempt, 6 drones
  and 10 planes killed.
- **What still ends attempts**: area C's fighters (2 F-16s, 2 MiG-21s, 2 F-4Es, switching on as the
  plane comes near, plus 4 Gripens) and the 11 drones that switch on at about minute 8-9, firing
  while the plane works the ground and dodges the SAM sites; most missile hits of the evening's
  attempts came from them.
