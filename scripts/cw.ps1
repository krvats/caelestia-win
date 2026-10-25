<#
.SYNOPSIS
    cw - control script for caelestia-win (the Windows counterpart of Caelestia's `caelestia` CLI).

.DESCRIPTION
    cw wallpaper next|prev|random|set <file>|current
    cw live next|prev|random|set <file>|stop|pause|resume|volume <0-100>|list|thumbs|status|install|settings
    cw live rules battery|fullscreen on|off      pause the animated wallpaper on battery power / when an app is fullscreen
    cw scheme dark|light|toggle
    cw variant tonal|vibrant|muted|mono
    cw theme            regenerate colours from the current wallpaper
    cw preset <name>|auto   pick a named colour theme, or auto to follow the wallpaper
    cw reload           reload komorebi, whkd and the bar
    cw start | stop     start or stop komorebi + whkd + YASB
    cw taskbar hide|show
    cw lock
    cw keys             print the keyboard shortcut cheat sheet
    cw screenshot       save a full-screen screenshot to Pictures\caelestia-win-screenshots
    cw autostart on|off|status      start caelestia-win at sign-in (a scheduled task, no startup delay)
    cw settings         open the settings window (colours, wallpapers, gaps, bar, shortcuts)   Alt+S
    cw dashboard        open the optional Caelestia dashboard app, if it is installed
    cw status
    cw doctor           check that everything is installed and wired up
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string]$Command = 'help',
    [Parameter(Position = 1)] [string]$Sub = '',
    [Parameter(Position = 2, ValueFromRemainingArguments = $true)] [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$CwHome       = Join-Path $HOME '.config\caelestia-win'
$StateFile    = Join-Path $CwHome 'state.json'
$WallDir      = Join-Path $HOME 'Pictures\Wallpapers'
$KomorebiHome = Join-Path $HOME '.config\komorebi'
$WhkdHome     = Join-Path $HOME '.config\whkd'
$YasbHome     = Join-Path $HOME '.config\yasb'
$LiveDir      = Join-Path $WallDir 'Animated'
$ThumbDir     = Join-Path $CwHome 'thumbs'
$LiveExt      = '^\.(mp4|webm|mkv|gif|mov|avi)$'

$env:KOMOREBI_CONFIG_HOME = $KomorebiHome
$env:WHKD_CONFIG_HOME     = $WhkdHome

# A terminal (or a hotkey) that was opened before the installer finished still has the old PATH, which is the
# usual reason for "komorebic is not recognised". Re-read it from the registry every time cw runs.
function Update-SessionPath {
    $seen = @{}
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($src in @($env:Path, [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))) {
        if (-not $src) { continue }
        foreach ($p in ($src -split ';')) {
            if ($p -and -not $seen.ContainsKey($p.ToLower())) { $seen[$p.ToLower()] = $true; $parts.Add($p) }
        }
    }
    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    if ((Test-Path -LiteralPath $links) -and -not $seen.ContainsKey($links.ToLower())) { $parts.Add($links) }
    $env:Path = ($parts -join ';')
}
Update-SessionPath

# ----------------------------------------------------------------------------- state

function Get-State {
    $s = [ordered]@{ wallpaper = ''; mode = 'dark'; variant = 'tonal'; preset = ''; taskbarHidden = $false
                     live = ''; liveVolume = 0; livePauseBattery = $true; livePauseFullscreen = $true }
    if (Test-Path -LiteralPath $StateFile) {
        try {
            $j = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
            foreach ($k in @('wallpaper', 'mode', 'variant', 'preset', 'live')) {
                if ($j.$k) { $s[$k] = [string]$j.$k }
            }
            if ($j.taskbarHidden -eq $true) { $s['taskbarHidden'] = $true }
            if ($null -ne $j.liveVolume) { $s['liveVolume'] = [int]$j.liveVolume }
            if ($j.livePauseBattery -eq $false) { $s['livePauseBattery'] = $false }
            if ($j.livePauseFullscreen -eq $false) { $s['livePauseFullscreen'] = $false }
        } catch { }
    }
    return $s
}

function Save-State($State) {
    New-Item -ItemType Directory -Force -Path $CwHome | Out-Null
    ($State | ConvertTo-Json) | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

# ----------------------------------------------------------------------------- helpers

function Test-Tool([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-TackyExe {
    $p = Join-Path $CwHome 'bin\tacky-borders.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Start-Tacky {
    $exe = Get-TackyExe
    if ($exe -and -not (Get-Process -Name 'tacky-borders' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $exe -WindowStyle Hidden
    }
}

function Get-PythonCommand {
    # returns @(exe, preArgs...) ; skips the Microsoft Store python.exe stub
    $py = Get-Command 'py' -ErrorAction SilentlyContinue
    if ($py) { return @($py.Source, '-3') }
    foreach ($name in @('python', 'python3')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c -and ($c.Source -notlike '*\WindowsApps\*')) { return @($c.Source) }
    }
    throw 'Python 3 was not found. Install it with:  winget install Python.Python.3.12'
}

function Invoke-Theme([string]$Image) {
    $st = Get-State
    $script = Join-Path $CwHome 'theme.py'
    if (-not (Test-Path -LiteralPath $script)) { throw "theme.py is missing: $script. Re-run Install.ps1." }

    $py = Get-PythonCommand
    $exe = $py[0]
    $pyArgs = @()
    if ($py.Count -gt 1) { $pyArgs += $py[1..($py.Count - 1)] }
    $pyArgs += @($script, '--home', $CwHome, '--yasb-dir', $YasbHome,
                 '--komorebi-json', (Join-Path $KomorebiHome 'komorebi.json'),
                 '--mode', $st['mode'], '--variant', $st['variant'])
    if (Get-TackyExe) { $pyArgs += @('--tacky-dir', (Join-Path $HOME '.config\tacky-borders')) }
    $schemeNames = @('catppuccin', 'gruvbox', 'nord', 'rosepine', 'tokyonight', 'dracula', 'everforest', 'onedark', 'solarized')
    if ($st['preset'] -and ($schemeNames -contains $st['preset'])) { $pyArgs += @('--scheme', $st['preset']) }
    elseif ($st['preset']) { $pyArgs += @('--preset', $st['preset']) }
    elseif ($Image) { $pyArgs += @('--image', $Image) }

    & $exe @pyArgs
    if ($LASTEXITCODE -ne 0) { throw "theme.py failed with exit code $LASTEXITCODE" }
}

function Invoke-Reload {
    $ErrorActionPreference = 'SilentlyContinue'   # these tools may simply not be running
    if (Test-Tool 'komorebic') {
        & komorebic reload-configuration 2>$null | Out-Null   # fails quietly if komorebi is not running
    }
    if (Test-Tool 'yasbc') {
        & yasbc reload --silent 2>$null | Out-Null
    }
    if (Get-TackyExe) {
        Get-Process -Name 'tacky-borders' | Stop-Process -Force   # it re-reads its config on start
        Start-Sleep -Milliseconds 300
        Start-Tacky
    }
}

function Set-Wallpaper([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    if (-not ([System.Management.Automation.PSTypeName]'CwNative').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CwNative {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
    }
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10'   # Fill
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0'
    [void][CwNative]::SystemParametersInfo(20, 0, $full, 3)   # SPI_SETDESKWALLPAPER, update + broadcast
    return $full
}

function Get-WallpaperList {
    if (-not (Test-Path -LiteralPath $WallDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $WallDir -File |
        Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' } |
        Sort-Object Name)
}

function Set-WindowsAppTheme([string]$Mode) {
    $value = 0
    if ($Mode -eq 'light') { $value = 1 }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-ItemProperty -Path $key -Name 'AppsUseLightTheme' -Value $value -Type DWord
    Set-ItemProperty -Path $key -Name 'SystemUsesLightTheme' -Value $value -Type DWord
}

function Set-TaskbarAutoHide([bool]$Hide) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    if (-not (Test-Path $key)) { throw 'Could not find the taskbar settings key. Turn on "Automatically hide the taskbar" in Settings instead.' }
    $v = (Get-ItemProperty -Path $key -Name 'Settings').Settings
    if ($Hide) { $v[8] = 3 } else { $v[8] = 2 }
    Set-ItemProperty -Path $key -Name 'Settings' -Value $v
    Stop-Process -Name 'explorer' -Force   # Windows restarts Explorer by itself; this applies the change
    $st = Get-State
    $st['taskbarHidden'] = $Hide
    Save-State $st
}

# ----------------------------------------------------------------------------- animated wallpapers (video / GIF)
# Engine: Lively Wallpaper (free, open source) draws the video behind the desktop. caelestia-win adds the
# colour extraction, thumbnails, library folder and the pause rules on top.

function Get-LivelyExe {
    $c = New-Object System.Collections.Generic.List[string]
    $c.Add((Join-Path $env:LOCALAPPDATA 'Programs\Lively Wallpaper\Lively.exe'))
    $c.Add((Join-Path $env:ProgramFiles 'Lively Wallpaper\Lively.exe'))
    if (${env:ProgramFiles(x86)}) { $c.Add((Join-Path ${env:ProgramFiles(x86)} 'Lively Wallpaper\Lively.exe')) }
    foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
    $cmd = Get-Command 'Lively.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-FfmpegExe {
    $cmd = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $pk = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $pk) {
        $hit = Get-ChildItem -LiteralPath $pk -Directory -Filter 'Gyan.FFmpeg*' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Get-LiveList {
    if (-not (Test-Path -LiteralPath $LiveDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $LiveDir -File | Where-Object { $_.Extension -match $LiveExt } | Sort-Object Name)
}

function Invoke-Lively([string[]]$LivelyArgs) {
    $exe = Get-LivelyExe
    if (-not $exe) { throw 'Lively Wallpaper is not installed. Run:  cw live install' }
    $q = @()
    foreach ($a in $LivelyArgs) { if ($a -match '\s') { $q += ('"' + $a + '"') } else { $q += $a } }
    Start-Process -FilePath $exe -ArgumentList $q -WindowStyle Hidden | Out-Null
}

function Start-LivelyIfNeeded {
    if (Get-Process -Name 'Lively' -ErrorAction SilentlyContinue) { return }
    $exe = Get-LivelyExe
    if (-not $exe) { throw 'Lively Wallpaper is not installed. Run:  cw live install' }
    Start-Process -FilePath $exe | Out-Null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process -Name 'Lively' -ErrorAction SilentlyContinue) { break }
    }
    Start-Sleep -Seconds 2
    Invoke-Lively @('app', '--showApp', 'false')   # keep Lively's own window closed; it lives in the tray
}

function Get-LiveKey([string]$Path) {
    $i = Get-Item -LiteralPath $Path
    $s = $i.FullName.ToLower() + '|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks
    $h = [System.Security.Cryptography.SHA1]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}

# One still frame of a video or GIF (cached by file name, size and date, so it is only made again when the file changes).
function Get-LiveFrame([string]$Path, [int]$Width = 960) {
    $ff = Get-FfmpegExe
    if (-not $ff) { return $null }
    New-Item -ItemType Directory -Force -Path $ThumbDir | Out-Null
    $out = Join-Path $ThumbDir ((Get-LiveKey $Path) + '-' + $Width + '.jpg')
    if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0)) { return $out }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        foreach ($ss in @('1', '0')) {   # one second in avoids black first frames; fall back to the very first frame
            & $ff -hide_banner -loglevel error -y -ss $ss -i $Path -frames:v 1 -vf ('scale=' + $Width + ':-2') -q:v 3 $out 2>$null
            if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0)) { return $out }
        }
    } finally { $ErrorActionPreference = $old }
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
    return $null
}

function Update-LiveThumbs {
    $list = Get-LiveList
    if ($list.Count -eq 0) { Write-Output "No animated wallpapers yet. Put .mp4, .webm, .mkv or .gif files in $LiveDir"; return }
    if (-not (Get-FfmpegExe)) { Write-Output 'FFmpeg is not installed, so no thumbnails or colours can be made. Run:  cw live install'; return }
    $made = 0
    foreach ($f in $list) { if (Get-LiveFrame $f.FullName 320) { $made++ } }
    Write-Output ("thumbnails ready for $made of " + $list.Count + ' file(s) in ' + $ThumbDir)
}

function Start-LiveGuard {
    $guard = Join-Path $CwHome 'live-guard.ps1'
    if (-not (Test-Path -LiteralPath $guard)) { return }
    $running = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*live-guard.ps1*' })
    if ($running.Count -gt 0) { return }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $guard + '"')) | Out-Null
}

function Stop-LiveGuard {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*live-guard.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# Closes the animated wallpaper (if one is running) so a picture can show again.
function Stop-LiveWallpaper {
    $st = Get-State
    if (-not $st['live']) { return }
    $st['live'] = ''
    Save-State $st
    if ((Get-LivelyExe) -and (Get-Process -Name 'Lively' -ErrorAction SilentlyContinue)) {
        Invoke-Lively @('closewp', '--monitor', '-1')
        Start-Sleep -Milliseconds 600
    }
    Stop-LiveGuard
}

function Set-LiveWallpaper([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $inLib = Join-Path $LiveDir $Path
        if (Test-Path -LiteralPath $inLib -PathType Leaf) { $Path = $inLib }
        else { throw "File not found: $Path" }
    }
    $full = (Resolve-Path -LiteralPath $Path).Path
    if ([IO.Path]::GetExtension($full) -notmatch $LiveExt) { throw 'Animated wallpapers can be .mp4, .webm, .mkv, .mov, .avi or .gif files.' }
    if (-not (Get-LivelyExe)) { throw 'Lively Wallpaper is not installed. Run:  cw live install' }
    Start-LivelyIfNeeded
    Add-Type -AssemblyName System.Windows.Forms
    if ([System.Windows.Forms.Screen]::AllScreens.Count -gt 1) { Invoke-Lively @('app', '--layout', 'duplicate') }   # same wallpaper on every screen
    Invoke-Lively @('setwp', '--file', $full)
    $st = Get-State
    $st['live'] = $full
    Save-State $st
    Invoke-Lively @('app', '--volume', [string]$st['liveVolume'])

    # colours from a frame of the video, like caelestia-aw does
    $frame = Get-LiveFrame $full
    if ($frame) { Invoke-Theme $frame }
    else {
        Write-Output 'FFmpeg is not installed, so the colours stay as they were. For wallpaper colours run:  cw live install'
        $img = ''
        if ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = $st['wallpaper'] }
        Invoke-Theme $img
    }
    Invoke-Reload
    Start-LiveGuard
    Write-Output ('animated wallpaper: ' + [IO.Path]::GetFileName($full))
}

function Install-LiveSupport {
    if (-not (Test-Tool 'winget')) { throw 'winget was not found. Install "App Installer" from the Microsoft Store first.' }
    if (-not (Get-LivelyExe)) {
        Write-Output 'installing Lively Wallpaper ...'
        & winget install --id rocksdanister.LivelyWallpaper --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Write-Warning 'winget could not install Lively. Get it from https://github.com/rocksdanister/lively/releases and run this again.' }
    } else { Write-Output 'Lively Wallpaper: already installed' }
    if (-not (Get-FfmpegExe)) {
        Write-Output 'installing FFmpeg (for thumbnails and wallpaper colours) ...'
        & winget install --id Gyan.FFmpeg --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Write-Warning 'winget could not install FFmpeg. Colours from videos need it: winget install Gyan.FFmpeg' }
    } else { Write-Output 'FFmpeg: already installed' }
    Update-SessionPath
    New-Item -ItemType Directory -Force -Path $LiveDir | Out-Null
    Write-Output ('Done. Put .mp4, .webm, .mkv or .gif files in ' + $LiveDir + ' and run:  cw live next')
}

function Invoke-LiveCommand {
    $st = Get-State
    switch ($Sub.ToLower()) {
        'install' { Install-LiveSupport; return }
        'list' {
            $list = Get-LiveList
            if ($list.Count -eq 0) { Write-Output "No animated wallpapers yet. Put .mp4, .webm, .mkv or .gif files in $LiveDir" }
            foreach ($f in $list) {
                $mark = '  '
                if ($f.FullName -eq $st['live']) { $mark = '* ' }
                Write-Output ($mark + $f.Name)
            }
            return
        }
        'thumbs' { Update-LiveThumbs; return }
        'status' {
            $exe = Get-LivelyExe
            if ($exe) { Write-Output ('engine         Lively Wallpaper ' + $(if (Get-Process -Name 'Lively' -ErrorAction SilentlyContinue) { '(running)' } else { '(not running)' })) }
            else { Write-Output 'engine         Lively Wallpaper is not installed (cw live install)' }
            if (Get-FfmpegExe) { Write-Output 'ffmpeg         installed' } else { Write-Output 'ffmpeg         not installed (needed for colours and thumbnails)' }
            if ($st['live']) { Write-Output ('playing        ' + $st['live']) } else { Write-Output 'playing        nothing (a picture is the wallpaper)' }
            Write-Output ('pause on battery     ' + $(if ($st['livePauseBattery']) { 'on' } else { 'off' }))
            Write-Output ('pause on fullscreen  ' + $(if ($st['livePauseFullscreen']) { 'on' } else { 'off' }))
            Write-Output ('volume         ' + $st['liveVolume'])
            return
        }
        'stop' {
            Stop-LiveWallpaper
            $img = ''
            if ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = (Set-Wallpaper $st['wallpaper']) }
            Invoke-Theme $img
            Invoke-Reload
            Write-Output 'animated wallpaper stopped'
            return
        }
        'pause'  { Invoke-Lively @('app', '--play', 'false'); return }
        'resume' { Invoke-Lively @('app', '--play', 'true'); return }
        'settings' { Invoke-Lively @('app', '--showApp', 'true'); return }
        'volume' {
            if (-not $Rest -or $Rest[0] -notmatch '^\d{1,3}$' -or [int]$Rest[0] -gt 100) { throw 'Usage: cw live volume <0-100>' }
            $st['liveVolume'] = [int]$Rest[0]
            Save-State $st
            if (Get-LivelyExe) { Invoke-Lively @('app', '--volume', [string]$Rest[0]) }
            return
        }
        'rules' {
            $which = ''
            if ($Rest -and $Rest.Count -ge 1) { $which = $Rest[0].ToLower() }
            $val = ''
            if ($Rest -and $Rest.Count -ge 2) { $val = $Rest[1].ToLower() }
            if (@('battery', 'fullscreen') -notcontains $which -or @('on', 'off') -notcontains $val) { throw 'Usage: cw live rules battery|fullscreen on|off' }
            $key = 'livePauseBattery'
            if ($which -eq 'fullscreen') { $key = 'livePauseFullscreen' }
            $st[$key] = ($val -eq 'on')
            Save-State $st
            Write-Output ("pause on $which : $val")
            return
        }
        'set' {
            if (-not $Rest -or -not $Rest[0]) { throw 'Usage: cw live set <video or gif file>' }
            Set-LiveWallpaper $Rest[0]
            return
        }
        { @('next', 'prev', 'random') -contains $_ } {
            $list = Get-LiveList
            if ($list.Count -eq 0) { throw "No animated wallpapers in $LiveDir. Put .mp4, .webm, .mkv or .gif files there first." }
            $idx = -1
            for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].FullName -eq $st['live']) { $idx = $i } }
            $mode = $Sub.ToLower()
            if ($mode -eq 'next') { $idx = ($idx + 1) % $list.Count }
            elseif ($mode -eq 'prev') { $idx = ($idx - 1 + $list.Count) % $list.Count }
            else {
                $new = Get-Random -Minimum 0 -Maximum $list.Count
                if ($list.Count -gt 1) { while ($new -eq $idx) { $new = Get-Random -Minimum 0 -Maximum $list.Count } }
                $idx = $new
            }
            Set-LiveWallpaper $list[$idx].FullName
            return
        }
        'wallpaper' { Write-Output 'Use:  cw live next   (or random | prev | set <file>)'; return }
        default {
            if ($Sub) { Write-Output ('Unknown option "' + $Sub + '".') }
            Write-Output 'cw live next | prev | random | set <file> | stop | pause | resume | volume <0-100>'
            Write-Output 'cw live rules battery|fullscreen on|off | list | thumbs | status | install | settings'
            Write-Output ''
            & $PSCommandPath 'live' 'status'
            return
        }
    }
}

# ----------------------------------------------------------------------------- autostart (runs at sign-in)
# A scheduled "at log on" task starts caelestia-win the moment you sign in (no admin needed: it runs as you).
# If Windows refuses the task, the HKCU Run key is used instead. Windows also normally waits ~10 seconds before it
# runs Run-key programs; StartupDelayInMSec = 0 removes that wait.

$AutostartTask = 'CaelestiaWin'
$RunKeyPath    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Get-AutostartState {
    if (Get-ScheduledTask -TaskName $AutostartTask -ErrorAction SilentlyContinue) { return 'task' }
    if (Get-ItemProperty -Path $RunKeyPath -Name $AutostartTask -ErrorAction SilentlyContinue) { return 'runkey' }
    return 'off'
}

function Set-Autostart([bool]$On) {
    if (-not $On) {
        Unregister-ScheduledTask -TaskName $AutostartTask -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RunKeyPath -Name $AutostartTask -ErrorAction SilentlyContinue
        return
    }
    $startScript = Join-Path $CwHome 'start.ps1'
    $psArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startScript + '"'
    $taskOk = $false
    try {
        $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $who
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
        [void](Register-ScheduledTask -TaskName $AutostartTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop)
        $taskOk = $true
    } catch {
        Write-Output ('(a scheduled task was not allowed here: ' + $_.Exception.Message + ' - using the Run key instead)')
    }
    if ($taskOk) {
        Remove-ItemProperty -Path $RunKeyPath -Name $AutostartTask -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $RunKeyPath -Name $AutostartTask -Value ('powershell.exe ' + $psArgs)
    }
    $ser = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
    if (-not (Test-Path -LiteralPath $ser)) { New-Item -Path $ser -Force | Out-Null }
    Set-ItemProperty -Path $ser -Name 'StartupDelayInMSec' -Value 0 -Type DWord
}

function Invoke-AutostartCommand {
    switch ($Sub.ToLower()) {
        'on'     { Set-Autostart $true;  Write-Output ('autostart: ' + (Get-AutostartState)) }
        'off'    { Set-Autostart $false; Write-Output 'autostart: off' }
        default  { Write-Output ('autostart: ' + (Get-AutostartState) + '   (cw autostart on | off)') }
    }
}

# ----------------------------------------------------------------------------- commands

function Invoke-WallpaperCommand {
    $st = Get-State
    $list = Get-WallpaperList
    $target = $null

    if ($Sub -eq 'set') {
        if (-not $Rest -or -not $Rest[0]) { throw 'Usage: cw wallpaper set <image file>' }
        $target = $Rest[0]
    }
    elseif ($Sub -eq 'current') {
        if ($st['wallpaper']) { Write-Output $st['wallpaper'] } else { Write-Output '(none set through cw yet)' }
        return
    }
    elseif (@('next', 'prev', 'random') -contains $Sub) {
        if ($list.Count -eq 0) { throw "No images in $WallDir. Put some .jpg or .png files there first." }
        $idx = -1
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i].FullName -eq $st['wallpaper']) { $idx = $i }
        }
        if ($Sub -eq 'next')   { $idx = ($idx + 1) % $list.Count }
        if ($Sub -eq 'prev')   { $idx = ($idx - 1 + $list.Count) % $list.Count }
        if ($Sub -eq 'random') {
            $new = Get-Random -Minimum 0 -Maximum $list.Count
            if ($list.Count -gt 1) { while ($new -eq $idx) { $new = Get-Random -Minimum 0 -Maximum $list.Count } }
            $idx = $new
        }
        $target = $list[$idx].FullName
    }
    else {
        throw 'Usage: cw wallpaper next|prev|random|set <file>|current'
    }

    Stop-LiveWallpaper   # a picture replaces any animated wallpaper
    $full = Set-Wallpaper $target
    $st = Get-State
    $st['wallpaper'] = $full
    Save-State $st
    Invoke-Theme $full
    Invoke-Reload
}

function Invoke-SchemeCommand {
    $st = Get-State
    $mode = $Sub
    if ($mode -eq 'toggle') {
        if ($st['mode'] -eq 'dark') { $mode = 'light' } else { $mode = 'dark' }
    }
    if (@('dark', 'light') -notcontains $mode) { throw 'Usage: cw scheme dark|light|toggle' }
    $st['mode'] = $mode
    Save-State $st
    Set-WindowsAppTheme $mode
    $img = ''
    if ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = $st['wallpaper'] }
    Invoke-Theme $img
    Invoke-Reload
}

function Invoke-VariantCommand {
    if (@('tonal', 'vibrant', 'muted', 'mono') -notcontains $Sub) { throw 'Usage: cw variant tonal|vibrant|muted|mono' }
    $st = Get-State
    $st['variant'] = $Sub
    Save-State $st
    $img = ''
    if ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = $st['wallpaper'] }
    Invoke-Theme $img
    Invoke-Reload
}

function Invoke-Start {
    if (-not (Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) {
        & komorebic start --whkd
    }
    if (Test-Tool 'yasbc') {
        Start-Process -FilePath 'yasbc' -ArgumentList @('start', '--silent') -WindowStyle Hidden
    }
    Start-Tacky
    $st = Get-State
    if ($st['live']) { Start-LiveGuard }
}

function Invoke-Stop {
    $ErrorActionPreference = 'SilentlyContinue'
    Stop-LiveGuard
    if (Test-Tool 'yasbc') { & yasbc stop --silent 2>$null | Out-Null }
    if (Test-Tool 'komorebic') { & komorebic stop --whkd 2>$null | Out-Null }
    Get-Process -Name 'tacky-borders' | Stop-Process -Force
}

function Invoke-Status {
    foreach ($p in @('komorebi', 'whkd', 'yasb', 'tacky-borders', 'Flow.Launcher')) {
        $running = [bool](Get-Process -Name $p -ErrorAction SilentlyContinue)
        $mark = 'stopped'
        if ($running) { $mark = 'running' }
        Write-Output ('{0,-14} {1}' -f $p, $mark)
    }
    $st = Get-State
    Write-Output ('mode           {0}   variant {1}' -f $st['mode'], $st['variant'])
    if ($st['wallpaper']) { Write-Output ('wallpaper      {0}' -f $st['wallpaper']) }
    if ($st['live']) { Write-Output ('animated       {0}' -f $st['live']) }
}

function Invoke-PresetCommand {
    $seedPresets = @('lavender', 'rose', 'sunset', 'amber', 'forest', 'mint', 'sky', 'ocean', 'orchid')
    $schemePresets = @('catppuccin', 'gruvbox', 'nord', 'rosepine', 'tokyonight', 'dracula', 'everforest', 'onedark', 'solarized')
    $presets = $seedPresets + $schemePresets
    $name = $Sub.ToLower()
    if (-not $name -or $name -eq 'list') {
        $st = Get-State
        $current = 'auto (follows the wallpaper)'
        if ($st['preset']) { $current = $st['preset'] }
        Write-Output ('current: ' + $current)
        Write-Output ('colour presets:  ' + ($seedPresets -join ', '))
        Write-Output ('community themes: ' + ($schemePresets -join ', '))
        Write-Output 'auto = follow the wallpaper'
        return
    }
    $st = Get-State
    if ($name -eq 'auto') { $st['preset'] = '' }
    elseif ($presets -contains $name) { $st['preset'] = $name }
    else { throw ('Unknown preset. Choose one of: ' + ($presets -join ', ') + ', auto') }
    Save-State $st
    $img = ''
    if ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = $st['wallpaper'] }
    Invoke-Theme $img
    Invoke-Reload
}

function Invoke-Doctor {
    $ErrorActionPreference = 'Continue'
    function Check([string]$Label, [bool]$Ok, [string]$Fix) {
        if ($Ok) { Write-Host ('  [ok]   ' + $Label) -ForegroundColor Green }
        else { Write-Host ('  [FAIL] ' + $Label + '  ->  ' + $Fix) -ForegroundColor Yellow; $script:problems++ }
    }
    $script:problems = 0
    Write-Host 'caelestia-win doctor'
    Check 'komorebic on PATH'   (Test-Tool 'komorebic') 'winget install LGUG2Z.komorebi, then open a new terminal'
    Check 'whkd on PATH'        (Test-Tool 'whkd')      'winget install LGUG2Z.whkd'
    Check 'yasbc on PATH'       (Test-Tool 'yasbc')     'winget install AmN.yasb'
    $hasPython = $true
    try { [void](Get-PythonCommand) } catch { $hasPython = $false }
    Check 'Python 3 available'  $hasPython 'winget install Python.Python.3.12'
    if ($hasPython) {
        $py = Get-PythonCommand
        $exe = $py[0]
        $a = @()
        if ($py.Count -gt 1) { $a += $py[1..($py.Count - 1)] }
        $a += @('-c', 'import PIL')
        & $exe @a 2>$null
        Check 'Pillow installed'    ($LASTEXITCODE -eq 0) 'python -m pip install --user pillow'
    }
    Check 'komorebi.json'       (Test-Path (Join-Path $KomorebiHome 'komorebi.json')) 'run Install.ps1 again'
    Check 'whkdrc'              (Test-Path (Join-Path $WhkdHome 'whkdrc'))            'run Install.ps1 again'
    Check 'YASB config.yaml'    (Test-Path (Join-Path $YasbHome 'config.yaml'))       'run Install.ps1 again'
    Check 'YASB styles.css'     (Test-Path (Join-Path $YasbHome 'styles.css'))        'run: cw theme'
    Check 'starts at sign-in'    ((Get-AutostartState) -ne 'off')                      'run: cw autostart on'
    Check 'settings window'      (Test-Path (Join-Path $CwHome 'settings.ps1'))        'run Install.ps1 again'
    Check 'komorebi running'    ([bool](Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) 'run: cw start'
    Check 'YASB running'        ([bool](Get-Process -Name 'yasb' -ErrorAction SilentlyContinue))     'run: cw start'
    if (Get-TackyExe) {
        Check 'tacky-borders running' ([bool](Get-Process -Name 'tacky-borders' -ErrorAction SilentlyContinue)) 'run: cw start'
    } else {
        Write-Host '  [info] tacky-borders (rounded gradient borders) is not installed; komorebi draws plain borders. Re-run Install.ps1 to add it.'
    }

    if (Get-LivelyExe) { Write-Host '  [ok]   Lively Wallpaper (animated wallpapers)' -ForegroundColor Green }
    else { Write-Host '  [info] animated wallpapers are off. Turn them on with:  cw live install' }
    if ((Get-LivelyExe) -and -not (Get-FfmpegExe)) { Write-Host '  [info] FFmpeg is missing: animated wallpapers work, but without thumbnails or colours. Run:  cw live install' }

    Add-Type -AssemblyName System.Drawing
    $fonts = (New-Object System.Drawing.Text.InstalledFontCollection).Families | Where-Object { $_.Name -like 'JetBrainsMono*' }
    Check 'Nerd Font (JetBrainsMono)' ([bool]$fonts) 'winget install DEVCOM.JetBrainsMonoNerdFont, then sign out and in once'

    if (Test-Tool 'komorebic') {
        Write-Host ''
        Write-Host 'komorebic check:'
        & komorebic check
    }
    Write-Host ''
    if ($script:problems -eq 0) { Write-Host 'Everything looks fine.' -ForegroundColor Green }
    else { Write-Host ("$($script:problems) item(s) need attention.") -ForegroundColor Yellow }
}

function Show-Keys {
    @'
  caelestia-win shortcuts   (Alt is the main key; edit ~\.config\whkd\whkdrc, then Alt+Shift+O)

  APPS            Alt+Enter terminal   Alt+Space launcher   Alt+E files   Alt+B browser   Alt+P screenshot
  SETTINGS        Alt+S opens the settings window (colours, wallpapers, gaps, bar, shortcuts)
  WINDOWS         Alt+Q close   Alt+M minimise   Alt+T float/tile   Alt+F maximise   Alt+Shift+F monocle
  FOCUS           Alt+H J K L  (left down up right)
  MOVE            Alt+Shift+H J K L     Alt+Shift+Enter  promote to main
  RESIZE          Alt+= / Alt+-  wider/narrower     Alt+Shift+= / -  taller/shorter
  LAYOUT          Alt+X flip horizontal   Alt+Y flip vertical
  TABS (STACKS)   Alt+Arrows stack   Alt+;  unstack   Alt+[ ]  cycle tabs
  WORKSPACES      Alt+1..9 go   Alt+Shift+1..9 send window there
  THEME           Alt+W next wallpaper   Alt+Shift+W random   Alt+Shift+T dark/light
  ANIMATED        Ctrl+Alt+W next animated wallpaper   Ctrl+Alt+Shift+W stop it
  SESSION         Alt+Shift+O reload   Alt+Shift+R retile   Alt+Shift+E quit tiling   Ctrl+Alt+L lock
'@ | Write-Output
}

function Save-Screenshot {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $dir = Join-Path $HOME 'Pictures\caelestia-win-screenshots'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $file = Join-Path $dir ('screenshot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.png')
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "Saved $file"
}

function Show-Help {
    Get-Help $PSCommandPath -Full | Out-String | Write-Output
}

# ----------------------------------------------------------------------------- dispatch

switch ($Command.ToLower()) {
    'wallpaper' { Invoke-WallpaperCommand }
    'scheme'    { Invoke-SchemeCommand }
    'variant'   { Invoke-VariantCommand }
    'preset'    { Invoke-PresetCommand }
    'live'      { Invoke-LiveCommand }
    'autostart' { Invoke-AutostartCommand }
    'settings'  {
        $s = Join-Path $CwHome 'settings.ps1'
        if (-not (Test-Path -LiteralPath $s)) { throw "settings.ps1 is missing: $s. Re-run Install.ps1." }
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $s + '"'))
    }
    'theme'     {
        $st = Get-State
        $img = ''
        if ($Sub -and (Test-Path -LiteralPath $Sub -PathType Leaf)) { $img = $Sub }   # cw theme <image> (used by Install.ps1)
        elseif ($st['wallpaper'] -and (Test-Path -LiteralPath $st['wallpaper'])) { $img = $st['wallpaper'] }
        Invoke-Theme $img
        Invoke-Reload
    }
    'reload'    { Invoke-Reload }
    'start'     { Invoke-Start }
    'stop'      { Invoke-Stop }
    'status'    { Invoke-Status }
    'doctor'    { Invoke-Doctor }
    'lock'      { & rundll32.exe user32.dll,LockWorkStation }
    'keys'      { Show-Keys }
    'screenshot' { Save-Screenshot }
    'taskbar'   {
        if ($Sub -eq 'hide') { Set-TaskbarAutoHide $true }
        elseif ($Sub -eq 'show') { Set-TaskbarAutoHide $false }
        else { throw 'Usage: cw taskbar hide|show' }
    }
    'dashboard' {
        $exe = Join-Path $env:ProgramFiles 'Caelestia\Caelestia.exe'
        if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe }
        else { Write-Output 'The optional dashboard app is not installed. See optional\Build-Dashboard.ps1.' }
    }
    default     { Show-Help }
}
