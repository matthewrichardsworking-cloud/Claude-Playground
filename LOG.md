# Log

Newest first. One short entry per session.

## 2026-10-17: REA and Ghidra running on the PC, Co-op Anything added

- First session on the owner's PC itself (Claude Code in the Claude desktop
  app). Everything went into `%USERPROFILE%\Desktop\Claude Tools`: Ghidra
  12.1.4, Temurin JDK 21, Node.js 24.22.0, and REA 6.5.0 from npm. Java and Node
  are portable zips, each checked against its published SHA-256, so there are no
  installers and nothing on the system PATH.
- REA is registered with Claude Code (`~/.claude.json`, backup beside it) and its
  skill is installed. `rea doctor` passes every Ghidra check, and a real
  `rea analyze` of `whoami.exe` through Ghidra took 55 seconds. A PowerShell
  profile puts `rea` on PATH in new terminal windows.
- Snags: the desktop app is the Microsoft Store build, which redirects AppData,
  so session folders have very long real paths and git needs
  `-c core.longpaths=true` to clone there. REA can't register the desktop chat
  app from inside it. A git clone of REA lacks the Windows native parts; the npm
  package has them.
- Cloned Co-op Anything next to them; notes in
  `experiments/2026-10-17-coop-anything/`. Its MCP server needs Python, and the
  PC has no working Python right now (the old `python-env` lost its base install).

## 2026-10-17: Ghidra notes and home setup guide

- Same session as the REA entry below. The owner asked to add Ghidra too, and
  plans to put both tools in a "Claude Tools" folder on their desktop.
  Notes plus step-by-step PC setup are in `experiments/2026-10-17-ghidra/`.
- Newest Ghidra is 12.1.4, which is exactly what REA was tested with. Ghidra's
  repo is huge; a sparse clone (`--filter=blob:none --sparse`) of just the
  docs took seconds.
- Told the owner REA isn't a folder (it installs through Node.js), and that
  Claude Code has to run on the PC to use either tool. If a session starts on
  the PC, `home-setup.md` step 5 is the next thing to do.

## 2026-10-17: read through REA

- The owner asked for a quick study of [REA](https://github.com/morluto/rea), a
  reverse-engineering toolkit for AI agents (MIT). Notes are in
  `experiments/2026-10-17-rea-reverse-engineering-tool/`.
- Cloning a public repo for reading still works with no setup.
- The session's safety check blocked running it with `npx` (code downloaded
  from the internet). Reading was fine. To try it, get the owner's go-ahead
  first; the JavaScript analyzer is the easy test since it needs no decompiler.

## 2026-10-17: BIOS update, CPU fan error

- The owner updated their PC's BIOS and got "CPU Fan Error" at startup. Walked
  them through the fix using photos of the screen. Notes on the PC and the fix
  are in `experiments/2026-10-17-bios-cpu-fan-error/`.
- Cause: the cooler is on the AIO_PUMP header and CPU_FAN is empty, and the
  update reset the setting that had been hiding the warning. The fix was to set
  Q-Fan Control to Auto, then the CPU fan low limit to Ignore.
- Sending photos of the screen worked well. The owner followed the BIOS steps
  without trouble once each one named the exact on-screen label.
- A research workflow pulled ASUS's own manuals as PDFs with curl. ASUS's site
  works; the ROG forum, Corsair, and Reddit block automated reads.

## 2026-10-17: Ace Combat 7 co-op research

- The owner found [Co-op Anything](https://github.com/cranebeaker/coop-anything), a
  playbook for adding co-op to single-player games (MIT license). Public repos
  clone fine for reading with no setup.
- Researched Ace Combat 7 co-op: nobody has done it. Notes and sources are in
  `experiments/2026-10-17-ace-combat-7-coop/`. Nexus Mods blocks automated page
  reads, so mod details there came from search snippets only.
- Hands-on game modding can't happen in the cloud workspace (no games, no
  Windows). It would need Claude Code on the owner's PC.
- Tidied `CLAUDE.md`: moved a stray line and added rules for borrowing from
  other projects.

## 2026-10-16: repo setup

- Connected GitHub. Reads worked at first, but pushes and issue creation got 403s
  until the Claude GitHub App was installed on the repo. Both work now.
- Tested an issue end to end (#1: create, comment, close).
- Added the layout, `CLAUDE.md`, this log, and a CI workflow that runs each
  experiment's `check.sh`. `experiments/_template/` doubles as the CI smoke test.
- Created `main`. The owner gave standing permission to merge freely (recorded in
  `CLAUDE.md`). If `main` isn't the default branch yet, the owner has to switch it
  under Settings → General → Default branch; the tools here can't do that.
- First CI run passed.
- The owner asked for plain-language explanations; they're new to programming
  and IT. Added a "Talking to the owner" section to `CLAUDE.md`.
