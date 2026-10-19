# universal-modder: review and hook-up

**Status:** worked. Installed in Claude Code, reviewed in depth, and wired into the Playground.

The owner asked for a review of [rehan-remade/universal-modder](https://github.com/rehan-remade/universal-modder),
hooked up to Claude's tools here and in the Playground, with observations pushed. Reviewed at commit
`6a8865ae171b406f50892c7f46fc5f45655269eb` (17 Oct 2026). That is also the version the Playground's settings
pin, so a change upstream can't reach our sessions until a session has read it.

## What it is

A kit that teaches AI coding agents (Claude Code, Codex, Cursor and others) to mod PC games. It has four
parts:

- **12 skills:** written instructions an agent picks up when a task matches, such as "mod any game", "make
  game art", "record a showcase video".
- **A command-line tool called `um`:** finds installed games and works out their engine, backs up saves,
  makes art through a paid service called fal, drives the mouse and keyboard on Windows, edits videos, and
  checks a mod before release.
- **A knowledge base** of 265 "field notes" in which agents wrote down how a specific game was modded: the
  exact versions, what worked, and the traps.
- **Three helper agents** for mods that take days.

## What I did

- Installed it in this session's Claude Code and checked that a new session gets all 12 skills, the 3
  helpers and `um`. Their own test suite passes here (163 passed, 1 skipped).
- Ran a ten-part review with 36 agents: each part read and tested by one agent, and every problem of medium
  or higher checked by a second agent trying to prove it wrong. Then three follow-ups on parts nobody had
  covered.
- Wired it into the Playground, pinned to the reviewed version (see "How it's hooked up").
- Wrote our Ace Combat 7 lessons as one of their field notes, using their own tool. It passes their checker.
  It's a draft and hasn't been sent anywhere.

## What I found

**The good:** it's careful and honest work. The main instructions are sound, every command they mention
exists, and the knowledge base is the real prize: hundreds of write-ups with the exact versions that worked
and the traps hit along the way. Several habits are worth copying here (listed in
[observations.md](observations.md)).

**The problems** (153 in all, 73 confirmed by a second agent; full list in observations.md):

1. **Its safety checks catch less than its docs claim.** The checker meant to stop you sharing game files,
   passwords or copied game code lets many of them through and still says "PASS". The command that shares a
   field note on GitHub can share far more than the note: unrelated unsaved work, and photo location data.
2. **"Input only reaches the game" has holes on Windows.** Keyboard input is guarded, but mouse clicks can
   land in another window, and by default the tool pulls the game back to the front if you switch away.
   This is from reading the code; nothing was run on Windows.
3. **The rules are written in several places, in different words,** and a few versions contradict each
   other.

**For us:** its Unreal Engine guide points the right way, but on Ace Combat 7 it would have been wrong
about the save location, the data-file format, reading the game's program on disk, and what C++ add-ons
cost. In two places it would steer a session into breaking your AC7 rules: it allows a private dump of a
copy-protected program, and its launcher starts your real game instead of the copy. The setup notes say
your rules win.

## How it's hooked up

- **Sessions on your PC** that work in the Playground will see it listed as switched on but not installed
  yet. Ask that session to install it, or type the two lines in [setup.md](setup.md).
- **Cloud sessions** (browser and phone) ignore a repo's plugin settings; that's how Claude Code works. To
  have it in every new cloud session, add two lines to the environment's setup script (exact steps in
  setup.md). Optional: any session can also install it for itself when needed.
- **To turn it off:** remove one line from `.claude/settings.json`, or see setup.md.

## Files

| File | What it is |
|---|---|
| [setup.md](setup.md) | How it's wired in, how to switch it on for cloud and PC sessions, where the Playground's rules override the toolkit's, how to move the pin, and the snags found while setting it up. |
| [observations.md](observations.md) | The review: method, verdict, what to borrow, the problems that matter, what it means for the Playground, and a table of all 153 findings with file and line. |
| [field-note-ace-combat-7.md](field-note-ace-combat-7.md) | Our Ace Combat 7 lessons as one of their field notes (made with `um kb new`, passes `um kb check`). A draft; not sent anywhere. |
| `check.sh` | CI check: the catalog and settings agree, the pin matches this README, the field note is complete. |
| `../../.claude-plugin/marketplace.json`, `../../.claude/settings.json` | The Playground's plugin catalog (one entry: universal-modder at the pinned commit) and the setting that switches it on. |

## Credits

universal-modder is MIT-licensed, copyright (c) 2026 Rehan and universal-modder contributors. Nothing from it
is copied into this repo except the field-note template's headings and header keys, which our draft follows
(scaffolded by its `um kb new`). The review's findings are our own reading of its code.

## Notes for next time

- Read [setup.md](setup.md) before using `um` on the PC, especially "Where the Playground's rules win".
- Before moving the pin, read the upstream changes to `hooks/`, `bin/`, `um/`, `.mcp.json` and `agents/`
  first: those run in every session.
- If the owner wants the problems reported upstream, their `SECURITY.md` asks for private reports for the
  security-related ones. Nothing has been sent.
- On a 4-core container a workflow runs two agents at a time; a ten-reader review with checking took about
  two hours. Checking findings in one batch per area, rather than one agent per finding, made it feasible.
