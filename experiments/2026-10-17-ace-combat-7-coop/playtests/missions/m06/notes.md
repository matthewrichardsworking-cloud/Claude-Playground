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
