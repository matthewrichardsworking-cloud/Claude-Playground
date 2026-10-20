# Mission 06 score race: why the bot lags a human player, and what would close the gap

Written 19 Oct 2026, 19:40, after the lane planner session (15 runs; numbers from
`tools\run-stats.py` on each run folder and from `m06-targets-start.json`, the mission's layout
dumped at the start of phase 1). For the owner and the next session.

## The short answer

The bot does not mainly lag on aiming or turning any more. Three things cap it, in this order:

1. **It runs out of missiles.** The Typhoon carries 112 standard missiles and 30 LAAMs. The bot
   spends 1.6-2.3 standard missiles per kill and almost never kills with the gun, so the
   standard missiles fall under 20 between minute 9.6 and 11.5 of every full phase, and the
   score flattens from about minute 11 (one run ran dry at 11.6 minutes). 112 missiles at 1.8 a
   kill is about 60 kills, about 13,000 points: exactly the plateau every full phase reached.
   24,000 points is about 120 kills at this mission's average of about 200 points a kill.
   Meanwhile 12-16 of the 30 LAAMs come home unused, because the LAAM only locks things in the
   air and most of the points are on the ground. (This was not visible during the session: the
   reports did not count ammunition. They do now.)
2. **It gets hit too often to use the whole 15 minutes.** Four F-16s around the start fire a
   missile every 5-10 s; one or two hit (40 each) in minutes 2-4 of most runs, and the guns of
   the anti-aircraft sites add 30-60 over a phase. The most aggressive run had the right pace
   (9,330 at 5 minutes, 6.4 kills a minute) and was shot down at 8:43.
3. **It collects too little of what is there.** At the start, 19,070 points sit on the ground
   with a target box, 8,160 in the air (bombers 3,600, AV-8Bs 960, F-16s 1,600, Gripens 2,000
   still without a box), 5,430 in buildings without a box (houses, hangars, water towers), and
   3,850 in drones that switch on at 9:00. The best runs took only 6,200-7,500 of the ground
   points (about a third), 0.4-1.6k of the fighters and almost none of the drones, and never
   reached area C (6,650 ground points plus the Gripens).

## How a human player differs (as far as the data and the game's design show)

| | Human player | The bot today |
|---|---|---|
| Weapons | Gun on soft targets (trucks, guns), one missile per kill, a special weapon chosen for the job | Standard missiles for nearly everything; gun only when a target happens to be dead ahead inside 1 km; LAAM idle on the ground |
| Missiles per kill | About 1 | 1.6-2.3 |
| Defence | Flares and small moves, keeps attacking | Defensive attack now, but still hit by one or two F-16 missiles a run |
| Air-to-air | Kills fighters and drones in passing | Hits what it fires at (8 of 8 at planes) but rarely gets the shot; forcing dogfights failed |
| Route | Flies the areas in an order that reaches everything | Clears A, stays in B, reaches C in the last minute or never |
| Knowledge | Learns the mission over retries | Reads everything live each run (by design: it is a test tool) |

Its kill rate while engaged (5-7 a minute, 8.9 with the 8AGM) is no longer the main gap.

## Avenues, ranked by expected value

1. **Ammunition economy (most promising, and general).** Every point the bot cannot shoot at
   after minute 11 is lost, so stretching 112 missiles over 15 minutes is worth up to about
   1,000-1,500 points a minute for the last 3-4 minutes, plus everything later steps add.
   - *Gun kills in the lanes:* soft targets (trucks 20 health, guns and SAM launchers 40) to
     the gun, missiles kept for what the gun cannot reach. The planner already models a weapon
     by cone, range and kill time; the gun is a second one (a few degrees, about 1 km, a burst).
     Measure the gun's damage per second against a 40-health target first.
   - *Missile discipline:* one missile per target that one missile kills (mostly done), no
     shots at the cone's edge from close in if the bot's own hit data says they miss (the hit
     tracking by weapon and range exists; add the angle), no standard missiles at agile drones
     beyond what the data supports, the LAAM spent on helicopters and planes before the
     standard missiles.
   - *The special weapon for the points that matter:* 70% of the reachable points are on the
     ground; the LAAM cannot touch them. The 8AGM run had the best engaged kill rate of the day
     (8.9 a minute, 1.1 missiles a kill) even with single-lock salvos; it lost on the bombers.
     A loadout test is cheap (`force_weapon` in the order); other planes' ground specials too.
   - *Houses and other buildings without a target box (5,430 points):* test whether the gun or
     missile blasts destroy them and score. If yes, gun runs along rows of them are a large
     pool no lock is needed for.
2. **Survive the opening.** Shoot the F-16s with the LAAM while they are ahead and far (one
   LAAM is 80 damage, an F-16 has 60; the bot hit 8 of 8 shots at planes), before they turn in;
   do not force turning fights (run 7). Flares from 3 s (done). Kill the guns that hit it
   (marked since run 5). Worth: the whole second half of the phase, in the runs that died.
3. **Close the plan-reality gap.** Plans promise 1.5-1.9 times the shots flown. Causes found:
   flying 300-600 m above the pass height (hard turns climbed; slicing turns added), not
   pulling in half the hard-turn time (bank-to-turn added). Next: measure each manoeuvre's real
   turn and climb against the model, per plane, and feed the measured values back.
4. **A phase plan for the time.** With the ammunition lasting, the route matters: reach area C
   (about 8,600 points) by about 9 minutes, and the drones when they appear. In the bot, from
   live data: points per area, flight times, the kill rate measured so far, the time left and
   the points still needed.
5. **Air lanes.** The lane planner for moving targets (predicted paths already exist in
   `awareness.lua`): drones (3,850), Gripens (2,000), the F-16s. Larger job, larger pool.

## Recommendation for the next session

Start with (1): measure the gun against a 40-health ground target and test whether a house
takes damage (one short `eval` session each), then gun kills in the lanes and missile
discipline, and one loadout run with the 8AGM. Judge every change with the ammunition line in
the report (standard missiles left at minute 10 and 15) and the score at 15:00, not only the
kill rate. Then (2), then (4). Expected: with missiles lasting the full 15 minutes, about
16,000-17,000 at the sixth full phase's pace (about 1,100 points a minute) and about 21,000 at
the fourth's (about 1,450, if it survives); with area C reached as well, 24,000 is within reach.

## What came of it (20 Oct 2026, the ammunition session)

The shortage was mostly waste. With every missile now followed (the game reuses missile objects,
which the old tracker missed), a quarter of the standard missiles turned out to fly unguided (the
next target was selected while the fire key was still down) and many others hit terrain or
buildings (no line-of-sight check). Both fixed: standard missiles at ground targets hit 92 of 94
and 72 of 73 times, one missile per kill, and they last the phase. The gun was measured (weak for
this bot, then zeroed from its own bullets: useful in passing), houses without a target box never
died, the 8AGM loadout was clearly worse (3,850 at 5 minutes), the LAAM took the opening F-16s
"in passing", and a leaving rule from foraging theory moved the plane between areas at the right
time. Full phases went from about 13,000 to 21,900-23,200; Mission 06 still needs 24,000. Details
and every attempt: `notes.md`, section "The ammunition session".
