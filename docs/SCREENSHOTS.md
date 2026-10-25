# Screenshots

The images in the README are concept renders. **Real screenshots are the single best thing you can add to the repository**, because people decide in seconds whether a desktop project looks good.

## Take them

1. Set your look: `cw preset lavender` (or any preset), a few windows open (terminal, browser, Explorer).
2. Press `Alt` `P`, or run `cw screenshot`. Files land in `Pictures\caelestia-win-screenshots`.
3. Take one per theme, one light mode, one showing the bar close up, one with the launcher open.
4. Put them in `docs/screenshots/` named like `lavender.png`, `ocean.png`, `light.png`, `launcher.png`.
5. Shrink big files at <https://squoosh.app> (aim for under 500 KB each).

## Show them in the README

Replace a concept render with a real one:

```markdown
<img src="docs/screenshots/lavender.png" alt="caelestia-win lavender theme on Windows 11" width="92%">
```

A side-by-side gallery:

```markdown
| Lavender | Ocean | Light |
|---|---|---|
| <img src="docs/screenshots/lavender.png"> | <img src="docs/screenshots/ocean.png"> | <img src="docs/screenshots/light.png"> |
```

## A short demo clip

A 10 second GIF of `Alt` `Enter` ×3, `Alt` `2`, `Alt` `W` explains the project better than any text. Record with ScreenToGif (`winget install NickeManarin.ScreenToGif`), keep it under 5 MB, save as `docs/screenshots/demo.gif` and put it at the top of the README.

## Social preview image

GitHub Settings → General → **Social preview** → upload a 1280×640 PNG (your best screenshot with the project name). This image appears when the link is shared on Discord, X, Reddit and Slack.
