"""Render reference frames from the Python engine for pixel comparison.

  <venv python> tools/py_frame.py
Writes tools/frames/py_<tag>.png plus shots.json describing each camera.
"""
from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path
from types import SimpleNamespace

os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"

def _find_ref() -> Path:
    """Reference project: env override, then the repository this folder sits in."""
    import os
    env = os.environ.get("CRAZY_LEGS_REF")
    if env:
        return Path(env)
    here = Path(__file__).resolve().parent
    # godot/tools/ lives inside the Python project it is ported from; the
    # reference/ candidates cover a standalone copy of the godot folder.
    for candidate in (here.parent.parent, here.parent / "reference",
                      here.parent.parent / "reference"):
        if (candidate / "main.py").is_file():
            return candidate
    raise SystemExit("Python reference project not found: set CRAZY_LEGS_REF to its folder.")


REF = _find_ref()
OUT = Path(__file__).resolve().parent / "frames"
sys.path.insert(0, str(REF))

import pygame as pg  # noqa: E402
from PIL import Image  # noqa: E402

import campaign  # noqa: E402
from engine import Art, Renderer  # noqa: E402

SHOTS = {
    # tag: (level, x, y, angle, eye_offset, pitch, horizon_shift)
    "spawn": ("hickston", 10.45, 29.25, -1.54, 0.0, 0.0, 0.0),
    "road_east": ("hickston", 12.0, 28.0, -0.15, 0.0, 0.0, 0.0),
    "road_west": ("hickston", 30.0, 28.2, 3.05, 0.0, 0.0, 0.0),
    "bar_inside": ("hickston", 11.2, 19.0, -1.2, 0.0, 0.0, 0.0),
    "bar_mirror": ("hickston", 5.2, 13.4, 2.85, 0.0, 0.0, 0.0),
    "barn": ("hickston", 22.0, 16.0, -1.9, 0.0, 0.0, 0.0),
    "pasture": ("hickston", 16.0, 5.0, 0.35, 0.0, 0.0, 0.0),
    "creek": ("hickston", 36.7, 6.6, 4.4, 0.0, 0.0, 0.0),
    "hub": ("hickston", 24.5, 47.0, -1.6, 0.0, 0.0, 0.0),
    "hub_north": ("hickston", 24.5, 43.0, -1.57, 0.0, 0.0, 0.0),
    "fair_gate": ("fair", 21.5, 34.0, -1.57, 0.0, 0.0, 0.0),
    "fair_mid": ("fair", 20.0, 28.0, -0.6, 0.0, 0.0, 0.0),
    "mill_yard": ("sawmill", 21.45, 32.0, -1.57, 0.0, 0.0, 0.0),
    "quarry_yard": ("quarry", 27.45, 35.0, -1.57, 0.0, 0.0, 0.0),
    # County Crossroads surface effects (crossroads.py): the water-tower
    # shadow on the service road and its low wall, the see-through screen on
    # the road shed, and the culvert runoff.
    "hub_tower": ("hickston", 26.2, 50.2, -2.511, 0.0, -25.0, 0.0),
    "hub_wall": ("hickston", 25.3, 48.4, 3.1416, 0.0, -15.0, 0.0),
    "hub_screen": ("hickston", 30.5, 45.9, 1.5708, 0.0, -10.0, 0.0),
    "hub_runoff": ("hickston", 31.0, 52.6, -2.06, 0.0, -30.0, 0.0),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pg.init()
    pg.display.set_mode((320, 200))
    art = Art()
    meta = {}
    worlds = {}
    for tag, (level_id, x, y, angle, eye_off, pitch, shift) in SHOTS.items():
        if level_id not in worlds:
            worlds[level_id] = campaign.BY_ID[level_id].build()
        world = worlds[level_id]
        renderer = Renderer(world, art)
        # Match game.tick's eye height and horizon composition.
        eye = .95 + world.elevation(x, y) + eye_off
        player = SimpleNamespace(x=x, y=y, view_angle=angle, pitch=pitch,
                                 bob=shift, sway=0., eye=eye)
        surface = renderer.draw(player, [], None, 0., (), ())
        surface = surface.convert()
        raw = pg.image.tobytes(surface, "RGB")
        Image.frombytes("RGB", (320, 156), raw).save(OUT / f"py_{tag}.png")
        meta[tag] = {"level": level_id, "x": x, "y": y, "angle": angle,
                     "eye": eye, "pitch": pitch, "horizon": shift}
        print("rendered", tag)
    (OUT / "shots.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
