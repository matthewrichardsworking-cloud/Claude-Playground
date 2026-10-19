# Using universal-modder in the Playground

What's wired up, how to switch it on where it isn't on by itself, and how to move the pin later.

## What's set up in the repo

- **`.claude-plugin/marketplace.json`** (repo root) is a small plugin catalog, called a "marketplace" in Claude
  Code. It lists one plugin: universal-modder, pinned to commit
  `6a8865ae171b406f50892c7f46fc5f45655269eb` (17 Oct 2026), the commit reviewed in this folder. A change
  upstream can't reach our sessions until a session reads it and moves the pin.
- **`.claude/settings.json`** (repo root) tells Claude Code that this repo uses that catalog and wants the
  plugin turned on.
- The catalog has to sit at the root: `claude plugin marketplace add` takes a repo name but no subfolder.

What the plugin adds to a session: 12 skills (`universal-modder:mod-any-game` and others), 3 helper agents,
the `um` command, a start-up hook that puts `um` on the Bash tool's PATH, and a connection to fal.ai's image
and audio service. Claude Code puts the always-loaded cost at about 2,800 tokens per session.

## Cloud sessions (claude.ai/code and the phone app)

Claude Code's docs say a cloud session does **not** install plugins that a repo's settings turn on. So
`.claude/settings.json` does nothing there. Two ways round it:

**For every new cloud session (a one-time change by the owner).** Not tested from a fresh environment,
because a session can't change its own environment's settings. The same two commands were run in this
session's container, and a new Claude Code process started there loaded all 12 skills and `um`.

1. Open any Claude Code session in the browser or the Claude app.
2. Tap or click the cloud environment menu in the session's title bar, then **Edit**.
3. In **Setup script**, add these two lines and save:
   ```bash
   claude plugin marketplace add matthewrichardsworking-cloud/Claude-Playground || true
   claude plugin install universal-modder@claude-playground || true
   ```
   The `|| true` means a GitHub hiccup can't stop a session from starting; that session just won't have the
   plugin.
4. New sessions start with it. Sessions already open don't change.

**Inside one session, without the setting.** Run the same two commands (without `|| true`). The session's
own skill list doesn't change until the next session, but `um` and the skill files are usable straight away:

```bash
UM=~/.claude/plugins/cache/claude-playground/universal-modder/6a8865ae171b
$UM/bin/um kb search "unreal"          # the CLI
cat $UM/skills/mod-any-game/SKILL.md   # a skill, read as a file
```

## Sessions on the owner's PC (Claude desktop app)

Once this is merged into `main`, a session working in a clone of the Playground sees the plugin as "enabled
in project settings but isn't installed here". The simplest route is to ask that session: *"install the
universal-modder plugin from the Playground's catalog"*. By hand it's two lines typed into the session, then
a new session:

```
/plugin marketplace add matthewrichardsworking-cloud/Claude-Playground
/plugin install universal-modder@claude-playground
```

Things a PC session should know (from `LOG.md` and this review):

- **`um` needs `uv` or a Python with Pillow, numpy and PyYAML.** `bin\um.cmd` uses `uv` when it's on PATH,
  otherwise `python`. The log doesn't show `uv` on the PC, and the default `python` there is 3.15, for which
  PyYAML has no Windows package yet. Keep anything new out of AppData: inside the Store-app Claude, new files
  under AppData land in the app's private storage, invisible to other programs (see `LOG.md`). So either:
  - make a virtual environment in a normal folder on Python 3.13 (for example `Claude Tools\um-env`, next to
    `coop-anything-env`), install Pillow, numpy and PyYAML from wheels checked against PyPI's SHA-256 with
    `PIP_NO_CACHE_DIR=1`, and run `um` with that environment's python and `PYTHONPATH` set to the plugin
    folder; or
  - install `uv` from its official GitHub release (checksum checked, like the other tools in `Claude Tools`)
    and set `UV_PYTHON=3.13` and `UV_CACHE_DIR` to a folder outside AppData before running `um`.
- **The hook only helps the Bash tool.** It writes `um` onto the PATH through Claude Code's per-session
  environment file, which Bash commands read and PowerShell commands don't. PC sessions mostly use
  PowerShell, so call `bin\um.cmd` by its full path there (the plugin lives under
  `%USERPROFILE%\.claude\plugins\cache\claude-playground\universal-modder\6a8865ae171b\`).
- **The hook runs through `bash`**, which Claude Code on Windows gets from Git for Windows. The PC clones
  repos with git, so it's very likely there; if the hook errors, that's the first thing to check.
- **The fal connection shows as failed** unless a fal API key is set. That's expected. fal is a paid service;
  don't sign up for anything without the owner.

## Where the Playground's rules win

The toolkit has its own safety rules. Where they differ from the owner's, the owner's win. From the review
(details in [observations.md](observations.md)):

- **Ace Combat 7: no code dumps, even private ones.** universal-modder's `safety.md` allows "a private dump"
  of a DRM-wrapped exe. The AC7 addendum forbids saving whole code sections or an unscrambled exe to disk.
  Read single functions from live memory only, as the AC7 tools do.
- **Ace Combat 7: start the game only with `tools\start-copy.ps1`.** `um win launch --steam 502500`, or the
  copy's exe launched by path, starts the owner's real, modded install. Once the copy is running,
  `um win shot`, `drive` and `record` are fine.
- **`um win drive`: add `--no-retry` whenever the owner might be at the PC.** By default, when the owner has
  switched to another app, it taps Alt into that app and pulls the game back to the front.
- **`um win drive`: prefer keys to mouse clicks.** Clicks go to whatever window is under the cursor, which
  may not be the game; keep any click well inside the game window.
- **Ask before `um win setup`.** It downloads a daily ffmpeg build into `%LOCALAPPDATA%`, which the Store-app
  Claude hides. Point `UM_FFMPEG_WIN` at an ffmpeg kept in `Claude Tools` and recorded like the other tools.
- **Don't trust a PASS from `um publish check` on its own.** It misses many key-file types and most
  decompiled code. In this repo, `git diff` before every commit is still the check.
- **Don't run `um kb pr`.** Sharing a field note upstream needs the owner's OK, and that command can publish
  unpushed commits, staged files and photo metadata along with the note. Use a fresh fork with only the
  note.

## Turning it off

- One session or machine: `/plugin disable universal-modder@claude-playground`.
- For the whole repo: remove the `universal-modder@claude-playground` line from `.claude/settings.json`.
- Just the fal connection: toggle it off in `/mcp`. The skills stay.

## Moving the pin to a newer upstream commit

1. Clone upstream read-only and read what changed since the pinned commit
   (`git log --stat 6a8865ae..origin/main` and the diffs of `hooks/`, `bin/`, `um/`, `.mcp.json`, `agents/`).
   The hook and the `um` launcher run on every session, so those come first.
2. Put the new full 40-character commit in `.claude-plugin/marketplace.json` **and** in this folder's
   `README.md` (`check.sh` fails if they differ).
3. `claude plugin marketplace update claude-playground` then
   `claude plugin update universal-modder@claude-playground`, and start a new session.

## Gotchas found while setting this up

1. **Removing a test marketplace emptied the repo's settings.** `claude plugin marketplace remove
   claude-playground`, run from inside the repo folder, also deleted the catalog and plugin entries from the
   repo's own `.claude/settings.json`. Run plugin commands from outside the repo, or check `git diff`
   afterwards. `check.sh` would catch it in CI.
2. **Test sessions started with `claude -p` share the parent session's environment file.** They inherit
   `CLAUDE_CODE_SESSION_ID`, so the plugin's start-up hook writes into the parent's file, and the parent's
   Bash commands pick up that PATH. Start test runs with `env -u CLAUDE_CODE_SESSION_ID claude -p ...`.
3. **The hook keeps the first `um` path it writes.** It skips writing if any `universal-modder-path` line is
   already in the session's environment file, without checking that it points at the current install. Seen
   here after reinstalling from a different catalog (gotcha 2 made it visible). It could also leave a
   resumed session on an old copy after an update; that case wasn't tested.
4. **The first `um` run writes into the plugin folder**: a `.venv` and a fresh `uv.lock` (upstream ships no
   lock file, so the library versions are whatever is newest that day). The installed folder came to 113 MB.
