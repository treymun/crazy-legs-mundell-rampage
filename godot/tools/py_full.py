"""Render full gameplay frames (view + weapon + HUD + grade) from the reference.

  <venv python> tools/py_full.py

Writes tools/frames/py_full_<tag>.png and tools/frames/full_shots.json with the
state each frame was captured in, so the Godot probe can reproduce it exactly.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

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

from main import Desktop  # noqa: E402

# tag: level, x, y, angle, clock, health, selected weapon, shots fired
SHOTS = {
    "stankys_road": ("hickston", 12.0, 28.0, -0.15, 1.0, 100, 1, 0),
    "stankys_bar": ("hickston", 11.2, 19.0, -1.2, 2.5, 100, 1, 0),
    "stankys_shotgun": ("hickston", 16.0, 24.0, -0.6, 3.0, 100, 2, 1),
    "stankys_enemy": ("hickston", 53.0, 22.0, 0.0, 4.0, 72, 2, 1),
    "stankys_hub": ("hickston", 24.5, 47.0, -1.6, 5.0, 100, 1, 0),
    "fair_gate_full": ("fair", 21.5, 34.0, -1.57, 6.0, 100, 1, 0),
    "mill_yard_full": ("sawmill", 21.45, 32.0, -1.57, 7.0, 100, 1, 0),
    "quarry_yard_full": ("quarry", 27.45, 35.0, -1.57, 8.0, 100, 1, 0),
}


def main():
    pg.init()
    d = Desktop(smoke=True)
    meta = {}
    for tag, (level_id, x, y, angle, clock, health, weapon, shots) in SHOTS.items():
        d.start(level_id)
        g = d.game
        p = g.player
        p.x, p.y, p.angle = x, y, angle
        p.eye = .95 + g.world.elevation(x, y)
        p.pitch = 0.0
        p.drunk = 0.0
        p.health = health
        g.clock = clock
        g.hurt_flash = 0.0
        g.blast_flash = 0.0
        g.message_until = 0.0
        g.district_until = 0.0
        g.map = False
        g.armory.select(weapon, g)
        g.armory.flash = 0.0
        g.armory.recoil = 0.0
        g.armory.reload = 0.0
        g.armory.cooldown = 0.0
        g.armory.shot_age = 0.0
        for _ in range(shots):
            g.armory.fire(g, False)
            g.armory.flash = 0.0
        d.canvas.fill((0, 0, 0))
        g.draw(d.canvas, crosshair=1, grade=d.palette.grade)
        raw = pg.image.tobytes(d.canvas, "RGB")
        Image.frombytes("RGB", (320, 200), raw).save(OUT / f"pyraw_{tag}.png")
        d.palette.apply(d.canvas)
        raw = pg.image.tobytes(d.canvas, "RGB")
        Image.frombytes("RGB", (320, 200), raw).save(OUT / f"py_full_{tag}.png")
        meta[tag] = {"level": level_id, "x": x, "y": y, "angle": angle,
                     "clock": clock, "health": health, "weapon": weapon}
        print("rendered", tag)
    (OUT / "full_shots.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
