# Playtest: Mission 01 hard

Run 18 Oct 2026, 13:50 by tools\playtest.py goto, then the orders takeoff and fly attack by hand; difficulty hard, mode fair.

**Completed on attempt 1 of 1.**

| Attempt | Result | Why it ended | Time | Kills | Missiles fired | Damage taken | Missile warnings | Score |
|---|---|---|---|---|---|---|---|---|
| 1 | completed | mission accomplished | 12.2 min | 18 | 90 | 0 | 2 | ? |

## Attempt 1

- 00:00 phase start: MissionPhase_01
- 00:23 takeoff end: after_s=9.783, ok=True
- 00:24 ground recovery: alt_m=123.3, vz=0
- 00:34 phase cleared: MissionPhase_01
- 00:35 phase start: MissionPhase_02
- 02:31 destroyed 00_en_bomber_1_1023  (4 missiles, 116 s after picking it)
- 04:41 destroyed 00_en_fighter_1_1  (5 missiles, 76 s after picking it)
- 04:47 destroyed 00_en_fighter_1_2  (4 missiles, 5 s after picking it)
- 05:15 destroyed 00_en_bomber_2_3167  (5 missiles, 28 s after picking it)
- 05:57 destroyed 02_en_bomber_3_1847  (5 missiles, 37 s after picking it)
- 06:08 destroyed 02_en_bomber_3_983  (8 missiles, 10 s after picking it)
- 06:09 destroyed 02_en_fighter_2_1  (1 missiles, 2 s after picking it)
- 06:13 destroyed 02_en_fighter_2_2  (3 missiles, 3 s after picking it)
- 07:08 destroyed 02_en_bomber_4_2891  (3 missiles, 31 s after picking it)
- 07:17 destroyed 02_en_fighter_3_1  (3 missiles, 9 s after picking it)
- 08:07 destroyed 02_en_fighter_4C_1  (4 missiles, 38 s after picking it)
- 08:49 destroyed 02_en_bomber_5_1411  (9 missiles, 42 s after picking it)
- 09:12 destroyed 02_en_fighter_4_1  (9 missiles, 22 s after picking it)
- 09:55 destroyed 02_en_fighter_5C_3  (5 missiles, 43 s after picking it)
- 09:59 destroyed 02_en_bomber_6_1  (3 missiles, 5 s after picking it)
- 10:05 destroyed 02_en_bomber_6_3  (4 missiles, 6 s after picking it)
- 10:14 missile warning: level=near
- 10:17 missile warning: level=very near
- 10:17 flare
- 10:30 destroyed 02_en_bomber_6_4  (6 missiles, 25 s after picking it)
- 11:09 destroyed 02_en_bomber_6_2  (9 missiles, 39 s after picking it)
- 11:09 phase cleared: MissionPhase_02
- 12:14 **mission accomplished**

## Notes

- Flown with the awareness tracker running (enemy and missile tracks) but before the tracker drove any decisions: defence was still the game's 'very near' warning (flare and break).
- One enemy missile was aimed at the plane (infrared, from a MiG-21 at 1.9 km); the flare at 790 m broke its lock at once and it passed 800 m away.
- No damage taken. Health on Hard is 120 (240 on Casual).

Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), pilot.log (the pilot's commentary), pictures\, saves-check.txt.
