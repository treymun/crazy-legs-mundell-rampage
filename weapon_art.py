"""Cut and grade original weapon plates into registered 320-pixel viewmodels."""
from pathlib import Path
import json
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from face_pipeline import digitize
from weapon_models import modeled_weapon

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source_art"
OUTPUT = ROOT / "assets" / "art"
SIZE = (320, 174)
VIEWMODEL_HEIGHT = 120
RESAMPLE = Image.Resampling.BICUBIC
SEED = np.random.default_rng(1917)


# The two photographed guns are laid out in the original 320x174 coordinates,
# built U times larger so the plate keeps its detail, then framed: FRAMING is
# (zoom, left, top) of the window of that layout the finished cel shows.
U = 3
FRAMING = {"shotgun": (1.75, 84.9, 67.5), "revolver": (1.70, 72.4, 57.4)}


def canvas(u=1):
    return Image.new("RGBA", (SIZE[0] * u, SIZE[1] * u))


def up(points, u=U):
    return [(x * u, y * u) for x, y in points]


def plate(name, position, size, flip=False, u=1):
    src = Image.open(SOURCE / f"{name}_plate.png").convert("RGBA")
    rgb = np.array(src)
    colors = rgb[..., :3].astype(np.float32)
    # Age the steel independently of the brown grips and the photographic hands.
    metal = (colors[...,0] - colors[...,2] < 14) & (rgb[...,3] > 0)
    gray = colors[metal].mean(axis=1)
    finish = {"shotgun": [.85,.93,1.05], "revolver": [1.01,1.025,1.08],
              "crowbar": [.78,.93,1.17]}[name]
    colors[metal] = np.clip((colors[metal]*.70 + gray[:,None]*.30) * finish + [1,2,4], 0, 255)
    rgb[..., :3] = colors
    src = Image.fromarray(rgb)
    if flip:
        src = ImageOps.mirror(src)
    src = src.resize((size[0] * u, size[1] * u), Image.Resampling.LANCZOS)
    im = canvas(u)
    im.alpha_composite(src, (position[0] * u, position[1] * u))
    return im


def move(image, x, y):
    out = Image.new("RGBA", image.size)
    out.alpha_composite(image, (x, y))
    return out


def shifted(image, x, y, u=U):
    """move() for the enlarged layout; clips instead of failing off the edge."""
    out = Image.new("RGBA", image.size)
    out.paste(image, (x * u, y * u), image)
    return out


def layer_pair(image, polygon):
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    front, back = Image.new("RGBA", image.size), Image.new("RGBA", image.size)
    front.paste(image, (0, 0), mask)
    back.paste(image, (0, 0), mask.point(lambda x: 255 - x))
    return front, back


def shell(image, x, y, tilt=0, u=1):
    """Copper and red paper with an off-axis highlight and visible crimp."""
    im = Image.new("RGBA", (17 * u, 27 * u))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((4 * u, 3 * u, 12 * u, 22 * u), 2 * u, fill="#713b32", outline="#261d1a",
                        width=u)
    d.line((6 * u, 5 * u, 6 * u, 18 * u), fill="#bb6751", width=2 * u)
    d.line((9 * u, 4 * u, 9 * u, 18 * u), fill="#8e493b", width=u)
    d.ellipse((5 * u, 3 * u, 11 * u, 6 * u), fill="#95533f")
    d.rectangle((5 * u, 18 * u, 11 * u, 22 * u), fill="#a98649")
    d.line((6 * u, 19 * u, 6 * u, 22 * u), fill="#d0b26b", width=u)
    image.alpha_composite(im.rotate(tilt, RESAMPLE), ((x - 8) * u, (y - 13) * u))


def plate_detail(points, size, tilt=0, flip=False):
    source = Image.open(SOURCE / "revolver_plate.png").convert("RGBA")
    mask = Image.new("L", source.size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    source.putalpha(mask)
    source = source.crop(mask.getbbox()).resize(size, Image.Resampling.LANCZOS)
    if flip:
        source = ImageOps.mirror(source)
    return source.rotate(tilt, RESAMPLE, expand=True)


def loading_hand(tilt, u=1):
    return plate_detail(((228, 308), (250, 266), (287, 243), (342, 244), (365, 204),
                         (400, 187), (437, 201), (469, 239), (532, 300), (611, 361),
                         (599, 397), (550, 447), (402, 447), (350, 409), (333, 353),
                         (306, 323), (261, 337), (240, 341)), (34 * u, 24 * u), tilt, True)


def framed(name, frames):
    """Cut each enlarged layout down to the window FRAMING names."""
    zoom, left, top = FRAMING[name]
    box = (round(left * U), round(top * U), round((left + SIZE[0] / zoom) * U),
           round((top + SIZE[1] / zoom) * U))
    return {pose: image.crop(box).resize(SIZE, Image.Resampling.LANCZOS)
            for pose, image in frames.items()}


def shotgun():
    u = U
    closed = plate("shotgun", (155, 106), (101, 74), u=u).rotate(-12, RESAMPLE,
                                                                 center=(235 * u, 161 * u))
    hinge = (223 * u, 139 * u)
    barrels, stock = layer_pair(closed, up([(0, 0), (238, 0), (237, 127), (221, 146),
                                            (207, 157), (0, 173)]))
    pivot = (248 * u, 158 * u)
    frames = {"idle": closed,
              "kick": shifted(closed.rotate(-8, RESAMPLE, center=pivot), -4, -9),
              "recover": shifted(closed.rotate(-3, RESAMPLE, center=pivot), -1, -2)}
    for name, angle, count in (("open", 24, 0), ("eject", 36, 2), ("load", 39, 2),
                               ("eject_one", 36, 1), ("load_one", 39, 1), ("close", 14, 0)):
        rise = -18 if name == "open" else -15 if name == "close" else -29
        pose = shifted(stock, 10, rise)
        forward = shifted(barrels.rotate(angle, RESAMPLE, center=hinge), 10, rise)
        pose.alpha_composite(forward)
        d = ImageDraw.Draw(pose)
        offset = 29 + rise
        d.polygon(up([(224, 109 + offset), (232, 102 + offset), (243, 106 + offset),
                      (238, 116 + offset), (227, 118 + offset)]),
                  fill="#4e463b", outline="#292927", width=u)
        d.ellipse((227 * u, (106 + offset) * u, 232 * u, (110 + offset) * u), fill="#221e1c",
                  outline="#8f836d", width=u)
        d.ellipse((234 * u, (108 + offset) * u, 240 * u, (112 + offset) * u),
                  fill="#b39455" if count == 1 else "#221e1c", outline="#8f836d", width=u)
        if name.startswith("eject"):
            shell(pose, 215, 81, 40, u)
            if count == 2:
                shell(pose, 234, 89, -27, u)
        elif name.startswith("load"):
            pose.alpha_composite(loading_hand(-20, u), (232 * u, 103 * u))
            shell(pose, 227, 102, -44, u)
            if count == 2:
                shell(pose, 234, 106, -40, u)
        frames[name] = pose
    return framed("shotgun", frames)


def revolver():
    u = U
    idle = plate("revolver", (144, 101), (80, 65), u=u).rotate(-25, RESAMPLE,
                                                               center=(201 * u, 147 * u))
    barrel, grip = layer_pair(idle, up([(0, 0), (320, 0), (320, 125), (190, 117), (0, 117)]))
    pivot = (219 * u, 145 * u)
    kick = shifted(idle.rotate(-12, RESAMPLE, center=pivot), -2, -6)
    frames = {"idle": idle, "kick": kick,
              "recover": shifted(idle.rotate(-5, RESAMPLE, center=pivot), -1, -2)}
    cylinder = plate_detail(((161, 96), (175, 77), (216, 79), (243, 96), (267, 128),
                             (271, 159), (257, 182), (229, 189), (187, 177), (163, 154)),
                            (17 * u, 15 * u), -24)
    for name, angle in (("open", 15), ("eject", 20), ("load", 20), ("close", 8)):
        pose = shifted(grip, 9, -14)
        pose.alpha_composite(shifted(barrel.rotate(angle, RESAMPLE, center=(206 * u, 115 * u)),
                                     9, -14))
        d = ImageDraw.Draw(pose)
        pose.alpha_composite(cylinder, (209 * u, 84 * u))
        d.ellipse((210 * u, 88 * u, 220 * u, 99 * u), fill="#5d5c55", outline="#302d2b", width=u)
        for x, y in ((214, 91), (217, 93), (214, 96)):
            d.ellipse((x * u, y * u, (x + 1) * u, (y + 1) * u), fill="#1d1a17")
        if name == "eject":
            d.line((206 * u, 79 * u, 210 * u, 84 * u), fill="#ab8950", width=2 * u)
            d.line((200 * u, 76 * u, 199 * u, 81 * u), fill="#906d44", width=2 * u)
            d.ellipse((202 * u, 77 * u, 203 * u, 78 * u), fill="#c7ac6c")
        elif name == "load":
            pose.alpha_composite(loading_hand(28, u), (179 * u, 95 * u))
            d.line((205 * u, 101 * u, 211 * u, 96 * u), fill="#ab8950", width=2 * u)
            d.line((209 * u, 104 * u, 214 * u, 98 * u), fill="#9b7746", width=2 * u)
        frames[name] = pose
    return framed("revolver", frames)


def crowbar():
    idle = plate("crowbar", (77, 81), (164, 96), flip=True)
    grip = (142, 134)
    return {
        "idle": idle,
        "wind": move(idle.rotate(-23, RESAMPLE, center=grip), 31, -11),
        "strike": move(idle.rotate(30, RESAMPLE, center=grip), -48, -3),
        "follow": move(idle.rotate(46, RESAMPLE, center=grip), -44, 15),
        "recover": move(idle.rotate(19, RESAMPLE, center=grip), -16, 11),
    }


def effect(frame, smoke):
    """Low-resolution expanding sprite with a warm core and feathered smoke."""
    y, x = np.indices((80, 80))
    a = np.arctan2(y - 40, x - 40)
    r = np.hypot(y - 40, x - 40)
    radius = (14 + 5 * frame) if smoke else (15 + 4.2 * frame)
    texture = SEED.uniform(0., 1., (80, 80))
    lobes = (1 + .14 * np.sin(5 * a + frame) + .10 * np.sin(9 * a - frame))
    heat = np.clip(1 - r / (radius * lobes) + .17 * (texture - .5), 0, 1)
    rgba = np.zeros((80, 80, 4), dtype=np.uint8)
    if smoke:
        shade = (heat * .62 + texture * .38) * 57
        rgba[..., :3] = np.array([84, 78, 68]) + shade[..., None]
        rgba[..., 3] = np.clip((heat**.55) * (165 - 30 * frame), 0, 255)
    else:
        color = np.stack([128 + 127 * np.sqrt(heat), 50 + 204 * heat**.45, 16 + 219 * heat**.72], axis=-1)
        rgba[..., :3] = np.clip(color, 0, 255)
        rgba[..., 3] = np.where(heat > .035, np.minimum(1, heat * 7) * (255 - frame * 15), 0)
    return Image.fromarray(rgba)


def digitized_pose(image,name=None,pose="idle"):
    # The game grades the viewmodel with the scene before the final VGA lookup.
    cell = image.crop((0,0,SIZE[0],VIEWMODEL_HEIGHT))
    rgba = np.array(cell)
    if name in ("crossbow","rifle","ripsaw","armgun","slingblade","bottle_launcher","riveter","pressure_gun"):
        # Match the tight specular edges and material grain of the scanned plates.
        rgba[:,:,:3] = np.asarray(cell.convert("RGB").filter(ImageFilter.UnsharpMask(.7,106,3)))
    if name:
        from weapon_finish import finish_weapon
        finish_weapon(rgba,name,pose)
    rgba[..., 3] = np.where(rgba[..., 3] >= 112, 255, 0)
    return Image.fromarray(rgba)


def tnt_stick(spark=0):
    im = Image.new("RGBA",(26,61))
    d = ImageDraw.Draw(im)
    d.line((12,17,11,10,15,4,20,5), fill="#3e382b",width=2)
    d.rounded_rectangle((5,16,21,56),3,fill="#8b3b2e",outline="#422823")
    for x,color in ((6,"#6d3229"),(7,"#9a4b38"),(9,"#b66b50"),(11,"#bf7a58"),
                    (14,"#a94b3b"),(17,"#923c2e"),(20,"#592a26")):
        d.line((x,19,x,53),fill=color,width=2)
    d.ellipse((5,15,21,21), fill="#9b6047",outline="#552f27")
    d.line((8,17,14,16,16,18),fill="#c48256")
    d.rectangle((6,31,20,41), fill="#8e7952")
    d.line((7,32,18,32),fill="#c3a070")
    for y, c in ((35,"#594331"),(38,"#614332")):
        d.line((8,y,17,y),fill=c)
    d.rectangle((7,50,19,54),fill="#805341")
    if spark:
        shape = ((14,5),(18,3),(21,0),(21,3),(25,2),(22,5),(24,8),(20,7),(17,10))
        d.polygon(shape,fill="#d77c41" if spark == 1 else "#efac59")
        d.line((16,6,21,3,23,5), fill="#fff1b6",width=2)
        if spark == 2:
            d.point((24,1),fill="#fce796")
    return im


def handheld_tnt():
    poses = {}
    for pose, tilt, x, y, lit in (("idle",17,192,68,0),("lit",11,184,62,1),
                                  ("lit_alt",11,184,62,2),("throw",-54,172,72,0),("kick",-28,199,93,0),
                                  ("dry",12,202,96,0)):
        im = canvas()
        forearm = ImageDraw.Draw(im)
        forearm.polygon(((200,111),(223,102),(244,123),(259,145),(217,147)),
                        fill="#52463b",outline="#39342d")
        forearm.line((213,113,223,114,240,129), fill="#756254",width=3)
        if pose not in ("throw","kick","dry"):
            stick = tnt_stick(lit).rotate(tilt,RESAMPLE,expand=True)
            im.alpha_composite(stick,(x,y))
        hand = loading_hand(tilt+8).resize((44,32),Image.Resampling.LANCZOS)
        im.alpha_composite(hand,(x+3,y+26 if pose not in ("throw","kick","dry") else y+3))
        if pose == "throw":
            im=move(im,-4,-4)
        poses[pose]=im
    return poses


def muzzle_from_plate(image):
    px = np.array(image)[:, :, 3]
    yy, xx = np.where(px >= 112)
    # The angled muzzle is the foremost part of the plate, distinct from the grip.
    n = (yy <= yy.min() + 4) & (xx < np.median(xx))
    if not n.any():
        n = yy <= yy.min()+4
    return [round(float(np.median(xx[n])),1), round(float(np.median(yy[n])),1)]


def make_weapons():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    groups = {"crowbar": crowbar(), "revolver": revolver(), "shotgun": shotgun(),
              "tnt": handheld_tnt()}
    pickups = {}
    anchors = {name: {pose: muzzle_from_plate(im) for pose, im in groups[name].items()
                      if pose in ("idle","kick","recover")}
               for name in ("shotgun","revolver")}
    for name in ("crossbow","rifle","ripsaw","armgun"):
        groups[name], anchors[name], pickups[name] = modeled_weapon(name)
    for name, poses in groups.items():
        for pose, im in poses.items():
            digitized_pose(im,name,pose).save(OUTPUT / f"gun_{name}_{pose}.png")
        pickup = pickups.get(name, poses["idle"])
        pickup = pickup.crop(pickup.getchannel("A").point(lambda a: 255 if a > 112 else 0).getbbox())
        pickup.thumbnail((45, 34), Image.Resampling.LANCZOS)
        digitize(pickup, pickup.size).save(OUTPUT / f"item_{name}.png")
    (OUTPUT / "weapon_anchors.json").write_text(json.dumps(anchors, separators=(",",":")), encoding="utf-8")
    for j, rotation in enumerate((22,105,-64)):
        bolt = tnt_stick(1+j%2).rotate(rotation, RESAMPLE, expand=True)
        bolt.thumbnail((36,36),Image.Resampling.LANCZOS)
        digitize(bolt,bolt.size,border=False).save(OUTPUT / f"fx_tnt_{j}.png")
    for smoke in (False, True):
        for frame in range(4):
            effect(frame, smoke).save(OUTPUT / f"fx_{'smoke' if smoke else 'fire'}_{frame}.png")
    for frame in range(4):
        px = np.array(effect(frame, False))
        rgb = px[..., :3].copy()
        px[..., 0] = (rgb[..., 1].astype(float) * .72).astype(np.uint8)
        px[..., 1] = rgb[..., 0]
        px[..., 2] = (rgb[..., 2].astype(float) * .80).astype(np.uint8)
        Image.fromarray(px).save(OUTPUT / f"fx_energy_{frame}.png")
        flame = np.array(effect(frame,False))
        smoke = np.array(effect(frame,True))
        for name,tint,source in (("rocket",(1.0,.72,.53),flame),("forge",(1.0,.94,.72),flame),
                                 ("steam",(.82,.95,1.13),smoke)):
            grade = source.copy()
            grade[:,:,:3] = np.clip(grade[:,:,:3]*tint+(19 if name=="steam" else 0),0,255)
            if name=="forge":
                y,x=np.indices(grade.shape[:2])
                spokes=(np.abs(x-grade.shape[1]*.48)<3)|(np.abs(y-grade.shape[0]*.52)<3)
                grade[:,:,3]=np.where(spokes,grade[:,:,3],grade[:,:,3]*.65)
            Image.fromarray(grade).save(OUTPUT/f"fx_{name}_{frame}.png")
    Image.open(OUTPUT / "fx_energy_1.png").resize((24, 24), Image.Resampling.LANCZOS).save(OUTPUT / "fx_arm_bolt.png")


if __name__ == "__main__":
    make_weapons()

