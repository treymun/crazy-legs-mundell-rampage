"""Small still-life cels with distinct spent poses."""
from pathlib import Path

from PIL import Image, ImageDraw

from world_art import scan


ART=Path(__file__).resolve().parent/"assets"/"art"


def cel(kind, spent):
    im=Image.new("RGBA",(68,66))
    d=ImageDraw.Draw(im)
    if kind=="bottles":
        if spent:
            for x,y in ((8,57),(21,50),(28,59),(42,54),(51,58),(55,48)):
                d.polygon(((x,y),(x+10,y+3),(x+2,y-8)),fill="#5d704d",outline="#373c2b")
                d.line((x+2,y-6,x+5,y-1),fill="#a1b487")
        else:
            for x,y,h,tone in ((7,23,39,"#4c5939"),(25,13,50,"#777548"),(44,27,35,"#5f704b")):
                d.polygon(((x+4,y),(x+10,y),(x+10,y+8),(x+14,y+14),(x+15,y+h),
                           (x,y+h),(x,y+16),(x+4,y+8)),fill=tone,outline="#2d3425")
                d.line((x+4,y+14,x+3,y+h-4),fill="#a0a477",width=2)
                d.rectangle((x+3,y+h-15,x+13,y+h-6),fill="#a18d5f")
    elif kind=="cans":
        for i,(x,y) in enumerate(((7,30),(25,24),(45,36)) if not spent else ((8,49),(26,53),(46,48))):
            w,h=(16,60-y) if not spent else (17,11)
            d.rectangle((x,y+2,x+w,y+h),fill=("#90715a","#786954","#854f3a")[i],outline="#3d3028",width=2)
            d.ellipse((x,y-1,x+w,y+6),fill="#9e9784",outline="#41392e",width=2)
            d.line((x+4,y+7,x+4,y+h-2),fill="#c0a383",width=2)
            d.line((x+5,y+h-9,x+12,y+h-9),fill="#c7ad78")
    elif kind=="prize":
        if spent:
            d.polygon(((7,55),(52,40),(61,52),(12,64)),fill="#917859",outline="#4c3b2f",width=3)
            d.arc((15,49,39,61),30,285,fill="#9a4d3d",width=3)
        else:
            d.polygon(((11,59),(7,18),(18,9),(49,8),(59,16),(61,59)),fill="#a88b5e",outline="#392b24",width=3)
            d.ellipse((18,17,51,51),outline="#5c4633",width=3)
            d.ellipse((23,21,47,47),outline="#a44e3a",width=4)
            d.ellipse((31,30,40,40),fill="#7c4134")
            d.line((15,48,26,37),fill="#baa879")
    elif kind=="scrap":
        positions=((9,39,36,60),(29,48,61,62),(14,54,46,64)) if spent else ((10,49,50,9),(13,15,57,47),(21,61,56,26))
        for i,(x,y,a,b) in enumerate(positions):
            d.line((x,y,a,b),fill="#3c3026",width=10)
            d.line((x,y,a,b),fill=("#77634a","#8a6d4f","#6f5340")[i],width=7)
            d.line((x+2,y+1,a-2,b),fill="#a28b67",width=1)
    elif kind=="belt":
        d.polygon(((5,9),(60,9),(62,59),(7,62)),fill="#635548",outline="#342d25",width=3)
        for x,y in ((19,21),(47,49)):
            d.ellipse((x-10,y-10,x+10,y+10),fill="#8a7961",outline="#38322c",width=3)
            d.ellipse((x-3,y-3,x+3,y+3),fill="#3a3029")
        points=((10,29),(35,50),(26,60),(43,59)) if spent else ((10,25),(40,56),(56,49),(23,14),(10,25))
        d.line(points,fill="#2e2925",width=5)
        if spent:
            d.line((15,42,26,41,17,48),fill="#ae7951",width=2)
    else:
        d.line(((12,57),(17,30),(26,22),(43,22),(47,13),(47,4)),fill="#302c24",width=14)
        d.line(((12,57),(17,30),(26,22),(43,22),(47,13),(47,4)),fill="#79664e",width=9)
        d.line(((11,52),(15,32),(23,23),(43,23)),fill="#ac8f65",width=2)
        d.ellipse((30,14,48,29),outline="#625044",width=3)
        if spent:
            d.line((33,28,35,41,34,53),fill="#777e67",width=3)
            d.line((41,27,44,44,40,56),fill="#95a184",width=2)
            d.ellipse((25,56,51,62),fill="#47554f")
    alpha=im.getchannel("A")
    material="weathered_plank_siding" if kind in ("scrap","prize") else "corrugated_iron"
    shade=scan(material,(132,116,91),1.16,.22).resize(im.size).convert("RGBA")
    im=Image.composite(Image.blend(im,shade,.26),im,alpha)
    im.putalpha(alpha)
    return im


def make_scenery():
    for kind in ("bottles","cans","prize","scrap","belt","pipe"):
        for state in ("whole","spent"):
            cel(kind,state=="spent").save(ART/f"scenery_{kind}_{state}.png")
    lead=Image.new("RGBA",(54,48))
    ink=ImageDraw.Draw(lead)
    for i in range(4):
        ink.ellipse((8+i,15+i,43-i,35-i),outline="#91754f",width=2)
    ink.line(((12,23),(7,13),(10,9),(17,12)),fill="#957b56",width=3)
    ink.line(((41,27),(46,34),(49,31)),fill="#b3a376",width=3)
    ink.rectangle((15,9,21,13),fill="#a7a494")
    lead.save(ART/"item_pa_patch.png")


if __name__=="__main__":
    make_scenery()
