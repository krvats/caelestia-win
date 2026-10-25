<#
.SYNOPSIS
    OPTIONAL and UNTESTED: builds the Krozzii/caelestia-windows Qt/QML dashboard from source.

.DESCRIPTION
    caelestia-win does not need this. It only adds the separate Qt dashboard window from
    https://github.com/Krozzii/caelestia-windows (a 1-star project with no releases).
    The steps below follow that repo's CMake layout; the repo's own README is for KDE and is outdated,
    so a build may fail. If it does, the rest of caelestia-win keeps working.

    Needs (not installed by this script, except where noted):
      - git, CMake, Ninja            (winget install Git.Git Kitware.CMake Ninja-build.Ninja)
      - Visual Studio Build Tools    (C++ workload)
      - Qt 6 for MSVC                (Qt online installer; pass -QtDir to the kit folder, e.g. C:\Qt\6.8.0\msvc2022_64)

.PARAMETER QtDir
    Qt kit folder. Auto-detected under C:\Qt if omitted.

.PARAMETER WorkDir
    Where to clone and build. Default: ~\caelestia-windows-build
#>
[CmdletBinding()]
param(
    [string]$QtDir,
    [string]$WorkDir = (Join-Path $HOME 'caelestia-windows-build')
)

$ErrorActionPreference = 'Stop'
function Write-Step([string]$Text) { Write-Host ''; Write-Host ('==> ' + $Text) -ForegroundColor Cyan }

Write-Step 'Checking tools'
$missing = @()
foreach ($t in @('git', 'cmake', 'ninja')) { if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $missing += $t } }
if ($missing) { throw ("Missing: " + ($missing -join ', ') + '. Install with: winget install Git.Git Kitware.CMake Ninja-build.Ninja') }

if (-not $QtDir) {
    $QtDir = Get-ChildItem 'C:\Qt' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^6\.' } | Sort-Object Name -Descending |
        ForEach-Object { Get-ChildItem $_.FullName -Directory -Filter 'msvc*_64' -ErrorAction SilentlyContinue } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $QtDir -or -not (Test-Path -LiteralPath $QtDir)) {
    throw 'Qt 6 (MSVC kit) not found. Install it from https://www.qt.io/download-qt-installer, then pass -QtDir.'
}
Write-Host "    Qt: $QtDir"

# the MSVC compiler must be on PATH for Ninja
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Build Tools not found (C++ workload needed).' }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'Visual Studio C++ tools not found.' }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'

Write-Step 'Cloning'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
if (Test-Path -LiteralPath (Join-Path $src '.git')) { & git -C $src pull --ff-only }
else { & git clone --depth 1 https://github.com/Krozzii/caelestia-windows.git $src }
if ($LASTEXITCODE -ne 0) { throw 'git failed' }

Write-Step 'Configuring and building (this takes a while)'
$build = Join-Path $WorkDir 'build'
$cmd = "`"$vcvars`" && cmake -S `"$src`" -B `"$build`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=`"$QtDir`" && cmake --build `"$build`" --config Release"
& cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) { throw 'Build failed. This project is unmaintained, so this is not unusual. The rest of caelestia-win is unaffected.' }

Write-Step 'Collecting the app'
$exe = Get-ChildItem -LiteralPath $build -Recurse -Filter '*.exe' |
    Where-Object { $_.Name -match 'caelestia' -and $_.Name -notmatch 'test' } | Select-Object -First 1
if (-not $exe) { throw 'Build finished but no caelestia*.exe was found.' }

$dist = Join-Path $WorkDir 'dist\Caelestia-Final'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item -LiteralPath $exe.FullName -Destination $dist -Force
& (Join-Path $QtDir 'bin\windeployqt.exe') --release --qmldir (Join-Path $src 'modules') (Join-Path $dist $exe.Name)

$repoInstall = Get-ChildItem -LiteralPath $src -Recurse -Filter 'install.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($repoInstall) {
    Write-Step "Running the project's own installer"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $repoInstall.FullName
} else {
    $target = Join-Path $env:ProgramFiles 'Caelestia'
    Write-Host "    No installer in the repo. Copy $dist to $target yourself (needs admin), then run: cw dashboard"
}

Write-Host ''
Write-Host "Built at $dist" -ForegroundColor Green
