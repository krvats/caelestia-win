# Customizing

## Colours

```powershell
cw preset ocean        # lavender rose sunset amber forest mint sky ocean orchid
cw preset catppuccin   # community themes: catppuccin gruvbox nord rosepine tokyonight dracula everforest onedark solarized
cw preset list         # show every preset and theme
cw preset auto         # follow the wallpaper again
cw variant vibrant     # tonal (default) | vibrant | muted | mono
cw scheme light        # dark | light | toggle
cw wallpaper set C:\path\to\picture.jpg
```

A custom seed colour for scripting: `python ~\.config\caelestia-win\theme.py --seed "#ff7a59"`.

Every colour role (`primary`, `surface_container`, `on_surface`, ...) is written to `~\.config\caelestia-win\colors.json`, so you can reuse the palette in other tools.

## The bar

- **Layout and widgets:** `~\.config\yasb\config.yaml`. Changes reload automatically. Widget reference: <https://github.com/amnweb/yasb/wiki>.
- **Look:** edit `~\.config\caelestia-win\templates\yasb.styles.css.tmpl`, then `cw theme`. Tokens look like `{{primary}}`, `{{surface_container}}` or `rgba({{surface_container_rgb}}, 0.9)`.
- **Move to the bottom:** set `alignment.position: "bottom"` in `config.yaml`.
- **Smaller or larger:** `dimensions.height`.

## Window borders

When tacky-borders is installed, borders come from `~\.config\tacky-borders\config.yaml`, which `cw theme` regenerates from `templates/tacky-borders.config.yaml.tmpl`. Edit the template to change width, radius, glow, or turn on the spinning gradient animation (`animations.enabled: true`). Reference: <https://github.com/lukeyou05/tacky-borders>.

Without it, komorebi draws borders: see `border_width` and `border_style` in `komorebi.json`.

## Tiling

`~\.config\komorebi\komorebi.json`: `default_workspace_padding`, `default_container_padding` (gaps), `border_width`, `animation`, `transparency` (+ `transparency_alpha`, dims unfocused windows, off by default), and the `workspaces` list (rename or add workspaces here, then add matching binds in `whkdrc`).

## Keybinds

`~\.config\whkd\whkdrc`, one `keys : command` per line. Key names: <https://github.com/LGUG2Z/whkd>. Reload with Alt+Shift+O.

## Windows Terminal

`cw theme` writes `~\.config\caelestia-win\colors\terminal-scheme.json`. Paste its contents into the `"schemes"` array of Terminal settings (Ctrl+Shift+,), then set `"colorScheme": "Caelestia Dynamic"` in your profile defaults.

## Flow Launcher

Settings -> Theme. Pick a dark theme to match the dark presets (it is not recoloured automatically).
