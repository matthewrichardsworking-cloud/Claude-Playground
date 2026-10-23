# MinHook and Dear ImGui: on the PC

**Status:** cloned into the owner's `Claude Tools` folder at their request. Source
only; nothing built or run yet.

Two small C/C++ libraries that most game add-ons on Windows are built from. Double
Trigger, the AC7 co-op mod (`experiments/2026-10-17-ace-combat-7-coop/double-trigger-review.md`),
uses both, and step 4 of the F.E.A.R. playbook (`experiments/2026-10-19-fear-lithtech/playbook.md`,
"write your own hook") would need MinHook. Having the source on the PC means a
session can build Double Trigger itself, or write its own add-on, without fetching
anything. Nothing from either project was copied into this repo.

## The two libraries

- **MinHook** ([TsudaKageyu/minhook](https://github.com/TsudaKageyu/minhook), BSD
  2-Clause, copyright 2009-2017 Tsuda Kageyu; includes the Hacker Disassembler
  Engine, BSD, copyright 2008-2009 Vyacheslav Patkov). "Hooking" means making one
  of a program's own functions run your code first: MinHook rewrites the start of
  the function to jump to yours, and gives you a "trampoline" to call the original.
  32- and 64-bit Windows. About 60 files.
  - Latest release **v1.3.4** (28 Mar 2025, tag commit `c3fcafd`); master at
    `8af6b4a` (8 Sep 2026, a fix to the bundled disassembler).
  - Double Trigger pins **v1.3.3** (8 Jan 2017, tag commit `9fbd087`).
- **Dear ImGui** ([ocornut/imgui](https://github.com/ocornut/imgui), MIT, copyright
  2014-2026 Omar Cornut). Draws windows, buttons and sliders with the program's own
  graphics device, so an add-on can show a menu inside a game. `backends/` has the
  glue for DirectX 9 to 12, OpenGL, Vulkan and Win32 input.
  - Latest release **v1.93.0** (14 Oct 2026, tag commit `c1aaac6`); master at
    `4e99c0a` (23 Oct 2026, "1.93.1 WIP"). The `docking` branch (windows that
    snap together) is in the clone too.
  - Double Trigger pins **v1.91.9b** (tag commit `f5befd2`), for its F5 panel drawn
    over AC7's DirectX 11 swap chain.

## Where they are on the PC

`%USERPROFILE%\Desktop\Claude Tools\minhook` and `...\imgui`, full git clones of
the default branch (`master`). Every past version is a tag away
(`git checkout v1.3.3`, `git checkout v1.91.9b`); `git pull` updates. Both are
listed in that folder's `README.txt` and `START-HERE.md`.

## What was checked

- Both licences read: permissive, and both only ask that the copyright notice
  travels with the code (and, for binaries, in the documentation).
- Files that run or are prebuilt: MinHook has two MinGW build scripts; ImGui has a
  `build_win.bat` per example, a CI script and two prebuilt `glfw3.lib` files for its
  examples. Nothing else. None was run.
- Sizes: MinHook 0.8 MB; ImGui 140 MB, almost all of it git history.

## Notes for next time

- To build Double Trigger offline, check out the pinned tags rather than master,
  or the build's hashes won't match. Its `build.cmd` also wants CMake and Ninja,
  which aren't on the PC yet (see the review's "Building it ourselves").
- Hooks belong in offline single-player copies only. A hooked DLL beside a game with
  anti-cheat looks like cheating to it.
