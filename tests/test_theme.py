"""Tests for caelestia-win. Run:  python -m pytest tests  (or: python tests/test_theme.py)"""
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import theme  # noqa: E402

HEX = re.compile(r"^#[0-9a-f]{6}$")
HUES = [i * 30 for i in range(12)]
PAIRS = [
    ("on_primary", "primary"), ("on_primary_container", "primary_container"),
    ("on_secondary", "secondary"), ("on_secondary_container", "secondary_container"),
    ("on_tertiary", "tertiary"), ("on_tertiary_container", "tertiary_container"),
    ("on_surface", "surface"), ("on_background", "background"),
    ("on_error", "error"), ("on_error_container", "error_container"),
    ("inverse_on_surface", "inverse_surface"),
]


def ctr(scheme, fg, bg):
    return theme.contrast(theme.from_hex(scheme[fg]), theme.from_hex(scheme[bg]))


class SchemeTests(unittest.TestCase):
    def test_all_hex_valid(self):
        for hue in HUES:
            for variant in theme.VARIANTS:
                for mode in ("dark", "light"):
                    s = theme.build_scheme(hue, mode, variant)
                    for k, v in s.items():
                        self.assertRegex(v, HEX, f"{k} hue={hue} {variant} {mode}")

    def test_contrast(self):
        for hue in HUES:
            for variant in theme.VARIANTS:
                for mode in ("dark", "light"):
                    s = theme.build_scheme(hue, mode, variant)
                    for fg, bg in PAIRS:
                        self.assertGreaterEqual(
                            ctr(s, fg, bg), 4.5, f"{fg}/{bg} hue={hue} {variant} {mode}")
                    self.assertGreaterEqual(ctr(s, "on_surface", "surface"), 7.0)

    def test_dark_is_dark_light_is_light(self):
        d = theme.build_scheme(280, "dark")
        l = theme.build_scheme(280, "light")
        self.assertLess(theme.luminance(theme.from_hex(d["surface"])), 0.05)
        self.assertGreater(theme.luminance(theme.from_hex(l["surface"])), 0.8)

    def test_mono_is_grey(self):
        s = theme.build_scheme(120, "dark", "mono")
        for k in ("primary", "surface", "outline"):
            r, g, b = theme.from_hex(s[k])
            self.assertLessEqual(max(r, g, b) - min(r, g, b), 2, k)

    def test_bad_args(self):
        with self.assertRaises(ValueError):
            theme.build_scheme(10, "blue")
        with self.assertRaises(ValueError):
            theme.build_scheme(10, "dark", "nope")

    def test_terminal_scheme_complete(self):
        t = theme.terminal_scheme(theme.build_scheme(280, "dark"), "dark")
        for name in ("black", "red", "green", "yellow", "blue", "purple", "cyan", "white"):
            self.assertRegex(t[name], HEX)
            self.assertRegex(t["bright" + name.capitalize()], HEX)


class TemplateTests(unittest.TestCase):
    def test_template_renders_fully(self):
        text = (ROOT / "templates" / "yasb.styles.css.tmpl").read_text(encoding="utf-8")
        out = theme.render_template(text, theme.build_scheme(280))
        self.assertNotIn("{{", out)
        self.assertNotIn("}}", out)
        code = re.sub(r"/\*.*?\*/", "", out, flags=re.S)  # the header comment mentions them on purpose
        self.assertNotIn("var(", code, "Qt stylesheets do not support CSS variables")
        self.assertNotIn("box-shadow", code, "Qt stylesheets do not support box-shadow")

    def test_unknown_token_fails(self):
        with self.assertRaises(KeyError):
            theme.render_template("{{nope}}", theme.build_scheme(10))

    def test_rgb_token(self):
        s = theme.build_scheme(10)
        r, g, b = theme.from_hex(s["surface"])
        self.assertEqual(theme.render_template("{{surface_rgb}}", s), f"{r}, {g}, {b}")


class ImageTests(unittest.TestCase):
    def setUp(self):
        try:
            from PIL import Image  # noqa: F401
        except ImportError:
            self.skipTest("Pillow not installed")

    def _solid(self, rgb, tmp):
        from PIL import Image
        p = Path(tmp) / "x.png"
        Image.new("RGB", (64, 64), rgb).save(p)
        return p

    def test_purple_hue(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = theme.extract_hue(self._solid((140, 90, 220), tmp))
            self.assertIsNotNone(found)
            expected = theme.hue_of((140, 90, 220))
            diff = abs((found[0] - expected + 180) % 360 - 180)
            self.assertLess(diff, 15)

    def test_grey_is_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(theme.extract_hue(self._solid((120, 120, 120), tmp)))

    def test_bundled_wallpaper_is_purple_ish(self):
        found = theme.extract_hue(ROOT / "wallpapers" / "caelestia-default.jpg")
        self.assertIsNotNone(found)
        self.assertTrue(250 <= found[0] <= 360 or found[0] <= 10, found)


class KomorebiTests(unittest.TestCase):
    def test_shipped_json_valid(self):
        data = json.loads((ROOT / "config/komorebi/komorebi.json").read_text(encoding="utf-8"))
        self.assertIn("border_colours", data)
        self.assertEqual(len(data["monitors"][0]["workspaces"]), 9)

    def test_patch_preserves_other_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "komorebi.json"
            p.write_text(json.dumps({"keep": 1, "border_colours": {"single": {"r": 0, "g": 0, "b": 0}}}))
            self.assertTrue(theme.patch_komorebi(p, theme.build_scheme(200)))
            data = json.loads(p.read_text())
            self.assertEqual(data["keep"], 1)
            self.assertEqual(set(data["border_colours"]), {"single", "stack", "monocle", "floating", "unfocused"})

    def test_patch_missing_file(self):
        self.assertFalse(theme.patch_komorebi(Path("/nonexistent/komorebi.json"), theme.build_scheme(1)))


class EndToEndTests(unittest.TestCase):
    def test_cli_writes_everything(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            home, yasb = tmp / "home", tmp / "yasb"
            kj = tmp / "komorebi.json"
            kj.write_text((ROOT / "config/komorebi/komorebi.json").read_text(encoding="utf-8"), encoding="utf-8")
            rc = theme.main(["--seed", "#3366cc", "--mode", "light", "--variant", "vibrant",
                             "--home", str(home), "--templates", str(ROOT / "templates"),
                             "--yasb-dir", str(yasb), "--komorebi-json", str(kj)])
            self.assertEqual(rc, 0)
            self.assertTrue((home / "colors.json").is_file())
            self.assertTrue((home / "colors" / "terminal-scheme.json").is_file())
            css = (yasb / "styles.css").read_text(encoding="utf-8")
            self.assertIn("caelestia-win", css)
            self.assertNotIn("{{", css)
            self.assertEqual(json.loads((home / "colors.json").read_text())["mode"], "light")

    def test_missing_image(self):
        self.assertEqual(theme.main(["--image", "/nope.png", "--print"]), 2)

    def test_print_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "h"
            theme.main(["--print", "--home", str(home)])
            self.assertFalse(home.exists())


class ConfigTests(unittest.TestCase):
    def test_yasb_config(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML not installed")
        cfg = yaml.safe_load((ROOT / "config/yasb/config.yaml").read_text(encoding="utf-8"))
        defined = set(cfg["widgets"])
        for side, names in cfg["bars"]["caelestia-bar"]["widgets"].items():
            for n in names:
                self.assertIn(n, defined, f"{n} ({side}) not defined")
        for name, w in cfg["widgets"].items():
            self.assertIn("type", w, name)

    def test_battery_line_is_removable(self):
        lines = (ROOT / "config/yasb/config.yaml").read_text(encoding="utf-8").splitlines()
        self.assertEqual(sum(1 for l in lines if re.match(r'^\s*-\s*"battery"\s*$', l)), 1)

    def test_whkdrc(self):
        lines = (ROOT / "config/whkd/whkdrc").read_text(encoding="utf-8").splitlines()
        seen = set()
        for l in lines:
            s = l.strip()
            if not s or s.startswith("#") or s.startswith(".shell"):
                continue
            self.assertIn(" : ", s, s)
            keys = s.split(" : ", 1)[0].strip()
            self.assertNotIn(keys, seen, f"duplicate binding: {keys}")
            seen.add(keys)
            self.assertTrue(keys.startswith("alt") or keys.startswith("ctrl + alt"), keys)

    def test_template_css_classes_match_yasb_classes(self):
        css = (ROOT / "templates/yasb.styles.css.tmpl").read_text(encoding="utf-8")
        self.assertIn(".yasb-bar", css)  # must match class_name in config.yaml


class PresetTests(unittest.TestCase):
    def test_presets_valid_and_distinct(self):
        hues = []
        for name, seed in theme.PRESETS.items():
            self.assertRegex(seed, HEX, name)
            hues.append(theme.hue_of(theme.from_hex(seed)))
        hues.sort()
        gaps = [(hues[(i + 1) % len(hues)] - hues[i]) % 360 for i in range(len(hues))]
        self.assertGreater(min(gaps), 15, "two presets are nearly the same colour")

    def test_preset_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            rc = theme.main(["--preset", "ocean", "--home", str(Path(tmp) / "h"), "--no-yasb", "--no-komorebi"])
            self.assertEqual(rc, 0)
            data = json.loads((Path(tmp) / "h" / "colors.json").read_text())
            self.assertEqual(data["source"], "preset ocean")

    def test_cw_knows_every_preset(self):
        text = (ROOT / "scripts" / "cw.ps1").read_text(encoding="utf-8")
        for name in theme.PRESETS:
            self.assertIn(f"'{name}'", text, name)

    def test_readme_lists_every_preset(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for name in theme.PRESETS:
            self.assertIn(name, readme, name)


class SchemeTests(unittest.TestCase):
    def test_every_scheme_has_every_role(self):
        ref = set(theme.build_scheme(200, "dark", "tonal"))
        for name, variants in theme.SCHEMES.items():
            for mode in ("dark", "light"):
                sc, used = theme.build_named_scheme(name, mode)
                self.assertEqual(set(sc), ref, f"{name} {mode}")
                self.assertIn(used, variants)
                for role, value in sc.items():
                    self.assertRegex(value, HEX, f"{name} {role}")

    def test_scheme_text_is_readable(self):
        for name in theme.SCHEMES:
            for mode in ("dark", "light"):
                sc, _ = theme.build_named_scheme(name, mode)
                for role in sc:
                    if role.startswith("on_") and role[3:] in sc:
                        ratio = theme.contrast(theme.from_hex(sc[role]), theme.from_hex(sc[role[3:]]))
                        self.assertGreaterEqual(ratio, 4.5, f"{name} {mode} {role}: {ratio:.1f}")

    def test_dark_schemes_are_dark(self):
        for name in theme.SCHEMES:
            sc, _ = theme.build_named_scheme(name, "dark")
            self.assertLess(theme.luminance(theme.from_hex(sc["surface"])), 0.1, name)

    def test_scheme_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            rc = theme.main(["--scheme", "catppuccin", "--mode", "light", "--home", str(Path(tmp) / "h"),
                             "--no-yasb", "--no-komorebi"])
            self.assertEqual(rc, 0)
            data = json.loads((Path(tmp) / "h" / "colors.json").read_text())
            self.assertEqual(data["source"], "scheme catppuccin")
            self.assertEqual(data["mode"], "light")
            self.assertEqual(data["colors"]["surface"], "#eff1f5")

    def test_scheme_without_light_variant_falls_back(self):
        sc, used = theme.build_named_scheme("dracula", "light")
        self.assertEqual(used, "dark")

    def test_scheme_names_do_not_clash_with_presets(self):
        self.assertFalse(set(theme.SCHEMES) & set(theme.PRESETS))

    def test_cw_and_readme_know_every_scheme(self):
        text = (ROOT / "scripts" / "cw.ps1").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for name in theme.SCHEMES:
            self.assertIn(f"'{name}'", text, name)
            self.assertIn(name, readme, name)


class RepoTests(unittest.TestCase):
    def test_powershell_files_are_ascii(self):
        for p in ROOT.rglob("*.ps1"):
            data = p.read_bytes()
            try:
                data.decode("ascii")
            except UnicodeDecodeError as e:
                self.fail(f"{p.relative_to(ROOT)} has non-ASCII bytes (breaks Windows PowerShell 5.1): {e}")

    def test_no_bom_in_configs(self):
        for rel in ("config/komorebi/komorebi.json", "config/whkd/whkdrc", "config/yasb/config.yaml"):
            self.assertFalse((ROOT / rel).read_bytes().startswith(b"\xef\xbb\xbf"), rel)

    def test_svgs_are_valid_xml(self):
        import xml.dom.minidom
        files = list((ROOT / "docs" / "assets").glob("*.svg"))
        self.assertGreaterEqual(len(files), 7)
        for f in files:
            xml.dom.minidom.parse(str(f))

    def test_previews_are_current(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("make_previews", ROOT / "tools" / "make_previews.py")
        mp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mp)
        self.assertEqual((ROOT / "docs/assets/banner.svg").read_text(encoding="utf-8"), mp.banner() + "\n",
                         "run: python tools/make_previews.py")
        self.assertEqual((ROOT / "docs/assets/presets.svg").read_text(encoding="utf-8"), mp.presets_sheet() + "\n",
                         "run: python tools/make_previews.py")
        self.assertEqual((ROOT / "docs/assets/schemes.svg").read_text(encoding="utf-8"), mp.schemes_sheet() + "\n",
                         "run: python tools/make_previews.py")

    def test_readme_local_links_exist(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        targets = re.findall(r'(?:src|href)="([^"#:]+)"', readme) + re.findall(r"\]\(([^)#:\s]+)(?:#[^)]*)?\)", readme)
        self.assertTrue(targets)
        for tgt in targets:
            if tgt.startswith(("http", "mailto")):
                continue
            self.assertTrue((ROOT / tgt).exists(), f"README links to missing file: {tgt}")

    def test_required_repo_files(self):
        for rel in ("LICENSE", ".gitignore", "CHANGELOG.md", "CONTRIBUTING.md", ".github/workflows/ci.yml",
                    "docs/TROUBLESHOOTING.md", "docs/CUSTOMIZING.md", "Install.ps1", "Uninstall.ps1"):
            self.assertTrue((ROOT / rel).is_file(), rel)

    def test_installer_references_existing_package_files(self):
        text = (ROOT / "Install.ps1").read_text(encoding="utf-8")
        for rel in re.findall(r"'((?:scripts|templates|config|wallpapers)\\[^']+)'", text):
            self.assertTrue((ROOT / rel.replace("\\", "/")).exists(), rel)


class WindowLevelTests(unittest.TestCase):
    def test_tacky_template_renders_valid_yaml(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML not installed")
        text = (ROOT / "templates" / "tacky-borders.config.yaml.tmpl").read_text(encoding="utf-8")
        s = theme.build_scheme(280)
        out = theme.render_template(text, s)
        self.assertNotIn("{{", out)
        cfg = yaml.safe_load(out)
        g = cfg["global"]
        self.assertEqual(g["active_color"]["colors"], [s["primary"], s["tertiary"]])
        self.assertEqual(cfg["rendering_backend"], "V2")  # Glow needs the V2 backend
        for key in ("border_width", "border_offset", "border_radius", "inactive_color", "animations", "effects"):
            self.assertIn(key, g)

    def test_cli_tacky_turns_off_komorebi_border(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            kj = tmp / "komorebi.json"
            kj.write_text(json.dumps({"border": True}))
            rc = theme.main(["--preset", "rose", "--home", str(tmp / "h"), "--templates", str(ROOT / "templates"),
                             "--yasb-dir", str(tmp / "y"), "--komorebi-json", str(kj), "--tacky-dir", str(tmp / "t")])
            self.assertEqual(rc, 0)
            self.assertTrue((tmp / "t" / "config.yaml").is_file())
            self.assertFalse(json.loads(kj.read_text())["border"])

    def test_without_tacky_dir_komorebi_border_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            kj = tmp / "komorebi.json"
            kj.write_text(json.dumps({"border": True}))
            theme.main(["--preset", "rose", "--home", str(tmp / "h"), "--templates", str(ROOT / "templates"),
                        "--yasb-dir", str(tmp / "y"), "--komorebi-json", str(kj)])
            self.assertTrue(json.loads(kj.read_text())["border"])

    def test_bar_has_taskbar_widget_and_styles(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML not installed")
        cfg = yaml.safe_load((ROOT / "config/yasb/config.yaml").read_text(encoding="utf-8"))
        bar = cfg["bars"]["caelestia-bar"]["widgets"]
        self.assertIn("taskbar", bar["left"])
        self.assertEqual(cfg["widgets"]["taskbar"]["type"], "yasb.taskbar.TaskbarWidget")
        self.assertIn(".taskbar-widget", (ROOT / "templates/yasb.styles.css.tmpl").read_text(encoding="utf-8"))

    def test_gaps_are_visible(self):
        data = json.loads((ROOT / "config/komorebi/komorebi.json").read_text(encoding="utf-8"))
        self.assertGreaterEqual(data["default_workspace_padding"], 12)
        self.assertGreaterEqual(data["default_container_padding"], 8)

    def test_installer_flags_documented(self):
        installer = (ROOT / "Install.ps1").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for flag in re.findall(r"^\s*\[switch\]\$(\w+)", installer, flags=re.M):
            self.assertIn("-" + flag, readme, f"-{flag} is not documented in the README")
        self.assertNotIn("-HideTaskbar", readme)


if __name__ == "__main__":
    unittest.main()
