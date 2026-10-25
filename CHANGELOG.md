# Changelog

## 1.1.2

- Installer finds tacky-borders in the last releases (and correctly reads the GitHub release list on Windows PowerShell 5.1) and accepts .exe, .zip or .msi files (fixes "latest release has no .exe file")
- Colour engine no longer prints the Pillow `getdata` deprecation warning
- New `cw keys` and `cw screenshot` commands, `Alt` `P` screenshot bind
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
