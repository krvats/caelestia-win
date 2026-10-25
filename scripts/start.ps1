# caelestia-win login script. Started from HKCU\...\Run by Install.ps1.
# Starts komorebi + whkd (+ tacky-borders, + the animated-wallpaper guard). YASB and Lively start themselves.
$ErrorActionPreference = 'SilentlyContinue'

# Re-read PATH from the registry: tools installed a moment ago are not in the environment this script was started with
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')

$env:KOMOREBI_CONFIG_HOME = Join-Path $HOME '.config\komorebi'
$env:WHKD_CONFIG_HOME     = Join-Path $HOME '.config\whkd'

if (-not (Get-Process -Name 'komorebi')) {
    & komorebic start --whkd
    Start-Sleep -Seconds 2
}

$tacky = Join-Path $HOME '.config\caelestia-win\bin\tacky-borders.exe'
if ((Test-Path -LiteralPath $tacky) -and -not (Get-Process -Name 'tacky-borders')) {
    Start-Process -FilePath $tacky -WindowStyle Hidden
}

# animated wallpaper: Lively restores the video by itself; the guard pauses it on battery / fullscreen apps
$stateFile = Join-Path $HOME '.config\caelestia-win\state.json'
$guard = Join-Path $HOME '.config\caelestia-win\live-guard.ps1'
if ((Test-Path -LiteralPath $stateFile) -and (Test-Path -LiteralPath $guard)) {
    $st = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($st.live) {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $guard + '"'))
    }
}
