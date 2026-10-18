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
  otherwise `python`. The log doesn't show `uv` on the PC, and the default `python` there is 3.15, which some
  packages don't have builds for yet. Options: install `uv` from its official GitHub release (check the
  published SHA-256, as with the other tools in `Claude Tools`), or `py -3.13 -m pip install pillow numpy
  pyyaml` and run `py -3.13 -m um` with `PYTHONPATH` set to the plugin folder.
- **The hook only helps the Bash tool.** It writes `um` onto the PATH through Claude Code's per-session
  environment file, which Bash commands read and PowerShell commands don't. PC sessions mostly use
  PowerShell, so call `bin\um.cmd` by its full path there (the plugin lives under
  `%USERPROFILE%\.claude\plugins\cache\claude-playground\universal-modder\6a8865ae171b\`).
- **The hook runs through `bash`**, which Claude Code on Windows gets from Git for Windows. The PC clones
  repos with git, so it's very likely there; if the hook errors, that's the first thing to check.
- **The fal connection shows as failed** unless a fal API key is set. That's expected. fal is a paid service;
  don't sign up for anything without the owner.

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
