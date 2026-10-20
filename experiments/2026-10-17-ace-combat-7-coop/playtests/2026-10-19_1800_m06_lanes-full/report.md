# Playtest: Mission 06 lanes-full

Run 19 Oct 2026, 18:00 by tools\campaign.py (story mode); difficulty ace, mode fair.

**Not completed** in 1 attempt(s).

| Attempt | Result | Why it ended | Time | Kills | Missiles fired (special) | Damage taken | Missiles at us (lock broken) | Score |
|---|---|---|---|---|---|---|---|---|
| 1 | failed | shot down or crashed | 3.8 min | 17 | 27 (8) | 5 | 9 (9) | 6260 |

## General numbers (tools\run-stats.py)

Attempt 1:
- Time split over 3.3 min (pilot's frame-by-frame split): locked 32%, ahead 15%, offnose 30%, defend 1%, break 5%, transit 12%, recovery 4%.
- Kills 17 (5.1 a minute; 6.3 a minute while engaged), missiles 27 (8.2 a minute, 1.6 per kill), special weapon 8.
- Kills by kind (game data): ground 12, large 3, plane 2.
- Points from kills (the game's bounty per kill): 5860.
- 31 locks (median 0.3 s from selection); 12 chained selections (next target picked in the cone right after a launch); 1 break turns, 9 defensive attacks; 5 damage taken.
- Steering (flight log): 51% of the time in hard turns, pulling in 54% of that; 16% of the time banked past 95 degrees; median speed 631 km/h.
- Own missiles that hit (target lost health or died): plwp_laam_e0_C at large from 2-4 km: 4 of 4; plwp_laam_e0_C at large from 4-6 km: 0 of 2; plwp_laam_e0_C at large from 8-10 km: 0 of 2; plwp_msl_a0_C at agile from 0-2 km: 1 of 1; plwp_msl_a0_C at ground from 0-2 km: 11 of 11; plwp_msl_a0_C at ground from 2-4 km: 1 of 1; plwp_msl_a0_C at large from 0-2 km: 4 of 4; plwp_msl_a0_C at plane from 0-2 km: 5 of 6.
- Lane plans audited: 24 plans expected 3.7 shots each in their look-ahead, 2.5 were launched (the planner's model is 1.5 times optimistic).
- Learned in the fight: lock_base_s 0.00, lock_rate_dps 33.63, load_s 3.73, turn_dps 50.43.
- Score on the HUD: 0:02 000000/024000, 1:02 000650/024000, 2:02 001410/024000, 3:02 005610/024000.

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
- 00:20 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 9481 m)
- 00:25 ground recovery: above_ground_m=573.3, alt_m=760.7, lowest_ahead_m=-16.77, vz=-93.74
- 00:32 ground recovery: above_ground_m=514.1, alt_m=625, lowest_ahead_m=140.2, vz=-40.77
- 00:35 weapon switch to standard missiles (no longer: beyond standard missile range, target 1800 m)
- 00:41 ground recovery: above_ground_m=557.6, alt_m=639.8, lowest_ahead_m=213.4, vz=-164.6
- 00:44 lanes: air=common_t160_2, air_rate=26.82, engaged=False, lane_rate=32.23, on=True, targets=18, value=270.6
- 00:46 missile warning: level=near
- 00:46 missile fired at us by common_A1_f16c_2 from 881 m (infrared)
- 00:46 missile warning: level=very near
- 00:47 flare: dist_m=675.8, missile=wp_msl_C_0, reason=tracker, tgo_s=1.978
- 00:47 that missile lost its lock at 674 m
- 00:49 destroyed common_shil_RC_A1  (None missiles, 0 s after picking it)
- 00:50 missile from common_A1_f16c_2 gone after 4 s, closest 675 m
- 00:50 reload learned: class_load_s=5.5, load_s=4.555
- 00:51 reload learned: class_load_s=5.5, load_s=3.735
- 00:53 destroyed ms06_RadarTower_A_842  (None missiles, 0 s after picking it)
- 00:53 took 1 damage, health 119
- 00:53 destroyed common_shil_RC_A2  (None missiles, 0 s after picking it)
- 00:54 took 1 damage, health 118
- 00:55 took 1 damage, health 117
- 00:55 took 1 damage, health 116
- 00:55 took 1 damage, health 115
- 00:59 destroyed ms06_OilTank_Middle_154  (None missiles, 0 s after picking it)
- 00:59 destroyed ms06_OilTank_Middle_S_122  (None missiles, 0 s after picking it)
- 01:05 destroyed ms06_trkc_1_8  (None missiles, 0 s after picking it)
- 01:07 destroyed ms06_trkc_1_7  (None missiles, 0 s after picking it)
- 01:09 ground recovery: above_ground_m=267.2, alt_m=367.9, lowest_ahead_m=24.74, vz=-2.789
- 01:09 destroyed ms06_trkc_1_5  (None missiles, 0 s after picking it)
- 01:09 lanes: air=common_A1_f16c_2, air_rate=39.55, engaged=True, lane_rate=36.63, on=False, targets=10, value=304.6
- 01:10 missile fired at us by common_A1_f16c_1 from 2282 m (infrared)
- 01:11 missile warning: level=near
- 01:13 flare: dist_m=863.4, missile=wp_msl_C_1, reason=tracker, tgo_s=1.37
- 01:13 that missile lost its lock at 852 m
- 01:15 missile warning: level=near
- 01:15 missile fired at us by common_A1_f16c_3 from 1146 m (infrared)
- 01:16 missile warning: level=very near
- 01:17 flare: dist_m=689.5, missile=wp_msl_C_0, reason=tracker, tgo_s=1.398
- 01:17 that missile lost its lock at 682 m
- 01:21 missile from common_A1_f16c_1 gone after 11 s, closest 863 m
- 01:23 destroyed common_A1_f16c_2  (None missiles, 0 s after picking it)
- 01:23 lanes: air=common_A1_f16c_2, air_rate=0, engaged=False, lane_rate=41.47, on=True, targets=10, value=230.6
- 01:26 missile from common_A1_f16c_3 gone after 11 s, closest 690 m
- 01:27 lanes: air=common_A1_f16c_1, air_rate=40, engaged=True, lane_rate=37.52, on=False, targets=7, value=229.6
- 01:34 ground recovery: above_ground_m=772.1, alt_m=862.2, lowest_ahead_m=101.7, vz=-130.5
- 01:35 missile warning: level=near
- 01:35 missile fired at us by common_A1_f16c_4 from 1004 m (infrared)
- 01:37 missile warning: level=very near
- 01:37 flare: dist_m=662.2, missile=wp_msl_C_2, reason=tracker, tgo_s=2.201
- 01:37 that missile lost its lock at 657 m
- 01:46 missile from common_A1_f16c_4 gone after 11 s, closest 662 m
- 01:49 ground recovery: above_ground_m=1062, alt_m=1143, lowest_ahead_m=515.6, vz=-285.6
- 01:51 lanes: air=common_t160_3, air_rate=34.48, engaged=False, lane_rate=39.74, on=True, targets=10, value=372
- 01:55 lanes: air=common_A1_f16c_1, air_rate=40, engaged=False, lane_rate=20.3, on=False, targets=9, value=152.3
- 01:57 missile warning: level=near
- 01:57 missile fired at us by common_A1_f16c_4 from 1541 m (infrared)
- 01:58 missile fired at us by common_A1_f16c_1 from 993 m (infrared)
- 01:59 missile warning: level=very near
- 01:59 flare: dist_m=795.8, missile=wp_msl_C_1, reason=tracker, tgo_s=1.399
- 01:59 break turn: missile 553 m away, impact in 1.2 s
- 02:00 flare: dist_m=222.8, missile=wp_msl_C_1, reason=tracker, tgo_s=0.451
- 02:01 that missile lost its lock at 21 m
- 02:01 that missile lost its lock at 36 m
- 02:03 missile from common_A1_f16c_1 gone after 5 s, closest 27 m
- 02:08 missile from common_A1_f16c_4 gone after 11 s, closest 34 m
- 02:09 kind: class=common_f16c_C, kills=1, missiles=10, why=learned: many missiles for each kill
- 02:17 destroyed common_A1_f16c_1  (None missiles, 0 s after picking it)
- 02:18 weapon switch to plwp_laam_e0_C (beyond standard missile range, target 2152 m)
- 02:22 missile warning: level=very near
- 02:22 flare: reason=warning
- 02:22 missile fired at us by common_A1_f16c_4 from 443 m (infrared)
- 02:23 flare: dist_m=233.7, missile=wp_msl_C_2, reason=tracker, tgo_s=0.8962
- 02:23 destroyed common_t160_2  (None missiles, 0 s after picking it)
- 02:24 that missile lost its lock at 40 m
- 02:24 destroyed common_t160_3  (None missiles, 0 s after picking it)
- 02:26 missile from common_A1_f16c_4 gone after 4 s, closest 46 m
- 02:33 destroyed common_t160_1  (None missiles, 0 s after picking it)
- 02:33 lanes: air=common_t160_1, air_rate=0, engaged=False, lane_rate=37.95, on=True, targets=12, value=206.1
- 02:33 weapon switch to standard missiles (no longer: beyond standard missile range, target 13370 m)
- 02:34 missile warning: level=very near
- 02:34 flare: reason=warning
- 02:34 missile fired at us by common_A1_f16c_4 from 335 m (infrared)
- 02:35 flare: dist_m=192.9, missile=wp_msl_C_0, reason=tracker, tgo_s=0.7729
- 02:36 that missile lost its lock at 72 m
- 02:39 missile from common_A1_f16c_4 gone after 5 s, closest 71 m
- 02:42 missile warning: level=very near
- 02:42 flare: reason=warning
- 02:42 missile fired at us by common_A1_f16c_4 from 661 m (infrared)
- 02:43 flare: dist_m=527.7, missile=wp_msl_C_1, reason=tracker, tgo_s=2.709
- 02:44 flare: dist_m=201.2, missile=wp_msl_C_1, reason=tracker, tgo_s=0.5271
- 02:45 that missile lost its lock at 12 m
- 02:53 missile from common_A1_f16c_4 gone after 11 s, closest 20 m
- 02:58 destroyed ms06_OilTank_Big_S_74  (None missiles, 0 s after picking it)
- 02:59 destroyed ms06_OilTank_Big_122  (None missiles, 0 s after picking it)
- 03:00 ground recovery: above_ground_m=645.7, alt_m=735.7, lowest_ahead_m=-44.46, vz=-114.1
- 03:06 destroyed Enemy_Ground_P1_A_ControlTower_1  (None missiles, 0 s after picking it)
- 03:08 lanes: air=common_A1_f16c_4, air_rate=26.03, engaged=False, lane_rate=14.48, on=False, targets=5, value=91.05
- 03:08 destroyed common_shil_RC_A3  (None missiles, 0 s after picking it)
- 03:44 **player dead**
- 03:46 how well enemy positions 2 s ahead were predicted: route planes: 3548 checks, the guess used was off by 2 m on average (each way: route 5 m, straight 6 m; now using route); steady planes: 152 checks, the guess used was off by 33 m on average (each way: full turn 33 m, half turn 33 m, straight 33 m; now using full turn); turning planes: 604 checks, the guess used was off by 103 m on average (each way: full turn 166 m, half turn 103 m, straight 133 m; now using half turn)

## Notes

- Story mode, flown by tools\campaign.py (lanes-full).

Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), pilot.log (the pilot's commentary), pictures\, saves-check.txt.
