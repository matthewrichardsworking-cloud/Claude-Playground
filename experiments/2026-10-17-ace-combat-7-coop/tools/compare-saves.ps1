# Compares the REAL AC7 save and settings folder with a backup, file by file, using
# SHA-256 checksums. Read-only. Prints "No change" or lists every file that was added,
# removed or changed. Exit code 0 = no change, 1 = something changed.
#
# By default it uses the newest folder in AC7-Coop\backups\. To pick one:
#   powershell -NoProfile -File tools\compare-saves.ps1 -Backup 2026-10-17_2206

param([string]$Backup = '')

$real = Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 7'
$root = Split-Path $PSScriptRoot -Parent
$backupsDir = Join-Path $root 'backups'

if ($Backup -eq '') {
    $latest = Get-ChildItem -LiteralPath $backupsDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{4}$' } | Sort-Object Name | Select-Object -Last 1
    if (-not $latest) { Write-Error "No backups found in $backupsDir"; exit 2 }
    $Backup = $latest.Name
}
$bak = Join-Path (Join-Path $backupsDir $Backup) 'ACE COMBAT 7'
if (-not (Test-Path -LiteralPath $bak)) { Write-Error "Backup folder not found: $bak"; exit 2 }

function Get-Hashes($dir) {
    $table = @{}
    Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($dir.Length).TrimStart('\')
        $table[$rel] = [pscustomobject]@{ Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash; Size = $_.Length; Time = $_.LastWriteTime }
    }
    return $table
}

$a = Get-Hashes $real
$b = Get-Hashes $bak
$changes = @()
foreach ($k in ($a.Keys + $b.Keys | Sort-Object -Unique)) {
    if (-not $b.ContainsKey($k)) { $changes += "ADDED    $k  ($($a[$k].Size) bytes, written $($a[$k].Time))"; continue }
    if (-not $a.ContainsKey($k)) { $changes += "REMOVED  $k  (was $($b[$k].Size) bytes)"; continue }
    if ($a[$k].Hash -ne $b[$k].Hash) { $changes += "CHANGED  $k  ($($b[$k].Size) -> $($a[$k].Size) bytes, written $($a[$k].Time))" }
}

"Real folder:  $real"
"Compared to:  backups\$Backup  ($($b.Count) files)"
if ($changes.Count -eq 0) {
    "No change: all $($a.Count) files have the same SHA-256 as the backup."
    exit 0
} else {
    "$($changes.Count) difference(s):"
    $changes | ForEach-Object { "  $_" }
    exit 1
}
