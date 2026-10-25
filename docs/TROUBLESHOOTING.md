# Troubleshooting

Start with `cw doctor`. It checks every piece and prints the fix next to each failure.

## The installer window closes before I can read it
Open PowerShell yourself (right-click Start, Terminal), `cd` into the folder and run the install command there. The installer now also waits for Enter at the end and saves everything to `~\.config\caelestia-win\install.log`. If it stops with an error, attach that log to your issue.

## The installer sits on "Adding rounded gradient window borders" or cannot download applications.json
Both come from GitHub. If github.com or raw.githubusercontent.com is slow or blocked on your network, try another DNS server (1.1.1.1) or a VPN, or run with `-SkipBorders`. Per-app rules can be fetched later with `komorebic fetch-asc`.

## The bar is empty or icons are boxes
Install the font and sign out/in: `winget install DEVCOM.JetBrainsMonoNerdFont`. Any Nerd Font works if you change the `font-family` line in `templates/yasb.styles.css.tmpl`, then run `cw theme`.

## `cw` is not recognised
Open a **new** terminal. The installer adds `~\.config\caelestia-win\bin` to your user PATH, which only applies to new windows.

## Nothing tiles / keybinds do nothing
`cw status`, then `cw start`. Keybinds come from whkd, which `komorebic start --whkd` launches. Run `komorebic check` for config errors. A syntax error in `komorebi.json` stops komorebi from loading it.

## A window will not tile (or tiles when it should float)
Press Alt+T to float it. For a permanent rule, add the app to `~\applications.json` (or use komorebi's `floating_applications` in `komorebi.json`). `komorebic fetch-asc` re-downloads the community rule set.

## The Windows taskbar is still there
The installer hides it by default. If you used `-KeepTaskbar` or it came back, run `cw taskbar hide` (auto-hide, Explorer restarts once). Undo with `cw taskbar show`. Auto-hide leaves the taskbar reachable by pushing the mouse to the bottom edge of the screen.

## No rounded gradient borders
Run `cw doctor`. If tacky-borders is missing the download failed: get the `.exe` from <https://github.com/lukeyou05/tacky-borders/releases>, save it as `~\.config\caelestia-win\bin\tacky-borders.exe`, then run `cw theme`. Antivirus or SmartScreen may block an unsigned file: allow it, or run the installer with `-SkipBorders` for komorebi's plain borders (`komorebic border enable` if they are off).

## My running apps do not show in the bar
The bar's `taskbar` widget lists them. Some windows are filtered by `strict_filtering`; set it to `false` under `widgets.taskbar.options` in `~\.config\yasb\config.yaml`.

## Colours do not change after `cw wallpaper next`
If you picked a preset with `cw preset <name>`, colours stay on that preset. Run `cw preset auto` to follow the wallpaper again. If Pillow is missing: `python -m pip install --user pillow`.

## winget could not install a package
The installer continues and prints the manual command. All IDs: `LGUG2Z.komorebi`, `LGUG2Z.whkd`, `AmN.yasb`, `Flow-Launcher.Flow-Launcher`, `DEVCOM.JetBrainsMonoNerdFont`, `Python.Python.3.12`. Search with `winget search <name>` if one has been renamed.

## Script execution is disabled
You never have to change the global policy. Always run scripts as `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`. The installer, `cw.cmd` and the autostart entry already do.

## Start over
`Uninstall.ps1 -RestoreBackup` brings back your earlier komorebi/whkd/YASB configs.
