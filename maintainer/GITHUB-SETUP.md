# Making the repository easy to find (honest, effective SEO)

GitHub and Google rank repositories using visible, genuine signals. Hidden keywords or invisible text are treated as spam and can get a repository demoted or removed, so this guide only uses things that help real people and search engines.

> Short version: run `maintainer\Publish.ps1` (see [BEFORE-UPLOAD.md](BEFORE-UPLOAD.md)). It does steps 1, 4 and the topics below for you. This page explains what it does and why.

## 1. About box (most important)

Repository page → gear icon next to **About**.

**Description** (copy):

> Windows tiling desktop rice inspired by Caelestia: komorebi + YASB + whkd, rounded glowing borders, wallpaper-based Material You colours, one-command installer.

**Website**: your GitHub Pages URL (step 4).

**Topics** (paste each one):

```text
windows windows-11 windows-10 rice ricing dotfiles tiling-window-manager komorebi yasb whkd tacky-borders
flow-launcher caelestia hyprland-windows material-you theme customization desktop-customization powershell
wallpaper-colors window-manager productivity keyboard-shortcuts windows-customization
```

Or run, with the GitHub CLI installed (`winget install GitHub.cli`):

```powershell
gh repo edit --description "Windows tiling desktop rice inspired by Caelestia: komorebi + YASB + whkd, rounded glowing borders, wallpaper colours, one-command installer." --add-topic windows,windows-11,rice,dotfiles,tiling-window-manager,komorebi,yasb,whkd,caelestia,material-you,powershell
```

## 2. Social preview

Upload a 1280×640 image under Settings → General. See [Screenshots](../docs/SCREENSHOTS.md).

## 3. README

Already written around the words people search: *Windows tiling window manager*, *Windows rice*, *Hyprland on Windows*, *Caelestia for Windows*, *komorebi config*, *YASB config*. Keep real screenshots near the top and keep headings descriptive.

## 4. GitHub Pages site

Settings → Pages → Source: **Deploy from a branch**, branch `main`, folder `/docs`. The file `docs/index.html` is a ready landing page with proper title, description, Open Graph tags and structured data. Your site will be at `https://krvats.github.io/caelestia-win/`.

## 5. Releases

Releases → **Create a new release** → push a tag such as `v1.2.0`; the release workflow builds the zip and publishes the release by itself. Releases show up in search and give people a download link.

## 6. Where to share (this is what really moves rankings)

Links and stars from other places matter more than anything on the page.

- Desktop customization communities such as r/Windows11 and r/desktops (read each community's rules first; most want a screenshot plus a short description)
- Awesome lists: open a PR to add it to lists for komorebi, YASB and Windows customization
- The komorebi and YASB Discords and GitHub Discussions "show and tell" boards
- A short demo video on YouTube or a GIF on X, with the repo link in the description

## 7. Community health

Issue templates, a contributing guide and a licence are already included; GitHub shows these in the **Insights → Community** checklist. Reply to issues quickly, since active repositories rank and convert better.
