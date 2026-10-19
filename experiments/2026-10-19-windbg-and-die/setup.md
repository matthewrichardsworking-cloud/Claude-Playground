# Setting up WinDbg and Detect It Easy on the PC

Both tools run on your Windows 11 PC. The WinDbg bridge is already switched on for this repo, so a PC session
will offer it; it still needs installing once. Detect It Easy is a plain download.

## WinDbg for Claude (the crash-and-debug bridge)

### What it needs on the PC (one-time)

1. **WinDbg** — Microsoft's debugger, which supplies the `cdb.exe` the bridge drives. Install it from the
   Microsoft Store (search "WinDbg", or the page at `aka.ms/windbg`). Nothing else from it needs setting up;
   the bridge finds it automatically.
2. **uv** — a small tool that launches the bridge. Install it once from a terminal:
   `winget install astral-sh.uv`. On first use it fetches the exact bridge version (`mcp-windbg@1.5.1`) by
   itself; there's nothing else to install, and no separate Python needed.
3. Symbols (the names that turn a crash address into a readable function and line) are handled automatically:
   the bridge points at Microsoft's public symbol server and caches to `C:\Symbols`. If you've already set a
   `_NT_SYMBOL_PATH`, yours is kept.

### Installing it

Once this repo's change is on `main`, a PC session working in the Playground will show the WinDbg bridge as
"enabled in project settings but isn't installed here." To install it:

- Easiest: ask that session to *"install the mcp-windbg-uvx plugin from the Playground catalog"*. It runs
  `claude plugin install mcp-windbg-uvx@claude-playground` with the full path to `claude.exe` (which isn't on
  the PATH on the PC — see the universal-modder setup note), from outside the repo folder.
- Or in the Claude app: the **+** next to the message box → **Plugins** → **Add plugin** → pick
  `mcp-windbg-uvx` from the claude-playground catalog.

Then start a new session. The bridge only works on Windows with WinDbg present, so in a cloud session it will
show as a failed connection — that's expected and harmless, like the fal one.

### What it's good for

- **Read a crash file.** When the game copy or one of our C++ add-ons crashes, Windows can leave a `.dmp`
  file. Claude opens it and runs the standard analysis — what faulted, the call stack, and with symbols, the
  line in our own code. This is the headline use and it's completely safe (read-only).
- **Live-debug our own mod code.** Claude can attach to a running program, set breakpoints and step through
  it, to work out why our own add-on misbehaves.

It adds to, rather than replaces, what's already on the PC: REA + Ghidra read a program's code statically;
the Ace Combat project's own Python readers understand that one game's crash files. This bridge adds
Microsoft-grade, symbolised Windows crash analysis and live debugging that works for any Windows program,
including 32-bit ones like F.E.A.R.

### The guardrails (already set, plus one rule for you to know)

The bridge exposes eleven commands. They're handled in three tiers:

- **Blocked repo-wide** (in `.claude/settings.json`, so no session can use them here): the three
  kernel-debugging commands — `open_kd_session`, `open_kd_dump`, `run_kd_command`. Kernel debugging reads and
  can freeze the whole machine and needs the PC booted into debug mode. That's the "could brick my PC" line,
  so these stay off. (The tool itself has no switch to disable individual commands, so the block lives in the
  repo's settings; the deny names are `mcp__mcp-windbg__open_kd_session` and the other two.)
- **Safe, left on**: listing crash files and opening a user-mode crash file for analysis, plus the
  housekeeping commands. This is the main use.
- **Powerful, left on with a rule**: attaching to a live program and running debugger commands
  (`open_cdb_remote`, `run_cdb_command`). These are what make live debugging of our own mods possible. The
  rule: **never dump or copy a copy-protected game's memory to disk** (the WinDbg commands `.dump /ma` and
  `.writemem`). On a protected game that would write out its unprotected code, which your rules forbid. Debug
  our own mod code, offline. If you ever want a hard lock on this too, the bridge accepts a small filter
  script (`--filter-script`) that can reject those commands; say the word and I'll add one.

## Detect It Easy (the "what protection does this game have" check)

### Installing it

No installer exists — it's a portable download. From the releases page
`https://github.com/horsicq/DIE-engine/releases/latest`, download the Windows file named like
`die_win64_portable_3.21_x64.zip` and unzip it into a tools folder (for example, next to the other tools in
`Claude Tools`). The program is `diec.exe`. **Download only from that official page** — the release carries
no published checksum and the binaries are built by the author, so the source page is the only assurance.

The download includes its own signature set, which is enough. (Advanced, optional: for fresher detections you
can clone `horsicq/Detect-It-Easy` and point `diec -D "<folder>\db"` at its `db` folder — but match the
signatures to the program version, or detections can misbehave.)

### How Claude uses it

As the **first step** when looking at any new game, before opening anything heavier:

```
diec -j "C:\path\to\Game.exe"
```

(`-j` gives machine-readable output; add `-d` for a deeper scan.) It reads the program and reports the
compiler, engine and any copy protection — and never changes the file. Reading the result:

- **A protection or packer is named** (SteamStub, Denuvo, SecuROM, VMProtect, Themida, Arxan, Enigma, or a
  packer like UPX): the program is wrapped. **Hands off the program itself** — Detect It Easy only tells you
  it's there; getting past it would mean stripping it, which your rules forbid. Work from live memory instead,
  the way the Ace Combat project does, or mod through the game's data and script files rather than its
  program.
- **Only an ordinary compiler or engine is named** (Microsoft Visual C/C++, Unity, Unreal, .NET, Go) with no
  protection line: the program is clean, and normal modding can proceed.

So it answers, safely and in a second, the gate question "is this game protected, and may I touch its
program?" — exactly the question the Ace Combat 7 copy protection (SteamStub) raised, and the one every new
game raises.
