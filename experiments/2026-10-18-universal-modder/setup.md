# Using universal-modder in the Playground

What's wired up, how to switch it on where it isn't on by itself, and how to move the pin later.

## What's set up in the repo

- **`.claude-plugin/marketplace.json`** (repo root) is a small plugin catalog, called a "marketplace" in Claude
  Code. It lists one plugin: universal-modder, pinned to commit
  `6a8865ae171b406f50892c7f46fc5f45655269eb` (17 Oct 2026), the commit reviewed in this folder. A change
  upstream can't reach our sessions until a session reads it and moves the pin.
- **`.claude/settings.json`** (repo root) tells Claude Code that this repo uses that catalog and wants the
  plugin turned on.
- The catalog sits at the root because that's where the short command
  `claude plugin marketplace add <owner>/<repo>` looks. A subfolder would work too, but every settings entry
  would then need a `path` and the setup script a full file URL.
- Claude Code reads the catalog from GitHub's `main` branch, so changes to it count only once merged.

What the plugin adds to a session: 12 skills (`universal-modder:mod-any-game` and others), 3 helper agents,
the `um` command, a start-up hook that puts `um` on the Bash tool's PATH, and a connection to fal.ai's image
and audio service. Claude Code puts the always-loaded cost at about 2,800 tokens per session. Installed the
usual way, a plugin is on in every project on that machine or cloud environment, not just this repo.

## Cloud sessions (claude.ai/code and the phone app)

Claude Code's docs say a cloud session does **not** install plugins that a repo's settings turn on. So
`.claude/settings.json` does nothing there. Two ways round it:

**For new cloud sessions (a one-time change by the owner).** Not tested from a fresh environment, because a
session can't change its own environment's settings. In this session's container the same two commands,
reading the catalog from this branch before it was merged, installed the plugin, and a new Claude Code process
there loaded all 12 skills and `um`.

1. Open any Claude Code session in the browser or the Claude app.
2. Tap or click the small arrow after the session's title at the top, then **Edit cloud environment**.
3. In **Setup script**, add these two lines and save:
   ```bash
   claude plugin marketplace add matthewrichardsworking-cloud/Claude-Playground || true
   claude plugin install universal-modder@claude-playground || true
   ```
4. New sessions start with it. Sessions already open don't change.

How the setup script runs matters here. It doesn't run for every session: it runs once, and the result is
saved and reused by new sessions for about a week, or until the setup script is edited. So:

- The `|| true` stops a GitHub hiccup from breaking the environment, but if one happens during that run, new
  sessions go without the plugin until the next rebuild. To force a rebuild, make any small edit to the setup
  script (even adding a comment line) and save.
- The same applies after the pin moves: edit the setup script once so new sessions pick up the new version.

**Inside one session, without the setting.** Run the same two commands (without `|| true`). Typing
`/reload-plugins` should then load the skills into that session (not tested here). Either way, `um` and the
skill files work straight away. The next cloud session won't have any of it unless the setup-script lines are
in place.

```bash
UM=~/.claude/plugins/cache/claude-playground/universal-modder/6a8865ae171b
$UM/bin/um kb search "unreal"          # the CLI
cat $UM/skills/mod-any-game/SKILL.md   # a skill, read as a file
```

## Sessions on the owner's PC (Claude desktop app)

Once this is merged into `main`, a session working in a clone of the Playground sees the plugin as "enabled
in project settings but isn't installed here". It needs installing once per PC.

- **Easiest:** ask that session to *"install the universal-modder plugin from the Playground's catalog"*.
  The `claude` command isn't on PATH on the PC (see `LOG.md`), so the session runs `claude plugin marketplace
  add matthewrichardsworking-cloud/Claude-Playground` and `claude plugin install
  universal-modder@claude-playground` with the full path to `claude.exe`, from outside the repo folder.
- **By hand:** in the Claude app, click the **+** next to the message box, choose **Plugins**, then
  **Add plugin**, and pick universal-modder from the claude-playground catalog. (The `/plugin` command works
  only in the terminal version of Claude Code, not in the app.)
- Then start a new session.

Things a PC session should know (from `LOG.md` and this review):

- **`um` needs `uv` or a Python with Pillow, numpy and PyYAML.** `bin\um.cmd` uses `uv` when it's on PATH,
  otherwise `python`. The log doesn't show `uv` on the PC, and the default `python` there is 3.15, for which
  PyYAML has no Windows package yet. Keep new installs out of AppData: inside the Store-app Claude, new files
  under AppData land in the app's private storage, invisible to other programs (see `LOG.md`). So either:
  - make a virtual environment in a normal folder on Python 3.13 (for example `Claude Tools\um-env`, next to
    `coop-anything-env`), install Pillow, numpy and PyYAML from wheels checked against PyPI's SHA-256 with
    `PIP_NO_CACHE_DIR=1`, and run `um` with that environment's python and `PYTHONPATH` set to the plugin
    folder; or
  - install `uv` from its official GitHub release (checksum checked, like the other tools in `Claude Tools`)
    and set `UV_PYTHON=3.13` and `UV_CACHE_DIR` to a folder outside AppData before running `um`.
- **The hook only helps the Bash tool.** It adds `um` to the PATH through Claude Code's per-session
  environment file, as a Bash `export` line with a Unix-style path, which PowerShell commands can't use. PC
  sessions mostly use PowerShell, so call `bin\um.cmd` by its full path there (the plugin lives under
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
  Claude hides. Instead, point `UM_FFMPEG_WIN` at an ffmpeg kept in `Claude Tools` and recorded like the other
  tools; it must be a build with the gfxcapture filter (`ffmpeg -filters` lists it), which um only checks
  when it records. Every `um win` command still copies its small PowerShell helpers into
  `%LOCALAPPDATA%\universal-modder`; that can't be avoided.
- **Don't trust a PASS from `um publish check` on its own.** It misses many key-file types and most
  decompiled code. In this repo, `git diff` before every commit is still the check.
- **Don't run `um kb pr`.** Sharing a field note upstream needs the owner's OK, and that command can publish
  unpushed commits, staged files and photo metadata along with the note. Use a fresh fork with only the
  note.

## Turning it off

- **On one PC or in one cloud environment:** in the Claude app, **+** > **Plugins** > **Manage plugins**.
  From a terminal or a session, `claude plugin disable universal-modder@claude-playground --scope user`, run
  from outside the repo folder. For cloud sessions, also remove the two setup-script lines.
- **For this repo, everywhere:** in `.claude/settings.json` change `"universal-modder@claude-playground": true`
  to `false`. A repo setting overrides the machine-wide one. `check.sh` accepts either value; it only fails if
  the entry disappears.
- **Just the fal connection:** turn it off in the session's MCP server list (`/mcp`). The skills stay.

## Moving the pin to a newer upstream commit

1. Clone upstream read-only and read what changed since the pinned commit
   (`git log --stat 6a8865ae..origin/main` and the diffs of `hooks/`, `bin/`, `um/`, `.mcp.json`, `agents/`).
   The hook and the `um` launcher run on every session, so those come first.
2. Put the new full 40-character commit in `.claude-plugin/marketplace.json` **and** in this folder's
   `README.md` (`check.sh` fails if they differ), and merge that into `main`.
3. On each PC: `claude plugin marketplace update claude-playground`, then
   `claude plugin update universal-modder@claude-playground`, then a new session. For cloud sessions, make a
   small edit to the setup script so the environment rebuilds; otherwise new sessions keep the old version for
   up to about a week.

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
