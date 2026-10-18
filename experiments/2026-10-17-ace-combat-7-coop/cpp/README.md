# C++ add-ons for UE4SS in the game copy

Plain-language notes on what was found out about the copy's UE4SS, how its C++ add-ons
are built, and what is in this folder. Written 18 Oct 2026 under the README's addendum
(sessions may build a C++ add-on for UE4SS). Nothing here touches the real install.

## Why a C++ add-on at all

The co-op plan shows your friend's plane in your game as a "puppet": an AI plane that is
put, every frame, where the other player's plane is. The puppet half works from a file
(workbench section 7). What is missing is the live feed: positions arriving over the
network instead of being read from a file. UE4SS's scripting language, Lua, has no way to
open a network connection, so that one piece has to be written in C++, the language UE4SS
itself is written in. UE4SS loads such add-ons ("C++ mods") from `Mods\<Name>\dlls\main.dll`
and the game copy already carries two of them (KismetDebuggerMod, EventViewerMod).

## Which UE4SS source the copy's build comes from

The copy runs the Playmore "PM-UE4SS-ZR1903" build (downloaded 17 Oct from the
Playmore-ModdingConcepts/PM-UE4SS release page). Its log says

    UE4SS - v3.0.1 Beta #0 - Git SHA #48e7edfe
    UE4SS Build Configuration: LessEqual421__Shipping__Win64 (MSVC)

- **48e7edfe** is a commit in the public UE4SS repository, UE4SS-RE/RE-UE4SS, from
  1 February 2026 ("docs: Updated changelog"). It is one of the "experimental" builds of
  UE4SS's main branch, which still calls itself v3.0.1 Beta (the last numbered release,
  v3.0.1, is from February 2024 and much older). The PM-UE4SS repository is a fork of
  RE-UE4SS; its own branch is based on an *older* snapshot and does not contain this
  commit, so the DLL in the copy was built from the upstream commit, by Playmore, on
  24 February 2026 (the date stamped inside the DLL), as a "hybrid" build according to
  the release notes. Whatever Playmore changed, the parts an add-on touches are
  unchanged: the add-on interface header is byte-for-byte the same in both repositories,
  and every function the shipped example add-ons import exists in the copy's UE4SS.dll
  with exactly the names the 48e7edfe headers produce.
- **LessEqual421** is UE4SS's build flavour for games on Unreal Engine 4.21 or older
  (Ace Combat 7 is 4.18). It changes how some engine structures are laid out, so add-ons
  must be built with the same flavour (`FNAME_ALIGN8` and `LESSEQUAL421` defines).
- **Shipping, MSVC**: a release build with Microsoft's compiler. The DLL carries the
  compiler's build numbers: MSVC 14.44 (Visual Studio 2022 version 17.14). C++ add-ons
  must use the same C++ runtime as UE4SS.dll (the header says so in a comment), so the
  same compiler family was used here.

The source was cloned at exactly that commit into `cpp\RE-UE4SS` (35 MB; a "blobless"
clone, so only the checked-out files were downloaded).

## How C++ add-ons work in this version

An add-on is a DLL that exports two plain C functions UE4SS looks up by name:

    start_mod()        -> creates the add-on object and returns it
    uninstall_mod(mod) -> deletes it

The object is a C++ class derived from UE4SS's `RC::CppUserModBase`
(`UE4SS/include/Mod/CppUserModBase.hpp`). UE4SS calls its methods at the right moments:

| Method | When UE4SS calls it |
|---|---|
| constructor | as soon as the DLL is loaded, before the game's engine is found ("Starting C++ mod" in the log) |
| `on_unreal_init()` | once UE4SS has found the engine's objects (after the "scan") |
| `on_program_start()` | once UE4SS itself is fully up, just before Lua mods start |
| `on_lua_start(mod_name, lua, main_lua, async_lua, hook_lua)` | for **every Lua mod** UE4SS starts; `lua` is that mod's Lua instance, and this is where a C++ add-on can add functions that the Lua mod can call |
| `on_lua_stop(...)` | before a Lua mod is stopped (for example on the Ctrl+P reload) |
| `on_update()` | every frame |
| `on_ui_init()`, `register_tab()` | the UE4SS debug window (not used here) |

C++ add-ons start before any Lua mod, in `mods.txt` order, and the Ctrl+P hot reload
unloads and reloads them too (the log shows "Stopping C++ mod ... for uninstall" and
"Starting C++ mod" again), so an add-on must tidy up after itself in its destructor.

Lua functions are added through UE4SS's `LuaMadeSimple::Lua` class:
`lua.register_function("Name", f)` makes `Name()` a global function in that Lua mod,
where `f` is a plain C++ function `int f(const Lua&)` that reads its arguments with
`lua.get_integer()` etc., pushes results with `lua.set_string()`, `lua.set_integer()`,
`lua.set_number()`, `lua.set_nil()`, and returns how many results it pushed. (This is the
mechanism UE4SS uses for its own Lua API, for example `RegisterHook`.)

Logging goes through `Output::send<LogLevel::Verbose>(STR("text {}\n"), value)`, which
writes to UE4SS.log and the UE4SS console.

### The build system of this version

At commit 48e7edfe the repository has both a `CMakeLists.txt` (the documented, current
way: "CMake >= 3.22, Visual Studio >= 17.13, Rust >= 1.73, Ninja or MSVC") and an
`xmake.lua` left over from 2024-2025. The guide (`docs/guides/creating-a-c++-mod.md`)
describes the CMake way: a folder with `RE-UE4SS` cloned inside it and a small
`CMakeLists.txt` per mod that says `target_link_libraries(MyMod PUBLIC UE4SS)`, so the mod
is compiled together with the whole of UE4SS and inherits its settings.

**That documented route is closed to us**, for two reasons found in the repository:

1. UE4SS's Unreal headers live in a git submodule, `deps/first/Unreal`, that points at a
   **private** repository (`Re-UE4SS/UEPseudo`). It is only readable with a GitHub account
   linked to an Epic Games account, which the guide's step 1 asks for and which the
   project rules say needs your OK (and would tie your accounts together). The same
   headers are needed to build UE4SS.dll itself and the two example add-ons that ship
   with it.
2. Building UE4SS.dll also needs the Rust toolchain for its pattern scanner
   (`patternsleuth`), another large install.

### What was done instead (and why it is sound)

An add-on does not need UE4SS.dll to be rebuilt; it needs (a) the headers that declare
the classes it uses, (b) an "import library" that tells the linker which functions live in
UE4SS.dll, and (c) the same compiler settings. All three can be had without the private
headers:

- **Headers**: `cpp\RE-UE4SS` at 48e7edfe provides `CppUserModBase.hpp`, the
  `LuaMadeSimple`, `DynamicOutput` (logging), `File`, `String` and `Input` headers, and
  the Lua headers. One header, `GUI/GUITab.hpp`, drags in the debug window and through it
  the private Unreal headers; `cpp\shim\GUI\GUITab.hpp` is a copy of just the class
  declaration from that file (identical members) placed ahead of it on the include path.
  Add-ons built this way cannot add tabs to the UE4SS debug window, which these don't.
  The log functions also need the `fmt` library's headers; the version UE4SS's own build
  fetches (11.2.0) is cloned in `cpp\third\fmt`.
- **Import library**: `cpp\make-implib.py` reads the list of 4,087 functions the copy's
  own `UE4SS.dll` exports and writes it as a `.def` file; the librarian (`lib.exe`) turns
  that into `UE4SS.lib`. So the add-ons link against exactly the UE4SS they run in, which
  is a tighter match than building UE4SS a second time would give.
- **Settings**: `cpp\build.ps1` uses the defines and flags UE4SS's own CMake files set for
  `LessEqual421__Shipping__Win64` (read from `cmake/modules/ProjectConfig.cmake` and
  `cmake/modules/CompilerOptions/msvc-compatible.cmake`): C++23, release optimisation,
  the shared C++ runtime (`/MD`), `UE_GAME FNAME_ALIGN8 LESSEQUAL421 UE_BUILD_SHIPPING
  PLATFORM_WINDOWS ... UNICODE`, and the same warning settings.

The compiler is the portable MSVC 14.44 + Windows SDK in `C:\AC7-Coop-Tools`
(see `downloads\installed-tools.md` for what, where, sizes and checksums, and why it is in
a folder rather than installed). CMake, Ninja, xmake and Rust turned out not to be needed:
two source files do not need a build system, and `build.ps1` calls the compiler directly.

After building, a check with a small script (`tools`-free, in the session) confirmed that
every function HelloMod (17) and CoopNetMod (27) import from UE4SS.dll exists in the copy's
UE4SS.dll under exactly that name, and that the DLLs import the same runtime DLLs
(MSVCP140, VCRUNTIME140) as the add-ons Playmore shipped.

## What is in this folder

| Path | What it is |
|---|---|
| `README.md` | this file |
| `build.ps1` | builds the add-ons; `-Install` copies them into the game copy and lists them in `mods.txt` (refuses while the game runs) |
| `make-implib.py` | writes the `.def` file for the import library from the copy's `UE4SS.dll` |
| `HelloMod\dllmain.cpp` | the UE4SS guide's own hello-world example, built first to prove the toolchain (the one line that looks up an Unreal object is left out: private headers) |
| `CoopNetMod\dllmain.cpp` | the socket add-on, see below |
| `shim\GUI\GUITab.hpp` | the stand-in header explained above (a class declaration copied from RE-UE4SS, which is MIT-licensed; the notice is in the file) |
| `RE-UE4SS\` | UE4SS source at commit 48e7edfe (git clone) |
| `third\fmt\` | fmt 11.2.0 (git clone) |
| `build\` | build output: `UE4SS.def`, `UE4SS.lib`, and `<Mod>\main.dll` + `main.pdb` |

To rebuild and reinstall, with the game copy closed:

    powershell -NoProfile -ExecutionPolicy Bypass -File cpp\build.ps1 -Install

## CoopNetMod: what the add-on does

When UE4SS starts it, CoopNetMod opens a UDP socket on the local address 127.0.0.1,
port 27777, and starts a thread that waits for packets. Each packet is one line of text:

    time,x,y,z,pitch,yaw,roll

the same fields the flight recorder writes. The add-on keeps the newest 64 packets with
their arrival times and a running count. It never sends anything, and it only listens on
the local machine, so nothing can reach it from outside this PC.

Into every Lua mod UE4SS starts, it adds four functions:

| Lua function | Returns |
|---|---|
| `CoopNet_Count()` | how many packets have arrived since the add-on started |
| `CoopNet_Latest()` | the newest packet's text, its number, and its age in milliseconds (or nil if none yet) |
| `CoopNet_Since(n)` | the oldest remembered packet newer than packet number `n` (text, number, age), so a script can fetch every packet it has not seen yet, one call at a time |
| `CoopNet_Status()` | a short text: whether the socket is open, how many packets and bytes |

`tools\coop-net-sender.py` plays a recorded flight into that socket at 40 packets a
second, standing in for the other player's PC. `mods\CoopNetCheckMod` is a one-screen Lua
mod that prints the count once a second, which is how the add-on was proved at the title
screen. `mods\CoopFlightLabMod` gained a key (F11) that drives the puppet plane from the
live packets instead of from a file (workbench section 9).

## Status

See workbench.md section 9 for what was tested and what it showed.
