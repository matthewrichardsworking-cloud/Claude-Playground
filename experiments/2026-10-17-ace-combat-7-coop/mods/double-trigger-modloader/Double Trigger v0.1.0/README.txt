Double Trigger v0.1.0 (0.1.0+6240b21f), packaged for AC7 Mod Loader
====================================================================

Two-player online co-op for ACE COMBAT 7 (Steam), by layer10-love (Mira), MIT licence.
Source and release: https://github.com/layer10-love/double-trigger/releases/tag/v0.1.0

Contents:
  dinput8.dll              the mod, unchanged from the release (SHA-256
                           97fdb3b80ca2a310fd7df67e5259d6c04dea280f531a595ab3c062bbd03221d7)
  LICENSE                  the mod's MIT licence
  THIRD_PARTY_NOTICES.md   MinHook and Dear ImGui licences

AC7 Mod Loader (build of 18 Oct 2026 or later) places dinput8.dll next to Ace7Game.exe and
removes it again when the mod is turned off or Vanilla mode is on. Older loader builds only
place .pak files and Game\Content files, and would install nothing from this folder.

In the game: F5 opens the co-op panel. The game's own online multiplayer is off while the mod
is installed. The mod writes ac7mp.ini, ac7mp.log and, after a crash, ac7mp_crash_*.dmp next
to Ace7Game.exe.
