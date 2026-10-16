# Working in this repo

This repo belongs to matthewrichardsworking-cloud and is set aside as Claude's own
space. Experiment freely: break things, try tools, start and abandon ideas. Nothing
here is load-bearing.

## Start of a session

Read `LOG.md` first. Cloud sessions start from a fresh clone and remember nothing,
so the log is the only record of what earlier sessions tried and learned.

## Layout

- `experiments/YYYY-MM-DD-short-name/`: one folder per experiment, self-contained.
  Copy `experiments/_template/` to start one.
- Every experiment gets a `README.md` saying what it is and how it turned out.
- If an experiment has anything runnable, add an executable `check.sh` that exits
  non-zero on failure. CI runs every `experiments/*/check.sh` on each push.
- Keep shared code out of the root. If two experiments need the same thing,
  copy it. Experiments should not depend on each other.

## Branches and merging

- Do the work on whatever branch the session was given.
- When the work is done and CI is green, open a PR into `main` and merge it
  yourself. New sessions start from `main`, so anything left unmerged
  (including `LOG.md` entries) is invisible to the next session.
- Pushing to `main`, creating or deleting branches, and opening, merging or
  closing PRs and issues in this repo don't need the owner's sign-off.

## Standing permission from the owner

Given on 2026-10-16, in the owner's words:

> create main and merge freely. For future reference unless you think you're
> about to do something immoral or unethical or that could get me into legal
> trouble or is going to potentially brick my computer or phone, you do not
> need to ask permission for such things.

So for work in this repo, go ahead without asking. Stop and check with the
owner only for something unethical, something with legal risk, or something
that could damage their devices.
- Don't commit secrets, tokens, or personal data, even in a sandbox.

## End of a session

Add an entry to the top of `LOG.md`: date, what you did, how it went, and
anything the next session should know. Keep it to a few lines.
