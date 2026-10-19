# Developer tools installed for the C++ add-on (18 Oct 2026)

Under the 18 Oct addendum ("sessions may build a C++ add-on for UE4SS and install the free
developer tools that needs, from their official pages, with sizes and checksums written
down"). Everything below can be removed by deleting the folders named; nothing was
registered with Windows, no system setting was changed, and no account was linked.

## Why the compiler is in a plain folder instead of "installed"

The normal route is Microsoft's **Visual Studio Build Tools** installer. Its bootstrapper
was downloaded (see table) but **not run**: it needs an administrator prompt (the blue
"Do you want to allow this app to make changes" box), which only you can click, and you
were away. The installer itself only downloads packages from Microsoft's servers and
unpacks them, so `tools\fetch-msvc-portable.py` does the same by hand: it reads the same
package list the installer reads (Microsoft's "channel manifest"), downloads just the
compiler and Windows SDK packages from `download.visualstudio.microsoft.com`, checks each
file's SHA-256 against the value in that list, and unpacks them into `C:\AC7-Coop-Tools`.
No administrator rights are needed for that. If you ever want the standard installation
instead, run `downloads\vs_BuildTools\vs_BuildTools.exe`, pick "Desktop development with
C++", and `cpp\build.ps1` will use it automatically (it looks for a Visual Studio install
when `C:\AC7-Coop-Tools\env.ps1` is missing).

## What is where

| Item | Where | Size | How to remove |
|---|---|---|---|
| Microsoft C++ compiler (MSVC toolset 14.44.35207, "v143", from Visual Studio 2022 17.14) | `C:\AC7-Coop-Tools\msvc\` | 371 MB | delete the folder |
| Windows 11 SDK 10.0.26100 (headers and libraries for Windows itself, e.g. `windows.h`, `winsock2.h`, `ws2_32.lib`) | `C:\AC7-Coop-Tools\sdk\` | 964 MB | delete the folder |
| `env.ps1` (puts the two above on the path of one PowerShell window) | `C:\AC7-Coop-Tools\env.ps1` | 1 KB | delete with the folder |
| The downloaded packages themselves (43 files) and Microsoft's package list | `AC7-Coop\downloads\msvc-portable\` | 325 MB | delete the folder; they are only needed to unpack again |
| Visual Studio Build Tools bootstrapper (downloaded, never run) | `AC7-Coop\downloads\vs_BuildTools\vs_BuildTools.exe` | 4.5 MB | delete the folder |
| UE4SS source code, the exact version in the game copy (git clone, history without file contents) | `AC7-Coop\cpp\RE-UE4SS\` | 35 MB | delete the folder |
| fmt text-formatting library 11.2.0 (git clone; UE4SS's log functions need its headers) | `AC7-Coop\cpp\third\fmt\` | 4 MB | delete the folder |
| Build output (import library, object files, the two add-on DLLs with their debugging symbols) | `AC7-Coop\cpp\build\` | 12 MB | delete the folder; `cpp\build.ps1` recreates it |
| The add-ons inside the game copy | `C:\AC7-Coop-Game\ue4ss\Mods\HelloMod\` and `...\Mods\CoopNetMod\`, two lines in `Mods\mods.txt` | 0.3 MB | delete the two folders and the two lines |

Already on the PC before this work, not installed by it: Git 2.x (`C:\Program Files\Git`),
Python 3.15 (`C:\Program Files\Python315`). No Python packages were added (the scripts use
the standard library only). CMake, xmake and Rust were **not** needed in the end (see
`cpp\README.md` for why).

## Downloads, with sources and checksums

### Microsoft

| File | From | Bytes | SHA-256 |
|---|---|---:|---|
| `vs_BuildTools.exe` (Visual Studio 2022 Build Tools bootstrapper 17.14.37806.7) | `https://aka.ms/vs/17/release/vs_BuildTools.exe` → `download.visualstudio.microsoft.com/download/pr/c95450be-.../vs_BuildTools.exe` | 4,474,800 | `2a6aa7d94e38d457a4eb3930fc60056ecab06865b2eb925e5275b8473a017583` |
| `channel.json` (Visual Studio 2022 release channel, 17.14.42+37806.7) | `https://aka.ms/vs/17/release/channel` | 91,688 | `4f0f290bb4d58a061a49a2fa893357a8c9e7e2b49fc91873f533ab8f791e4fa0` |
| `VisualStudio.vsman` (the package list the installer reads, 19,354 packages) | linked from channel.json: `download.visualstudio.microsoft.com/download/pr/c95450be-.../VisualStudio.vsman` | 17,954,770 | `99dda859c4ae3c446eb25620d1a6237bb135d95d14d55cd1d30a15340bb39d80`. **Honest note:** the channel file lists `a871a5ff…` and 30,443,686 bytes for this payload, and the file Microsoft's server actually sends is `99dda859…` and 17,954,770 bytes (fetched twice, identical both times, plain JSON). So the package list itself could not be checked against its listed checksum. It was accepted because everything it pointed at *was* checked two independent ways: each package file matched the SHA-256 in the list, and Microsoft's own digital signatures (Authenticode) on the compiler programs (`cl.exe`, `link.exe`, `lib.exe`, `c1xx.dll`, `c2.dll`, `mspdbcore.dll`), on all nine SDK installers and on the `.cab` archives checked all read "Valid, CN=Microsoft Corporation" (`Get-AuthenticodeSignature`, 18 Oct 07:10). |
| 43 package files: 5 compiler `.vsix` packages (MSVC 14.44), 9 Windows SDK `.msi` installers and the 29 `.cab` archives they reference | `download.visualstudio.microsoft.com` (every URL is in `payloads.json`) | 311,179,323 in total | one line per file in [`msvc-portable\payloads.md`](msvc-portable/payloads.md); every file was checked against the SHA-256 in `VisualStudio.vsman` before unpacking. For five of them the manifest's listed *size* differs from the file served while the SHA-256 matches exactly (noted in `fetch.log`); the checksum is the check that counts. |

Microsoft package versions: `Microsoft.VC.14.44.17.14.Tools.HostX64.TargetX64.base` 14.44.35229
(compiler, linker, librarian; the binaries report 19.44.35229 and install into a
`14.44.35207` folder), `…CRT.Headers.base` 14.44.35220, `…CRT.x64.Desktop.base` and
`…CRT.x64.Store.base` 14.44.35226, `…Tools.HostX64.TargetX64.Res.base` (English messages)
14.44.35229, `Win11SDK_10.0.26100` 10.0.26100.15. The copy's own UE4SS.dll was built with
MSVC 14.44 build 35207/35213, the same toolset family, which is what matters for the two
to share one C++ runtime.

### Double Trigger v0.1.0 (18 Oct 2026, 16:44)

Downloaded on your request from the mod's official GitHub release page,
`https://github.com/layer10-love/double-trigger/releases/download/v0.1.0/<file>`, into
`downloads\double-trigger-v0.1.0\`. All three files match the release's own `SHA256SUMS`.
The DLL is a 64-bit DLL carrying the version stamp `0.1.0+6240b21f`, has no digital
signature (the author says so), and Windows Defender's scan found no threats.

| File | Bytes | SHA-256 |
|---|---:|---|
| `dinput8.dll` | 1,242,112 | `97fdb3b80ca2a310fd7df67e5259d6c04dea280f531a595ab3c062bbd03221d7` |
| `LICENSE` | 1,070 | `8f812ebd69083dee893958aacbe1c3f38830236e251aca7eb2ff5c95f5efb426` |
| `THIRD_PARTY_NOTICES.md` | 6,348 | `98f3a994b8efa8ac779e5a860864285dbe6f1bed0d44ebcc19510c2457feb408` |
| `SHA256SUMS` | 244 | (the release's checksum list) |

Installed only in the copy, by AC7 Mod Loader: `C:\AC7-Coop-Game\dinput8.dll` (a hard link
to the loader's library copy) and the loader's data folder `C:\AC7-Coop-Game\ModLoader\`.
To remove it: run the loader with Vanilla mode on, or delete both. The mod itself writes
`ac7mp.ini`, `ac7mp.log` (and older `ac7mp-N.log`) next to the copy's exe.

**Also in your real install since 18 Oct 2026, 16:53** (your one-time OK): `ACE COMBAT 7\dinput8.dll`
(Mod Loader mod 31, "Double Trigger v0.1.0", in `ACE COMBAT 7\ModLoader\library\`), and the
updated `ACE COMBAT 7\ModLoader\AC7ModLoader.exe` (SHA-256 `cd22a606…e69e962`; the old one,
`94bd369e…789e523ac`, is in `backups\2026-10-18_real-install-before-double-trigger\ModLoader\`).
To remove: untick Double Trigger in the Mod Loader or turn on Vanilla mode; workbench section 13.

### GitHub (git clones, no account needed)

| Repository | Commit | Why | Size |
|---|---|---|---|
| `https://github.com/UE4SS-RE/RE-UE4SS` | `48e7edfe0a085e2209a71bd0e1665d6e6bf01e30` (1 Feb 2026, "docs: Updated changelog") | the version the copy's UE4SS.dll reports ("Git SHA #48e7edfe"); the add-ons are compiled against its headers | 35 MB (clone with `--filter=blob:none`, so only the checked-out files were fetched) |
| `https://github.com/fmtlib/fmt` | tag `11.2.0` = `40626af88bd7df9a5fb80be7b25ac85b122d6c21` | the version UE4SS 48e7edfe fetches during its own build (deps/third/CMakeLists.txt); only its headers are used | 4 MB |

Not fetched: the two git submodules of RE-UE4SS. `deps/first/Unreal` (Re-UE4SS/UEPseudo)
is a private repository that needs a GitHub account linked to an Epic Games account, which
the rules say to ask about first; `deps/first/patternsleuth` is public but only needed to
build UE4SS.dll itself, which this work does not do. The example mods that ship with UE4SS
(KismetDebuggerMod, EventViewerMod) need the private headers, so the guide's hello-world
example was built instead.
