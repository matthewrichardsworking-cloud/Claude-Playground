# Playtest: Mission 01 first-run

Run 18 Oct 2026, 12:37 by hand, from a Claude session (tools\pilot.py); difficulty casual, mode fair.

**Completed on attempt 2 of 2.**

| Attempt | Result | Why it ended | Time | Kills | Missiles fired | Damage taken | Missile warnings | Score |
|---|---|---|---|---|---|---|---|---|
| 1 | failed | left the mission area (the session's test order ran out after 400 s and the plane flew on unattended) | 10.3 min | 8 | 33 | 0 | 0 | 4880 |
| 2 | completed | mission accomplished | 9.4 min | 19 | 80 | 0 | 0 | 12180 |

## Attempt 1

- 00:11 takeoff end: after_s=10.42, ok=True
- 00:12 ground recovery: alt_m=106.2, vz=0
- 00:21 phase cleared: MissionPhase_01
- 00:22 phase start: MissionPhase_02
- 04:43 destroyed 00_en_bomber_1_1023  (5 missiles, 70 s after picking it)
- 07:09 destroyed 00_en_fighter_1_1  (4 missiles, 72 s after picking it)
- 07:14 destroyed 00_en_fighter_1_2  (4 missiles, 5 s after picking it)
- 07:32 destroyed 00_en_bomber_2_3167  (5 missiles, 18 s after picking it)
- 08:15 destroyed 02_en_bomber_3_1847  (4 missiles, 28 s after picking it)
- 08:18 destroyed 02_en_bomber_3_983  (3 missiles, 3 s after picking it)
- 08:25 destroyed 02_en_fighter_2_1  (3 missiles, 6 s after picking it)
- 08:40 destroyed 02_en_fighter_2_2  (5 missiles, 15 s after picking it)
- 10:17 **out of zone**

## Attempt 2

- 00:00 phase start: MissionPhase_02
- 01:44 destroyed 00_en_bomber_1_1023  (5 missiles, 102 s after picking it)
- 03:38 destroyed 00_en_fighter_1_1  (5 missiles, 61 s after picking it)
- 03:43 destroyed 00_en_fighter_1_2  (4 missiles, 6 s after picking it)
- 04:03 destroyed 00_en_bomber_2_3167  (6 missiles, 20 s after picking it)
- 04:42 destroyed 02_en_bomber_3_1847  (5 missiles, 33 s after picking it)
- 04:49 destroyed 02_en_bomber_3_983  (6 missiles, 7 s after picking it)
- 04:53 destroyed 02_en_fighter_2_1  (3 missiles, 4 s after picking it)
- 04:58 destroyed 02_en_fighter_2_2  (4 missiles, 5 s after picking it)
- 05:30 destroyed 02_en_bomber_4_2891  (4 missiles, 28 s after picking it)
- 05:39 destroyed 02_en_fighter_3_1  (2 missiles, 9 s after picking it)
- 06:37 destroyed 02_en_fighter_4C_1  (5 missiles, 40 s after picking it)
- 06:42 destroyed 02_en_fighter_4B_1  (3 missiles, 5 s after picking it)
- 06:45 destroyed 02_en_fighter_4_1  (3 missiles, 3 s after picking it)
- 07:19 destroyed 02_en_bomber_5_1411  (6 missiles, 34 s after picking it)
- 07:59 destroyed 02_en_fighter_5C_2  (4 missiles, 38 s after picking it)
- 08:05 destroyed 02_en_bomber_6_4  (4 missiles, 6 s after picking it)
- 08:10 destroyed 02_en_bomber_6_3  (4 missiles, 5 s after picking it)
- 08:16 destroyed 02_en_bomber_6_1  (4 missiles, 5 s after picking it)
- 08:20 destroyed 02_en_bomber_6_2  (3 missiles, 5 s after picking it)
- 08:21 phase cleared: MissionPhase_02
- 08:49 ground recovery: alt_m=1921, vz=-429.4
- 08:49 ground recovery: alt_m=1885, vz=-421.1
- 09:19 ground recovery: alt_m=1381, vz=-294.1
- 09:19 ground recovery: alt_m=1375, vz=-305.1
- 09:19 ground recovery: alt_m=1370, vz=-312.7
- 09:27 **mission accomplished**

## Notes

- Driven by hand from a Claude session with tools\pilot.py (orders 'takeoff', then 'fly attack'), before tools\playtest.py existed; attempt 2 is 'Retry from checkpoint', which restarts phase 2 (after the take-off).
- Plane: Typhoon with LAAM (the copy's last-used setup). Casual: missiles and gun unlimited.
- No damage taken in either attempt; no missile warnings were logged (Casual enemies rarely fire at this range).
- Score 12,180 at the end of attempt 2, the same as the second-best score on the owner's own Mission 01 record.

Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), pilot.log (the pilot's commentary), pictures\, saves-check.txt.
