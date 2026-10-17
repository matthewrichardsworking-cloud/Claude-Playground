# REA: a read-through

**Status:** read through the code and docs. Didn't run it (see "What I didn't do").

The owner pointed me at [REA, "Reverse Engineer Anything"](https://github.com/morluto/rea)
by morluto (MIT license, copyright 2026 morluto). I cloned it and read the
README, docs and a sample of the source at commit `19329e4` (17 Oct 2026).
Nothing from it was copied into this repo; these are my own notes.

## What it is

Reverse engineering means working out how a finished program works when you
don't have its source code, the human-readable instructions it was built from.
REA is a toolkit that lets an AI agent (Claude Code, Codex, Cursor and others)
do that. You point it at an app and ask something like "how does search work
in this?" It inspects the files, traces the relevant code, and hands back what
it found along with the evidence for each claim.

It plugs in through MCP (Model Context Protocol), the standard way to give an
AI agent extra tools. The same features also work as plain terminal commands.
Everything runs on your own computer; nothing gets uploaded except what the
agent itself sends to its AI provider.

## What it can look at

- **Regular programs** (Windows .exe, Mac and Linux apps). For the deep work it
  drives a separate decompiler, a program that turns machine code back into
  rough, readable code. It supports Ghidra (free, made by the NSA), Hopper and
  IDA (both paid). REA doesn't include any of them.
- **JavaScript and Electron apps** (Discord, Notion, VS Code and the like are
  Electron apps). This part needs no decompiler.
- **Websites**, through a Chrome-style browser: page structure, scripts,
  network traffic.
- **Android apps**, **.NET programs**, **Go and Rust programs**, **firmware**
  (the software inside devices like routers), **saved network captures**,
  **SQLite databases** and more. The README's table lists about 23 kinds.

## How it's built

- Written mostly in TypeScript, run with Node.js. About 335,000 lines of code,
  550 test files next to the code and another 1,350 or so files in `tests/`.
- Small "bridge" scripts run inside each decompiler (Python for Hopper, Java
  for Ghidra) and talk back to REA over a private connection locked with a
  random password for each session.
- Every result is an "Evidence" record that keeps four things apart: what was
  directly seen, what was worked out from that, what's a guess, and what's
  still unknown. The project's rules for contributors hammer on this.
- `npx rea-agents setup` adds REA to your agent. It shows the planned changes
  first, waits for a yes, and backs up the old settings.

## Things that stood out

- **It moves fast.** Version 0.1.0 came out on 12 July 2026, and version 6.5.0
  on 13 October, 36 releases in three months. Pull request numbers are past
  3,000. The README claims 300,000 GitHub stars; I didn't check that.
- **The docs are careful about what's been tested.** The changelog often spells
  out "tested on Linux with tool X version Y; Windows and macOS unverified."
- **Clever installer detail.** `install.sh` wraps the whole script in one pair
  of curly braces. If the download gets cut off partway, the shell sees an
  unfinished block and refuses to run any of it, instead of running half an
  installer. Cheap trick, worth remembering for our own scripts.
- **Lots of rules for AI contributors.** `AGENTS.md` is a full style guide for
  agents working on the code, and every PR needs a human to sign off that they
  reviewed it.
- **Copycat warning.** The README says to get REA only from the GitHub repo,
  rea.tools, or the `rea-agents` package on npm, because look-alike copies
  exist. I checked that the npm package points back at the real GitHub repo.

## Rules it sets

REA's `DISCLAIMER.md` says it's for security research, malware analysis,
learning, making programs work together, preserving old software, and checking
software you own or have permission to examine. It won't help with getting
around copy protection or license checks, game cheats, anti-cheat, or breaking
into systems. Paid tools like IDA and Hopper have to be properly licensed.

## Could the owner use it?

Possibly, but not from here. It would run on the owner's PC with Claude Code
installed there, plus Ghidra for normal Windows programs. Ghidra notes and
setup steps for the PC are in `experiments/2026-10-17-ghidra/`.

For the Ace Combat 7 co-op idea (`experiments/2026-10-17-ace-combat-7-coop/`),
REA isn't the right first tool. That game is built on Unreal Engine 4, and the
community's UE4SS tool is the usual way into those games. REA could help later
with a specific question about the game's code. Any of that has to stay offline
and away from public online matches, which is also REA's own rule.

## What I didn't do

- **Didn't run it.** I wrote a tiny fake Electron app (a notes search box) to
  try `analyze-javascript-application` on, but the session's safety check
  blocked running a package downloaded from the internet. If a later session
  gets the go-ahead, that's the easiest test: it needs only Node.js 22.19 or
  newer, no decompiler. The sample app is a few lines and quick to recreate.
- Didn't read the code in depth. This was a skim of the main docs plus a few
  source files (the Hopper bridge, the installer, the setup code).
