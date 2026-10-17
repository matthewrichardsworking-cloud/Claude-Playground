# Ghidra: a read-through

**Status:** read the docs at the latest release. Not installed or run here.

[Ghidra](https://github.com/NationalSecurityAgency/ghidra) is the free
reverse-engineering program made by the NSA (the US National Security Agency).
It's the decoding engine REA uses for regular Windows programs, so it goes with
the REA notes in `experiments/2026-10-17-rea-reverse-engineering-tool/`.
Apache 2.0 license; parts written by the US government have no copyright.
I read the README, license, notices and the Getting Started guide at the
`Ghidra_12.1.4_build` tag (released 11 Sep 2026). Nothing copied in.

Steps for putting both tools on the owner's PC are in [home-setup.md](home-setup.md).

## What it does

A program on your computer is stored as machine code: long runs of numbers the
processor understands and people mostly can't. Ghidra turns that back into
something readable in two steps:

- **Disassembly** turns the numbers into assembly, a list of tiny processor
  steps like "copy this, add that, jump there."
- **Decompiling** goes one step further and rebuilds rough C code, which reads
  much more like normal programming. Variable names and comments are gone, so
  it's a guess at the original, but it's usually a good one.

It also draws diagrams of how the code branches, lists text and names found
inside the program, and shows which parts call which. It handles Windows,
Mac and Linux programs, plus lots of processor types (game consoles, routers,
old DOS machines). You can use it with its own windows and menus, or run it
with no window at all, which is how REA uses it.

## What it needs

- Windows 10 (version 1809 or later), macOS or Linux, 64-bit.
- 4 GB of memory and 1 GB of disk space at minimum. The docs "strongly suggest"
  two monitors, which tells you how busy its screens are.
- **Java 21** (the JDK version, 64-bit). Java is a separate free program that
  Ghidra runs on. The docs point to Adoptium Temurin or Amazon Corretto.
- Python 3.9 to 3.14 only for some extras. REA doesn't need it.

## Things worth knowing

- **No installer.** You unzip it into a folder and run `ghidraRun.bat`. It
  doesn't touch Windows settings, so deleting the folder removes it. The
  downside is no Start menu entry or desktop shortcut unless you make one.
- **Don't unzip over an old copy.** New versions go in a fresh folder.
- **Pick the right download.** On the releases page, the real one is the
  `ghidra_..._PUBLIC_....zip` file under "Assets." The two "Source code" files
  are the raw code, not the program.
- **Folder names matter.** It won't start if the folder path contains `!` or
  `^`.
- **Keep it current.** The README warns that some older versions have known
  security holes and links to the list. The newest release is the safe pick.
- **It fits REA exactly.** REA accepts Ghidra 12.1.x and was tested with
  12.1.4, which is the newest release right now. REA's Windows support is
  marked experimental and is read-only: it looks at programs and never
  changes them.
