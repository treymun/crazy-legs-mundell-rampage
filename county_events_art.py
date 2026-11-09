"""Original cutouts for the fair gallery and the county's paper trail."""
from PIL import Image, ImageDraw

from county_detail_art import Paint, COPPER, GREEN, PAPER, RED, TIN, WOOD
from expansion_art import ART, sign, weather
from county_events import HUB_DISPATCH
from world_art import paint_sign, scan


def interiors():
    for name in ("dispatch","tickets","break","bunk"):
        panel=Paint()
        d=panel.ink
        if name=="dispatch":
            panel.box(13,31,111,55,GREEN,4)
            panel.papers(22,42,52,30,"OUT")
            d.rectangle((83,40,108,69),fill="#5d4a3a",outline="#392e27")
            for x,y in ((88,46),(96,52),(103,46)):
                d.arc((x-3,y-2,x+3,y+6),-20,270,fill="#d0ac72",width=2)
                d.line((x+1,y+5,x+1,y+13),fill="#9e7d50")
            panel.label((80,73),"TOW",size=10)
        elif name=="tickets":
            panel.box(9,52,121,30,WOOD,5)
            panel.box(19,40,53,28,TIN,4)
            panel.label((28,46),"TILL",size=11)
            for x in range(28,65,7):
                d.point((x,61),fill="#b99d73")
            panel.papers(82,33,36,36,"5C")
            panel.reel(110,60,12,PAPER)
            panel.bottle(74,73,29,RED)
        elif name=="break":
            panel.box(10,56,124,25,WOOD,4)
            panel.box(28,31,61,41,RED,6)
            panel.tube(((41,32),(45,22),(67,22),(73,31)),4,"#5e4d3c")
            panel.label((39,47),"LUNCH",size=10)
            panel.bottle(101,73,37,TIN,"#947454")
            panel.spanner(107,72,20,-5)
        else:
            panel.box(12,61,119,25,GREEN,5)
            panel.form("polygon",((19,61),(29,32),(96,30),(119,45),(113,64)),PAPER)
            for x in range(34,101,12):
                d.line((x,39,x-4,60),fill="#8c7b55",width=2)
            panel.tube(((28,35),(22,59),(28,69)),4,"#8d6443")
            panel.bottle(118,73,35,COPPER)
            panel.label((49,68),"SHIFT B",size=9)
        panel.save(f"room_{name}")
        (ART/f"detail_room_{name}.png").replace(ART/f"county_room_{name}.png")


def backstop():
    tile=scan("weathered_plank_siding",(124,92,60),1.11,.25,turn=True).resize((120,139))
    d=ImageDraw.Draw(tile)
    d.rectangle((2,2,117,136),outline="#4b3527",width=3)
    for x in (7,31,60,88,113):
        d.line((x,36,x+1,123),fill="#534330",width=2)
    for y in (29,120):
        d.rectangle((3,y,117,y+8),fill="#514b37",outline="#332b23")
        for x in (8,108):
            d.ellipse((x,y+2,x+3,y+5),fill="#ba9b6b")
    paint_sign(tile,"PRIZE ALLEY",(8,8,102,14),"#deb882")
    paint_sign(tile,"NO LIVE AMMO",(8,126,102,8),"#ccab75")
    weather(tile,413,9,"weathered_plank_siding").save(ART/"county_gallery_backstop.png")


def dispatch_props():
    tag = Image.new("RGBA",(49,40))
    d = ImageDraw.Draw(tag)
    d.arc((13,3,35,25),17,354,fill="#a59a78",width=3)
    d.polygon(((17,18),(32,12),(41,18),(43,34),(20,38),(12,27)),
              fill="#b79659",outline="#574434",width=2)
    d.ellipse((16,21,20,25),fill="#503e2d")
    d.line((21,30,26,29,26,22,33,20,34,29),fill="#7b3f2d",width=2)
    weather(tag,112,8,"corrugated_iron").save(ART/"county_dispatch_tag.png")
    trunk = Image.new("RGBA",(72,45))
    d = ImageDraw.Draw(trunk)
    d.polygon(((2,13),(23,4),(60,5),(70,15),(66,40),(14,43)),fill="#4e6570",outline="#30383a",width=2)
    d.line((3,16,17,25,67,18),fill="#7e8c84",width=2)
    d.line((16,24,16,42),fill="#323d43",width=3)
    d.line((23,8,35,18,36,41),fill="#5c4534",width=4)
    d.line((53,8,59,17,58,39),fill="#715942",width=4)
    d.polygon(((38,26),(54,23),(55,34),(38,36)),fill="#aa8d5d",outline="#64553c")
    d.line((40,28,51,26),fill="#544b3a")
    weather(trunk,215,10,"weathered_plank_siding").save(ART/"county_dispatch_trunk.png")


def creek_shadow():
    # Flatten the project's own tree canopy into a directional floor cutout.
    with Image.open(ART/"prop_tree.png") as source:
        alpha = source.convert("RGBA").getchannel("A")
    x0,y0,x1,y1 = alpha.getbbox()
    crown = alpha.crop((x0,y0,x1,y0+round((y1-y0)*.74))).resize((71,29),Image.Resampling.BICUBIC)
    crown = crown.rotate(-14,Image.Resampling.BICUBIC,expand=True)
    shadow = Image.new("RGBA",crown.size,(16,19,15,0))
    shadow.putalpha(crown.point(lambda value: round(value*.42)))
    shadow.save(ART/"county_creek_shadow.png")


def bake():
    sign("TIN ROOSTER","4 HITS / BORROWED ROUNDS","#41382a","#f3db9f",
         size=(154,55)).save(ART/"county_gallery_sign.png")
    sign("DRY BOARDS","POND BYPASS","#453b2d","#e5cc9a",
         size=(123,45)).save(ART/"county_mill_bypass.png")
    target = Image.new("RGBA",(40,40))
    d = ImageDraw.Draw(target)
    d.polygon(((9,33),(5,28),(5,21),(10,18),(15,22),(19,21),(23,10),(28,8),
               (28,4),(31,7),(33,4),(34,8),(38,13),(32,16),(32,25),(28,34),
               (23,35),(23,38),(13,38),(14,34)),fill="#a76242",outline="#332419",width=2)
    d.ellipse((12,20,29,34),fill="#cfb27c",outline="#52422d",width=2)
    d.ellipse((17,24,25,31),fill="#a75c3b",outline="#6d442b")
    d.point((31,11),fill="#f9db9c")
    weather(target,91,9,"corrugated_iron").save(ART/"county_gallery_target.png")
    note = Image.new("RGBA",(49,36))
    d = ImageDraw.Draw(note)
    d.polygon(((3,4),(40,2),(47,7),(45,33),(2,35)),fill="#b89562",outline="#493723")
    d.line((7,10,36,8),fill="#695039",width=2)
    for y in (16,20,24,28):
        d.line((7,y,39-y%5,y-2),fill="#7f6041")
    d.rectangle((30,21,42,29),outline="#8c4837")
    weather(note,137,8,"old_linoleum_flooring_01").save(ART/"county_note.png")
    for index,(label,_,_) in enumerate(HUB_DISPATCH):
        sign("COUNTY DISPATCH",label,"#514034" if index%2 else "#424a3d","#ecd0a0",
             size=(134,52)).save(ART/f"county_dispatch_{index}.png")
    interiors()
    backstop()
    dispatch_props()
    creek_shadow()
    for kind,shape,tone in (
        ("chips",((1,6),(2,3),(7,1),(9,2),(7,5),(3,8)),"#bd9761"),
        ("powder",((3,2),(7,2),(9,5),(7,9),(3,8),(1,5)),"#c9bda4"),
        ("soil",((2,5),(4,2),(8,3),(9,7),(6,9),(3,8)),"#866442"),
    ):
        speck=Image.new("RGBA",(10,10))
        d=ImageDraw.Draw(speck)
        d.polygon(shape,fill=tone,outline="#514236")
        d.point((4,4),fill="#d4b486")
        speck.save(ART/f"fx_{kind}.png")


if __name__=="__main__":
    bake()
