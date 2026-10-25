#!/usr/bin/env python3
"""caelestia-win theme generator.

Windows has no equivalent of Caelestia's "colours follow the wallpaper" feature,
so this script provides it. It reads a wallpaper, picks a dominant colour, builds
a Material 3 style tonal palette from it, and writes that palette into:

  * the YASB bar stylesheet   (rendered from templates/yasb.styles.css.tmpl)
  * komorebi window borders   (only the "border_colours" key of komorebi.json)
  * a Windows Terminal colour scheme fragment (to paste into settings.json)
  * colors.json               (every colour, for your own scripts)

Standard library + Pillow only. Pillow is needed just to read the image.

Note: this is a close approximation of Material You, not a bit-exact port. Tones
are real CIE L* tones and hue comes from CIE LCh instead of CAM16, so colours are
very similar to, but not identical with, what Android or Caelestia on Linux give.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Colour maths (sRGB <-> CIE Lab / LCh, D65)
# --------------------------------------------------------------------------

_M = (
    (0.4124564, 0.3575761, 0.1804375),
    (0.2126729, 0.7151522, 0.0721750),
    (0.0193339, 0.1191920, 0.9503041),
)
_MINV = (
    (3.2404542, -1.5371385, -0.4985314),
    (-0.9692660, 1.8760108, 0.0415560),
    (0.0556434, -0.2040259, 1.0572252),
)
_WHITE = (0.95047, 1.0, 1.08883)
_EPS = (6 / 29) ** 3
_KAPPA = 1 / (3 * (6 / 29) ** 2)


def _to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _from_linear(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def _f(t: float) -> float:
    return t ** (1 / 3) if t > _EPS else _KAPPA * t + 4 / 29


def _finv(t: float) -> float:
    return t ** 3 if t ** 3 > _EPS else (t - 4 / 29) / _KAPPA


def rgb_to_lab(r: int, g: int, b: int) -> tuple[float, float, float]:
    lin = [_to_linear(v / 255) for v in (r, g, b)]
    xyz = [sum(_M[i][j] * lin[j] for j in range(3)) / _WHITE[i] for i in range(3)]
    fx, fy, fz = (_f(v) for v in xyz)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def _lab_to_linear_rgb(L: float, a: float, b: float) -> tuple[float, float, float]:
    fy = (L + 16) / 116
    fx = fy + a / 500
    fz = fy - b / 200
    x, y, z = (_finv(fx) * _WHITE[0], _finv(fy) * _WHITE[1], _finv(fz) * _WHITE[2])
    return tuple(  # type: ignore[return-value]
        _MINV[i][0] * x + _MINV[i][1] * y + _MINV[i][2] * z for i in range(3)
    )


def _in_gamut(rgb: tuple[float, float, float]) -> bool:
    return all(-1e-4 <= v <= 1 + 1e-4 for v in rgb)


def tone_color(tone: float, chroma: float, hue: float) -> tuple[int, int, int]:
    """sRGB colour with exact CIE L* == tone and hue; chroma is reduced until it fits sRGB."""
    tone = max(0.0, min(100.0, tone))
    if tone <= 0.0:
        return (0, 0, 0)
    if tone >= 100.0:
        return (255, 255, 255)
    hr = math.radians(hue)

    def lin_at(c: float) -> tuple[float, float, float]:
        return _lab_to_linear_rgb(tone, c * math.cos(hr), c * math.sin(hr))

    lin = lin_at(chroma)
    if not _in_gamut(lin):
        lo, hi = 0.0, chroma
        for _ in range(30):
            mid = (lo + hi) / 2
            if _in_gamut(lin_at(mid)):
                lo = mid
            else:
                hi = mid
        lin = lin_at(lo)
    out = []
    for v in lin:
        v = min(1.0, max(0.0, v))
        out.append(int(round(_from_linear(v) * 255)))
    return (out[0], out[1], out[2])


def to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def from_hex(value: str) -> tuple[int, int, int]:
    value = value.strip().lstrip("#")
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    if not re.fullmatch(r"[0-9a-fA-F]{6}", value):
        raise ValueError(f"not a hex colour: {value!r}")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = (_to_linear(v / 255) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# --------------------------------------------------------------------------
# Picking a seed from a wallpaper
# --------------------------------------------------------------------------

DEFAULT_SEED_HEX = "#9a82db"  # soft lavender, close to Caelestia's default look

# Named seed colours. `--preset NAME` / `cw preset NAME` use these instead of reading the wallpaper.
PRESETS = {
    "lavender": "#9a82db",   # default
    "rose":     "#e0709a",
    "sunset":   "#ef8a62",
    "amber":    "#dfa63e",
    "forest":   "#5aaa6a",
    "mint":     "#3fb8a0",
    "ocean":    "#4a8fe0",
    "sky":      "#35b0d8",
    "orchid":   "#d36fd0",
}


def hue_of(rgb: tuple[int, int, int]) -> float:
    _, a, b = rgb_to_lab(*rgb)
    return math.degrees(math.atan2(b, a)) % 360


def extract_hue(image_path: Path) -> tuple[float, float] | None:
    """Return (hue, mean_chroma) of the dominant colourful region, or None if the image is grey."""
    from PIL import Image  # imported lazily so the rest works without Pillow

    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im.thumbnail((96, 96))
        # Pillow 12+ deprecates getdata(); prefer get_flattened_data() when it exists
        getter = getattr(im, "get_flattened_data", None) or im.getdata
        pixels = list(getter())

    bins = 24
    weight = [0.0] * bins
    vx = [0.0] * bins
    vy = [0.0] * bins
    csum = [0.0] * bins
    for r, g, b in pixels:
        L, a, bb = rgb_to_lab(r, g, b)
        C = math.hypot(a, bb)
        if L < 12 or L > 95 or C < 10:
            continue
        h = math.atan2(bb, a)
        # favour saturated, mid-tone pixels (Material's scorer likes these too)
        w = C * (1.0 - abs(L - 55) / 90.0)
        idx = int((math.degrees(h) % 360) / (360 / bins)) % bins
        weight[idx] += w
        vx[idx] += w * math.cos(h)
        vy[idx] += w * math.sin(h)
        csum[idx] += w * C
    if sum(weight) <= 0:
        return None
    # smooth over neighbouring bins so one noisy bin cannot win
    scores = [
        weight[i] + 0.5 * weight[(i - 1) % bins] + 0.5 * weight[(i + 1) % bins]
        for i in range(bins)
    ]
    best = max(range(bins), key=lambda i: scores[i])
    group = [(best - 1) % bins, best, (best + 1) % bins]
    x = sum(vx[i] for i in group)
    y = sum(vy[i] for i in group)
    w = sum(weight[i] for i in group)
    if w <= 0:
        return None
    return math.degrees(math.atan2(y, x)) % 360, sum(csum[i] for i in group) / w


# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

# chroma (CIE LCh) per palette, and tertiary hue offset
VARIANTS = {
    "tonal":   dict(p=40, s=16, t=28, n=4, nv=8,  shift=60),
    "vibrant": dict(p=64, s=34, t=44, n=6, nv=12, shift=70),
    "muted":   dict(p=14, s=8,  t=14, n=3, nv=5,  shift=40),
    "mono":    dict(p=0,  s=0,  t=0,  n=0, nv=0,  shift=0),
}

# role -> (palette key, tone) for each mode
_DARK = {
    "primary": ("p", 80), "on_primary": ("p", 20),
    "primary_container": ("p", 30), "on_primary_container": ("p", 90),
    "secondary": ("s", 80), "on_secondary": ("s", 20),
    "secondary_container": ("s", 30), "on_secondary_container": ("s", 90),
    "tertiary": ("t", 80), "on_tertiary": ("t", 20),
    "tertiary_container": ("t", 30), "on_tertiary_container": ("t", 90),
    "background": ("n", 6), "on_background": ("n", 90),
    "surface": ("n", 6), "surface_dim": ("n", 6), "surface_bright": ("n", 24),
    "surface_container_lowest": ("n", 4), "surface_container_low": ("n", 10),
    "surface_container": ("n", 12), "surface_container_high": ("n", 17),
    "surface_container_highest": ("n", 22),
    "on_surface": ("n", 90), "on_surface_variant": ("nv", 80),
    "outline": ("nv", 60), "outline_variant": ("nv", 30),
    "inverse_surface": ("n", 90), "inverse_on_surface": ("n", 20),
    "inverse_primary": ("p", 40),
}
_LIGHT = {
    "primary": ("p", 40), "on_primary": ("p", 100),
    "primary_container": ("p", 90), "on_primary_container": ("p", 10),
    "secondary": ("s", 40), "on_secondary": ("s", 100),
    "secondary_container": ("s", 90), "on_secondary_container": ("s", 10),
    "tertiary": ("t", 40), "on_tertiary": ("t", 100),
    "tertiary_container": ("t", 90), "on_tertiary_container": ("t", 10),
    "background": ("n", 98), "on_background": ("n", 10),
    "surface": ("n", 98), "surface_dim": ("n", 87), "surface_bright": ("n", 98),
    "surface_container_lowest": ("n", 100), "surface_container_low": ("n", 96),
    "surface_container": ("n", 94), "surface_container_high": ("n", 92),
    "surface_container_highest": ("n", 90),
    "on_surface": ("n", 10), "on_surface_variant": ("nv", 30),
    "outline": ("nv", 50), "outline_variant": ("nv", 80),
    "inverse_surface": ("n", 20), "inverse_on_surface": ("n", 95),
    "inverse_primary": ("p", 80),
}
_ERROR = {
    "dark": {"error": "#ffb4ab", "on_error": "#690005",
             "error_container": "#93000a", "on_error_container": "#ffdad6"},
    "light": {"error": "#ba1a1a", "on_error": "#ffffff",
              "error_container": "#ffdad6", "on_error_container": "#410002"},
}


def build_scheme(hue: float, mode: str = "dark", variant: str = "tonal") -> dict[str, str]:
    if mode not in ("dark", "light"):
        raise ValueError("mode must be 'dark' or 'light'")
    if variant not in VARIANTS:
        raise ValueError(f"variant must be one of {sorted(VARIANTS)}")
    v = VARIANTS[variant]
    hues = {"p": hue, "s": hue, "t": (hue + v["shift"]) % 360, "n": hue, "nv": hue}
    roles = _DARK if mode == "dark" else _LIGHT
    scheme = {
        name: to_hex(tone_color(tone, v[key], hues[key]))
        for name, (key, tone) in roles.items()
    }
    scheme.update(_ERROR[mode])
    scheme["shadow"] = "#000000"
    scheme["scrim"] = "#000000"
    return scheme


def terminal_scheme(scheme: dict[str, str], mode: str) -> dict[str, str]:
    """Windows Terminal scheme: 6 fixed hues, tinted and brightness-matched to the palette."""
    normal, bright = (68, 80) if mode == "dark" else (40, 52)
    chroma = 46
    hues = {"red": 25, "green": 142, "yellow": 95, "blue": 262, "purple": 325, "cyan": 200}
    out = {
        "name": "Caelestia Dynamic",
        "background": scheme["surface"],
        "foreground": scheme["on_surface"],
        "cursorColor": scheme["primary"],
        "selectionBackground": scheme["primary_container"],
        "black": scheme["surface_container_high"] if mode == "dark" else scheme["on_surface"],
        "white": scheme["on_surface_variant"] if mode == "dark" else scheme["surface_container_high"],
        "brightBlack": scheme["outline"],
        "brightWhite": scheme["on_surface"] if mode == "dark" else scheme["surface"],
    }
    for name, h in hues.items():
        out[name] = to_hex(tone_color(normal, chroma, h))
        out["bright" + name.capitalize()] = to_hex(tone_color(bright, chroma, h))
    return out


# --------------------------------------------------------------------------
# Writers
# --------------------------------------------------------------------------

_TOKEN = re.compile(r"\{\{\s*([a-z0-9_]+)\s*\}\}")


def render_template(text: str, scheme: dict[str, str]) -> str:
    tokens = dict(scheme)
    for name, value in scheme.items():
        r, g, b = from_hex(value)
        tokens[name + "_rgb"] = f"{r}, {g}, {b}"

    def sub(match: re.Match) -> str:
        key = match.group(1)
        if key not in tokens:
            raise KeyError(f"unknown colour token in template: {key}")
        return tokens[key]

    return _TOKEN.sub(sub, text)


def _rgb_dict(hex_value: str) -> dict[str, int]:
    r, g, b = from_hex(hex_value)
    return {"r": r, "g": g, "b": b}


def patch_komorebi(path: Path, scheme: dict[str, str], native_border: bool | None = None) -> bool:
    """Only touches 'border_colours' (and 'border' when native_border is given). True if the file was updated."""
    if not path.is_file():
        return False
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if native_border is not None:
        data["border"] = native_border
    data["border_colours"] = {
        "single": _rgb_dict(scheme["primary"]),
        "stack": _rgb_dict(scheme["tertiary"]),
        "monocle": _rgb_dict(scheme["secondary"]),
        "floating": _rgb_dict(scheme["outline"]),
        "unfocused": _rgb_dict(scheme["surface_container_highest"]),
    }
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return True


def default_komorebi_json() -> Path:
    home = os.environ.get("KOMOREBI_CONFIG_HOME")
    base = Path(home) if home else Path.home() / ".config" / "komorebi"
    return base / "komorebi.json"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Generate a wallpaper-driven colour scheme for caelestia-win")
    ap.add_argument("--image", type=Path, help="wallpaper to take the colour from")
    ap.add_argument("--seed", help="hex colour to use instead of reading an image, e.g. #8844cc")
    ap.add_argument("--preset", choices=sorted(PRESETS), help="named seed colour instead of reading an image")
    ap.add_argument("--list-presets", action="store_true", help="list the preset names and exit")
    ap.add_argument("--mode", choices=("dark", "light"), default="dark")
    ap.add_argument("--variant", choices=sorted(VARIANTS), default="tonal")
    ap.add_argument("--home", type=Path, default=Path.home() / ".config" / "caelestia-win",
                    help="caelestia-win config folder (holds templates/ and receives colors.json)")
    ap.add_argument("--templates", type=Path, help="templates folder (default: <home>/templates)")
    ap.add_argument("--yasb-dir", type=Path, default=Path.home() / ".config" / "yasb")
    ap.add_argument("--komorebi-json", type=Path, default=None)
    ap.add_argument("--tacky-dir", type=Path, default=None,
                    help="tacky-borders config folder; when given, its config.yaml is generated and komorebi's own border is turned off")
    ap.add_argument("--no-yasb", action="store_true")
    ap.add_argument("--no-komorebi", action="store_true")
    ap.add_argument("--print", dest="print_only", action="store_true",
                    help="print the generated scheme as JSON and write nothing")
    args = ap.parse_args(argv)

    if args.list_presets:
        for name, hex_value in PRESETS.items():
            print(f"{name:10s} {hex_value}")
        return 0

    # 1. choose the hue
    source = "default"
    hue = hue_of(from_hex(DEFAULT_SEED_HEX))
    if args.preset:
        hue = hue_of(from_hex(PRESETS[args.preset]))
        source = f"preset {args.preset}"
    elif args.seed:
        hue = hue_of(from_hex(args.seed))
        source = f"seed {args.seed}"
    elif args.image:
        if not args.image.is_file():
            print(f"theme.py: image not found: {args.image}", file=sys.stderr)
            return 2
        try:
            found = extract_hue(args.image)
        except ImportError:
            print("theme.py: Pillow is missing. Run: python -m pip install --user pillow", file=sys.stderr)
            return 3
        if found is None:
            source = "image is nearly grey, using the default seed"
        else:
            hue = found[0]
            source = f"image {args.image.name}"

    scheme = build_scheme(hue, args.mode, args.variant)
    summary = {"source": source, "hue": round(hue, 1), "mode": args.mode,
               "variant": args.variant, "colors": scheme}
    if args.print_only:
        print(json.dumps(summary, indent=2))
        return 0

    # 2. write outputs
    args.home.mkdir(parents=True, exist_ok=True)
    (args.home / "colors.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    written = ["colors.json"]

    term_dir = args.home / "colors"
    term_dir.mkdir(exist_ok=True)
    (term_dir / "terminal-scheme.json").write_text(
        json.dumps(terminal_scheme(scheme, args.mode), indent=2) + "\n", encoding="utf-8")
    written.append("colors/terminal-scheme.json")

    if not args.no_yasb:
        tmpl = (args.templates or args.home / "templates") / "yasb.styles.css.tmpl"
        if tmpl.is_file():
            args.yasb_dir.mkdir(parents=True, exist_ok=True)
            css = render_template(tmpl.read_text(encoding="utf-8"), scheme)
            (args.yasb_dir / "styles.css").write_text(css, encoding="utf-8")
            written.append(str(args.yasb_dir / "styles.css"))
        else:
            print(f"theme.py: template missing, skipped YASB: {tmpl}", file=sys.stderr)

    native_border = None
    if args.tacky_dir is not None:
        ttmpl = (args.templates or args.home / "templates") / "tacky-borders.config.yaml.tmpl"
        if ttmpl.is_file():
            args.tacky_dir.mkdir(parents=True, exist_ok=True)
            (args.tacky_dir / "config.yaml").write_text(
                render_template(ttmpl.read_text(encoding="utf-8"), scheme), encoding="utf-8", newline="\n")
            written.append(str(args.tacky_dir / "config.yaml"))
            native_border = False  # tacky-borders draws the borders instead
        else:
            print(f"theme.py: template missing, skipped tacky-borders: {ttmpl}", file=sys.stderr)

    if not args.no_komorebi:
        kpath = args.komorebi_json or default_komorebi_json()
        if patch_komorebi(kpath, scheme, native_border):
            written.append(str(kpath))

    print(f"scheme from {source} (hue {hue:.0f}, {args.mode}, {args.variant})")
    for item in written:
        print("  wrote", item)
    return 0


if __name__ == "__main__":
    sys.exit(main())
