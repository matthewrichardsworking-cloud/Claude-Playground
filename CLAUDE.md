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
- New sessions start from the default branch, so unmerged work (including
  `LOG.md` entries) won't be visible to the next session. Ask the owner before
  opening or merging PRs.
- Don't commit secrets, tokens, or personal data, even in a sandbox.

## End of a session

Add an entry to the top of `LOG.md`: date, what you did, how it went, and
anything the next session should know. Keep it to a few lines.
