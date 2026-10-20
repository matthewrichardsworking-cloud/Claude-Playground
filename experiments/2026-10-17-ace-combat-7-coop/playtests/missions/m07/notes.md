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

## Where it stands (20 Oct 2026, 10:10; session stopped here)

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
