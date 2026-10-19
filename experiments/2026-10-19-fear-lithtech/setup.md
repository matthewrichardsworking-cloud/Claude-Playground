# F.E.A.R. on GOG: setup and a first thing to try

Plain steps for the owner. About ten minutes, fully reversible, no copying or cracking — GOG F.E.A.R. is
DRM-free.

## Install EchoPatch (the fix pack)

1. **Find your game folder.** In GOG Galaxy: Library → right-click F.E.A.R. → "Manage installation" → "Show
   folder". (Without Galaxy it's usually `C:\GOG Games\FEAR`.) It's the folder that contains `FEAR.exe`.
   Leave it open.
2. **Download the patch.** In a browser, go to `github.com/Wemino/EchoPatch/releases/latest` and download
   **`EchoPatch.zip`** (current version 4.3.0, 3 Oct 2026; take the newest if higher). No checksum is
   published, so download only from that official page.
3. **Unzip into the game folder.** Copy everything from the zip into the folder from step 1 (next to
   `FEAR.exe`). The two files that matter are **`dinput8.dll`** (the patch) and **`EchoPatch.ini`** (its
   settings). The game loads the patch by itself on launch.
4. **The "4GB" prompt — you won't see it.** Steam owners get a one-time large-memory/4GB pop-up on first
   launch. Your GOG version already has that built in, so the prompt never appears and there's nothing to do.
   Leave the `CheckLAAPatch` line in the ini as it is — on GOG it does nothing and won't change `FEAR.exe`.
5. **GOG-only — unlock the frame rate.** In the same folder, open **`dxwrapper.ini`** in Notepad, find
   `LimitPerFrameFPS = 60`, change the 60 to **0**, save. GOG ships this capping the game at 60 fps; this
   hands control to EchoPatch. (Skip this and the smoothness fixes stay asleep.)
6. **(Optional) adjust settings.** Open `EchoPatch.ini` in Notepad — each line has a comment. Easy ones:
   `SkipIntro = 1` skips the logos; `CustomFOV = 90` widens the view; raise `HUDCustomScalingFactor` if the
   on-screen text is small on a big monitor. Defaults are sensible, so leaving it alone is fine too.
7. **Play.** Launch F.E.A.R. normally from GOG. Nothing extra to run.
8. **To undo everything.** Delete `dinput8.dll`, `EchoPatch.ini` and any log/`GyroCalibration` files it made.
   Because nothing in `FEAR.exe` was changed on GOG, that's a clean game again.

Expansions (Extraction Point, Perseus Mandate) work the same way — put the same files next to each one's own
`.exe`.

## A first thing to try (proves the toolchain on your build)

**The zero-code version.** Do the install above, and before launching set `SkipIntro = 1` and
`CustomFOV = 90` in `EchoPatch.ini`. Launch. Success looks like: the logo videos are gone (the patch loaded
and its hooks fired on *your* GOG exe) and the view is noticeably wider (it can change how the game renders in
memory). EchoPatch rejects any exe it doesn't recognise with a clear message box, so a normal launch is
itself proof your GOG `FEAR.exe` matched one of its known builds. With the 60-fps line set to 0, the Home key
opens EchoPatch's dev console as a bonus check. Undo is deleting two files.

**The programmer version (reading the game's own data — for a PC session later).** Prove the *other* route:
read a level's contents without the game running.
1. With **Game Extractor** (set up in `../2026-10-19-game-file-tools/`), open one of F.E.A.R.'s `.Arch00`
   archives and extract one `.world00p` level file.
2. List every spawn point, trigger, light and door in that level with a short headless Python script. Don't
   reinvent the parser — reuse the MIT pieces from **io_scene_jupex** (Amphos), keeping the copyright notice
   and crediting Amphos: `utils.py` holds the whole low-level byte reader (`ReadRaw`, `ReadVector`,
   `ReadLTString`, `ReadCString`), and `WorldObjects.py`'s `Object.read()` reads one object's `type_name` and
   properties. The ~10-line header reader checks the version equals 113, reads the four section offsets, and
   seeks to the object section; then loop `Object.read()` and print each object's type and position.

That's a few dozen lines, all MIT. Printing a real level's object list proves you can read F.E.A.R.'s level
format without touching the game — the foundation for any data or level mod.

**Note:** I couldn't build or test that script here — there's no `.world00p` file in the cloud (they're inside
the game's archives on your PC), and the level format has a couple of unverified corners (see the playbook).
So treat it as a verified-on-the-PC task, not a finished tool. The licensed **F.E.A.R. Public Tools SDK** in
your `Claude Tools` folder is the better base for anything past this — its editor and data tools, and its own
game source, under its EULA (keep SDK-derived code off this public repo).
