# How co-op mods work: a teardown for the Ace Combat 7 co-op project

**Status:** study done. Reading only; nothing installed. A plain-language summary is at the top, the detail
below it.

The owner asked to understand how open-source co-op mods actually work, to build on for two-player Ace
Combat 7. A workflow read the source of eight projects in the cloud sandbox and wrote up how each adds a
second player to a game that shipped without one. Nothing was run; nothing touched the PC or the game.

## What was read

| Project | Game it adds co-op to | Licence | Means for us |
|---|---|---|---|
| Skyrim Together (`tiltedphoques/TiltedEvolution`) | Skyrim / Fallout | GPLv3 | Learn the ideas; can't copy its code |
| Quantum Space Buddies (`qsb-dev/quantum-space-buddies`) | Outer Wilds | AGPLv3 | Learn the ideas; can't copy its code |
| `praydog/AutomataMP` | NieR: Automata | MIT | Code copyable with credit |
| `onimp/oni_multiplayer` | Oxygen Not Included | MIT | Code copyable with credit |
| `VOTV-MP/Multivoid` | Voices of the Void (Unreal) | MIT | **Closest match; code copyable with credit** |
| `multitheftauto/mtasa-blue` | GTA: San Andreas | GPLv3 | Learn the ideas; can't copy its code |
| `LunaMultiplayer/LunaMultiplayer` | Kerbal Space Program | MIT | Code copyable with credit |
| `ValveSoftware/GameNetworkingSockets`, `lsalzman/enet` | networking libraries | BSD / MIT | Copyable; the plumbing under a co-op mod |

"Licence" matters: MIT/BSD code can be copied into our work with a credit line kept; GPL/AGPL code can be
read and learned from, but its code can't be pasted into our own, so the reusable thing is the **idea**,
written in our own words.

## The short version

Every one of these mods does the same handful of things. In plain terms:

1. **Slip in while the game runs; don't change the game's files.** The mod is a small piece of code that
   latches onto the game's own functions in memory. The game on disk is untouched, so it's reversible. This
   is already how Ace Combat 7's loader and the Double Trigger co-op mod get in.
2. **The other player is a puppet, not a second brain.** Their plane shows up as a stand-in copy. You move
   that copy from the data coming over the connection; you don't let it think or fly for itself. Several mods
   reuse an existing in-game ally as the stand-in.
3. **Park the puppet's brain, keep its looks.** Switch off the copy's own decision-making and physics so it
   can't fight the incoming data, but let the game engine still work out the banking, control surfaces,
   afterburner and contrails from the few numbers you feed it. This is the exact cure for the "puppet plane
   that tries to fly itself" problem the project already hit.
4. **One machine is in charge of each shared thing, with a referee.** For anything both players see — a
   plane, an enemy, a mission flag — exactly one computer is "in charge" at a time and the other copies it.
   The host is the referee. Get this wrong and the two games fight each other. The host runs the enemy AI
   planes so both players see the same battle.
5. **Two kinds of messages.** The constant "where is the plane right now" updates are sent 20–60 times a
   second and it's fine if some are lost. The rare important things — missile fired, hit taken, mission
   reached — go on a separate guaranteed channel that always arrives, once, in order.
6. **Smooth it by showing the other plane slightly in the past.** Packets arrive unevenly, so never draw the
   plane at the very newest update. Hold updates a split second, show the plane a moment behind "live", and
   glide between the last two known positions. If an update is late, keep the plane coasting the way it was
   going; if it's suddenly far off, jump it rather than sliding (which looks like rubber-banding).
7. **Among friends, let Steam carry it.** For people who each own the game, Steam's own friend-to-friend
   connection finds the other player and tunnels the data with no router setup — the same path Ace Combat 7's
   online and Double Trigger already use.

## Two paths for Ace Combat 7

**Path A — ride the game's own Steam session, like Double Trigger.** Reuse Ace Combat 7's whole network
layer. Least new plumbing, but the hard part is reverse-engineering and hooking the game's own netcode, which
is exactly why the Playground built a separate fallback instead. Double Trigger already does this; testing it
is the current plan.

**Path B — the puppet-plane fallback.** This is where the study pays off, and **Voices of the Void co-op
(Multivoid)** is the standout: it's on Unreal (the same engine family as Ace Combat 7) and it's MIT, so its
actual code can be reused with credit. The recipe transfers almost directly:

- Spawn the other plane as an orphaned copy of Ace Combat 7's **own** plane, with its controller, AI, and
  per-frame updates switched off ("park the brain").
- Each frame, write its position and motion from the network and let Unreal draw the rest.
- Smooth it with Multivoid's small interpolation routine (MIT, copyable): cache the error once when a packet
  arrives, apply it across a short window, snap at the window's end.
- For a fast jet, add the idea from Multi Theft Auto (idea only — GPL): don't just slide the plane between
  packets; run a light flight simulation for the puppet and nudge it toward each new packet, with a short
  coast for late packets. That gives natural banking instead of visible stepping.
- Swap the current hand-written network socket for **enet** (MIT, tiny, copyable whole): it adds connection
  setup, the two-channel split, packet reassembly and round-trip timing for free.
- Hook the game's once-per-frame draw call (it renders on DirectX 11) for an overlay and to pump data in step
  with the game.

The gold-standard smoothing comes from Skyrim Together (GPL, so idea-only): buffer updates, render a moment
behind, and — cleverest part — watch the connection's jitter and speed the playback up or down by ~10% to
stay just behind live, with the leftover guess-error fading out so the plane never visibly pops.

## A build ladder for Path B

Each step is testable on its own:

1. Swap the raw UDP socket for **enet** (vendor it, keep the notice). Known IP/port for two friends for now.
2. Define a tiny shared message: unreliable pose 20–60×/sec (position, orientation, velocity, throttle/boost
   bit, a few state bits); reliable events (spawn, missile fired, hit taken, mission trigger). One definition
   both sides compile.
3. Interpolate with Multivoid's `lerp_window` idea (MIT), then layer MTA's local-flight-model correction for
   a fast jet.
4. Spawn the remote plane as an orphaned copy of the game's own plane pawn, brain parked, moved from the net.
   Verify with an overlay drawn from the game's per-frame draw hook.
5. Pin down authority before any joint test: host owns the enemy AI planes and mission triggers and streams
   them (this plugs into the existing `awareness.lua` tracking); each player owns their own plane; a guest
   sends "intents" (fire, lock) that the host validates.
6. Give co-op a clean on/off toggle, and **first** fix the known F5/F9 key clash between the flight-lab mod
   and Double Trigger, or two mods grab the same keys.

## Honest limits

- **None of these is a flight game**, and none hooks Ace Combat 7's exact engine version. The patterns carry;
  the game's flight model, its missile/lock/flare mechanics, and the exact layout of its plane still have to
  be worked out inside Ace Combat 7 itself.
- **The two richest references (Skyrim Together, Multi Theft Auto) are GPL**, so they teach ideas only. The
  freely copyable material is Multivoid, enet and GameNetworkingSockets.
- **Oxygen Not Included and Kerbal co-op carry the least** — a slow colony sim and an orbital time-warp model
  have little to do with two jets in real time. Useful only for the "guaranteed message, one authority" idea
  and the occasional full resync.
- **NieR co-op (AutomataMP) is the cautionary case**: it does no smoothing at all, which would look terrible
  on fast jets. Its useful bits are its dead-simple one-host model and reusing an in-game ally as the puppet.
- **Path A still needs Ace Combat 7's own netcode reverse-engineered**; no reference does that for you.

## Credits

The projects above, each under its own licence (see the table). Where code is reused later it will be
Multivoid, enet or GameNetworkingSockets, with their notices kept; everything from the GPL/AGPL projects is
described in our own words as technique, not copied.
