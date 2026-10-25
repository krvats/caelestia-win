# caelestia-win login script. Started from HKCU\...\Run by Install.ps1.
# Starts komorebi + whkd (+ tacky-borders). YASB starts itself (yasbc enable-autostart).
$ErrorActionPreference = 'SilentlyContinue'

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
