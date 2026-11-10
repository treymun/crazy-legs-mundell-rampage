"""Read or stamp the version carried by the Godot project and its export presets.

    python scripts/godot_version.py                 # prints e.g. 2.0.0-dev.9
    python scripts/godot_version.py --set 2.1.0     # release builds stamp the tag

One version string lives in ``godot/project.godot``. The export presets need
it in three more shapes: the four-part Windows file version, the Android
version name, and the Android version code (an integer that must grow with
every release an installed copy should be able to update to).
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot" / "project.godot"
PRESETS = ROOT / "godot" / "export_presets.cfg"
SHAPE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z]+\.(\d+))?$")


def read() -> str:
    found = re.search(r'^config/version="([^"]*)"', PROJECT.read_text(encoding="utf-8"), re.M)
    if not found:
        raise SystemExit("godot/project.godot has no config/version line.")
    return found.group(1)


def parts(version: str) -> tuple[int, int, int, int | None]:
    found = SHAPE.match(version)
    if not found:
        raise SystemExit(f"Version must look like 2.1.0 or 2.1.0-dev.3, not {version!r}.")
    major, minor, patch = (int(found.group(i)) for i in (1, 2, 3))
    return major, minor, patch, int(found.group(4)) if found.group(4) else None


def stamp(version: str) -> None:
    major, minor, patch, build = parts(version)
    windows = f"{major}.{minor}.{patch}.{build or 0}"
    # A final release sorts above every pre-release of the same number.
    code = major * 1_000_000 + minor * 10_000 + patch * 100 + (99 if build is None else min(build, 98))
    replace(PROJECT, {r'^config/version="[^"]*"': f'config/version="{version}"'})
    replace(PRESETS, {
        r'^application/file_version="[^"]*"': f'application/file_version="{windows}"',
        r'^application/product_version="[^"]*"': f'application/product_version="{windows}"',
        r'^version/name="[^"]*"': f'version/name="{version}"',
        r"^version/code=\d+": f"version/code={code}",
    })
    print(f"Stamped {version} (Windows {windows}, Android code {code})")


def replace(path: Path, rules: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8")
    for pattern, line in rules.items():
        text, count = re.subn(pattern, line, text, flags=re.M)
        if count != 1:
            raise SystemExit(f"{path.name}: expected one line matching {pattern}, found {count}.")
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--set", metavar="VERSION", help="write this version into the project")
    args = parser.parse_args()
    if args.set:
        stamp(args.set.removeprefix("v"))
    else:
        print(read())


if __name__ == "__main__":
    main()
