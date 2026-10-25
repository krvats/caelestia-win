<#
.SYNOPSIS
    Installs caelestia-win: a Caelestia-style desktop for Windows 10/11.

.DESCRIPTION
    Installs (through winget): komorebi (tiling), whkd (hotkeys), YASB (status bar),
    Flow Launcher (app launcher), JetBrainsMono Nerd Font, and Python if it is missing.
    Then copies the configs, generates wallpaper-based colours, enables autostart and starts everything.

    Run it as your normal user (no admin needed):
        powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1

.PARAMETER KeepTaskbar
    By default the Windows taskbar is set to auto-hide (Explorer restarts once) because the bar shows your
    running apps. Pass this to leave the taskbar alone. Undo later with: cw taskbar show

.PARAMETER SkipBorders
    Do not download tacky-borders (rounded gradient window borders). komorebi's plain borders are used instead.

.PARAMETER SetWallpaper
    Also switch your Windows wallpaper to the bundled one. By default your current wallpaper is kept
    and only used to pick the colours.

.PARAMETER SkipLauncher
    Do not install Flow Launcher.

.PARAMETER SkipFont
    Do not install the Nerd Font (bar icons will show as empty boxes without one).

.PARAMETER KeepConfigs
    If komorebi.json, whkdrc or the YASB config already exist, leave them alone.

.PARAMETER WithAnimated
    Also install animated wallpaper support (Lively Wallpaper and FFmpeg) so video and GIF wallpapers work.
    You can add it later with: cw live install   (or the button in the settings window)

.PARAMETER NoPause
    Do not wait for Enter at the end. By default the window stays open so you can read errors.

Everything printed is also saved to ~\.config\caelestia-win\install.log
#>
[CmdletBinding()]
param(
    [switch]$KeepTaskbar,
    [switch]$SkipBorders,
    [switch]$SetWallpaper,
    [switch]$SkipLauncher,
    [switch]$SkipFont,
    [switch]$KeepConfigs,
    [switch]$WithAnimated,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

$CwHome       = Join-Path $HOME '.config\caelestia-win'
$KomorebiHome = Join-Path $HOME '.config\komorebi'
$WhkdHome     = Join-Path $HOME '.config\whkd'
$YasbHome     = Join-Path $HOME '.config\yasb'
$WallDir      = Join-Path $HOME 'Pictures\Wallpapers'
$LiveDir      = Join-Path $WallDir 'Animated'
$BinDir       = Join-Path $CwHome 'bin'
$Stamp        = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot   = Join-Path $CwHome ("backup-" + $Stamp)
$LogFile      = Join-Path $CwHome 'install.log'
$script:failed = $false
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5.1 downloads are extremely slow with the progress bar on

New-Item -ItemType Directory -Force -Path $CwHome | Out-Null
try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { }

function Write-Step([string]$Text) { Write-Host ''; Write-Host ('==> ' + $Text) -ForegroundColor Cyan }
function Write-Note([string]$Text) { Write-Host ('    ' + $Text) }

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $seen = @{}
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($src in @($env:Path, $machine, $user, (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))) {
        if (-not $src) { continue }
        foreach ($d in ($src -split ';')) {
            if ($d -and -not $seen.ContainsKey($d.ToLower())) { $seen[$d.ToLower()] = $true; $parts.Add($d) }
        }
    }
    $env:Path = ($parts -join ';')
}

# winget does not always put a program on PATH. If a tool is still "not found", look for it in the usual places
# and add its folder to the PATH of this window and of your account, so hotkeys and new terminals find it too.
function Add-ToolToPath([string]$Exe, [string[]]$PackageFilters) {
    if (Test-Tool $Exe) { return }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($base) { foreach ($f in $PackageFilters) { $roots.Add((Join-Path $base $f)) } }
    }
    $pk = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $pk) {
        foreach ($d in (Get-ChildItem -LiteralPath $pk -Directory -ErrorAction SilentlyContinue)) {
            foreach ($f in $PackageFilters) { if ($d.Name -like ($f + '*')) { $roots.Add($d.FullName) } }
        }
    }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -Filter ($Exe + '.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) {
            $dir = $hit.DirectoryName
            $env:Path += ';' + $dir
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ((($userPath -split ';') -notcontains $dir)) { [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';')) + ';' + $dir), 'User') }
            Write-Note "found $Exe in $dir and added it to PATH"
            return
        }
    }
}

function Test-Tool([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Install-WingetPackage([string]$Id, [string]$Label) {
    $listed = (& winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String)
    if ($listed -match [regex]::Escape($Id)) { Write-Note "already installed: $Label"; return }
    Write-Note "installing $Label ..."
    & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget could not install $Label (exit code $LASTEXITCODE). The rest will continue; install it by hand later: winget install --id $Id"
    }
}

function Install-ConfigFile([string]$Source, [string]$Destination, [string]$BackupLabel) {
    $dir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        if ($KeepConfigs) { Write-Note "kept your existing $BackupLabel"; return }
        $same = (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash
        if (-not $same) {
            $back = Join-Path $BackupRoot $BackupLabel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $back) | Out-Null
            Copy-Item -LiteralPath $Destination -Destination $back -Force
            Write-Note "backed up your old $BackupLabel to $back"
        }
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

try {
# ------------------------------------------------------------------------------------------ 0. checks
Write-Step 'Checking your system'

$build = [Environment]::OSVersion.Version.Build
if ($build -lt 19041) { throw "Windows 10 version 2004 (build 19041) or newer is required. You have build $build." }
if ($build -lt 22000) { Write-Warning 'Windows 10 detected. Everything works, but some effects (animations, rounded borders) look best on Windows 11.' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Write-Warning 'You are running as administrator. This is not needed; settings are stored for the current user.' }

if (-not (Test-Tool 'winget')) {
    throw 'winget was not found. Install "App Installer" from the Microsoft Store, then run this script again.'
}
foreach ($p in @('scripts\cw.ps1', 'scripts\theme.py', 'scripts\start.ps1', 'scripts\settings.ps1', 'scripts\settings-lib.ps1', 'scripts\live-guard.ps1', 'templates\yasb.styles.css.tmpl', 'templates\tacky-borders.config.yaml.tmpl',
                 'config\komorebi\komorebi.json', 'config\whkd\whkdrc', 'config\yasb\config.yaml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $p))) { throw "Package file missing: $p. Extract the whole zip before running." }
}
Write-Note "Windows build $build, winget found."

# ------------------------------------------------------------------------------------------ 1. apps
Write-Step 'Installing apps with winget'
Install-WingetPackage 'LGUG2Z.komorebi' 'komorebi (tiling window manager)'
Install-WingetPackage 'LGUG2Z.whkd'     'whkd (hotkey daemon)'
Install-WingetPackage 'AmN.yasb'        'YASB (status bar)'
if (-not $SkipLauncher) { Install-WingetPackage 'Flow-Launcher.Flow-Launcher' 'Flow Launcher (app launcher)' }
if (-not $SkipFont)     { Install-WingetPackage 'DEVCOM.JetBrainsMonoNerdFont' 'JetBrainsMono Nerd Font' }
if ($WithAnimated) {
    Install-WingetPackage 'rocksdanister.LivelyWallpaper' 'Lively Wallpaper (plays video and GIF wallpapers)'
    Install-WingetPackage 'Gyan.FFmpeg' 'FFmpeg (thumbnails and colours for animated wallpapers)'
}

Update-SessionPath
$havePython = (Test-Tool 'py') -or ((Get-Command 'python' -ErrorAction SilentlyContinue) -and ((Get-Command 'python').Source -notlike '*\WindowsApps\*'))
if (-not $havePython) {
    Install-WingetPackage 'Python.Python.3.12' 'Python 3.12 (used for wallpaper colours)'
    Update-SessionPath
}

# winget does not always add a tool to PATH for the running session
if (-not (Test-Tool 'yasbc')) {
    foreach ($dir in @((Join-Path $env:ProgramFiles 'YASB'), (Join-Path $env:LOCALAPPDATA 'Programs\YASB'))) {
        if (Test-Path -LiteralPath (Join-Path $dir 'yasbc.exe')) { $env:Path += ';' + $dir; break }
    }
}
Add-ToolToPath 'komorebic' @('komorebi', 'LGUG2Z.komorebi')
Add-ToolToPath 'whkd' @('whkd', 'komorebi', 'LGUG2Z.whkd')
foreach ($t in @('komorebic', 'whkd', 'yasbc')) {
    if (-not (Test-Tool $t)) { Write-Warning "$t is still not on PATH. Open a NEW terminal after the install and run:  cw doctor" }
}

# ------------------------------------------------------------------------------------------ 2. files
Write-Step 'Copying configuration'
New-Item -ItemType Directory -Force -Path $CwHome, $BinDir, (Join-Path $CwHome 'templates'), (Join-Path $CwHome 'defaults'), $WallDir, $LiveDir | Out-Null

foreach ($name in @('cw.ps1', 'start.ps1', 'theme.py', 'settings.ps1', 'settings-lib.ps1', 'live-guard.ps1')) {
    Copy-Item -LiteralPath (Join-Path $Root ('scripts\' + $name)) -Destination (Join-Path $CwHome $name) -Force
}
# an untouched copy of the shortcuts, so the settings window can offer "Reset to defaults"
Copy-Item -LiteralPath (Join-Path $Root 'config\whkd\whkdrc') -Destination (Join-Path $CwHome 'defaults\whkdrc') -Force
Copy-Item -LiteralPath (Join-Path $Root 'templates\yasb.styles.css.tmpl') -Destination (Join-Path $CwHome 'templates\yasb.styles.css.tmpl') -Force
Copy-Item -LiteralPath (Join-Path $Root 'templates\tacky-borders.config.yaml.tmpl') -Destination (Join-Path $CwHome 'templates\tacky-borders.config.yaml.tmpl') -Force

Install-ConfigFile (Join-Path $Root 'config\komorebi\komorebi.json') (Join-Path $KomorebiHome 'komorebi.json') 'komorebi\komorebi.json'
Install-ConfigFile (Join-Path $Root 'config\whkd\whkdrc')            (Join-Path $WhkdHome 'whkdrc')            'whkd\whkdrc'
Install-ConfigFile (Join-Path $Root 'config\yasb\config.yaml')       (Join-Path $YasbHome 'config.yaml')       'yasb\config.yaml'

# a hand-made YASB stylesheet is backed up before the generated one replaces it
$yasbCss = Join-Path $YasbHome 'styles.css'
if ((Test-Path -LiteralPath $yasbCss) -and -not (Select-String -LiteralPath $yasbCss -Pattern 'caelestia-win - YASB stylesheet' -Quiet)) {
    $back = Join-Path $BackupRoot 'yasb\styles.css'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $back) | Out-Null
    Copy-Item -LiteralPath $yasbCss -Destination $back -Force
    Write-Note "backed up your old YASB styles.css to $back"
}

# wallpapers: add the bundled one, never overwrite
$bundled = Join-Path $Root 'wallpapers\caelestia-default.jpg'
$defaultWall = Join-Path $WallDir 'caelestia-default.jpg'
if ((Test-Path -LiteralPath $bundled) -and -not (Test-Path -LiteralPath $defaultWall)) {
    Copy-Item -LiteralPath $bundled -Destination $defaultWall
}

# desktop PCs have no battery; drop the widget so the bar stays clean
if (-not (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)) {
    $yasbCfg = Join-Path $YasbHome 'config.yaml'
    # explicit UTF-8 in and out (no BOM): the config contains icon characters and Windows PowerShell 5.1 defaults to ANSI
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $kept = [System.IO.File]::ReadAllLines($yasbCfg, $utf8) | Where-Object { $_ -notmatch '^\s*-\s*"battery"\s*$' }
    [System.IO.File]::WriteAllLines($yasbCfg, [string[]]$kept, $utf8)
    Write-Note 'no battery found: removed the battery widget from the bar'
}

# Start menu entry for the settings window
try {
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $lnk = Join-Path $programs 'Caelestia Settings.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $CwHome 'settings.ps1') + '"'
    $sc.WorkingDirectory = $CwHome
    $sc.Description = 'caelestia-win settings: colours, wallpapers, gaps, bar and shortcuts'
    $sc.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll') + ',109'
    $sc.Save()
    Write-Note 'added "Caelestia Settings" to the Start menu (or press Alt+S)'
} catch { Write-Warning "Could not create the Start menu shortcut ($_). Open the settings with Alt+S or: cw settings" }

# the "cw" command
Set-Content -LiteralPath (Join-Path $BinDir 'cw.cmd') -Encoding ASCII -Value @(
    '@echo off',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\caelestia-win\cw.ps1" %*'
)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ((($userPath -split ';') -notcontains $BinDir)) {
    [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';')) + ';' + $BinDir), 'User')
}
$env:Path += ';' + $BinDir

[Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $KomorebiHome, 'User')
[Environment]::SetEnvironmentVariable('WHKD_CONFIG_HOME', $WhkdHome, 'User')
$env:KOMOREBI_CONFIG_HOME = $KomorebiHome
$env:WHKD_CONFIG_HOME = $WhkdHome

# ------------------------------------------------------------------------------------------ 3. python deps
Write-Step 'Installing the colour tool dependency (Pillow)'
try {
    if (Test-Tool 'py') { & py -3 -m pip install --user --quiet --disable-pip-version-check pillow }
    else { & python -m pip install --user --quiet --disable-pip-version-check pillow }
    if ($LASTEXITCODE -ne 0) { throw "pip exit code $LASTEXITCODE" }
    Write-Note 'Pillow ready.'
} catch {
    Write-Warning "Could not install Pillow ($_). Wallpaper colours need it: python -m pip install --user pillow"
}

# ------------------------------------------------------------------------------------------ 4. komorebi app rules
Write-Step 'Fetching komorebi application rules'
$ascCandidates = @((Join-Path $env:USERPROFILE 'applications.json'), (Join-Path $KomorebiHome 'applications.json'))
function Find-Asc { foreach ($c in $ascCandidates) { if (Test-Path -LiteralPath $c) { return $c } } return $null }
$ascPath = Find-Asc
if (-not $ascPath -and (Test-Tool 'komorebic')) {
    try { & komorebic fetch-asc 2>&1 | Out-Null } catch { Write-Note "komorebic fetch-asc failed: $_" }
    $ascPath = Find-Asc
}
if (-not $ascPath) {
    # fall back to downloading the file ourselves, with a timeout
    try {
        $dest = Join-Path $KomorebiHome 'applications.json'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/LGUG2Z/komorebi-application-specific-configuration/master/applications.json' -OutFile $dest -UseBasicParsing -TimeoutSec 30
        $ascPath = $dest
    } catch { Write-Note "direct download failed: $_" }
}
$kj = Join-Path $KomorebiHome 'komorebi.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($kj, $utf8)
if ($ascPath) {
    $pathJson = $ascPath.Replace('\', '/')
    $text = $text -replace '(?m)^(\s*"app_specific_configuration_path":\s*)".*?"', ('$1"' + $pathJson + '"')
    [System.IO.File]::WriteAllText($kj, $text, $utf8)
    Write-Note 'application rules ready.'
} else {
    Write-Warning 'applications.json could not be downloaded (is github.com blocked on your network?). Continuing without per-app rules; run "komorebic fetch-asc" later.'
    $text = $text -replace '(?m)^\s*"app_specific_configuration_path".*\r?\n', ''
    [System.IO.File]::WriteAllText($kj, $text, $utf8)
}

# ------------------------------------------------------------------------------------------ 4b. rounded gradient borders
if (-not $SkipBorders) {
    Write-Step 'Adding rounded gradient window borders (tacky-borders)'
    $tackyExe = Join-Path $BinDir 'tacky-borders.exe'
    if (-not (Test-Path -LiteralPath $tackyExe)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $hdr = @{ 'User-Agent' = 'caelestia-win' }
            # Look through the last few releases (the newest one may ship no usable file) and accept .exe, .zip or .msi.
            # Piping through ForEach-Object unrolls the JSON array (Windows PowerShell 5.1 otherwise returns it as ONE object,
            # which made every "$r.draft" test look true and skipped all releases).
            $releases = @(Invoke-RestMethod -Uri 'https://api.github.com/repos/lukeyou05/tacky-borders/releases?per_page=10' -Headers $hdr -TimeoutSec 30 | ForEach-Object { $_ })
            $asset = $null
            $guessInstalled = $false
            $seen = New-Object System.Collections.Generic.List[string]
            foreach ($r in $releases) {
                if ($r.draft -eq $true) { continue }
                $names = @($r.assets | ForEach-Object { $_.name })
                $seen.Add(("{0}: {1}" -f $r.tag_name, $(if ($names.Count) { $names -join ', ' } else { 'no files' })))
                foreach ($pattern in @('*.exe', '*.zip', '*.msi')) {
                    $asset = $r.assets | Where-Object { $_.name -like $pattern -and $_.name -notlike '*arm64*' -and $_.name -notlike '*source*' } | Select-Object -First 1
                    if ($asset) { break }
                }
                if ($asset) { break }
            }
            if (-not $asset) {
                # last resort: the conventional "latest release" file name, accepted only if it really is a Windows program
                $guess = 'https://github.com/lukeyou05/tacky-borders/releases/latest/download/tacky-borders.exe'
                $gtmp = Join-Path ([IO.Path]::GetTempPath()) 'cw-tacky-guess.exe'
                $okGuess = $false
                try {
                    $oldPp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                    try { Invoke-WebRequest -Uri $guess -OutFile $gtmp -UseBasicParsing -TimeoutSec 120 } finally { $ProgressPreference = $oldPp }
                    $head = [IO.File]::ReadAllBytes($gtmp) | Select-Object -First 2
                    if ($head.Count -eq 2 -and $head[0] -eq 0x4D -and $head[1] -eq 0x5A) { $okGuess = $true }
                } catch { }
                if ($okGuess) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tackyExe) | Out-Null
                    Copy-Item -LiteralPath $gtmp -Destination $tackyExe -Force
                    Remove-Item -LiteralPath $gtmp -Force -ErrorAction SilentlyContinue
                    Write-Note 'installed tacky-borders.exe from the latest release'
                    $guessInstalled = $true
                }
                Remove-Item -LiteralPath $gtmp -Force -ErrorAction SilentlyContinue
                if (-not $guessInstalled) { throw ('no .exe, .zip or .msi found. Releases seen -> ' + ($seen -join ' | ')) }
            }
            if (-not $guessInstalled) {
            Write-Note ('downloading ' + $asset.name + ' (up to 2 minutes) ...')
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('cw-tacky-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            $dl = Join-Path $tmp $asset.name
            $oldProgress = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            try { Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dl -UseBasicParsing -TimeoutSec 120 } finally { $ProgressPreference = $oldProgress }
            $unpack = Join-Path $tmp 'unpacked'
            New-Item -ItemType Directory -Force -Path $unpack | Out-Null
            switch -Wildcard ($asset.name.ToLower()) {
                '*.exe' { Copy-Item -LiteralPath $dl -Destination (Join-Path $unpack 'tacky-borders.exe') -Force }
                '*.zip' { Expand-Archive -LiteralPath $dl -DestinationPath $unpack -Force }
                '*.msi' {
                    # administrative extract: unpacks the files without installing and without admin rights
                    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/a', "`"$dl`"", '/qn', "TARGETDIR=`"$unpack`"") -Wait -PassThru
                    if ($p.ExitCode -ne 0) { throw "msiexec could not unpack the installer (exit code $($p.ExitCode))" }
                }
            }
            $found = Get-ChildItem -LiteralPath $unpack -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '*tacky*' } | Select-Object -First 1
            if (-not $found) { throw "downloaded $($asset.name) but found no tacky-borders .exe inside it" }
            Copy-Item -LiteralPath $found.FullName -Destination $tackyExe -Force
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            Write-Note ('installed ' + $asset.name + ' from github.com/lukeyou05/tacky-borders')
            }
        } catch {
            if (Test-Path -LiteralPath $tackyExe) { Remove-Item -LiteralPath $tackyExe -Force }
            Write-Warning "Could not set up tacky-borders ($_). Plain komorebi borders will be used. Get it from https://github.com/lukeyou05/tacky-borders/releases and save the .exe as $tackyExe, then run: cw theme"
        }
    } else { Write-Note 'already downloaded.' }
    $tackyCfg = Join-Path $HOME '.config\tacky-borders\config.yaml'
    if ((Test-Path -LiteralPath $tackyExe) -and (Test-Path -LiteralPath $tackyCfg) -and -not (Select-String -LiteralPath $tackyCfg -Pattern 'caelestia-win - tacky-borders config' -Quiet)) {
        $back = Join-Path $BackupRoot 'tacky-borders\config.yaml'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $back) | Out-Null
        Copy-Item -LiteralPath $tackyCfg -Destination $back -Force
        Write-Note "backed up your old tacky-borders config to $back"
    }
}

# ------------------------------------------------------------------------------------------ 5. colours
Write-Step 'Generating colours from your wallpaper'
$cw = Join-Path $CwHome 'cw.ps1'
$image = $null
if ($SetWallpaper -and (Test-Path -LiteralPath $defaultWall)) {
    & $cw 'wallpaper' 'set' $defaultWall
} else {
    $current = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
    if ($current -and (Test-Path -LiteralPath $current)) { $image = $current }
    elseif (Test-Path -LiteralPath $defaultWall) { $image = $defaultWall }
    try { & $cw 'theme' $image } catch { Write-Warning "Colour generation failed: $_  (the bar will use the built-in default style until you run: cw theme)" }
}

# ------------------------------------------------------------------------------------------ 6. autostart + launch
Write-Step 'Enabling autostart and starting everything'
try { & $cw 'autostart' 'on' } catch { Write-Warning "Could not set up start at sign-in: $_  (try: cw autostart on)" }

# our own sign-in script starts the bar (and retries), so YASB's separate autostart entry is switched off to avoid a double start
if (Test-Tool 'yasbc') {
    try { & yasbc disable-autostart 2>$null | Out-Null } catch { }
}
try { & $cw 'start' } catch { Write-Warning "Could not start the stack automatically: $_  (try: cw doctor)" }

$flow = Join-Path $env:LOCALAPPDATA 'FlowLauncher\Flow.Launcher.exe'
if ((-not $SkipLauncher) -and (Test-Path -LiteralPath $flow)) { Start-Process -FilePath $flow }

if (-not $KeepTaskbar) {
    Write-Step 'Hiding the Windows taskbar (your running apps now live in the bar; Explorer restarts once)'
    try { & $cw 'taskbar' 'hide' } catch { Write-Warning "Could not hide the taskbar: $_  (Settings > Personalization > Taskbar > Taskbar behaviors > Automatically hide)" }
}

# ------------------------------------------------------------------------------------------ done
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'Try these:'
Write-Host '  Alt+Enter          terminal            Alt+Space   launcher (Flow Launcher)'
Write-Host '  Alt+H/J/K/L        focus windows       Alt+Shift+H/J/K/L   move windows'
Write-Host '  Alt+1..9           workspaces          Alt+Shift+1..9      send window to workspace'
Write-Host '  Alt+S              SETTINGS WINDOW (colours, wallpapers, gaps, bar, shortcuts)'
Write-Host '  Alt+W              next wallpaper + new colours'
Write-Host '  Alt+Shift+T        dark / light        Alt+Q       close window'
Write-Host '  cw preset ocean    pick a colour theme (cw preset auto follows the wallpaper)'
Write-Host '  cw live install    add animated (video / GIF) wallpapers'
Write-Host ''
Write-Host 'If anything looks wrong, open a NEW terminal and run:  cw doctor'
Write-Host 'Open a NEW terminal to use the "cw" command. Sign out and in once so the Nerd Font is picked up by every app.'
if (Test-Path -LiteralPath $BackupRoot) { Write-Host ("Your old configs were saved in " + $BackupRoot) }
Write-Host ("Full log: " + $LogFile)
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('INSTALL STOPPED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('At: ' + $_.InvocationInfo.PositionMessage)
    Write-Host ("Log saved to: " + $LogFile + "  (send it along if you ask for help)")
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    if (-not $NoPause -and [Environment]::UserInteractive) { [void](Read-Host 'Press Enter to close this window') }
}
if ($script:failed) { exit 1 }
