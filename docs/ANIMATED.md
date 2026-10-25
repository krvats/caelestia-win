# Animated wallpapers

Video and GIF wallpapers for caelestia-win. This follows the idea of [caelestia-aw](https://github.com/AdiAmbassador/caelestia-aw), a fork that adds animated wallpapers to Caelestia on Linux. On Windows the video is played by [Lively Wallpaper](https://github.com/rocksdanister/lively) (free, open source), and caelestia-win adds the rest: colours from the video, a library with thumbnails, pause rules and the `cw live` command.

## Set it up (one time)

Any one of these:

- Click **Wallpaper > Animated > Install animated wallpaper support** in the settings window (`Alt` `S`)
- Run `cw live install`
- Install with `Install.ps1 -WithAnimated`

This installs Lively Wallpaper and FFmpeg through winget. Lively plays the video, FFmpeg takes a still frame so the desktop colours can follow it and thumbnails can be shown. Without FFmpeg the video still plays, only the colours and thumbnails are missing.

## Add wallpapers

Put `.mp4`, `.webm`, `.mkv`, `.mov`, `.avi` or `.gif` files in `~\Pictures\Wallpapers\Animated` (the settings window has an **Add files ...** button that copies them there).

## Use them

| Do this | Result |
|---|---|
| `Ctrl` `Alt` `W` or `cw live next` | Next animated wallpaper, desktop recolours from a frame of it |
| `cw live random`, `cw live prev` | Random or previous one |
| `cw live set C:\path\clip.mp4` | A specific file (a bare file name inside the Animated folder works too) |
| `Ctrl` `Alt` `Shift` `W` or `cw live stop` | Back to your picture wallpaper |
| `Alt` `W` (normal wallpaper keys) | Also switches back to pictures: a picture always replaces the animation |
| `cw live pause` / `cw live resume` | Pause or resume by hand |
| `cw live volume 0` ... `100` | Sound level (default 0, muted) |
| `cw live list`, `cw live status` | What is in the library, what is playing and which rules are on |

## Pause rules (saves battery and gaming performance)

A small background guard (`live-guard.ps1`) checks every few seconds:

- **On battery power:** the animation pauses, and resumes when you plug in.
- **An app is fullscreen** (a game or a video): the animation pauses, and resumes afterwards.

Both are on by default. Switch them off per rule:

```powershell
cw live rules battery off
cw live rules fullscreen off
```

or untick them on the **Wallpaper > Animated** page of the settings window. The guard stops by itself when no animated wallpaper is active. Lively also has its own performance options (Settings > Performance); the two do not clash.

## Hardware decoding

If the video stutters, open Lively's own settings with `cw live settings` and try another video player or hardware decoding (Settings > Wallpaper / Performance). caelestia-aw offers the same choice for its Linux decoder.

## Tips

- Smaller is smoother: 1080p at 30 fps looks great and costs far less than 4K at 60 fps.
- H.264 `.mp4` is the safest format. WebM and MKV depend on the codecs inside.
- With several monitors the same video is shown on every screen.
- A thumbnail is made once per file and re-made only when the file changes. Delete `~\.config\caelestia-win\thumbs` to rebuild them.
- Lively starts with Windows and keeps your animated wallpaper after a restart. It lives in the tray; its own window can stay closed.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Lively Wallpaper is not installed" | `cw live install` |
| Video plays but colours do not change | FFmpeg is missing: `cw live install`, then `cw live next` |
| Thumbnails are grey play icons | The same: FFmpeg is missing, or run `cw live thumbs` |
| Wallpaper stays black | Try another file; open `cw live settings` and pick a different video player |
| The animation never pauses | `cw live status` shows whether the rules are on; the guard starts with the next `cw live set` or after sign-in |
