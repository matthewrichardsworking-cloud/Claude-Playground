# Working in this repo

This repo belongs to matthewrichardsworking-cloud and is set aside as Claude's own
space. Experiment freely: break things, try tools, start and abandon ideas. Nothing
here is load-bearing.

## Talking to the owner

The owner has no background in programming, IT, or computer hardware. Treat
them as a sharp person who's new to all of it, and assume they know only the
most basic ideas unless the list below says otherwise.

- Use plain language. If a technical word can't be avoided, say what it means
  in a few words the first time it comes up.
- Lead with what happened and what it means for them. Skip the internals
  unless they ask.
- Don't expect them to read code, error messages, or terminal output. Tell
  them what it says instead.
- When they need to do something themselves, give exact steps: which page,
  which button, what it's labeled on screen.
- They'll pick things up over time. When they mention something they know or
  have learned, add it to the list below so later sessions don't over-explain.

### What the owner already knows

- Updated their own PC's BIOS, and can find their way around the BIOS settings
  screens when told the exact on-screen labels (2026-10-17). Hardware words like
  "chassis" or "header" still need a few words of explanation. Photos of the
  screen are an easy way for them to show what they're seeing.

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
- Don't commit secrets, tokens, or personal data, even in a sandbox.

## Borrowing from other projects

Public repos can be cloned for reading (`add_repo` with read access). Before
copying anything in, check the project's license, keep its copyright notice,
and credit it in the experiment's README. No license means no copying.

## Standing permission from the owner

Given on 2026-10-16, in the owner's words:

> create main and merge freely. For future reference unless you think you're
> about to do something immoral or unethical or that could get me into legal
> trouble or is going to potentially brick my computer or phone, you do not
> need to ask permission for such things.

So for work in this repo, go ahead without asking. Stop and check with the
owner only for something unethical, something with legal risk, or something
that could damage their devices.

## End of a session

Add an entry to the top of `LOG.md`: date, what you did, how it went, and
anything the next session should know. Keep it to a few lines.
