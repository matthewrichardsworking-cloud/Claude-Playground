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

Next, in order of expected value: (1) survive the F-16s (kill them with the LAAM while they are
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
