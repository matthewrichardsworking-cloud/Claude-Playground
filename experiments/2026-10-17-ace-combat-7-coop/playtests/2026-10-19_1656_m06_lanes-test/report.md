# Playtest: Mission 06

Run 19 Oct 2026, 16:56 by tools\playtest.py; difficulty ace, mode fair.

**Not completed** in 1 attempt(s).

| Attempt | Result | Why it ended | Time | Kills | Missiles fired (special) | Damage taken | Missiles at us (lock broken) | Score |
|---|---|---|---|---|---|---|---|---|
| 1 | stopped | time limit or stopped | 3.4 min | 5 | 17 (4) | 0 | 5 (5) | ? |

## General numbers (tools\run-stats.py)

Attempt 1:
- Time split over 3.0 min (pilot's frame-by-frame split): locked 15%, ahead 5%, offnose 26%, break 4%, transit 48%, recovery 2%.
- Kills 5 (1.7 a minute; 3.4 a minute while engaged), missiles 17 (5.7 a minute, 3.4 per kill), special weapon 4.
- Kills by kind (game data): large 1, plane 4.
- Points from kills (the game's bounty per kill): 2800.
- 7 locks (median 4.8 s from selection); 4 break turns, 2 jinks; 0 damage taken.
- Score on the HUD: 0:06 000000/024000, 1:06 000000/024000, 2:06 001600/024000, 3:06 001600/024000.

## Attempt 1

- 00:02 score mode: goal=24000, hud=000000/024000, on=True, why=the HUD shows a score goal
- 00:02 kind: class=ms06_WatchTower_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Warehouse_C_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Warehouse_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Warehouse_A_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Warehouse3_Wide_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Warehouse3_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_RadarTower_A_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_OilTank_Middle_S_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_OilTank_Middle_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_OilTank_Big_S_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_OilTank_Big_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_GasTank_S_size_smoke_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_GasTank_NoSmoke_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_GasTank_Detonation_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_ControlTower_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_geck_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_ch47_C, native=AIHeli, top_kmh=-1, turn=-1, why=AIHeli
- 00:02 kind: class=ms06_trkc_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=ms06_Bridge_Destructible_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_t072_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_shil_RayCheck_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_shil_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_rams_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_ah64_C, native=AIHeli, top_kmh=-1, turn=-1, why=AIHeli
- 00:02 kind: class=common_btr9_C, native=AIGroundVehicle, top_kmh=-1, turn=-1, why=AIGroundVehicle
- 00:02 kind: class=common_t160_C, native=AIPlane, top_kmh=666.7, turn=91.67, why=large plane flag
- 00:02 kind: class=common_f16c_C, native=AIPlane, top_kmh=519.4, turn=125, why=AIPlane
- 00:02 kind: class=common_av8b_C, native=AIPlane, top_kmh=519.4, turn=102.8, why=large plane flag
- 00:11 ground recovery: above_ground_m=1017, alt_m=1195, lowest_ahead_m=526.5, vz=-295.3
- 00:25 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9499 m)
- 00:30 ground recovery: above_ground_m=292, alt_m=541.2, lowest_ahead_m=228.6, vz=-33.11
- 00:35 ground recovery: above_ground_m=528.8, alt_m=677.1, lowest_ahead_m=86.07, vz=-45.46
- 00:40 weapon switch to standard missiles (no longer: beyond standard missile range, target 1796 m)
- 00:49 lanes: air=common_t160_2, air_rate=25.5, engaged=False, lane_rate=29.23, on=True, targets=18, value=154.2
- 00:51 missile warning: level=near
- 00:51 missile fired at us by common_A1_f16c_1 from 1208 m (infrared)
- 00:52 missile fired at us by common_A1_f16c_2 from 1475 m (infrared)
- 00:52 break turn: missile 1152 m away, impact in 3.5 s
- 00:53 flare: dist_m=834, missile=wp_msl_C_0, reason=tracker, tgo_s=1.629
- 00:53 jink: dist_m=834, miss_m=191.7, missile=wp_msl_C_0, tgo_s=1.629
- 00:53 that missile lost its lock at 827 m
- 00:54 missile warning: level=very near
- 00:55 flare: dist_m=586.5, missile=wp_msl_C_1, reason=tracker, tgo_s=1.02
- 00:55 jink: dist_m=586.5, miss_m=190.7, missile=wp_msl_C_1, tgo_s=1.02
- 00:55 that missile lost its lock at 586 m
- 01:01 lanes: air=common_t160_1, air_rate=30.1, engaged=False, lane_rate=18.64, on=False, targets=18, value=100.8
- 01:02 missile from common_A1_f16c_1 gone after 11 s, closest 834 m
- 01:03 missile from common_A1_f16c_2 gone after 11 s, closest 586 m
- 01:08 reload learned: class_load_s=5.5, load_s=4.652
- 01:08 missile warning: level=near
- 01:09 missile fired at us by common_A1_f16c_3 from 1721 m (infrared)
- 01:10 destroyed common_A1_f16c_1  (None missiles, 0 s after picking it)
- 01:11 reload learned: class_load_s=5.5, load_s=4.229
- 01:11 break turn: missile 1238 m away, impact in 2.6 s
- 01:11 missile fired at us by common_A1_f16c_4 from 2024 m (infrared)
- 01:12 flare: dist_m=1023, missile=wp_msl_C_2, reason=tracker, tgo_s=1.222
- 01:13 missile warning: level=very near
- 01:13 flare: dist_m=459.5, missile=wp_msl_C_2, reason=tracker, tgo_s=0.4361
- 01:13 that missile lost its lock at 460 m
- 01:13 missile warning: level=near
- 01:15 flare: dist_m=948.7, missile=wp_msl_C_3, reason=tracker, tgo_s=1.874
- 01:15 break turn: missile 949 m away, impact in 1.9 s
- 01:16 missile warning: level=very near
- 01:16 ground recovery: above_ground_m=61.01, alt_m=2519, lowest_ahead_m=2482, vz=54.28
- 01:17 flare: dist_m=253.1, missile=wp_msl_C_3, reason=tracker, tgo_s=0.3964
- 01:17 that missile lost its lock at 22 m
- 01:19 missile from common_A1_f16c_3 gone after 11 s, closest 460 m
- 01:20 destroyed common_A1_f16c_2  (None missiles, 0 s after picking it)
- 01:21 missile warning: level=near
- 01:21 missile fired at us by common_A1_f16c_3 from 1877 m (infrared)
- 01:22 missile from common_A1_f16c_4 gone after 11 s, closest 20 m
- 01:24 flare: dist_m=995.5, missile=wp_msl_C_4, reason=tracker, tgo_s=1.8
- 01:24 break turn: missile 996 m away, impact in 1.8 s
- 01:25 missile warning: level=very near
- 01:25 flare: dist_m=236.3, missile=wp_msl_C_4, reason=tracker, tgo_s=0.3303
- 01:26 that missile lost its lock at 73 m
- 01:32 missile from common_A1_f16c_3 gone after 11 s, closest 85 m
- 01:37 destroyed common_A1_f16c_4  (None missiles, 0 s after picking it)
- 01:45 destroyed common_A1_f16c_3  (None missiles, 0 s after picking it)
- 01:45 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 4343 m)
- 03:01 weapon switch to standard missiles (no longer: beyond standard missile range, target 1798 m)
- 03:14 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 2345 m)
- 03:16 destroyed common_t160_1  (None missiles, 0 s after picking it)
- 03:17 lanes: air=common_t160_1, air_rate=0, engaged=False, lane_rate=18.31, on=True, targets=15, value=93.57
- 03:17 lanes: air=common_t160_2, air_rate=25.81, engaged=True, lane_rate=18.73, on=False, targets=19, value=110.7
- 03:18 weapon switch to standard missiles (no longer: beyond standard missile range, target 1789 m)
- -1:56 phase start: MissionPhase_01

Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), pilot.log (the pilot's commentary), pictures\, saves-check.txt.
