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
