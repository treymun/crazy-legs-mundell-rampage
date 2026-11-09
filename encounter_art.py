"""Hand-assembled enemy poses, projectiles and ammo boxes for the Hickston roster."""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw

from face_pipeline import digitize, font
from actor_models import baked_actor

ROOT = Path(__file__).resolve().parent
ART = ROOT / "assets" / "art"
SOURCE = ROOT / "source_art"


def textured(image, points, color, grain=.19, form=0.):
    """Lay photographed siding grain under a painted silhouette."""
    material = Image.open(SOURCE / "materials" / "weathered_plank_siding.png").convert("L")
    material = material.transpose(Image.Transpose.ROTATE_90).resize(image.size)
    values = np.asarray(material, dtype=float)
    y, x = np.indices(values.shape)
    shade = (values - np.median(values)) * grain + np.cos((x + y * .46) * .43) * 6
    if form:
        lo, hi = min(p[0] for p in points), max(p[0] for p in points)
        axis = (x - lo) / max(hi - lo, 1)
        shade += form * (np.exp(-((axis - .40) / .31) ** 2) - .67)
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    pixels = np.empty((image.height, image.width, 4), dtype=np.uint8)
    pixels[..., :3] = np.clip(np.array(color) + shade[..., None], 0, 255)
    pixels[..., 3] = np.asarray(mask)
    image.alpha_composite(Image.fromarray(pixels))


def football(size=(36, 23)):
    im = Image.new("RGBA", size)
    d = ImageDraw.Draw(im)
    w, h = size
    for i, color in enumerate(("#3c221c", "#63362a", "#925138", "#a66a4a", "#ba8260")):
        d.ellipse((1 + i, 2 + i, w - 2 - i, h - 2 - i), fill=color)
    d.line((w // 3, h // 2, w * 2 // 3, h // 2 - 1), fill="#d3b493", width=1)
    for i in range(w // 3 + 2, w * 2 // 3, 3):
        d.line((i, h // 2 - 2, i, h // 2 + 1), fill="#c8af8d")
    return im


def blade(size=34, phase=0):
    im = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(im)
    c = size / 2
    teeth = []
    for i in range(42):
        a = (i / 42 + phase * .014) * math.tau
        r = size * (.48 if i % 3 == 1 else .414)
        teeth.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(teeth, fill="#a5a29b", outline="#443c34")
    inset = size * .16
    d.ellipse((inset, inset, size - inset, size - inset), fill="#6c7478", outline="#393d3e")
    d.arc((inset + 2, inset + 2, size - inset - 2, size - inset - 2),
          180 + phase * 26, 335 + phase * 26, fill="#dad4ba", width=2)
    for r in (size * .24, size * .13):
        d.ellipse((c - r, c - r, c + r, c + r), outline="#4b4f51")
    d.ellipse((c - 2, c - 2, c + 2, c + 2), fill="#2a2928")
    return im


def skeeter(frame):
    im = Image.new("RGBA", (100, 76))
    d = ImageDraw.Draw(im)
    aiming = frame in ("aim", "fire")
    beat = frame if isinstance(frame,int) else -1 if aiming else 1
    for side in (-1, 1):
        root = 51+side*5,37
        x = 51+side*(29+beat*7)
        y = 5+(beat+1)*7+side*2
        d.polygon((root,(51+side*14,y+9),(x-side*5,y+1),(x+side*5,y),
                   (x+side*6,y+5),(x+side*4,y+12),(51+side*18,y+23)), 
                  fill=(159,158,138,208),outline=(201,194,173,220))
        d.line((root,(51+side*18,y+18),(x+side*3,y+4)),fill="#625e57",width=2)
        d.line(((51+side*15,y+21),(51+side*14,y+14),(x-side*3,y+5)),fill="#9c9381")
        d.line(((51+side*20,y+16),(x+side*2,y+10),(x+side*4,y+6)),fill="#ded1af")
        for n in range(3):
            knee=(51+side*(16+n*5),42+n*5)
            foot=(51+side*(9+n*7),61+n*5)
            d.line((51+side*3,38+n*4,*knee,*foot),fill="#332a23",width=2)
            d.line((51+side*5,38+n*4,*knee),fill="#887f4b")
    d.polygon([(45,38),(56,36),(58,48),(55,58),(50,69),(46,57),(43,48)],
              fill="#575634",outline="#28291c")
    for y,span in ((45,6),(50,5),(55,4),(60,3)):
        d.arc((51-span,y-3,51+span,y+1),0,180,fill="#a6a157",width=2)
    d.ellipse((42,28,61,43),fill="#72663a",outline="#453d27")
    d.ellipse((41,28,49,37),fill="#a99c4e",outline="#544733")
    d.ellipse((54,28,62,37),fill="#ad9955",outline="#544733")
    d.point((45,30),fill="#e8c981")
    d.point((57,30),fill="#e0bf78")
    tip = (57,74) if aiming else (47,66)
    d.line((52,36,51,55,*tip),fill="#ba6845" if aiming else "#94724c",width=2)
    if aiming:
        d.line((52,46,52,58,*tip),fill="#dca374")
        d.point((45,30),fill="#fae098")
        d.point((57,30),fill="#fae098")
    return im


def jerry(frame):
    im = Image.new("RGBA", (140, 174))
    shift = frame if isinstance(frame,int) else 0
    textured(im, [(51, 106), (76, 111), (69, 139), (64 + shift * 3, 161),
                  (44 + shift * 3, 161), (45, 136)], (56, 61, 77), .39)
    textured(im, [(73, 108), (96, 109), (101, 136), (107 - shift * 3, 159),
                  (87 - shift * 3, 163), (78, 139)], (64, 70, 87), .39)
    d = ImageDraw.Draw(im)
    d.polygon([(44, 157), (62, 157), (68, 167), (62, 172), (35, 172), (32, 166)],
              fill="#35343a", outline="#202025")
    d.polygon([(88, 156), (105, 155), (114, 165), (110, 171), (85, 172), (83, 166)],
              fill="#36363d", outline="#202025")
    upper = Image.open(SOURCE / "jerry_sideline.png").convert("RGBA").resize((102, 121), Image.Resampling.LANCZOS)
    if frame in ("aim", "fire", "pain"):
        rotation = {"aim": -8, "fire": 10, "pain": 13}[frame]
        upper = upper.rotate(rotation, Image.Resampling.BICUBIC, center=(50,89))
    im.alpha_composite(upper, (20+shift*2, 1))
    d = ImageDraw.Draw(im)
    # Brass play-call box and an improvised belt rig.
    d.polygon([(58, 105), (101, 106), (103, 112), (97, 117), (57, 115)],
              fill="#343539", outline="#1c2226")
    d.rounded_rectangle((73, 104, 91, 115), 2, fill="#8c7757", outline="#4f4540")
    d.line((76, 106, 87, 106), fill="#bda175")
    d.rectangle((94, 107, 98, 110), fill="#aa7446")
    d.polygon([(92, 53), (112, 55), (118, 63), (114, 73), (104, 73), (95, 63)],
              fill="#646d73", outline="#303842")
    d.line((95, 55, 112, 60), fill="#9da6a4", width=2)
    d.rounded_rectangle((43,101,60,116),2,fill="#4f4c45",outline="#2e302c")
    for x in (47,51,55):
        d.line((x,103,x,110),fill="#aa8964")
    d.line((47,67,53,83,49,105),fill="#655a4b",width=3)
    if frame == "aim":
        ball = football((37, 23)).rotate(24, Image.Resampling.BICUBIC, expand=True)
        im.alpha_composite(ball, (17, 32))
        d.line((54, 55, 61, 65, 76, 67), fill="#b2976b", width=2)
    elif frame == "fire":
        d.polygon(((47,51),(30,50),(18,63),(21,71),(42,69),(55,60)),
                  fill="#4e515c",outline="#2e3138")
        d.polygon(((20,63),(10,63),(6,70),(14,74),(23,69)),
                  fill="#bd9873",outline="#614d42")
        d.line((12,69,20,66,30,61,43,57),fill="#a7a5a0")
    return im


def ammo(kind):
    im = Image.new("RGBA", (64, 48))
    d = ImageDraw.Draw(im)
    if kind == "saw_ammo":
        im.alpha_composite(blade(38).resize((42, 34), Image.Resampling.BICUBIC), (11, 9))
    elif kind == "arm_ammo":
        for x in (15, 28, 41):
            d.rounded_rectangle((x, 8, x + 10, 38), 3, fill="#637648", outline="#273b29", width=2)
            d.line((x + 3, 13, x + 3, 32), fill="#b5bb61", width=2)
            d.rectangle((x + 1, 8, x + 8, 13), fill="#796c48")
            d.rectangle((x + 1, 33, x + 8, 38), fill="#796c48")
    else:
        d.polygon([(5, 16), (48, 13), (59, 21), (56, 39), (8, 42)], fill="#817044", outline="#37321f")
        d.polygon([(6, 17), (48, 15), (56, 21), (13, 25)], fill="#a18a50")
        d.text((13, 25), "RIFLE", font=font(13, True), fill="#2c2318")
    return im


def make_encounters():
    from actor_finish import finish
    from actor_models import actor_bounds, humanoid, turn_cels

    def save(image, name):
        digitize(image,image.size,border=False).save(ART/f"{name}.png")

    hand = {"skeeter": skeeter, "jerry": jerry}
    for name in ("clone","billy","coot","alien","skeeter","saucer","boss","jerry"):
        compose = hand.get(name)
        for frame in (-1, 0, 1, "aim", "fire", "pain"):
            sprite = compose(frame) if compose else baked_actor(name, frame)
            sprite = finish(sprite,name,frame)
            save(sprite,f"{name}_{frame}")
        if name not in ("skeeter","saucer"):
            pose = compose(0).rotate(-78, expand=True) if compose else baked_actor(name, "down")
            pose = pose.crop(pose.getchannel("A").getbbox()) if compose else pose
            digitize(pose, (76, 24), border=False).save(ART / f"{name}_down.png")
        if name in ("clone","billy","coot","alien","boss"):
            turn_cels(name,humanoid,actor_bounds(name),save)
        if name in ("clone","billy","coot"):
            save(finish(baked_actor(name,"fidget"),name,"fidget"),f"{name}_fidget")
    for frame in range(3):
        blade(35, frame).resize((48 - frame * 5, 24 + frame * 3)).save(ART / f"fx_blade_{frame}.png")
    football().save(ART / "fx_football.png")
    for name in ("rifle_ammo", "saw_ammo", "arm_ammo"):
        digitize(ammo(name), (48, 36), border=False).save(ART / f"item_{name}.png")

