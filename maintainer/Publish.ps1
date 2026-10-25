<#
.SYNOPSIS
    Publishes this project to GitHub for you: fills in your username, creates the repository,
    pushes the code, sets the description and topics and turns on GitHub Pages.

.DESCRIPTION
    Run it once, from the project folder, in a normal PowerShell window:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\maintainer\Publish.ps1

    It installs Git and the GitHub CLI with winget if they are missing and opens the browser
    once so you can sign in to GitHub.

.PARAMETER RepoName
    Repository name. Default: caelestia-win

.PARAMETER Private
    Create a private repository instead of a public one.
#>
[CmdletBinding()]
param(
    [string]$RepoName = 'caelestia-win',
    [switch]$Private
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot   # this script lives in <project>\maintainer
Set-Location -LiteralPath $Root

function Write-Step([string]$Text) { Write-Host ''; Write-Host ('==> ' + $Text) -ForegroundColor Cyan }
function Test-Tool([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Update-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }

try {
    Write-Step 'Checking tools'
    foreach ($pair in @(@('git', 'Git.Git'), @('gh', 'GitHub.cli'))) {
        if (-not (Test-Tool $pair[0])) {
            if (-not (Test-Tool 'winget')) { throw "$($pair[0]) is missing and winget is not available. Install it from https://git-scm.com or https://cli.github.com and run this again." }
            Write-Host "installing $($pair[1]) ..."
            & winget install --id $pair[1] -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            Update-Path
            if (-not (Test-Tool $pair[0])) { throw "$($pair[0]) was installed but is not on PATH yet. Close this window, open a new PowerShell and run Publish.ps1 again." }
        }
    }

    Write-Step 'Signing in to GitHub'
    $ErrorActionPreference = 'Continue'   # native tools write to stderr; do not treat that as a script error
    & gh auth status 2>$null | Out-Null
    $authed = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = 'Stop'
    if (-not $authed) {
        Write-Host 'A browser window will open. Sign in, then come back here.'
        & gh auth login --web --git-protocol https
        if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in did not finish.' }
    }
    $user = (& gh api user --jq .login).Trim()
    if (-not $user) { throw 'Could not read your GitHub username.' }
    Write-Host "signed in as $user"

    Write-Step 'Checking for real screenshots'
    $shots = @(Get-ChildItem -LiteralPath (Join-Path $Root 'docs\screenshots') -Include *.png, *.jpg, *.gif -Recurse -ErrorAction SilentlyContinue)
    if ($shots.Count -eq 0) {
        Write-Warning 'docs\screenshots is empty. The README will use the concept renders. Real screenshots get far more stars (see docs\SCREENSHOTS.md).'
        $ans = Read-Host 'Publish anyway? (y/N)'
        if ($ans -notmatch '^[yY]') { Write-Host 'Stopped. Add screenshots, then run Publish.ps1 again.'; return }
    } else { Write-Host ("found {0} screenshot file(s)" -f $shots.Count) }

    Write-Step 'Pointing links at your GitHub account'
    # The project ships with links to github.com/krvats/caelestia-win. If you publish under another account or
    # repository name, every link is rewritten here. For krvats/caelestia-win nothing changes.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $exts = @('.md', '.yml', '.yaml', '.ps1', '.py', '.html', '.tmpl')
    $changed = 0
    if (($user -ne 'krvats') -or ($RepoName -ne 'caelestia-win')) {
        Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
            $exts -contains $_.Extension -and $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]maintainer[\\/]'
        } | ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName)
            if ($text.Contains('krvats')) {
                $new = $text.Replace('krvats.github.io/caelestia-win', "$user.github.io/$RepoName")
                $new = $new.Replace('krvats/caelestia-win', "$user/$RepoName")
                $new = $new.Replace('github.com/krvats', "github.com/$user")
                [IO.File]::WriteAllText($_.FullName, $new, $utf8)
                $changed++
            }
        }
    }
    Write-Host "$changed file(s) updated"

    Write-Step 'Creating the repository and uploading'
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { & git init -b main | Out-Null }
    $gitName = (& git config user.name); if (-not $gitName) { & git config user.name $user }
    $gitMail = (& git config user.email); if (-not $gitMail) { & git config user.email "$user@users.noreply.github.com" }
    & git add -A
    $ErrorActionPreference = 'Continue'
    & git commit -m 'caelestia-win: first release' 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    $vis = if ($Private) { '--private' } else { '--public' }
    $desc = 'Windows tiling desktop rice inspired by Caelestia: komorebi + YASB + whkd, rounded glowing borders, wallpaper colours, one-command installer.'
    & gh repo create "$user/$RepoName" $vis --description $desc --source . --remote origin --push
    if ($LASTEXITCODE -ne 0) { throw 'gh repo create failed (does that repository name already exist on your account?).' }

    Write-Step 'Adding topics and turning on GitHub Pages'
    $topics = @('windows', 'windows-11', 'windows-10', 'rice', 'ricing', 'dotfiles', 'tiling-window-manager', 'komorebi', 'yasb', 'whkd',
                'tacky-borders', 'flow-launcher', 'caelestia', 'material-you', 'theme', 'customization', 'powershell', 'window-manager',
                'productivity', 'keyboard-shortcuts', 'windows-customization')
    $topicArgs = @()
    foreach ($tp in $topics) { $topicArgs += @('--add-topic', $tp) }
    & gh repo edit "$user/$RepoName" @topicArgs | Out-Null
    try {
        & gh api -X POST "repos/$user/$RepoName/pages" -f 'source[branch]=main' -f 'source[path]=/docs' | Out-Null
        Write-Host "GitHub Pages: https://$user.github.io/$RepoName/ (live in a minute or two)"
    } catch { Write-Warning 'Could not enable GitHub Pages automatically. Settings > Pages > Deploy from a branch > main > /docs.' }

    Write-Host ''
    Write-Host 'Done. Your repository:' -ForegroundColor Green
    Write-Host "  https://github.com/$user/$RepoName"
    Write-Host ''
    Write-Host 'Last manual step (GitHub has no command for it): Settings > General > Social preview > upload a 1280x640 image.'
} catch {
    Write-Host ''
    Write-Host "Stopped: $_" -ForegroundColor Red
    exit 1
}
