<#
.SYNOPSIS
    Removes caelestia-win autostart and (optionally) its apps and configs.

.PARAMETER RemoveApps
    Also uninstall komorebi, whkd and YASB with winget. Flow Launcher and the font are kept.

.PARAMETER RemoveConfig
    Also delete ~/.config/caelestia-win, komorebi, whkd and yasb config folders.

.PARAMETER RestoreBackup
    Copy the newest backup made by Install.ps1 back into place.
#>
[CmdletBinding()]
param(
    [switch]$RemoveApps,
    [switch]$RemoveConfig,
    [switch]$RestoreBackup
)

$ErrorActionPreference = 'Continue'

$CwHome       = Join-Path $HOME '.config\caelestia-win'
$KomorebiHome = Join-Path $HOME '.config\komorebi'
$WhkdHome     = Join-Path $HOME '.config\whkd'
$YasbHome     = Join-Path $HOME '.config\yasb'
$BinDir       = Join-Path $CwHome 'bin'

function Write-Step([string]$Text) { Write-Host ''; Write-Host ('==> ' + $Text) -ForegroundColor Cyan }

Write-Step 'Showing the Windows taskbar again'
$cw = Join-Path $CwHome 'cw.ps1'
if (Test-Path -LiteralPath $cw) {
    try { & $cw 'taskbar' 'show' } catch { Write-Warning "Could not restore the taskbar: $_" }
}

Write-Step 'Stopping komorebi, whkd and YASB'
& komorebic stop --whkd 2>$null | Out-Null
& yasbc stop 2>$null | Out-Null
& yasbc disable-autostart 2>$null | Out-Null
foreach ($name in @('komorebi', 'whkd', 'yasb', 'tacky-borders')) { Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force }

Write-Step 'Removing autostart and environment variables'
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CaelestiaWin' -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $null, 'User')
[Environment]::SetEnvironmentVariable('WHKD_CONFIG_HOME', $null, 'User')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $clean = (($userPath -split ';') | Where-Object { $_ -and ($_ -ne $BinDir) }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $clean, 'User')
}

if ($RestoreBackup) {
    Write-Step 'Restoring your previous configs'
    $latest = Get-ChildItem -LiteralPath $CwHome -Directory -Filter 'backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) {
        $map = @{ 'komorebi' = $KomorebiHome; 'whkd' = $WhkdHome; 'yasb' = $YasbHome }
        foreach ($key in $map.Keys) {
            $src = Join-Path $latest.FullName $key
            if (Test-Path -LiteralPath $src) {
                New-Item -ItemType Directory -Force -Path $map[$key] | Out-Null
                Copy-Item -Path (Join-Path $src '*') -Destination $map[$key] -Force -Recurse
                Write-Host ("    restored $key from " + $latest.Name)
            }
        }
    } else { Write-Warning 'No backup folder found.' }
}

if ($RemoveApps) {
    Write-Step 'Uninstalling apps'
    foreach ($id in @('LGUG2Z.komorebi', 'LGUG2Z.whkd', 'AmN.yasb')) {
        & winget uninstall --id $id --exact --silent 2>$null
    }
}

if ($RemoveConfig) {
    Write-Step 'Deleting configuration folders'
    $latestBackup = $null
    if ($RestoreBackup) { $latestBackup = $null }
    foreach ($dir in @($KomorebiHome, $WhkdHome, $YasbHome)) {
        if ((Test-Path -LiteralPath $dir) -and -not $RestoreBackup) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    if ($RestoreBackup) { Write-Host '    (kept komorebi/whkd/yasb folders because -RestoreBackup was used)' }
    # remove our home last: it contains the backups
    if (Test-Path -LiteralPath $CwHome) { Remove-Item -LiteralPath $CwHome -Recurse -Force }
}

Write-Host ''
Write-Host 'caelestia-win removed.' -ForegroundColor Green
if (-not $RemoveConfig) { Write-Host "Your config files were left in place under $HOME\.config (use -RemoveConfig to delete)." }
Write-Host 'Wallpapers in Pictures\Wallpapers were not touched.'
