# Game identity

Recorded 17 Oct 2026, following Co-op Anything's `coop-triage` skill. Every co-op
step must be checked against this exact build. If any line below changes (for
example after a Steam update), re-check before trusting earlier notes.

| What | Value | How it was found |
|---|---|---|
| Title | ACE COMBAT 7: SKIES UNKNOWN | Steam |
| Store | Steam, app 502500, depot 502501 | Steam's install record (`appmanifest_502500.acf`) |
| Steam build id | **9855922** | same file (`buildid`) |
| Depot manifest | 788319397026631312 | same file |
| Main program | `Ace7Game.exe` in the game's top folder (there is no separate `Binaries\Win64` launcher) | folder listing |
| SHA-256 of `Ace7Game.exe` | **c7da97f5f8a807d4f1264adbb074146fcffe9bdc2ffa98791b822cd28e558f4f** | Co-op Anything `game_identity`, confirmed by REA |
| Size | 65,331,992 bytes | same |
| Built | 2 Nov 2022 (the exe's own timestamp) | same |
| Game version | 2.2.1.16 | the exe's version information |
| Engine | **Unreal Engine 4.18.2** | the exe's version information says 4.18.2.0; its text says `++UE4+Release-4.18` (66 times) |
| Data packs | 12 `.pak` files, pak format version 4 (normal for UE 4.18), encrypted | pak footers |
| Steam library inside the game | Steamworks SDK v1.39 (`steam_api64.dll`) | folder listing |
| Copy protection | Steam's own wrapper ("SteamStub", the `.bind` section). The exe's code section is scrambled on disk (it looks like random data) and only unscrambled by Steam when the game starts. Denuvo was removed in 2021. | section check |
| Anti-cheat | No third-party anti-cheat (no Easy Anti-Cheat, BattlEye or similar in the exe). The Steam store page doesn't list Valve Anti-Cheat. The config's `bVACEnabled=1` is Unreal's default setting. The game does have **its own cheat checks** in online matches (see research.md). | exe text, Steam store page, config |
| OS | Windows 11 Home (10.0.26300), 64-bit | this PC |
| Installed at | `C:\Program Files (x86)\Steam\steamapps\common\ACE COMBAT 7` | |
| Size of the plain game | 65.66 GB (Windows Explorer shows this as 61.2 GB) | measured, without `~mods` and `ModLoader` |
| Mods installed | 30 mods in AC7 Mod Loader's library, 19 folders currently placed in `Game\Content\Paks\~mods` (0.84 GB) | folder listing |
| Saves | `%LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 7\SaveGames\` (0.7 MB in total with config), also synced by Steam Cloud | folder listing, store page |

Nothing in the real install, the mods, the mod loader or the saves was changed.
Everything above was read only.
