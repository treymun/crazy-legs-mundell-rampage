"""Original fair and sawmill art assembled from drawing and the project's CC0 scans."""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from world_art import paint_sign, scan

ROOT = Path(__file__).resolve().parent
TILES = ROOT / "assets" / "tiles"
ART = ROOT / "assets" / "art"


def panel(size=(128, 128)):
    return Image.new("RGBA", size)


def bolts(draw, points, color="#ad9b77", shadow="#3b332b"):
    for x, y in points:
        draw.ellipse((x-2,y-2,x+2,y+2), fill=shadow)
        draw.point((x-1,y-1), fill=color)
        draw.point((x,y), fill=color)


def weather(image, seed, strength=14, scan_name="weathered_plank_siding"):
    """Add correlated photographic grain without rounding off hard silhouettes."""
    reference = scan(scan_name, (128,128,128), 1.05, .10).convert("L")
    grain = np.asarray(reference.resize(image.size), dtype=np.float32) - 128
    rng = np.random.default_rng(seed)
    specks = np.where(rng.random(grain.shape)<.042, rng.uniform(-32,15,grain.shape), 0)
    variation = grain * (strength/24) + specks
    values = np.asarray(image).copy()
    values[:,:,:3] = np.clip(values[:,:,:3].astype(np.float32)
                              + variation[:,:,None] * (1.,.91,.79),0,255)
    return Image.fromarray(values)


def wet_surface(name, base, seed):
    image = scan(name, base, 1.12, .38)
    values = np.asarray(image).copy()
    y,x = np.indices((128,128))
    stains = np.sin(x*.103+y*.067) + .61*np.sin(x*.21-y*.13) + .46*np.cos(y*.37)
    pooled = stains > 1.17
    values[pooled,:3] = np.clip(values[pooled,:3]*[.72,.78,.81]+[4,5,8],0,255)
    image = Image.fromarray(values)
    draw = ImageDraw.Draw(image)
    rng = np.random.default_rng(seed)
    for _ in range(30):
        sx,sy = (int(v) for v in rng.integers(1,121,2))
        if pooled[sy,sx]:
            draw.line((sx,sy,sx+int(rng.integers(2,8)),sy),fill=(104,111,104))
    return weather(image, seed, 10, name)


def water():
    y,x = np.indices((128,128))
    waves = np.sin(y*math.tau/32 + np.sin(x*math.tau/128)*1.8)
    waves += .47*np.sin(y*math.tau/16 - x*math.tau/128)
    foam = np.maximum(0,waves-.84)*26
    reflection = 5*np.sin(x*math.tau/128+y*math.tau/64)
    r = 47+5*waves+foam*.79+reflection
    g = 72+8*waves+foam*.96+reflection
    b = 81+9*waves+foam+reflection
    rgb = np.dstack((r,g,b)).clip(0,255).astype(np.uint8)
    return weather(Image.fromarray(rgb).convert("RGBA"),339,6,"brown_mud_03")


def log_end(draw, x, y, rx, ry, seed):
    rng = np.random.default_rng(seed)
    draw.ellipse((x-rx,y-ry,x+rx,y+ry),fill="#312923",outline="#1f211f",width=2)
    draw.ellipse((x-rx+2,y-ry+2,x+rx-2,y+ry-2),fill="#b1a078",outline="#725a40")
    for fraction in (.27,.43,.59,.74,.86):
        offset = int(rng.integers(-2,3))
        draw.ellipse((x-rx*fraction+offset,y-ry*fraction,x+rx*fraction+offset,y+ry*fraction),
                     outline=("#8f7754" if fraction<.7 else "#86704e"))
    for angle in rng.uniform(0, math.tau, 4):
        dx,dy = math.cos(angle)*rx, math.sin(angle)*ry
        draw.line((x+dx*.35,y+dy*.35,x+dx*.88,y+dy*.88),fill="#6a5541")


def mill_log():
    image = scan("weathered_plank_siding", (75,61,43), 1.24, .47)
    d = ImageDraw.Draw(image)
    for x,y,rx,ry in ((19,25,19,22),(60,23,23,23),(106,26,23,21),
                      (25,69,25,23),(72,68,21,24),(115,67,23,24),
                      (5,111,19,21),(44,111,22,23),(92,111,26,22)):
        log_end(d,x,y,rx,ry,20+x+y)
    return weather(image, 278, 16)


def tile_art():
    booth = scan("weathered_plank_siding", (119,75,55), 1.6, .5, turn=True)
    d = ImageDraw.Draw(booth)
    d.rectangle((0,48,127,74), fill="#9b9374")
    d.rectangle((0,53,127,63), fill="#598284")
    d.line((0,74,127,74), fill="#463628",width=3)
    for x in (0,32,64,96):
        d.line((x,0,x,127),fill="#48382e",width=2)
        d.line((x+2,4,x+2,127),fill="#a88d6c")
    bolts(d,[(x+7,y) for x in (0,32,64,96) for y in (8,114)])
    fair_iron = scan("corrugated_iron",(78,101,104),1.5,.65)
    d = ImageDraw.Draw(fair_iron)
    for x in (1, 63, 125):
        d.line((x,0,x,127),fill="#435659",width=2)
    d.rectangle((0,95,127,101),fill="#454c43")
    bolts(d,[(x,y) for x in (7,59,70,120) for y in (10,100,119)],"#a7a691")
    gate = scan("weathered_plank_siding",(111,88,61),1.25,.55,turn=True)
    d = ImageDraw.Draw(gate)
    d.rectangle((0,14,127,113),fill="#423733",outline="#b19860",width=2)
    for x in range(5,124,17):
        d.polygon(((x,19),(x+11,19),(x+7,107),(x-1,107)),fill="#67534c")
    bolts(d,[(x,y) for x in (8,120) for y in (19,107)])
    prize = scan("weathered_plank_siding",(109,96,77),1.26,.37,turn=True)
    d = ImageDraw.Draw(prize)
    for x in range(0,128,22):
        d.rectangle((x,0,x+8,127),fill="#725361")
        d.line((x+8,0,x+8,127),fill="#493841")
    for y in (7,113):
        d.rectangle((0,y,127,y+7),fill="#827760")
        d.line((0,y+7,127,y+7),fill="#413931")

    tin = scan("corrugated_iron",(100,115,112),1.50,.53)
    d = ImageDraw.Draw(tin)
    for x in (1,64,127):
        d.line((x,0,x,127),fill="#374b4c",width=2)
    d.rectangle((0,98,127,109),fill="#63574a")
    d.line((0,99,127,99),fill="#9c7a5f")
    bolts(d,[(x,y) for x in (6,60,70,121) for y in (15,103)])
    pump = scan("corrugated_iron",(71,93,88),1.11,.43)
    d = ImageDraw.Draw(pump)
    d.rectangle((7,10,120,116),fill="#4f5f54",outline="#202f2b",width=3)
    for y in range(22,105,8):
        d.rectangle((21,y,108,y+3),fill="#293734")
        d.line((22,y+4,106,y+4),fill="#68776b")
    bolts(d,[(x,y) for x in (13,113) for y in (16,110)])

    return {
        "fair_booth": weather(booth,23,28),
        "fair_iron": weather(fair_iron,84,20,"corrugated_iron"),
        "fair_gravel": wet_surface("asphalt_02",(84,87,82),16),
        "fair_gate": weather(gate,31,29),
        "fair_prize": weather(prize,89,25),
        "mill_tin": weather(tin,64,23,"corrugated_iron"),
        "mill_water": water(),
        "mill_log": mill_log(),
        "mill_oil": wet_surface("worn_concrete_floor",(93,84,68),81),
        "mill_pump": weather(pump,47,19,"corrugated_iron"),
        "mill_grit": wet_surface("brown_mud_03",(101,103,87),57),
    }


def sky(colors, seed, mill=False):
    rng = np.random.default_rng(seed)
    width, height = 512, 116
    clouds = np.zeros((height,width))
    for dimensions, amplitude in (((7,6),22),((17,12),15),((42,28),9),((97,40),6)):
        w,h = dimensions
        random = rng.integers(0,255,(h,w),dtype=np.uint8)
        random[:,-1] = random[:,0]
        layer = np.asarray(Image.fromarray(random).resize((width,height),Image.Resampling.BICUBIC))
        clouds += (layer/255.-.5)*amplitude
    y,x = np.indices((height,width))
    blend = np.clip(y/103 + .17*np.cos(x*math.tau/512),0,1)
    pixel = np.asarray(colors[0]) + blend[:,:,None]*(np.asarray(colors[1])-colors[0])
    pixel += clouds[:,:,None]
    border = 93 + 4*np.sin(x*.049) + 2*np.sin(x*.197)
    if mill:
        border -= 3*(np.sin(x*.23)+np.sin(x*.57)> .7)
    pixel[y>=border] *= .43
    pixel += rng.normal(0,1.3,(height,width,1))
    return Image.fromarray(pixel.clip(0,255).astype(np.uint8))


def sign(title, subtitle, background, ink, border="#b19367", size=(176,67), direction=0):
    w,h = size
    im = panel(size)
    d = ImageDraw.Draw(im)
    d.polygon(((4,2),(w-5,2),(w-1,9),(w-2,h-6),(w-7,h-1),(4,h-2),(0,h-8),(1,9)),
              fill=background,outline="#271f1b")
    d.rectangle((5,5,w-6,h-6),outline=border,width=2)
    paint_sign(im,title,(12,11,w-24,round(h*.37)),ink)
    if direction:
        y = round(h*.73)
        x = 27 if direction<0 else w-28
        shape = ((-12,-3),(1,-3),(1,-9),(14,0),(1,9),(1,3),(-12,3))
        d.polygon([(x+dx*direction,y+dy) for dx,dy in shape],fill=ink,outline="#2b241c")
    start = 48 if direction<0 else 10
    width = w-58 if direction else w-20
    paint_sign(im,subtitle,(start,round(h*.63),width,round(h*.20)),"#d7c89f")
    bolts(d,[(8,8),(w-9,8),(8,h-9),(w-9,h-9)])
    return weather(im, w+h, 14)


def mounted(board, *, grounded=False):
    w,h = board.size
    im = panel((w,h+50))
    d=ImageDraw.Draw(im)
    for x in (28,w-29):
        lower = (h+49,h+49) if grounded else (h+48,h+47)
        d.polygon(((x-4,27),(x+5,29),(x+5,lower[0]),(x-4,lower[1])),fill="#78634a",outline="#43372e")
        d.line((x-2,35,x-2,h+44),fill="#a58c66",width=2)
    im.alpha_composite(board)
    return weather(im,91,11)


def wayfinding():
    markers = (
        ("fair_concession_arrow","FOOD COURT","CONCESSIONS","#55412f","#f3d99e",-1),
        ("fair_games_arrow","GAME COURT","PRIZE GAMES","#354948","#ead7aa",1),
        ("mill_west_arrow","WEST BANK","FEED VALVE","#3b4a3d","#e9d4a0",-1),
        ("mill_east_arrow","EAST BANK","DRY KILNS","#504332","#ecd0a0",1),
        ("quarry_cut_arrow","CUTTING SHED","STONE FEED","#57483a","#f1d8a0",-1),
        ("quarry_stills_arrow","STILL YARD","CONDENSER","#544333","#f0d6a1",1),
    )
    for name,title,subtitle,background,ink,direction in markers:
        mounted(sign(title,subtitle,background,ink,direction=direction),grounded=True).save(ART/f"{name}.png")
    back = scan("weathered_plank_siding",(98,76,53),1.14,.23).resize((176,67)).convert("RGBA")
    ink = ImageDraw.Draw(back)
    ink.rectangle((1,1,174,65),outline="#3e3227",width=3)
    for y in (19,45):
        ink.line((3,y,172,y),fill="#513e2e",width=2)
        ink.line((3,y+2,172,y+2),fill="#a38460")
    for x in (28,147):
        ink.rectangle((x-4,3,x+5,65),fill="#725a42",outline="#43372a")
    bolts(ink,[(x,y) for x in (28,147) for y in (10,54)])
    mounted(back,grounded=True).save(ART/"wayfinding_back.png")


def barricade():
    im = panel((220,72))
    d = ImageDraw.Draw(im)
    for x in (5,205):
        d.rectangle((x,2,x+9,71),fill="#63594e",outline="#342c24",width=2)
    for y in (9,32,53):
        d.rectangle((2,y,217,y+8),fill="#6c5641",outline="#403428")
        d.line((5,y+1,214,y+1),fill="#9e7952",width=2)
    d.line((16,58,203,14),fill="#805b41",width=9)
    for x in range(46,182,32):
        d.rectangle((x,34,x+9,39),fill="#bf7546",outline="#e4ad72")
    return weather(im,86,19,"corrugated_iron")


def wheel():
    im = panel((200,222))
    d = ImageDraw.Draw(im)
    center = 101, 93
    ring = [(round(101+82*math.cos(a*math.tau/40)),round(93+77*math.sin(a*math.tau/40))) for a in range(40)]
    for x,y in ring[::4]:
        d.line((*center,x,y),fill="#393a42",width=4)
        d.line((center[0]-1,center[1],x-1,y),fill="#826969",width=1)
    d.line(ring+[ring[0]],fill="#393942",width=6)
    d.line(ring+[ring[0]],fill="#95717a",width=2)
    d.ellipse((93,85,109,101),fill="#85584b",outline="#403738",width=3)
    for i,(x,y) in enumerate(ring[::4]):
        if i == 3:
            d.line((x,y,x+2,y+18),fill="#775b51",width=3)
            continue
        d.line((x,y,x,y+11),fill="#837267",width=2)
        fill = ("#88534c","#527879","#8f8257")[i%3]
        d.polygon(((x-12,y+8),(x+12,y+8),(x+10,y+22),(x-9,y+22)),
                  fill=fill,outline="#3e3a3e")
        d.line((x-10,y+10,x+10,y+10),fill="#b29a82",width=2)
    for x in (42,162):
        d.line((101,96,x,213),fill="#473e40",width=10)
        d.line((101,96,x-3,213),fill="#916e64",width=3)
    d.line((54,188,148,188),fill="#564b47",width=5)
    return weather(im,23,19,"corrugated_iron")


def control(active, mill=False, relay=False):
    w,h = 112,126
    im = panel((w,h))
    d = ImageDraw.Draw(im)
    body = "#627470" if mill else "#6f6964"
    d.polygon(((15,12),(80,7),(101,17),(100,95),(85,106),(15,111)),
              fill="#363b37",outline="#211f1e",width=3)
    d.rectangle((14,17,86,103),fill=body,outline="#a49a7c",width=3)
    d.rectangle((19,22,80,47),fill="#302f29")
    paint_sign(im,("RELAY" if relay else "FEED" if mill else "POWER"),(24,27,51,13),"#f0d8ab")
    if relay:
        for i in range(3):
            x = 29+17*i
            d.rectangle((x,55,x+8,85),fill="#44382d",outline="#282925")
            d.rectangle((x+2,58,x+6,81),fill="#7d7763" if active else "#a5bb70")
        d.line((49,105,48,123,82,124),fill="#644d32",width=6)
    else:
        d.rounded_rectangle((31,53,69,86),4,fill="#2e3331",outline="#aca28d",width=2)
        d.line((49,71,57,60 if active else 80),fill="#c1a476",width=6)
        d.ellipse((64,89,76,99),fill="#b5ca76" if active else "#a95848")
    bolts(d,[(x,y) for x in (21,80) for y in (22,96)])
    return weather(im,131 if mill else 68,19,"corrugated_iron")


def post(mill=False):
    im=panel((52,142))
    d=ImageDraw.Draw(im)
    d.polygon(((22,19),(28,19),(31,141),(18,141)),fill="#68584b",outline="#352e27")
    d.line((23,21,20,136),fill="#958167",width=2)
    d.polygon(((12,13),(35,11),(46,25),(10,27)),fill="#5c5145",outline="#2f2b26")
    d.rectangle((14,23,43,27),fill="#f1ca7c" if mill else "#cfbbda")
    d.line((14,27,42,27),fill="#ab8052" if mill else "#a57592")
    d.line((27,29,28,105),fill="#403831",width=2)
    return weather(im,22,12)


def bulbs(active=True):
    im=panel((122,31))
    d=ImageDraw.Draw(im)
    d.arc((2,-31,120,23),15,167,fill="#5a4b3d",width=3)
    for i,x in enumerate((12,29,46,63,80,97,112)):
        y=15+round(8*math.sin(i*math.pi/6))
        color=("#dba76a","#e2be80","#98aeb3","#bf8698")[i%4] if active else "#645f50"
        d.ellipse((x-4,y-4,x+4,y+4),fill=color,outline="#453837")
        if active:
            d.point((x-1,y-2),fill="#f6dfb3")
    return im


def timber(pile=True):
    im=panel((128,64))
    d=ImageDraw.Draw(im)
    if pile:
        for x,y in ((24,46),(52,47),(79,47),(101,46),(39,28),(68,28),(91,28),(56,12),(78,13)):
            log_end(d,x,y,14,12,x+y)
    else:
        for x,y in ((9,33),(15,47),(6,55)):
            d.polygon(((x,y),(x+91,y-15),(x+112,y-10),(x+113,y-3),(x+14,y+10),(x,y+7)),
                      fill="#9b7e57",outline="#594634")
            d.line((x+3,y+1,x+105,y-9),fill="#c0a77f",width=2)
    return weather(im,37,19)


def pilings():
    im=panel((80,111))
    d=ImageDraw.Draw(im)
    for x, h, lean in ((14,32,-5),(39,13,4),(65,39,-4)):
        d.polygon(((x-6,h),(x+6,h),(x+lean+7,109),(x+lean-7,110)),
                  fill="#4e4940",outline="#282c2a",width=2)
        d.ellipse((x-6,h-3,x+6,h+5),fill="#977c56",outline="#584a37")
        d.line((x-4,h+8,x+lean-5,105),fill="#7a6954",width=2)
    d.line((11,58,67,63),fill="#564536",width=3)
    return weather(im,57,28)


def saw():
    im=panel((140,111))
    d=ImageDraw.Draw(im)
    d.polygon(((8,94),(37,71),(80,72),(121,81),(136,94),(132,107),(9,109)),
              fill="#56554e",outline="#252c28",width=3)
    center=(74,58)
    points=[]
    for i in range(66):
        a=i*math.tau/66
        r=42 if i%3==0 else 38
        points.append((center[0]+r*math.cos(a),center[1]+r*math.sin(a)))
    d.polygon(points,fill="#8f9890",outline="#424b48")
    d.ellipse((47,32,101,85),outline="#6b736b",width=3)
    d.ellipse((65,49,83,67),fill="#484f49",outline="#a6a298",width=2)
    d.arc((33,17,115,99),181,301,fill="#bab4a0",width=2)
    d.rectangle((7,90,137,107),fill="#52635d",outline="#303732",width=2)
    return weather(im,74,20,"corrugated_iron")


def prize_pile():
    im=panel((120,81))
    d=ImageDraw.Draw(im)
    for x,y,color in ((32,45,"#88705b"),(67,49,"#aa865e"),(92,55,"#64807a")):
        d.ellipse((x-13,y,x+14,y+24),fill=color,outline="#4c3e36")
        d.ellipse((x-13,y-16,x+10,y+7),fill=color,outline="#504234")
        d.ellipse((x-15,y-20,x-6,y-11),fill=color,outline="#4c3e36")
        d.ellipse((x+3,y-19,x+12,y-10),fill=color,outline="#4c3e36")
        d.ellipse((x-7,y-8,x-5,y-5),fill="#302822")
        d.ellipse((x+3,y-8,x+5,y-5),fill="#302822")
        d.line((x-2,y+1,x+2,y+2),fill="#3e3327",width=2)
    d.line((8,67,111,70),fill="#735040",width=5)
    d.line((12,73,109,75),fill="#493a30",width=3)
    return weather(im,52,25)


def scatter(kind):
    im=panel((128,64))
    d=ImageDraw.Draw(im)
    if kind=="aftermath":
        d.polygon(((9,44),(27,34),(53,35),(64,29),(82,33),(115,27),(107,40),
                   (72,45),(66,50),(33,48)),fill="#536243",outline="#313a2c")
        for x,y in ((18,47),(56,44),(91,37),(100,39),(27,40)):
            d.line((x,y,x+7,y-2),fill="#8a9161",width=2)
    elif kind=="dispatch":
        d.polygon(((12,36),(47,20),(69,38),(38,57)),fill="#b9a680",outline="#504336")
        for y in range(31,45,3):
            d.line((26,y,48,y+4),fill="#70604a")
        d.line((56,43,95,24,119,34),fill="#554637",width=5)
        d.rectangle((87,33,113,53),fill="#7a8176",outline="#382f29",width=2)
        d.line((89,37,109,37),fill="#b9ba99",width=2)
    else:
        d.ellipse((18,32,60,53),fill="#665149")
        d.ellipse((20,32,59,47),fill="#aa8e65",outline="#4b3930")
        d.ellipse((26,33,53,43),fill="#866943")
        d.polygon(((65,21),(80,19),(88,44),(75,50)),fill="#964d3e",outline="#5c3c31")
        d.line((66,22,80,20),fill="#c9ad82",width=2)
        d.polygon(((89,33),(113,21),(116,25),(93,41)),fill="#b2a77c",outline="#57483a")
    return weather(im,28 if kind=="dispatch" else 49,13)


def make_art():
    for name, image in tile_art().items():
        image.convert("RGB").save(TILES/f"{name}.png")
    sky(((17,22,34),(64,52,73)),613).save(TILES/"fair_sky.png")
    sky(((25,37,45),(98,112,109)),176,True).save(TILES/"mill_sky.png")
    signs = {
        "fair_entry": ("POSSUM COUNTY","FAIRGROUNDS","#664451","#f5deb0"),
        "fair_pavilion": ("PRIZE PAVILION","REDEMPTION CENTER","#583c43","#f3c89e"),
        "fair_ticket_rule": ("ADMISSION","TICKETS ARE FINAL","#514139","#d3bf93"),
        "fair_redemption": ("NO REFUNDS","EVEN IF PRIZE HATCHES","#644753","#efcca2"),
        "fair_lost_property": ("LOST SOCKS","CHECK THE PANEL","#435551","#e5c99d"),
        "mill_entry": ("BLACKWATER TIMBER","FLOOD SHIFT","#364c4a","#ddcfaa"),
        "mill_shed": ("CUTTING SHED","WATCH YOUR STEP","#434d42","#e2c695"),
        "mill_pump_sign": ("PUMP HOUSE","AUTHORIZED ONLY","#5b5141","#efc984"),
        "mill_notice": ("DRY STORAGE","BEHIND LOOSE GRILLE","#5e5446","#e1c79a"),
        "hub_title": ("COUNTY CROSSROADS","THRU TRAFFIC BEYOND GATES","#665139","#ead3a0"),
        "hub_hickston": ("HICKSTON","ROAD","#493b30","#f1dfbb"),
        "hub_return": ("COUNTY HUB","RETURN GATE","#4f5543","#eee0b0"),
    }
    props = {name: sign(*arguments) for name, arguments in signs.items()}
    for name in ("hub_title","mill_entry"):
        props[name] = mounted(props[name])
    props.update(fair_wheel=wheel(), fair_pylon=post(), mill_pylon=post(True),
                 fair_bulbs=bulbs(), fair_bulbs_on=bulbs(), fair_bulbs_off=bulbs(False),
                 fair_prize_pile=prize_pile(), fair_spill=scatter("food"),
                 story_dispatch=scatter("dispatch"), story_food=scatter("food"),
                 story_aftermath=scatter("aftermath"), hub_lamp=post(True),
                 mill_pilings=pilings(), mill_saw=saw(), mill_timber=timber(False),
                 mill_log_ends=timber(), hub_barricade_off=barricade(),
                 hub_barricade_on=panel((220,72)))
    for active, suffix in ((True, "_on"),(False,"_off")):
        for name,title,direction in (("hub_fair","COUNTY FAIR","MIDWAY"),
                                     ("hub_mill","BLACKWATER","SAWMILL")):
            props[name+suffix] = sign(title, direction if active else "GATE CLOSED",
                                      "#3f4e37" if active else "#5e382d","#f1dfbb")
        for prefix, mill in (("fair",False),("mill",True)):
            props[prefix+"_control"+suffix] = control(active,mill)
            props[prefix+"_relay"+suffix] = control(active,mill,True)
            props[prefix+"_exit"+suffix] = sign("EXIT", "LANE CLEAR" if active else "HOLD POSITION",
                                                 "#415741" if active else "#66483d",
                                                 "#e9e3ba" if active else "#e3b489")
    for name,image in props.items():
        image.save(ART/f"{name}.png")
    wayfinding()


if __name__ == "__main__":
    make_art()
