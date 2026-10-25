# caelestia-win - helpers for the settings window (no windows or buttons in here, so they can be tested).
# Dot-sourced by settings.ps1 and by tests\settings-lib.tests.ps1.

function Read-TextFile([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-TextFile([string]$Path, [string]$Text) {
    # explicit UTF-8 without BOM: the YASB config holds icon characters and Windows PowerShell 5.1 defaults to ANSI
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-NewLine([string]$Text) {
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

# ------------------------------------------------------------------ komorebi.json (edited in place, formatting kept)

function Get-JsonNumber([string]$Text, [string]$Key, [int]$Default) {
    $m = [regex]::Match($Text, '"' + [regex]::Escape($Key) + '"\s*:\s*(-?\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $Default
}

function Set-JsonNumber([string]$Text, [string]$Key, [int]$Value) {
    $rx = New-Object System.Text.RegularExpressions.Regex ('("' + [regex]::Escape($Key) + '"\s*:\s*)-?\d+')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $Value + $Text.Substring($m.Index + $m.Length)
}

function Get-JsonBool([string]$Text, [string]$Key, [bool]$Default) {
    $m = [regex]::Match($Text, '"' + [regex]::Escape($Key) + '"\s*:\s*(true|false)')
    if ($m.Success) { return ($m.Groups[1].Value -eq 'true') }
    return $Default
}

function Set-JsonBool([string]$Text, [string]$Key, [bool]$Value) {
    $rx = New-Object System.Text.RegularExpressions.Regex ('("' + [regex]::Escape($Key) + '"\s*:\s*)(true|false)')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    $word = 'false'
    if ($Value) { $word = 'true' }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $word + $Text.Substring($m.Index + $m.Length)
}

function Get-AnimationEnabled([string]$Text) {
    $m = [regex]::Match($Text, '"animation"\s*:\s*\{\s*"enabled"\s*:\s*(true|false)')
    if ($m.Success) { return ($m.Groups[1].Value -eq 'true') }
    return $true
}

function Set-AnimationEnabled([string]$Text, [bool]$Value) {
    $rx = New-Object System.Text.RegularExpressions.Regex ('("animation"\s*:\s*\{\s*"enabled"\s*:\s*)(true|false)')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    $word = 'false'
    if ($Value) { $word = 'true' }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $word + $Text.Substring($m.Index + $m.Length)
}

function Get-DefaultLayout([string]$Text) {
    $m = [regex]::Match($Text, '"layout"\s*:\s*"(\w+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return 'BSP'
}

function Set-AllLayouts([string]$Text, [string]$Layout) {
    if ($Layout -notmatch '^\w+$') { throw "Bad layout name: $Layout" }
    return [regex]::Replace($Text, '("layout"\s*:\s*")\w+(")', ('${1}' + $Layout + '${2}'))
}

# ------------------------------------------------------------------ tacky-borders config / template (YAML, one value per line)

function Get-YamlNumber([string]$Text, [string]$Key, [int]$Default) {
    $m = [regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Key) + ':\s*(-?\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $Default
}

function Set-YamlNumber([string]$Text, [string]$Key, [int]$Value) {
    $rx = New-Object System.Text.RegularExpressions.Regex ('(?m)^(\s*' + [regex]::Escape($Key) + ':\s*)-?\d+')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $Value + $Text.Substring($m.Index + $m.Length)
}

# ------------------------------------------------------------------ YASB bar (config.yaml)

function Get-BarPosition([string]$Text) {
    $m = [regex]::Match($Text, '(?m)^\s*position:\s*"(top|bottom)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return 'top'
}

function Set-BarPosition([string]$Text, [string]$Position) {
    if (@('top', 'bottom') -notcontains $Position) { throw "Bad bar position: $Position" }
    $rx = New-Object System.Text.RegularExpressions.Regex ('(?m)^(\s*position:\s*")(top|bottom)(")')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $Position + $m.Groups[3].Value + $Text.Substring($m.Index + $m.Length)
}

function Get-BarHeight([string]$Text) {
    $m = [regex]::Match($Text, '(?m)^    dimensions:\s*\r?\n\s+width:[^\r\n]*\r?\n\s+height:\s*(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 44
}

function Set-BarHeight([string]$Text, [int]$Height) {
    $rx = New-Object System.Text.RegularExpressions.Regex ('(?m)^(    dimensions:\s*\r?\n\s+width:[^\r\n]*\r?\n\s+height:\s*)\d+')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + $Height + $Text.Substring($m.Index + $m.Length)
}

function Get-BarWidgets([string]$Text) {
    $res = @{ left = @(); center = @(); right = @() }
    $inBlock = $false
    $section = $null
    foreach ($line in ($Text -split "\r?\n")) {
        if (-not $inBlock) {
            if ($line -match '^    widgets:\s*$') { $inBlock = $true }
            continue
        }
        if ($line -match '^\s{6}(left|center|right):\s*$') { $section = $Matches[1]; continue }
        if ($line -match '^\s{8}-\s*"([^"]+)"\s*$') {
            if ($section) { $res[$section] = @($res[$section]) + $Matches[1] }
            continue
        }
        if ($line.Trim() -eq '') { continue }
        break   # reached the next block
    }
    return $res
}

function Set-BarWidgets([string]$Text, $Layout) {
    $nl = Get-NewLine $Text
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('    widgets:' + $nl)
    foreach ($section in @('left', 'center', 'right')) {
        [void]$sb.Append('      ' + $section + ':' + $nl)
        foreach ($w in @($Layout[$section])) { [void]$sb.Append('        - "' + $w + '"' + $nl) }
    }
    [void]$sb.Append($nl)   # blank line before the top-level "widgets:" block
    $rx = New-Object System.Text.RegularExpressions.Regex ('(?ms)^    widgets:.*?(?=^widgets:)')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $sb.ToString() + $Text.Substring($m.Index + $m.Length)
}

# ------------------------------------------------------------------ whkdrc (keyboard shortcuts)

$script:WhkdBinding = '^(?<k>[^#:\s][^:]*?)\s+:\s+(?<c>.+?)\s*$'

function Format-KeyId([string]$Keys) {
    return (($Keys.ToLower()) -replace '\s+', '')
}

function Get-WhkdBindings([string]$Text) {
    $rows = @()
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match $script:WhkdBinding) {
            $rows += [pscustomobject]@{ Keys = $Matches['k'].Trim(); Command = $Matches['c'] }
        }
    }
    return $rows
}

function Update-WhkdText([string]$Text, $Rows) {
    # Keeps every comment and the original order. Changed rows are rewritten in place,
    # rows that were removed disappear, brand-new rows are added at the end.
    $nl = Get-NewLine $Text
    $byKey = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Rows)) {
        $keys = ([string]$r.Keys).Trim()
        $cmd = ([string]$r.Command).Trim()
        if (-not $keys -or -not $cmd) { continue }
        if ($keys -match ':') { throw "A shortcut cannot contain a colon: $keys" }
        $id = Format-KeyId $keys
        if (-not $byKey.ContainsKey($id)) { $order.Add($id) }
        $byKey[$id] = [pscustomobject]@{ Keys = $keys; Command = $cmd }
    }
    $used = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match $script:WhkdBinding) {
            $id = Format-KeyId $Matches['k']
            if ($byKey.ContainsKey($id) -and -not $used.ContainsKey($id)) {
                $r = $byKey[$id]
                $out.Add($r.Keys + ' : ' + $r.Command)
                $used[$id] = $true
            }
            # not in the table any more (deleted, or a duplicate): drop the line
        } else {
            $out.Add($line)
        }
    }
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($id in $order) {
        if (-not $used.ContainsKey($id)) { $added.Add($byKey[$id].Keys + ' : ' + $byKey[$id].Command) }
    }
    if ($added.Count -gt 0) {
        while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
        $out.Add('')
        $out.Add('# ---------------------------------------------------------------- added in the settings window')
        foreach ($a in $added) { $out.Add($a) }
        $out.Add('')
    }
    return ($out -join $nl)
}

# ------------------------------------------------------------------ small things

# Same recipe as Get-LiveKey in cw.ps1 (the two must stay identical: the settings window finds the thumbnails cw made).
function Get-FileKey([string]$Path) {
    $i = Get-Item -LiteralPath $Path
    $s = $i.FullName.ToLower() + '|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks
    $h = [System.Security.Cryptography.SHA1]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-ColourFromHex([string]$Hex, [string]$Fallback) {
    $h = $Hex
    if (-not $h -or $h -notmatch '^#[0-9a-fA-F]{6}$') { $h = $Fallback }
    return [System.Drawing.ColorTranslator]::FromHtml($h)
}
