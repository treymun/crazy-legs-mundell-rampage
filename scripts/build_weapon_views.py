"""Cut the first-person cels for the thirteen weapons that are not photographed plates.

    python scripts/build_weapon_views.py [--no-render] [--only rifle,tnt] [--preview]

The crowbar, revolver and shotgun are photographs with the hands in them.
Blender (scripts/blender/weapon_views.py) renders every other weapon through
the camera of one of those plates, so here the plate's own hand is laid over
the weapon at the plate's own size and place, and the result goes through the
same layout the plate goes through in weapon_art.py (LAYOUT below). A weapon
held like the revolver therefore shows the revolver's hand, pixel for pixel,
where the revolver shows it.

--preview writes the cels to _preview/weapon_cels instead of assets/art.
"""
from __future__ import annotations

import argparse
import json
import math
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
CEL = (320, 174)
PLATE_AT = (640, 448)       # where the plate's frame sits on the 1280x896 render

# The hand in each plate, as an outline on the plate.
HANDS = {
    "pistol": ("revolver", ((228, 308), (246, 268), (272, 246), (302, 240), (340, 246), (368, 206), (396, 188),
                            (430, 195), (456, 216), (482, 250), (520, 290), (560, 316), (600, 336), (640, 346),
                            (640, 448), (300, 448), (286, 420), (280, 386), (256, 350), (236, 336))),
    "bar": ("crowbar", ((322, 268), (340, 236), (366, 216), (400, 210), (430, 226), (456, 250), (480, 280),
                        (500, 320), (540, 360), (590, 376), (640, 400), (640, 432), (432, 432), (400, 400),
                        (370, 370), (346, 340), (324, 302))),
    "long": ("shotgun", ((42, 160), (55, 136), (75, 126), (95, 136), (110, 160), (125, 186), (140, 216),
                         (160, 250), (184, 290), (200, 330), (190, 370), (176, 400), (166, 448), (0, 448),
                         (0, 380), (20, 330), (38, 270), (40, 210))),
}
# How weapon_art.py seats each plate in the 320x174 layout: where the plate's
# corner goes, the plate's scale, its turn (degrees clockwise) about a point,
# then the window (zoom, left, top) the finished cel shows.
LAYOUT = {
    "pistol": ((144, 101), 80 / 640, 25, (201, 147), (1.70, 72.4, 57.4)),
    "long": ((155, 106), 101 / 640, 12, (235, 161), (1.75, 84.9, 67.5)),
    "bar": ((96, 30), 164 / 640, 0, (0, 0), (1.0, 0, 0)),
    "carry": ((62, 24), .306, 0, (0, 0), (1.0, 0, 0)),
    "ball": ((104, 22), .306, 0, (0, 0), (1.0, 0, 0)),
}
# Pose -> (extra clockwise turn about the wrist, shift) in layout pixels.
GUN = {"idle": (0, (0, 0)), "kick": (12, (-2, -6)), "recover": (5, (-1, -2)), "open": (-12, (5, 9)),
       "eject": (-16, (6, 12)), "load": (-16, (6, 12)), "close": (-6, (3, 5)),
       "grind": (2, (-2, 1)), "grind_hot": (3, (-3, 0))}
SWING = {"idle": (0, (0, 0)), "wind": (22, (10, -6)), "strike": (-30, (-24, 2)), "follow": (-46, (-30, 12)),
         "recover": (-18, (-10, 8))}
THROW = {"idle": (0, (0, 0)), "kick": (-14, (-10, -8)), "throw": (-26, (-22, -20)), "lit": (0, (0, 0)),
         "lit_alt": (0, (0, 0)), "dry": (0, (0, 4))}
CARRY = {"idle": (0, (0, 0), True), "kick": (0, (0, -12), False), "recover": (0, (0, 6), False),
         "open": (0, (0, 20), False), "eject": (0, (0, 28), False), "load": (0, (0, 24), True),
         "close": (0, (0, 9), True)}
WRIST = {"pistol": (219, 145), "long": (248, 158), "bar": (212, 116), "carry": (160, 174),
         "ball": (202, 174)}
GUN_POSES = ("idle", "kick", "recover", "open", "eject", "load", "close")
POSES = {"slingblade": tuple(SWING), "tnt": tuple(THROW),
         "ripsaw": ("idle", "kick", "open", "eject", "load", "close", "grind", "grind_hot"),
         "crossbow": ("idle", "kick", "open", "eject", "load", "close")}


def turn_about(point, degrees):
    """3x3 matrix: clockwise turn on screen (y down) about `point`."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    x, y = point
    return np.array(((c, -s, x - c * x + s * y), (s, c, y - s * x - c * y), (0, 0, 1)))


def move(dx, dy):
    return np.array(((1., 0, dx), (0, 1., dy), (0, 0, 1)))


def grow(k):
    return np.array(((k, 0, 0), (0, k, 0), (0, 0, 1.)))


def to_cel(rig: str, turn: float = 0., shift=(0, 0)) -> np.ndarray:
    """Matrix taking a pixel of the 1280x896 render to the 320x174 cel."""
    corner, scale, tilt, about, (zoom, left, top) = LAYOUT[rig]
    plate = move(*corner) @ grow(scale) @ move(-PLATE_AT[0], -PLATE_AT[1])
    seated = turn_about(about, tilt) @ plate
    posed = move(*shift) @ turn_about(WRIST[rig], turn) @ seated
    return grow(zoom) @ move(-left, -top) @ posed


def lay(image: Image.Image, matrix: np.ndarray) -> Image.Image:
    inverse = np.linalg.inv(matrix)
    big = image.transform((CEL[0] * 4, CEL[1] * 4), Image.Transform.AFFINE,
                          tuple((inverse @ grow(.25))[:2].reshape(6)), Image.Resampling.BICUBIC)
    return big.resize(CEL, Image.Resampling.LANCZOS)


def weathered(image: Image.Image, seed: int) -> Image.Image:
    """Pull a clean render toward the plates: flatter colour, harder edges, a little grain."""
    rgb = ImageEnhance.Color(image.convert("RGB")).enhance(.80)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.14)
    rgb = ImageEnhance.Brightness(rgb).enhance(.94)
    rgb = rgb.filter(ImageFilter.UnsharpMask(2.0, 80, 2))
    arr = np.asarray(rgb, dtype=np.float32)
    arr += np.random.default_rng(seed).normal(0, 5.0, arr.shape[:2])[..., None]
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(image.getchannel("A"))
    return out


def plate_hand(rig: str) -> Image.Image:
    """The plate's hand on a transparent 1280x896 sheet, exactly where the plate has it."""
    plate, outline = HANDS[rig]
    source = Image.open(SOURCE / f"{plate}_plate.png").convert("RGBA")
    mask = Image.new("L", source.size)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.0))
    source.putalpha(Image.fromarray(np.minimum(np.asarray(source.getchannel("A")), np.asarray(mask))))
    sheet = Image.new("RGBA", (1280, 896))
    sheet.alpha_composite(source, PLATE_AT)
    return sheet


def carry_hands(view: dict) -> Image.Image:
    """Two of the shotgun's cupping hands under something round."""
    plate, outline = HANDS["long"]
    source = Image.open(SOURCE / f"{plate}_plate.png").convert("RGBA")
    mask = Image.new("L", source.size)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    source.putalpha(Image.fromarray(np.minimum(np.asarray(source.getchannel("A")), np.asarray(mask))))
    cut = source.crop(source.getchannel("A").getbbox())
    cut = cut.resize((round(cut.width * .9), round(cut.height * .9)), Image.Resampling.LANCZOS)
    sheet = Image.new("RGBA", (1280, 896))
    cx, cy = view["grip"]
    for mirror, dx in ((False, -150), (True, 150 - cut.width)):
        piece = ImageOps.mirror(cut) if mirror else cut
        sheet.alpha_composite(piece, (round(cx + dx), round(cy - 6)))
    return sheet


def spark(cel: Image.Image, at, size: int, hot: bool) -> None:
    d = ImageDraw.Draw(cel)
    x, y = at
    for dx, dy in ((size, 0), (-size, 0), (0, size), (0, -size), (size * .6, size * .6), (-size * .6, -size * .6)):
        d.line((x, y, x + dx, y + dy), fill="#ff9a30", width=1)
    d.ellipse((x - 1, y - 1, x + 1, y + 1), fill="#fff2b0" if hot else "#ffd070")


def cels(name: str, view: dict) -> tuple[dict[str, Image.Image], dict[str, list[float]]]:
    rig = view["rig"]
    weapon = weathered(Image.open(RAW / f"{name}.png").convert("RGBA"), sum(map(ord, name)))
    hands = carry_hands(view) if rig == "carry" else plate_hand(rig)
    held = Image.new("RGBA", weapon.size)
    if rig == "carry":
        held.alpha_composite(hands)
        held.alpha_composite(weapon)
    else:
        held.alpha_composite(weapon)
        held.alpha_composite(hands)
    table = SWING if name == "slingblade" else THROW if name == "tnt" else CARRY if rig == "carry" else GUN
    out, fronts = {}, {}
    for pose in POSES.get(name, GUN_POSES):
        entry = table[pose]
        # The bowling ball is carried low on the right, the keg in front of the belly.
        matrix = to_cel("ball" if name == "bowling_ball" else rig, entry[0], entry[1])
        source = held
        if (rig == "carry" and not entry[2]) or (name == "tnt" and pose == "dry"):
            source = hands
        cel = lay(source, matrix)
        front = matrix @ np.array((view["front"][0], view["front"][1], 1.0))
        if name == "tnt" and pose.startswith("lit"):
            spark(cel, (front[0], front[1]), 5 if pose == "lit" else 3, pose == "lit")
        if pose.startswith("grind"):
            for k in range(4 if pose == "grind" else 7):
                spark(cel, (front[0] + 4 + k * 5 % 19, front[1] + 3 + (k * 7) % 11), 3, pose == "grind_hot")
        out[pose] = cel
        fronts[pose] = [round(float(front[0]), 1), round(float(front[1]), 1)]
    return out, fronts


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
        made, fronts = cels(name, view)
        for pose, cel in made.items():
            digitized_pose(cel, None, pose).save(out_dir / f"gun_{name}_{pose}.png")
            count += 1
        if view["rig"] in ("pistol", "long"):
            anchors[name] = {pose: fronts[pose] for pose in ("idle", "kick", "recover") if pose in fronts}
    if not args.preview:
        anchors_path.write_text(json.dumps(anchors, separators=(",", ":")), encoding="utf-8")
    print(f"weapon views: {count} cels in {out_dir}")


if __name__ == "__main__":
    main()
