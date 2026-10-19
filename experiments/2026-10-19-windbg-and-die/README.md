# WinDbg and Detect It Easy: two tools for Claude on the PC

**Status:** studied and wired in. The WinDbg server is pinned in the Playground's plugin catalog; both still
need a one-time install on the PC. Read-only study in the sandbox; nothing was run.

These are the first two picks from the repo shortlist (`experiments/2026-10-19-repo-shortlist/`). Both run on
your Windows PC, not in a cloud session, so "wiring in" means: pin the catalog entry, deny the risky bits, and
write the PC setup steps below.

## What they are, in plain terms

- **WinDbg for Claude** (`svnscha/mcp-windbg`, MIT): a small bridge that lets Claude drive Microsoft's own
  Windows debugger. When the game, or one of our mods, crashes and leaves a crash file, Claude can open it and
  say what broke — and, with symbols, which line of our own code. It can also attach to a running program to
  step through it. Pinned to commit `48e4350d57c44a38068be4f64e89a0fe60fe5c04` (10 Oct 2026); it runs the
  debugger package `mcp-windbg@1.5.1`.
- **Detect It Easy** (`horsicq/Detect-It-Easy`, MIT): a tiny tool that looks at a game's program and names its
  copy protection and the compiler it was built with — in about a second, and **only by reading it, never
  changing it**. That tells Claude right away when a game is wrapped in protection it must not touch, which
  guards your no-DRM-stripping rule on every new game. Studied at release 3.21.

## What was done here

- Read both projects' source in the sandbox and checked their licences (both MIT), their latest state, and —
  for the WinDbg bridge — every command it exposes and how risky each one is.
- Added the WinDbg bridge to `.claude-plugin/marketplace.json`, pinned to the reviewed commit, using the
  `git-subdir` source type (its plugin lives in a subfolder of its repo). Confirmed in this container that the
  pinned entry installs and places its server config correctly.
- Switched it on for the repo in `.claude/settings.json`, and **denied its three kernel-debugging commands
  there**, repo-wide, because kernel debugging can freeze or destabilise a PC and needs the machine booted
  into a special mode — the one line your standing permission always keeps.
- Could **not** confirm the debugger server actually connects: that needs Windows and WinDbg, which the cloud
  sandbox doesn't have. That check happens on the PC (see setup.md).

## Files

| File | What it is |
|---|---|
| [setup.md](setup.md) | The one-time PC install for both tools, the safety guardrails, and how Claude should use them. |
| `check.sh` | CI check: the WinDbg pin, the repo settings and the kernel-tool deny-list all agree with this folder. |

## The short version of the guardrails

- **WinDbg's kernel commands are off** (denied in the repo settings): they carry the risk of freezing the PC.
- **Reading crash files is the safe, main use** and stays on.
- **Live debugging of our own mods is allowed**, with one rule: never dump or copy a copy-protected game's
  memory to disk — that would write out its unprotected code, which your rules forbid. Full detail in
  setup.md.
- **Detect It Easy only ever reports.** It has no feature that strips protection, and we only run its
  identify commands.
