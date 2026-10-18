# Starts the test copy at C:\AC7-Coop-Game straight from its own folder, with its OWN
# save and settings folder, so it cannot touch your real saves.
#
# How it works:
# - Started plainly, the copy hands itself to Steam, and Steam then starts the REAL
#   install. When Steam starts a game it tells it which app it is (SteamAppId); this
#   script does the same for this one launch. Steam must be running and still checks
#   that the account owns the game. Nothing is written to Steam or the real install.
# - Windows tells each program where its "Local AppData" folder is, and the game keeps
#   its saves and settings there (BANDAI NAMCO Entertainment\ACE COMBAT 7). For the game
#   process started here, and only for it, the script points that folder at
#   C:\AC7-Coop-Game\UserProfile instead. So the copy reads and writes
#   C:\AC7-Coop-Game\UserProfile\AppData\Local\BANDAI NAMCO Entertainment\ACE COMBAT 7
#   and never your real folder. Nothing else on the PC changes.
# - The first time, that folder is created and your current settings (windowed mode and
#   so on) and your save are COPIED into it, so the copy starts like your real game.
#   Your real files are only read. Add -NoSeed to start the copy empty instead.
# - The real save folder is backed up first, every time (tools\backup-saves.ps1).
#
#   powershell -NoProfile -File tools\start-copy.ps1
#   powershell -NoProfile -File tools\start-copy.ps1 -Second
#       second copy at the same time; it gets its own folder, C:\AC7-Coop-Game\UserProfile2,
#       and a smaller window (1280x720) so the two can be told apart
#   powershell -NoProfile -File tools\start-copy.ps1 -GameArgs '-UserDir=UserData'
#       extra words on the game's command line (for experiments)
#   powershell -NoProfile -File tools\start-copy.ps1 -SharedUserFolder
#       the OLD way: the copy uses your REAL save folder. Title screen only!

param(
    [switch]$Second,
    [switch]$SharedUserFolder,
    [switch]$NoSeed,
    [string]$GameArgs = ''
)

$game = 'C:\AC7-Coop-Game'
$exe = Join-Path $game 'Ace7Game.exe'
$steamId = '76561198126172633'
$realSaves = Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 7'

if (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
    Write-Error 'Open Steam first.'; exit 1
}
if ((Get-Process Ace7Game -ErrorAction SilentlyContinue) -and -not $Second) {
    Write-Error 'A copy of AC7 is already running. Add -Second to start another one anyway.'; exit 1
}
if ($Second -and $SharedUserFolder) {
    Write-Error 'A second copy must have its own save folder (leave out -SharedUserFolder).'; exit 1
}

& (Join-Path $PSScriptRoot 'backup-saves.ps1')
if ($LASTEXITCODE) { Write-Error 'Save backup failed, not starting the game.'; exit 1 }

$saved = @{ UP = $env:USERPROFILE; LA = $env:LOCALAPPDATA; AD = $env:APPDATA }
try {
    if ($SharedUserFolder) {
        $copySaves = $realSaves
    } else {
        $profileName = if ($Second) { 'UserProfile2' } else { 'UserProfile' }
        $profile = Join-Path $game $profileName
        $copySaves = Join-Path $profile 'AppData\Local\BANDAI NAMCO Entertainment\ACE COMBAT 7'

        if (-not (Test-Path -LiteralPath $copySaves)) {
            foreach ($d in @('Config', 'Logs', "SaveGames\$steamId")) {
                New-Item -ItemType Directory -Force -Path (Join-Path $copySaves $d) | Out-Null
            }
            New-Item -ItemType Directory -Force -Path (Join-Path $profile 'AppData\Roaming') | Out-Null
            if ($NoSeed) {
                "Created an empty save folder for the copy: $copySaves"
            } else {
                Copy-Item -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $realSaves 'Config') -Filter *.ini).FullName -Destination (Join-Path $copySaves 'Config')
                Copy-Item -LiteralPath (Join-Path $realSaves "SaveGames\$steamId\ACE7Save.sav") -Destination (Join-Path $copySaves "SaveGames\$steamId\ACE7Save.sav")
                if ($Second) {
                    # The crashed second copy of 17 Oct looked for its save here (no Steam-ID folder).
                    Copy-Item -LiteralPath (Join-Path $realSaves "SaveGames\$steamId\ACE7Save.sav") -Destination (Join-Path $copySaves 'SaveGames\ACE7Save.sav')
                    # Smaller window, lower right, so the two copies can be told apart. Keeps the file's encoding.
                    $ini = Join-Path $copySaves 'Config\GameUserSettings.ini'
                    $bytes = [IO.File]::ReadAllBytes($ini)
                    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = New-Object System.Text.UnicodeEncoding($false, $true) }
                    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = New-Object System.Text.UTF8Encoding($true) }
                    else { $enc = New-Object System.Text.UTF8Encoding($false) }
                    $text = [IO.File]::ReadAllText($ini)
                    $text = $text -replace '(?m)^(ResolutionSizeX=)\d+', '${1}1280' -replace '(?m)^(ResolutionSizeY=)\d+', '${1}720' -replace '(?m)^(WindowPosX=)-?\d+', '${1}600' -replace '(?m)^(WindowPosY=)-?\d+', '${1}330'
                    [IO.File]::WriteAllText($ini, $text, $enc)
                }
                "Created the copy's own save folder and copied your settings and save into it (your real files were only read):"
                "  $copySaves"
                if ($Second) { "  The second copy's window is set to 1280x720, lower right, so you can tell it from the first." }
            }
        }

        # Only the game process started below sees these. Restored for this window afterwards.
        $env:USERPROFILE = $profile
        $env:LOCALAPPDATA = Join-Path $profile 'AppData\Local'
        $env:APPDATA = Join-Path $profile 'AppData\Roaming'
    }

    $env:SteamAppId = '502500'
    $env:SteamGameId = '502500'
    $start = Get-Date
    if ($GameArgs -ne '') {
        $p = Start-Process -FilePath $exe -WorkingDirectory $game -ArgumentList $GameArgs -PassThru
    } else {
        $p = Start-Process -FilePath $exe -WorkingDirectory $game -PassThru
    }
    "Started $exe at $($start.ToString('HH:mm:ss')) (process id $($p.Id))$(if ($GameArgs -ne '') { ", command line: $GameArgs" })"
    if ($SharedUserFolder) {
        "WARNING: this run uses your REAL save folder. Stay on the title screen; past it, the copy loads and later rewrites your real save."
    } else {
        "This run's saves and settings: $copySaves"
    }
} finally {
    $env:USERPROFILE = $saved.UP; $env:LOCALAPPDATA = $saved.LA; $env:APPDATA = $saved.AD
}
