"""Bake the breakable furniture (TV, toilet, vending machine, window sash, trash
can, jukebox) as meshes, whole and wrecked, in the same rendered look as the
weapons and props. Replaces the flat placeholder cels from content2.py.

    python scenery_models.py            # writes assets/art/scenery_<kind>_<state>.png
    python scenery_models.py --preview  # also a contact sheet in _preview/
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from rampage_weapons import lathe, sphere
from weapon_models import BLACK, BRASS, DARK_WOOD, STEEL, WOOD, Camera, Mesh, render

ROOT = Path(__file__).resolve().parent
ART = ROOT / "assets" / "art"
SIZE = (68, 66)

CABINET = (92, 62, 40, "wood", .30)
SCREEN = (120, 164, 170, "enamel", .95)
DEAD = (14, 16, 18, "rubber", .05)
SHARD = (170, 196, 200, "enamel", .95)
PORCELAIN = (224, 220, 206, "enamel", .80)
WATER = (86, 138, 160, "enamel", .95)
RED = (150, 44, 36, "enamel", .50)
RED_DULL = (104, 40, 34, "enamel", .20)
PANEL = (214, 220, 210, "paper", .30)
GALV = (128, 136, 138, "iron", .75)
GALV_DARK = (86, 92, 96, "iron", .50)
CHROME = (170, 176, 180, "iron", .95)
AMBER = (232, 168, 62, "paper", .85)
PLUM = (120, 46, 60, "enamel", .60)
GRILL = (60, 50, 40, "rubber", .10)
SASH = (176, 164, 140, "wood", .20)


def tv(spent):
    m = Mesh()
    m.block(0., .47, 1.0, .46, .50, .78, CABINET)
    m.block(.235, .49, 1.08, .012, .36, .50, DEAD if spent else SCREEN)
    m.block(.238, .49, .70, .012, .36, .14, DARK_WOOD)
    for y in (.58, .46):
        m.tube((.23, y, .70), (.27, y, .70), .032, .028, BRASS, n=9)
    for z in (.68, 1.32):
        for x in (-.16, .16):
            m.tube((x, .0, z), (x, .22, z), .028, .034, DARK_WOOD, n=7)
    if spent:
        for y, z, r in ((.52, 1.16, .07), (.44, 1.02, .05), (.58, .98, .04)):
            sphere(m, (.244, y, z), r, SHARD, n=6, bands=4, squash=(.12, 1., 1.))
        m.link([(.0, .72, 1.0), (.06, .92, .88)], (.012, .008), STEEL)
    else:
        m.link([(.0, .72, 1.0), (.0, 1.00, 1.22)], (.012, .008), STEEL)
        m.link([(.0, .72, 1.0), (.0, 1.00, .78)], (.012, .008), STEEL)
    return m


def toilet(spent):
    m = Mesh()
    # Pedestal, bowl and seat, with the tank behind.
    lathe(m, .10, 1.0, [(.0, .17), (.06, .15), (.24, .12), (.34, .22), (.42, .27)], PORCELAIN, n=16)
    lathe(m, .10, 1.0, [(.42, .29), (.45, .29)], PORCELAIN, n=18, ends=True)
    lathe(m, .10, 1.0, [(.452, .20), (.456, .20)], DEAD if spent else WATER, n=14)
    if spent:
        m.block(-.24, .52, 1.0, .20, .26, .50, PORCELAIN)
        m.link([(-.20, .66, 1.18), (-.10, .74, 1.26), (.02, .70, 1.30)], (.05, .04, .03), PORCELAIN)
        lathe(m, .34, .86, [(.004, .30), (.008, .30)], WATER, n=14)
        lathe(m, -.02, 1.36, [(.004, .20), (.008, .20)], WATER, n=12)
    else:
        m.block(-.24, .62, 1.0, .20, .46, .50, PORCELAIN)
        m.block(-.24, .86, 1.0, .23, .04, .54, PORCELAIN)
        m.tube((-.13, .74, 1.22), (-.08, .74, 1.24), .022, .018, CHROME, n=8)
    return m


def vending(spent):
    m = Mesh()
    m.block(0., .75, 1.0, .50, 1.50, .80, RED_DULL if spent else RED)
    m.block(.252, .98, 1.08, .012, .84, .50, DEAD if spent else PANEL)
    m.block(.252, .98, .70, .012, .84, .16, GALV_DARK)
    m.block(.256, .28, 1.0, .012, .22, .56, DEAD)
    if not spent:
        for row, y in enumerate((1.28, 1.08, .88, .68)):
            for col, z in enumerate((1.24, 1.08, .92)):
                tint = ((176, 60, 48), (66, 110, 150), (190, 150, 60))[(row + col) % 3]
                m.block(.262, y, z, .012, .12, .10, (*tint, "paper", .4))
    else:
        for y, z, r in ((1.10, 1.14, .10), (.86, .98, .07), (1.26, .96, .05)):
            sphere(m, (.258, y, z), r, SHARD, n=6, bands=4, squash=(.12, 1., 1.))
    for y in (1.10, .96, .82):
        m.tube((.25, y, .70), (.275, y, .70), .028, .024, CHROME, n=8)
    return m


def window(spent):
    """A salvaged sash leaning against the wall."""
    m = Mesh()
    lean = .22
    def at(y, z, x=0.):
        return (x - y * lean + .12, y, z)
    for z in (.62, 1.0, 1.38):
        m.link([at(.0, z), at(1.18, z)], (.035, .035), SASH)
    for y in (.02, .60, 1.17):
        m.link([at(y, .62), at(y, 1.38)], (.035, .035), SASH)
    if not spent:
        for y0, y1 in ((.05, .57), (.63, 1.14)):
            for z0, z1 in ((.65, .97), (1.03, 1.35)):
                m.face([at(y0, z0, .012), at(y0, z1, .012), at(y1, z1, .012), at(y1, z0, .012)], SCREEN)
    else:
        m.face([at(.05, .65, .012), at(.05, .97, .012), at(.30, .80, .012)], SHARD)
        m.face([at(.63, 1.35, .012), at(1.00, 1.35, .012), at(.63, 1.12, .012)], SHARD)
        for z, r in ((.80, .09), (1.16, .12), (1.44, .07)):
            lathe(m, .26, z, [(.004, r), (.008, r)], SHARD, n=7)
    return m


def cancan(spent):
    m = Mesh()
    if spent:
        # Kicked over: the can on its side, the lid rolled away.
        m.tube((0., .20, .66), (0., .20, 1.30), .20, .18, GALV, n=18)
        for z in (.74, .98, 1.22):
            m.tube((0., .20, z), (0., .20, z + .03), .207, .207, GALV_DARK, n=18)
        m.tube((0., .20, 1.30), (0., .20, 1.305), .165, .165, DEAD, n=16)
        lathe(m, .30, 1.56, [(.0, .21), (.03, .21), (.05, .12)], GALV_DARK, n=16)
    else:
        lathe(m, 0., 1.0, [(.0, .17), (.50, .20), (.52, .20)], GALV, n=18)
        for y in (.10, .28, .44):
            lathe(m, 0., 1.0, [(y, .206), (y + .025, .206)], GALV_DARK, n=18, ends=False)
        lathe(m, 0., 1.0, [(.52, .215), (.55, .215), (.60, .11), (.61, .04)], GALV_DARK, n=18)
        m.link([(0., .61, .96), (0., .66, 1.0), (0., .61, 1.04)], (.014, .014, .014), STEEL)
        for z in (.80, 1.20):
            m.link([(0., .40, z), (0., .34, z + (.04 if z > 1 else -.04)), (0., .28, z)], (.012, .012, .012), STEEL)
    return m


def jukebox(spent):
    m = Mesh()
    glow = DEAD if spent else AMBER
    m.block(0., .50, 1.0, .48, 1.00, .78, CABINET)
    # Arched top: a half drum across the cabinet.
    rings = []
    for k in range(9):
        a = math.pi * k / 8
        rings.append([(x, 1.00 + .39 * math.sin(a), 1.0 - .39 * math.cos(a)) for x in (-.24, .24)])
    for lo, hi in zip(rings, rings[1:]):
        m.face([lo[0], lo[1], hi[1], hi[0]], CHROME)
    front = [(.242, 1.00 + .36 * math.sin(math.pi * k / 8), 1.0 - .36 * math.cos(math.pi * k / 8))
             for k in range(9)]
    m.face(front, glow)
    m.block(.246, .72, 1.0, .012, .38, .56, PLUM if not spent else DEAD)
    m.block(.25, .30, 1.0, .012, .34, .56, GRILL)
    for z in (.66, 1.34):
        m.tube((.25, .12, z), (.25, 1.0, z), .034, .034, glow if not spent else GALV_DARK, n=8)
    for z in (.84, 1.0, 1.16):
        m.tube((.25, .14, z), (.25, .46, z), .012, .012, CHROME, n=6)
    if spent:
        for y, z, r in ((1.14, 1.06, .08), (.78, .92, .06)):
            sphere(m, (.25, y, z), r, SHARD, n=6, bands=4, squash=(.12, 1., 1.))
    return m


OAK = (112, 74, 44, "wood", .22)
HOOP = (62, 60, 58, "iron", .55)
PINE = (150, 112, 70, "wood", .16)
PINE_DARK = (112, 80, 50, "wood", .14)
STRAW = (190, 152, 74, "paper", .06)
STRAW_DARK = (150, 116, 54, "paper", .05)
TWINE = (96, 70, 40, "rubber", .05)
TREAD = (34, 33, 32, "rubber", .08)
DRUM_RED = (156, 46, 36, "enamel", .45)
DRUM_BAND = (214, 170, 60, "paper", .30)


def barrel():
    m = Mesh()
    lathe(m, 0., 1.0, [(.0, .27), (.20, .33), (.52, .37), (.84, .33), (1.04, .27)], OAK, n=22)
    for y, r in ((.08, .305), (.30, .352), (.74, .352), (.96, .305)):
        lathe(m, 0., 1.0, [(y - .025, r), (y + .025, r)], HOOP, n=22, ends=False)
    lathe(m, 0., 1.0, [(1.02, .24), (1.025, .24)], PINE_DARK, n=18)
    return m


def crate():
    m = Mesh()
    m.block(0., .375, 1.0, .70, .75, .70, PINE)
    # Frame and a diagonal brace on the two faces the camera sees.
    for y in (.04, .71):
        m.block(.352, y, 1.0, .02, .08, .72, PINE_DARK)
        m.block(0., y, .648, .72, .08, .02, PINE_DARK)
    for z in (.66, 1.34):
        m.block(.352, .375, z, .02, .75, .08, PINE_DARK)
    for x in (-.34, .34):
        m.block(x, .375, .648, .08, .75, .02, PINE_DARK)
    m.face([(.356, .08, .70), (.356, .16, .70), (.356, .68, 1.30), (.356, .60, 1.30)], PINE_DARK)
    m.face([(-.30, .08, .644), (-.30, .16, .644), (.30, .68, .644), (.30, .60, .644)], PINE_DARK)
    m.block(0., .752, 1.0, .72, .012, .72, PINE_DARK)
    return m


def hay():
    m = Mesh()
    m.loft([(.56, 0., .455, .37, .45), (.60, 0., .455, .40, .455), (1.40, 0., .455, .40, .455),
            (1.44, 0., .455, .37, .45)], STRAW, box=True)
    for z in (.66, .78, .90, 1.02, 1.14, 1.26, 1.38):
        m.block(0., .455, z, .805, .915, .012, STRAW_DARK)
    for z in (.80, 1.20):
        m.block(0., .455, z, .82, .93, .03, TWINE)
    for x, y, z in ((.30, .93, .70), (-.20, .93, 1.10), (.36, .50, 1.46), (.10, .94, 1.34)):
        m.link([(x, y, z), (x + .06, y + .05, z + .05)], (.012, .006), STRAW)
    return m


def tire():
    m = Mesh()
    # A tire lying flat: the tread ring, the sidewall, and the dark of the hole.
    lathe(m, 0., 1.0, [(.0, .40), (.04, .47), (.20, .50), (.36, .47), (.40, .40)], TREAD, n=26)
    lathe(m, 0., 1.0, [(.40, .40), (.405, .40)], (52, 50, 48, "rubber", .10), n=26)
    lathe(m, 0., 1.0, [(.406, .26), (.410, .26)], (10, 10, 10, "rubber", .02), n=22)
    for k in range(13):
        a = math.tau * k / 13
        m.tube((.505 * math.cos(a), .08, 1.0 + .505 * math.sin(a)),
               (.505 * math.cos(a), .32, 1.0 + .505 * math.sin(a)), .018, .018,
               (20, 20, 20, "rubber", .04), n=5)
    return m


def fuel():
    m = Mesh()
    lathe(m, 0., 1.0, [(.0, .30), (1.04, .30)], DRUM_RED, n=22)
    for y in (.02, .36, .70, 1.02):
        lathe(m, 0., 1.0, [(y - .02, .312), (y + .02, .312)], (116, 38, 32, "enamel", .4), n=22, ends=False)
    lathe(m, 0., 1.0, [(.44, .316), (.62, .316)], DRUM_BAND, n=22, ends=False)
    lathe(m, 0., 1.0, [(1.04, .27), (1.045, .27)], (120, 40, 34, "enamel", .3), n=20)
    m.tube((.12, 1.045, 1.10), (.12, 1.075, 1.10), .045, .040, HOOP, n=9)
    return m


# name -> (builder, canvas size, box the old cel filled)
PROPS = {
    "barrel": (barrel, (58, 88), (9, 10, 50, 88)),
    "crate": (crate, (58, 88), (3, 16, 57, 88)),
    "hay": (hay, (58, 88), (3, 16, 57, 88)),
    "tire": (tire, (75, 57), (2, 3, 73, 57)),
    "fuel": (fuel, (58, 88), (9, 10, 50, 88)),
}


def prop_cel(mesh, canvas, box, yaw=.42):
    image = render(mesh, Camera(side=True, yaw=yaw, roll=-.62, pitch=-.21))
    image = image.crop(image.getchannel("A").point(lambda a: 255 if a > 112 else 0).getbbox())
    image = image.resize((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
    rgba = np.array(image)
    rgba[:, :, :3] = np.asarray(image.convert("RGB").filter(ImageFilter.UnsharpMask(.6, 90, 3)))
    rgba[..., 3] = np.where(rgba[..., 3] >= 112, 255, 0)
    out = Image.new("RGBA", canvas)
    out.alpha_composite(Image.fromarray(rgba), (box[0], box[1]))
    return out


def make_props(preview=False):
    strip = Image.new("RGB", (80 * len(PROPS), 90), (52, 70, 78))
    for i, (name, (make, canvas, box)) in enumerate(PROPS.items()):
        image = prop_cel(make(), canvas, box)
        image.save(ART / f"prop_{name}.png")
        strip.paste(image, (i * 80, 90 - canvas[1]), image)
    if preview:
        out = ROOT / "_preview"
        out.mkdir(exist_ok=True)
        strip.resize((strip.width * 4, strip.height * 4), Image.NEAREST).save(out / "prop_models.png")


KINDS = (("tv", tv), ("toilet", toilet), ("vending", vending), ("window", window),
         ("cancan", cancan), ("jukebox", jukebox))


def cel(mesh):
    image = render(mesh, Camera(side=True, yaw=.42, roll=-.62, pitch=-.21))
    box = image.getchannel("A").point(lambda a: 255 if a > 112 else 0).getbbox()
    image = image.crop(box)
    image.thumbnail((SIZE[0] - 2, SIZE[1] - 2), Image.Resampling.LANCZOS)
    rgba = np.array(image)
    rgba[:, :, :3] = np.asarray(image.convert("RGB").filter(ImageFilter.UnsharpMask(.6, 90, 3)))
    rgba[..., 3] = np.where(rgba[..., 3] >= 112, 255, 0)
    image = Image.fromarray(rgba)
    out = Image.new("RGBA", SIZE)
    out.alpha_composite(image, ((SIZE[0] - image.width) // 2, SIZE[1] - image.height))
    return out


def make_scenery(preview=False):
    sheet = Image.new("RGB", (SIZE[0] * len(KINDS), SIZE[1] * 2), (52, 70, 78))
    for column, (kind, make) in enumerate(KINDS):
        for row, (state, spent) in enumerate((("whole", False), ("spent", True))):
            image = cel(make(spent))
            image.save(ART / f"scenery_{kind}_{state}.png")
            sheet.paste(image, (column * SIZE[0], row * SIZE[1]), image)
    if preview:
        out = ROOT / "_preview"
        out.mkdir(exist_ok=True)
        sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(out / "scenery_models.png")


if __name__ == "__main__":
    make_scenery(preview="--preview" in sys.argv)
    make_props(preview="--preview" in sys.argv)
