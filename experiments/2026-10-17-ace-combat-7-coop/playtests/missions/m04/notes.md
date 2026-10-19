# Mission 04 Rescue (story, Ace), the bot's notes

Level `ms04`, the Selatapura / Space Elevator map. Written 19 Oct 2026 while flying it.

## Phase 1: the stealth run (about 15 minutes on the clock)

- Radio: "If you're spotted, the mission is over. Stay out of enemy radar. Use of weaponry is
  also strictly forbidden."
- 87 `SystemObjectRadarArea` spheres, 79 active on Ace (`m04-radar.csv`). Sphere on the ground,
  3.5 to 10 km radius. Measured: at 167 m the plane's `IsInRadarArea` came on 5.97 km from the
  centre of a 6 km sphere; "We've been spotted! Abort mission!" 3 s later; the game then either
  restarts the phase by itself or shows the retry menu.
- Cleared by entering `Phase01_Clear_Field`, a 14 km sphere around (-230296, 7181) by the Space
  Elevator. Section triggers on the designers' path: `Phase01_Sect1End` (45424, -203717),
  `Phase01_branch_root` (84006, -152779), `Phase01_Sect2End` (108582, -53044). The AWACS counts
  the progress ("a third of the way", "halfway", "three-fourths") and warns "Five minutes
  remaining" about ten minutes in.
- Start: (166940, -288930) at 471 m, heading -170.
- Route: `m04-route.csv` (tools\route-avoid.py, 500 m outside every active sphere, 110 m over
  the highest ground within 600 m, 128 km). Flown at the first try: 1 to 40 m off the line.
- Clouds at low level ("Careful of ice formation in the clouds", "Mage 2, you're icing up"):
  no effect seen on the flight.

## Phase 2: "Destroy the anti-air around the space elevator" (about 10 minutes)

- SAM sites and AA guns around the elevator base; the allies (Mage, Golem) help. Cleared in
  about 2 minutes once the bot attacked (8AGM).
- The elevator's base (measured with rays): base disc ~530 m across up to ~100 m, tower ~45 m
  across, legs on two opposite sides from 750 m out at the bottom to 150 m out at 1,800 m,
  rings 525 m out at 350 m and 330 m out at 700 m.
- Two crashes into the structure during attack runs before the fight mode had the vision
  safety net (vision.lua); none after.

## Phase 3: container-launched drones (15 minutes)

- "Multiple bandits over Selatapura harbor! They're container-launched UAVs." Then "UAVs
  approaching the space elevator! Stop them!" "Eliminate all enemy UAVs."
- Attempt 3 (8AGM still armed from Mission 02): 16 kills in 15 minutes, 51 missiles, 54 break
  turns, "We're out of time. All units, abort the operation." Changes: drones are attacked from
  1.4 km nose-on with two missiles; HCAA for the next sortie.

## Vision test 1 (your request): through the Space Elevator's base

- 02:40, phase 2, from 12 km out: `fly to -239670 36570 2200 through vision on speed 520 floor 15`
  (250 m beside the tower, 220 m up, under the lowest ring). Passed 13 m from the point, no
  contact; rays saw the base 165 m below, the ring 83 to 113 m above, the tower 95 m to the right.
- Crashed 3 s later when the fight mode took over inside the structure (fixed: straight on with
  vision for 1.5 km after a fly-through; overhang-aware ground check).
