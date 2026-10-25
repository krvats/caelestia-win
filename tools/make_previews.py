"""Renders the SVG graphics used in the README into docs/assets.

These are *concept renders* drawn from the real colour palettes that scripts/theme.py generates.
They show the intended layout and colours; they are not screenshots. Replace them with real
screenshots whenever you like (see docs/CONTRIBUTING.md).

    python tools/make_previews.py
"""
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import theme  # noqa: E402

OUT = ROOT / "docs" / "assets"
SANS = "'Segoe UI Variable','Segoe UI',Inter,'Helvetica Neue',Arial,sans-serif"
MONO = "'JetBrains Mono','Cascadia Code',Consolas,'SF Mono',monospace"


def t(x, y, s, fill, size=13, weight=500, anchor="start", family=SANS, opacity=1.0, spacing=0):
    return (f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}" font-weight="{weight}" '
            f'text-anchor="{anchor}" font-family="{family}" fill-opacity="{opacity}" '
            f'letter-spacing="{spacing}">{escape(s)}</text>')


def rect(x, y, w, h, r, fill, stroke=None, sw=1, op=1.0, sop=1.0):
    st = f' stroke="{stroke}" stroke-width="{sw}" stroke-opacity="{sop}"' if stroke else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" fill-opacity="{op}"{st}/>'


def sparkle(cx, cy, r, fill):
    k = r * 0.22
    d = (f"M{cx},{cy - r} C{cx + k},{cy - k} {cx + k},{cy - k} {cx + r},{cy} "
         f"C{cx + k},{cy + k} {cx + k},{cy + k} {cx},{cy + r} "
         f"C{cx - k},{cy + k} {cx - k},{cy + k} {cx - r},{cy} "
         f"C{cx - k},{cy - k} {cx - k},{cy - k} {cx},{cy - r}Z")
    return f'<path d="{d}" fill="{fill}"/>'


def defs(s, w, h, uid):
    return f"""<defs>
  <linearGradient id="bg{uid}" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{s['surface_container_lowest']}"/>
    <stop offset="0.55" stop-color="{s['surface']}"/>
    <stop offset="1" stop-color="{s['primary_container']}"/>
  </linearGradient>
  <radialGradient id="g1{uid}" cx="0.22" cy="0.25" r="0.55">
    <stop offset="0" stop-color="{s['primary']}" stop-opacity="0.38"/><stop offset="1" stop-color="{s['primary']}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="g2{uid}" cx="0.82" cy="0.78" r="0.5">
    <stop offset="0" stop-color="{s['tertiary']}" stop-opacity="0.30"/><stop offset="1" stop-color="{s['tertiary']}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="bd{uid}" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0" stop-color="{s['primary']}"/><stop offset="1" stop-color="{s['tertiary']}"/>
  </linearGradient>
  <filter id="glow{uid}" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="7"/></filter>
</defs>
<rect width="{w}" height="{h}" fill="url(#bg{uid})"/>
<rect width="{w}" height="{h}" fill="url(#g1{uid})"/>
<rect width="{w}" height="{h}" fill="url(#g2{uid})"/>"""


def bar(s, x, y, w, label):
    """A floating-pill bar, same structure as config/yasb/config.yaml."""
    out = []
    pill = lambda px, pw: rect(px, y, pw, 34, 17, s["surface_container"], s["outline_variant"], 1, 0.92, 0.6)
    # left: home, workspaces, layout
    out.append(pill(x, 212))
    out.append(sparkle(x + 22, y + 17, 8, s["primary"]))
    cx = x + 46
    for i in range(5):
        if i == 1:
            out.append(rect(cx, y + 12, 22, 10, 5, s["primary"]))
            cx += 28
        else:
            out.append(rect(cx, y + 12, 10, 10, 5, s["outline"] if i in (0, 2) else s["outline_variant"]))
            cx += 16
    out.append(t(x + 46 + 118, y + 22, "BSP", s["tertiary"], 11, 700, spacing=0.5))
    # running apps (the YASB taskbar widget): first one is focused
    ax = x + 224
    out.append(pill(ax, 4 * 34 + 14))
    for i, col in enumerate((s["primary"], s["tertiary"], s["secondary"], s["outline"])):
        bx = ax + 8 + i * 34
        if i == 0:
            out.append(rect(bx, y + 4, 30, 26, 12, s["primary_container"]))
        elif i == 1:
            out.append(rect(bx, y + 4, 30, 26, 12, s["surface_container_high"]))
        out.append(rect(bx + 7, y + 9, 16, 16, 5, col))
    # centre: clock
    cw_ = 108
    out.append(rect(x + w / 2 - cw_ / 2, y, cw_, 34, 17, s["primary_container"], s["primary"], 1, 0.95, 0.35))
    out.append(t(x + w / 2, y + 22, "09:41", s["on_primary_container"], 14, 700, "middle"))
    # right: stats
    rw = 318
    rx = x + w - rw
    out.append(pill(rx, rw))
    items = [("CPU 12%", s["secondary"]), ("RAM 41%", s["tertiary"]), ("VOL 60", s["primary"])]
    cx = rx + 16
    for label_, col in items:
        out.append(f'<circle cx="{cx + 4}" cy="{y + 17}" r="4" fill="{col}"/>')
        out.append(t(cx + 14, y + 21.5, label_, s["on_surface"], 11.5))
        cx += 82
    out.append(f'<circle cx="{rx + rw - 22}" cy="{y + 17}" r="6" fill="none" stroke="{s["error"]}" stroke-width="2"/>')
    out.append(f'<line x1="{rx + rw - 22}" y1="{y + 10.5}" x2="{rx + rw - 22}" y2="{y + 16}" stroke="{s["error"]}" stroke-width="2" stroke-linecap="round"/>')
    return "\n".join(out)


def window(s, term, x, y, w, h, title, focused, body, uid="d"):
    border = f"url(#bd{uid})" if focused else s["surface_container_highest"]
    out = ["<g>"]
    if focused:
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="none" stroke="url(#bd{uid})" '
                   f'stroke-width="6" stroke-opacity="0.55" filter="url(#glow{uid})"/>')
    out.append(rect(x, y, w, h, 12, s["surface_container_low"], border, 3 if focused else 2))
    out.append(rect(x + 1.5, y + 1.5, w - 3, 30, 10, s["surface_container"]))
    for i, col in enumerate((s["outline_variant"], s["outline_variant"], s["outline_variant"])):
        out.append(f'<circle cx="{x + 20 + i * 16}" cy="{y + 17}" r="4.5" fill="{col}"/>')
    out.append(t(x + w / 2, y + 21, title, s["on_surface_variant"], 12, 500, "middle"))
    out.append(body)
    out.append("</g>")
    return "\n".join(out)


def terminal_body(s, term, x, y, w):
    lines = [
        [("~ ", term["blue"]), ("cw preset ", s["on_surface"]), ("ocean", term["purple"])],
        [("scheme from preset ocean", s["on_surface_variant"])],
        [("  wrote ", term["green"]), ("styles.css", s["on_surface"])],
        [("~ ", term["blue"]), ("cw scheme ", s["on_surface"]), ("toggle", term["yellow"])],
        [("~ ", term["blue"]), ("▌", s["primary"])],
    ]
    out = []
    for i, parts in enumerate(lines):
        cx = x + 18
        for text, col in parts:
            out.append(t(cx, y + 58 + i * 22, text, col, 12.5, 500, family=MONO))
            cx += len(text) * 7.55
    return "\n".join(out)


def list_body(s, x, y, w, h):
    out = []
    for i, (name, col) in enumerate([("Wallpapers", s["primary"]), ("Projects", s["tertiary"]),
                                     ("Downloads", s["secondary"]), ("Documents", s["outline"])]):
        yy = y + 50 + i * 40
        out.append(rect(x + 14, yy, w - 28, 32, 9, s["primary_container"] if i == 0 else s["surface_container"], None, 1, 0.9 if i == 0 else 0.7))
        out.append(rect(x + 26, yy + 9, 14, 14, 4, col))
        out.append(t(x + 50, yy + 21, name, s["on_surface"], 12.5))
    return "\n".join(out)


def browser_body(s, x, y, w, h):
    out = [rect(x + 16, y + 44, w - 32, 28, 14, s["surface_container_high"])]
    out.append(t(x + 34, y + 63, "github.com/you/caelestia-win", s["on_surface_variant"], 12))
    cols = [s["primary_container"], s["secondary_container"], s["tertiary_container"]]
    cw_ = (w - 32 - 24) / 3
    for i in range(3):
        out.append(rect(x + 16 + i * (cw_ + 12), y + 88, cw_, 70, 12, cols[i]))
    for i in range(4):
        out.append(rect(x + 16, y + 176 + i * 22, (w - 32) * (0.9 - i * 0.14), 8, 4, s["outline_variant"], None, 1, 0.8))
    return "\n".join(out)


def desktop(preset=None, mode="dark", w=1280, h=720, uid="d"):
    seed = theme.PRESETS[preset or "lavender"]
    s = theme.build_scheme(theme.hue_of(theme.from_hex(seed)), mode, "tonal")
    term = theme.terminal_scheme(s, mode)
    gap, top = 18, 70
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" '
           f'aria-label="caelestia-win concept render, {preset or "lavender"} {mode}">', defs(s, w, h, uid)]
    out.append(bar(s, 16, 14, w - 32, ""))
    lw = int((w - gap * 3) * 0.54)
    rw = w - gap * 3 - lw
    rh = (h - top - gap * 3) // 2
    out.append(window(s, term, gap, top, lw, h - top - gap, "Windows Terminal", True,
                      terminal_body(s, term, gap, top, lw), uid))
    out.append(window(s, term, gap * 2 + lw, top, rw, rh, "Browser", False,
                      browser_body(s, gap * 2 + lw, top, rw, rh), uid))
    out.append(window(s, term, gap * 2 + lw, top + rh + gap, rw, rh, "Files", False,
                      list_body(s, gap * 2 + lw, top + rh + gap, rw, rh), uid))
    out.append("</svg>")
    return "\n".join(out)


def banner(w=1280, h=380):
    s = theme.build_scheme(theme.hue_of(theme.from_hex(theme.PRESETS["lavender"])), "dark", "tonal")
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="caelestia-win">',
           defs(s, w, h, "b")]
    import random
    rnd = random.Random(11)
    for _ in range(70):
        out.append(f'<circle cx="{rnd.uniform(0, w):.0f}" cy="{rnd.uniform(0, h):.0f}" r="{rnd.uniform(0.6, 1.7):.1f}" fill="{s["on_surface"]}" fill-opacity="{rnd.uniform(0.15, 0.6):.2f}"/>')
    out.append(sparkle(w / 2, 96, 30, s["primary"]))
    out.append(sparkle(w / 2 + 52, 70, 9, s["tertiary"]))
    out.append(sparkle(w / 2 - 48, 120, 6, s["secondary"]))
    out.append(t(w / 2, 190, "caelestia-win", s["on_surface"], 64, 700, "middle", spacing=-1.5))
    out.append(t(w / 2, 232, "A Caelestia-style desktop for Windows 10 & 11", s["on_surface_variant"], 21, 400, "middle"))
    chips = ["komorebi", "whkd", "YASB", "Flow Launcher", "wallpaper colours"]
    widths = [len(c) * 8.4 + 34 for c in chips]
    total = sum(widths) + 12 * (len(chips) - 1)
    x = (w - total) / 2
    for c, cw_ in zip(chips, widths):
        out.append(rect(x, 276, cw_, 34, 17, s["surface_container"], s["outline_variant"], 1, 0.85, 0.7))
        out.append(t(x + cw_ / 2, 298, c, s["on_surface"], 13.5, 500, "middle"))
        x += cw_ + 12
    out.append("</svg>")
    return "\n".join(out)


def presets_sheet():
    names = list(theme.PRESETS)
    cols, cw_, ch = 3, 400, 168
    rows = (len(names) + cols - 1) // cols
    w, h = cols * cw_ + 24, rows * ch + 24
    base = theme.build_scheme(theme.hue_of(theme.from_hex(theme.PRESETS["lavender"])), "dark", "tonal")
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="colour presets">',
           rect(0, 0, w, h, 0, "#0f0e13")]
    for i, name in enumerate(names):
        s = theme.build_scheme(theme.hue_of(theme.from_hex(theme.PRESETS[name])), "dark", "tonal")
        x, y = 12 + (i % cols) * cw_, 12 + (i // cols) * ch
        out.append(rect(x, y, cw_ - 12, ch - 12, 18, s["surface"], s["outline_variant"], 1))
        out.append(rect(x + 14, y + 14, cw_ - 40, 34, 17, s["surface_container"], s["outline_variant"], 1, 0.9, 0.6))
        out.append(rect(x + 20, y + 26, 22, 10, 5, s["primary"]))
        out.append(rect(x + 48, y + 26, 10, 10, 5, s["outline"]))
        out.append(rect(x + 64, y + 26, 10, 10, 5, s["outline_variant"]))
        out.append(rect(x + (cw_ - 12) / 2 - 36, y + 18, 72, 26, 13, s["primary_container"]))
        out.append(t(x + (cw_ - 12) / 2, y + 36, "09:41", s["on_primary_container"], 12.5, 700, "middle"))
        out.append(t(x + 18, y + 78, name, s["on_surface"], 17, 700))
        out.append(t(x + cw_ - 38, y + 78, theme.PRESETS[name], s["on_surface_variant"], 12, 500, "end", MONO))
        sw = [s["primary"], s["secondary"], s["tertiary"], s["primary_container"], s["secondary_container"],
              s["tertiary_container"], s["surface_container_high"], s["outline"]]
        for j, col in enumerate(sw):
            out.append(rect(x + 18 + j * 43, y + 98, 38, 38, 11, col))
    out.append("</svg>")
    return "\n".join(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "banner.svg": banner(),
        "preview-lavender.svg": desktop("lavender", "dark", uid="a"),
        "preview-ocean.svg": desktop("ocean", "dark", uid="b"),
        "preview-rose.svg": desktop("rose", "dark", uid="c"),
        "preview-light.svg": desktop("mint", "light", uid="d"),
        "presets.svg": presets_sheet(),
    }
    for name, svg in files.items():
        (OUT / name).write_text(svg + "\n", encoding="utf-8")
        print("wrote", OUT / name)


if __name__ == "__main__":
    main()
