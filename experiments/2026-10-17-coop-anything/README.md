# Co-op Anything: on the PC

**Status:** on the owner's PC next to REA and Ghidra, with its MCP server
connected to Claude Code. Not used on a game yet.

[Co-op Anything](https://github.com/cranebeaker/coop-anything) by cranebeaker
(MIT license, copyright 2026 cranebeaker and contributors) is a guidebook for AI
agents that want to turn a single-player game into a co-op one. The Ace Combat 7
research (`experiments/2026-10-17-ace-combat-7-coop/`) already used it as a
guide. This entry is about the project itself and getting it onto the PC. Notes
are from commit `3a45f4b`. Nothing from it was copied into this repo.

## What it is

- **A playbook:** how-to pages for each stage of a co-op project: working out
  what's already been tried, looking inside the game, building, testing with
  bots, and packaging it so friends can install it with one click.
- **Two paths.** Path 1 finishes a co-op mod someone else started and abandoned.
  Path 2 builds co-op from nothing. Most well-loved games are on path 1.
- **A directory of 230+ games** (`DIRECTORY.md`) listing existing co-op mods and
  the gaps, with how well each one was actually tested.
- **12 skills for Claude Code** in `.claude/skills` (the same ones are in
  `.agents/skills` for other agents).
- **A small MCP server** (`tools/mcp/coop_mcp.py`). MCP is the standard way to
  give an AI agent extra tools. This one lets an agent search the directory,
  guess a game's engine from its install folder, read the playbook, and check a
  contribution before it's sent. It's about 320 lines of Python. It uses only
  Python's built-in parts plus PyYAML, a small add-on for reading YAML files. I
  searched it for network and program-launching calls and found none.
- **It pairs with REA.** Its README puts it this way: Co-op Anything knows what
  to do, REA looks inside the game. For games with no source code, its tool
  tables list REA and Ghidra, both now set up on the PC.

## Where it is on the PC

`%USERPROFILE%\Desktop\Claude Tools\coop-anything`, as a git clone, so
`git pull` in that folder updates it. REA, Ghidra 12.1.4, Java 21 and Node.js 24
are in the same Claude Tools folder, and REA is already hooked into Claude Code
there. See the LOG entry for 2026-10-17.

## Things that stood out

- **Brand new.** Created 16 Oct 2026, 175 stars when I checked.
- **Sensible rules for agents.** Ask the owner before installing anything or
  using their accounts. Never touch the real game install or saves; work on a
  copy. Downloads only from official sources, checked by checksum. No
  anti-cheat, nothing that cheats in other people's online games, no game files
  in pull requests.
- **Compiled leftovers in the repo.** Two `.pyc` files (Python's machine-made
  cache of its scripts) are checked into git under `__pycache__`. Projects
  normally leave these out, so it's probably an accident. They can't be read the
  way the source can, so delete them before running the server. (Done on the
  PC.)
- **Contributions go out under the owner's GitHub account,** as draft pull
  requests the owner reviews first.

## The MCP server is connected

- **Its own Python:** a virtual environment (a private Python setup for one
  tool) at `%USERPROFILE%\Desktop\Claude Tools\coop-anything-env`, on Python
  3.13 with PyYAML 6.0.3. It's 3.13 rather than 3.15 because PyYAML has no
  ready-made Windows package for 3.15 yet. The PyYAML install was pinned to the
  official package's SHA-256.
- **Registered for every Claude Code session** under the name `coop-anything`,
  with `claude mcp add --scope user`, the same level as REA. Config backup made
  first: `%USERPROFILE%\.claude.json.coop-anything.backup`.
- **Checked:** `claude mcp list` shows both `rea` and `coop-anything` as
  connected. A direct query loaded all 244 directory entries (that part needs
  PyYAML) and found 5 Deus Ex co-op projects.
- **Its eight tools:** `search_directory`, `detect_engine`, `game_identity`,
  `list_docs`, `read_playbook`, `get_skill`, `get_game`, `validate_entry`. They
  appear in sessions started after the registration.
- **Remove it** with `claude mcp remove --scope user coop-anything`.

## Not done yet

- **Opening Claude Code inside the coop-anything folder** would load its skills,
  and Claude Code would also offer the folder's own `.mcp.json` server. That
  one runs plain `python` (3.15, no PyYAML), so its directory search would
  fail. Decline it; the user-level server already covers it.
- **No game picked yet.** Ace Combat 7 is the only one researched so far, and
  for an Unreal Engine 4 game like that, Co-op Anything's first stop is UE4SS,
  not REA.
