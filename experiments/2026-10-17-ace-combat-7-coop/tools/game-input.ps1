# Lets Claude "play" the Ace Combat 7 test copy without the owner at the keyboard:
# it finds the game's window, brings it to the front, presses keys in it and takes
# screenshots of it, so menus can be read and driven from a session.
#
# Only sends key presses to the game window of the COPY (process Ace7Game started from
# C:\AC7-Coop-Game). Does not touch the real install or anything else.
#
#   powershell -NoProfile -File tools\game-input.ps1 -Info
#       list the game windows (process id, start time, title, position)
#   powershell -NoProfile -File tools\game-input.ps1 -Screenshot C:\path\shot.png
#       picture of the game window (add -FullScreen for the whole screen)
#   powershell -NoProfile -File tools\game-input.ps1 -Keys Enter
#   powershell -NoProfile -File tools\game-input.ps1 -Keys Down,Down,Enter -WaitMs 3000 -Screenshot C:\path\after.png
#       press keys one after another (held 80 ms, 400 ms apart), wait 3 s, then take a picture
#   powershell -NoProfile -File tools\game-input.ps1 -ProcessId 1234 -Keys Escape
#       when two copies run, pick one by process id (default: the one started first)
#   powershell -NoProfile -File tools\game-input.ps1 -Keys Ctrl+P
#       key combinations: the names before the last "+" are held while the last one is
#       pressed (Ctrl+P reloads UE4SS scripts, Ctrl+J writes the UE4SS object dump)
#
# Key names: Enter, Escape, Space, Tab, Backspace, Up, Down, Left, Right, Home, End,
# PageUp, PageDown, Insert, Delete, F1..F12, A..Z, 0..9, Shift, Ctrl, Alt.

param(
    [string[]]$Keys = @(),
    [int]$HoldMs = 80,
    [int]$GapMs = 400,
    [string]$Screenshot = '',
    [int]$WaitMs = 0,
    [switch]$FullScreen,
    [int]$ProcessId = 0,
    [switch]$Info
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Win -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
public struct RECT { public int Left, Top, Right, Bottom; }
public struct POINT { public int X, Y; }
'@
[void][Win.Native]::SetProcessDPIAware()

$vk = @{
    Enter = 0x0D; Escape = 0x1B; Esc = 0x1B; Space = 0x20; Tab = 0x09; Backspace = 0x08
    Up = 0x26; Down = 0x28; Left = 0x25; Right = 0x27
    Home = 0x24; End = 0x23; PageUp = 0x21; PageDown = 0x22; Insert = 0x2D; Delete = 0x2E
    Shift = 0x10; Ctrl = 0x11; Alt = 0x12
}
1..12 | ForEach-Object { $vk["F$_"] = 0x6F + $_ }
65..90 | ForEach-Object { $vk[[string][char]$_] = $_ }   # A..Z
48..57 | ForEach-Object { $vk[[string][char]$_] = $_ }   # 0..9
$extended = @(0x26, 0x28, 0x25, 0x27, 0x24, 0x23, 0x21, 0x22, 0x2D, 0x2E)

function Get-GameWindows {
    $list = New-Object System.Collections.ArrayList
    $procs = @{}
    Get-Process Ace7Game -ErrorAction SilentlyContinue | ForEach-Object { $procs[[uint32]$_.Id] = $_ }
    if ($procs.Count -eq 0) { return @() }
    $cb = [Win.Native+EnumWindowsProc] {
        param($h, $l)
        $wpid = [uint32]0
        [void][Win.Native]::GetWindowThreadProcessId($h, [ref]$wpid)
        if ($procs.ContainsKey($wpid) -and [Win.Native]::IsWindowVisible($h)) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][Win.Native]::GetWindowText($h, $sb, 512)
            $title = $sb.ToString()
            if ($title -like '*ACE COMBAT*') {
                $r = New-Object Win.Native+RECT
                [void][Win.Native]::GetWindowRect($h, [ref]$r)
                [void]$list.Add([pscustomobject]@{
                    Handle = $h; ProcessId = [int]$wpid; Started = $procs[$wpid].StartTime; Title = $title
                    Left = $r.Left; Top = $r.Top; Width = $r.Right - $r.Left; Height = $r.Bottom - $r.Top
                    Foreground = ([Win.Native]::GetForegroundWindow() -eq $h)
                })
            }
        }
        return $true
    }
    [void][Win.Native]::EnumWindows($cb, [IntPtr]::Zero)
    return @($list | Sort-Object Started)
}

$windows = Get-GameWindows
if ($Info) {
    if ($windows.Count -eq 0) { 'No Ace Combat 7 game window found (is the copy running?).'; exit 0 }
    $windows | ForEach-Object {
        "process $($_.ProcessId), started $($_.Started.ToString('HH:mm:ss')), window at ($($_.Left),$($_.Top)) size $($_.Width)x$($_.Height)$(if ($_.Foreground) { ', in front' })  '$($_.Title)'"
    }
    exit 0
}

if ($Keys.Count -eq 0 -and $Screenshot -eq '') { Write-Error 'Nothing to do: give -Keys, -Screenshot or -Info.'; exit 1 }

$target = $null
if ($Keys.Count -gt 0 -or ($Screenshot -ne '' -and -not $FullScreen)) {
    if ($windows.Count -eq 0) { Write-Error 'No Ace Combat 7 game window found (is the copy running?).'; exit 2 }
    if ($ProcessId -ne 0) {
        $target = $windows | Where-Object { $_.ProcessId -eq $ProcessId } | Select-Object -First 1
        if (-not $target) { Write-Error "No game window belongs to process $ProcessId."; exit 2 }
    } else {
        $target = $windows[0]
        if ($windows.Count -gt 1) { "Two or more copies are running; using the one started first (process $($target.ProcessId)). Use -ProcessId to pick another." }
    }
}

if ($Keys.Count -gt 0) {
    # Split "Down,Down,Enter" style lists and check every name first. "Ctrl+P" holds
    # Ctrl while P is pressed (any number of modifiers, the last name is the key).
    $names = @($Keys | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ -ne '' })
    foreach ($n in $names) { foreach ($part in ($n -split '\+')) { if (-not $vk.ContainsKey($part)) { Write-Error "Unknown key '$part'. Known: $($vk.Keys -join ', ')"; exit 1 } } }

    # Bring the game window to the front. A quick Alt tap makes Windows allow it.
    if ([Win.Native]::IsIconic($target.Handle)) { [void][Win.Native]::ShowWindow($target.Handle, 9) }
    [Win.Native]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Win.Native]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [void][Win.Native]::SetForegroundWindow($target.Handle)
    Start-Sleep -Milliseconds 400
    if ([Win.Native]::GetForegroundWindow() -ne $target.Handle) {
        Write-Error "Could not bring the game window to the front (process $($target.ProcessId)); no keys sent."; exit 3
    }
    $press = {
        param([int]$code, [bool]$down)
        $scan = [byte]([Win.Native]::MapVirtualKey([uint32]$code, 0) -band 0xFF)
        $flags = [uint32]0x0008   # scan code
        if ($extended -contains $code) { $flags = $flags -bor 0x0001 }
        if (-not $down) { $flags = $flags -bor 0x0002 }
        [Win.Native]::keybd_event([byte]$code, $scan, $flags, [UIntPtr]::Zero)
    }
    foreach ($n in $names) {
        $parts = @($n -split '\+')
        $mods = @(); if ($parts.Count -gt 1) { $mods = $parts[0..($parts.Count - 2)] }
        $main = $parts[$parts.Count - 1]
        foreach ($m in $mods) { & $press $vk[$m] $true; Start-Sleep -Milliseconds 40 }
        & $press $vk[$main] $true
        Start-Sleep -Milliseconds $HoldMs
        & $press $vk[$main] $false
        [array]::Reverse($mods); foreach ($m in $mods) { Start-Sleep -Milliseconds 40; & $press $vk[$m] $false }
        Start-Sleep -Milliseconds $GapMs
    }
    "Pressed $($names -join ', ') in the game window of process $($target.ProcessId)."
}

if ($Screenshot -ne '') {
    if ($WaitMs -gt 0) { Start-Sleep -Milliseconds $WaitMs }   # give the game time to react before the picture
    $dir = Split-Path -Parent $Screenshot
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($FullScreen) {
        Add-Type -AssemblyName System.Windows.Forms
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $x = $b.X; $y = $b.Y; $w = $b.Width; $h = $b.Height
    } else {
        # Picture of the game's drawing area (without the title bar), where it is on screen.
        $cr = New-Object Win.Native+RECT
        [void][Win.Native]::GetClientRect($target.Handle, [ref]$cr)
        $pt = New-Object Win.Native+POINT
        [void][Win.Native]::ClientToScreen($target.Handle, [ref]$pt)
        $x = $pt.X; $y = $pt.Y; $w = $cr.Right - $cr.Left; $h = $cr.Bottom - $cr.Top
        if ($w -le 0 -or $h -le 0) { Write-Error 'The game window has no visible area (minimised?).'; exit 4 }
    }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $g.Dispose()
    $bmp.Save($Screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "Screenshot ${w}x${h} saved to $Screenshot"
}
