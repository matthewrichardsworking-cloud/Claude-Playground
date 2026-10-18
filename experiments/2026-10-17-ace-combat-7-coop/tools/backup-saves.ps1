# Copies the AC7 save and settings folder into AC7-Coop\backups\<date_time>\ and checks
# every file's SHA-256 against the original. Read-only on the real folder.
# Run before every test launch:  powershell -NoProfile -File tools\backup-saves.ps1

$src = Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 7'
$root = Split-Path $PSScriptRoot -Parent
$dst = Join-Path $root ("backups\" + (Get-Date -Format 'yyyy-MM-dd_HHmm') + "\ACE COMBAT 7")

if (-not (Test-Path -LiteralPath $src)) { Write-Error "Save folder not found: $src"; exit 2 }

robocopy $src $dst /E /COPY:DAT /DCOPY:T /R:1 /W:1 /NP /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Error "Copy failed (robocopy code $LASTEXITCODE)"; exit 3 }

function Get-Hashes($dir) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object {
        [pscustomobject]@{ R = $_.FullName.Substring($dir.Length); H = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
}
$a = @(Get-Hashes $src)
$b = @(Get-Hashes $dst)
$diff = @(Compare-Object $a $b -Property R, H)
if ($diff.Count -ne 0) { Write-Error "Backup does not match the original ($($diff.Count) differences)"; exit 4 }

"Backed up $($a.Count) files to $dst (all checksums match)"
exit 0
