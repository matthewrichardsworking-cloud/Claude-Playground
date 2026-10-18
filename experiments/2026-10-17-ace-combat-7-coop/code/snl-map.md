# First map of the online layer (SNL), read from the running copy (18 Oct 2026, 06:53 to 07:08)

Made with `tools\read-game-code.py` against the copy at the title screen (process 31156,
live base 0x7ff67de90000). Every address below is written `exe+0x...`, an offset from
the exe's base: the base changes from run to run (Windows moves the program each boot),
the offsets do not, so these numbers stay valid for this build (Steam build 9855922,
`identity.md`). Nothing was written into the game; the process was opened read-only.

**Where the names come from.** None of these functions appear in the UE4SS object dump
(SNL is plain C++ below Unreal's reflection), so the names come from two other places:
the game's class data (RTTI type descriptors in `.data`, which name 712 classes, 134 of
them in the `SNL` namespace, and link each class to its table of virtual functions), and
the strings the functions use. "`SNL::P2PSession::vtbl[15]`" means "virtual function
number 15 of class `SNL::P2PSession`", and `P2PSessionSteam` (the Steam version of the
class) shares most of those functions. Steam calls are named from the Steamworks SDK
1.39 interface layout (the crash of 17 Oct already showed slot +0x40 is Networking);
method names are best effort from the SDK headers.

The exe's SNL strings: only one contains "SNL_P2P" (`SNL_P2P_HOST`, there is no
separate "SNL_P2P"); the rest are `SNL_STEAMLOBBY_OWNER_NAME`, `SNL-`,
`P2PSessionKeepAliveThread`, UTF-16 `SNLMultiplayer`, `[SNLMultiplayer] DebugMode`, four
log messages from `LobbyGameMode.cpp` (never referenced directly: they sit inside
check-failure records), the 87 `SNL_...` developer command names (empty in this build,
workbench section 6; they are only referenced by Unreal's reflection tables), and 330
class names such as `.?AVP2PSessionSteam@SNL@@`.

## 1. The crash site of the second copy (workbench section 6), now with names

| Function | Size | Named as | What it does |
|---|---|---|---|
| `exe+0x1da32e0` | 69 bytes | `SNL::PlatformUDPSocket::vtbl[5]` | Asks Steam whether a P2P packet is waiting on this socket's channel: calls `SteamInternal_ContextInit`, takes the table's slot +0x40 (`ISteamNetworking`), reads its function table, and jumps to `IsP2PPacketAvailable(size = none, channel = socket+0x68)`. The crash at `exe+0x1da3319` is the read of the function table from a null `ISteamNetworking` pointer. |
| `exe+0x1d93710` | 525 bytes | `SNL::UDPStreamSocket::vtbl[5]` | The socket's receive step, run from a worker thread: locks, calls the platform socket's slot 6 (session bookkeeping, `exe+0x1da3110`), then slot 5 above; if a packet is waiting it is read (slot 8, `ReadP2PPacket`) and handed on. |
| `exe+0x1d7de70` | 127 bytes | (no class slot; just after `SNL::System::vtbl[17]`) | SNL's thread body: calls the thread object's slot 1 (start), loops calling slot 2 (one step) while the running counter is positive, then slot 3 (finish) and signals an event. Every `SNL-` thread runs this. |

So the chain in the dumps (thread start, `exe+0x1d7dea9`, `exe+0x1d9377c`, fault) is: SNL
socket thread, receive step, "is a packet waiting?", null Steam networking pointer. The
pointer is null because `SteamAPI_Init` failed in the second process (section 4).

## 2. Functions that use the SNL strings

| Function | Size | Strings it touches | Named as, or nearest name | What it appears to do (plain language) |
|---|---|---|---|---|
| `exe+0x1d91350` | 184 | `SNL_P2P_HOST`, value `"1"` | `SNL::P2PSession::vtbl[15]` | **Mark this player as the host.** Writes `SNL_P2P_HOST = 1` into our own entry of the Steam lobby's member data (`ISteamMatchmaking::SetLobbyMemberData`). |
| `exe+0x1d91720` | 1,139 | `SNL_P2P_HOST` (twice) | `SNL::P2PSession::vtbl[3]` | **Session update.** Polls the pending Steam call (`IsAPICallCompleted`, `GetAPICallResult`: the lobby being created or joined); when done, walks the lobby members (`GetNumLobbyMembers`, `GetLobbyMemberByIndex`) reading each one's `SNL_P2P_HOST` to find the host; if nobody is marked (we created the lobby) it marks us, publishes the lobby data (`exe+0x1d923e0`) and sends out the privacy-changed message. |
| `exe+0x1d92150` | 297 | `SNL_P2P_HOST` | 0x1d0 after `SNLP2PSessionProtocol_SteamSessionPrivacyChanged::vtbl[0]` | **Who is the host?** Reads the members' `SNL_P2P_HOST` entries (`GetLobbyMemberData`); if none is set, falls back to Steam's own lobby owner (`GetLobbyOwner`). Returns the host as an SNL end point. |
| `exe+0x1d91020` | 810 | `SNL_STEAMLOBBY_OWNER_NAME` | `SNL::P2PSession::vtbl[4]` | **Create (host) a session.** Builds the list of session properties (string filters, including the owner-name key), then `ISteamMatchmaking::CreateLobby(type, max players)`. |
| `exe+0x1d923e0` | 876 | `SNL_STEAMLOBBY_OWNER_NAME` (twice) | 0x460 after the same message class | **Publish the session's properties.** For every property calls `ISteamMatchmaking::SetLobbyData(lobby, key, value)`; the host's player name goes in under `SNL_STEAMLOBBY_OWNER_NAME`. Called by the session update. |
| `exe+0x1d93010` | 560 | `SNL_STEAMLOBBY_OWNER_NAME` | `SNL::P2PSessionsFinder::vtbl[2]` | **Session search, results step.** When Steam's lobby list arrives (`IsAPICallCompleted`, `GetAPICallResult`), turns each lobby (`GetLobbyByIndex`, `GetNumLobbyMembers`, `GetLobbyMemberLimit`) into a found-session record, reading the owner name from the lobby data. |
| `exe+0x1d93250` | 128 | (none) | `SNL::P2PSessionsFinder::vtbl[1]` | **Session search, start.** `AddRequestLobbyListDistanceFilter` then `RequestLobbyList`. |
| `exe+0x1d7f470` | 489 | `SNL-` | 0xb0 after a `UserManagementSystemSteam` callback | **Thread constructor.** Every SNL worker thread gets the name `SNL-` + its name (`SNL::BaseThread`, with an `SNL::Event`). |
| `exe+0x1d8f680` | 154 | `P2PSessionKeepAliveThread` | 0x4d0 after `SNL::SessionObjectIDPool::vtbl[10]` | **Starts the keep-alive thread** of a session (`SNL::P2PSessionKeepAliveThread`, via the constructor above). |
| `exe+0x58e410` | 157 | `SNLMultiplayer`, `VersionIntNumber` | 0x1670 after `SNL::SessionInvitation::vtbl[0]` (Unreal side) | **Reads the online version number**: the setting `VersionIntNumber` in the `[SNLMultiplayer]` section of the game's packed config, and hands it to SNL. Almost certainly the number that decides which players can see each other's sessions, so a co-op mod that changes the game should change it. |
| `exe+0x46f6d1` | 1,695 | `[SNLMultiplayer] DebugMode`, `[ Multiplayer Option ]`, `(Apply multiplayer parameters to campaign):`, `AssistAngleForRemotePlayer (%.3f)`, `SetLocalRankExp (%d)`, `SetRemainingMissionTime (%dmin)`, `ON`, `OFF` | Unreal side, `EDebugMenuMultiplayerItems` | **The developers' multiplayer debug-menu page.** Builds the menu items above, including a switch labelled "Apply multiplayer parameters to campaign". The menu itself is not reachable in the shipped game, but the switch it sets is a lead: whatever reads it is the game's own hook for running campaign content with multiplayer settings. Worth following up with `refs` on the flag it writes. |

Also seen in the session class: `vtbl[5]` (`exe+0x1d91470`) **joins** a lobby
(`JoinLobby`), `vtbl[7]` (`exe+0x1d91510`) **leaves** it (`LeaveLobby`), `vtbl[8]`
(`exe+0x1d90cf0`) **lists the members**, `vtbl[20]` (`exe+0x1d91640`) **opens Steam's
invite overlay** (`ISteamFriends::ActivateGameOverlayInviteDialog`), `vtbl[17]` and
`vtbl[23]` build a "session privacy changed" message, and `vtbl[0]` is the destructor.
`SNL::SteamSignaling::vtbl[0]` (`exe+0x1d96b20`) is a destructor that unregisters two
Steam callbacks (`SteamAPI_UnregisterCallback`).

## 3. The save path

`exe+0x19c32a0` (562 bytes, Unreal side, no class name) builds the save file's folder
and name, once, and caches it in globals at `exe+0x3caac78..0x3caac88`:

1. `SteamInternal_ContextInit`, slot +0x8 (`ISteamUser`), `GetSteamID`.
2. Checks the ID is a real one (universe 1 to 4, account type 1 to 10, non-zero
   account); if not, skips step 3.
3. Formats `"%sSaveGames/%llu"` with the base folder and the 64-bit Steam ID.
4. Later, the file name: `"%s/%s.sav"` under that folder if step 3 ran, otherwise
   `"%sSaveGames/%s.sav"` directly under the base folder.

That is exactly the stray `SaveGames\ACE7Save.sav` (no ID folder) the crashed second copy
wrote on 17 Oct: without a working Steam link, `GetSteamID` returns nothing valid and
the game saves in the no-identity place (workbench section 6 guessed this; the code
confirms it).

## 4. Steam start-up and the callback pump

| Function | Size | Named as / where | What it does |
|---|---|---|---|
| `exe+0x211cbb0` | 463 | Unreal's `OnlineSubsystemSteam` start-up (far from any dump name) | `SteamAPI_RestartAppIfNecessary`, then `SteamAPI_Init`, then ten `SteamInternal_ContextInit` calls checking each interface pointer in turn, `ISteamApps` slot 0 (is the game owned), `ISteamUtils::GetAppID`, `ISteamUtils::SetWarningMessageHook`. In the second copy `SteamAPI_Init` fails (Steam already has the game running under the first process), the interface table stays empty, and section 1 follows. |
| `exe+0x590f10` | 218 | SNL's per-frame update (next to `CCallbackImpl` tables) | Runs SNL's own step, then `SteamAPI_RunCallbacks`: this is where Steam's lobby and P2P events reach SNL each frame. Unreal's own online task manager (`exe+0x2120710`) also calls `SteamAPI_RunCallbacks`. |
| `exe+0x1d66580` | 129 | SNL singleton accessor | Returns SNL's global system object at `exe+0x3cd00f0` (created once, under a mutex); nearly every SNL function calls it first. |
| `exe+0x3a49e40`, `0x3a49e28`, `0x3a49e38` | | delay-load slots | The delay-load import slots of `SteamAPI_Init`, `SteamAPI_RestartAppIfNecessary` and `SteamAPI_RunCallbacks` (all 258 Steam imports are delay-loaded, in `.data`; the static import table has no Steam entry). |

## 5. The Steam P2P socket (SNL's "UDP socket" on PC)

`SNL::PlatformUDPSocket` (vtable `exe+0x3056178`, 10 slots): slot 5 `exe+0x1da32e0`
"is a packet waiting?" (`IsP2PPacketAvailable`), slot 7 `exe+0x1da33d0` send
(`SendP2PPacket`), slot 8 `exe+0x1da3330` receive (`ReadP2PPacket`), slot 6
`exe+0x1da3110` bookkeeping without a direct Steam call. The channel number lives at
offset 0x68 of the socket object. So on PC every SNL message is a Steam P2P packet on
a channel, which is what layer10_love's mod builds on (research.md section 5): a
"custom channel" is simply another channel number on the same mechanism.

## 6. SNL's main session class, `SNL::P2PSession` / `P2PSessionSteam` (25 virtual functions)

Vtable at `exe+0x3051e78` (Steam version at `exe+0x3054698`, same functions apart from
the destructor). Known so far: 0 destructor, 3 update (section 2), 4 create, 5 join, 7
leave, 8 list members, 15 mark self as host, 17 and 23 privacy-changed message, 20 invite
overlay; 2, 13, 16, 18 are shared empty stubs; 1 (`exe+0x1d91410`), 6 (`0x1d914c0`), 9,
10, 11, 12, 14, 19, 21 (`0x1d90f30`), 22 (`0x1d90800`), 24 (`0x1d90c40`) are small and
not yet read. `tools\read-game-code.py class P2PSession` prints the whole table.

## 7. The SNL classes (134 with virtual functions)

- **System and services:** `System`, `BaseSystem` (19 slots), `BaseSystem::NetworkBandwidthInfos`, `P2PSessionService`, `AsyncTasksManager`, `JobScheduler`, `JobSchedulerThread`, `EventQueue`, `IncomingMessagesQueue`, `SerializableFactory`.
- **Sessions and peers:** `BaseP2PSession`, `P2PSession`, `P2PSessionSteam`, `P2PSessionListener`, `P2PSessionsFinder`, `P2PSessionsFinderSteam`, `FoundSessionDesc`, `SessionFilter<...>`, `SessionInvitation`, `SessionObject`, `SessionObjectIDPool`, `SessionObjectProperty`, `P2PClient`, `P2PClientPlatformData`, `P2PClientQoS`, `NetworkPeer`, `PeerConnection`, `PeerIdentifier`, `EndPoint`, `EndPointSteam`, `LobbyIdentifier`.
- **Session protocol messages** (`SNL::Protocol::P2PSession::SNLP2PSessionProtocol_...`, each a serialisable message type): `JoinSessionQuery`, `JoinSessionAnswer`, `AddSessionClient`, `RemoveSessionClient`, `SessionClientDesc`, `AddSessionObject`, `AddSessionObjectRequest`, `RemoveSessionObject`, `RemoveSessionObjectRequest`, `SessionObjectCreationParams`, `SessionObjectDescription`, `SessionObjectFullDescription`, `SessionObjectFullUpdateRequest`, `SessionObjectUpdate`, `SessionObjectOwnershipRequest`, `MigrateSessionObject`, `NewSessionObjectIDsRequest`, `NewSessionObjectIDsAnswer`, `HostMigrationStarted`, `HostMigrationValidation`, `HostMigrationComplete`, `KeepAliveMessage`, `LobbyKeepAliveMessage`, `LeaveSession`, `RemovedByHost`, `PingRequest`, `ReliableSessionEventList`, `UnreliableSessionEvent`, `RequestSessionEvents`, `SessionEventsHistory`, `SessionTimeSyncRequest`, `SessionTimeSyncAnswer`, `SteamSessionPrivacyChanged`. This list is the vocabulary of the online layer: planes and other replicated things are "session objects" with owners, full descriptions and updates, and the host can migrate.
- **Transport:** `BaseSocket`, `BaseUDPSocket`, `PlatformUDPSocket` (Steam P2P), `BaseStreamSocket`, `UDPStreamSocket`, `BaseStream`, `RUDPService`, `BaseRUDPQuery` (+ `SendParams`, `RecvParams`, `NegotiationParams`), and the RUDP messages `SNLRUDPProtocol_NegotiationQuery`, `NegotiationAnswer`, `DataPart`, `TransferACK`, `WindowACK` (a reliable layer on top of the packets), plus `Stream` messages `Ping` and `Pong`.
- **Signaling and users:** `BaseSignalingService`, `SteamSignaling` (Steam P2P session request/connect-fail callbacks), `SystemEventsServiceSteam`, `BaseUserManagementSystem`, `UserManagementSystem`, `UserManagementSystemSteam` (Steam server connected/disconnected callbacks), `OnlineUser`, `OnlineUserSteam`.
- **Plumbing:** `BaseThread`, `ThreadWinNT`, `P2PSessionKeepAliveThread`, `Event`, `EventWinNT`, `Mutex`, `MutexWinNT`, `BinaryBuffer`, `Serializable`, `Reflection::Member...`, `SharedPointer<...>`, `DeferredContainer<...>`.

## 8. Caveats

- A class name on a function means "this function sits in that class's table of virtual
  functions"; a derived class that does not override a function shows the same address,
  and the first class scanned gives the name. Slot numbers are the position in the table.
- Steam method names assume the SDK 1.39 layout. The crash analysis confirmed the
  networking slot; the matchmaking names fit the strings (lobby data next to the owner
  name, member data next to the host flag), so they are very likely right, but one
  misordered method in the header list would shift a name by one.
- "What it appears to do" is read from the calls and strings only; nothing was traced
  while running. Function sizes are from the exe's exception table (exact).
- The saved bytes (`code\*.bin`) and listings (`code\*.txt`) stay in this folder and are
  not copied to the Playground repo (README addendum: the code is not shared).
