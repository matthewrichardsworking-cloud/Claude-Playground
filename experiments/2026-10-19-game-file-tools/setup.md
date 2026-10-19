# Setting up the game-file tools on the PC

Three plain downloads. None is a Claude plugin; each is a program the PC runs. All three only read or convert
a game's own files in the uses below.

## UAssetGUI — read and edit Unreal asset files (Ace Combat 7)

### Get it

From `https://github.com/atenfyr/UAssetGUI/releases/latest`, open release **v1.1.0** and download the file
named `UAssetGUI.exe` (about 13 MB). It's a single program — no installer; put it in a tools folder and run
it. (The newest source, 1.1.1, is only on an "experimental" per-commit build and needs a newer runtime; the
stable 1.1.0 is the one to use.)

It needs Microsoft's **.NET Desktop Runtime 8.0** (x64) installed, or the program won't start. If it doesn't
launch, that's the first thing to add (`winget install Microsoft.DotNet.DesktopRuntime.8`). No checksum is
published, so download only from that official releases page.

### Use it

- It opens Unreal `.uasset`/`.umap` files and shows their contents as a tree you can edit, and it converts an
  asset to readable JSON and back from the command line:
  - to JSON: `UAssetGUI tojson Plane.uasset Plane.json VER_UE4_18`
  - back: `UAssetGUI fromjson Plane.json Plane.uasset`
  - (`VER_UE4_18` tells it the engine version — Ace Combat 7 is Unreal 4.18.)
- It has Ace Combat 7's asset encryption built in, so it can read AC7's files where generic Unreal tools
  can't.

### The trap — work on copies

**Opening an Ace Combat 7 asset in the UAssetGUI window decrypts it in place, overwriting that file on disk**
(it shows a "decrypted in-situ" notice). So never open a file straight from the game install — first copy the
asset out to a working folder, then open the copy. The command-line `tojson` does not auto-decrypt AC7 files,
so for AC7 the window is the route, on copies only.

This tool is Unreal-only. It does nothing for F.E.A.R. (a different engine).

## Game Extractor — open a game's archive files (F.E.A.R. and ~1,950 others)

### Get it

From the GitHub releases page for tag **v3.16.0008**
(`https://github.com/wattostudios/GameExtractor/releases`), download **`extract.exe`** (the installer, about
142 MB) and run it — it bundles its own Java, so nothing else needs installing. (There's also `extract.zip`,
a portable copy that just unzips.) Don't download the "source code" zip — it won't run without being built.
No checksum is published; use the GitHub or SourceForge release. Pin to 3.16.0008 or newer (an earlier build
had a path-handling bug when extracting).

### Use it

It's a window by default, but it has a real command-line mode for Claude. From the install folder:

- **List what's in an archive** (read-only, prints JSON):
  `.\jre\bin\java -Xmx1536m -jar GameExtractor.jar -list -input "C:\Games\FEAR\FileX.Arch00" -format JSON -fields All`
- **Copy files out** to a folder:
  `.\jre\bin\java -Xmx1536m -jar GameExtractor.jar -extract -input "C:\Games\FEAR\FileX.Arch00" -output "C:\out\fear"`

It reads F.E.A.R.'s `.Arch00` archives directly (the same plugin also covers F.E.A.R. 2, Condemned, and
Shadow of Mordor/War). Ace Combat 7's Unreal `.pak` files it reads generically — you may have to try to find
the right format variant, since it isn't labelled for AC7 by name.

Both `-list` and `-extract` only read the archive and write copies out; neither changes the original. Avoid
the window's "replace"/save-into-archive feature on original game files — that's the one way it can write
back, and we don't need it. It's Windows-only.

## apitrace — see how an older game draws its screen (F.E.A.R.)

### Get it

From `https://apitrace.github.io/` (Download), get **`apitrace-latest-win64.7z`**, and also
**`apitrace-latest-win32.7z`** for 32-bit games like F.E.A.R. Windows 11 unzips `.7z` with right-click →
Extract All. Self-contained — nothing else to install to read traces. No checksum is published; use the
official site or the GitHub release (version 14.0).

### Use it

Two parts:

- **Recording (on the PC, one offline session).** Copy the matching wrapper DLL — for F.E.A.R. that's the
  32-bit `d3d9.dll` from the win32 build — next to a **copy** of the game's program, launch the game once to
  record a `.trace` file, then delete the DLL. F.E.A.R. draws with DirectX 9, so `d3d9.dll` is the wrapper;
  a 64-bit DirectX 11 game like Ace Combat 7 would use the win64 `dxgi` wrapper instead.
- **Reading the trace (anywhere, read-only).** `apitrace dump game.trace` turns the recording into a full
  text list of every drawing command — textures set, render state, draw calls, shader setup — which is how
  you work out how the HUD and world are drawn. This dump step even runs here in the cloud on a `.trace`
  file; only recording and replaying frames as images need Windows.

**Only record offline single-player.** Dropping a graphics DLL next to a game is exactly what an online
game's anti-cheat can treat as tampering, so keep apitrace to offline copies, record one session, and remove
the DLL afterwards.

For Ace Combat 7 this is a side tool — it could capture AC7's live drawing if that ever mattered, but AC7's
assets are better read with UAssetGUI above.
