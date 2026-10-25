# Changelog

## 1.2.0

- **Settings window** (`Alt` `S`, Start menu, `cw settings`): colours and themes, wallpaper thumbnails, gaps, borders and layout, bar position and items, and an editable table of every keyboard shortcut. No file editing needed. Every file is backed up before it is changed
- **Animated wallpapers** (video and GIF) like the caelestia-aw fork: `cw live next|prev|random|set|stop|pause|resume|volume|list|thumbs|status|install|settings`, played by Lively Wallpaper, desktop colours taken from a frame of the video, cached thumbnails, an Animated library folder, `Ctrl` `Alt` `W`
- Pause rules for animated wallpapers: on battery power and when an app is fullscreen (`cw live rules ...`)
- Installer: `-WithAnimated`, a Start menu entry, finds tools that winget left off PATH and adds them, keeps a default copy of the shortcuts for "Reset to defaults"
- Fixes for "not found": `cw`, the login script and the settings window re-read PATH, so hotkeys no longer fail with "komorebic is not recognised" right after installing; `Alt` `Enter` falls back to PowerShell when Windows Terminal is missing
- All repository links point to github.com/krvats/caelestia-win; the README version badge no longer shows "no releases"; pushing a `v*` tag now builds the zip and creates the GitHub release
- Maintainer-only files (publishing script, upload checklists) moved to a git-ignored `maintainer` folder

## 1.1.2

- Installer finds tacky-borders in the last releases (and correctly reads the GitHub release list on Windows PowerShell 5.1) and accepts .exe, .zip or .msi files (fixes "latest release has no .exe file")
- Colour engine no longer prints the Pillow `getdata` deprecation warning
- New `cw keys` and `cw screenshot` commands, `Alt` `P` screenshot bind
- Nine community themes (catppuccin, gruvbox, nord, rosepine, tokyonight, dracula, everforest, onedark, solarized), five with a light mode: `cw preset <name>`
- `Setup.bat` (double-click install) and `Publish.ps1` (one-command GitHub upload with topics and Pages)
- New docs: beginner guide, shortcut and productivity guide, screenshots guide, GitHub setup guide, GitHub Pages landing page, printable cheat sheet

## 1.1.1

- Installer keeps the window open, writes `install.log`, and reports where it stopped
- Download timeouts, no progress-bar slowdown, and a fallback download for komorebi's `applications.json`

## 1.1.0

- Rounded gradient window borders with a glow, via tacky-borders, coloured from the wallpaper palette
- The YASB `taskbar` widget shows running apps; the Windows taskbar is auto-hidden by default (`-KeepTaskbar` to opt out)
- Wider window gaps; `-HideTaskbar` replaced by `-KeepTaskbar`; `-SkipBorders` added
- `cw preset` and nine named colour presets

## 1.0.0

First release.

- komorebi + whkd + YASB + Flow Launcher setup with a one-command installer and uninstaller
- Hyprland-style Alt keybinds, 9 workspaces, BSP tiling, animated borders
- Floating-pill YASB bar with workspaces, layout, active window, clock, media, stats, tray and power menu
- `theme.py`: wallpaper-driven Material-style colour generator (dark/light, 4 variants) and 9 named presets
- `cw` command: wallpaper, scheme, variant, preset, theme, reload, start/stop, taskbar, doctor
- 22+ automated tests, GitHub Actions CI (Python tests, PowerShell parse check)
- Optional `optional/Build-Dashboard.ps1` for the Krozzii Qt dashboard (untested)
