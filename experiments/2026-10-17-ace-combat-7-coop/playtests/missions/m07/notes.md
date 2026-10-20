# Mission 07 First Contact (story, Ace), the bot's notes

Reached on 20 Oct 2026 at 09:27, straight after Mission 06 was cleared (the campaign order goes on
by itself). Flown with the Typhoon and LAAM (the last used; no mission.txt yet) and the general
attack (not a score race, so no lanes).

The radio: "This mission needs to be quick. Target radar facilities and AA weaponry. They're set up
on rugged terrain and there's a lot of cloud cover. You will be near thunderclouds."

## Attempts

| Attempt | Build | Result | Notes |
|---|---|---|---|
| 09:29 (1) | the Mission 06 build | shot down/crashed at 75 s | rain, a cloud base about 820 m; the ground attacks keep under it, among cliffs that rise into the clouds; the vision safety net reported a blocked way six times in 13 s at 540-830 km/h, and the plane hit a rock face (all 119 health at once) |
| 09:31 (2) | same | stopped at 34 s | for the next build |
| 09:35 | + 500 km/h (braking) for 3 s after each obstacle the vision net reports | shot down/crashed at 169 s | at 1,350 m, 830 km/h between reports, turning hard (the target 99 degrees off at 1.2 km) over rock pillars: 960 m above the ground, then 177 m a second later, then the rock |
| 09:42 | + the caution for 20 s after each report, at 550 km/h; and among obstacles (a report in the last 30 s) the ground runs no longer keep under the cloud base (the shorter lock range in cloud costs less than the pillars) | shot down/crashed at 103 s | now flown at about 590 km/h and 1,000-1,150 m above the ground; a 25-degree dive at the SAM site 01_en_xsam_1_1, 1.5-2 km away behind rock (the lock "invalid" all along): the vision net's free space fell from 980 m to 21 m and the plane hit the rock |
| 09:48 | + no running in at a target with terrain in the line (one ray trace; blocked more than 150 m short: extend and come round again) | stopped at 3.6 min, alive, no kills | no crash for 3.6 minutes (a first), but the check and the "far enough out, turn back in" rule undid each other at 2.6 km: the plane hung there; the first target, SAM site 01_en_xsam_1_1, was about 1 km behind rock |
| 09:55 | + a target hidden behind terrain set aside for 20 s (another one is taken; it comes back from another side later) | stopped at 5.5 min, alive (health 96), 2 kills | the mission's targets (activated at the start): 4 SAM sites (xsam), 3 radar sites, 3 Shilkas, 6 RayCheck AA guns, a VADS and 6 AH-64s; the radar and SAM sites sit in canyons: 10 runs blocked by rock from 3 km in 5 minutes |
| 10:04 | + after a blocked run the next one at that target comes from high (1,600 m above the ground, diving up to about 40 degrees, out by 500 m); set aside only if blocked from above too | shot down/crashed at 73 s | the SAM was set aside at once (checked from 3 km, the high run was judged again before it had climbed; fixed afterwards, untested: the line is checked only inside the 2.6 km turn-back distance); then, flying level at 690 m and 590 km/h, a rock wall: the plane pulled up 32 degrees (the vision net offers climbs up to 30), the wall was taller, and a turn away would have been the way out |
| 11:07 (camp42) | the manoeuvre planner (below) + the attack geometry (an entry point on a clear ray from the target) + a dive's escape rule | **phase 1 cleared at 545 s** (55 s left), phase 2 cleared 426 s later, phase 3 (Mihaly) flown | no crash and full health for 7 minutes; the 7 SAM and radar sites were the objective ("SAM sites down", "All targets destroyed"); the first SAM, in a canyon, took 4.5 minutes: three times the plane reached its entry point and found the line blocked at once (the point is reached from any heading; the turn in takes it off the ray), the third time it worked (40-47 degree dives, kills at 1.75 km); 184 of the first 304 s were transit; flares all gone 102 s in; phase 2 (UAVs over the recon team): 10 UAVs, missiles and the LAAM |
| 11:57 (camp43) | attack lines (`approach.lua`) + the speed-aware brake in the planner + the range cap fix (patched in live) | failed on time in phase 1 at 600 s, 6 of 7 objectives | the six SAM and radar sites outside the canyon fell in pairs: a line, a lock at 1.6-2.3 km, the cluster's radar on a direct line locked in 0.2-0.3 s, both dead within 3 s (at 270, 334 and 400-406 s; camp42 had them at 545 s); the canyon SAM 01_en_xsam_1_1 cost the first 240 s and the last 110: on its 50-60 degree lines at 1,050-1,150 km/h (the brake cannot slow such a dive) the game's lock went to the AA gun 600 m from it, which the bot would not shoot, or the SAM's own missile turned the nose 35 degrees off at 2 km (the defensive attack), and after 8 s pointed at it without a lock it was set aside a minute; two SAM hits (72 health) |
| 12:10 (camp44) | + a lock the game holds on another ground enemy in reach and sight is taken; 650 km/h before lines of 35 degrees or more; the line held longer the longer it has been held; a 12-degree side-step for a missile from the target dived at; the range cap fix built in | **phase 1 cleared at 531 s at full health**; phase 2 failed twice (a recon plane shot down) | the canyon SAM fell at 124 s (in camp43 never); five objectives by 210 s, then 320 s on the north SAM: on its 30-degree line, far out and 1.8 km above it, the line's point lay nearly straight below and the level-turn rule (an aim more than 80 degrees off is a level turn) circled it for 160 s, climbing to 5 km; then one dive killed the SAM, the radar and a helicopter at once. Phase 2: opened out from a UAV 490 m away among the recon team, re-judged it from behind and chased one 9 km off for 96 s; the near one shot down recon A-2 |
| 12:34 (camp45) | + the line point nearly straight below is dived at, not circled; back in a turn radius past the gate (not past the approach point); the smallest dodge that clears a missile (awareness.lua's minDodge, the owner's advice), grown 2.5% at a time while dodged missiles hit too often; a close drone being opened out from stays the target; the 550 km/h cap 4 s after the planner's last adjustment (was 20) | **phase 1 cleared at 355 s with no damage at all**; phase 2 failed twice (recon A-1, then D-1) | phase 1: the canyon SAM at 121 s, then pairs at 202-231, 280 and 355 s; time to 304 s: transit 155 s, target more than 45 degrees off the nose 92, full breaks 19, defensive attack 16, ahead 15; 46 dodge choices, jumping 25-0-35-0 degrees for one missile within a second (made to grow only, per missile, afterwards). Phase 2: 76 s on one evasive UAV opened out from three times while the A group shot recon A-1 down |
| 12:49 (camp46) | + an enemy chasing an ally weighted up to 5 times more the closer it is to that ally; straight for the approach point until 2.5 km from it; the planner's margin 60 m; one missile's dodge only grows | phase 1 cleared at 474 s, no damage; phase 2 failed (recon A-2 at 122 s) | phase 1: the game's lock on the AA gun beside the canyon SAM was taken and the gun killed, the SAM 84 s later. Phase 2: the weights rose to about 1,500 and swung with each UAV's distance to its recon plane; the bot went for UAVs 10-13 km away one after another (A-1, D-1, C-1, C-2) and killed nothing from 18 to 122 s. In camp42, which cleared the phase, it kept each UAV until it died, one every 20-35 s. The factor was taken out |
| 13:07 (camp48) | the distance factor out; an enemy chasing an ally that lost health in the last 10 s counts 4 times; full throttle to a target more than 6 km away within 30 degrees of the nose, in any fight | phase 1 cleared at 358 s at full health, then shot down/crashed 8 s later | after the phase cleared the bot took a leftover AA gun 1.5 km off and dived at it at 780 km/h among rock pillars; the ground check saw ground 115 m ahead, the planner's last turn came 0.6 s before a pillar about 1.1 km high (96 damage at once). The planner's margin had been lowered to 60 m on the wargame's word; the survey's 50 m grid smooths such pillars away, so it went back to 80 |
| 13:17 (camp49) | the margin back to 80 m; no last-instant full break for a missile a small dodge was found to clear | **MISSION 07 COMPLETED on the first attempt (1,292 s)**: phase 1 in 183 s with no damage, phase 2 in 347 s with no recon plane lost, phase 3 (Mihaly) in 540 s | phase 1: the canyon SAM at 80 s, then pairs at 116, 152 and 183 s; in the first 124 s the target was more than 45 degrees off the nose for 16 s (13%; camp45 30%), transit 76 s, 2 full breaks and 5 dodges in the whole phase. Phase 2: all 11 UAVs, one every 15-50 s in order (B-1, B-2, C-1, A-1, C-2, A-2, D-1, D-2, D-3, A-3, C-3), health 120 to 81. Phase 3: Mihaly (320 health) and two Sol Squadron Su-30s (120 each), none flagged TGT by IsTGT(); five missiles missed him in the first 70 s, the cap learned 2 km, and the learned minimum range rose to 2.2 km (the farthest of all-missed shots): no shot for two minutes while locked on him at 0.8-1.8 km; patched live at 13:32 (no minimum without a hit farther out), then seven missiles in a minute and hits: 314.7, 261.4, 240, 200 health, and at 13:37 he broke off and the phase was cleared (the bot at 41 health) |

## The manoeuvre planner (20 Oct 2026, 10:20 onward; the owner: "overall, general improvement to
## the bot's pathfinding, maneuvering, innate knowledge of its own aircraft's capabilities and how
## to use them in maneuvering, and decision making ... decisiveness")

1. **The plane, measured** (`tools\aircraft-model.py` over six Mission 06 attempts' flight logs,
   `playtests\aircraft\typhoon.json`): the flight path turns 38-43 degrees a second with a full
   pull at 300-500 km/h (radius about 170 m at 450 km/h, 320 m at 800); the roll is 80 degrees a
   second typical, 130 at full stick; throttle adds about 14 m/s each second in level flight, the
   high-G turn costs about 10, and the brake takes off about 70 (800 to 500 km/h in a little over
   a second).
2. **The ground, surveyed** (the pilot's `survey` order: 561,501 heights every 50 m over 35 x 40 km
   in 16 s; `terrain-50m.csv`): median 657 m, a tenth above 1,500 m, peaks 2,517 m.
3. **The wargame** (`tools\maneuver-sim.py`): ground attack runs as main.lua flies them at the
   mission's targets, from random starts, two minutes each, with each safety layer:

   | Layer | Runs that crashed | Crashes an hour of flying | Shots a minute |
   |---|---|---|---|
   | none | 92% (120 runs) | 104 | 0.74 |
   | today's straight-ray net (vision) | 64% (200) | 28.5 | 0.78 |
   | planner, first version | 4-5% | 1.3-1.7 | 0.88-0.92 |
   | + must end where a pull-out is possible | 1.5% (200) | 0.5 | 0.90 |
   | + holds its choice 1.5 s, prefers comfortable clearance | 1.3% (300) | 0.4 | 1.11 |

   Tried and dropped: the manoeuvre's own roll and pull as the aim (22.5% crashed); its point one
   second ahead as the aim works. A test at a 2 km wall 1 km ahead showed the indecision the
   owner had seen in fights: six different ways to turn in two seconds, waiting, then the wall;
   holding the choice fixed it.
4. **In the pilot** (`maneuver.lua`, from main.lua's apStep in fights): four times a second, the
   wanted way flown ahead 5 s and traced with the engine's own line traces (each step and 80 m
   beyond it, and 80 m below), ending where a pull-out is possible; kept when clear with half as
   much again to spare; otherwise 50 candidates (lift up, down or to the sides at 30-degree steps,
   pull 0.6 or full, keeping speed or braking), the safe one closest to the wanted way, held
   1.5 s; its point one second ahead is the aim, and the brake comes on with it. It replaces the
   straight-ray safety net in fights; the ground recovery's straight lines stand down while it
   has a clear way (60 m over the ground is still an emergency). The speed table learns in flight.

## Attack lines and the plane's speed (20 Oct 2026, 11:20 onward)

1. **Where each target can be seen from.** From each of the mission's 17 ground targets (their
   positions read from the game at 11:11), rays in 16 directions at 10-80 degrees, 3 km long, over
   the survey: nine of them are open from almost every side at 10 degrees (the mountaintop SAM,
   radar and AA gun at 2,290 m; the three AA guns in the middle; the far east guns), the others
   sit in canyons: SAM site 01_en_xsam_1_1, the one camp42 spent 4.5 minutes on, is seen only from
   30-80 degrees up, and from one side not at all. The entry point of 11:07 was reached from any
   heading, and the turn in at the point took the plane off its ray (blocked 721 m and 1,363 m
   short at once); and its rays started 30 m above the target, the pilot's own sight check 3 m.
2. **Attack lines** (`approach.lua`): the target's visibility map (the same rays, with the
   engine's traces, 3 m up); a usable line also has 10 degrees lower clear and a side neighbour
   clear; the line the plane is on soonest (the way to its point 3 km out, the climb, the two
   turns at the measured turn rate); held unless another is 4 s sooner. Flown onto from outside
   with a point 800 m down the line as the aim (the line falls toward the target at its angle:
   that is the dive), repositioning out along it two turn radii to the side when inside the
   gate, a line found blocked dropped for 30 s, and a target in sight ahead attacked on the line
   the plane is on (the next of a cluster, no going round).
3. **The wargame** (`SIM_LINE=1`, ten-minute flights at all 17 targets, the nearest next):

   | Approach | Shots a minute | Crashes |
   |---|---|---|
   | entry points (the 11:07 build) | 1.13 | 3 of 160 |
   | attack lines, gate 2.4 km | 3.12 | 0 of 160 |
   | gate 2.0 / 2.2 / 2.8 km | 3.25 / 3.20 / 2.88 | 0 / 4 / 1 of 192 |
   | carrot 500 m / 1.2 km (800 m kept) | 3.15 / 2.79 | 0 / 0 of 96 |
   | without "10 degrees lower clear too" | 3.00 | 2 of 192 |
   | the next target by line cost, not nearest | 2.89 | 0 of 160 |

   Two kinds of crash were found and fixed in both the sim and the module: the turn back onto the
   line from behind it was a split-S (an aim behind the plane with a small downward part: the
   pull went down), now any aim more than 80 degrees off the nose is a level turn toward its
   side; and the turn onto the line is kept within -8..+17 degrees while the line is more than
   70 degrees off. Gate 2.2 km and approach point 3 km in the module (the game's lock on ground
   targets came at about 1.77 km).
4. **The plane's speed, measured again** (`tools\aircraft-model.py`, now by climb angle and speed
   together, 145 logs of Missions 06 and 07): the turn rate hardly changes with speed (37-43
   degrees a second from 300 to 1,600 km/h, so the radius grows with speed: about 400 m at
   850 km/h, 650 m at 1,150); the brake takes 46 m/s each second off at 600 km/h level, 63 at 800,
   98 at 1,200, but in a 30-60 degree dive it only holds the speed (0 to -9): a steep dive is flown
   at the speed it starts with. The planner (`maneuver.lua`) has this table now and keeps learning
   it in flight. Slowing to 600 km/h before steep lines did not help in the wargame (5 crashes in
   192 flights against none), so the lines are flown at 1,150 km/h beyond 4.5 km, 850 to 2.6 km,
   700 after.

## Where it stood before that (20 Oct 2026, 10:10)

Not cleared: six attempts, four ended against rock within 73-169 s, the others stopped by hand for
the next build; two kills in the best one. Mission 07 is a terrain mission: radar and SAM sites in
canyons among pillars and cliffs that rise into the clouds, rain, and a cloud base about 820-870 m.
The bot's general attack (not the lanes: this is not a score race) and its obstacle handling were
built for open ground and for the narrower cases of Missions 04 and 14. What helped: slowing down
near obstacles, not keeping under the cloud base among them, not running in at a target with rock
in the line (one attempt lived 3.6 minutes). What is still missing, as a work package:

1. Turning away from a wall the plane cannot climb over (the vision net's fan offers climbs up to
   30 degrees; the free direction it picks is the one nearest the wanted way, not the safest).
2. Cruising and turning above the highest ground around (within 2 km), not a set height above the
   ground directly below (in a canyon that is far below the peaks next to it).
3. Attacking canyon targets from above: the vertical attacks of the lanes (Mission 06) are not
   used outside score races; a steep approach from high is what the radar and SAM sites need.
