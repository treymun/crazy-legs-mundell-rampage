"""Cut the first-person cels for the thirteen weapons that are not photographed plates.

    python scripts/build_weapon_views.py [--no-render] [--only rifle,tnt] [--preview]

Blender (scripts/blender/weapon_views.py) renders each weapon alone at the angle
of one of the three plates. This lays the photographed hand from that plate over
the weapon's grip, so every weapon is held by the same hands as the shotgun, the
revolver and the crowbar, then poses the result into the cels the game asks for
and grades them like the plates (weapon_art.digitized_pose).

--preview writes the cels to _preview/weapon_cels instead of assets/art.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
RAW = ROOT / "_preview" / "weapon_raw"
ART = ROOT / "assets" / "art"
SOURCE = ROOT / "source_art"
BLENDER = os.environ.get("BLENDER_PATH") or str(
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Blender" / "blender.exe")
CEL = (320, 120)
BICUBIC = Image.Resampling.BICUBIC

# Outlines of the hands on the 640-wide plates, and the point of each that sits on the weapon.
HANDS = {
    "grip": ("revolver", ((228, 308), (246, 268), (272, 246), (302, 240), (340, 246), (368, 206), (396, 188),
                          (430, 195), (456, 216), (482, 250), (520, 290), (560, 316), (600, 336), (640, 346),
                          (640, 448), (300, 448), (286, 420), (280, 386), (256, 350), (236, 336)), (318, 300)),
    "fist": ("crowbar", ((322, 268), (340, 236), (366, 216), (400, 210), (430, 226), (456, 250), (480, 280),
                         (500, 320), (540, 360), (590, 376), (640, 400), (640, 432), (432, 432), (400, 400),
                         (370, 370), (346, 340), (324, 302)), (396, 300)),
    "cup": ("shotgun", ((42, 160), (55, 136), (75, 126), (95, 136), (110, 160), (125, 186), (140, 216),
                        (160, 250), (184, 290), (200, 330), (190, 370), (176, 400), (166, 448), (0, 448),
                        (0, 380), (20, 330), (38, 270), (40, 210)), (120, 230)),
}
# rig -> (hand, hand scale on the canvas, hand in front of the weapon?)
RIG_HAND = {"pistol": ("grip", 1.0, True), "bar": ("fist", 1.2, True), "long": ("cup", .38, True),
            "carry": ("cup", .62, False)}
# weapon -> (canvas-to-cel scale, where its front point lands in the cel, nudge of the hand on the canvas)
LAYOUT = {
    "rifle": (.24, (166, 56), (0, 0)), "crossbow": (.46, (166, 78), (0, 0), .56),
    "cow_launcher": (.24, (170, 58), (0, 0)), "bottle_launcher": (.24, (168, 56), (0, 0)),
    "armgun": (.24, (172, 60), (0, 0)), "riveter": (.26, (174, 64), (0, 0)),
    "pressure_gun": (.24, (172, 60), (0, 0)), "teat_gun": (.26, (176, 66), (0, 0)),
    "ripsaw": (.24, (168, 60), (0, 0)), "slingblade": (.34, (146, 30), (0, 0)),
    "tnt": (.36, (190, 52), (0, 0)), "bowling_ball": (.30, (160, 58), (0, 0)),
    "powder_keg": (.30, (160, 36), (0, 0)),
}
GUN_POSES = ("idle", "kick", "recover", "open", "eject", "load", "close")
POSES = {"slingblade": ("idle", "wind", "strike", "follow", "recover"),
         "tnt": ("idle", "kick", "throw", "lit", "lit_alt", "dry"),
         "ripsaw": GUN_POSES[:1] + ("kick", "open", "eject", "load", "close", "grind", "grind_hot"),
         "crossbow": ("idle", "kick", "open", "eject", "load", "close")}


def hand(kind: str, scale: float, mirror: bool = False) -> tuple[Image.Image, tuple[float, float]]:
    plate, outline, anchor = HANDS[kind]
    source = Image.open(SOURCE / f"{plate}_plate.png").convert("RGBA")
    mask = Image.new("L", source.size)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    alpha = np.minimum(np.asarray(source.getchannel("A")), np.asarray(mask))
    source.putalpha(Image.fromarray(alpha))
    box = source.getchannel("A").getbbox()
    source = source.crop(box)
    ax, ay = anchor[0] - box[0], anchor[1] - box[1]
    if mirror:
        source = ImageOps.mirror(source)
        ax = source.width - ax
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    return source.resize(size, Image.Resampling.LANCZOS), (ax * scale, ay * scale)


def weathered(image: Image.Image, seed: int) -> Image.Image:
    """Pull a clean render toward the plates: flatter colour, harder edges, a little grain."""
    rgb = ImageEnhance.Color(image.convert("RGB")).enhance(.82)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
    rgb = rgb.filter(ImageFilter.UnsharpMask(1.2, 90, 2))
    arr = np.asarray(rgb, dtype=np.float32)
    arr += np.random.default_rng(seed).normal(0, 4.0, arr.shape[:2])[..., None]
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(image.getchannel("A"))
    return out


def composite(name: str, view: dict, with_weapon: bool = True, with_hand: bool = True) -> Image.Image:
    """The weapon and its hand on a canvas twice the plate's size (room to rotate)."""
    canvas = Image.new("RGBA", (1280, 896))
    off = (320, 224)
    kind, scale, front = RIG_HAND[view["rig"]]
    if len(LAYOUT[name]) > 3:
        scale = LAYOUT[name][3]
    weapon = weathered(Image.open(RAW / f"{name}.png").convert("RGBA"), sum(map(ord, name)))
    nudge = LAYOUT[name][2]
    layers = []
    if with_hand:
        if view["rig"] == "carry":
            cx, cy = view["support"]
            for mirror, dx in ((False, -92), (True, 92)):
                cut, anchor = hand(kind, scale, mirror)
                layers.append((cut, (round(off[0] + cx + dx - anchor[0]), round(off[1] + cy - 30 - anchor[1]))))
        else:
            cut, anchor = hand(kind, scale)
            at = view["support"] if view["rig"] == "long" else view["grip"]
            layers.append((cut, (round(off[0] + at[0] + nudge[0] - anchor[0]),
                                 round(off[1] + at[1] + nudge[1] - anchor[1]))))
    if not front:
        for cut, at in layers:
            canvas.alpha_composite(cut, at)
    if with_weapon:
        canvas.alpha_composite(weapon, off)
    if front:
        for cut, at in layers:
            canvas.alpha_composite(cut, at)
    return canvas


def to_cel(name: str, view: dict, canvas: Image.Image, turn: float = 0., shift=(0, 0)) -> Image.Image:
    """Rotate the canvas about the wrist, scale it and seat it in the 320x120 cel."""
    scale, target = LAYOUT[name][:2]
    pivot = (320 + view["grip"][0] + 60, 224 + view["grip"][1] + 90)
    if view["rig"] == "long":
        pivot = (320 + 560, 224 + 430)
    if view["rig"] == "carry":
        pivot = (320 + 320, 224 + 448)
    if turn:
        canvas = canvas.rotate(turn, BICUBIC, center=pivot)
    small = canvas.resize((round(canvas.width * scale), round(canvas.height * scale)), Image.Resampling.LANCZOS)
    fx, fy = (320 + view["front"][0]) * scale, (224 + view["front"][1]) * scale
    cel = Image.new("RGBA", CEL)
    cel.alpha_composite(small, (0, 0)) if False else None
    out = Image.new("RGBA", (CEL[0], 174))
    x, y = round(target[0] - fx + shift[0]), round(target[1] - fy + shift[1])
    layer = Image.new("RGBA", out.size)
    layer.paste(small, (x, y), small)
    return layer


def spark(cel: Image.Image, at: tuple[float, float], size: int, hot: bool) -> None:
    d = ImageDraw.Draw(cel)
    x, y = at
    core = "#fff2b0" if hot else "#ffd070"
    for dx, dy in ((size, 0), (-size, 0), (0, size), (0, -size), (size * .6, size * .6), (-size * .6, -size * .6)):
        d.line((x, y, x + dx, y + dy), fill="#ff9a30", width=1)
    d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=core)


def cels(name: str, view: dict) -> dict[str, Image.Image]:
    whole = composite(name, view)
    out: dict[str, Image.Image] = {}
    rig = view["rig"]
    poses = POSES.get(name, GUN_POSES)
    scale, target = LAYOUT[name][:2]
    for pose in poses:
        if name == "slingblade":
            turn, shift = {"idle": (0, (0, 0)), "wind": (-20, (26, -10)), "strike": (30, (-52, 4)),
                           "follow": (46, (-50, 20)), "recover": (18, (-18, 10))}[pose]
            out[pose] = to_cel(name, view, whole, turn, shift)
        elif name == "tnt":
            if pose == "dry":
                out[pose] = to_cel(name, view, composite(name, view, with_weapon=False), 0, (0, 6))
                continue
            turn, shift = {"idle": (0, (0, 0)), "kick": (14, (-14, -10)), "throw": (26, (-30, -26)),
                           "lit": (0, (0, 0)), "lit_alt": (0, (0, 0))}[pose]
            cel = to_cel(name, view, whole, turn, shift)
            if pose.startswith("lit"):
                spark(cel, (target[0], target[1] + 1), 5 if pose == "lit" else 3, pose == "lit")
            out[pose] = cel
        elif rig == "carry":
            empty = composite(name, view, with_weapon=False)
            turn, shift, held = {"idle": (0, (0, 0), True), "kick": (0, (0, -14), False),
                                 "recover": (0, (0, 6), False), "open": (0, (0, 22), False),
                                 "eject": (0, (0, 30), False), "load": (0, (0, 26), True),
                                 "close": (0, (0, 10), True)}[pose]
            out[pose] = to_cel(name, view, whole if held else empty, turn, shift)
        else:
            turn, shift = {"idle": (0, (0, 0)), "kick": (-7, (5, -7)), "recover": (-3, (2, -3)),
                           "open": (12, (4, 14)), "eject": (15, (5, 18)), "load": (15, (5, 18)),
                           "close": (6, (2, 7)), "grind": (-2, (-3, 1)), "grind_hot": (-3, (-4, 0))}[pose]
            cel = to_cel(name, view, whole, turn, shift)
            if pose.startswith("grind"):
                for k in range(4 if pose == "grind" else 7):
                    spark(cel, (target[0] + 6 + k * 5 % 23, target[1] + 2 + (k * 7) % 11), 3, pose == "grind_hot")
            out[pose] = cel
    return out


def muzzle(name: str, view: dict, turn: float, shift: tuple[int, int]) -> list[float]:
    """Where the weapon's front point sits in a cel posed with to_cel(turn, shift)."""
    import math

    scale, target = LAYOUT[name][:2]
    pivot = (320 + view["grip"][0] + 60, 224 + view["grip"][1] + 90)
    x, y = 320 + view["front"][0] - pivot[0], 224 + view["front"][1] - pivot[1]
    c, k = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    moved = (x * c + y * k - x, -x * k + y * c - y)
    return [round(target[0] + moved[0] * scale + shift[0], 1), round(target[1] + moved[1] * scale + shift[1], 1)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--no-render", action="store_true")
    parser.add_argument("--only", default="")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    if not args.no_render:
        subprocess.run([BLENDER, "-b", "-P", str(ROOT / "scripts" / "blender" / "weapon_views.py"), "--",
                        str(RAW), args.only or "all"], check=True, stdout=subprocess.DEVNULL)
    from weapon_art import digitized_pose

    views = json.loads((RAW / "views.json").read_text())
    out_dir = ROOT / "_preview" / "weapon_cels" if args.preview else ART
    out_dir.mkdir(parents=True, exist_ok=True)
    anchors_path = ART / "weapon_anchors.json"
    anchors = json.loads(anchors_path.read_text())
    count = 0
    for name, view in views.items():
        if args.only and name not in args.only.split(","):
            continue
        made = cels(name, view)
        for pose, cel in made.items():
            digitized_pose(cel, None, pose).save(out_dir / f"gun_{name}_{pose}.png")
            count += 1
        posed = {"idle": (0, (0, 0)), "kick": (-7, (5, -7)), "recover": (-3, (2, -3))}
        if view["rig"] in ("pistol", "long"):
            anchors[name] = {pose: muzzle(name, view, *posed[pose]) for pose in posed if pose in made}
    if not args.preview:
        anchors_path.write_text(json.dumps(anchors, separators=(",", ":")), encoding="utf-8")
    print(f"weapon views: {count} cels in {out_dir}")


if __name__ == "__main__":
    main()
