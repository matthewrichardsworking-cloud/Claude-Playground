# Double Trigger: a read of layer10_love's co-op mod, first release

Read on 18 Oct 2026, a few hours after the release. Source: the public repository
[github.com/layer10-love/double-trigger](https://github.com/layer10-love/double-trigger)
(tag v0.1.0, commit 45bf7ec, cloned read-only into a scratch folder and read file by file).
Nothing was downloaded into the game copy and nothing was run: this is a reading of the
code and the release page, plus three read-only checks against our copy of the game
(section 6). Plain language first; section 10 is the technical appendix for later sessions.

## 1. Short version

- **It is real, it is complete for a first release, and it is the thing we set out to
  build.** Two-player online co-op for the campaign's missions (Free Mission mode), with
  one player hosting and the other joining through Steam friends. Enemies, missiles,
  damage, score, radio, music, mission flow, failure and retry, pausing, checkpoints and
  the mission's end are all kept in step. MIT licence, full source published, one file to
  install (`dinput8.dll`, 1.2 MB, with a published checksum).
- **It takes exactly the route our plan called Route A** and judged hardest: it reuses the
  game's own online layer (SNL) for the session, the Steam lobby and the two player
  planes, and sends everything else over a private channel of its own. It confirms our
  map of that layer (code\snl-map.md) point for point, including the lead we flagged
  about the online version number.
- **It is well made.** About 24,000 lines of careful C++ written in seven days (12 to 18
  Oct, 65 commits, one author, "Mira", who says they used AI tools heavily). Every hook
  into the game is guarded so a fault switches that one feature off instead of crashing
  the game; the mod refuses to run at all if the game's code is not byte-for-byte the
  build it knows; the game's own public and ranked multiplayer is switched off while the
  mod is installed, so modded players cannot wander into normal matches.
- **It should run in our copy.** Three things the mod checks before it does anything were
  checked here read-only, and all pass: the exe is the build it expects, the Steam library
  file next to the game is the one it expects, and the copy carries none of the
  pirated-copy markers it looks for. UE4SS in the copy uses a different loader file
  (`dwmapi.dll`), so the two do not collide on file names.
- **Two copies on one PC still will not work.** The mod waits for a real Steam connection
  and stays passive without one, and the second copy crashes before that anyway
  (workbench section 6). A test with two players needs a second PC and a Steam friend
  who owns the game.
- **Recommendation: switch this project to testing and helping Double Trigger**, as you
  said you would if it turned out stable. The honest caveat is that it is hours old, one
  person's work, and its own README lists real rough edges (landings, take-offs,
  refuelling, cutscene skips, "continue mission", the replay screen, some bosses). Our
  own route stays on the shelf as a fallback. Section 9 has the concrete next steps and
  which of them need your OK.

## 2. What was released

| | |
|---|---|
| Name | Double Trigger ("ac7mp" inside the code and logs) |
| Author | "Mira" (GitHub `layer10-love`, Reddit `layer10_love`); thanks "Mia" for planning, testing, the logo and the trailer |
| Released | 18 Oct 2026, 16:40 UTC, as GitHub release v0.1.0 (build `0.1.0+6240b21f`) |
| Files | `dinput8.dll` (1,242,112 bytes), `SHA256SUMS`, `LICENSE`, `THIRD_PARTY_NOTICES.md` |
| Checksum of the DLL | `97fdb3b80ca2a310fd7df67e5259d6c04dea280f531a595ab3c062bbd03221d7` (from the release's SHA256SUMS; we have not downloaded the DLL, so this is their number, not ours) |
| Licence | MIT. Uses MinHook 1.3.3 (BSD) for hooking and Dear ImGui 1.91.9b (MIT) for the in-game panel |
| Source | 162 files, 24,270 lines of C++, all of it the mod's own code: no game files, no game code, no third-party binaries |
| History | 65 commits from 12 to 18 Oct 2026; the first public commit is from 13 Oct (the Reddit clip was 15 Oct) |
| Game build | The final Steam build, PE timestamp 2 Nov 2022 (`0x6362748e`), the build in identity.md |
| Players | Exactly two: one host, one client. The lobby is capped at two |
| Requirements | AC7 on Steam, Windows, both players Steam friends, both on the same mod build, both owning any DLC the mission needs |

A small check of our own: the "build ID" after the plus sign in the version is a
fingerprint of the source code (a hash of every source file). Recomputing it from the
published source gives the same `6240b21f`, so the release's version stamp matches the
code that is public. (It does not prove the DLL was built from that code; building it
ourselves would, and we have the compiler for that now.)

The author's own disclaimers, worth repeating: early release, expect rough edges; the
DLL is not code-signed, so Windows SmartScreen or an antivirus may warn; back up your
save; remove the DLL before playing the game's own online modes.

## 3. How it works, in plain words

**How it gets into the game.** The game asks Windows for a standard input library named
`dinput8.dll` when it starts. Windows looks in the game's own folder first, so a file of
that name there gets loaded instead of the real one. The mod is that file: it forwards
every request to the real Windows library so the game works as before, and runs its own
code on the side. This is the oldest and most common way PC mods load (our UE4SS does the
same thing under the name `dwmapi.dll`).

**It waits, then checks, then hooks.** The exe's code is scrambled on disk by Steam's
wrapper and unscrambled in memory about two seconds after launch. The mod waits for that
by watching the first bytes of the game's real entry point, exactly as our code-reading
tool does; it does not touch the wrapper. Then it checks the game's build stamp and, for
each of 222 game functions it uses, a checksum of the function's first bytes, plus 13
places in the game's tables of virtual functions. If any of the 247 checks fails it logs
why and stays passive for the rest of the run. Only then does it place its hooks (75
places in the game's code, each one a small detour that runs the mod's code before or
after the game's).

**The session rides on the game's own online layer.** This is the clever part. The game
already has everything for two players to find each other and fly in one world: Steam
lobbies, the SNL peer-to-peer session, and a "network plane" object for each player's
aircraft whose position the game sends and smooths itself (that is how Team Deathmatch
works). The mod uses all of that as it is:

- To host, it calls the game's own "create a session" function with a friends-only or
  private Steam lobby and a limit of two players. To join, it builds the same invitation
  record Steam's "Join game" would produce and hands it to the game's own join function.
  Public lobbies are refused in the settings.
- It flips the game's online version number (the `VersionIntNumber` our SNL map flagged
  as "almost certainly the number that decides which players can see each other") to a
  modded value, so modded sessions and normal sessions never see each other.
- Each player's plane is published into the session as the game's own network plane, and
  on the other PC the mod spawns a plane for it the way Team Deathmatch does (same class,
  same dummy controller, same smoothing). So the other player's plane moves as smoothly
  as an opponent does in the game's own online matches.
- Three small fixes make the game's online code work outside its multiplayer menus,
  where some objects it expects do not exist (it would otherwise crash on hosting, refuse
  every join, and mistake the client's lobby data for a "second host").

**Everything else goes over a private channel.** Steam's peer-to-peer packets have
channel numbers; the game's online layer reads only its own channels. The mod opens
channel `0x4d50` ("MP") between the two players and sends 54 kinds of message over it.
The host's game is the world: it runs the enemies, the ground units, the mission script
and the music, and sends their state to the client. On the client, every AI plane and
ground unit becomes a **puppet**: its own brain is switched off (the mod answers "yes, a
replay is playing" to the game's own check whenever a puppet is being updated, which is
how the game already disables AI during replays) and, right before each puppet's update,
the mod places its flight engine where the host's plane should be by now, predicted
forward from the last message and with any correction faded in over 0.2 seconds. Aces
and bosses are sent 30 times a second and shown a tenth of a second behind, on a smooth
curve through the host's positions, because their manoeuvres outrun prediction. This is
the same idea as our puppet plane in workbench section 7, done at the level of the game's
own code, with velocity, rotation, parking spots, carrier decks, wrecks and scripted
moves all handled.

**Missiles, damage and hits.** Each launch by an AI or a player is sent with its slot,
target, position, speed and the session clock time; the other PC fires the same slot from
its copy of the shooter and lets the copy catch up by the measured delay, as the game's
own online code does. An AI missile aimed at the client's plane is the client's to dodge,
flare or take; everything else is a visual copy whose damage is dropped. Hits the client
lands on enemies are sent to the host, which applies them, so kills count and the mission
reacts. Enemy hits on the client's plane are seen on the host (on its copy of the client's
plane, which the game never lets lose health) and sent to the client, which applies them
to its own plane with its own parts and difficulty.

**Who the enemies attack.** The campaign was built for one player. The mod makes enemies
treat the other player's plane as a player too (for targeting, radar and mission
triggers), and on the host it answers every "where is the player?" question with the
nearer of the two planes, weighted by how many enemies are already chasing each one, with
a one-minute stickiness. The README explains this well and it is adjustable.

**The panel.** F5 opens an in-game window (Dear ImGui drawn over the game's DirectX 11
frame) with Host, Invite friends, Join (a list of friends currently hosting a co-op
lobby), Leave, the player list with each player's status, and the version. Steam IDs are
shown masked unless you click Show.

**What it refuses to do.** While the DLL is installed, the game's own Multiplayer menu
entry is greyed out, the game's "enter online multiplayer" function is blocked, Steam's
lobby search is refused, and only the mod's own host and join may create or join a lobby.
If the game ever ends up in its online mode anyway, an "online gate" switches every hook
of the mod off until the game restarts. And a copy check refuses to run on anything that
is not a Steam copy owned by the logged-in account: it looks for Steam's wrapper on the
exe, checks the Steam library file's checksum, looks for the usual pirated-copy marker
files, checks that the Steam client is signed by Valve, and asks Steam whether this
account owns the game.

**Logs and settings.** It writes `ac7mp.log` (and keeps the last few runs as `ac7mp-1.log`
and so on), `ac7mp.ini` with every feature switchable, and on a crash an `ac7mp_crash_*.dmp`
memory dump, all in the game folder.

## 4. What it does and does not do

From the README and the settings file, in the author's own grouping:

- **Together:** fly the same Free Mission at the same difficulty, each in your own plane;
  one shared world (enemies, targets, damage, score, radio, music); enemies split between
  the players; mission failure, retry, checkpoints, pausing, cutscene skips and the
  mission's end happen for both at once; resupply on the return line together
  (experimental); special handling for the Arsenal Bird, the Alicorn, Rage and Scream,
  Mihaly and Sol Squadron, and mission quirks in missions 13, 14, 16, 17 and the DLC
  missions; a "WINGMATE" label on the other plane; both names on the debriefing map.
- **Known issues (their list):** landing, take-off and refuelling minigames and the
  return line are "wonky"; cutscenes may not skip properly; playing many missions in a
  row can leave stale state (restart the game between missions); some bosses still
  misbehave ("the client being ignored in some way or enemies moving jumpily"); continuing
  a mission from the menu "will most likely break the game in a myriad of ways"; the
  replay screen does not work.
- **Limits by design:** two players only; both need the identical build; the game's own
  online play is off while installed; **no shared campaign progress** (each game saves its
  own, so Free Mission is the mode; "this might change in the future"); other mods that
  load as `dinput8.dll` cannot be installed at the same time.

So the goal from plan.md step 2 (one campaign mission together) is what v0.1.0 delivers,
mission by mission through Free Mission. Step 3 (the whole campaign as a campaign, with
shared progress) is not there yet, and the author names it as a possible future change.

## 5. How it compares with what we built and found

**Our SNL map was right, and they went further.** Their address table names the function
at `exe+0x1d92150` "P2PSessionSteam::OnLobbyDataUpdate"; our map read the same function as
"who is the host?" (it reads the lobby's `SNL_P2P_HOST` entries), and their fix for it
explains the one thing we did not know: on the host, any member data set by a client made
the game think a second host had appeared and leave the session. Their `SNL_Clock_Get` is
our "SNL singleton accessor" at `exe+0x1d66580`. And the service field they call
`kVersion` ("[SNLMultiplayer] VersionIntNumber, read by StartGameStream") is exactly the
lead our map ended on; they use it the way we guessed it could be used. Our tool
(`tools\read-game-code.py`) can verify their whole table of 247 addresses against the
running copy, which is a concrete way we could help them check a future game update.

**Their puppet is our puppet, grown up.** Workbench section 7's recipe (AI off, invincible,
teleport the plane every frame with time interpolation) corresponds to their
`sync::Drive`: before the plane's own update they overwrite its flight engine's position
and rotation with a prediction, then let the engine run, then place the actor directly if
something scripted moved it away. Where we got 0.2 units of correction per frame straight
and 6 in turns with 10 ms Lua updates, they send states every 100 ms (every 33 ms for
aces) and hide the gaps with velocity extrapolation and fading corrections. Our live
packet feed (workbench section 9) is their channel in miniature: both are "position
messages over a socket into a plane the game flies", but theirs rides Steam's
peer-to-peer link between two PCs, which was the piece we had not built.

**Their other player's plane is the real thing.** Our plan set Route A aside partly because
the game's network plane machinery was invisible to UE4SS scripts. They reached it from
compiled code: the game's own `CreateNetworkPlane`, `SpawnRemotePlane` recipe and
movement replication. A puppet plane fed by our own packets was always going to be an
approximation of that.

**Two copies on one PC: nothing changes.** Their mod needs a working Steam connection in
the process (it waits up to a minute for Steam to come up and then gives up), and the
second copy never gets one and crashes in SNL regardless (workbench section 6, snl-map
section 1). Any two-player test needs a second PC.

**What we have that is useful to them.** A clean, isolated copy of the game to test in
without risking a real install; tools that start the copy and press its keys; a crash-dump
reader that can read their `ac7mp_crash_*.dmp` files (they are standard Windows
minidumps); the code-reading tool to verify or extend their address table; and the two
leads in our SNL map they do not use yet, in particular the developers' own switch "apply
multiplayer parameters to campaign", which may matter for the shared-campaign-progress
feature they say may come.

## 6. Will it run in our copy?

Checks done on 18 Oct, all read-only, nothing changed:

| What the mod checks | Our copy | Result |
|---|---|---|
| The exe's build stamp must be `0x6362748e` | `C:\AC7-Coop-Game\Ace7Game.exe` header | **matches** |
| The exe's entry point must sit in Steam's wrapper section (`.bind`) | entry `0x43e7310`, inside `.bind` | **passes** |
| `steam_api64.dll` SHA-256 must be `38f6a1dd…9b29` | `Engine\Binaries\ThirdParty\Steamworks\Steamv139\Win64\steam_api64.dll` | **matches** |
| None of 15 pirated-copy marker files next to the exe or the Steam library | copy's root folder | **none present** |
| Steam client running and signed by Valve; the process runs as app 502500; the account owns the game | `tools\start-copy.ps1` sets the app ID to 502500 and needs Steam running; you own the game | **should pass** (checked only when it runs) |
| 222 function checksums and 13 table slots | can only be checked while the game runs; two of their SNL addresses already coincide with functions our map read from the running copy | **very likely** (same build) |

Two things to know before a test:

- **UE4SS and Double Trigger both hook the game.** They use different loader file names
  (`dwmapi.dll` and `dinput8.dll`), so both can be in the folder at once. Both also hook a
  few of the same game functions (the one every Blueprint event runs through, for one).
  Two hooks on one function usually chain fine, but it is untested here. If the mod's log
  reports hooks that could not be placed, the clean test is to move UE4SS's `dwmapi.dll`
  out of the copy's folder for the duration (the copy only; it goes back after).
- **The copy's save folder is its own** (`C:\AC7-Coop-Game\UserProfile`), so whatever the
  mod does, your real save cannot be touched. The mod itself says it does not interfere
  with saving, and the code agrees: the only save-related hook holds back the game's
  "save finished, open the sortie screen" step until both players are ready; the save
  itself runs unchanged.

## 7. Safety, and our ground rules

- **Copy protection and anti-cheat.** The mod does not touch Steam's wrapper (it waits
  for the game to unpack itself, like UE4SS and like our reading tool) and does not
  change any check of the game's. Its own copy check refuses pirated copies, the opposite
  of circumventing protection. There is no third-party anti-cheat in AC7 (identity.md).
- **Online play.** Only friends-only or private Steam lobbies are possible; public ones
  are refused in code and in the settings. The game's own public and ranked modes are
  blocked while the DLL is installed, so a modded player cannot affect normal players.
  This fits our rule "private rooms only, with people running the same mod".
- **Terms of use.** Hooking the game's code is the same category of thing as UE4SS and
  the AC7 Mod Loader already on your PC; the mod adds nothing new there.
- **Privacy.** The log file contains your Steam ID and display name and your friend's,
  and the crash dumps are raw memory; the bug-report form says so and offers e-mail
  (`contact@layer10.love`) for the dumps. Decide before attaching logs to a public issue.
- **Antivirus.** An unsigned DLL that hooks a game may be flagged. The checksum file lets
  you confirm the download is the one they published.
- **Our own rules still apply:** the copy only, never the real install (whose 30 mods and
  Mod Loader may or may not use `dinput8.dll`; nobody here will look); downloads only
  from the official release page with the checksum checked; test runs through
  `tools\start-copy.ps1` and `tools\compare-saves.ps1`; your OK before downloading,
  installing, or hosting a lobby (that is "going online", even friends-only).

## 8. Quality of the code

**Strengths.**

- Defensive from end to end. Every per-frame job and every hook body runs under a "fuse":
  a fault is logged, and five faults in a row switch that one feature off for the rest of
  the run while the game and the other features keep going. Hooks are placed
  all-or-nothing where a half-installed set would be dangerous. The address check, the
  build-stamp check, the online gate and the copy check all fail towards "do nothing".
- The networking is sound for what it is: a small header (magic number, protocol version
  31, message type), payloads read through a bounds-checked reader, lists chunked to
  Steam's 1,200-byte limit, reliable sends where order matters and unreliable with
  periodic snapshots where it does not, messages dropped from anyone who is not the one
  other member of the lobby, and host-only messages accepted only from the host.
  Mismatched builds are kept apart twice over (protocol number and build fingerprint),
  so two players on different versions never desync silently.
- The comments read like a lab notebook: nearly every offset and behaviour is marked
  "observed" with where and how, and oddities ("the bomber's wreck in ms01 jumped back
  33 to 103 m every 250 ms") are recorded with the fix. For anyone continuing the work,
  including the author after a break, this is worth a lot.
- Every feature has a switch in `ac7mp.ini`, re-read while the game runs, so a misbehaving
  feature can be turned off in the field without a new build.

**Weak spots and honest signals.**

- Hours old, one developer, five GitHub stars and one download of the DLL at the time of
  reading. The known-issues list is long and candid. Expect to hit bugs, and expect
  frequent releases that both players must install together.
- The author states that they relied heavily on AI tools; the code's consistency suggests
  so too. That is not a defect in itself, but the "observed" notes are the author's, and
  some parts (the special-case fixes for single missions) will have been tested on few
  runs.
- Everything is tuned to the one game build. A game update would break every address;
  the mod would then stay passive and log why, which is the right failure, but it means a
  rebuild by the author each time (the hidden folders `work/`, `rea/`, `tools/` and
  `dev_docs/` in their ignore list hold the reverse-engineering notes and tooling, which
  are not published).
- Design limits that will not move easily: two players (the author says three or four
  would make the sync "exceedingly difficult"); no campaign progression; the host's PC
  carries the world, so a weak host PC or a poor link shows as jumpy enemies for the
  client.
- Small things noticed in passing, none serious: while the host's Steam ID is still
  unknown, host-only messages are accepted from the peer; the lobby member cap in the
  mod's own code is 8 even though the lobby is created for 2 (extra members are logged
  and ignored); the mod replaces three entries of Steam's matchmaking table inside the
  game process (it affects only this process, and is why lobby search and the game's own
  online modes are blocked).

Overall: for a seven-day, one-person first release this is unusually careful work, and
the parts that protect the player (checks, gates, fuses, friends-only) are the best parts.

## 9. What this means for the project, and next steps

**Direction.** The plan's 18 Oct update said: wait for the release, read it, try it in
the copy, and if it is stable turn this project into testing and helping that mod. The
release is out and the reading is positive. The sensible course is to go ahead with the
"try it" part and help the author with exact, log-backed bug reports from a clean test
bench. Our own route (puppets fed by our own add-on) stays as the fallback and as a tool:
the flight lab and the add-on are still useful for experiments the mod does not cover.

**Next steps, in order.** Steps 1 and 2 need your OK (a download and an install into the
copy; a Steam lobby, even friends-only, counts as going online). Step 3 needs a second PC
and a person.

1. **Download v0.1.0 and verify it** (your OK needed: a download). `dinput8.dll` from the
   release page, 1.2 MB, checked against the SHA-256 in the release's `SHA256SUMS`, kept
   under `downloads\` with the checksum written down, like PM-UE4SS was.
2. **Dry run in the copy, alone** (your OK needed: installing into the copy, and hosting
   a friends-only lobby). Put the DLL in `C:\AC7-Coop-Game`, start the copy with
   `tools\start-copy.ps1`, and read `ac7mp.log`: it should say the game code was decrypted,
   "all game addresses check out", "copy check: Steam copy, owned", "online block in
   place" and "overlay ready: F5 opens and closes it". Then: F5 opens the panel; Host
   creates a lobby (the panel says "Hosting"); the main menu's Multiplayer entry is greyed
   out; Leave; quit; `tools\compare-saves.ps1` shows your real save unchanged. That checks
   everything except a second player, with nobody else involved. If hooks fail with UE4SS
   present, repeat with UE4SS's `dwmapi.dll` moved aside.
3. **A two-player test** needs a Steam friend with the game and the same DLL on a second
   PC. Options: a friend of yours; or asking in the Reddit thread or the repository's
   issues for a test partner. A session can prepare a test script (which mission, what to
   watch, which logs to keep) and read both logs afterwards.
4. **Help the author.** Bug reports with both logs through their form; our crash-dump
   reader on any `ac7mp_crash_*.dmp`; our code-reading tool to double-check their
   address table or to find addresses for them after a game update; and, if they take up
   shared campaign progress, the "apply multiplayer parameters to campaign" lead from
   code\snl-map.md.

**Not to do:** install it in your real game folder (your call entirely, outside this
project's rules); play public or ranked online with any modded install (the mod blocks it
anyway); share any of the game's code bytes from `code\` with anyone, the author included
(README addendum).

## 10. Technical appendix (for sessions)

**Layout of the source** (`mod/src/`, 162 files):

| Folder | Lines | What |
|---|---|---|
| `core/` | 2,431 | DLL entry and the `dinput8` forwarders; crash logger (vectored handler + minidumps); MinHook wrapper (`detour`); the `Fuse`; feature list and tick order (`features.cpp`); online gate; online block; copy check (`genuine.cpp`); ini config; log |
| `game/` | 2,703 | `game_addresses.inc` (222 functions with CRC32 of the first 32 bytes, 12 data addresses, 13 vtable slots, "generated from the unpacked exe"); typed wrappers and offsets for UE4 objects, planes, weapons, mission, SNL service and session |
| `net/` | 1,538 | Steam flat API access through the game's own `steam_api64.dll` (SDK 1.39 interfaces: SteamClient017, SteamUser019, SteamFriends015, SteamMatchMaking009, SteamNetworking005, SteamUtils008, STEAMAPPS_INTERFACE_VERSION008); channel `0x4d50`; header = magic `0xa7c0`, protocol 31, type; 54 message types in `protocol.h` with packed structs; bounded `Reader`/`Writer`, `SendChunked` |
| `mp/` | 3,605 | session host/join/leave; mission matching via lobby data (`ac7mp_ver`, `ac7mp_build`, `ac7mp_players`, `ac7mp_mission` = "version:mission:difficulty:build"); remote plane spawn (port of `ATeamDeathMatchGameMode::SpawnRemotePlane`); sortie wait; load wait (hooks `NotifyReadyToPlay` and `WaitTargetLoaded`, start time on the host's clock); player status; AI targeting of remote planes; HUD box label; debrief names |
| `sync/` | 9,227 | plane states (100 ms, aces 33 ms), object states (activation, health, attributes), client hits, score, plane damage, fail/retry rounds, missiles and gun rounds, interceptions, AI locks, mission variables (by property index, FNV-1a class hash), radio and BGM (by name text), phases and mission end, drones, ground units (puppets, aims, rounds), supply, cutscenes, pause, host settings, puppets (`IsReplaying` override while a puppet ticks, hooks on `AUnit::Tick`, `AGameObject::Tick`, `UAIFireControlSystem::TickComponent`), triggers (`ProcessEvent` hook; player getters return the remote plane during its overlap events) |
| `special/` | 2,258 | Arsenal Bird barrier, ex03 shield drones and Alicorn (submarine calls, railgun aim, search spot), unknown targets (ms16 to ms19), ms13 MOP, ms14 searchlights, ms16 friendly kills, ms17 hit events, ex02 Su-47s, aces list, camera shake |
| `ui/` | 1,090 | ImGui overlay on `IDXGISwapChain::Present`/`ResizeBuffers` (found via a probe swap chain); input through `FWindowsApplication::AppWndProc` and DirectInput, only the toggle key is swallowed |
| `diag/` | 1,136 | roster, state-change events, player census, mission log, peer clock (ping/pong, wall clock since 1601) |
| `hooks/` | 319 | engine tick (vtable slot of `UNimbusGameEngine::Tick`), three SNL fixes, mission events (`AMission::BeginPlay/StartMission/StartPhase/Complete`, `GOnMissionVariableChanged`) |

**Start-up sequence** (`core/dllmain.cpp`): thread from `DllMain` → check PE timestamp →
wait until the bytes at the original entry point (`+0x22339ec`) read `48 83 EC 28 E8` →
install crash logger → `game::Init` (all CRCs and slots) → wait for `steam_api64.dll` and
`SteamAPI_GetHSteamUser() != 0` (up to 60 s) → resolve Steam interfaces → MinHook init →
online block (Steam vtable slots `RequestLobbyList` +0x20, `CreateLobby` +0x68,
`JoinLobby` +0x70; permanent detours on `EnterOnlineMultiplayer`,
`FNimbusNetworkService::OnSessionInvitation`, `UMainMenuWidget::Setup`) → copy check →
engine tick hook. Each frame: `gate::Tick` classifies the game as offline / online /
not-yet; the first "offline" installs the three fixes and inits every feature in list
order; any "online" verdict leaves the session and disables all non-permanent hooks.

**Session mechanics** (`mp/session.cpp`, `game/session.h`): `FNimbusNetworkService` offsets
`+0x54` version, `+0x5a` initialized, `+0x5b` stream active, `+0x68` `SNL::P2PSession*`,
`+0x80` game mode, `+0x1e0` sync state, `+0x3a0` `FNetworkGameSettings*`. Session offsets
`+0x10` version, `+0x20` state (9 = in session), `+0x28/+0x34` clients, `+0x38` local,
`+0x40` host, `+0x1a0` start mode, `+0x1a4` privacy, `+0x15b8` lobby CSteamID, `+0xc68`
clock offset. Hosting: version `^= 0x4d500000`, `StartGameStream`, detach the menu's game
mode from the service, `SNL::P2PSession::Host(session, privacy, user, 2, empty filters)`.
Joining: `RequestLobbyData`, wait for the `ac7mp_ver` marker, then
`SNL::P2PSession::JoinFound` with a hand-built `SNL::SessionInvitationSteam` (0x88 bytes;
lobby ID at +0x58, invited flag at +0x78). Net plane: `APlayerPlane::CreateNetworkPlane`,
then `Ready` (+0x310) set and marked dirty; remote spawn uses `ANetworkDummyController`,
deferred construction, `SetNetworkPlane`, `LinkActor` (sample preserved), `FinishSpawning`,
`ResetFlightModels`, activation via the replay recorder wrappers.

**Cross-checks with code\snl-map.md:** `SNL_P2PSessionSteam_OnLobbyDataUpdate =
exe+0x1d92150` (our "who is the host?"); `SNL_Clock_Get = exe+0x1d66580` (our SNL
singleton accessor; they read `+0x20` then vslot 3 for the clock source); `service +0x54`
= `VersionIntNumber`, read by `StartGameStream` (our lead `exe+0x58e410`). Their
`SNL_P2PSession_Host = exe+0x1d6a8f0` and `JoinFound = exe+0x1d6b750` are in the generic
`SNL::P2PSession` area our map had not read (our vtable-based names were the Steam
subclass's slots 4 and 5 at `0x1d91020`/`0x1d91470`: the platform layer under these).

**Verification we could run** (not done yet, the game was not running): launch the copy,
then `tools\read-game-code.py` over the 222 `AC7MP_FUNC` entries, CRC32 of the first 32
bytes at `base + rva`, compared with the table. Worth doing before step 2 above and
after any game update.

**Reproducing the build ID** (done): SHA-256 of a manifest of `path\nsha256(content with
\r removed)\n` for the sorted set of `src/**/*.{h,hpp,cpp,def,rc}`, `cmake/*`,
`CMakeLists.txt`, `VERSION` (165 files), first 8 hex digits = `6240b21f` = the release's.

**Building it ourselves** (not done): their `build.cmd` wants Visual Studio 2022 via
`vswhere`, CMake and Ninja, and fetches MinHook and ImGui by URL with pinned hashes. Our
portable MSVC 14.44 plus Windows SDK in `C:\AC7-Coop-Tools` has the compiler; CMake and
Ninja would be two more downloads (allowed by the README addendum, with checksums). A
local build would let us confirm the published DLL byte for byte, and later test fixes.

**Where they log what:** `ac7mp.log` categories `core, steam, net, session, planes, ai,
sync, objects, weapons, triggers, mission, audio, ui` plus diagnostics; levels per
category in `[log]`; 10-second packet statistics per message type; 5-second sync reports
("client, N planes from the host, driving M here, ...").
