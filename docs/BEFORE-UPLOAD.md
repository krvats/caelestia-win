# Before you upload to GitHub

Do these in order. Steps 1 to 3 take about 15 minutes and decide whether anyone stars the project.

## 1. Test it on your own PC

- [ ] Run `Setup.bat` (or `Install.ps1`) to the end and sign out and in once.
- [ ] Open a **new** terminal and run `cw doctor`. Everything should say OK.
- [ ] Try `Alt+Enter` twice, `Alt+2`, `Alt+W`, `Alt+Space`, `Alt+Shift+T`.
- [ ] Run `Uninstall.ps1` once on a spare machine or VM if you can, then install again. People will do both.

## 2. Add real screenshots

- [ ] `cw preset lavender`, open a few windows, press `Alt+P`. Repeat for two or three other presets and for light mode.
- [ ] Copy the images from `Pictures\caelestia-win-screenshots` to `docs\screenshots`, named `lavender.png`, `ocean.png`, `light.png`.
- [ ] Optional but very effective: a 10 second GIF (`docs\screenshots\demo.gif`). See [SCREENSHOTS.md](SCREENSHOTS.md).
- [ ] Put the best screenshot in the README in place of the concept render.

## 3. Check what you are publishing

- [ ] Search the folder for anything personal: your name in paths, tokens, e-mail addresses. (The project contains none, but check anything you added.)
- [ ] The default wallpaper in `wallpapers\` must be yours or free to use. Say where it came from in the README credits.
- [ ] Keep the "not affiliated with Caelestia" line in the README. Do not use the Caelestia logo.
- [ ] Open `LICENSE` and put your name in the copyright line.

## 4. Choose the repository name

Use **`caelestia-win`**.

- It matches the project name, the folder and the `cw` command.
- It contains both words people search: *caelestia* and *win(dows)*.
- It is short enough to type and to remember.

Other good options if it is taken: `caelestia-windows-rice` or `windows-caelestia`. Avoid names with only a nickname, since search engines cannot connect them to the topic. Another repository called `caelestia-windows` already exists, so a different name also avoids confusion.

## 5. Upload (automatic)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Publish.ps1
```

It installs Git and the GitHub CLI if needed, signs you in through the browser, fills in your username everywhere, creates the repository, pushes the code, sets the description and topics, and turns on GitHub Pages. Use `-RepoName name` for a different name and `-Private` to keep it private at first.

Prefer doing it by hand? Create an empty repository on github.com, then:

```powershell
python tools\set_repo.py YOUR-GITHUB-USERNAME
git init -b main
git add -A
git commit -m "caelestia-win: first release"
git remote add origin https://github.com/YOUR-GITHUB-USERNAME/caelestia-win.git
git push -u origin main
```

## 6. After uploading

- [ ] Settings → General → **Social preview**: upload a 1280×640 image (the only step GitHub does not allow by command).
- [ ] Check the **Actions** tab: CI should turn green.
- [ ] Create a release: Releases → new release → tag `v1.1.2` → paste the CHANGELOG entry.
- [ ] Open the Pages link once to confirm the landing page works.
- [ ] Share it (see [GITHUB-SETUP.md](GITHUB-SETUP.md)) and answer the first issues quickly.
