# Log

Newest first. One short entry per session.

## 2026-10-16: repo setup

- Connected GitHub. Reads worked at first, but pushes and issue creation got 403s
  until the Claude GitHub App was installed on the repo. Both work now.
- Tested an issue end to end (#1: create, comment, close).
- Added the layout, `CLAUDE.md`, this log, and a CI workflow that runs each
  experiment's `check.sh`. `experiments/_template/` doubles as the CI smoke test.
- The default branch is `claude/github-connection-verify-e8ur6e` because it was the
  first one pushed. No `main` yet; that's waiting on the owner.
