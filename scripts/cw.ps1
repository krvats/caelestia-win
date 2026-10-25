<#
.SYNOPSIS
    cw - control script for caelestia-win (the Windows counterpart of Caelestia's `caelestia` CLI).

.DESCRIPTION
    cw wallpaper next|prev|random|set <file>|current
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

$env:KOMOREBI_CONFIG_HOME = $KomorebiHome
$env:WHKD_CONFIG_HOME     = $WhkdHome

# ----------------------------------------------------------------------------- state

function Get-State {
    $s = [ordered]@{ wallpaper = ''; mode = 'dark'; variant = 'tonal'; preset = ''; taskbarHidden = $false }
    if (Test-Path -LiteralPath $StateFile) {
        try {
            $j = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
            foreach ($k in @('wallpaper', 'mode', 'variant', 'preset')) {
                if ($j.$k) { $s[$k] = [string]$j.$k }
            }
            if ($j.taskbarHidden -eq $true) { $s['taskbarHidden'] = $true }
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

    $full = Set-Wallpaper $target
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
}

function Invoke-Stop {
    $ErrorActionPreference = 'SilentlyContinue'
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
    Check 'komorebi running'    ([bool](Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) 'run: cw start'
    Check 'YASB running'        ([bool](Get-Process -Name 'yasb' -ErrorAction SilentlyContinue))     'run: cw start'
    if (Get-TackyExe) {
        Check 'tacky-borders running' ([bool](Get-Process -Name 'tacky-borders' -ErrorAction SilentlyContinue)) 'run: cw start'
    } else {
        Write-Host '  [info] tacky-borders (rounded gradient borders) is not installed; komorebi draws plain borders. Re-run Install.ps1 to add it.'
    }

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
  WINDOWS         Alt+Q close   Alt+M minimise   Alt+T float/tile   Alt+F maximise   Alt+Shift+F monocle
  FOCUS           Alt+H J K L  (left down up right)
  MOVE            Alt+Shift+H J K L     Alt+Shift+Enter  promote to main
  RESIZE          Alt+= / Alt+-  wider/narrower     Alt+Shift+= / -  taller/shorter
  LAYOUT          Alt+X flip horizontal   Alt+Y flip vertical
  TABS (STACKS)   Alt+Arrows stack   Alt+;  unstack   Alt+[ ]  cycle tabs
  WORKSPACES      Alt+1..9 go   Alt+Shift+1..9 send window there
  THEME           Alt+W next wallpaper   Alt+Shift+W random   Alt+Shift+T dark/light
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
