# Builds the C++ UE4SS add-ons in this folder (HelloMod, CoopNetMod, CoopPadMod) and, with -Install,
# puts them into the game copy at C:\AC7-Coop-Game\ue4ss\Mods\<Name>\dlls\main.dll and
# lists them in mods.txt. Never touches the real install.
#
#   powershell -NoProfile -File cpp\build.ps1
#   powershell -NoProfile -File cpp\build.ps1 -Install
#   powershell -NoProfile -File cpp\build.ps1 -Mods CoopNetMod -Install
#
# How it works (details in cpp\README.md):
#   1. Loads the compiler: the portable MSVC 14.44 + Windows SDK in C:\AC7-Coop-Tools
#      (put there by tools\fetch-msvc-portable.py), or, if a normal Visual Studio Build
#      Tools install exists, its vcvars64.bat.
#   2. Makes an import library UE4SS.lib from the copy's own UE4SS.dll (cpp\make-implib.py
#      + lib.exe), so the add-ons link against exactly the UE4SS they will run in.
#   3. Compiles each add-on with the same language level, defines and flags UE4SS's own
#      CMake build uses for the LessEqual421__Shipping__Win64 configuration (the one the
#      copy's UE4SS.dll reports), against the headers of RE-UE4SS commit 48e7edfe.

param(
    [string[]]$Mods = @('HelloMod', 'CoopNetMod', 'CoopPadMod'),
    [string]$Tools = 'C:\AC7-Coop-Tools',
    [string]$Game = 'C:\AC7-Coop-Game',
    [switch]$Install
)

# Native tools (cl, link, lib) print to stderr, which PowerShell 5.1 would report as errors under 'Stop';
# so exit codes are checked by hand below instead.
$ErrorActionPreference = 'Continue'
$cpp = $PSScriptRoot
$ue = Join-Path $cpp 'RE-UE4SS'
$out = Join-Path $cpp 'build'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1. compiler -------------------------------------------------------------------------
if (Test-Path (Join-Path $Tools 'env.ps1')) {
    . (Join-Path $Tools 'env.ps1')
} else {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw "No compiler found: neither $Tools\env.ps1 nor a Visual Studio installation." }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    cmd /c "`"$vcvars`" >nul && set" | ForEach-Object { if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] } }
    "Visual Studio at $vs"
}
cmd /c 'cl 2>&1' | Select-Object -First 1

# 2. import library from the copy's UE4SS.dll -------------------------------------------
$dll = Join-Path $Game 'ue4ss\UE4SS.dll'
$def = Join-Path $out 'UE4SS.def'
$lib = Join-Path $out 'UE4SS.lib'
& python -I (Join-Path $cpp 'make-implib.py') $dll $def
if ($LASTEXITCODE) { throw 'make-implib.py failed' }
& lib /nologo /machine:x64 "/def:$def" "/out:$lib"
if ($LASTEXITCODE) { throw 'lib.exe failed' }
"import library: $lib"

# 3. compile and link each add-on ---------------------------------------------------------
$includes = @(
    (Join-Path $cpp 'shim'),                                   # stand-in GUI/GUITab.hpp (no ImGui / Unreal headers needed)
    (Join-Path $ue 'UE4SS\include'),
    (Join-Path $ue 'deps\first\String\include'),
    (Join-Path $ue 'deps\first\File\include'),
    (Join-Path $ue 'deps\first\DynamicOutput\include'),
    (Join-Path $ue 'deps\first\Helpers\include'),
    (Join-Path $ue 'deps\first\Input\include'),
    (Join-Path $ue 'deps\first\LuaMadeSimple\include'),
    (Join-Path $ue 'deps\first\LuaRaw\include'),
    (Join-Path $ue 'deps\first\Constructs\include'),
    (Join-Path $ue 'deps\first\Function\include'),
    (Join-Path $cpp 'third\fmt\include')
) | ForEach-Object { '/I'; $_ }   # '/I' and the folder as two words: the paths here contain spaces

# Same defines as UE4SS's CMake build for LessEqual421__Shipping__Win64, plus FMT_HEADER_ONLY
# (fmt is compiled into UE4SS.dll but not exported, so the add-on carries its own copy).
$defines = @(
    'UE_GAME', 'FNAME_ALIGN8', 'LESSEQUAL421', 'UE_BUILD_SHIPPING',
    'PLATFORM_WINDOWS', 'PLATFORM_MICROSOFT', 'OVERRIDE_PLATFORM_HEADER_NAME=Windows', 'UBT_COMPILED_PLATFORM=Win64',
    'HAS_INPUT', '_UNICODE', 'UNICODE', '_WIN32_WINNT=0x0A00', 'WINVER=0x0A00',
    '_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR', 'FMT_HEADER_ONLY', 'WIN32_LEAN_AND_MEAN', 'NOMINMAX',
    '_SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING', '_SILENCE_ALL_CXX17_DEPRECATION_WARNINGS'
) | ForEach-Object { "/D$_" }

# Same flags as UE4SS's msvc-compatible.cmake for Shipping: /O2 /MD (release, shared C runtime,
# which the C++ mods must share with UE4SS.dll), /Zi (symbols), /std:c++latest (C++23).
$cflags = @('/nologo', '/std:c++latest', '/EHsc', '/MD', '/O2', '/Zi', '/W3', '/wd4005', '/wd4251', '/wd4068',
            '/Zc:inline', '/Zc:strictStrings', '/Zc:preprocessor', '/Gy', '/utf-8', '/bigobj')
$ldflags = @('/nologo', '/DLL', '/MACHINE:X64', '/DEBUG:FULL', '/OPT:REF', '/OPT:ICF', '/INCREMENTAL:NO')

$built = @()
foreach ($mod in $Mods) {
    $src = Join-Path $cpp "$mod\dllmain.cpp"
    if (-not (Test-Path $src)) { throw "no source at $src" }
    $dir = Join-Path $out $mod
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    "`n=== $mod"
    & cl @cflags @defines @includes "/Fo$dir\dllmain.obj" "/Fd$dir\main.pdb" /c $src
    if ($LASTEXITCODE) { throw "compiling $mod failed" }
    & link @ldflags "/OUT:$dir\main.dll" "/PDB:$dir\main.pdb" "$dir\dllmain.obj" $lib kernel32.lib user32.lib ws2_32.lib
    if ($LASTEXITCODE) { throw "linking $mod failed" }
    $f = Get-Item "$dir\main.dll"
    "built $($f.FullName) ($($f.Length) bytes, $(Get-FileHash -Algorithm SHA256 $f | Select-Object -ExpandProperty Hash))"
    $built += $mod
}

# 4. install into the copy ------------------------------------------------------------
if ($Install) {
    if (Get-Process Ace7Game -ErrorAction SilentlyContinue) { throw 'The game copy is running; close it before installing (the DLLs are locked while loaded).' }
    $modsDir = Join-Path $Game 'ue4ss\Mods'
    $modsTxt = Join-Path $modsDir 'mods.txt'
    $text = Get-Content -Raw $modsTxt
    foreach ($mod in $built) {
        $dest = Join-Path $modsDir "$mod\dlls"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $out "$mod\main.dll") (Join-Path $dest 'main.dll') -Force
        Copy-Item (Join-Path $out "$mod\main.pdb") (Join-Path $dest 'main.pdb') -Force
        if ($text -notmatch "(?m)^$mod\s*:") {
            # before the "; Built-in keybinds" block, as UE4SS's installing guide says
            $text = $text -replace '(?m)^(; Built-in keybinds)', "$mod : 1`r`n`r`n`r`n`$1"
            "added '$mod : 1' to mods.txt"
        }
        "installed $mod -> $dest\main.dll"
    }
    [IO.File]::WriteAllText($modsTxt, $text)
}
