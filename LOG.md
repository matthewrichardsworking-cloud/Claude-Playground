# Log

Newest first. One short entry per session.

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
