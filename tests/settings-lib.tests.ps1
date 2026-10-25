# Tests for scripts\settings-lib.ps1 against the shipped config files. Run with:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\settings-lib.tests.ps1
# Works on Windows PowerShell 5.1 and PowerShell 7 (also on Linux/macOS, no GUI is used).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'scripts\settings-lib.ps1')

$script:failures = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ("$Actual" -ceq "$Expected") { Write-Host "  ok    $Name" }
    else { Write-Host "  FAIL  $Name : expected [$Expected] got [$Actual]"; $script:failures++ }
}
function Assert-True([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Host "  ok    $Name" } else { Write-Host "  FAIL  $Name"; $script:failures++ }
}

$kom = Read-TextFile (Join-Path $Root 'config\komorebi\komorebi.json')
$yasb = Read-TextFile (Join-Path $Root 'config\yasb\config.yaml')
$whkd = Read-TextFile (Join-Path $Root 'config\whkd\whkdrc')
$tacky = Read-TextFile (Join-Path $Root 'templates\tacky-borders.config.yaml.tmpl')

Write-Host 'komorebi.json'
Assert-Equal (Get-JsonNumber $kom 'default_workspace_padding' 0) 14 'read outer gap'
Assert-Equal (Get-JsonNumber $kom 'default_container_padding' 0) 10 'read inner gap'
Assert-Equal (Get-JsonNumber $kom 'border_width' 0) 3 'read border width'
$k2 = Set-JsonNumber $kom 'default_workspace_padding' 20
Assert-Equal (Get-JsonNumber $k2 'default_workspace_padding' 0) 20 'write outer gap'
Assert-Equal (Get-JsonNumber $k2 'default_container_padding' 0) 10 'other numbers untouched'
$k2 = Set-JsonNumber $k2 'border_width' 5
Assert-Equal (Get-JsonNumber $k2 'border_width' 0) 5 'write border width'
Assert-Equal (Get-JsonNumber $k2 'border_offset' 0) -1 'negative numbers survive'
Assert-True ((($k2 | ConvertFrom-Json).default_workspace_padding) -eq 20) 'result is still valid JSON'
Assert-True (Get-AnimationEnabled $kom) 'animation enabled by default'
$k3 = Set-AnimationEnabled $kom $false
Assert-True (-not (Get-AnimationEnabled $k3)) 'animation switched off'
Assert-True ((($k3 | ConvertFrom-Json).animation.enabled) -eq $false) 'animation JSON valid'
Assert-True (-not (Get-JsonBool $kom 'mouse_follows_focus' $true)) 'read mouse_follows_focus'
$k4 = Set-JsonBool $kom 'mouse_follows_focus' $true
Assert-True ((($k4 | ConvertFrom-Json).mouse_follows_focus) -eq $true) 'write mouse_follows_focus'
Assert-Equal (Get-DefaultLayout $kom) 'BSP' 'read layout'
$k5 = Set-AllLayouts $kom 'Columns'
$j5 = $k5 | ConvertFrom-Json
Assert-Equal (@($j5.monitors[0].workspaces | Where-Object { $_.layout -eq 'Columns' }).Count) 9 'all nine workspaces changed layout'

Write-Host 'tacky-borders template'
Assert-Equal (Get-YamlNumber $tacky 'border_width' 0) 3 'read tacky border width'
$t2 = Set-YamlNumber $tacky 'border_width' 6
Assert-Equal (Get-YamlNumber $t2 'border_width' 0) 6 'write tacky border width'
Assert-Equal (Get-YamlNumber $t2 'border_offset' 0) -1 'border_offset untouched'

Write-Host 'YASB bar'
Assert-Equal (Get-BarPosition $yasb) 'top' 'read bar position'
$y2 = Set-BarPosition $yasb 'bottom'
Assert-Equal (Get-BarPosition $y2) 'bottom' 'write bar position'
Assert-True ($y2.Contains('label_position: "left"')) 'label_position untouched'
Assert-Equal (Get-BarHeight $yasb) 44 'read bar height'
$y3 = Set-BarHeight $yasb 52
Assert-Equal (Get-BarHeight $y3) 52 'write bar height'
$w = Get-BarWidgets $yasb
Assert-Equal ($w.left -join ',') 'home,komorebi_workspaces,komorebi_active_layout,taskbar' 'read left widgets'
Assert-Equal ($w.center -join ',') 'clock' 'read centre widgets'
Assert-True (@($w.right).Count -ge 8) 'read right widgets'
$w2 = @{ left = @($w.left); center = @($w.center); right = @($w.right | Where-Object { $_ -ne 'media' -and $_ -ne 'cpu' }) }
$y4 = Set-BarWidgets $yasb $w2
$w3 = Get-BarWidgets $y4
Assert-Equal ($w3.right -join ',') ($w2.right -join ',') 'widgets removed'
Assert-True ($y4.Contains("`nwidgets:`n  home:") -or $y4.Contains("`r`nwidgets:`r`n  home:")) 'top-level widgets block intact'
Assert-True ($y4 -match '(?m)^bars:') 'bars block intact'
Assert-Equal ((Get-BarWidgets (Set-BarWidgets $yasb (Get-BarWidgets $yasb))).right -join ',') ($w.right -join ',') 'round trip keeps order'
Assert-Equal (Set-BarWidgets $yasb (Get-BarWidgets $yasb)) $yasb 'round trip is byte for byte identical'
$yCrLf = $yasb -replace "`r?`n", "`r`n"
Assert-Equal (Set-BarWidgets $yCrLf (Get-BarWidgets $yCrLf)) $yCrLf 'round trip with Windows line endings'

Write-Host 'whkdrc'
$rows = @(Get-WhkdBindings $whkd)
Assert-True ($rows.Count -ge 55) "parsed $($rows.Count) shortcuts"
$open = $rows | Where-Object { $_.Keys -eq 'alt + q' }
Assert-Equal $open.Command 'komorebic close' 'alt + q closes'
$sameText = Update-WhkdText $whkd $rows
Assert-Equal $sameText $whkd 'unchanged table gives an identical file'
$rows2 = @($rows | ForEach-Object { [pscustomobject]@{ Keys = $_.Keys; Command = $_.Command } })
($rows2 | Where-Object { $_.Keys -eq 'alt + q' }).Command = 'komorebic close --test'
$rows2 = @($rows2 | Where-Object { $_.Keys -ne 'alt + m' })
$rows2 += [pscustomobject]@{ Keys = 'alt + n'; Command = 'notepad.exe' }
$edited = Update-WhkdText $whkd $rows2
$back = @(Get-WhkdBindings $edited)
Assert-Equal ($back | Where-Object { $_.Keys -eq 'alt + q' }).Command 'komorebic close --test' 'edited command saved'
Assert-True (-not ($back | Where-Object { $_.Keys -eq 'alt + m' })) 'deleted shortcut gone'
Assert-Equal ($back | Where-Object { $_.Keys -eq 'alt + n' }).Command 'notepad.exe' 'new shortcut added'
Assert-True ($edited.Contains('# ---------------------------------------------------------------- session')) 'comments kept'
Assert-True ($edited.StartsWith('.shell powershell')) '.shell line kept'
Assert-Equal @($back).Count ($rows.Count) 'one removed, one added'
$threw = $false
try { [void](Update-WhkdText $whkd @([pscustomobject]@{ Keys = 'alt : x'; Command = 'y' })) } catch { $threw = $true }
Assert-True $threw 'a colon in the keys is rejected'

Write-Host 'thumbnail keys'
$cwAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'scripts\cw.ps1'), [ref]$null, [ref]$null)
$fn = $cwAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Get-LiveKey' }, $true) | Select-Object -First 1
Assert-True ($null -ne $fn) 'cw.ps1 defines Get-LiveKey'
$tmpFile = Join-Path ([IO.Path]::GetTempPath()) ('cw-key-test-' + [guid]::NewGuid().ToString('N') + '.mp4')
Set-Content -LiteralPath $tmpFile -Value 'x'
try {
    Invoke-Expression $fn.Extent.Text
    Assert-Equal (Get-LiveKey $tmpFile) (Get-FileKey $tmpFile) 'cw and settings agree on the thumbnail name'
} finally { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }

if ($script:failures -gt 0) { Write-Host "$($script:failures) check(s) failed"; exit 1 }
Write-Host 'all settings-lib checks passed'
