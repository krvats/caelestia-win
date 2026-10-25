"""Replace the YOUR-USERNAME placeholder with your GitHub username in README, docs and templates.

    python tools/set_repo.py octocat
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(argv):
    if len(argv) != 2 or not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})", argv[1]):
        print("usage: python tools/set_repo.py <github-username>")
        return 2
    changed = 0
    for path in ROOT.rglob("*"):
        if path.suffix not in {".md", ".yml", ".yaml", ".ps1", ".py"} or ".git" in path.parts:
            continue
        if path.name == "set_repo.py":
            continue
        text = path.read_text(encoding="utf-8")
        if "YOUR-USERNAME" in text:
            path.write_text(text.replace("YOUR-USERNAME", argv[1]), encoding="utf-8", newline="\n")
            print("updated", path.relative_to(ROOT))
            changed += 1
    print(f"{changed} file(s) updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
