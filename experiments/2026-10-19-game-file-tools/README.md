# Three tools for reading a game's own files

**Status:** studied; setup notes written. All three run on the PC and are plain downloads (no plugin to pin).
Read-only study in the sandbox; nothing installed on the PC yet.

More picks from the repo shortlist (`experiments/2026-10-19-repo-shortlist/`): the "file toolbox" layer. Each
one only reads, converts, or traces a game's own files — none injects into a game, strips protection, or
touches the system. They cover inspecting Ace Combat 7's Unreal files and F.E.A.R.'s (and other old games')
archives and graphics.

## The three tools

- **UAssetGUI** (`atenfyr/UAssetGUI` + `UAssetAPI`, MIT): reads and edits Unreal Engine asset files
  (`.uasset`/`.umap`) and converts them to and from readable JSON. It has **built-in support for Ace Combat
  7's asset encryption**, so it can open AC7's files directly. Stable version 1.1.0.
- **Game Extractor** (`wattostudios/GameExtractor`, GPL-2.0): opens game **archive** files for about 1,950
  games and lists or copies out their contents. It reads **F.E.A.R.'s `.Arch00` archives** by name (the same
  format covers F.E.A.R. 2, Condemned, and Shadow of Mordor/War). Version 3.16.0008.
- **apitrace** (`apitrace/apitrace`, MIT): records the drawing commands an older game sends to the graphics
  card, so you can read back exactly how it draws its HUD and world — useful for DirectX 8/9 games like
  F.E.A.R. that the usual modern capture tool can't open. Version 14.0.

## What was done

- Read all three projects' source in the sandbox; confirmed licences, current versions, the headless
  command-line use of each, and that each leaves the original game files untouched in normal use.
- Wrote the PC setup and usage steps in [setup.md](setup.md), with the cautions below.
- Nothing is pinned in the plugin catalog — none of these is a Claude plugin; they're ordinary downloads the
  PC uses, like Detect It Easy.

## Cautions, up front

- **UAssetGUI overwrites an Ace Combat 7 asset when you open it in the window** (it decrypts the file in
  place). Always copy AC7 assets out of the game folder and open the copy — never point it at the live
  install. Full detail in setup.md.
- **None of the three publishes a checksum** for its download, so get each only from its official page (linked
  in setup.md), which is the only assurance of what you're downloading.
- **Use only the read/list/extract/dump modes.** Game Extractor's "replace" feature and apitrace's recording
  wrapper are the only ways any of these can change or sit beside a game; setup.md says when each is fine and
  when to steer clear (for apitrace: offline single-player only, never while a game's anti-cheat is active).

## Files

| File | What it is |
|---|---|
| [setup.md](setup.md) | Per-tool: what to download, the exact read-only commands, and the cautions. |
