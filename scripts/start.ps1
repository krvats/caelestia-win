# caelestia-win sign-in script (started by the "CaelestiaWin" scheduled task, see: cw autostart).
# Starts the bar, the borders, komorebi + whkd (+ the animated-wallpaper guard) right away and retries
# anything that is not up yet, so a slow sign-in does not leave you with a bare desktop.
# What happened is written to ~\.config\caelestia-win\start.log
$ErrorActionPreference = 'SilentlyContinue'

$CwHome = Join-Path $HOME '.config\caelestia-win'
$log = Join-Path $CwHome 'start.log'
New-Item -ItemType Directory -Force -Path $CwHome | Out-Null
Set-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  sign-in start')
function Write-Log([string]$Text) { Add-Content -LiteralPath $log -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $Text) }

# Re-read PATH from the registry: tools installed a moment ago are not in the environment this script was started with
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
$env:KOMOREBI_CONFIG_HOME = Join-Path $HOME '.config\komorebi'
$env:WHKD_CONFIG_HOME     = Join-Path $HOME '.config\whkd'

# wait (up to a minute) for the desktop shell: tools that attach to it fail if it is not there yet
for ($i = 0; $i -lt 120; $i++) {
    if (Get-Process -Name 'explorer') { break }
    Start-Sleep -Milliseconds 500
}
Write-Log 'explorer is up'

$tacky = Join-Path $CwHome 'bin\tacky-borders.exe'

for ($attempt = 1; $attempt -le 6; $attempt++) {
    if (-not (Get-Process -Name 'komorebi')) { & komorebic start --whkd 2>&1 | Out-Null; Write-Log "komorebi start (try $attempt)" }
    if (-not (Get-Process -Name 'yasb')) { Start-Process -FilePath 'yasbc' -ArgumentList @('start', '--silent') -WindowStyle Hidden; Write-Log "yasb start (try $attempt)" }
    if ((Test-Path -LiteralPath $tacky) -and -not (Get-Process -Name 'tacky-borders')) { Start-Process -FilePath $tacky -WindowStyle Hidden; Write-Log 'tacky-borders start' }
    Start-Sleep -Seconds 3
    $ok = (Get-Process -Name 'komorebi') -and (Get-Process -Name 'whkd') -and (Get-Process -Name 'yasb')
    if ($ok) { break }
}
foreach ($n in @('komorebi', 'whkd', 'yasb', 'tacky-borders')) {
    if (Get-Process -Name $n) { Write-Log ($n + ': running') } else { Write-Log ($n + ': NOT running') }
}

# animated wallpaper: Lively restores the video by itself; the guard pauses it on battery / fullscreen apps
$stateFile = Join-Path $CwHome 'state.json'
$guard = Join-Path $CwHome 'live-guard.ps1'
if ((Test-Path -LiteralPath $stateFile) -and (Test-Path -LiteralPath $guard)) {
    $st = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($st.live) {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $guard + '"'))
        Write-Log 'animated wallpaper guard started'
    }
}
Write-Log 'done'
