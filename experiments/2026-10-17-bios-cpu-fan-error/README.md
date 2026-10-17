# CPU Fan Error after a BIOS update

**Status:** fixed in the BIOS. As of these notes, the owner hadn't yet confirmed that Windows starts.

The owner updated the BIOS on their PC and then got "CPU Fan Error! Press F1 to
Run SETUP" at startup. We fixed it together over chat using photos of the screen.

## The PC

- ASUS TUF GAMING X570-PLUS (WI-FI), now on BIOS 5021 (2024-11-04). That's the
  newest stable version. A 5044 beta from 2026-02 also exists.
- AMD Ryzen 9 3900X.
- 2 x 16 GB A-DATA DDR4 in slots A2 and B2, running at 2666 because D.O.C.P.
  is off. We don't know what speed the kit is rated for.
- Windows on a Maxtor Z1 960 GB SATA SSD, listed as "Windows Boot Manager".
- The cooler is plugged into the AIO_PUMP header and reads about 5,465 RPM.
  Nothing is plugged into CPU_FAN, CPU_OPT, or CHA_FAN1-3, so all of those read
  N/A. It's probably a liquid (AIO) cooler with its fans powered some other way,
  but we haven't confirmed the cooler model.
- A SanDisk Extreme portable SSD shows up twice at startup, once as the drive
  and once as "SES Device". It's one drive, probably the one that carried the
  BIOS file.

## What was wrong

The board only checks the CPU_FAN header for the CPU fan warning, and nothing
is plugged into it. Before the update the warning was presumably switched off.
The update reset every setting to its default, so the warning came back. The
cooler itself was fine: the owner saw the fan spinning, and the CPU held steady
at 61°C in the BIOS.

## The fix

In Advanced Mode (F7): Monitor > Q-Fan Configuration.

1. CPU Q-Fan Control: Disabled -> Auto. While this is Disabled, the low-limit
   item below it is hidden.
2. CPU Fan Speed Lower Limit: 200 RPM -> Ignore.
3. The owner also set Chassis Fan 1-3 Speed Low Limit to Ignore. That does no
   harm because nothing is plugged into those headers.

Then F10 > OK.

## Notes for next time

- If the owner wants faster memory, turn D.O.C.P. back on. It's in the EZ Mode
  dropdown, or under Ai Tweaker > Ai Overclock Tuner. Change one thing at a
  time.
- A BitLocker recovery prompt is possible after this update, because BIOS 5003
  changed the fTPM. The key is at https://aka.ms/myrecoverykey. If an fTPM
  "Press Y / Press N" screen ever appears, N keeps the existing TPM keys.
- One forum report on this same board says Windows stopped starting on its own
  after going to 5021 and needed Boot Override. That fits the boot order being
  reset. Here, Windows Boot Manager was already first in line.
- Turning the warning off means the board won't complain if a fan dies. It
  wasn't watching the pump header anyway. The 3900X slows itself down at 95°C
  and shuts off if it keeps heating up.
- The "proper" wiring, per the ASUS manual, is the pump on AIO_PUMP and the
  radiator fans on CPU_FAN. Only revisit that if the owner wants the board to
  control the fans.

## Sources

- ASUS TUF GAMING X570-PLUS (WI-FI) user manual E15236: fan header names,
  locations, and default speeds (AIO_PUMP runs at full speed).
- ASUS PRIME/PRO/TUF GAMING X570 Series BIOS manual E15829: Monitor and Q-Fan
  menu items, and the fact that the low limit only shows when Q-Fan Control
  isn't Disabled.
- ASUS FAQ 1006064 (CPU Fan Error), and the ASUS BIOS download page for this
  board (5021 and 5044 release notes, and 5003's BitLocker note).
- Microsoft's list of BitLocker recovery triggers, which includes firmware
  upgrades.
