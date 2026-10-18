# Putting REA and Ghidra on the home PC

> **Done on 2026-10-17** by a Claude Code session on the PC, though not exactly
> as written below. Everything went into the Claude Tools folder on the desktop
> (that desktop isn't synced to OneDrive, and REA accepted it), and Java and
> Node.js are portable copies inside that folder rather than installers. See the
> LOG entry for that date.

Written for the owner, assuming the PC runs Windows 10 or 11. Takes about half
an hour, most of it downloads. Nothing here changes BIOS or system settings,
and every piece can be uninstalled.

## Before you start: two catches

**1. Only Ghidra fits in a folder.** Ghidra is a folder you unzip. REA isn't:
it gets installed by a command, and lives inside Node.js (a program that runs
JavaScript code). Downloading REA's GitHub page as a zip and putting it in a
folder won't do anything on its own. Step 5 handles REA.

**2. The Claude in this cloud workspace can't see your PC.** I run on a
computer in the cloud, so files on your desktop are out of my reach. For
Claude to use these tools, Claude Code has to run on the PC itself (step 4).
That Claude can then read this guide from the playground repo.

**Where to put Ghidra:** use `C:\Tools` instead of the desktop. Windows often
syncs the desktop to OneDrive, and REA's Windows support refuses some kinds of
special folders, which likely includes synced ones. REA's own instructions use
`C:\tools` too. You can still keep a shortcut in your Claude Tools folder
(end of step 2).

## Step 1: Java 21

Ghidra runs on Java.

1. Go to **adoptium.net/temurin/releases**.
2. Pick **Windows**, **x64**, **JDK**, version **21 - LTS**, and download the
   file ending in **.msi**.
3. Open it and click **Next** through every screen. The default choices are
   fine.

## Step 2: Ghidra

1. Go to **github.com/NationalSecurityAgency/ghidra/releases**.
2. Find **Ghidra 12.1.4**. If a newer version is listed, still get 12.1.4:
   that's the one REA was tested with.
3. Under **Assets**, click the file named **ghidra_12.1.4_PUBLIC_** followed by
   a date, ending in **.zip** (it's several hundred MB). Don't pick the "Source
   code" files.
4. Make the folder: open File Explorer, click **This PC**, double-click
   **Local Disk (C:)**, right-click an empty spot, choose **New → Folder**, and
   name it `Tools`. If Windows asks for administrator permission, click
   **Continue**.
5. In your Downloads folder, right-click the Ghidra zip and choose
   **Extract All...**. Click **Browse**, pick the `Tools` folder on C:, then
   click **Extract**.
6. Open `C:\Tools`. You should find a folder called `ghidra_12.1.4_PUBLIC`.
   Inside is a file called **ghidraRun** (type "Windows Batch File"). If it
   landed one folder deeper, that's fine; just remember the actual location.
7. Double-click **ghidraRun** to test it. Windows may ask if you're sure you
   want to run it; click **Run**. Ghidra shows a user agreement (click
   **I Agree**), then a window titled "Ghidra: NO ACTIVE PROJECT". That means
   it works. You can close it.
8. Shortcut for your Claude Tools folder: hold the **right** mouse button on
   **ghidraRun**, drag it into the Claude Tools folder, let go, and choose
   **Create shortcuts here**.

If Ghidra says it can't find Java, restart the PC and try step 7 again.

## Step 3: Node.js

REA runs on Node.js.

1. Go to **nodejs.org** and download the **LTS** version for Windows (.msi).
2. Open it and click **Next** through. On the "Tools for Native Modules"
   screen, leave the box **unticked**. REA doesn't need those extras.

## Step 4: Claude Code on the PC

Install Claude Code on the PC if it isn't there already. The current steps
are at **code.claude.com**. Sign in with the same account you use here.

## Step 5: connect REA

Easiest way: open Claude Code on the PC and paste this:

> Please set up REA for Claude Code on this PC with `npx rea-agents setup`.
> Ghidra is in C:\Tools\ghidra_12.1.4_PUBLIC. Show me what setup will change
> before it changes anything, then check that REA can find Ghidra.

REA's setup always lists its planned changes and waits for a yes. Restart
Claude Code afterwards so it picks up the new tools.

## Step 6: a first test

A safe first try: ask Claude on the PC to write a tiny test program, then
examine it with REA and Ghidra and explain what it finds. That way there are
no questions about whose software it is.

## Ground rules

- Download only from the pages named above. REA warns that fake copies of it
  are out there. The real REA comes from github.com/morluto/rea, rea.tools, or
  the `rea-agents` package that setup downloads.
- Both tools only read programs. They don't change them.
- Keep them away from online games and anti-cheat. REA's rules forbid that,
  and it can get a game account banned.

## Removing everything

- Ghidra: delete the `C:\Tools\ghidra_12.1.4_PUBLIC` folder.
- REA: ask Claude on the PC to uninstall it. REA has its own uninstall
  command that undoes what setup added.
- Java and Node.js: **Settings → Apps → Installed apps**, find each one, and
  click **Uninstall**.
