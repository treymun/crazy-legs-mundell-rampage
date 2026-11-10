"""Paint the muzzle flashes, smoke, blasts and impact puffs.

    python scripts/build_fx_art.py

Writes into assets/art (four frames each unless noted):
  fx_fire_N     a spiked muzzle flash dying to an ember; also the fireball of a blast
  fx_smoke_N    rolling smoke
  fx_energy_N   the alien arm gun's discharge
  fx_rocket_N, fx_forge_N, fx_steam_N   the same shapes in each weapon's colours
  fx_blast_N, fx_blast_energy_N   the swelling fireball of an explosion
  fx_puff_N     dust kicked off a wall or the ground by a bullet
  fx_sparks_N   (three frames) a bullet striking metal
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
SIZE = 80
RNG = np.random.default_rng(1997)


def cloud(size: int, seed: int, octaves=(4, 8, 16, 32)) -> np.ndarray:
    """Soft fractal noise in 0..1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), dtype=np.float32)
    weight = 0.0
    for k, cells in enumerate(octaves):
        grid = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
        layer = np.asarray(grid.resize((size, size), Image.Resampling.BICUBIC), dtype=np.float32) / 255
        gain = .5 ** k
        total += layer * gain
        weight += gain
    return total / weight


def polar(size: int):
    y, x = np.indices((size, size), dtype=np.float32)
    c = (size - 1) / 2
    return np.hypot(x - c, y - c) / (size / 2), np.arctan2(y - c, x - c)


def ramp(heat: np.ndarray, stops) -> np.ndarray:
    """Map 0..1 heat through colour stops [(at, (r, g, b)), ...]."""
    out = np.zeros(heat.shape + (3,), dtype=np.float32)
    for (a0, c0), (a1, c1) in zip(stops, stops[1:]):
        t = np.clip((heat - a0) / max(1e-6, a1 - a0), 0, 1)[..., None]
        seg = np.asarray(c0, dtype=np.float32) * (1 - t) + np.asarray(c1, dtype=np.float32) * t
        mask = (heat >= a0)[..., None]
        out = np.where(mask, seg, out)
    return out


FIRE = [(0, (70, 20, 8)), (.25, (176, 58, 16)), (.5, (238, 132, 34)), (.75, (255, 214, 96)), (1, (255, 252, 226))]
PLASMA = [(0, (10, 50, 18)), (.3, (40, 150, 60)), (.6, (120, 240, 120)), (.85, (210, 255, 190)), (1, (250, 255, 240))]


def flash(frame: int, stops=FIRE, seed: int = 3) -> Image.Image:
    r, a = polar(SIZE)
    rng = np.random.default_rng(seed + frame * 7)
    reach = (1.0, .78, .5, .3)[frame]
    spikes = (9, 7, 4, 0)[frame]
    heat = np.exp(-(r / (.30 * reach)) ** 2) * 1.25
    for _ in range(spikes):
        at = rng.uniform(-math.pi, math.pi)
        width = rng.uniform(.05, .13)
        length = rng.uniform(.45, 1.0) * reach
        delta = np.angle(np.exp(1j * (a - at)))
        heat += np.exp(-(delta / width) ** 2) * np.exp(-r / (length * .42)) * rng.uniform(.7, 1.1)
    heat *= .8 + .4 * cloud(SIZE, seed * 5 + frame, (6, 12, 24))
    heat = np.clip(heat * (1.0, .92, .7, .42)[frame], 0, 1)
    rgb = ramp(heat, stops)
    alpha = np.clip((heat - .06) * 4.2, 0, 1) * (255, 250, 225, 170)[frame]
    if frame >= 2:
        # the flash is going out: smoke starts to show round the ember
        grey = cloud(SIZE, seed * 11 + frame)
        puff = np.clip(1 - r / (.62 + .1 * frame), 0, 1) * (.5 + grey * .7)
        smoke_rgb = np.stack([70 + grey * 50, 64 + grey * 46, 56 + grey * 40], axis=-1)
        keep = np.clip(heat * 2.2, 0, 1)[..., None]
        rgb = rgb * keep + smoke_rgb * (1 - keep)
        alpha = np.maximum(alpha, np.clip(puff * 1.5, 0, 1) * (150 - 30 * (frame - 2)))
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out)


def smoke(frame: int, tint=(1.0, 1.0, 1.0), seed: int = 21) -> Image.Image:
    r, _ = polar(SIZE)
    grain = cloud(SIZE, seed + frame * 3)
    lumps = cloud(SIZE, seed * 3 + frame, (3, 6, 12))
    radius = .50 + .13 * frame
    body = np.clip((radius - r * (.75 + lumps * .5)) * 3.2, 0, 1)
    shade = 58 + grain * 76 + (1 - r) * 22
    rgb = np.stack([shade * 1.04, shade * .98, shade * .9], axis=-1) * np.asarray(tint, dtype=np.float32)
    alpha = body * (.55 + grain * .45) * (178 - 34 * frame)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 255)]).astype(np.uint8))


def puff(frame: int) -> Image.Image:
    size = 40
    r, _ = polar(size)
    grain = cloud(size, 60 + frame, (4, 8, 16))
    radius = .34 + .2 * frame
    body = np.clip((radius - r * (.8 + grain * .5)) * 4.0, 0, 1)
    shade = 122 + grain * 70
    rgb = np.stack([shade, shade * .93, shade * .8], axis=-1)
    alpha = body * (190 - 44 * frame)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 255)]).astype(np.uint8))


def sparks(frame: int) -> Image.Image:
    size = 40
    r, a = polar(size)
    rng = np.random.default_rng(90)
    heat = np.exp(-(r / .16) ** 2) * (1.2, .7, .25)[frame]
    for _ in range(11):
        at = rng.uniform(-math.pi, math.pi)
        length = rng.uniform(.5, 1.0)
        delta = np.angle(np.exp(1j * (a - at)))
        head = (.25, .55, .85)[frame] * length
        streak = np.exp(-(delta / .05) ** 2) * np.exp(-((r - head) / .16) ** 2)
        heat += streak * (1.1, .9, .6)[frame]
    heat = np.clip(heat, 0, 1)
    rgb = ramp(heat, FIRE)
    alpha = np.clip((heat - .12) * 5, 0, 1) * 255
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8))


def fireball(frame: int, stops=FIRE, seed: int = 41) -> Image.Image:
    """A blast: a rolling ball of fire that swells, then chars at the edges."""
    r, _ = polar(SIZE)
    churn = cloud(SIZE, seed + frame * 5, (4, 8, 16, 32))
    radius = (.52, .72, .88, .98)[frame]
    heat = np.clip((radius - r * (.72 + churn * .6)) * 3.0, 0, 1)
    heat = heat * (1.0, .9, .72, .5)[frame] * (.7 + churn * .5)
    rgb = ramp(np.clip(heat, 0, 1), stops)
    if frame >= 2:
        soot = np.clip((r - radius * .45) * 2.4, 0, 1)[..., None] * (.45 + .2 * (frame - 2))
        rgb = rgb * (1 - soot) + np.asarray((52, 44, 38), dtype=np.float32) * soot
    alpha = np.clip((radius - r * (.72 + churn * .6)) * 5.0, 0, 1) * (255, 250, 236, 214)[frame]
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8))


def tinted(image: Image.Image, tint, lift: float = 0.0) -> Image.Image:
    px = np.asarray(image, dtype=np.float32).copy()
    px[..., :3] = np.clip(px[..., :3] * np.asarray(tint, dtype=np.float32) + lift, 0, 255)
    return Image.fromarray(px.astype(np.uint8))


def main() -> None:
    count = 0
    for frame in range(4):
        fire = flash(frame)
        fire.save(ART / f"fx_fire_{frame}.png")
        grey = smoke(frame)
        grey.save(ART / f"fx_smoke_{frame}.png")
        flash(frame, PLASMA, seed=8).save(ART / f"fx_energy_{frame}.png")
        tinted(fire, (1.0, .78, .6)).save(ART / f"fx_rocket_{frame}.png")
        tinted(flash(frame, FIRE, seed=14), (1.0, .96, .78)).save(ART / f"fx_forge_{frame}.png")
        tinted(smoke(frame, seed=33), (.86, .96, 1.1), 22).save(ART / f"fx_steam_{frame}.png")
        puff(frame).save(ART / f"fx_puff_{frame}.png")
        fireball(frame).save(ART / f"fx_blast_{frame}.png")
        fireball(frame, PLASMA, seed=47).save(ART / f"fx_blast_energy_{frame}.png")
        count += 9
    for frame in range(3):
        sparks(frame).save(ART / f"fx_sparks_{frame}.png")
        count += 1
    Image.open(ART / "fx_energy_1.png").resize((24, 24), Image.Resampling.LANCZOS).save(ART / "fx_arm_bolt.png")
    print(f"fx art: {count} frames")


if __name__ == "__main__":
    main()
