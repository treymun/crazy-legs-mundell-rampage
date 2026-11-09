"""Generate reusable 1990s-style material tiles, props and first-person art."""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from face_pipeline import digitize, font
from encounter_art import make_encounters
from period_palette import generate_lookup
from weapon_art import make_weapons

ROOT = Path(__file__).resolve().parent / "assets"
SOURCE = ROOT.parent / "source_art"
N = 128
Y, X = np.indices((N, N))
rng = np.random.default_rng(1997)


def grain():
    field = np.zeros((N, N))
    for size, strength in ((4, 15), (9, 9), (23, 8), (57, 5), (128, 4)):
        noise = Image.fromarray(rng.integers(0, 256, (size, size), dtype=np.uint8))
        field += (np.asarray(noise.resize((N, N), Image.Resampling.BICUBIC)) / 127.5 - 1) * strength
    return field


def material(color, shade):
    values = np.clip(np.array(color) + shade[..., None] * [1, .89, .74], 0, 255).astype(np.uint8)
    return Image.fromarray(values).convert("RGBA")


def scan(name, color, contrast=1., saturation=.40, turn=False, crop=None):
    photo = Image.open(SOURCE / "materials" / f"{name}.png").convert("RGB")
    if crop:
        photo = photo.crop(crop)
    if turn:
        photo = photo.transpose(Image.Transpose.ROTATE_90)
    photo = photo.resize((N, N), Image.Resampling.LANCZOS)
    rgb = np.asarray(photo.filter(ImageFilter.UnsharpMask(.7, 78, 2)), dtype=np.float32)
    luma = rgb @ [.299, .587, .114]
    detail = (luma - np.median(luma)) * contrast
    chroma = rgb - luma[..., None]
    chroma -= np.median(chroma, axis=(0, 1))
    values = np.clip(np.array(color) + detail[..., None] + chroma * saturation, 0, 255)
    return Image.fromarray(values.astype(np.uint8)).convert("RGBA")


def sign_mask(size, word, box):
    """Fill the lettering area using true cap height, without font baseline padding."""
    x,y,w,h=box
    f=font(64,True)
    left,top,right,bottom=f.getbbox(word)
    mask=Image.new("L",(right-left,bottom-top))
    ImageDraw.Draw(mask).text((-left,-top),word,font=f,fill=255)
    mask=mask.crop(mask.getbbox())
    width=min(w,round(mask.width*h/mask.height*1.12))
    width=max(1,width)
    dest=Image.new("L",size)
    dest.paste(mask.resize((width,h),Image.Resampling.LANCZOS),(x+(w-width)//2,y))
    return dest


def paint_sign(im, word, box, color, edge="#211911"):
    mask=sign_mask(im.size,word,box)
    im.paste(edge,(0,0),mask.filter(ImageFilter.MaxFilter(3)))
    im.paste(color,(0,0),mask)


def stamp(im, word, line, neon=False):
    if neon:
        return neon_sign(im, word, line)
    d = ImageDraw.Draw(im)
    d.rectangle((3, 28, 124, 101), fill="#2b2320", outline="#b79461", width=2)
    d.rectangle((7, 32, 120, 97), outline="#74513c")
    for x in (10, 117):
        for y in (35, 94):
            d.ellipse((x - 1, y - 1, x + 1, y + 1), fill="#b39b78")
    paint_sign(im,word,(11,40,106,28),"#fae5b7","#150f0d")
    paint_sign(im,line,(14,77,100,13),"#e6bd84")
    return im


def wanted_tile(wood=None):
    if wood is None:
        wood = scan("weathered_plank_siding",(119,107,90),1.40,.53,turn=True)
    tile = wood.copy()
    with Image.open(ROOT/"art"/"wanted_poster.png") as poster:
        tile.alpha_composite(poster.resize((87,109),Image.Resampling.LANCZOS),(20,9))
    return tile


def neon_sign(im, word, line):
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((6, 35, 121, 92), radius=7, fill="#2a2021", outline="#514248", width=2)
    halo = Image.new("RGBA", im.size)
    light = ImageDraw.Draw(halo)
    hue = "#dc5039" if word == "LIQUOR" else "#47b6a7"
    hot = "#fff0c6" if word == "LIQUOR" else "#e4fff2"
    light.rounded_rectangle((11, 40, 116, 87), 6, outline=hue, width=2)
    name=sign_mask(im.size,word,(15,43,98,28))
    halo.paste(hue,(0,0),name.filter(ImageFilter.MaxFilter(5)))
    im.alpha_composite(halo.filter(ImageFilter.GaussianBlur(4.1)))
    im.alpha_composite(halo)
    im.paste(hot,(0,0),name)
    paint_sign(im,line,(18,76,92,9),"#f7bc94" if word=="LIQUOR" else "#b9e1d0","#302025")
    return im


def materials():
    tiles = {}
    wood = scan("weathered_plank_siding", (119, 107, 90), 1.40, .53, turn=True)
    tiles["wood"] = wood
    tiles["barn"] = scan("weathered_plank_siding", (123, 64, 45), 1.57, .45, turn=True)
    wave = np.sin(X * 2 * np.pi / 16)
    rust = grain()
    steel = scan("corrugated_iron", (100, 91, 78), 1.22, .33)
    metal = np.asarray(steel.convert("RGB"), dtype=np.float32)
    oxide = np.maximum(0, rust - 5)
    metal += (18 * wave - oxide * 1.1)[..., None] + oxide[..., None] * [1.1, .1, -.22]
    tiles["tin"] = Image.fromarray(np.clip(metal, 0, 255).astype(np.uint8)).convert("RGBA")
    stripes = 8 * np.sin(Y * .84) + rust * .33
    hud = np.asarray(tiles["tin"].transpose(Image.Transpose.ROTATE_90).convert("RGB"), dtype=float)
    tiles["hud"] = Image.fromarray(np.clip(hud * [.90, .78, .65] + stripes[..., None], 0, 255).astype("uint8"))
    brickx = (X + (Y // 16 % 2) * 16) % 32
    bricky = Y % 16
    grout = (brickx < 2) | (bricky < 2)
    tiles["brick"] = scan("red_bricks_04", (139, 84, 58), .92, .88, crop=(69, 58, 277, 266))
    tiles["plaster"] = scan("worn_concrete_floor", (139, 128, 106), .59, .31)
    glaze = np.asarray(scan("worn_concrete_floor", (151, 143, 124), .32).convert("L"), dtype=float)
    tiles["tile"] = material((157, 150, 134), glaze - np.mean(glaze)
                             - 38 * ((X % 32 == 0) | (Y % 32 == 0))
                             + 13 * ((X % 32 == 1) | (Y % 32 == 1)) - 22 * (Y > 94))
    tiles["mirror"] = tiles["tile"].copy()
    md = ImageDraw.Draw(tiles["mirror"])
    md.rectangle((8, 12, 119, 112), fill="#514a3e", outline="#362b27", width=3)
    md.rectangle((11, 15, 116, 109), outline="#a39776", width=2)
    tiles["floor_tile"] = scan("old_linoleum_flooring_01", (120, 105, 78), .76, .6,
                               crop=(18, 22, 220, 224))
    tiles["concrete"] = scan("worn_concrete_floor", (108, 100, 88), .65, .40)
    tiles["dirt"] = scan("brown_mud_03", (114, 89, 60), 1.11, .63)
    tires = ((X > 25 + Y * .015) & (X < 43)) | ((X > 84) & (X < 103 + Y * .02))
    mud = np.asarray(tiles["dirt"].convert("RGB"), dtype=float)
    tracks = mud + (tires * (-14 + 8 * (Y % 11 < 3)))[..., None]
    tiles["tracks"] = Image.fromarray(np.clip(tracks, 0, 255).astype("uint8")).convert("RGBA")
    tiles["grass"] = scan("forest_ground_04", (91, 91, 57), 1.25, .46)
    tiles["asphalt"] = scan("asphalt_02", (84, 83, 80), .94, .32)
    tiles["road"] = tiles["asphalt"].copy()
    d = ImageDraw.Draw(tiles["road"])
    for yy in range(61, 66):
        for xx in range(4, 100):
            if rng.uniform() > .08:
                d.point((xx, yy), fill=(int(rng.integers(111, 181)), 100, 56))
    tiles["door"] = tiles["wood"].copy()
    d = ImageDraw.Draw(tiles["door"])
    d.rectangle((1, 1, 126, 126), outline="#493829", width=4)
    d.rectangle((11, 12, 116, 111), outline="#675440", width=3)
    d.rectangle((94, 60, 108, 65), fill="#333030")
    d.line((93, 60, 106, 60), fill="#b6a078", width=2)
    tiles["gate"] = tiles["tin"].copy()
    d = ImageDraw.Draw(tiles["gate"])
    for yy in (25, 100):
        d.rectangle((0, yy, 127, yy + 10), fill="#60452d")
        d.line((0, yy + 1, 127, yy + 1), fill="#947350", width=2)
    d.rectangle((40, 53, 87, 77), fill="#372923", outline="#a48d60", width=2)
    paint_sign(tiles["gate"],"LOCK",(45,61,38,10),"#efc579","#312016")
    tiles["liquor"] = stamp(tiles["brick"].copy(), "LIQUOR", "COLD BEER", True)
    tiles["eat"] = stamp(tiles["plaster"].copy(), "EAT", "STANKY'S", True)
    tiles["restroom"] = stamp(tiles["tile"].copy(), "GENTS", "WASH UP", False)
    tiles["barnsign"] = stamp(tiles["barn"].copy(), "HICKSTON", "FEED & SEED")
    tiles["warning"] = stamp(tiles["gate"].copy(), "KEEP OUT", "COUNTY PROPERTY")
    tiles["wanted"] = wanted_tile(wood)
    tiles["crack"] = wood.copy()
    d = ImageDraw.Draw(tiles["crack"])
    d.line([(87, 10), (70, 32), (77, 50), (57, 62), (60, 76), (45, 100)], fill="#43342a", width=3)
    tiles["ship"] = material((82, 91, 79), grain() + 14 * np.cos(X * np.pi / 16) - 23 * (Y % 40 < 4))
    d = ImageDraw.Draw(tiles["ship"])
    d.rectangle((7, 19, 120, 27), fill="#382f24")
    for xx in range(11, 119, 12):
        d.rectangle((xx, 22, xx + 5, 24), fill="#a9bd75")
    tiles["ceiling"] = scan("worn_concrete_floor", (106, 100, 89), .44, .22)
    tiles["joists"] = scan("weathered_plank_siding", (100, 80, 59), 1.35)
    d = ImageDraw.Draw(tiles["joists"])
    for yy in (8, 68):
        d.line((0, yy, 127, yy), fill="#382d25", width=4)
    tiles["fascia"] = scan("corrugated_iron", (110, 91, 73), 1.22, .38)
    tiles["cinder"] = material((119, 113, 98), glaze - np.mean(glaze) - 34 * grout)
    tiles["porch"] = scan("weathered_plank_siding", (106, 97, 80), 1.44, .52)
    tiles["counter_top"] = scan("weathered_plank_siding", (95, 64, 47), 1.18, .51)
    tiles["counter"] = scan("weathered_plank_siding", (118, 81, 53), 1.21, .51, turn=True)
    d = ImageDraw.Draw(tiles["counter"])
    for yy, color, width in ((4, "#b69268", 4), (14, "#583e2d", 4), (110, "#583e2d", 4)):
        d.line((0, yy, 127, yy), fill=color, width=width)
    tiles["crate_side"] = scan("weathered_plank_siding", (132, 104, 68), 1.24, .42, turn=True)
    d = ImageDraw.Draw(tiles["crate_side"])
    d.rectangle((4, 4, 123, 123), outline="#765c42", width=9)
    d.line((9, 111, 114, 11), fill="#896944", width=12)
    d.line((10, 108, 113, 9), fill="#a6875c", width=3)
    tiles["steel_mesh"] = tiles["tin"].copy()
    d = ImageDraw.Draw(tiles["steel_mesh"])
    for yy in (2, 117):
        d.rectangle((0, yy, 127, yy + 8), fill="#53483d")
        d.line((0, yy + 2, 127, yy + 2), fill="#877b63")
    tiles["tavern"] = stamp(wood.copy(), "STANKY'S", "BAR & GRILL")
    tiles["shelves"] = wood.copy()
    d = ImageDraw.Draw(tiles["shelves"])
    for y in (34, 63, 91):
        d.rectangle((7, y - 24, 120, y), fill="#36281d")
        d.rectangle((5, y, 123, y + 4), fill="#79583a")
        d.line((5, y, 123, y), fill="#ad8760")
        for x in range(11, 111, 11):
            h = int(rng.integers(9, 22))
            color = ("#79664a", "#625f3b", "#735744", "#7e3b32")[(x + y) % 4]
            d.rounded_rectangle((x, y - h + 4, x + 6, y - 1), 2, fill=color)
            d.rectangle((x + 2, y - h, x + 4, y - h + 5), fill=color)
            d.line((x + 1, y - 8, x + 5, y - 8), fill="#b39b6d", width=2)
    tiles["window"] = tiles["brick"].copy()
    d = ImageDraw.Draw(tiles["window"])
    d.rectangle((12, 34, 116, 93), fill="#3e352d", outline="#4d473c", width=4)
    d.rectangle((16, 38, 112, 88), fill="#96764e", outline="#bc985d")
    for x in range(17, 111, 3):
        d.line((x, 39, x, 87), fill=(int(rng.integers(142, 196)), 104, 58))
    d.line((63, 37, 63, 90), fill="#4d3f2e", width=4)
    d.line((15, 67, 114, 67), fill="#564735", width=4)
    d.line((11, 93, 116, 93), fill="#856c4e", width=2)
    tiles["gravel"] = scan("asphalt_02", (119, 111, 94), 1.40, .42)
    tiles["shoulder"] = scan("brown_mud_03", (104, 85, 59), 1.26, .50)
    tiles["orchard"] = scan("forest_ground_04", (78, 86, 49), 1.30, .54)
    hedge = np.array(scan("forest_ground_04",(63,78,57),1.65,.45))
    barks = (5*np.sin(X*.35+Y*.014)+11*np.sin(X*.15+Y*.031)**7)*np.clip((Y-53)/75,0.,1.)
    undergrowth = (1-.36*np.clip((Y-62)/70,0.,1.))
    hedge[...,:3] = np.clip(hedge[...,:3]*undergrowth[...,None]+barks[...,None]*[.94,.71,.47],0,255)
    tiles["hedgerow"] = Image.fromarray(hedge)
    tiles["creek"] = scan("brown_mud_03", (71, 92, 85), 1.05, .22, turn=True)
    d = ImageDraw.Draw(tiles["creek"])
    for i in range(44):
        x, y = (int(v) for v in rng.integers(1, 115, 2))
        d.line((x, y, min(127, x + int(rng.integers(4, 20))), y),
               fill=("#879c86", "#425c5c", "#596e6a")[i % 3])
    tiles["office_wall"] = scan("weathered_plank_siding", (129, 112, 85), 1.12, .33)
    tiles["stockyard"] = scan("weathered_plank_siding", (102, 88, 70), 1.50, .46, turn=True)
    d = ImageDraw.Draw(tiles["stockyard"])
    for y in (22, 58, 101):
        d.rectangle((0, y, 127, y + 10), fill="#453d33")
        d.line((0, y - 1, 127, y - 1), fill="#a18a69", width=2)
    for x in (1, 120):
        d.rectangle((x, 0, x + 6, 127), fill="#70614d")
        for y in (16, 53, 96):
            d.point((x + 3, y), fill="#c0af8d")
    tiles["bleachers"] = scan("corrugated_iron", (117, 113, 102), 1.16, .22, turn=True)
    d = ImageDraw.Draw(tiles["bleachers"])
    for y in (8, 68, 119):
        d.line((0, y, 127, y), fill="#514d43", width=4)
    tiles["trailer"] = scan("corrugated_iron", (139, 135, 110), .92, .26, turn=True)
    d = ImageDraw.Draw(tiles["trailer"])
    d.rectangle((0, 88, 127, 96), fill="#667463")
    d.line((0, 99, 127, 99), fill="#445b55", width=2)
    d.rectangle((0, 112, 127, 127), fill="#675b4d")
    tiles["trailer_window"] = tiles["trailer"].copy()
    d = ImageDraw.Draw(tiles["trailer_window"])
    d.rectangle((10, 29, 118, 72), fill="#494740", outline="#bbb18e", width=3)
    for y in range(35, 69, 4):
        d.line((15, y, 113, y), fill="#88866e")
    d.line((64, 32, 64, 70), fill="#6e6150", width=3)
    tiles["service"] = stamp(tiles["tin"].copy(), "SERVICE", "PARTS & TIRES")
    tiles["dispatch"] = stamp(tiles["office_wall"].copy(), "DELIVERIES", "BACK OFFICE")
    tiles["feed"] = stamp(tiles["barn"].copy(), "FEED SCALE", "KEEP GATE SHUT")
    tiles["powder_panel"] = stamp(tiles["tin"].copy(), "POWDER", "KEEP CLEAR")
    d = ImageDraw.Draw(tiles["powder_panel"])
    for radius, color in ((23,"#50352e"),(18,"#b27b61"),(13,"#7c4535"),(7,"#caa074"),(3,"#4f3530")):
        d.ellipse((64-radius,96-radius,64+radius,96+radius),fill=color)
    tiles["glazing"] = scan("old_linoleum_flooring_01",(85,98,103),.38,.15)
    d = ImageDraw.Draw(tiles["glazing"])
    for a,b in ((18,5),(69,11),(95,21)):
        d.line((a,b,a-17,b+45),fill="#96a5a2",width=2)
        d.line((a+4,b+6,a-10,b+44),fill="#77888b")
    for pos in (0,62,122):
        d.rectangle((pos,0,pos+5,127),fill="#665745")
    for pos in (0,67,121):
        d.rectangle((0,pos,127,pos+6),fill="#725f49")
    for name,title,tag,base in (
        ("stanky_marquee","STANKY'S","GAS   -   BAR & GRILL",tiles["fascia"]),
        ("feed_marquee","HICKSTON FEED & SEED","CASH OR CREDIT",tiles["barn"]),
    ):
        sign = base.resize((304,55),Image.Resampling.LANCZOS)
        d = ImageDraw.Draw(sign)
        d.rectangle((0,0,303,54),outline="#a98a58",width=2)
        d.rectangle((7,5,297,50),fill="#302720",outline="#705739")
        paint_sign(sign,title,(16,8,272,28),"#f2dfb1","#15120f")
        paint_sign(sign,tag,(22,39,260,9),"#d6ab77")
        rgb = np.array(sign)
        yy,xx = np.indices(rgb.shape[:2])
        wear = np.asarray(base.resize(sign.size).convert("L")).astype(float)
        wear = np.clip((wear-np.median(wear))*.34,-17,18)
        rgb[..., :3] = np.clip(rgb[...,:3] + wear[...,None] -
                             (4*np.sin(xx*.19+yy*.1))[...,None],0,255)
        tiles[name] = Image.fromarray(rgb).resize((N,N),Image.Resampling.LANCZOS)
    tiles["cable"] = Image.new("RGBA",(N,N),"#27252a")
    oil = np.array(tiles["asphalt"])
    stains = (np.exp(-((X-53)/34)**2-((Y-70)/18)**2) +
              .55*np.exp(-((X-89)/21)**2-((Y-34)/24)**2))
    oil[...,:3] = np.clip(oil[...,:3]-stains[...,None]*[24,22,17],0,255)
    tiles["oil_asphalt"] = Image.fromarray(oil)
    folder = ROOT / "tiles"
    folder.mkdir(parents=True, exist_ok=True)
    for name, tile in tiles.items():
        tile.convert("RGB").save(folder / f"{name}.png")
    sky = dusk_sky()
    sky.save(folder / "sky.png")


def dusk_sky():
    width, height = 512, 116
    yy, xx = np.indices((height, width))
    dusk = np.exp(-((yy - 76) / 20)**2)
    cloud = np.zeros((height, width))
    for w, h, amplitude in ((10, 7, 23), (21, 15, 18), (45, 24, 10), (128, 70, 5)):
        layer = rng.integers(0, 255, (h, w), dtype=np.uint8)
        layer[:, -1] = layer[:, 0]
        octave = Image.fromarray(layer).resize((width, height), Image.Resampling.BICUBIC)
        cloud += (np.asarray(octave) / 127.5 - 1) * amplitude
    west = (.45+.55*(.5+.5*np.cos((xx-258)*math.tau/width))**2)
    base = np.stack((26+yy*.47+dusk*113*west,37+yy*.48+dusk*70*west,
                     66+yy*.41+dusk*31*west),axis=-1)
    billow = np.clip((cloud-3)*1.3,-56,36)
    grade = base + billow[..., None]*[.82,.95,1.12]
    grade += rng.normal(0, 1.8, (height, width))[..., None]
    skyline = 89 + 2*np.cos(xx*math.tau*7/width) + 4*np.sin(xx*math.tau*17/width)
    skyline += 1.7*np.sin(xx*math.tau*62/width)+rng.integers(-1,2,width)
    tree = yy > skyline
    grade[tree] = np.stack((28+cloud*.22,33+cloud*.24,30+cloud*.18),axis=-1)[tree]
    return Image.fromarray(np.clip(grade, 0, 255).astype(np.uint8))


def creek_tree(lean):
    im = Image.new("RGBA", (128, 154))
    bark = ImageDraw.Draw(im)
    bark.polygon(((58,153),(63,121),(64,94),(59,79),(48,65),(35,53),(42,51),
                  (61,67),(69,82),(76,69),(90,52),(96,52),(82,76),(76,94),
                  (73,123),(76,152),(71,151),(67,153)),fill="#665441")
    bark.line((64,149,68,126,67,98,63,85,49,68),fill="#9b8262",width=2)
    bark.line((71,148,70,124,73,108,72,87,84,71),fill="#3e342b",width=2)
    bark.line((70,82,71,63,66,48),fill="#755e45",width=3)
    bark.line((75,90,94,78,103,68),fill="#514031",width=3)
    for y,shift in ((104,0),(115,1),(132,-1),(145,-3)):
        bark.line((65+shift,y,68+shift,y-3),fill="#5b4939")
    leaves = Image.new("L", im.size)
    tones = Image.new("L", im.size, 100)
    brush,shade = ImageDraw.Draw(leaves),ImageDraw.Draw(tones)
    local = np.random.default_rng(673 if lean else 455)
    clusters = ((31,58,21,13,87),(91,56,23,14,92),(55,68,24,17,82),
                (77,61,24,19,88),(22,41,16,13,109),(41,34,22,15,123),
                (57,21,19,17,136),(81,32,23,14,120),(99,40,18,11,105),
                (57,45,23,17,111),(76,49,20,15,101))
    for cx,cy,w,h,value in clusters:
        if lean:
            cx += int((cy-53)*.29)
            cy += int((54-cx)*.12)
        points = []
        for angle in np.arange(20)*math.tau/20:
            span = local.uniform(.77,1.21)
            points.append((round(cx+w*span*math.cos(angle)),round(cy+h*span*math.sin(angle))))
        brush.polygon(points,fill=255)
        shade.polygon(points,fill=value)
        for x,y in points[::2]:
            radius = int(local.integers(2,5))
            bounds = (x-radius,y-radius,x+radius,y+radius-1)
            brush.ellipse(bounds,fill=255)
            shade.ellipse(bounds,fill=value+int(local.integers(-14,12)))
    sample = scan("forest_ground_04", (80, 89, 49), 1.04, .41).resize(im.size)
    rgba = np.array(sample)
    exposure = (np.array(tones,dtype=np.float32)-100)*.88
    rgba[...,:3] = np.clip(rgba[...,:3]+exposure[...,None]*[1.08,1.,.62],0,255)
    rgba[...,3] = np.array(leaves)
    im.alpha_composite(Image.fromarray(rgba))
    return ImageOps.mirror(im) if lean else im


def county_prop(name):
    if name == "water_tower":
        im = Image.new("RGBA",(122,171))
        d = ImageDraw.Draw(im)
        for a,b in ((35,15),(53,45),(77,90),(91,110)):
            d.line((a,67,b,170),fill="#5d5244",width=4)
            d.line((a-1,73,b-1,167),fill="#978263",width=1)
        for y,span in ((92,29),(123,37),(153,44)):
            d.line((61-span,y,61+span,y),fill="#5e5847",width=3)
            d.line((61-span,y,61+span+5,y+16),fill="#5f5345",width=2)
        d.ellipse((24,59,101,84),fill="#6b5f49",outline="#39352a",width=2)
        mask=Image.new("L",im.size)
        ImageDraw.Draw(mask).rounded_rectangle((24,22,101,73),6,fill=255)
        tin=scan("corrugated_iron",(126,114,89),1.32,.44).resize(im.size)
        tin.putalpha(mask)
        im.alpha_composite(tin)
        d.polygon(((18,26),(47,8),(63,3),(83,9),(108,25),(98,31),(24,31)),
                  fill="#776853",outline="#4e463b")
        d.line((24,23,62,7,91,19),fill="#b29c74",width=2)
        d.line((26,66,99,66),fill="#4d4a3d",width=2)
        paint_sign(im,"HICKSTON",(28,42,70,15),"#e4d1a5","#433a2b")
        return im
    if name.startswith("windmill"):
        im = Image.new("RGBA", (91, 142))
        d = ImageDraw.Draw(im)
        for x in (25, 64):
            d.line((45, 47, x, 141), fill="#6c6958", width=3)
            d.line((44, 51, x - 1, 141), fill="#a29679")
        for y in (69, 92, 120):
            r = round((y - 47) * .19)
            d.line((45-r, y, 45+r, y), fill="#827766", width=2)
            d.line((45-r, y, 50+r, y + 14), fill="#605c4e", width=2)
        d.line((44, 45, 71, 56), fill="#625748", width=3)
        d.polygon([(67, 51), (85, 53), (78, 64), (66, 57)], fill="#807968", outline="#51493e")
        frame = int(name[-1])
        for i in range(10):
            a = (i + frame / 3.) * math.tau / 10
            points = [(43 + r * math.cos(a + o), 42 + r * math.sin(a + o))
                      for r, o in ((15, -.06), (35, -.13), (39, .10), (17, .27))]
            d.polygon(points, fill="#b5ab90" if i in (5, 6, 7, 8) else "#857d6f", outline="#5c5549")
            d.line((43, 42, points[0][0], points[0][1]), fill="#716c62")
        d.ellipse((38, 37, 48, 47), fill="#68523f", outline="#b0a386")
        return im
    if name == "silo":
        im = Image.new("RGBA", (64, 151))
        d = ImageDraw.Draw(im)
        outline = [(5, 146), (5, 43), (9, 31), (19, 21), (31, 17),
                   (43, 21), (54, 32), (58, 45), (58, 146)]
        mask = Image.new("L", im.size)
        ImageDraw.Draw(mask).polygon(outline, fill=255)
        tin = np.array(scan("corrugated_iron", (128, 119, 99), .92, .32, turn=True).resize(im.size))
        y, x = np.indices(tin.shape[:2])
        shade = 28 * np.exp(-((x-25) / 19)**2) - .34 * x - 12 * (y < 43)
        tin[..., :3] = np.clip(tin[..., :3] + shade[..., None], 0, 255)
        tin[..., 3] = np.array(mask)
        im.alpha_composite(Image.fromarray(tin))
        d.line((5, 43, 17, 40, 43, 41, 58, 45), fill="#807563", width=2)
        d.line((43, 46, 43, 147), fill="#554d41", width=2)
        d.line((49, 47, 49, 147), fill="#51493e", width=2)
        for y in range(48, 145, 7):
            d.line((43, y, 49, y), fill="#98856a")
        d.rectangle((21, 11, 35, 20), fill="#8c7961", outline="#60523f")
        return im.crop((2, 8, 62, 147))
    if name == "reeds":
        im = Image.new("RGBA", (65, 52))
        d = ImageDraw.Draw(im)
        local = np.random.default_rng(73)
        for i in range(38):
            x = int(local.integers(8, 57))
            height = int(local.integers(14, 47))
            bend = int(local.integers(-7, 8))
            d.line((x, 50, x, 38, x + bend, 51-height), width=1 + (i % 3 == 0),
                   fill=("#3d4c35", "#686542", "#86744a", "#8c8250")[i % 4])
            if i % 4 == 1:
                d.ellipse((x+bend-1, 48-height, x+bend+1, 54-height), fill="#796044")
        return im
    if name in ("tree","tree_b"):
        return creek_tree(name=="tree_b")
    if name in ("pickup_truck","pickup_truck_b"):
        finish = "blue" if name=="pickup_truck_b" else "ochre"
        with Image.open(SOURCE / f"county_truck_{finish}.png") as source:
            truck = source.convert("RGBA")
        # Crop the opaque vehicle and resize uniformly. Both source wheels are level.
        bounds = truck.getchannel("A").point(lambda value: 255 if value>128 else 0).getbbox()
        truck = truck.crop(bounds)
        truck.thumbnail((196,100),Image.Resampling.LANCZOS)
        return truck
    im = Image.new("RGBA", (84, 128))
    d = ImageDraw.Draw(im)
    if name == "utilitypole":
        d.polygon([(38, 127), (40, 18), (45, 16), (47, 127)], fill="#76664c", outline="#443a2c")
        d.line((42, 24, 42, 125), fill="#9c8560", width=2)
        d.line((12, 21, 72, 21), fill="#514438", width=5)
        for x in (16, 30, 59, 69):
            d.rectangle((x, 16, x+3, 20), fill="#b8b1a1")
        return im.crop((7, 13, 78, 128))
    if name in ("roadsign", "bleacher_sign"):
        d.rectangle((40, 47, 45, 125), fill="#87775d", outline="#514435")
        d.rectangle((3, 18, 81, 54), fill="#5e6650" if name == "roadsign" else "#634f3f",
                    outline="#d0b787", width=2)
        for y,h,label in ((23,13,"HICKSTON"),(40,9,"COUNTY RD.")) if name=="roadsign" else (
                (23,13,"HOG BALL"),(40,9,"NO REFUNDS")):
            paint_sign(im,label,(8,y,69,h),"#fae7b8","#373427")
        return im.crop((2, 15, 82, 126))
    if name == "mailbox":
        d.rectangle((38, 55, 46, 124), fill="#927858", outline="#5e4c38")
        d.rounded_rectangle((13, 21, 71, 60), 13, fill="#79807a", outline="#454946", width=3)
        d.arc((11, 19, 41, 60), 90, 270, fill="#adb0a2", width=2)
        d.line((54, 49, 55, 24), fill="#a95740", width=4)
        d.rectangle((55, 22, 65, 30), fill="#ad6647")
        return im.crop((9, 19, 75, 126))
    d.ellipse((7, 68, 77, 121), fill="#403e36", outline="#242721", width=3)
    d.ellipse((15, 68, 69, 108), fill="#4e4e44", outline="#646254", width=2)
    d.ellipse((24, 78, 60, 100), fill=(0, 0, 0, 0))
    for x in range(16, 74, 7):
        d.line((x, 106, x - 3, 113), fill="#70675a")
    return im.crop((5, 65, 80, 122))


def item(name):
    im = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(im)
    if name in ("beer", "moonshine", "rinds"):
        if name == "beer":
            d.rounded_rectangle((20, 10, 45, 54), 5, fill="#b99c57", outline="#493823", width=2)
            d.ellipse((21, 8, 44, 16), fill="#d0c49e", outline="#76644d")
            d.rectangle((22, 21, 43, 43), fill="#a14638")
            paint_sign(im,"BEER",(22,27,22,8),"#fff0b9","#503a23")
        elif name == "moonshine":
            d.rounded_rectangle((16, 20, 48, 56), 7, fill="#a68b65", outline="#443325", width=2)
            d.rectangle((25, 11, 38, 24), fill="#896746")
            d.rectangle((24, 8, 39, 14), fill="#574331")
            d.arc((32, 14, 49, 32), 190, 345, fill="#c2a97a", width=3)
            paint_sign(im,"XXX",(21,34,22,9),"#35251d","#bd975f")
        else:
            d.polygon([(14, 12), (47, 11), (49, 54), (16, 53)], fill="#b4833e", outline="#593322", width=2)
            d.rectangle((16, 18, 47, 24), fill="#a84836")
            d.rectangle((17, 29, 47, 43), fill="#633e28")
            paint_sign(im,"RINDS",(17,31,29,9),"#ffe6ad","#44281d")
    elif name.startswith("key"):
        c = "#cfb568" if name.endswith("brass") else "#a7aeac"
        d.ellipse((12, 17, 33, 38), fill=c, outline="#56492d", width=2)
        d.ellipse((18, 23, 26, 31), fill=(0, 0, 0, 0))
        d.polygon([(28, 29), (53, 43), (51, 51), (46, 47), (44, 50), (38, 45), (39, 43), (24, 35)], fill=c)
    elif name in ("shells", "bullets", "dynamite"):
        c = "#bd4631" if name != "bullets" else "#a99057"
        for x in (16, 24, 32, 40):
            d.rounded_rectangle((x, 19 + x % 3 * 3, x + 8, 49), 2, fill=c, outline="#4b3122")
            d.line((x + 2, 26, x + 2, 46), fill="#e3a370")
            d.rectangle((x + 1, 44, x + 7, 49), fill="#a98c52")
    return im


def actor(name, frame=0):
    source = "pig" if name == "bessie" else name
    im = Image.open(SOURCE / f"{source}_plate.png").convert("RGBA")
    im.thumbnail((125, 145), Image.Resampling.LANCZOS)
    im = ImageOps.expand(im, border=(5, 2, 5, 2), fill=(0, 0, 0, 0))
    px = np.array(im)
    yy, xx = np.indices(px.shape[:2])
    leg = np.tanh((xx - im.width / 2) / 5) * frame
    leg = leg * np.clip((yy / im.height - .57) / .43, 0, 1)
    lean = frame * np.clip(1 - yy / im.height, 0, 1) * (2.7 if name == "chicken" else 1.1)
    sample_x = np.rint(xx - leg * 5 - lean).astype(int)
    sample_y = np.rint(yy + np.maximum(leg, 0) * 2).astype(int)
    px = px[np.clip(sample_y, 0, im.height - 1), np.clip(sample_x, 0, im.width - 1)]
    im = Image.fromarray(px)
    if name == "bessie":
        d = ImageDraw.Draw(im)
        x, y = int(im.width * .74), int(im.height * .56)
        d.line((x - 1, y - 9, x - 3, y, x - 1, y + 7), fill="#913d31", width=3)
        d.ellipse((x - 1, y + 2, x + 5, y + 7), fill="#c8a052", outline="#544031")
    return im


def photo_pump(name):
    photo = Image.open(SOURCE / "hardy_station.png").convert("RGBA")
    contour = ((84, 282), (87, 271), (99, 266), (122, 266), (128, 274), (132, 288),
               (133, 417), (82, 416), (83, 344)) if name == "pump" else (
                   (487, 276), (494, 264), (509, 260), (525, 263), (532, 272),
                   (535, 417), (486, 417), (484, 298))
    mask = Image.new("L", photo.size)
    ImageDraw.Draw(mask).polygon(contour, fill=255)
    photo.putalpha(mask)
    return photo.crop(mask.getbbox())


def prop(name):
    if name == "lamp":
        im = Image.new("RGBA", (96, 33))
        d = ImageDraw.Draw(im)
        d.polygon([(7, 11), (89, 11), (95, 17), (88, 26), (9, 26), (2, 17)],
                  fill="#41392c", outline="#231f1c", width=2)
        d.rounded_rectangle((7, 17, 90, 24), 3, fill="#dab989", outline="#a17c55")
        d.line((11, 20, 86, 20), fill="#fff0c1", width=2)
        return im
    if name in ("pump", "pump_b"):
        return photo_pump(name)
    im = Image.new("RGBA", (64, 96))
    d = ImageDraw.Draw(im)
    if name == "jukebox":
        d.rounded_rectangle((10, 6, 55, 93), 14, fill="#50392c", outline="#2c231c", width=3)
        d.rounded_rectangle((15, 11, 50, 69), 11, fill="#9a4533", outline="#bf8855", width=2)
        d.rounded_rectangle((20, 16, 45, 44), 5, fill="#634a35", outline="#d89a55", width=2)
        d.rectangle((23, 22, 42, 35), fill="#a99369")
        for x in range(23, 43, 4):
            d.line((x, 27, x + 1, 34), fill="#41382d")
        for y in range(54, 85, 3):
            d.line((18, y, 47, y), fill="#776657", width=1)
        d.line((17, 25, 16, 75), fill="#c77c4e", width=2)
        d.line((48, 25, 49, 75), fill="#c77c4e", width=2)
    elif name in ("hay", "crate"):
        color = "#a28b48" if name == "hay" else "#896748"
        d.polygon([(4, 36), (18, 19), (55, 25), (61, 39), (60, 86), (21, 94), (4, 78)],
                  fill=color, outline="#4f3d2a", width=2)
        for y in range(41, 84, 3 if name == "hay" else 13):
            d.line((5, y - 2, 21, y + 2, 60, y), fill="#675735", width=1)
        d.line((21, 34, 21, 91), fill="#695234", width=2)
        d.line((48, 36, 48, 87), fill="#665335", width=3)
    elif name == "sink":
        d.polygon([(7, 45), (15, 31), (55, 31), (60, 46), (55, 56), (16, 56)],
                  fill="#b0aa96", outline="#555048", width=2)
        d.ellipse((15, 37, 54, 50), fill="#66675d", outline="#d0c6aa", width=2)
        d.line((33, 38, 33, 25, 42, 25, 42, 32), fill="#807e72", width=4)
        d.polygon([(28, 55), (46, 55), (44, 92), (30, 92)], fill="#9b9581", outline="#635e52")
    else:
        d.rounded_rectangle((11, 18, 53, 94), 6, fill="#855b44", outline="#3f3229", width=2)
        d.ellipse((11, 12, 53, 28), fill="#a17b58", outline="#554434", width=2)
        d.ellipse((16, 15, 48, 24), fill="#765641")
        for y in (38, 69, 87):
            d.line((12, y, 26, y + 3, 41, y + 3, 53, y), fill="#493e35", width=3)
    arr = np.array(im)
    yy, xx = np.indices(arr.shape[:2])
    noise = np.cos(xx / 9) * 9 + rng.normal(0, 3, xx.shape)
    arr[:, :, :3] = np.clip(arr[:, :, :3] + noise[..., None], 0, 255)
    return Image.fromarray(arr)


def make_assets():
    from county_events_art import bake as bake_county_events

    generate_lookup()
    materials()
    folder = ROOT / "art"
    for name in ("rinds", "beer", "moonshine", "key_brass", "key_steel", "shells", "bullets", "dynamite"):
        digitize(item(name), (48, 48)).save(folder / f"item_{name}.png")
    for name in ("pig", "bessie", "chicken"):
        for frame in (-1, 0, 1):
            pose = actor(name, frame)
            digitize(pose, pose.size, border=False).save(folder / f"{name}_{frame}.png")
    for name in ("chicken", "pig"):
        pose = Image.open(folder / f"{name}_0.png").convert("RGBA").rotate(-78, expand=True)
        pose = pose.crop(pose.getchannel("A").getbbox())
        pose = pose.resize((76, 29), Image.Resampling.LANCZOS)
        px = np.array(pose)
        px[..., :3] = (px[..., :3] * [.70, .61, .55]).astype("uint8")
        Image.fromarray(px).save(folder / f"{name}_down.png")
    for name in ("pump", "pump_b", "hay", "barrel", "sink", "crate", "jukebox", "lamp"):
        image = prop(name)
        size = (29, 88) if name.startswith("pump") else (78, 26) if name == "lamp" else (58, 88)
        digitize(image, size, border=not name.startswith("pump")).save(folder / f"prop_{name}.png")
    fuel = prop("barrel")
    pixels = np.array(fuel)
    pixels[..., :3] = np.clip(pixels[..., :3] * [1.27, .62, .55], 0, 255)
    fuel = Image.fromarray(pixels)
    d = ImageDraw.Draw(fuel)
    x, y = fuel.width // 2, fuel.height // 2
    d.polygon([(x, y-8), (x+9, y), (x, y+8), (x-9, y)],
              fill="#bf9957", outline="#5a3929")
    d.line((x, y-4, x, y+2), fill="#58392c", width=2)
    d.point((x, y+4), fill="#58392c")
    digitize(fuel, (58, 88)).save(folder / "prop_fuel.png")
    for name in ("tree", "tree_b", "pickup_truck", "pickup_truck_b", "roadsign", "bleacher_sign", "utilitypole", "mailbox", "water_tower",
                 "tire", "silo", "reeds", "windmill_0", "windmill_1", "windmill_2"):
        image = county_prop(name)
        digitize(image, image.size, border=False).save(folder / f"prop_{name}.png")
    sy, sx = np.indices((9, 61))
    coverage = np.clip(1 - ((sx - 30) / 29)**2 - ((sy - 4) / 4)**2, 0, 1)
    shadow = np.zeros((9, 61, 4), dtype=np.uint8)
    shadow[..., 3] = (coverage * 145).astype("uint8")
    Image.fromarray(shadow).save(folder / "fx_shadow.png")
    for name,light,edge in (("wood","#a47e54","#6b4b35"),("stone","#a5947e","#6f6255"),
                            ("metal","#a0a59e","#5e6464")):
        hole=Image.new("RGBA",(19,19))
        d=ImageDraw.Draw(hole)
        d.polygon(((2,11),(4,7),(7,7),(9,2),(12,6),(16,6),(14,10),
                   (17,14),(12,14),(10,17),(6,13),(4,14)),fill=edge)
        d.line((4,9,8,8,10,4),fill=light)
        d.line((11,12,15,13),fill=light)
        d.ellipse((6,6,13,13),fill="#272522")
        d.ellipse((8,7,11,11),fill="#111417")
        hole.save(folder/f"fx_hole_{name}.png")
    for name, color in (("spark", "#e4b775"), ("plasma", "#afb675"), ("feather", "#e9dfbb"),
                        ("gore", "#a23b30"), ("dust", "#a78b66"), ("bolt", "#ac4534"),
                        ("glass", "#a0b5a8"), ("splash", "#739894")):
        im = Image.new("RGBA", (16, 16))
        d = ImageDraw.Draw(im)
        if name == "bolt":
            d.line((3, 12, 11, 4), fill="#4a3228", width=6)
            d.line((4, 11, 11, 4), fill=color, width=4)
            d.line((5, 10, 10, 5), fill="#c9855d")
            d.ellipse((10, 2, 13, 5), fill="#ffc87b")
        elif name == "feather":
            d.polygon([(2, 13), (5, 8), (6, 5), (10, 3), (14, 2), (12, 6),
                       (9, 9), (6, 10)], fill=color)
            d.line((2, 13, 12, 3), fill="#a3916c")
        elif name in ("glass","splash"):
            d.polygon(((2,14),(6,3),(13,1),(9,13)),fill=color)
            d.line((3,13,8,3),fill="#dfded0")
        else:
            d.polygon([(8, 1), (10, 6), (14, 7), (10, 10), (8, 15), (6, 10), (2, 8), (6, 6)], fill=color)
            d.ellipse((6, 6, 9, 9), fill="#fff1b5" if name in ("spark", "plasma") else color)
        im.save(folder / f"fx_{name}.png")
    screen_art(folder)
    status_art(folder)
    make_weapons()
    make_encounters()
    from expansion_art import make_art
    from expansion_enemies import make_enemies
    from expansion_weapons import make_weapons as make_expansion_weapons
    from route_art import paint as paint_routes
    from quarry_art import paint as paint_quarry
    from quarry_actors import bake as bake_quarry_actors
    from crossroads_art import make_crossroads
    from wing_art import make_wings
    from scenery_art import make_scenery
    from signature_art import bake as bake_signatures
    from county_detail_art import make_details
    make_art()
    make_enemies()
    make_expansion_weapons()
    paint_routes()
    paint_quarry()
    bake_quarry_actors()
    make_crossroads()
    make_wings()
    make_scenery()
    bake_signatures()
    make_details()
    bake_county_events()


def status_art(folder):
    """Layer scan-grain oak, recesses, cut steel, and stamped hardware."""
    width,height=320,44
    yy,xx=np.indices((height,width))
    oak=Image.open(SOURCE/"materials"/"weathered_plank_siding.png").convert("RGB")
    oak=ImageOps.fit(oak.transpose(Image.Transpose.ROTATE_90),(width,96),Image.Resampling.LANCZOS)
    oak=oak.crop((0,21,width,21+height)).filter(ImageFilter.UnsharpMask(.65,88,2))
    pixels=np.asarray(oak,dtype=float)
    luma=pixels @ [.30,.58,.12]
    random=np.random.default_rng(1947)
    detail=(luma-np.median(luma))*.79+random.normal(0,1.8,luma.shape)
    detail+=3.6*np.sin(yy*.64+np.sin(xx*.053)*.88)
    detail-=.14*np.maximum(0,abs(xx-160)-95)
    color=np.array([132,88,59])+detail[...,None]*[1.05,.84,.73]
    base=Image.fromarray(np.clip(color,0,255).astype("uint8")).convert("RGB")
    d=ImageDraw.Draw(base)
    for y in (9,26,41):
        d.line((0,y,319,y),fill="#533a2d")
        d.line((0,y+1,319,y+1),fill="#a3734e")
    d.line((0,43,319,43),fill="#392b25")

    # Black enamel ammo rail with hand-cut divisions and a scuffed rolled edge.
    d.rectangle((0,0,319,8),fill="#382d25")
    d.line((0,0,319,0),fill="#b68e63")
    d.rectangle((3,1,316,6),fill="#211b17")
    d.line((2,7,317,7),fill="#6c5140")
    for x in (4,48,93,138,183,228,273,315):
        d.line((x,2,x,6),fill="#514032")
        d.point((x+1,2),fill="#68523f")

    # The labels sit on torn tin tags above deep, bevel-cut instrument wells.
    def bay(x,w):
        d.polygon(((x,21),(x+w,21),(x+w,37),(x+w-3,40),(x+2,40),(x,38)),fill="#68452e")
        d.polygon(((x+1,19),(x+w-1,19),(x+w-1,37),(x+w-4,39),(x+3,39),(x+1,36)),fill="#301e17")
        d.rectangle((x+3,21,x+w-3,36),fill="#191512")
        d.line((x+3,21,x+w-4,21),fill="#130e0c")
        d.line((x+3,36,x+w-3,36),fill="#30251e")
        d.line((x+2,40,x+w-4,40),fill="#a27248")
        tag=((x-2,13),(x+1,11),(x+w-3,11),(x+w+2,13),(x+w,19),
             (x+w-4,21),(x+1,20))
        d.polygon(tag,fill="#806047",outline="#553b2e")
        d.line((x+1,11,x+w-3,11),fill="#b1875e")
        for t in (x+2,x+w-3):
            d.point((t,16),fill="#b2976b")
            d.point((t+1,17),fill="#352922")
        for _ in range(max(6,w//2)):
            a=int(random.integers(x+3,x+w-2))
            b=int(random.integers(13,19))
            d.point((a,b),fill=random.choice(("#624b38","#957154","#aa825f")))

    for x,w in ((8,42),(56,42),(104,23),(273,38)):
        bay(x,w)
    d.polygon(((133,11),(162,11),(169,15),(171,34),(166,41),(130,41),(126,35),(126,19)),
              fill="#34312a",outline="#c18d5d")
    d.polygon(((134,13),(162,13),(168,18),(168,34),(164,39),(132,39),(129,34),(129,20)),
              fill="#211815",outline="#554639")
    d.line((127,32,130,39,166,40,169,36),fill="#574336")
    for x,y in ((3,13),(3,38),(122,39),(174,12),(174,38),(316,13),(316,38)):
        d.ellipse((x-2,y-2,x+2,y+2),fill="#50372a",outline="#30241f")
        d.line((x-1,y-1,x+1,y-1),fill="#ba8e61")
        d.line((x-1,y+1,x+1,y),fill="#3c3028")
    base.save(folder/"status_panel.png")


def screen_art(folder):
    from PIL import ImageFont

    source = Image.open(SOURCE / "hardy_station.png").convert("RGB")
    inset = round(source.width * .046)
    source = source.crop((inset, inset, source.width - inset, source.height - inset))
    source = ImageOps.fit(source, (320, 200), Image.Resampling.LANCZOS, centering=(.54, .48))
    source = source.filter(ImageFilter.UnsharpMask(.8, 80, 2))
    yy, xx = np.indices((200, 320))
    grade = .46 + .33 * np.clip((xx - 29) / 235, 0, 1)
    shade = np.asarray(source, dtype=float) * grade[..., None] * [.92, .96, 1.13]
    im = Image.fromarray(np.clip(shade, 0, 255).astype("uint8")).convert("RGBA")
    d = ImageDraw.Draw(im)
    actor_image = Image.open(folder / "full_body_player.png").resize((79, 140), Image.Resampling.LANCZOS)
    im.alpha_composite(actor_image, (226, 63))
    for x in (6, 313):
        d.line((x, 6, x, 193), fill="#927650")
    for y in (6, 193):
        d.line((6, y, 313, y), fill="#927650")
    im.save(folder / "title_backdrop.png")
    words = Image.new("RGBA", (212, 80))
    title_grain = np.random.default_rng(1997)
    try:
        f = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 58)
    except OSError:
        f = font(60, True)
    for y, word, width, height, top, bottom in (
            (3, "CRAZY LEGS", 141, 15, [233, 211, 167], [146, 114, 82]),
            (21, "MUNDELL", 182, 20, [247, 229, 187], [155, 130, 101]),
            (46, "RAMPAGE", 202, 27, [250, 212, 107], [160, 62, 31])):
        glyphs = Image.new("L", (600, 95))
        ImageDraw.Draw(glyphs).text((12, 7), word, font=f, fill=255)
        glyphs = glyphs.crop(glyphs.getbbox()).resize((width, height), Image.Resampling.LANCZOS)
        mask = Image.new("L", words.size)
        mask.paste(glyphs, ((212-width)//2, y))
        shadow = mask.filter(ImageFilter.MaxFilter(7 if y>20 else 5))
        words.paste((17, 13, 13, 255), (0, 3), shadow)
        words.paste((79, 49, 36, 255), (0, 0), mask.filter(ImageFilter.MaxFilter(3)))
        rows = np.clip((np.arange(80) - y) / height, 0, 1)
        paint = np.asarray(top)[None, None] * (1 - rows[:, None, None]) + np.asarray(bottom) * rows[:, None, None]
        dust=title_grain.normal(0,7,(80,212,1))
        dust-=26*(title_grain.random((80,212,1))<.083)
        paint = np.clip(paint + dust, 0, 255).astype("uint8")
        layer = Image.fromarray(paint).convert("RGBA")
        words.paste(layer, (0, 0), mask)
    words.save(folder / "title_logo.png")
    icon = Image.new("RGBA", (64, 64), "#402b23")
    d = ImageDraw.Draw(icon)
    d.rectangle((4, 4, 59, 59), outline="#ae854d", width=3)
    d.text((32, 23), "CLM", anchor="mm", font=font(24, True), fill="#e2b680", stroke_width=1, stroke_fill="#271d19")
    d.line((12,34,52,34), fill="#6a4e39")
    d.text((32, 44), "RAMPAGE", anchor="mm", font=font(13, True), fill="#d98a50")
    icon.save(folder / "hickston_icon.png")
    icon.save(folder / "hickston.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])


if __name__ == "__main__":
    make_assets()

