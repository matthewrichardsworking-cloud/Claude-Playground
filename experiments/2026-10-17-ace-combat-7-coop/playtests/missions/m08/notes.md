# Mission 08 Pipeline Destruction (story, Ace), the bot's notes

Reached on 20 Oct 2026 at 13:41, straight after Mission 07 was completed (the campaign order goes on
by itself). Flown with the Typhoon and LAAM (the last used; no mission.txt yet) with the day's
build: the lanes and sweeps of Mission 06 (a score race), the manoeuvre planner, the speed-aware
plane model, the minimum missile dodges.

The radio: "Target in sight. I see a lot of oil tanks." "The boats aren't warships. There are
plenty of buildings too." The HUD: SCORE 000000/022000, a phase of about 5 minutes; then "Dust
cloud is entering the area of operations. Finish your work."

What the mission switches on (the pilot's eval at 13:47, 225 active enemies): oil tanks of many
sizes (about 120), oil facilities (about 60), chimneys (13), four tankers (TGT_P1_Tanker, 500
points each, the most valuable things there; IsTGT() false), AA guns (20), six SAM sites, three
T-90 tanks, two AH-64s, six F-15Cs.

## Attempts

| Attempt | Result | Notes |
|---|---|---|
| 13:41 (1) | failed on time: 16,050 of 22,000 at 301 s | 137 kills on the HUD, 118 health, 51 missiles left (time, not missiles, was short); 3,200 points a minute against 4,400 needed; to 244 s: locked 70 s, target off the nose 54, ahead 50, transit 44, defending 13; 59 chained picks, 17 vertical dives; deaths counted: 71 oil tanks, 38 facilities, 26 optional enemies, 12 chimneys, one tanker |
| 13:47 (2, from the checkpoint) | failed on time: 15,150 at 301 s | 119 kills on the HUD, health 91, 54 missiles left; then a fresh start with the 8AGM (mission.txt) |
| 13:55 (camp50, 8AGM, fresh start) | failed on time: **21,750 of 22,000** at 300 s | 179 kills on the HUD, health 117, every 8AGM fired, 45 standard missiles left; with the LAAM 13,000 by 245 s, with the 8AGM 18,800 |
| 14:01 (camp50, 2, from the checkpoint) | failed on time: 19,370 at 300 s | 151 kills, health 120, the 24 8AGMs all fired (each at its own target, one missile a lock; the last at 231 s in the first try), 48 standard missiles left |
| 14:06 (camp50, 3, from the checkpoint) | failed on time: 18,570 at 300 s | 149 kills, health 115 |
| 14:16 (camp51, chain values, fresh start) | failed on time: 18,600 at 300 s | 167 kills, health 78 (one 40-point hit at 218 s), 13 full breaks (16 s), a stall from 154 to 215 s; one attempt, inside the spread of the others |
| 14:22 (camp51, 2, from the checkpoint) | failed on time: **21,490** at 300 s | the fastest start yet (14,000 at 124 s, 20,540 at 245 s); the 8AGMs gone by about 230 s, then 950 points in the last 55 s: 25 targets left near the plane (the lanes' rate fell from about 90 to 20 points a second) and the F-15Cs hunting it from 440-1,300 m, five full breaks in 50 s; no return line in this mission (the pilot's Gim.returnLine(): none) |
| 14:27 (camp51, 3, from the checkpoint) | failed on time: 21,140 at 300 s | 18,920 by 185 s (the fastest), then 2,200 in two minutes; four 8AGMs left |
| 14:32 (camp51, 4, from the checkpoint) | **phase 1 CLEARED: 22,690 of 22,000** (at 305 s) | health 80; 20,290 at 245 s, 22,390 at 275 s; then phase 2: "Megastorm Inessa 2", fuel trucks escaping (22: 18 common_tnkl, 2 ms08_tnkl, 2 geck), "burn down everything that turns up", 10 minutes, 52 missiles left against an estimated need of about 113 |
| 14:38 (camp51, 4, phase 2) | phase 2 failed (objective lost) at 601 s | 7 of the 22 fuel trucks killed (four in the first 21 s, then one at 120, 197 and 298 s), nine of the optional UAVs, score 26,330; time: transit 291 s, target off the nose 176, locked 165, ahead 145, defend 47, break 41; the lock taken from the game 143 times (the game's lock and the bot's choice taking turns): from 14:51 the lock is only taken for a target the game would not select or lock, at most once in 5 s |
| 14:51 (camp52, the lock rule narrowed, fresh start) | failed on time: 17,900 at 300 s | 11,750 by 124 s, then 1,400 in two minutes: 90 s committed to the F-15Cs "after us" (the furball rule) for one F-15C (550) and two AA guns, while the lanes rated their targets at 38-73 points a second against 22-31 for the air target |
| 14:57 (camp52, 2, from the checkpoint) | **phase 1 CLEARED again: 22,940** (15:02) | 11,150 by 124 s, 21,440 by 245 s, health 118 |
| 15:02 (camp52, 2, phase 2) | shot down or crashed at 15:08:39 (about 6.5 minutes in) | health 118 to 77 by about 600 s (missile hits from UAVs), then 77 to 0 at once at 920 m above the ground, diving 25 degrees at 887 km/h with the nose 2 degrees off a UAV it was chasing: most likely a collision with it (not confirmed); the score 25,060; the session's six hours ended here and the copy was closed |

## What dies with a kill

In the 21,750 attempt the bot's own missiles were credited with 88 kills and 12,200 points; the
HUD counted 179 kills and 21,750. The other 91 kills (9,550 points, 44%) were things dying
around what the missiles hit: oil tanks set off their neighbours. 90 launches in 300 s, two
weapons on their reloads, so the pace has to come from points per missile, not more missiles.
From 14:18 the pilot learns it (main.lua, `killTally.chainNote`/`chainValue`): per class of
target, its kills, the targets within 400 m of each, and the points of those that died within
1.5 s and 400 m of it without the bot firing at them; points per neighbour times a target's live
neighbours is added to its value in the lanes once its class has three kills. No names: a class
that sets nothing off stays at its own points.

## Next steps (20 Oct 2026, 14:30)

1. The F-15Cs (550 points each) hunting the plane: in camp52 the furball rule (commit to aircraft
   after it, the owner's Mission 06 advice) held the plane 90 s on them for 850 points while the
   lanes rated their own targets at 38-73 points a second against 22-31; in camp51 their missiles
   cost five full breaks in the last minute. In a score phase the commitment could be weighed on
   points a second, overriding the lanes only when the attacker threatens the plane's survival.
2. The last minute's pace: the 8AGMs are gone by about 230 s and the area near the plane is
   thinned out; moving on to the next group earlier, or keeping a few 8AGMs for it.
3. What is left late (attempt 4 at 254 s, 20,390 points, the pilot's eval): three 500-point tankers
   alone 4.3-6.7 km away, an F-15C or two, groups of 3-8 oil tanks 3-4 km off. A move to another
   group needs 6 targets and 1,000 points and more than 6 km (Mission 06's rules against hopping
   between leftovers); closer, the lanes' 12-second plans do not reach them. Planning for single
   high-value targets a few km off in a worked-out area is the gap.
