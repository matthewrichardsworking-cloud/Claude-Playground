# All 68 candidates

Every repo the scouts found, with the vetting agent's verdict (before the ranking and skeptic passes, which are in [README.md](README.md)). Vetted 19 Oct 2026. **Verdict** is the vetting agent's: assimilate, reference-only (read, don't install), later (when a matching game or need turns up), skip. Repo names are plain text, not links: a few candidates were turned down as unsafe, so read the verdict before opening one.


## Ace Combat 7

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `CreeperUX/AC7-Integrated-Mod` | MIT | 2026-10-16 | 5 | assimilate | This is the only public source that shows exactly where analog flight input enters AC7, on the owner's exact build. It comes with a reusable flight model under MIT. It solves a problem the Playground hit and wrote down (Input* … |
| `Weebpummling/ac7-cockpit` | MIT | 2026-08-23 | 3 | reference-only | Useful notes and a field list for the bot's awareness code, plus the Input.ini/vJoy analog-control idea. There's nothing to install, its loop pattern is one we've seen crash AC7, and the CreeperUX hook is a cleaner analog route. |
| `greentrafficlight/nimbus-template` | none | 2024-02-17 | 3 | reference-only | It is the most readable AC7 class reference that cloud sessions can reach, and it backs up the PC object-dump findings the bot design relies on (InputPitch/Roll/Throttle, PlayerWeaponActivator, Mission). It has no licence, … |

## F.E.A.R. and older games

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `wemino/echopatch` | GPL-3.0 | 2026-10-04 | 4 | assimilate | It is the standard F.E.A.R. base layer and the clearest working reference for how the engine is hooked, which fills universal-modder's LithTech gap. Assimilate it only with a locked ini (CheckLAAPatch = 0) and a written warning, … |
| `five-damned-dollarz/io_scene_jupex` | MIT | 2024-11-15 | 4 | assimilate | It fills the F.E.A.R. gap directly: level layout, object placement and, through the format notes, the AI nav mesh, for bot and co-op planning. It is MIT and small enough to reuse headlessly. Its limits (work in progress, idle, … |
| `katana-steel/lithtech` | none | 2026-07-28 | 4 | reference-only | It is the most direct help for the owner's next game and fills universal-modder's missing LithTech playbook: Monolith's own co-op mission manager next to F.E.A.R.'s matching server mission manager, all readable in the cloud. It … |
| `sendotarget/fear-more` | MIT (allowlisted components only: … | 2026-07-18 | 3 | reference-only | Its documents are the best guide to F.E.A.R.'s game-code source and its compiler-compatibility limit, and they are MIT, so worth reading and crediting for a LithTech playbook and for any F.E.A.R. co-op idea. Its launcher and … |
| `dr-89/fear-vr` | MIT | 2026-08-04 | 3 | reference-only | It shows the safe way to mod F.E.A.R. (exe untouched, byte-checked in-memory patches, wrapping game modules, 32-to-64-bit IPC) and has a verified-looking address map for the game client. That is valuable reading for a LithTech … |
| `Reloaded-Project/Reloaded-II` | GPL-3.0-only | 2026-09-23 | 2 | later | It's a solid general loader, but it does nothing for AC7, the bot or F.E.A.R. that existing routes don't already do better. It's heavy and needs .NET, and two of its paths break the owner's rules. Revisit only when a game whose … |
| `rohit-n/lithtech` | none | 2026-06-19 | 2 | skip | Not F.E.A.R.'s engine version. The F.E.A.R. part is better taken legitimately from the owner's own Public Tools. The engine source has no verifiable licence and may be leaked. What remains, an older LithTech engine and its tools … |

## Unreal Engine

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `littleRabbit94/ue4ss-bridge` | MIT | 2026-09-16 | 5 | assimilate | This is the biggest direct speed-up on the list for the AC7 puppet-plane fallback and the playtest bot, and it works for every later Unreal game. It is small enough to read in full, MIT, ships no binaries, and uses the same UE4SS … |
| `atenfyr/UAssetAPI` | MIT | 2026-10-15 | 4 | assimilate | The standard, actively maintained base for every UE asset and Kismet tool. It understands AC7's quirks natively, gives Claude a CLI JSON route on the PC, and serves future Unreal games. universal-modder only names it and misses … |
| `tge-was-taken/KismetKompiler` | MIT | 2024-07-12 | 4 | assimilate | It fills a real gap in Claude's Unreal toolchain (readable and editable Blueprint scripts) that universal-modder lacks. There's direct UE 4.18 test evidence, and it would replace hand-assembled bytecode for AC7 mission edits. … |
| `trumank/jmap` | MIT (LICENSE file, (c) 2025 Truman … | 2026-09-18 | 4 | assimilate | A tool that is cheap, MIT-licensed, actively released and needs no injection. It fills a real cross-game gap (.usmap and default-value dumps for every UE4/UE5 game) and gives AC7 a structured, diffable reflection dump the bot can … |
| `trumank/kismet-analyzer` | MIT | 2026-01-10 | 3 | later | Real value for whole-game Blueprint maps, but it overlaps heavily with KismetKompiler (readable text) and UAssetAPI (JSON). Pick it up if KismetKompiler fails on AC7's 4.18 assets, or when a Blueprint-heavy game needs a … |
| `eliotvu/unreal-library` | MIT | 2026-10-16 | 3 | later | It is the right tool for a real cross-game gap (UE1-3 script decompilation), it is MIT and it is actively maintained. But no UE1-3 game is on the owner's list yet: AC7 is UE4 and F.E.A.R. is LithTech. Building it needs a .NET SDK … |
| `trumank/patternsleuth` | MIT OR Apache-2.0 (declared in the … | 2026-09-30 | 3 | later | Useful and well maintained. It fills the 'AES key without unpacking' and 'why did UE4SS's scan fail' gaps for future UE games. But it does nothing for AC7, needs a nightly Rust build on the PC, and its main scanning power already … |
| `elliotttate/uevr-mcp` | MIT (stated only under a '## License' … | 2026-06-14 | 3 | later | A real capability for future UE 4.22+ games (live object access, ProcessEvent tracing and covered-window screenshots from an MCP). But it doesn't reach AC7's 4.18, it's single-maintainer and quiet, its in-game HTTP API is … |
| `emberglazee/project-modman` | MIT | 2026-10-12 | 2 | later | It is well made and MIT, but it targets a game the owner hasn't named, and its AC7 overlap is already covered by NimbusModManager and the owner's AC7 Mod Loader. Pick it up if Project Wingman becomes a target, or read combine.rs … |
| `trumank/uesave` | MIT (LICENSE file, (c) 2022 Truman … | 2026-04-23 | 2 | later | Mature, permissive and easy to adopt, and it fills a small cross-game gap (setting up playtest states in UE games). But AC7's save is encrypted, so it gives nothing now. Pick it up when a future UE game with plain GVAS saves … |

## Unity, .NET, Godot

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `snowyegret23/UnityInfoMCP` | MIT | 2026-08-09 | 4 | assimilate | It fills a real gap across Unity games: a licensed, safe, Claude-Desktop-ready way for Claude to see inside a running Unity game under either loader. It also takes screenshots without the mouse. Use it before bepinex-mcp because … |
| `krafs/publicizer` | MIT | 2026-09-18 | 3 | assimilate | MIT, actively maintained, and nearly free to adopt. It fixes a documented cross-game .NET gotcha in universal-modder's own notes, and it goes in as a template and playbook reference with no game code committed. |
| `rkuhn153/bepinex-mcp` | MIT | 2026-08-11 | 3 | later | It is a real Unity counterpart to the AC7 tooling, but it is unsafe as shipped and no Unity game is queued. Adopt it when a Unity game needs live patching, after a small patch: bind only 127.0.0.1, require a random token or … |
| `lukefz/il2cppinspectorredux` | AGPL-3.0-only | 2026-08-25 | 3 | later | It fills a real IL2CPP-to-Ghidra naming gap that feeds the owner's REA + Ghidra setup, and it is the maintained successor. But it only matters once an IL2CPP game is chosen; then use the release CLI with the rule-breaking options … |
| `vfsfitvnm/frida-il2cpp-bridge` | MIT | 2026-09-06 | 3 | later | Active, popular and permissively licensed, but it only matters once an IL2CPP game is on the list, and loader-based tools (UnityInfoMCP, BepInEx 6) are easier on Windows. Record it in the Unity notes now as the licensed … |
| `bepinex/bepinex.debug` | LGPL-3.0-only | 2026-10-11 | 3 | later | Trustworthy and useful for cutting restart time and getting clean logs, but it only matters for Mono BepInEx 5 games and none is queued. Install it per game when the first one comes up, and add a line to the Unity notes now. |
| `yukieiji/UnityExplorer` | GPL-3.0-only | 2026-09-11 | 3 | later | It's the right build to install when the first Unity game comes up, because the archived original no longer keeps up with BepInEx 6 or MelonLoader 0.6+. It does nothing for AC7, F.E.A.R. or the bot today, and Claude can't drive … |
| `hhyyrylainen/GodotPckTool` | MIT | 2026-07-24 | 2 | skip | It duplicates GDRE Tools, which universal-modder already names and which is MIT, active and has a pck-create and pck-patch CLI. No Godot game is planned, and the editor is needed anyway for anything beyond swapping … |

## Native loaders and graphics

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `elishacloud/dxwrapper` | Zlib | 2026-10-17 | 4 | assimilate | An actively maintained, permissively licensed tool that is already part of the GOG F.E.A.R. install and covers a whole generation of 32-bit D3D9-and-older games, and universal-modder doesn't name it. Low effort, because no build … |
| `apitrace/apitrace` | MIT | 2026-10-09 | 4 | assimilate | It fills a real, verified gap in Claude's toolchain: seeing what an old D3D8 or D3D9 game draws. That gap matters right away for F.E.A.R. and for many later games. It is permissively licensed, built by CI, current, and gives … |
| `JiaboLi-GitHub/renderdoc-mcp` | MIT | 2026-05-19 | 4 | assimilate | MIT, low effort, and it fills a real cross-game gap that universal-modder's playbooks already assume: Claude can't see inside a frame today. It is the most complete of the three RenderDoc MCPs checked (ZylNice runs inside the … |
| `thirteenag/widescreenfixespack` | MIT | 2026-10-09 | 3 | reference-only | A valuable worked-example library, with one directly relevant LithTech Jupiter EX template (Condemned), but it is per-game code rather than a tool to wire in. It also contains two DRM or CD-check pieces that conflict with the … |
| `SpecialKO/SpecialK` | GPL-3.0-only | 2026-10-17 | 2 | reference-only | It's worth reading as a hook catalogue, but not worth installing. EchoPatch already does the F.E.A.R. fixes, AC7 already has its hook stack, and it carries opt-in and per-game DRM and online-check workarounds that clash with the … |
| `doitsujin/dxvk` | Zlib | 2026-10-19 | 3 | later | It is a trusted, permissive, actively maintained tool and the only practical route to RenderDoc captures of Direct3D 8/9 games, which matters for F.E.A.R. and the older games to come. But nothing in the current F.E.A.R. plan … |
| `aap/librw` | MIT | 2026-08-26 | 2 | later | It is the clean, permissive source for RenderWare model and texture formats and fills a gap in universal-modder, but none of the owner's current or next games uses RenderWare, so wiring it in now buys nothing. |
| `samuelgr/xidi` | BSD-3-Clause | 2026-09-24 | 2 | later | Solid, permissive and maintained, but it solves a problem none of the current targets has: AC7 is XInput, and F.E.A.R.'s controller support comes with EchoPatch. Record it as the go-to fix for a future old DirectInput game whose … |

## Co-op references

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `lsalzman/enet` | MIT (LICENSE: Copyright (c) 2002-2024 … | 2026-06-23 | 4 | assimilate | Fills a real gap. Claude's PC toolchain has no reliable game-networking library, and every native co-op mod needs one. It is tiny, MIT, 20 years old, builds with the compiler already on the PC, and can be tested in the cloud. … |
| `exraven99-design/PWCoop` | MIT | 2026-10-19 | 4 | reference-only | It's the closest open-source match to the AC7 fallback plan, with concrete crash-avoidance and ghost-spawning patterns worth borrowing. It's an alpha with binaries we shouldn't run, and Double Trigger already covers AC7's … |
| `votv-mp/multivoid` | MIT (LICENSE file, (c) 2026 pelmentor … | 2026-10-18 | 4 | reference-only | The best open model of a UE4SS-hosted co-op mod with puppet players, host-side AI and multi-copy testing. It maps closely onto the AC7 puppet-plane fallback and onto a future UE co-op playbook. It's a reference rather than … |
| `tiltedphoques/TiltedEvolution` | GPL-3.0-or-later (LICENSE). It says … | 2026-10-18 | 3 | reference-only | The best-maintained, agent-documented open example of AI ownership hand-over and quest/world-state sync in a big single-player game. Worth reading before any future open-world co-op, and to inform the 'who runs this enemy' … |
| `ampreeT/SourceCoop` | GPL-3.0 (LICENSE) | 2026-08-25 | 3 | reference-only | Its real value now is as the model for F.E.A.R. co-op through the engine's own multiplayer: what state must follow players across levels and checkpoints. That is a design input, not something to install. It becomes a direct … |
| `valvesoftware/gamenetworkingsockets` | BSD-3-Clause | 2026-10-02 | 2 | reference-only | Well made, permissive and current, but it adds little now. AC7's 2017-era Steam DLL predates these interfaces, Double Trigger already has working Steam P2P, and building the standalone library is heavy for a fallback path. Keep … |
| `lunamultiplayer/lunamultiplayer` | MIT | 2026-08-31 | 2 | reference-only | The only new thing it offers the Playground is the lock/ownership model for AI-plane hand-over, plus the adaptive-delay detail. Both are worth reading if the puppet-plane fallback is built out, but buffered interpolation already … |
| `praydog/AutomataMP` | MIT (LICENSE: Copyright (c) 2022 … | 2024-01-20 | 2 | reference-only | The scouts' claims check out, but its value for AC7 is small. Double Trigger (MIT, same game) already implements host-owned enemies and puppets, with prediction and faded corrections that AutomataMP lacks. It is kept as reference … |
| `onimp/oni_multiplayer` | MIT (LICENSE: Copyright (c) 2023 Zuev … | 2026-03-19 | 2 | later | Accurate, permissive and legitimate, but nothing on today's list needs it. AC7 uses Unreal and Double Trigger already rides the game's own Steam P2P. F.E.A.R. predates Steamworks and would use its engine's own multiplayer. … |
| `multitheftauto/mtasa-blue` | GPL-3.0 (LICENSE; README: 'Unless … | 2026-10-17 | 2 | skip | Redundant. For AC7, Double Trigger (MIT, same game) already does predicted, faded-in corrections for planes, aces and bosses. As a general pattern, TiltedEvolution's InterpolationSystem and ownership code cover the same ground … |

## Reverse-engineering tools

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `svnscha/mcp-windbg` | MIT | 2026-10-10 | 5 | assimilate | It is the clearest gap in the PC toolchain: Claude can't currently read a Windows crash dump, and every mod iteration on AC7 and the Playground's own C++ add-ons produces crashes. It is MIT, mature, actively released and already … |
| `wattostudios/gameextractor` | GPL-2.0-or-later | 2026-08-01 | 4 | assimilate | It fills a real cross-game gap, a scriptable archive lister and extractor for many engines, which universal-modder never names. It is also the only licensed tool found that opens F.E.A.R.'s .Arch00 archives. Its JSON listing and … |
| `horsicq/detect-it-easy (+ horsicq/DIE-engine for the diec binaries)` | MIT ((c) 2012-2026 hors), both the … | 2026-10-18 | 4 | assimilate | Cheap, MIT, very actively maintained, and it fills a recon gap for every future game, especially disc-era 2000s titles with SecuROM, SafeDisc or StarForce. It directly protects the owner's no-unpacking rule by spotting protection … |
| `WerWolv/ImHex (+ WerWolv/ImHex-Patterns, WerWolv/PatternLanguage)` | GPL-2.0 (ImHex, ImHex-Patterns); … | 2026-10-08 | 4 | assimilate | It fills the cross-game file-format gap with a widely used, very active tool. It suits a non-programmer, who can see the same structure Claude is describing. The headless pattern runner works today on the stable release, and the … |
| `setsunayukiovo/x64dbg-mcp` | MIT | 2026-08-21 | 4 | assimilate | Live debugging is the one real gap next to Ghidra/REA. It matters most for F.E.A.R. (32-bit native, no UE4SS), and also helps AC7 and crash-hunting. It is the most complete and best-guarded x64dbg MCP: loopback by default, writes … |
| `dariushoule/x64dbg-automate-pyclient (+ dariushoule/x64dbg-automate plugin)` | MIT (both; (c) 2025 Dariush Houle). … | 2026-07-28 | 3 | later | It mostly duplicates mcp-windbg. cdb attaches to both 32-bit and 64-bit processes, sets hardware write-breakpoints (ba w4), reads memory and disassembles, and mcp-windbg's live tools already reach it. That one install would cover … |
| `kaitai-io/kaitai_struct (+ kaitai_struct_compiler, kaitai_struct_python_runtime, kaitai_struct_formats)` | The umbrella repo has no LICENSE (it is … | 2026-10-18 | 3 | later | It is worth having once a truly undocumented format needs a parser that ships and is tested. F.E.A.R.'s main formats already have community tools (the LithTech archive and model extractors scouted elsewhere), and ImHex covers … |
| `JameZUK/ProcmonMCP` | MIT ((c) 2026 JameZUK) | 2026-08-30 | 3 | later | It is a convenience layer, not a missing capability. The real prerequisite is Procmon on the PC plus a capture recipe, and Claude can already read a filtered CSV export with Python. Add it when a game's loading behaviour becomes … |
| `trumank/binfold` | MIT (LICENSE file holds the MIT text … | 2026-07-17 | 2 | later | Clever and MIT-licensed, and it would speed up native RE in Ghidra. But it's useless for AC7 (wrapped exe, disk-only input), its UE database comes from an unverified Google Drive link, and building one needs Epic-linked source. … |

## Game AI and automation

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `BrettRyland/BDArmory` | CC-BY-SA-2.0 (no root LICENSE file; … | 2026-08-15 | 3 | reference-only | It is the right source of ideas for missile evasion, extending and energy recovery, and plane-to-plane collision avoidance. But the share-alike licence and the KSP coupling make it a reading list, not something to copy or … |
| `rlabbe/filterpy` | MIT (filterpy, (c) 2015 Roger R. Labbe … | 2022-08-22 | 3 | reference-only | Small, permissive and well explained. It is the standard answer to the bot's documented prediction weakness, and it can be studied and tuned entirely in the cloud. Nothing needs installing on the PC: the value is the algorithm … |
| `vazgriz/FlightSim` | MIT | 2026-05-26 | 2 | reference-only | Clean MIT code that is easy to read, but it mostly duplicates what the AC7 bot already does, often more simply. The only parts worth borrowing are the cross-track waypoint correction and the reaction-delay idea for fair-mode … |
| `BAAI-Agents/Cradle` | MIT | 2024-11-07 | 2 | reference-only | The patterns are worth borrowing for any future bridge-less play-testing, but the code is two years stale and much heavier than anything the owner needs. Read it, cite it (MIT) if ideas are written up, and install nothing. |
| `yannbouteiller/vgamepad` | MIT | 2026-05-18 | 3 | later | It is small, MIT-licensed, and a real cross-game gap (analog control for bots). But the AC7 bot already beats Mission 01 on Ace and Mission 02 on Hard with keyboard input. Installing it means adding a retired kernel driver, whose … |
| `NiiightmareXD/windows-capture` | MIT | 2026-08-08 | 3 | later | Solid and low-effort, but nothing current needs it: the AC7 bot reads game state through UE4SS, and 'um win shot' already covers menu checks. Install it when a game without an in-engine bridge actually needs a vision loop, such … |

## Claude tooling

| Repo | Licence | Last commit | Fit | Verdict | Why |
|---|---|---|---|---|---|
| `anthropics/claude-plugins-official` | Apache-2.0 | 2026-10-15 | 4 | assimilate | An official, actively maintained, Apache-2.0 source that fills a real gap across every game: checking Lua, C++ and Python while writing it. The cost is a few catalog lines plus installing language servers on the PC. Pin only … |
| `microsoftdocs/mcp` | CC-BY-4.0 (docs content, LICENSE) and … | 2026-09-10 | 3 | assimilate | Almost free to add, and a steady accuracy gain for the Windows side of every native mod (input, sockets, DLL proxies, D3D9/11, MSVC errors). The gain is modest, because Claude can already read learn.microsoft.com pages with … |
| `trailofbits/skills` | CC-BY-SA-4.0 | 2026-10-15 | 3 | assimilate | A narrow install is worth it. It isn't a modding tool, but the Playground keeps putting third-party code on the owner's PC, and supply-chain-risk-auditor plus differential-review make those checks systematic and measured. … |
| `punkpeye/awesome-mcp-servers` | MIT | 2026-10-17 | 2 | reference-only | It's a good place to look first when a new engine or emulator comes up, and its MIT licence makes linking easy. But it isn't a tool. Most of its modding-relevant entries are already named in universal-modder, it has nothing for … |
| `x360ce/x360ce` | LGPL-3.0-only | 2026-10-18 | 3 | later | It's a well-made, Claude-ready tool for a real gap (controller mapping), with an official MCP route. But it rests on a retired kernel driver and has no current need. Install it when the owner gets a flight stick or wheel, or if … |
| `MaaXYZ/MaaMCP` | AGPL-3.0-or-later (MaaMCP). … | 2026-10-02 | 2 | later | It is a real new capability (OCR plus repeatable menu pipelines), but it adds little to the current work: AC7 already has widget-based menus and pauses in the background, and F.E.A.R. probably ignores posted input. Revisit when a … |
| `CursorTouch/Windows-MCP` | MIT | 2026-10-18 | 2 | later | Well made, MIT and current, and the accessibility tree is cheaper and more reliable than screenshot-and-guess for normal Windows apps. But it is not a modding capability. It overlaps the desktop app's own computer use and `um … |
