"""Rebuild everything the Godot port generates from this Python project.

The port under ``godot/`` never hand-authors content: its maps come from the
level modules and its art, sound and palette from ``assets/``. The large packs
(``godot/assets_gen/*.bin``, about 170 MB) are not committed, so a fresh clone
or a CI job runs this once before opening or exporting the Godot project.

    python scripts/build_godot_data.py            # asset packs (numpy + Pillow)
    python scripts/build_godot_data.py --levels   # also godot/data/*.json

``--levels`` imports the level builders exactly as the game does; the JSON it
writes is committed, so it is only needed after a level module changes.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "godot" / "tools"
PACKS = ("tiles.bin", "art.bin", "sfx.bin", "music.bin", "palette.bin", "grain.bin",
         "sky.bin")


def run(script: str) -> None:
    env = dict(os.environ, CRAZY_LEGS_REF=str(ROOT), SDL_VIDEODRIVER="dummy",
               SDL_AUDIODRIVER="dummy")
    print(f"-- {script}", flush=True)
    subprocess.run([sys.executable, str(TOOLS / script)], check=True, env=env,
                   cwd=ROOT / "godot")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--levels", action="store_true",
                        help="re-export godot/data/*.json from the level modules")
    args = parser.parse_args()
    if args.levels:
        run("export_levels.py")
    run("pack_assets.py")
    run("pack_skies.py")
    out = ROOT / "godot" / "assets_gen"
    missing = [name for name in PACKS if not (out / name).is_file()]
    if missing:
        raise SystemExit(f"Packs were not written: {', '.join(missing)}")
    total = sum((out / name).stat().st_size for name in PACKS)
    print(f"Godot data ready: {len(PACKS)} packs, {total / 1e6:.0f} MB in {out}")


if __name__ == "__main__":
    main()
