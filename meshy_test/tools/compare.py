import sys
from PIL import Image, ImageDraw, ImageFont
S = sys.argv[1]
F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
f2 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
def panel(path, h, crop=None):
    im = Image.open(path).convert("RGB")
    if crop: im = im.crop(crop)
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
def build(name, items, h=560):
    ims = [panel(p, h, c) for p, _, _, c in items]
    W = sum(i.width for i in ims) + 12 * (len(ims) + 1)
    c = Image.new("RGB", (W, h + 100), (28, 26, 24))
    d = ImageDraw.Draw(c); x = 12
    for im, (_, t, sub, _) in zip(ims, items):
        c.paste(im, (x, 86)); d.text((x, 14), t, font=F, fill=(240, 228, 200)); d.text((x, 50), sub, font=f2, fill=(190, 180, 160)); x += im.width + 12
    c.save(f"{S}/pres/compare_{name}.png")
CROP = (107, 0, 1173, 625)
build("enemy", [
    (f"{S}/cmp/enemy_old_q.png", "Existing: Billy", "23,742 tris, 512² (Blender build)", None),
    (f"{S}/cmp/enemy_new_q.png", "Meshy, game-ready", "9,993 tris, 512² dusk bake + game grade", None),
    (f"{S}/tour3/2_enemy_close_fx.png", "In the game's own 3D view", "left: Billy actor, right: Meshy model", CROP)])
build("hog", [
    (f"{S}/cmp/hog_old_qr.png", "Existing: herd hog", "7,770 tris, 256²", None),
    (f"{S}/cmp/hog_new_qr.png", "Meshy mutant, game-ready", "5,996 tris (Meshy remesh), 512²", None),
    (f"{S}/tour3/4_hog_close_fx.png", "In the game's own 3D view", "centre: Meshy, right: existing hog", CROP)])
build("tractor", [
    (f"{S}/cmp/tractor_old_q.png", "Existing: tractor prop", "1,012 tris, 256²", None),
    (f"{S}/cmp/tractor_new_q.png", "Meshy, game-ready", "7,954 tris, 512²", None),
    (f"{S}/tour3/5_tractors_fx.png", "In the game's own 3D view (Grainyard)", "left: Meshy, right: existing", CROP)])
