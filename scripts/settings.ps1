<#
.SYNOPSIS
    caelestia-win settings window: change colours, wallpapers (pictures and animated), gaps, borders, the bar
    and keyboard shortcuts with buttons, so nobody has to open a file or a terminal.

.DESCRIPTION
    Open it with Alt+S, from the Start menu ("Caelestia Settings") or with:  cw settings
    Every button edits the same files the installer made (komorebi.json, whkdrc, YASB config.yaml) or calls the
    matching "cw" command, and applies the result straight away. A copy of each file is kept in
    ~\.config\caelestia-win\backup-settings before it is changed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$CwHome       = Join-Path $HOME '.config\caelestia-win'
$CwScript     = Join-Path $CwHome 'cw.ps1'
$StateFile    = Join-Path $CwHome 'state.json'
$KomorebiHome = Join-Path $HOME '.config\komorebi'
$WhkdHome     = Join-Path $HOME '.config\whkd'
$YasbHome     = Join-Path $HOME '.config\yasb'
$TackyHome    = Join-Path $HOME '.config\tacky-borders'
$WallDir      = Join-Path $HOME 'Pictures\Wallpapers'
$LiveDir      = Join-Path $WallDir 'Animated'
$ThumbDir     = Join-Path $CwHome 'thumbs'
$BackupDir    = Join-Path $CwHome 'backup-settings'
$env:KOMOREBI_CONFIG_HOME = $KomorebiHome
$env:WHKD_CONFIG_HOME     = $WhkdHome
# a window opened before the installer finished has an old PATH; read the current one so komorebic and whkd are found
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

. (Join-Path $PSScriptRoot 'settings-lib.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------------------------------------------------------------------- state and colours

function Get-StateObject {
    $s = @{ wallpaper = ''; mode = 'dark'; variant = 'tonal'; preset = ''; live = ''; liveVolume = 0
            livePauseBattery = $true; livePauseFullscreen = $true; taskbarHidden = $false }
    if (Test-Path -LiteralPath $StateFile) {
        try {
            $j = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
            foreach ($k in @('wallpaper', 'mode', 'variant', 'preset', 'live')) { if ($j.$k) { $s[$k] = [string]$j.$k } }
            if ($null -ne $j.liveVolume) { $s['liveVolume'] = [int]$j.liveVolume }
            if ($j.livePauseBattery -eq $false) { $s['livePauseBattery'] = $false }
            if ($j.livePauseFullscreen -eq $false) { $s['livePauseFullscreen'] = $false }
            if ($j.taskbarHidden -eq $true) { $s['taskbarHidden'] = $true }
        } catch { }
    }
    return $s
}

function Get-PaletteColours {
    $c = @{}
    $f = Join-Path $CwHome 'colors.json'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = (Read-TextFile $f) | ConvertFrom-Json
            foreach ($p in $j.colors.PSObject.Properties) { $c[$p.Name] = [string]$p.Value }
        } catch { }
    }
    return $c
}

$pal = Get-PaletteColours
$ColBg      = Get-ColourFromHex $pal['surface']                   '#141218'
$ColCard    = Get-ColourFromHex $pal['surface_container']         '#211f26'
$ColCard2   = Get-ColourFromHex $pal['surface_container_highest'] '#36343b'
$ColText    = Get-ColourFromHex $pal['on_surface']                '#e6e0e9'
$ColMuted   = Get-ColourFromHex $pal['on_surface_variant']        '#cac4d0'
$ColAccent  = Get-ColourFromHex $pal['primary']                   '#cfbcff'
$ColOnAcc   = Get-ColourFromHex $pal['on_primary']                '#381e72'
$ColLine    = Get-ColourFromHex $pal['outline_variant']           '#49454f'

$FontNormal = New-Object System.Drawing.Font('Segoe UI', 10)
$FontBold   = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$FontTitle  = New-Object System.Drawing.Font('Segoe UI Semibold', 16)

# ----------------------------------------------------------------------------- running cw and other helpers

function ConvertTo-QuotedArg([string]$A) {
    if ($A -match '[\s"]') { return '"' + ($A -replace '"', '\"') + '"' }
    return $A
}

$script:busy = $false

function Set-Status([string]$Text, [bool]$IsError = $false) {
    $script:lblStatus.Text = $Text
    if ($IsError) { $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 140) }
    else { $script:lblStatus.ForeColor = $ColMuted }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-Cw([string[]]$CwArgs) {
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (ConvertTo-QuotedArg $CwScript))
    foreach ($a in $CwArgs) { $argList += (ConvertTo-QuotedArg $a) }
    $script:busy = $true
    $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $script:nav.Enabled = $false
    $script:content.Enabled = $false
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $null = $p.Handle   # keeps ExitCode readable on Windows PowerShell 5.1
        while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 60 }
        $p.WaitForExit()
        $text = ''
        foreach ($f in @($outFile, $errFile)) {
            if (Test-Path -LiteralPath $f) { $text += (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue) }
        }
        return [pscustomobject]@{ Ok = ($p.ExitCode -eq 0); Text = ([string]$text).Trim() }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        $script:nav.Enabled = $true
        $script:content.Enabled = $true
        $script:form.Cursor = [System.Windows.Forms.Cursors]::Default
        $script:busy = $false
    }
}

function Invoke-CwStatus([string[]]$CwArgs, [string]$Done) {
    Set-Status ('working ...')
    $r = Invoke-Cw $CwArgs
    if ($r.Ok) { Set-Status $Done }
    else {
        $line = ($r.Text -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        if (-not $line) { $line = 'something went wrong; run  cw doctor' }
        Set-Status ('Problem: ' + $line) $true
    }
    return $r
}

function Backup-ConfigFile([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dest = Join-Path $BackupDir $Label
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $dest -Force
}

function Open-Folder([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $Path + '"') | Out-Null
}

function Start-VisibleCw([string]$Line) {
    $cmd = '& "' + $CwScript + '" ' + $Line + '; Write-Host ""; Read-Host "Press Enter to close"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ('"' + ($cmd -replace '"', '\"') + '"')) | Out-Null
}

# ----------------------------------------------------------------------------- small UI builders

function Set-ControlStyle($Ctrl) {
    foreach ($c in $Ctrl.Controls) {
        if ($c -is [System.Windows.Forms.Button]) {
            $c.FlatStyle = 'Flat'
            $c.FlatAppearance.BorderColor = $ColLine
            if ($c.Tag -eq 'primary') { $c.BackColor = $ColAccent; $c.ForeColor = $ColOnAcc }
            else { $c.BackColor = $ColCard2; $c.ForeColor = $ColText }
            $c.UseVisualStyleBackColor = $false
            $c.Cursor = [System.Windows.Forms.Cursors]::Hand
        }
        elseif ($c -is [System.Windows.Forms.ComboBox]) { $c.FlatStyle = 'Flat'; $c.BackColor = $ColCard2; $c.ForeColor = $ColText }
        elseif ($c -is [System.Windows.Forms.NumericUpDown]) { $c.BackColor = $ColCard2; $c.ForeColor = $ColText }
        elseif ($c -is [System.Windows.Forms.CheckedListBox]) { $c.BackColor = $ColCard; $c.ForeColor = $ColText; $c.BorderStyle = 'None' }
        elseif ($c -is [System.Windows.Forms.ListView]) { $c.BackColor = $ColCard; $c.ForeColor = $ColText; $c.BorderStyle = 'None' }
        elseif ($c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton] -or $c -is [System.Windows.Forms.Label]) {
            if ($c.Tag -eq 'muted') { $c.ForeColor = $ColMuted } else { $c.ForeColor = $ColText }
            $c.BackColor = [System.Drawing.Color]::Transparent
        }
        if ($c.Controls.Count -gt 0 -and -not ($c -is [System.Windows.Forms.DataGridView])) { Set-ControlStyle $c }
    }
}

function New-Page {
    $p = New-Object System.Windows.Forms.FlowLayoutPanel
    $p.Dock = 'Fill'
    $p.FlowDirection = 'TopDown'
    $p.WrapContents = $false
    $p.AutoScroll = $true
    $p.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
    $p.BackColor = $ColBg
    $p.Visible = $false
    return $p
}

function New-Heading([string]$Text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = $FontTitle
    $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    return $l
}

function New-Note([string]$Text, [int]$Width = 640) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Tag = 'muted'
    $l.AutoSize = $false
    $l.Width = $Width
    $lines = [Math]::Ceiling(($Text.Length * 7.2) / $Width) + ($Text.Split("`n").Count - 1)
    $l.Height = [int]([Math]::Max(1, $lines) * 20 + 4)
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    return $l
}

function New-Row {
    $r = New-Object System.Windows.Forms.FlowLayoutPanel
    $r.FlowDirection = 'LeftToRight'
    $r.WrapContents = $true
    $r.AutoSize = $true
    $r.AutoSizeMode = 'GrowAndShrink'
    $r.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $r.BackColor = [System.Drawing.Color]::Transparent
    return $r
}

function New-FieldLabel([string]$Text, [int]$Width = 190) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Width = $Width
    $l.Height = 28
    $l.TextAlign = 'MiddleLeft'
    return $l
}

function New-Btn([string]$Text, [int]$Width, [scriptblock]$OnClick, [bool]$Primary = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = $Width
    $b.Height = 32
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    if ($Primary) { $b.Tag = 'primary'; $b.Font = $FontBold }
    $b.Add_Click($OnClick)
    return $b
}

function New-Check([string]$Text, [bool]$Checked, [int]$Width = 420) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Checked = $Checked
    $c.Width = $Width
    $c.Height = 26
    return $c
}

function New-Number([int]$Min, [int]$Max, [int]$Value) {
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Minimum = $Min
    $n.Maximum = $Max
    $v = [Math]::Max($Min, [Math]::Min($Max, $Value))
    $n.Value = $v
    $n.Width = 80
    return $n
}

function New-Combo([string[]]$Items, [string]$Selected, [int]$Width = 240) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    $c.Width = $Width
    foreach ($i in $Items) { [void]$c.Items.Add($i) }
    $idx = [Array]::IndexOf($Items, $Selected)
    if ($idx -lt 0) { $idx = 0 }
    if ($c.Items.Count -gt 0) { $c.SelectedIndex = $idx }
    return $c
}

# ----------------------------------------------------------------------------- the window

$script:form = New-Object System.Windows.Forms.Form
$form.Text = 'Caelestia Settings'
$form.Size = New-Object System.Drawing.Size(980, 700)
$form.MinimumSize = New-Object System.Drawing.Size(860, 600)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $ColBg
$form.ForeColor = $ColText
$form.Font = $FontNormal

$script:lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Dock = 'Bottom'
$lblStatus.Height = 30
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
$lblStatus.BackColor = $ColCard
$lblStatus.ForeColor = $ColMuted
$lblStatus.Text = 'Ready. Changes apply straight away.'

$script:nav = New-Object System.Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Left'
$nav.Width = 190
$nav.FlowDirection = 'TopDown'
$nav.WrapContents = $false
$nav.Padding = New-Object System.Windows.Forms.Padding(12, 16, 12, 12)
$nav.BackColor = $ColCard

$script:content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = $ColBg

$form.Controls.Add($content)
$form.Controls.Add($nav)
$form.Controls.Add($lblStatus)

$script:pages = @{}
$script:navButtons = @{}

function Show-Page([string]$Name) {
    foreach ($k in $script:pages.Keys) { $script:pages[$k].Visible = ($k -eq $Name) }
    foreach ($k in $script:navButtons.Keys) {
        if ($k -eq $Name) { $script:navButtons[$k].BackColor = $ColAccent; $script:navButtons[$k].ForeColor = $ColOnAcc }
        else { $script:navButtons[$k].BackColor = $ColCard; $script:navButtons[$k].ForeColor = $ColText }
    }
    if ($Name -eq 'Wallpaper') { Update-WallpaperPage }
}

$navTitle = New-Object System.Windows.Forms.Label
$navTitle.Text = 'Caelestia'
$navTitle.Font = $FontTitle
$navTitle.ForeColor = $ColAccent
$navTitle.AutoSize = $true
$navTitle.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 14)
$nav.Controls.Add($navTitle)

foreach ($name in @('Colours', 'Wallpaper', 'Windows', 'Bar', 'Shortcuts', 'System')) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $name
    $b.Tag = $name
    $b.Width = 164
    $b.Height = 40
    $b.TextAlign = 'MiddleLeft'
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $ColCard
    $b.ForeColor = $ColText
    $b.UseVisualStyleBackColor = $false
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click({ param($sender, $e) Show-Page ([string]$sender.Tag) })
    $nav.Controls.Add($b)
    $script:navButtons[$name] = $b
}

# ============================================================================= page: Colours

$pgColours = New-Page
$pgColours.Controls.Add((New-Heading 'Colours'))
$pgColours.Controls.Add((New-Note 'Pick a theme, or let the colours follow your wallpaper. The bar, window borders and terminal all change together.'))

$themeSeeds   = @('lavender', 'rose', 'sunset', 'amber', 'forest', 'mint', 'sky', 'ocean', 'orchid')
$themeSchemes = @('catppuccin', 'gruvbox', 'nord', 'rosepine', 'tokyonight', 'dracula', 'everforest', 'onedark', 'solarized')
$themeItems   = @('auto  (follow the wallpaper)') + $themeSeeds + $themeSchemes
$stNow = Get-StateObject
$themeSel = $themeItems[0]
if ($stNow['preset'] -and ($themeItems -contains $stNow['preset'])) { $themeSel = $stNow['preset'] }

$rowTheme = New-Row
$rowTheme.Controls.Add((New-FieldLabel 'Theme'))
$script:cbTheme = New-Combo $themeItems $themeSel 260
$rowTheme.Controls.Add($cbTheme)
$pgColours.Controls.Add($rowTheme)

$rowMode = New-Row
$rowMode.Controls.Add((New-FieldLabel 'Mode'))
$script:rbDark = New-Object System.Windows.Forms.RadioButton
$rbDark.Text = 'Dark'; $rbDark.Width = 90; $rbDark.Height = 28
$script:rbLight = New-Object System.Windows.Forms.RadioButton
$rbLight.Text = 'Light'; $rbLight.Width = 90; $rbLight.Height = 28
if ($stNow['mode'] -eq 'light') { $rbLight.Checked = $true } else { $rbDark.Checked = $true }
$rowMode.Controls.Add($rbDark)
$rowMode.Controls.Add($rbLight)
$pgColours.Controls.Add($rowMode)

$rowVariant = New-Row
$rowVariant.Controls.Add((New-FieldLabel 'Colour style'))
$script:cbVariant = New-Combo @('tonal', 'vibrant', 'muted', 'mono') $stNow['variant'] 260
$rowVariant.Controls.Add($cbVariant)
$pgColours.Controls.Add($rowVariant)
$pgColours.Controls.Add((New-Note 'Colour style only applies to "auto" and the nine colour themes; the community themes (catppuccin ... solarized) have fixed colours.'))

$pgColours.Controls.Add((New-Btn 'Apply colours' 150 {
    $st = Get-StateObject
    $sel = [string]$script:cbTheme.SelectedItem
    $wantPreset = ''
    if ($sel -and -not $sel.StartsWith('auto')) { $wantPreset = $sel }
    $wantMode = 'dark'
    if ($script:rbLight.Checked) { $wantMode = 'light' }
    $wantVariant = [string]$script:cbVariant.SelectedItem
    $ok = $true
    if ($wantMode -ne $st['mode']) { $r = Invoke-CwStatus @('scheme', $wantMode) 'mode changed'; if (-not $r.Ok) { $ok = $false } }
    if ($ok -and ($wantVariant -ne $st['variant'])) { $r = Invoke-CwStatus @('variant', $wantVariant) 'colour style changed'; if (-not $r.Ok) { $ok = $false } }
    if ($ok -and ($wantPreset -ne $st['preset'])) {
        $arg = $wantPreset
        if (-not $arg) { $arg = 'auto' }
        $r = Invoke-CwStatus @('preset', $arg) ('theme: ' + $arg)
        if (-not $r.Ok) { $ok = $false }
    }
    if ($ok) { Set-Status 'Colours applied.' }
    Update-Swatches
} $true))

$pgColours.Controls.Add((New-Note ''))
$swatchTitle = New-Object System.Windows.Forms.Label
$swatchTitle.Text = 'Current palette'
$swatchTitle.Font = $FontBold
$swatchTitle.AutoSize = $true
$pgColours.Controls.Add($swatchTitle)
$script:swatchPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$swatchPanel.AutoSize = $true
$swatchPanel.MaximumSize = New-Object System.Drawing.Size(700, 0)
$swatchPanel.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
$pgColours.Controls.Add($swatchPanel)

function Update-Swatches {
    $script:swatchPanel.Controls.Clear()
    $p = Get-PaletteColours
    foreach ($role in @('primary', 'secondary', 'tertiary', 'primary_container', 'surface_container_highest', 'surface', 'on_surface', 'outline')) {
        $box = New-Object System.Windows.Forms.Panel
        $box.Width = 78
        $box.Height = 46
        $box.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
        $box.BackColor = Get-ColourFromHex $p[$role] '#808080'
        $tip = New-Object System.Windows.Forms.ToolTip
        $tip.SetToolTip($box, ($role + '  ' + $p[$role]))
        $script:swatchPanel.Controls.Add($box)
    }
}

$script:pages['Colours'] = $pgColours
$content.Controls.Add($pgColours)

# ============================================================================= page: Wallpaper

$pgWall = New-Page
$pgWall.Controls.Add((New-Heading 'Wallpaper'))
$pgWall.Controls.Add((New-Note 'Pictures recolour the whole desktop. Animated wallpapers (video or GIF) play behind your windows; the colours come from a frame of the video.'))

$script:wallMode = 'pictures'

$rowSwitch = New-Row
$script:btnPictures = New-Btn 'Pictures' 120 { $script:wallMode = 'pictures'; Update-WallpaperPage } $true
$script:btnAnimated = New-Btn 'Animated' 120 { $script:wallMode = 'animated'; Update-WallpaperPage }
$rowSwitch.Controls.Add($btnPictures)
$rowSwitch.Controls.Add($btnAnimated)
$pgWall.Controls.Add($rowSwitch)

$script:imgList = New-Object System.Windows.Forms.ImageList
$imgList.ImageSize = New-Object System.Drawing.Size(160, 90)
$imgList.ColorDepth = 'Depth32Bit'

$script:lvWall = New-Object System.Windows.Forms.ListView
$lvWall.View = 'LargeIcon'
$lvWall.LargeImageList = $imgList
$lvWall.MultiSelect = $false
$lvWall.HideSelection = $false
$lvWall.Width = 700
$lvWall.Height = 300
$lvWall.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$pgWall.Controls.Add($lvWall)

$rowWallBtns = New-Row
$rowWallBtns.Controls.Add((New-Btn 'Set as wallpaper' 150 { Invoke-WallpaperApply } $true))
$rowWallBtns.Controls.Add((New-Btn 'Next' 70 { Invoke-WallpaperStep 'next' }))
$rowWallBtns.Controls.Add((New-Btn 'Random' 80 { Invoke-WallpaperStep 'random' }))
$rowWallBtns.Controls.Add((New-Btn 'Add files ...' 110 { Add-WallpaperFiles }))
$rowWallBtns.Controls.Add((New-Btn 'Open folder' 110 {
    if ($script:wallMode -eq 'animated') { Open-Folder $LiveDir } else { Open-Folder $WallDir }
}))
$pgWall.Controls.Add($rowWallBtns)

$script:chkPreview = New-Check 'Preview while I click through the list' $false 380
$pgWall.Controls.Add($chkPreview)

$script:panelAnim = New-Object System.Windows.Forms.FlowLayoutPanel
$panelAnim.FlowDirection = 'TopDown'
$panelAnim.WrapContents = $false
$panelAnim.AutoSize = $true
$panelAnim.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

$script:lblAnimMissing = New-Note 'Animated wallpapers need Lively Wallpaper (free) and FFmpeg. One click installs both.' 640
$panelAnim.Controls.Add($lblAnimMissing)
$script:btnInstallLive = New-Btn 'Install animated wallpaper support' 280 { Start-VisibleCw 'live install' } $true
$panelAnim.Controls.Add($btnInstallLive)

$script:chkBattery = New-Check 'Pause the animation on battery power' $true 420
$script:chkFullscreen = New-Check 'Pause the animation when an app is fullscreen' $true 420
$panelAnim.Controls.Add($chkBattery)
$panelAnim.Controls.Add($chkFullscreen)
$script:chkBattery.Add_Click({
    $v = 'off'; if ($script:chkBattery.Checked) { $v = 'on' }
    [void](Invoke-CwStatus @('live', 'rules', 'battery', $v) ('pause on battery: ' + $v))
})
$script:chkFullscreen.Add_Click({
    $v = 'off'; if ($script:chkFullscreen.Checked) { $v = 'on' }
    [void](Invoke-CwStatus @('live', 'rules', 'fullscreen', $v) ('pause when fullscreen: ' + $v))
})

$rowVol = New-Row
$rowVol.Controls.Add((New-FieldLabel 'Volume' 70))
$script:tbVolume = New-Object System.Windows.Forms.TrackBar
$tbVolume.Minimum = 0; $tbVolume.Maximum = 100; $tbVolume.TickFrequency = 25; $tbVolume.Width = 240
$script:lblVol = New-Object System.Windows.Forms.Label
$lblVol.Width = 50; $lblVol.Height = 28; $lblVol.TextAlign = 'MiddleLeft'
$tbVolume.Add_MouseUp({ [void](Invoke-CwStatus @('live', 'volume', [string]$script:tbVolume.Value) ('volume ' + $script:tbVolume.Value)) })
$tbVolume.Add_ValueChanged({ $script:lblVol.Text = [string]$script:tbVolume.Value })
$rowVol.Controls.Add($tbVolume)
$rowVol.Controls.Add($lblVol)
$panelAnim.Controls.Add($rowVol)

$rowAnimBtns = New-Row
$rowAnimBtns.Controls.Add((New-Btn 'Stop animated wallpaper' 200 {
    $r = Invoke-CwStatus @('live', 'stop') 'back to the picture wallpaper'
    Update-Swatches
}))
$rowAnimBtns.Controls.Add((New-Btn 'Pause / resume' 130 {
    $script:animPaused = -not $script:animPaused
    if ($script:animPaused) { [void](Invoke-CwStatus @('live', 'pause') 'paused') } else { [void](Invoke-CwStatus @('live', 'resume') 'playing') }
}))
$rowAnimBtns.Controls.Add((New-Btn 'Lively settings (hardware decoding) ...' 280 { [void](Invoke-CwStatus @('live', 'settings') 'opened Lively; hardware decoding is under Settings > Performance') }))
$panelAnim.Controls.Add($rowAnimBtns)
$pgWall.Controls.Add($panelAnim)

$script:animPaused = $false
$script:loading = $false

function New-Thumb([string]$Path, [bool]$IsPicture) {
    $bmp = New-Object System.Drawing.Bitmap 160, 90
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear($ColCard2)
        $src = $null
        try { $src = [System.Drawing.Image]::FromFile($Path) } catch { $src = $null }
        if ($src) {
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $sw = $src.Width; $sh = $src.Height
                $target = 160.0 / 90.0
                if (($sw / $sh) -gt $target) {
                    $cw = [int]($sh * $target); $cx = [int](($sw - $cw) / 2)
                    $srcRect = New-Object System.Drawing.Rectangle $cx, 0, $cw, $sh
                } else {
                    $ch = [int]($sw / $target); $cy = [int](($sh - $ch) / 2)
                    $srcRect = New-Object System.Drawing.Rectangle 0, $cy, $sw, $ch
                }
                $dst = New-Object System.Drawing.Rectangle 0, 0, 160, 90
                $g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $src.Dispose() }
        } else {
            $brush = New-Object System.Drawing.SolidBrush $ColMuted
            $g.DrawString([string][char]0x25B6, $FontTitle, $brush, 66, 28)
            $brush.Dispose()
        }
    } finally { $g.Dispose() }
    return $bmp
}

function Get-WallpaperFiles {
    if ($script:wallMode -eq 'animated') {
        if (-not (Test-Path -LiteralPath $LiveDir)) { return @() }
        return @(Get-ChildItem -LiteralPath $LiveDir -File | Where-Object { $_.Extension -match '^\.(mp4|webm|mkv|gif|mov|avi)$' } | Sort-Object Name)
    }
    if (-not (Test-Path -LiteralPath $WallDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $WallDir -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' } | Sort-Object Name)
}

function Update-WallpaperPage {
    $animated = ($script:wallMode -eq 'animated')
    if ($animated) { $script:btnAnimated.BackColor = $ColAccent; $script:btnAnimated.ForeColor = $ColOnAcc; $script:btnPictures.BackColor = $ColCard2; $script:btnPictures.ForeColor = $ColText }
    else { $script:btnPictures.BackColor = $ColAccent; $script:btnPictures.ForeColor = $ColOnAcc; $script:btnAnimated.BackColor = $ColCard2; $script:btnAnimated.ForeColor = $ColText }
    $script:panelAnim.Visible = $animated

    $st = Get-StateObject
    $haveLively = $false
    foreach ($p in @((Join-Path $env:LOCALAPPDATA 'Programs\Lively Wallpaper\Lively.exe'), (Join-Path $env:ProgramFiles 'Lively Wallpaper\Lively.exe'))) { if (Test-Path -LiteralPath $p) { $haveLively = $true } }
    $script:lblAnimMissing.Visible = -not $haveLively
    $script:btnInstallLive.Visible = -not $haveLively
    $script:chkBattery.Checked = [bool]$st['livePauseBattery']
    $script:chkFullscreen.Checked = [bool]$st['livePauseFullscreen']
    $script:tbVolume.Value = [Math]::Max(0, [Math]::Min(100, [int]$st['liveVolume']))
    $script:lblVol.Text = [string]$script:tbVolume.Value

    $files = Get-WallpaperFiles
    if ($animated -and $files.Count -gt 0) {
        # thumbnails come from FFmpeg frames made by "cw live thumbs"; make any that are missing
        $missing = $false
        foreach ($f in $files) { if (-not (Find-LiveThumb $f.FullName)) { $missing = $true } }
        if ($missing) { [void](Invoke-CwStatus @('live', 'thumbs') 'thumbnails ready') }
    }

    $script:loading = $true
    $script:lvWall.BeginUpdate()
    try {
        $script:lvWall.Items.Clear()
        $script:imgList.Images.Clear()
        $i = 0
        foreach ($f in $files) {
            $thumbPath = $f.FullName
            $isPic = -not $animated
            if ($animated) { $thumbPath = Find-LiveThumb $f.FullName; $isPic = $true; if (-not $thumbPath) { $thumbPath = '' } }
            $bmp = $null
            if ($thumbPath) { $bmp = New-Thumb $thumbPath $true } else { $bmp = New-Thumb 'missing' $false }
            $script:imgList.Images.Add($bmp)
            $bmp.Dispose()
            $item = New-Object System.Windows.Forms.ListViewItem -ArgumentList @([IO.Path]::GetFileNameWithoutExtension($f.Name), $i)
            $item.Tag = $f.FullName
            $current = $st['wallpaper']
            if ($animated) { $current = $st['live'] }
            $added = $script:lvWall.Items.Add($item)
            if ($f.FullName -eq $current) { $added.Selected = $true }
            $i++
        }
    } finally { $script:lvWall.EndUpdate(); $script:loading = $false }
    if ($files.Count -eq 0) {
        if ($animated) { Set-Status ('No animated wallpapers yet. Click "Add files ..." or drop .mp4 / .webm / .gif files into ' + $LiveDir) }
        else { Set-Status ('No pictures yet. Click "Add files ..." or put images into ' + $WallDir) }
    }
}

function Find-LiveThumb([string]$Path) {
    $key = Get-FileKey $Path
    $t = Join-Path $ThumbDir ($key + '-320.jpg')
    if ((Test-Path -LiteralPath $t) -and ((Get-Item -LiteralPath $t).Length -gt 0)) { return $t }
    return $null
}

function Invoke-WallpaperApply {
    if ($script:lvWall.SelectedItems.Count -eq 0) { Set-Status 'Click a wallpaper first.' $true; return }
    $path = [string]$script:lvWall.SelectedItems[0].Tag
    if ($script:wallMode -eq 'animated') { $r = Invoke-CwStatus @('live', 'set', $path) 'animated wallpaper set' }
    else { $r = Invoke-CwStatus @('wallpaper', 'set', $path) 'wallpaper set' }
    Update-Swatches
}

function Invoke-WallpaperStep([string]$Step) {
    if ($script:wallMode -eq 'animated') { $r = Invoke-CwStatus @('live', $Step) 'animated wallpaper changed' }
    else { $r = Invoke-CwStatus @('wallpaper', $Step) 'wallpaper changed' }
    Update-WallpaperPage
    Update-Swatches
}

function Add-WallpaperFiles {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    if ($script:wallMode -eq 'animated') { $dlg.Filter = 'Animated wallpapers|*.mp4;*.webm;*.mkv;*.mov;*.avi;*.gif|All files|*.*'; $dest = $LiveDir }
    else { $dlg.Filter = 'Pictures|*.jpg;*.jpeg;*.png;*.bmp|All files|*.*'; $dest = $WallDir }
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $n = 0
    foreach ($f in $dlg.FileNames) {
        $target = Join-Path $dest ([IO.Path]::GetFileName($f))
        if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $f -Destination $target; $n++ }
    }
    Set-Status ("added $n file(s) to $dest")
    Update-WallpaperPage
}

$lvWall.Add_DoubleClick({ Invoke-WallpaperApply })
$lvWall.Add_SelectedIndexChanged({
    if ($script:chkPreview.Checked -and -not $script:busy -and -not $script:loading -and $script:lvWall.SelectedItems.Count -gt 0) { Invoke-WallpaperApply }
})

$script:pages['Wallpaper'] = $pgWall
$content.Controls.Add($pgWall)

# ============================================================================= page: Windows

$pgWin = New-Page
$pgWin.Controls.Add((New-Heading 'Windows'))
$pgWin.Controls.Add((New-Note 'Gaps, borders and how windows are arranged. Applied straight away.'))

$komorebiJson = Join-Path $KomorebiHome 'komorebi.json'
$kText = ''
if (Test-Path -LiteralPath $komorebiJson) { $kText = Read-TextFile $komorebiJson }

$rowOuter = New-Row
$rowOuter.Controls.Add((New-FieldLabel 'Space around the screen'))
$script:numOuter = New-Number 0 80 (Get-JsonNumber $kText 'default_workspace_padding' 14)
$rowOuter.Controls.Add($numOuter)
$rowOuter.Controls.Add((New-FieldLabel '  pixels' 80))
$pgWin.Controls.Add($rowOuter)

$rowInner = New-Row
$rowInner.Controls.Add((New-FieldLabel 'Space between windows'))
$script:numInner = New-Number 0 60 (Get-JsonNumber $kText 'default_container_padding' 10)
$rowInner.Controls.Add($numInner)
$rowInner.Controls.Add((New-FieldLabel '  pixels' 80))
$pgWin.Controls.Add($rowInner)

$rowBorder = New-Row
$rowBorder.Controls.Add((New-FieldLabel 'Border thickness'))
$script:numBorder = New-Number 0 12 (Get-JsonNumber $kText 'border_width' 3)
$rowBorder.Controls.Add($numBorder)
$rowBorder.Controls.Add((New-FieldLabel '  pixels' 80))
$pgWin.Controls.Add($rowBorder)

$layouts = @('BSP', 'Columns', 'Rows', 'Grid', 'VerticalStack', 'HorizontalStack', 'UltrawideVerticalStack', 'RightMainVerticalStack')
$rowLayout = New-Row
$rowLayout.Controls.Add((New-FieldLabel 'Default layout'))
$script:cbLayout = New-Combo $layouts (Get-DefaultLayout $kText) 260
$rowLayout.Controls.Add($cbLayout)
$pgWin.Controls.Add($rowLayout)

$script:chkAnim = New-Check 'Animate windows when they move' (Get-AnimationEnabled $kText)
$script:chkMouse = New-Check 'Move the mouse pointer to the focused window' (Get-JsonBool $kText 'mouse_follows_focus' $false)
$pgWin.Controls.Add($chkAnim)
$pgWin.Controls.Add($chkMouse)
$pgWin.Controls.Add((New-Note ''))

$pgWin.Controls.Add((New-Btn 'Apply' 120 {
    try {
        if (-not (Test-Path -LiteralPath $komorebiJson)) { throw "komorebi.json not found at $komorebiJson. Run Install.ps1 again." }
        Backup-ConfigFile $komorebiJson 'komorebi\komorebi.json'
        $t = Read-TextFile $komorebiJson
        $t = Set-JsonNumber $t 'default_workspace_padding' ([int]$script:numOuter.Value)
        $t = Set-JsonNumber $t 'default_container_padding' ([int]$script:numInner.Value)
        $t = Set-JsonNumber $t 'border_width' ([int]$script:numBorder.Value)
        $t = Set-AllLayouts $t ([string]$script:cbLayout.SelectedItem)
        $t = Set-AnimationEnabled $t ([bool]$script:chkAnim.Checked)
        $t = Set-JsonBool $t 'mouse_follows_focus' ([bool]$script:chkMouse.Checked)
        Write-TextFile $komorebiJson $t
        # rounded borders (tacky-borders) have their own thickness, kept in the template so "cw theme" does not undo it
        $tmpl = Join-Path $CwHome 'templates\tacky-borders.config.yaml.tmpl'
        if (Test-Path -LiteralPath $tmpl) {
            Write-TextFile $tmpl (Set-YamlNumber (Read-TextFile $tmpl) 'border_width' ([int]$script:numBorder.Value))
        }
        $tcfg = Join-Path $TackyHome 'config.yaml'
        if (Test-Path -LiteralPath $tcfg) {
            Write-TextFile $tcfg (Set-YamlNumber (Read-TextFile $tcfg) 'border_width' ([int]$script:numBorder.Value))
        }
        $r = Invoke-CwStatus @('reload') 'Window settings applied. Press Alt+Shift+R if windows did not move yet.'
        # layout changes only affect workspaces that are re-tiled
        if (Get-Command komorebic -ErrorAction SilentlyContinue) { & komorebic retile 2>$null | Out-Null }
    } catch { Set-Status ('Problem: ' + $_.Exception.Message) $true }
} $true))

$script:pages['Windows'] = $pgWin
$content.Controls.Add($pgWin)

# ============================================================================= page: Bar

$pgBar = New-Page
$pgBar.Controls.Add((New-Heading 'Bar'))
$pgBar.Controls.Add((New-Note 'Where the bar sits, how tall it is and which items it shows.'))

$yasbConfig = Join-Path $YasbHome 'config.yaml'
$yText = ''
if (Test-Path -LiteralPath $yasbConfig) { $yText = Read-TextFile $yasbConfig }

$rowPos = New-Row
$rowPos.Controls.Add((New-FieldLabel 'Position'))
$script:cbBarPos = New-Combo @('top', 'bottom') (Get-BarPosition $yText) 160
$rowPos.Controls.Add($cbBarPos)
$pgBar.Controls.Add($rowPos)

$rowHeight = New-Row
$rowHeight.Controls.Add((New-FieldLabel 'Height'))
$script:numBarHeight = New-Number 28 90 (Get-BarHeight $yText)
$rowHeight.Controls.Add($numBarHeight)
$rowHeight.Controls.Add((New-FieldLabel '  pixels' 80))
$pgBar.Controls.Add($rowHeight)

$barItems = [ordered]@{
    'home' = @('left', 'Start button / system menu')
    'komorebi_workspaces' = @('left', 'Workspaces')
    'komorebi_active_layout' = @('left', 'Current layout (BSP, columns ...)')
    'taskbar' = @('left', 'Running apps')
    'active_window' = @('left', 'Title of the focused window')
    'clock' = @('center', 'Clock')
    'media' = @('right', 'Music player')
    'cpu' = @('right', 'CPU')
    'memory' = @('right', 'Memory')
    'wifi' = @('right', 'Wi-Fi')
    'volume' = @('right', 'Volume')
    'battery' = @('right', 'Battery')
    'notifications' = @('right', 'Notifications')
    'systray' = @('right', 'System tray icons')
    'power_menu' = @('right', 'Power menu')
}
$script:barKeys = @($barItems.Keys)

$pgBar.Controls.Add((New-FieldLabel 'Show these items' 300))
$script:clbBar = New-Object System.Windows.Forms.CheckedListBox
$clbBar.CheckOnClick = $true
$clbBar.Width = 420
$clbBar.Height = 320
$clbBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$curLayout = Get-BarWidgets $yText
$curAll = @($curLayout.left) + @($curLayout.center) + @($curLayout.right)
foreach ($k in $script:barKeys) {
    $idx = $clbBar.Items.Add($barItems[$k][1])
    $clbBar.SetItemChecked($idx, ($curAll -contains $k))
}
$pgBar.Controls.Add($clbBar)

$pgBar.Controls.Add((New-Btn 'Apply' 120 {
    try {
        if (-not (Test-Path -LiteralPath $yasbConfig)) { throw "YASB config not found at $yasbConfig. Run Install.ps1 again." }
        Backup-ConfigFile $yasbConfig 'yasb\config.yaml'
        $t = Read-TextFile $yasbConfig
        $t = Set-BarPosition $t ([string]$script:cbBarPos.SelectedItem)
        $t = Set-BarHeight $t ([int]$script:numBarHeight.Value)
        $cur = Get-BarWidgets $t
        $extras = @{ left = @(); center = @(); right = @() }
        foreach ($s in @('left', 'center', 'right')) {
            foreach ($w in @($cur[$s])) { if ($script:barKeys -notcontains $w) { $extras[$s] += $w } }   # items added by hand stay
        }
        $new = @{ left = @(); center = @(); right = @() }
        for ($i = 0; $i -lt $script:barKeys.Count; $i++) {
            if ($script:clbBar.GetItemChecked($i)) {
                $key = $script:barKeys[$i]
                $new[$barItems[$key][0]] += $key
            }
        }
        foreach ($s in @('left', 'center', 'right')) { $new[$s] = @($new[$s]) + @($extras[$s]) }
        $t = Set-BarWidgets $t $new
        Write-TextFile $yasbConfig $t
        $r = Invoke-CwStatus @('reload') 'Bar updated.'
    } catch { Set-Status ('Problem: ' + $_.Exception.Message) $true }
} $true))

$script:pages['Bar'] = $pgBar
$content.Controls.Add($pgBar)

# ============================================================================= page: Shortcuts

$pgKeys = New-Page
$pgKeys.Controls.Add((New-Heading 'Shortcuts'))
$pgKeys.Controls.Add((New-Note 'Every keyboard shortcut. Double-click a cell to change it, use the empty bottom row to add one, select a row and press Delete to remove it. Keys look like  alt + shift + h  (write the keys with + between them). The command is anything PowerShell can run, for example  Start-Process "C:\Program Files\App\app.exe"'  680))

$whkdFile = Join-Path $WhkdHome 'whkdrc'

$script:grid = New-Object System.Windows.Forms.DataGridView
$grid.Width = 700
$grid.Height = 330
$grid.AllowUserToAddRows = $true
$grid.AllowUserToDeleteRows = $true
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.SelectionMode = 'FullRowSelect'
$grid.BackgroundColor = $ColCard
$grid.GridColor = $ColLine
$grid.BorderStyle = 'None'
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = $ColCard2
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $ColText
$grid.DefaultCellStyle.BackColor = $ColCard
$grid.DefaultCellStyle.ForeColor = $ColText
$grid.DefaultCellStyle.SelectionBackColor = $ColAccent
$grid.DefaultCellStyle.SelectionForeColor = $ColOnAcc
$colKeys = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colKeys.HeaderText = 'Keys'; $colKeys.FillWeight = 32
$colCmd = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCmd.HeaderText = 'Command'; $colCmd.FillWeight = 68
[void]$grid.Columns.Add($colKeys)
[void]$grid.Columns.Add($colCmd)
$grid.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$pgKeys.Controls.Add($grid)

function Read-ShortcutTable([string]$Path) {
    $script:grid.Rows.Clear()
    if (-not (Test-Path -LiteralPath $Path)) { Set-Status "whkdrc not found at $Path" $true; return }
    foreach ($b in @(Get-WhkdBindings (Read-TextFile $Path))) { [void]$script:grid.Rows.Add($b.Keys, $b.Command) }
}
Read-ShortcutTable $whkdFile

function Restart-Whkd {
    Get-Process -Name 'whkd' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    Start-Process -FilePath 'whkd' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
}

$rowKeyBtns = New-Row
$rowKeyBtns.Controls.Add((New-Btn 'Save shortcuts' 140 {
    try {
        $grid.EndEdit()
        $rows = @()
        foreach ($r in $script:grid.Rows) {
            if ($r.IsNewRow) { continue }
            $k = [string]$r.Cells[0].Value
            $c = [string]$r.Cells[1].Value
            if ($k.Trim() -or $c.Trim()) {
                if (-not $k.Trim() -or -not $c.Trim()) { throw 'Every row needs both keys and a command (or delete the row).' }
                $rows += [pscustomobject]@{ Keys = $k; Command = $c }
            }
        }
        if (-not (Test-Path -LiteralPath $whkdFile)) { throw "whkdrc not found at $whkdFile" }
        Backup-ConfigFile $whkdFile 'whkd\whkdrc'
        $new = Update-WhkdText (Read-TextFile $whkdFile) $rows
        Write-TextFile $whkdFile $new
        Restart-Whkd
        Read-ShortcutTable $whkdFile
        Set-Status 'Shortcuts saved and active.'
    } catch { Set-Status ('Problem: ' + $_.Exception.Message) $true }
} $true))
$rowKeyBtns.Controls.Add((New-Btn 'Add an app ...' 130 {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Programs|*.exe;*.lnk|All files|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $i = $script:grid.Rows.Add('alt + ', ('Start-Process "' + $dlg.FileName + '"'))
        $script:grid.CurrentCell = $script:grid.Rows[$i].Cells[0]
        $script:grid.BeginEdit($true)
        Set-Status 'Type the keys for this app (for example  alt + n ), then press Save shortcuts.'
    }
}))
$rowKeyBtns.Controls.Add((New-Btn 'Delete selected' 130 {
    foreach ($r in @($script:grid.SelectedRows)) { if (-not $r.IsNewRow) { $script:grid.Rows.Remove($r) } }
}))
$rowKeyBtns.Controls.Add((New-Btn 'Undo changes' 120 { Read-ShortcutTable $whkdFile; Set-Status 'Reloaded from the file.' }))
$rowKeyBtns.Controls.Add((New-Btn 'Reset to defaults' 150 {
    $def = Join-Path $CwHome 'defaults\whkdrc'
    if (-not (Test-Path -LiteralPath $def)) { Set-Status 'No default copy found. Run Install.ps1 again.' $true; return }
    $ans = [System.Windows.Forms.MessageBox]::Show('Replace all shortcuts with the original set?', 'Caelestia Settings', 'YesNo', 'Question')
    if ($ans -eq 'Yes') {
        Backup-ConfigFile $whkdFile 'whkd\whkdrc'
        Copy-Item -LiteralPath $def -Destination $whkdFile -Force
        Restart-Whkd
        Read-ShortcutTable $whkdFile
        Set-Status 'Shortcuts reset.'
    }
}))
$pgKeys.Controls.Add($rowKeyBtns)

$script:pages['Shortcuts'] = $pgKeys
$content.Controls.Add($pgKeys)

# ============================================================================= page: System

$pgSys = New-Page
$pgSys.Controls.Add((New-Heading 'System'))
$pgSys.Controls.Add((New-Note 'Startup, the Windows taskbar, health check and folders.'))

$autoNow = $false
try {
    if ((Get-ScheduledTask -TaskName 'CaelestiaWin' -ErrorAction SilentlyContinue) -or (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CaelestiaWin' -ErrorAction SilentlyContinue)) { $autoNow = $true }
} catch { }
$script:chkAuto = New-Check 'Start caelestia-win when I sign in (no startup delay)' $autoNow
$chkAuto.Add_Click({
    if ($script:chkAuto.Checked) { [void](Invoke-CwStatus @('autostart', 'on') 'caelestia-win will start the moment you sign in.') }
    else { [void](Invoke-CwStatus @('autostart', 'off') 'caelestia-win will not start at sign-in.') }
})
$pgSys.Controls.Add($chkAuto)
$pgSys.Controls.Add((New-Note ''))

$rowTask = New-Row
$rowTask.Controls.Add((New-Btn 'Hide the Windows taskbar' 210 { [void](Invoke-CwStatus @('taskbar', 'hide') 'taskbar set to auto-hide (Explorer restarted once)') }))
$rowTask.Controls.Add((New-Btn 'Show the Windows taskbar' 210 { [void](Invoke-CwStatus @('taskbar', 'show') 'taskbar is back') }))
$pgSys.Controls.Add($rowTask)

$rowRun = New-Row
$rowRun.Controls.Add((New-Btn 'Restart everything' 170 {
    [void](Invoke-CwStatus @('stop') 'stopped')
    Start-Sleep -Milliseconds 800
    [void](Invoke-CwStatus @('start') 'komorebi, hotkeys, bar and borders restarted')
}))
$rowRun.Controls.Add((New-Btn 'Reload config' 150 { [void](Invoke-CwStatus @('reload') 'configuration reloaded') }))
$rowRun.Controls.Add((New-Btn 'Screenshot' 120 { $r = Invoke-CwStatus @('screenshot') 'screenshot saved'; if ($r.Ok) { Set-Status $r.Text } }))
$pgSys.Controls.Add($rowRun)

$rowDoc = New-Row
$rowDoc.Controls.Add((New-Btn 'Health check (cw doctor)' 210 { Start-VisibleCw 'doctor' }))
$rowDoc.Controls.Add((New-Btn 'Shortcut cheat sheet' 190 { Start-VisibleCw 'keys' }))
$rowDoc.Controls.Add((New-Btn 'Animated wallpaper support' 220 { Start-VisibleCw 'live install' }))
$pgSys.Controls.Add($rowDoc)

$pgSys.Controls.Add((New-Note ''))
$lblFolders = New-Object System.Windows.Forms.Label
$lblFolders.Text = 'Open a folder'
$lblFolders.Font = $FontBold
$lblFolders.AutoSize = $true
$pgSys.Controls.Add($lblFolders)
$rowFolders = New-Row
$rowFolders.Controls.Add((New-Btn 'caelestia-win' 130 { Open-Folder $CwHome }))
$rowFolders.Controls.Add((New-Btn 'komorebi' 100 { Open-Folder $KomorebiHome }))
$rowFolders.Controls.Add((New-Btn 'Shortcuts' 100 { Open-Folder $WhkdHome }))
$rowFolders.Controls.Add((New-Btn 'Bar (YASB)' 110 { Open-Folder $YasbHome }))
$rowFolders.Controls.Add((New-Btn 'Wallpapers' 110 { Open-Folder $WallDir }))
$pgSys.Controls.Add($rowFolders)

$script:pages['System'] = $pgSys
$content.Controls.Add($pgSys)

# ----------------------------------------------------------------------------- go

foreach ($pg in $script:pages.Values) { Set-ControlStyle $pg }
Set-ControlStyle $nav
Update-Swatches

$startPage = 'Colours'
$form.Add_Shown({ $script:form.Activate() })
Show-Page $startPage
[void]$form.ShowDialog()
