# Contributing

Thanks for helping. The project is small on purpose: configs, a colour generator, and two PowerShell scripts.

## Setup

```powershell
git clone https://github.com/krvats/caelestia-win
cd caelestia-win
python -m pip install pillow pyyaml
python tests/test_theme.py
```

## Rules of thumb

- **`.ps1` files must stay ASCII-only.** Windows PowerShell 5.1 reads BOM-less files as ANSI and mangles other characters. Icons belong in `config/yasb/config.yaml`, which is read as UTF-8.
- Write config files as UTF-8 **without BOM** (komorebi's JSON parser rejects a BOM). Use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- Qt stylesheets are not CSS: no `var()`, no `box-shadow`, no `gap`. The test suite checks this.
- `styles.css` is generated. Change `templates/yasb.styles.css.tmpl`.
- Changed a palette, the bar or a preset? Run `python tools/make_previews.py` and commit `docs/assets`.

## Screenshots wanted

The images in the README are concept renders drawn from the real palettes. Real screenshots are very welcome: put them in `docs/assets/screenshots/` and open a pull request.

## Reporting bugs

Include the output of `cw doctor`, your Windows build, and `komorebic --version` / `yasbc --version`.
