"""Bake painted hardware, work surfaces and ground stains from credited scans."""
from functools import lru_cache
from pathlib import Path
from random import Random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from county_detail import SITES, SURFACES
from world_art import scan


ART = Path(__file__).resolve().parent / "assets" / "art"
TILES = ART.parent / "tiles"
SIZE = (144, 96)
EDGE = "#302923"
WOOD = ("weathered_plank_siding", (119, 88, 60))
TIN = ("corrugated_iron", (103, 111, 105))
RED = ("corrugated_iron", (142, 74, 57))
COPPER = ("corrugated_iron", (153, 111, 71))
CANVAS = ("worn_concrete_floor", (161, 139, 94))
PAPER = ("old_linoleum_flooring_01", (175, 150, 108))
STONE = ("worn_concrete_floor", (145, 135, 110))
RUBBER = ("asphalt_02", (66, 65, 57))
TEAL = ("corrugated_iron", (81, 111, 102))
GREEN = ("corrugated_iron", (104, 112, 76))


@lru_cache(maxsize=24)
def texture(finish):
    material, tone = finish
    return scan(material,tone,1.07,.20).resize(SIZE,Image.Resampling.LANCZOS)


@lru_cache(maxsize=1)
def abrasion():
    plate = texture(STONE).convert("L")
    photo = np.asarray(plate,dtype=np.float32)
    broad = np.asarray(plate.filter(ImageFilter.GaussianBlur(3)),dtype=np.float32)
    return np.clip((photo-broad)*.58+(broad-np.median(broad))*.40,-17,17)


class Paint:
    def __init__(self):
        self.image = Image.new("RGBA",SIZE)
        self.ink = ImageDraw.Draw(self.image)

    def form(self, shape, xy, finish, outline=EDGE, width=2):
        mask = Image.new("L",SIZE)
        getattr(ImageDraw.Draw(mask),shape)(xy,fill=255)
        self.image.paste(texture(finish),(0,0),mask)
        getattr(self.ink,shape)(xy,outline=outline,width=width)

    def box(self, x, y, w, h, finish=WOOD, side=9):
        self.form("polygon",((x,y),(x+side,y-side),(x+w+side,y-side),(x+w,y)),finish)
        self.form("polygon",((x+w,y),(x+w+side,y-side),(x+w+side,y+h-side),(x+w,y+h)),finish,"#41362b")
        self.form("rectangle",(x,y,x+w,y+h),finish)
        self.ink.line((x+3,y+2,x+w-3,y+2),fill="#b29a74")
        self.ink.line((x+2,y+h-2,x+w-2,y+h-2),fill="#463a2f",width=2)

    def tube(self, points, width=9, tint="#937b55", gleam="#c5a678"):
        self.ink.line(points,fill=EDGE,width=width+3,joint="curve")
        self.ink.line(points,fill=tint,width=width,joint="curve")
        self.ink.line(tuple((x-1,y-2) for x,y in points),fill=gleam,width=max(1,width//4),joint="curve")

    def bolts(self, points, tint="#baa279"):
        for x,y in points:
            self.ink.ellipse((x-2,y-2,x+2,y+2),fill="#473b30")
            self.ink.point((x,y-1),fill=tint)

    def label(self, xy, word, color="#d8c39d", size=10):
        self.ink.text(xy,word,font=ImageFont.load_default(size=size),fill=color,stroke_width=0)

    def dial(self, x, y, r, reading=1):
        self.form("ellipse",(x-r,y-r,x+r,y+r),TIN,width=3)
        self.ink.ellipse((x-r+4,y-r+4,x+r-4,y+r-4),fill="#c4b78e",outline="#5e5442",width=2)
        for dx,dy in ((-7,0),(-5,-5),(0,-7),(5,-5),(7,0)):
            sx,sy=x+dx*r//10,y+dy*r//10
            self.ink.point((sx,sy),fill="#463b2c")
        self.ink.line((x,y,x+reading*(r-6),y-r//2),fill="#884734",width=2)
        self.ink.ellipse((x-2,y-2,x+2,y+2),fill=EDGE)

    def reel(self, x, y, r, finish=RED):
        self.form("ellipse",(x-r,y-r,x+r,y+r),finish,width=3)
        self.ink.ellipse((x-r+5,y-r+5,x+r-5,y+r-5),outline="#655441",width=4)
        self.ink.ellipse((x-r+9,y-r+9,x+r-9,y+r-9),outline="#918165",width=2)
        for dx,dy in ((-8,-5),(8,-5),(0,9)):
            self.ink.ellipse((x+dx-3,y+dy-3,x+dx+3,y+dy+3),fill="#39332b")
        self.bolts(((x,y),))

    def bottle(self, x, bottom, h, finish=GREEN, label="#a79363"):
        top = bottom-h
        self.form("polygon",((x-6,bottom),(x-8,bottom-5),(x-8,top+16),(x-4,top+10),
                             (x-4,top+3),(x+4,top+3),(x+4,top+10),(x+8,top+16),
                             (x+8,bottom-4),(x+5,bottom)),finish)
        self.ink.rectangle((x-4,top,x+4,top+4),fill="#aa8c57",outline=EDGE)
        self.ink.line((x-5,top+18,x-5,bottom-6),fill="#b7ad85")
        self.ink.polygon(((x-6,top+22),(x+6,top+21),(x+6,top+30),(x-6,top+31)),fill=label)

    def bag(self, x, y, w, h, finish=CANVAS):
        self.form("polygon",((x+8,y),(x+w-12,y+1),(x+w-3,y+8),(x+w,y+h-5),(x+w-10,y+h),
                             (x+4,y+h),(x,y+h-6),(x+2,y+9)),finish)
        self.ink.line((x+9,y+4,x+w-13,y+5),fill="#cfb989",width=2)
        self.ink.line((x+11,y+h-6,x+w-10,y+h-7),fill="#695943",width=2)
        self.ink.line((x+w-10,y+9,x+w-6,y+h-12),fill="#9a7f59",width=2)

    def papers(self, x, y, w, h, stamp=None):
        self.form("polygon",((x+5,y),(x+w,y+3),(x+w-7,y+h),(x,y+h-3)),PAPER,width=1)
        for line in range(7,h-4,5):
            self.ink.line((x+8,y+line,x+w-12,y+line+1),fill="#88765d")
        if stamp:
            self.label((x+9,y+3),stamp,"#594635",8)

    def spanner(self, x, y, dx, dy, tint="#968e78"):
        self.tube(((x,y),(x+dx,y+dy)),4,tint,"#b1a287")
        self.ink.arc((x-6,y-6,x+6,y+6),48,336,fill="#a79b80",width=3)
        self.ink.ellipse((x+dx-3,y+dy-3,x+dx+3,y+dy+3),outline=EDGE,width=2)

    def save(self, name):
        rgba = np.array(self.image)
        rgb = rgba[:,:,:3].astype(np.float32)
        # A shifted plate keeps adjacent props from sharing the same chips.
        rng = Random(f"county-hardware:{name}")
        wear = np.roll(abrasion(),(rng.randrange(SIZE[1]),rng.randrange(SIZE[0])),axis=(0,1))
        level = rgb.mean(axis=2)
        exposed = np.clip((level-35.)/40.,0.,1.) * np.clip((202.-level)/55.,0.,1.)
        grime = np.maximum(wear,0.)*np.linspace(.04,.57,SIZE[1])[:,None]
        shade = (wear-grime) * exposed
        rgba[:,:,:3] = np.clip(rgb+shade[:,:,None]*[1.06,.95,.84],0,255).astype(np.uint8)
        Image.fromarray(rgba).crop(self.image.getbbox()).save(ART/f"detail_{name}.png")


def town(name, p):
    d=p.ink
    if name=="bar_backstock":
        p.box(10,58,112,26,WOOD)
        for x,b,h in ((26,64,51),(46,66,60),(65,67,45),(86,62,55),(105,69,42)):
            p.bottle(x,b,h,GREEN if x%3 else COPPER)
        p.form("polygon",((10,58),(55,62),(120,57),(121,83),(10,84)),WOOD)
        p.label((46,67),"EMPTIES")
        p.bolts(((16,76),(114,76)))
    elif name=="dispatch_rack":
        p.box(10,14,113,67,GREEN,5)
        p.papers(17,24,48,44,"OUT")
        for x,y in ((75,32),(91,30),(108,34)):
            p.bolts(((x,y),))
            d.arc((x-3,y+3,x+6,y+12),-40,235,fill="#c3ae81",width=2)
            p.tube(((x+1,y+10),(x+4,y+25)),2,"#ac9564")
            d.rectangle((x+2,y+20,x+8,y+24),fill="#ad9161")
        p.label((70,65),"COUNTY")
    elif name=="feed_sampler":
        p.box(12,55,104,29,WOOD)
        p.bag(18,18,43,49)
        p.bag(71,27,46,40)
        p.tube(((67,64),(81,36),(101,23)),5,"#716953","#c5b182")
        p.label((22,36),"FEED","#644934")
        d.ellipse((49,64,82,77),fill="#9f8354",outline=EDGE,width=2)
        p.bolts(((19,78),(108,78)))
    elif name=="trailer_service":
        p.box(9,18,119,62,TIN,5)
        p.tube(((18,31),(48,31),(49,61),(78,60),(81,34),(115,34)),8,"#5d6e66","#a1a393")
        p.dial(104,54,13,-1)
        p.bolts(((16,23),(122,23),(16,72),(121,73)))
        p.label((22,56),"12 V")
    elif name=="tire_patch_bench":
        p.box(13,55,111,29,TEAL)
        p.reel(44,45,27,RUBBER)
        p.box(84,34,26,23,RED,5)
        p.spanner(62,68,36,7)
        p.bolts(((18,78),(117,78)))
        p.label((88,39),"PATCH","#d1b58b",8)
    elif name=="tow_spool":
        p.box(18,61,94,22,WOOD)
        p.reel(59,45,31,RED)
        p.tube(((70,44),(98,53),(102,70),(122,74)),6,"#746c57","#aa9b76")
        d.arc((115,62,135,82),12,268,fill="#b0a184",width=4)
        p.bolts(((24,75),(105,76)))
    elif name=="registry_stamp":
        p.box(12,58,114,26,WOOD)
        p.papers(17,31,56,39,"ENTRY")
        p.box(88,48,23,21,RED,6)
        p.tube(((99,50),(99,28)),8,"#765337","#ae885d")
        p.form("ellipse",(85,20,113,35),WOOD)
        p.label((79,72),"FILE 4")
    else:
        p.box(12,56,109,27,WOOD)
        p.bag(17,17,52,49)
        p.bag(62,28,53,44)
        d.line((29,37,52,38),fill="#8d4939",width=3)
        d.line((29,41,51,42),fill="#8d4939",width=2)
        p.label((70,44),"MASH","#6b4f3a")


def fair(name, p):
    d=p.ink
    if name=="ticket_rolls":
        p.box(10,49,115,35,RED)
        for x,y,r in ((33,46,18),(65,37,20),(100,46,17)):
            p.reel(x,y,r,PAPER)
        p.papers(46,53,55,20,"ADMIT ONE")
        p.bolts(((16,78),(121,78)))
    elif name=="soda_fountain":
        p.box(14,36,109,47,TIN)
        p.form("rectangle",(23,19,115,57),TEAL)
        p.label((45,22),"COLD POP",size=11)
        p.bolts(((28,25),(110,25),(28,52),(111,52)))
        for x in (40,67,94):
            p.tube(((x,38),(x,48),(x+7,49)),5,"#9a8a70","#c5b999")
            d.rectangle((x-1,56,x+11,68),fill="#8a593f",outline=EDGE)
            d.line((x+2,69,x+5,75),fill="#6f5342")
        d.polygon(((20,73),(118,72),(114,80),(26,80)),fill="#55483b",outline=EDGE)
        for x in range(30,112,6):
            d.line((x,74,x-2,78),fill="#a8977b")
    elif name=="prize_cubbies":
        p.box(9,16,117,68,RED,4)
        for x,y,kind in ((16,22,"bell"),(53,22,"ring"),(90,22,"duck"),(16,51,"ring"),
                         (53,51,"duck"),(90,51,"bell")):
            d.rectangle((x,y,x+30,y+24),fill="#48332c",outline="#ae8062")
            if kind=="bell":
                d.polygon(((x+7,y+17),(x+10,y+8),(x+15,y+4),(x+20,y+8),(x+24,y+18)),
                          fill="#af8450",outline=EDGE)
            elif kind=="ring":
                d.ellipse((x+8,y+6,x+23,y+20),outline="#98694d",width=4)
            else:
                d.ellipse((x+7,y+11,x+23,y+19),fill="#c39b5d",outline=EDGE)
                d.ellipse((x+17,y+6,x+25,y+14),fill="#c39b5d",outline=EDGE)
    elif name=="stage_footlights":
        p.box(8,44,122,37,RED,5)
        for x,off in ((21,0),(45,1),(70,0),(95,0),(118,1)):
            p.form("ellipse",(x-9,26,x+9,51),TIN)
            d.ellipse((x-5,31,x+5,45),fill="#605849" if off else "#bba075",outline=EDGE)
        p.tube(((19,66),(54,61),(98,69),(121,60)),3,"#695443")
    elif name=="freight_cartons":
        p.box(15,45,105,37,WOOD)
        p.box(24,27,48,39,PAPER,5)
        p.box(77,36,32,35,RED,5)
        d.line((46,28,47,63),fill="#b38b5a",width=5)
        p.label((27,49),"SHOW 2","#78523b")
        p.label((79,46),"FRAGILE",size=7)
    elif name=="raffle_drawer":
        p.box(11,18,118,62,RED,4)
        d.rectangle((22,30,114,68),fill="#60483a",outline="#9e795c",width=3)
        p.papers(25,28,50,33,"STUBS")
        p.papers(68,37,41,22)
        p.tube(((52,62),(55,67),(87,67),(89,61)),5)
        p.bolts(((18,23),(119,23),(17,74),(119,74)))
    elif name=="pa_cable_case":
        p.box(13,42,113,41,TEAL,6)
        p.reel(52,44,27,RUBBER)
        p.tube(((52,45),(80,57),(95,51),(103,37),(119,35)),4,"#5e5749","#938469")
        d.rectangle((111,31,123,42),fill="#b49163",outline=EDGE)
        p.label((86,67),"JACK B")
    else:
        p.box(11,47,120,36,WOOD,5)
        p.bag(19,36,43,25,CANVAS)
        p.form("ellipse",(64,31,102,62),TEAL)
        p.tube(((74,47),(84,44),(100,51),(114,59)),3,"#a2906b")
        p.papers(74,59,44,20,"FOUND")


def timber(name, p):
    d=p.ink
    if name=="delivery_chocks":
        p.box(9,62,117,20,WOOD)
        for x,y in ((17,30),(49,37),(81,28)):
            p.form("polygon",((x,y+29),(x+27,y),(x+39,y+28)),WOOD)
            d.line((x+4,y+27,x+29,y+9),fill="#b2996c",width=2)
        p.tube(((20,64),(51,65),(90,63),(114,72)),3,"#696f5f")
    elif name=="sluice_winder":
        p.box(16,56,110,27,TIN)
        p.reel(46,43,27,TEAL)
        p.tube(((46,43),(78,42),(94,36),(111,35)),8,"#827d69","#a6a389")
        p.form("polygon",((88,39),(110,40),(115,64),(84,64)),TIN)
        p.tube(((105,38),(112,23),(127,18)),4)
        p.bolts(((24,76),(112,76)))
    elif name=="carriage_tools":
        p.box(11,21,118,60,WOOD,5)
        p.spanner(38,42,14,21)
        p.spanner(77,36,-10,27)
        p.tube(((104,35),(101,65)),5,"#956e45")
        d.rectangle((94,32,110,39),fill="#788078",outline=EDGE)
        p.bolts(((20,29),(121,30),(21,73),(121,74)))
    elif name=="pump_manifold":
        p.box(9,19,117,65,TIN)
        p.tube(((18,59),(44,60),(44,33),(87,34),(87,64),(122,64)),10,"#797b69","#aaa489")
        p.dial(65,40,15,1)
        p.reel(100,53,13,RED)
        d.line((17,75,124,73),fill="#7d5c47",width=2)
    elif name=="sort_chain_box":
        p.box(11,49,115,34,TEAL)
        p.box(20,23,103,30,TIN)
        d.rectangle((25,29,114,44),fill="#3f4037",outline="#a69370")
        for x in range(31,113,12):
            d.ellipse((x-5,32,x+7,41),outline="#a19579",width=2)
        p.label((23,62),"OIL BEFORE SHIFT")
        p.bolts(((17,77),(121,77)))
    elif name=="kiln_duct":
        p.box(13,49,109,34,TIN)
        p.tube(((31,58),(31,22),(89,21),(105,32),(105,51)),19,"#798078","#a8a68a")
        for x,y,w,h in ((24,42,16,5),(53,12,4,18),(85,14,4,16)):
            p.form("rectangle",(x,y,x+w,y+h),TIN,width=1)
            p.bolts(((x+2,y+2),(x+w-2,y+h-2)))
        p.form("ellipse",(89,43,120,61),TIN)
        d.ellipse((95,46,113,56),fill="#514f43")
        p.dial(61,53,15,-1)
        p.bolts(((21,57),(21,76),(114,67),(113,77)))
        d.line((23,72,111,69),fill="#907358",width=3)
    elif name=="rain_stock":
        p.box(12,61,106,20,WOOD)
        for x,y,w in ((18,56,96),(23,44,90),(15,33,93),(27,23,81)):
            p.box(x,y,w,12,WOOD,7)
            d.line((x+6,y+9,x+w-8,y+9),fill="#887258")
        p.papers(77,44,38,24,"WET")
        p.tube(((28,27),(28,69)),3,"#8e8061")
    else:
        p.box(11,53,115,29,WOOD)
        for x,y,r in ((45,42,25),(78,38,27),(104,48,19)):
            p.form("ellipse",(x-r,y-r,x+r,y+r),TIN)
            d.ellipse((x-5,y-5,x+5,y+5),outline=EDGE,width=3)
            for dx,dy in ((-13,-10),(10,-13),(12,9),(-10,11)):
                d.line((x+dx,y+dy,x+dx+4,y+dy+1),fill="#8b6c52",width=2)
        p.label((27,67),"RESAW BLADES")


def quarry(name, p):
    d=p.ink
    if name=="scale_weights":
        p.box(14,56,106,26,WOOD)
        for x,y,w in ((22,29,32),(63,38,24),(95,48,19)):
            p.form("polygon",((x,y+29),(x+4,y+5),(x+w-4,y+4),(x+w,y+29)),TIN)
            d.arc((x+8,y-3,x+w-8,y+12),185,354,fill="#ad9e7c",width=3)
        p.label((26,43),"50","#d1bc93")
        p.papers(59,65,50,14)
    elif name=="cutting_drill":
        p.box(14,54,114,27,WOOD)
        p.tube(((27,49),(44,40),(83,37),(112,33)),12,"#74776c","#aead91")
        p.form("ellipse",(29,28,64,56),TIN)
        p.tube(((43,45),(45,67)),8,"#745947")
        for x in (74,85,96,107):
            d.line((x-3,44,x+3,32),fill="#4f5043",width=3)
        p.bag(90,55,25,20)
    elif name=="still_gauge_bank":
        p.box(11,42,117,40,COPPER)
        for x,y,r,angle in ((32,40,18,-1),(68,35,22,1),(109,44,15,-1)):
            p.tube(((x,67),(x,y)),7,"#9a7751")
            p.dial(x,y,r,angle)
        p.bolts(((20,76),(117,77)))
        p.label((50,66),"HEAD")
    elif name=="bottling_cradles":
        p.box(11,55,114,28,WOOD)
        for x,b,h in ((29,62,48),(47,65,51),(66,65,44),(87,62,53),(108,67,38)):
            p.bottle(x,b,h,TEAL if x%2 else GREEN,"#bd9f72")
        p.tube(((14,61),(50,67),(84,64),(119,60)),5,"#87674e")
        p.label((50,71),"LOT 9")
    elif name=="lower_core_samples":
        p.box(12,48,112,35,WOOD)
        for x,y,finish in ((21,22,STONE),(53,20,CANVAS),(86,27,STONE)):
            p.form("polygon",((x,y+14),(x+7,y),(x+29,y+2),(x+35,y+25),(x+13,y+37),(x+1,y+29)),finish)
            d.line((x+2,y+17,x+22,y+23,x+33,y+18),fill="#a79c7e",width=2)
        p.papers(51,60,48,19,"CUT 6")
    elif name=="recovery_seal_kit":
        p.box(11,47,116,35,COPPER,5)
        for x,y,r in ((31,43,18),(70,38,24),(105,45,16)):
            p.form("ellipse",(x-r,y-r,x+r,y+r),COPPER)
            d.ellipse((x-r+5,y-r+5,x+r-5,y+r-5),fill="#514638",outline="#b29869",width=2)
        p.spanner(57,59,31,14)
        p.label((18,65),"GSKT.")
    elif name=="wash_rejects":
        p.box(13,49,116,32,WOOD)
        p.bottle(37,59,41,GREEN,"#89795d")
        p.bottle(64,60,48,COPPER)
        p.bottle(94,58,32,TEAL)
        d.polygon(((109,64),(112,51),(120,63)),fill="#918f6a",outline=EDGE)
        p.label((43,65),"REJECTS")
    else:
        p.box(11,47,113,34,TIN)
        p.spanner(39,35,37,32)
        p.spanner(95,31,-15,28)
        p.reel(105,63,14,COPPER)
        p.label((19,65),"RELIEF")


def roads(name, p):
    d=p.ink
    if name=="town_roadside_kit":
        p.box(15,47,105,34,TIN)
        p.box(28,31,56,33,RED,5)
        p.tube(((43,30),(43,23),(71,22),(73,29)),4,"#82735d")
        p.spanner(89,43,27,22)
        p.label((35,43),"COUNTY")
    elif name=="fair_route_crate":
        p.box(13,38,110,45,RED)
        p.bag(19,30,44,29)
        p.reel(91,42,20,PAPER)
        p.papers(54,58,51,15,"FAIR")
        d.line((27,69,29,80),fill="#9b7250",width=4)
    elif name=="mill_tie_off":
        p.box(15,55,108,27,WOOD)
        p.reel(48,42,28,RUBBER)
        p.tube(((57,45),(79,55),(111,52),(124,62)),5,"#85785c")
        d.arc((114,55,134,76),0,296,fill="#a69b80",width=3)
        p.label((22,66),"CHOKER")
    elif name=="quarry_survey_case":
        p.box(15,48,109,34,GREEN)
        p.papers(20,32,52,33,"BENCH")
        p.dial(99,43,21,-1)
        d.line((83,56,110,58),fill="#a79e82")
        p.bolts(((23,74),(117,74)))
    elif name=="tower_service_valve":
        p.box(13,55,111,28,TIN)
        p.tube(((19,52),(42,52),(42,33),(97,34),(100,55),(120,55)),12,"#897458","#b79e72")
        p.reel(70,43,20,RED)
        p.dial(91,28,11,1)
        p.label((20,67),"NO. 2")
    elif name=="shed_tool_tray":
        p.box(11,52,117,30,WOOD)
        p.form("polygon",((18,43),(32,33),(121,37),(121,58),(19,61)),TEAL)
        p.spanner(35,42,37,9)
        p.tube(((78,43),(109,48)),4,"#b39164")
        d.rectangle((96,42,111,49),fill="#686a60",outline=EDGE)
        p.label((20,67),"ROAD CREW")
    elif name=="shed_spare_screen":
        p.box(16,55,110,28,WOOD)
        p.form("polygon",((29,62),(24,19),(110,9),(117,54)),WOOD,width=3)
        d.polygon(((35,52),(31,24),(103,16),(109,49)),fill="#4c4940")
        for nudge in range(0,65,8):
            d.line((34+nudge,26,36+nudge,49),fill="#817d65")
        for nudge in range(0,23,5):
            d.line((34,27+nudge,104,20+nudge),fill="#9a8b6b")
        p.tube(((32,57),(110,13)),3,"#897758")
    else:
        p.box(14,58,113,25,TIN)
        p.form("polygon",((22,62),(31,21),(112,24),(121,62)),TIN)
        for x in (33,50,67,84,101):
            p.tube(((x+5,28),(x,58)),5,"#716c54","#99937a")
        p.tube(((28,37),(116,38)),5)
        d.line((36,53,63,48,86,54,104,48),fill="#a48a5d",width=3)


WEAR = {
    "oil":((56,46,35),132), "grain":((157,128,74),125),
    "soda":((83,60,45),130), "tickets":((163,117,73),141),
    "sawdust":((157,122,72),145), "chalk":((166,148,116),139),
    "copper":((93,109,74),133), "silt":((82,80,55),123),
}


def stain(kind, color, opacity):
    rng=Random(f"county-detail:{kind}")
    canvas=Image.new("RGBA",(112,64))
    d=ImageDraw.Draw(canvas)
    if kind in ("oil","soda","copper","silt"):
        d.polygon(((10,28),(22,19),(49,22),(64,12),(90,23),(95,38),(71,44),(48,48),
                   (37,41),(22,46),(8,37)),fill=(*color,opacity-46))
        for _ in range(58):
            x=rng.randint(13,98)
            y=rng.randint(13,49)
            if ((x-55)/49)**2+((y-32)/19)**2>1:
                continue
            d.line((x,y,x+rng.randint(1,8),y+rng.choice((-1,0,1))),
                   fill=(*color,rng.randint(opacity-44,opacity)),width=rng.choice((1,2)))
    else:
        for _ in range(114 if kind!="tickets" else 28):
            x=rng.randint(8,104)
            y=rng.randint(6,57)
            if ((x-55)/49)**2+((y-32)/26)**2>1:
                continue
            w=rng.randint(2,7) if kind=="tickets" else rng.randint(1,4)
            h=rng.randint(2,4) if kind=="tickets" else 1
            tint=tuple(min(255,max(0,c+rng.randint(-15,16))) for c in color)
            d.polygon(((x,y),(x+w,y-1),(x+w+1,y+h),(x+1,y+h+1)),
                      fill=(*tint,rng.randint(opacity-55,opacity)))
    canvas.save(ART/f"detail_wear_{kind}.png")


def paint_wall(surface):
    base_name = "wood" if surface.finish=="bar wainscot" else surface.base
    with Image.open(TILES/f"{base_name}.png") as source:
        base = source.convert("RGB")
    rgb=np.asarray(base,dtype=np.float32)
    gray=rgb.mean(axis=2)
    tint=np.clip(np.asarray(surface.tone)+(gray-np.median(gray))[:,:,None]*.83,0,255)
    tinted=Image.fromarray(tint.astype("uint8"))
    rng=Random(f"county-panel:{surface.name}")
    mask=Image.new("L",base.size)
    d=ImageDraw.Draw(mask)
    mode=surface.finish
    if mode=="bar wainscot":
        image=Image.blend(base,tinted,.72)
        d=ImageDraw.Draw(image)
        d.rectangle((0,67,127,127),fill=None,outline=(68,53,43),width=2)
        d.line((0,68,127,68),fill=(131,105,75),width=3)
        d.line((0,73,127,73),fill=(63,49,37),width=2)
        for x in (11,48,86,115):
            d.line((x,76,x-2,123),fill=(62,48,37))
            d.line((x+1,77,x,120),fill=(107,82,61))
            d.point((x+4,79),fill=(147,116,84))
    elif mode in ("oil paint","skirting","fair stripes"):
        y=64 if mode=="oil paint" else 79 if mode=="skirting" else 28
        bottom=127 if mode!="fair stripes" else 106
        d.polygon(((0,y+1),(16,y),(33,y+2),(53,y+1),(84,y-1),(108,y+1),(127,y+1),
                   (127,bottom),(0,bottom)),fill=209 if mode=="oil paint" else 174)
        for _ in range(33):
            x,top=rng.randrange(1,125),rng.randrange(y,max(y+1,bottom))
            depth=rng.randrange(2,13) if top<y+13 else rng.randrange(1,6)
            d.polygon(((x,top),(x+rng.randrange(1,9),top+1),(x+3,top+depth),(x,top+depth-1)),
                      fill=rng.randrange(28,106))
        image=Image.composite(tinted,base,mask)
        d=ImageDraw.Draw(image)
        upper=(156,119,77) if mode!="fair stripes" else (163,133,87)
        d.line((0,y+2,21,y+1,51,y+3,82,y+1,127,y+2),fill=upper,width=2)
        if mode=="fair stripes":
            d.line((0,100,28,98,65,100,96,98,127,100),fill=(145,124,91),width=3)
            d.line((0,105,127,105),fill=(85,90,82),width=2)
        for x,w in ((17,2),(56,1),(96,3),(111,1)):
            d.line((x,bottom-8,x+w,bottom-2),fill=(84,69,48))
    elif mode=="riveted patches":
        d.rectangle((0,0,127,127),fill=134)
        for box in ((11,18,52,52),(79,71,117,108)):
            d.rectangle(box,fill=213)
        image=Image.composite(tinted,base,mask)
        d=ImageDraw.Draw(image)
        for x0,y0,x1,y1 in ((11,18,52,52),(79,71,117,108)):
            d.rectangle((x0,y0,x1,y1),outline=(78,62,48),width=2)
            d.line((x0+2,y0+1,x1-1,y0+1),fill=(151,126,84))
            for x,y in ((x0+5,y0+5),(x1-5,y0+5),(x0+5,y1-5),(x1-5,y1-5)):
                d.rectangle((x-1,y-1,x+1,y+1),fill=(66,60,48))
                d.point((x-1,y-1),fill=(160,135,97))
                d.line((x,y+1,x+1,y+rng.randint(4,11)),fill=(109,77,55))
    elif mode=="runoff":
        for x,width,length in ((7,10,89),(39,16,124),(75,9,83),(105,13,112)):
            d.polygon(((x,0),(x+width,0),(x+width-4,length),(x+3,length-6)),fill=196)
            d.line((x+2,2,x+2,length-1),fill=217,width=2)
        image=Image.composite(tinted,base,mask)
        d=ImageDraw.Draw(image)
        d.line((0,105,36,102,60,107,91,104,127,107),fill=(88,105,99),width=3)
        d.line((0,110,29,109,66,112,100,109,127,112),fill=(69,77,67),width=2)
    else:
        for y in (23,62,104):
            d.polygon(((0,y+3),(26,y),(41,y-4),(72,y-2),(94,y+1),(127,y+3),
                       (127,y+9),(99,y+7),(71,y+5),(36,y+3),(0,y+9)),fill=189)
        image=Image.composite(tinted,base,mask)
        d=ImageDraw.Draw(image)
        d.line((18,27,36,24,48,18,53,18,59,15),fill=(105,91,69),width=2)
        d.line((62,61,83,63,90,65,114,68),fill=(121,108,81),width=2)
        d.line((22,108,45,104,57,108,66,105),fill=(111,99,76),width=2)
    image.save(TILES/f"{surface.tile}.png")


def make_details():
    for chapter,paint in (("hickston",town),("fair",fair),("sawmill",timber),
                          ("quarry",quarry),("hub",roads)):
        for site in SITES[chapter]:
            prop=Paint()
            paint(site.name,prop)
            prop.save(site.name)
    for kind,(color,opacity) in WEAR.items():
        stain(kind,color,opacity)
    for group in SURFACES.values():
        for surface in group:
            paint_wall(surface)


if __name__=="__main__":
    make_details()
