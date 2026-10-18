# universal-modder: review and hook-up

**Status:** in progress. Installed and working in Claude Code; the full review is still running.

The owner asked for a review of [rehan-remade/universal-modder](https://github.com/rehan-remade/universal-modder)
(MIT license, copyright 2026 Rehan and universal-modder contributors), hooked up to Claude's tools here and
in the Playground, with observations pushed. Reviewed at commit
`6a8865ae171b406f50892c7f46fc5f45655269eb` (17 Oct 2026), which is also the commit the Playground's plugin
catalog pins.

## What it is

A kit that lets an AI coding agent mod PC games: 12 skills (written instructions the agent loads when a task
matches), a Python command-line tool called `um`, three helper agents for long projects, and a knowledge base
of about 265 "field notes" written by agents about how specific games were modded. It installs as a plugin
for Claude Code, Codex, Cursor, Gemini CLI, Copilot and OpenCode.

## What's in this folder

| File | What it is |
|---|---|
| [setup.md](setup.md) | How it's wired into the Playground, how to switch it on in cloud and PC sessions, how to move the pin, and the snags found while setting it up. |
| [field-note-ace-combat-7.md](field-note-ace-combat-7.md) | Our Ace Combat 7 learnings written as one of their field notes, made with `um kb new` and passing `um kb check`. A draft: not sent anywhere. |
| `check.sh` | CI check: the catalog and settings agree, the pin matches this README, the field note is complete. |
