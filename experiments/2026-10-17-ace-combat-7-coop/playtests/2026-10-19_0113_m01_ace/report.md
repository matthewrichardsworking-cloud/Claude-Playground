# Playtest: Mission 01 ace

Run 19 Oct 2026, 01:13 by tools\campaign.py (story mode); difficulty ace, mode fair.

**Completed on attempt 1 of 1.**

| Attempt | Result | Why it ended | Time | Kills | Missiles fired (special) | Damage taken | Missiles at us (lock broken) | Score |
|---|---|---|---|---|---|---|---|---|
| 1 | completed | mission accomplished | 7.6 min | 18 | 7 (24) | 0 | 0 (0) | 11960 |

## Attempt 1

- 00:11 takeoff end: after_s=9.952, ok=True
- 00:12 ground recovery: above_ground_m=90.42, alt_m=90.44, lowest_ahead_m=90.42, vz=0
- 00:27 phase cleared: MissionPhase_01
- 00:28 phase start: MissionPhase_02
- 01:17 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9499 m)
- 01:23 destroyed 00_en_bomber_1_1023  (None missiles, 0 s after picking it)
- 01:23 weapon switch to standard missiles (nothing selected; the special weapon hides some targets, target -1 m)
- 02:41 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9500 m)
- 02:42 weapon switch to standard missiles (no longer: beyond standard missile range, target 9761 m)
- 02:44 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9225 m)
- 02:47 destroyed 00_en_bomber_2_3167  (None missiles, 0 s after picking it)
- 02:47 destroyed 00_en_fighter_1_1  (None missiles, 0 s after picking it)
- 02:53 weapon switch to standard missiles (no longer: beyond standard missile range, target 12100 m)
- 02:55 destroyed 00_en_fighter_1_2  (None missiles, 0 s after picking it)
- 03:13 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9499 m)
- 03:20 destroyed 02_en_bomber_3_983  (None missiles, 0 s after picking it)
- 03:20 destroyed 02_en_bomber_3_1847  (None missiles, 0 s after picking it)
- 03:27 destroyed 02_en_fighter_2_2  (None missiles, 0 s after picking it)
- 03:27 destroyed 02_en_fighter_2_1  (None missiles, 0 s after picking it)
- 03:28 weapon switch to standard missiles (nothing selected; the special weapon hides some targets, target -1 m)
- 03:43 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9498 m)
- 03:48 destroyed 02_en_bomber_4_2891  (None missiles, 0 s after picking it)
- 03:55 destroyed 02_en_fighter_3_1  (None missiles, 0 s after picking it)
- 03:55 weapon switch to standard missiles (nothing selected; the special weapon hides some targets, target -1 m)
- 04:49 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9498 m)
- 04:56 destroyed 02_en_bomber_5_1411  (None missiles, 0 s after picking it)
- 05:06 weapon switch to standard missiles (no longer: beyond standard missile range, target 1798 m)
- 05:08 destroyed 02_en_fighter_4B_1  (None missiles, 0 s after picking it)
- 05:10 destroyed 02_en_fighter_4_1  (None missiles, 0 s after picking it)
- 05:31 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 1802 m)
- 05:36 weapon switch to standard missiles (no longer: beyond standard missile range, target 23040 m)
- 05:38 destroyed 02_en_fighter_4C_1  (None missiles, 0 s after picking it)
- 06:14 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9497 m)
- 06:16 weapon switch to standard missiles (no longer: beyond standard missile range, target 10120 m)
- 06:18 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9497 m)
- 06:20 destroyed 02_en_bomber_6_2  (None missiles, 0 s after picking it)
- 06:21 destroyed 02_en_bomber_6_1  (None missiles, 0 s after picking it)
- 06:28 destroyed 02_en_bomber_6_3  (None missiles, 0 s after picking it)
- 06:29 destroyed 02_en_bomber_6_4  (None missiles, 0 s after picking it)
- 06:29 phase cleared: MissionPhase_02
- 06:29 weapon switch to standard missiles (nothing selected; the special weapon hides some targets, target -1 m)
- 07:34 **mission accomplished**
- 07:36 how well enemy positions 2 s ahead were predicted: route planes: 253 checks, the guess used was off by 16 m on average (each way: route 16 m, straight 19 m; now using route); steady planes: 2153 checks, the guess used was off by 28 m on average (each way: full turn 28 m, half turn 28 m, straight 28 m; now using full turn); turning planes: 2255 checks, the guess used was off by 72 m on average (each way: full turn 116 m, half turn 70 m, straight 95 m; now using half turn)

## Notes

- Story mode, flown by tools\campaign.py (ace).

Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), pilot.log (the pilot's commentary), pictures\, saves-check.txt.
