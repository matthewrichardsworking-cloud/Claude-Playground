# Builds the stand-in gamepad library cpp\CoopPad\xinput1_3.dll (a plain DLL, no UE4SS
# headers needed) with the portable MSVC in C:\AC7-Coop-Tools and, with -Install, copies
# it into the game copy's own folder (C:\AC7-Coop-Game\xinput1_3.dll), where the copy
# loads it instead of Windows' own. Never touches the real install.
#
#   powershell -NoProfile -File cpp\CoopPad\build.ps1
#   powershell -NoProfile -File cpp\CoopPad\build.ps1 -Install
#
# To remove it again: delete C:\AC7-Coop-Game\xinput1_3.dll (the copy then uses Windows'
# own library, as before).

param(
    [string]$Tools = 'C:\AC7-Coop-Tools',
    [string]$Game = 'C:\AC7-Coop-Game',
    [switch]$Install
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$out = Join-Path (Split-Path -Parent $here) 'build\CoopPad'
New-Item -ItemType Directory -Force -Path $out | Out-Null
. (Join-Path $Tools 'env.ps1')

& cl /nologo /std:c++20 /EHsc /MT /O2 /Zi /W3 /utf-8 /DUNICODE /D_UNICODE /DWIN32_LEAN_AND_MEAN `
    "/Fo$out\xinput_proxy.obj" "/Fd$out\xinput1_3.pdb" /c (Join-Path $here 'xinput_proxy.cpp')
if ($LASTEXITCODE) { throw 'compiling failed' }
& link /nologo /DLL /MACHINE:X64 /DEBUG:FULL /OPT:REF /OPT:ICF /INCREMENTAL:NO `
    "/DEF:$(Join-Path $here 'xinput1_3.def')" "/OUT:$out\xinput1_3.dll" "/PDB:$out\xinput1_3.pdb" `
    "$out\xinput_proxy.obj" kernel32.lib user32.lib
if ($LASTEXITCODE) { throw 'linking failed' }
$f = Get-Item "$out\xinput1_3.dll"
"built $($f.FullName) ($($f.Length) bytes, SHA-256 $((Get-FileHash -Algorithm SHA256 $f).Hash))"

if ($Install) {
    if (Get-Process Ace7Game -ErrorAction SilentlyContinue) { throw 'The game copy is running; close it first (the DLL is locked while loaded).' }
    Copy-Item $f.FullName (Join-Path $Game 'xinput1_3.dll') -Force
    "installed -> $(Join-Path $Game 'xinput1_3.dll')"
}
