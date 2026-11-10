"""Bake the bowling ball, powder keg, cow launcher and teat gun viewmodels.

These four replace the flat placeholder cels from content2.py with meshes
rendered by the same offline rasterizer as the rest of the arsenal, so every
weapon shares one light, one camera and one set of hands.

    python rampage_weapons.py            # writes assets/art/gun_<name>_<pose>.png
    python rampage_weapons.py --preview  # also writes a contact sheet to _preview/
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from weapon_models import BLACK, BRASS, METAL, STEEL, WOOD, DARK_WOOD, Camera, Mesh, glove, render

ROOT = Path(__file__).resolve().parent
ART = ROOT / "assets" / "art"
POSES = ("idle", "kick", "recover", "open", "eject", "load", "close")

BALL = (34, 44, 66, "enamel", .92)
BALL_SWIRL = (58, 74, 104, "enamel", .92)
HOLE = (9, 10, 12, "rubber", .02)
STAVE = (118, 76, 42, "wood", .22)
HOOP = (58, 56, 54, "iron", .55)
STENCIL = (176, 44, 34, "paper", .08)
FUSE = (186, 170, 132, "paper", .05)
EMBER = (255, 190, 80, "paper", .9)
PIPE = (104, 110, 112, "iron", .70)
SOOT = (40, 38, 36, "iron", .20)
RUST = (112, 68, 44, "iron", .40)
HIDE_WHITE = (214, 206, 190, "hide", .10)
HIDE_BLACK = (38, 34, 32, "hide", .10)
NOSE = (198, 132, 126, "rubber", .30)
HORN = (206, 190, 150, "hide", .40)
CAN = (132, 140, 142, "iron", .78)
CAN_DARK = (84, 92, 96, "iron", .60)
UDDER = (214, 142, 136, "rubber", .34)
TEAT = (196, 112, 112, "rubber", .40)
HOSE = (50, 46, 42, "rubber", .08)
DIAL = (206, 196, 160, "paper", .10)
MILK = (236, 232, 218, "paper", .30)


def hand(mesh, x, y, z):
    """The same right hand the other improvised weapons use."""
    glove(mesh, (x, y, z), (x + .10, y - .14, z - .16), [
        [(x - .03, y + .03, z + .022), (x - .08, y + .06, z + .06), (x - .089, y + .05, z + .091)],
        [(x - .03, y - .035, z + .04), (x - .089, y + .011, z + .10), (x - .110, y + .019, z + .10)],
        [(x - .03, y - .077, z + .045), (x - .081, y - .023, z + .097), (x - .108, y - .022, z + .090)],
        [(x - .031, y - .096, z + .017), (x - .078, y - .064, z + .076), (x - .101, y - .047, z + .073)],
    ])


def left_hand(mesh, x, y, z):
    """A mirrored hand reaching in from the left edge of the picture."""
    glove(mesh, (x, y, z), (x - .16, y - .15, z - .15), [
        [(x + .03, y + .03, z + .022), (x + .08, y + .06, z + .06), (x + .089, y + .05, z + .091)],
        [(x + .03, y - .035, z + .04), (x + .089, y + .011, z + .10), (x + .110, y + .019, z + .10)],
        [(x + .03, y - .077, z + .045), (x + .081, y - .023, z + .097), (x + .108, y - .022, z + .090)],
        [(x + .031, y - .096, z + .017), (x + .078, y - .064, z + .076), (x + .101, y - .047, z + .073)],
    ])


def sphere(mesh, centre, radius, mat, n=20, bands=12, squash=(1., 1., 1.)):
    cx, cy, cz = centre
    rings = []
    for k in range(bands + 1):
        theta = math.pi * (k + .0001 if k == 0 else k - .0001 if k == bands else k) / bands
        r = radius * math.sin(theta)
        z = cz - radius * math.cos(theta) * squash[2]
        rings.append([(cx + r * math.cos(a) * squash[0], cy + r * math.sin(a) * squash[1], z)
                      for a in np.arange(n) * math.tau / n])
    mesh.rings(rings, mat, ends=False)


def lathe(mesh, cx, cz, profile, mat, n=18, ends=True):
    """A turned shape standing upright: profile is [(y, radius), ...] bottom to top."""
    rings = [[(cx + r * math.cos(a), y, cz + r * math.sin(a))
              for a in np.arange(n) * math.tau / n] for y, r in profile]
    mesh.rings(rings, mat, ends=ends)


# ------------------------------------------------------------------ bowling

def bowling(pose):
    m = Mesh()
    has_ball = pose in ("idle", "load", "close", "pickup")
    reach = {"kick": .46, "recover": .30, "open": .12}.get(pose, 0.)
    drop = {"kick": -.20, "recover": -.12, "open": -.04, "eject": -.10}.get(pose, 0.)
    if has_ball:
        c = (-.03, .05, 1.20)
        sphere(m, c, .33, BALL, n=26, bands=16)
        # Marbled swirl: two shallow caps just proud of the surface.
        sphere(m, (c[0] - .10, c[1] + .13, c[2] - .10), .225, BALL_SWIRL, n=16, bands=8)
        sphere(m, (c[0] + .15, c[1] - .02, c[2] - .13), .19, BALL_SWIRL, n=16, bands=8)
        # Finger holes on the face turned to the player.
        for dx, dy in ((-.075, .215), (.035, .235), (-.015, .125)):
            m.tube((c[0] + dx, c[1] + dy, c[2] - .262), (c[0] + dx, c[1] + dy, c[2] - .30),
                   .040, .040, HOLE, n=10)
        if pose != "pickup":
            hand(m, .17, -.21, 1.02)
            m.link([(.15, -.18, 1.06), (.21, -.02, 1.16), (.20, .10, 1.26)], (.034, .030, .024),
                   (149, 104, 76, "skin", .12))
    else:
        # Follow-through: the open hand low and forward after the roll.
        hand(m, .10, -.24 + drop, .92 + reach)
    return m, None


BOWLING_VIEW = {
    "idle": dict(x=-.10, y=.06, yaw=-.06, roll=-.04, z=-.52),
    "kick": dict(x=-.22, y=.00, yaw=-.14, roll=.10, z=-.30),
    "recover": dict(x=-.16, y=.02, yaw=-.10, roll=.05, z=-.42),
    "open": dict(x=-.06, y=-.02, yaw=-.02, roll=-.06, z=-.52),
    "eject": dict(x=-.02, y=-.10, yaw=.02, roll=-.10, z=-.52),
    "load": dict(x=-.04, y=-.20, yaw=-.02, roll=-.10, z=-.52),
    "close": dict(x=-.08, y=-.04, yaw=-.05, roll=-.06, z=-.52),
}


# --------------------------------------------------------------------- keg

def keg(pose):
    m = Mesh()
    has_keg = pose in ("idle", "load", "close", "pickup")
    if has_keg:
        cx, cz, base = -.04, 1.22, -.22
        profile = [(base, .215), (base + .10, .262), (base + .27, .292), (base + .44, .262),
                   (base + .54, .215)]
        lathe(m, cx, cz, profile, STAVE, n=22)
        for y, r in ((base + .045, .247), (base + .175, .286), (base + .365, .286), (base + .495, .247)):
            lathe(m, cx, cz, [(y - .020, r), (y + .020, r)], HOOP, n=22, ends=False)
        # Stencilled warning band and the bung with its fuse.
        lathe(m, cx, cz, [(base + .235, .2945), (base + .305, .2945)], STENCIL, n=22, ends=False)
        m.tube((cx, base + .54, cz), (cx, base + .575, cz), .060, .052, DARK_WOOD, n=10)
        fuse = [(cx, base + .57, cz), (cx - .03, base + .66, cz - .02), (cx - .09, base + .71, cz - .05),
                (cx - .13, base + .70, cz - .09)]
        m.link(fuse, (.014, .013, .012, .010), FUSE)
        if pose in ("idle", "pickup"):
            sphere(m, fuse[-1], .030, EMBER, n=8, bands=5)
        if pose != "pickup":
            hand(m, .215, -.14, 1.12)
            left_hand(m, -.32, -.16, 1.10)
    else:
        push = {"kick": .40, "recover": .24, "open": .10}.get(pose, 0.)
        hand(m, .16, -.20, .94 + push)
        left_hand(m, -.26, -.22, .92 + push)
    return m, None


KEG_VIEW = {
    "idle": dict(x=-.14, y=.03, yaw=-.04, roll=-.03, z=-.50),
    "kick": dict(x=-.14, y=.07, yaw=-.04, pitch=-.10, z=-.40),
    "recover": dict(x=-.14, y=.02, yaw=-.04, pitch=-.04, z=-.46),
    "open": dict(x=-.14, y=-.08, yaw=-.04, z=-.50),
    "eject": dict(x=-.14, y=-.18, yaw=-.04, z=-.50),
    "load": dict(x=-.14, y=-.22, yaw=-.04, roll=-.08, z=-.50),
    "close": dict(x=-.14, y=-.06, yaw=-.04, roll=-.05, z=-.50),
}


# --------------------------------------------------------------------- cow

def cow(pose):
    m = Mesh()
    tilt = {"open": .22, "eject": .36, "load": .34, "close": .10}.get(pose, 0.)
    back = .13 if pose == "kick" else .05 if pose == "recover" else 0.

    def at(z, x=-.03, y=.10):
        z -= back
        return x, y - (z - 1.20) * math.sin(tilt), 1.20 + (z - 1.20) * math.cos(tilt)

    # Plank stock and a wrapped grip.
    m.loft([(.40, .02, -.11, .10, .14), (.70, .01, -.09, .12, .13), (1.20, -.02, -.06, .12, .09),
            (1.74, -.03, -.05, .10, .07)], WOOD, n=12)
    m.tube((-.02, -.07, .80), (.02, -.36, .66), .080, .062, DARK_WOOD, n=12)
    # Stovepipe barrel: two crimped sections, soot at the mouth, rust at the seams.
    m.tube(at(.98), at(1.40), .235, .242, PIPE, n=24)
    m.tube(at(1.38), at(1.78), .246, .262, PIPE, n=24)
    for z, r, mat in ((.98, .250, RUST), (1.19, .246, STEEL), (1.39, .262, RUST), (1.58, .264, STEEL),
                      (1.74, .278, SOOT)):
        m.tube(at(z), at(z + .05), r, r, mat, n=24)
    m.tube(at(1.780), at(1.786), .222, .222, BLACK, n=22)
    # Breech: a domed stove cap with a wing-nut, closed toward the player.
    m.tube(at(.98), at(.90), .236, .150, RUST, n=24)
    m.tube(at(.90), at(.885), .150, .060, STEEL, n=18)
    m.tube(at(.885), at(.84), .034, .030, BRASS, n=10)
    # Baling-wire straps to the plank and a bent-nail sight.
    for z in (1.16, 1.52):
        m.link([at(z, -.25, .02), at(z, -.20, -.10), at(z, .00, -.15), at(z, .17, -.10),
                at(z, .21, .02)], (.014, .014, .014, .014, .014), RUST)
    muzzle = at(1.80)
    if pose in ("idle", "close", "load", "pickup"):
        # The passenger: head out of the muzzle, looking back down the bore.
        out = .13 if pose != "load" else -.02
        hx, hy, hz = at(1.86 + out)
        hy += .16
        k = 1.35
        sphere(m, (hx, hy, hz), .215 * k, HIDE_WHITE, n=18, bands=10, squash=(1., .95, 1.1))
        sphere(m, (hx + .11 * k, hy + .09 * k, hz - .06 * k), .135 * k, HIDE_BLACK, n=12, bands=7)
        sphere(m, (hx - .13 * k, hy - .02 * k, hz - .08 * k), .095 * k, HIDE_BLACK, n=12, bands=7)
        for side in (-1, 1):
            m.link([(hx + side * .14 * k, hy + .14 * k, hz), (hx + side * .25 * k, hy + .25 * k, hz + .01),
                    (hx + side * .27 * k, hy + .37 * k, hz + .02)], (.040 * k, .030 * k, .010 * k), HORN)
            m.link([(hx + side * .18 * k, hy + .05 * k, hz - .01),
                    (hx + side * .33 * k, hy + .08 * k, hz - .03),
                    (hx + side * .41 * k, hy + .04 * k, hz - .04)], (.050 * k, .058 * k, .016 * k),
                   HIDE_BLACK if side > 0 else HIDE_WHITE)
    if pose == "pickup":
        return m, muzzle
    hand(m, .04, -.20, .70)
    if pose in ("eject", "load"):
        left_hand(m, -.34, .12, 1.36 if pose == "load" else 1.22)
    else:
        left_hand(m, -.30, -.12, 1.34 - back)
    return m, muzzle


COW_VIEW = {
    "idle": dict(x=.00, y=.06, yaw=-.20, roll=-.07, z=-.30),
    "kick": dict(x=.035, y=.125, yaw=-.22, pitch=-.085, z=-.45, roll=-.11),
    "recover": dict(x=.015, y=.085, yaw=-.21, pitch=-.03, z=-.35, roll=-.09),
    "open": dict(x=.00, y=.17, yaw=-.28, roll=-.22, z=-.30),
    "eject": dict(x=-.03, y=.19, yaw=-.35, roll=-.32, z=-.30),
    "load": dict(x=-.03, y=.20, yaw=-.34, roll=-.28, z=-.30),
    "close": dict(x=.00, y=.12, yaw=-.24, roll=-.15, z=-.30),
}


# -------------------------------------------------------------------- teat

def teat(pose):
    m = Mesh()
    back = .07 if pose == "kick" else .03 if pose == "recover" else 0.
    lift = {"open": .10, "eject": .20, "load": .16, "close": .04}.get(pose, 0.)

    def at(z, x=0., y=0.):
        return x, y, z - back

    # Galvanized milk can for a receiver: shoulder, neck and a clamped lid.
    m.loft([(.80, .00, .02, .165, .160), (1.30, .00, .02, .172, .166), (1.44, .00, .03, .120, .116),
            (1.56, .00, .03, .120, .116)], CAN, n=22)
    for z in (.84, 1.06, 1.28):
        m.tube(at(z, 0., .02), at(z + .035, 0., .02), .182, .182, CAN_DARK, n=22, ratio=.96)
    m.tube(at(.80, 0., .02), at(.76, 0., .02), .155, .120, CAN_DARK, n=20)
    # Pistol grip and a wire bail folded back over the top.
    m.tube(at(.92, .02, -.15), at(.84, .06, -.42), .078, .062, DARK_WOOD, n=12)
    m.link([at(.86, -.20, .10), at(.90, -.17, .29), at(1.10, .00, .36), at(1.24, .17, .29),
            at(1.30, .20, .10)], (.016, .016, .016, .016, .016), STEEL)
    # Pressure dial on a brass stem, set high on the left where the player reads it.
    gx, gy, gz = -.15, .285, 1.18 - back
    m.tube((-.08, .17, gz), (gx, gy - .04, gz), .028, .028, BRASS, n=10)
    m.tube((gx, gy, gz + .06), (gx, gy, gz - .012), .105, .105, BRASS, n=20)
    m.tube((gx, gy, gz - .013), (gx, gy, gz - .018), .084, .084, DIAL, n=20)
    needle = (gx + .050, gy + .030) if pose in ("kick", "recover") else (gx - .045, gy + .035)
    m.link([(gx, gy - .01, gz - .021), (gx, gy, gz - .022), (*needle, gz - .022)],
           (.008, .009, .006), RUST)
    # The udder up front: one rubber bag, four teats for barrels.
    ux, uy, uz = 0., -.03, 1.76 - back
    sphere(m, (ux, uy, uz), .285, UDDER, n=20, bands=10, squash=(1.05, .95, 1.0))
    tips = []
    for dx, dy in ((-.15, .13), (.15, .13), (-.15, -.16), (.15, -.16)):
        start = (ux + dx, uy + dy, uz + .13)
        end = (ux + dx * 2.2, uy + dy * 2.1, uz + .42)
        m.tube(start, end, .085, .052, TEAT, n=12)
        sphere(m, end, .056, TEAT, n=10, bands=6)
        m.tube(end, (end[0], end[1], end[2] + .046), .016, .014, BLACK, n=8)
        tips.append(end)
    if pose == "kick":
        for tip in tips[:2]:
            sphere(m, (tip[0], tip[1], tip[2] + .09), .034, MILK, n=8, bands=5)
    # Hose from the lid round to the udder, and the feed jar that lifts to reload.
    m.link([at(1.60, .12, .13), at(1.72, .26, .12), at(1.86, .25, .02), at(1.90, .16, -.02)],
           (.030, .032, .030, .026), HOSE)
    jar_y = .23 + lift
    m.tube(at(1.02, .05, jar_y), at(1.02, .05, jar_y + .21), .098, .098, MILK, n=16)
    m.tube(at(1.02, .05, jar_y + .21), at(1.02, .05, jar_y + .255), .074, .060, CAN_DARK, n=14)
    m.tube(at(1.02, .05, jar_y - .03), at(1.02, .05, jar_y), .104, .104, CAN_DARK, n=16)
    muzzle = (ux, uy - .015, uz + .46)
    if pose == "pickup":
        return m, muzzle
    hand(m, .06, -.30, .78)
    if lift:
        left_hand(m, -.20, jar_y + .02, .98)
    else:
        left_hand(m, -.30, -.16, 1.36 - back)
    return m, muzzle


TEAT_VIEW = {
    "idle": dict(x=-.06, y=.09, yaw=-.17, roll=-.05, z=-.28),
    "kick": dict(x=-.045, y=.11, yaw=-.175, pitch=-.035, z=-.33, roll=-.06),
    "recover": dict(x=-.055, y=.097, yaw=-.17, pitch=-.012, z=-.30, roll=-.055),
    "open": dict(x=-.06, y=.16, yaw=-.22, roll=-.17, z=-.28),
    "eject": dict(x=-.07, y=.20, yaw=-.27, roll=-.27, z=-.28),
    "load": dict(x=-.07, y=.19, yaw=-.25, roll=-.24, z=-.28),
    "close": dict(x=-.06, y=.12, yaw=-.19, roll=-.11, z=-.28),
}

def whole_cow():
    """The cow in flight: what the launcher throws and what its ammo box holds."""
    m = Mesh()
    sphere(m, (0., .0, 1.20), .30, HIDE_WHITE, n=18, bands=10, squash=(.85, .9, 1.75))
    sphere(m, (.10, .12, 1.05), .17, HIDE_BLACK, n=12, bands=7, squash=(1., 1., 1.3))
    sphere(m, (.12, .02, 1.48), .14, HIDE_BLACK, n=12, bands=7, squash=(1., 1., 1.2))
    sphere(m, (0., .10, 1.86), .17, HIDE_WHITE, n=14, bands=8, squash=(.9, .9, 1.2))
    sphere(m, (0., .03, 2.02), .09, NOSE, n=10, bands=6)
    sphere(m, (0., -.27, 1.02), .10, UDDER, n=10, bands=6)
    for side in (-1, 1):
        m.link([(side * .09, .22, 1.84), (side * .17, .31, 1.86), (side * .18, .40, 1.88)],
               (.030, .022, .008), HORN)
        m.link([(side * .13, .16, 1.80), (side * .26, .17, 1.78)], (.040, .014), HIDE_BLACK)
        for z, kick in ((.86, -.16), (1.56, .16)):
            m.link([(side * .13, -.16, z), (side * .14, -.40, z + kick), (side * .14, -.58, z + kick * 1.7)],
                   (.060, .045, .040), HIDE_WHITE)
            m.tube((side * .14, -.58, z + kick * 1.7), (side * .14, -.64, z + kick * 1.8), .045, .045,
                   HIDE_BLACK, n=8)
    m.link([(0., .12, .70), (0., .02, .56), (0., -.14, .52)], (.022, .018, .030), HIDE_BLACK)
    return m


def cut_out(image, size, canvas_size=None):
    """Trim a side render to its subject and fit it to a world-sprite size."""
    image = image.crop(image.getchannel("A").point(lambda a: 255 if a > 112 else 0).getbbox())
    image.thumbnail(size, Image.Resampling.LANCZOS)
    rgba = np.array(image)
    rgba[..., 3] = np.where(rgba[..., 3] >= 112, 255, 0)
    image = Image.fromarray(rgba)
    out = Image.new("RGBA", canvas_size or image.size)
    out.alpha_composite(image, ((out.width - image.width) // 2, out.height - image.height
                                if canvas_size else 0))
    return out


def make_world_sprites():
    """Pickups and projectiles from the same meshes, seen from the side."""
    side = Camera(side=True, yaw=.12)
    ball = render(bowling("pickup")[0], side)
    barrel = render(keg("pickup")[0], side)
    launcher = render(cow("pickup")[0], side)
    milker = render(teat("pickup")[0], side)
    flying = render(whole_cow(), side)
    for name, image, size in (("bowling_ball", ball, (30, 30)), ("bowling_ammo", ball, (26, 26)),
                              ("powder_keg", barrel, (30, 38)), ("keg_ammo", barrel, (26, 32)),
                              ("cow_launcher", launcher, (46, 32)), ("cow_ammo", flying, (40, 28)),
                              ("teat_gun", milker, (46, 32))):
        cut_out(image, size, (48, 48)).save(ART / f"item_{name}.png")
    cut_out(ball, (24, 24)).save(ART / "fx_bowling.png")
    cut_out(barrel, (28, 30)).save(ART / "fx_keg.png")
    cut_out(flying, (40, 28)).save(ART / "fx_cow.png")


WEAPONS = (
    ("bowling_ball", bowling, BOWLING_VIEW),
    ("powder_keg", keg, KEG_VIEW),
    ("cow_launcher", cow, COW_VIEW),
    ("teat_gun", teat, TEAT_VIEW),
)
# How far each whole set is lifted into the 120-row cel.
RAISE = {"bowling_ball": .30, "powder_keg": .27, "cow_launcher": .13, "teat_gun": .12}


def digitize(image):
    """The plate look the scanned weapons have: tight edges, hard alpha, 120 rows."""
    cell = image.crop((0, 0, 320, 120))
    rgba = np.array(cell)
    rgba[:, :, :3] = np.asarray(cell.convert("RGB").filter(ImageFilter.UnsharpMask(.7, 106, 3)))
    rgba[..., 3] = np.where(rgba[..., 3] >= 112, 255, 0)
    return Image.fromarray(rgba)


def make_weapons(only=None, preview=False):
    anchor_file = ART / "weapon_anchors.json"
    anchors = json.loads(anchor_file.read_text(encoding="utf-8"))
    sheet = Image.new("RGB", (320 * len(POSES), 120 * len(WEAPONS)), (52, 70, 78))
    for row, (name, make, views) in enumerate(WEAPONS):
        if only and name not in only:
            continue
        anchors[name] = {}
        for column, pose in enumerate(POSES):
            mesh, muzzle = make(pose)
            view = dict(views[pose])
            view["y"] = view.get("y", 0.) + RAISE[name]
            camera = Camera(**view)
            image = digitize(render(mesh, camera))
            image.save(ART / f"gun_{name}_{pose}.png")
            sheet.paste(image, (column * 320, row * 120), image)
            if muzzle is not None:
                anchors[name][pose] = [round(float(n), 1) for n in camera.project(muzzle)[:2]]
        if not anchors[name]:
            del anchors[name]
    anchor_file.write_text(json.dumps(anchors, separators=(",", ":")), encoding="utf-8")
    if not only:
        make_world_sprites()
    if preview:
        out = ROOT / "_preview"
        out.mkdir(exist_ok=True)
        sheet.save(out / "rampage_weapons.png")
        strip = Image.new("RGB", (48 * 10, 48), (52, 70, 78))
        for i, name in enumerate(("item_bowling_ball", "item_bowling_ammo", "item_powder_keg",
                                  "item_keg_ammo", "item_cow_launcher", "item_cow_ammo",
                                  "item_teat_gun", "fx_bowling", "fx_keg", "fx_cow")):
            im = Image.open(ART / f"{name}.png")
            strip.paste(im, (i * 48, 0), im)
        strip.resize((strip.width * 4, strip.height * 4), Image.NEAREST).save(out / "rampage_items.png")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    make_weapons(only=args or None, preview="--preview" in sys.argv)
