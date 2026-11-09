"""Original limestone, refinery panels and fixed signs for Stillwater Cut."""
from PIL import Image, ImageDraw
import numpy as np

from expansion_art import ART, TILES, bolts, mounted, panel, sign, sky, weather, wet_surface
from world_art import paint_sign, scan


def stone():
    face = scan("worn_concrete_floor",(160,151,134),1.06,.28).convert("RGB")
    pixels = np.asarray(face).astype(float)
    y,x = np.indices((128,128))
    strata = 16*np.sin(y*.25+.85*np.sin(x*.042))+8*np.sin(y*.082+x*.021)
    cracks = (np.sin(y*.46+x*.022+np.sin(x*.17)*.55)>.90)*15
    seepage = np.maximum(0,np.cos(x*.13+np.sin(y*.047)*.59)-.45)*(13+y*.39)
    pixels += (strata-cracks-seepage)[...,None]
    out = Image.fromarray(np.clip(pixels,0,255).astype("uint8"))
    return weather(out,137,10,"worn_concrete_floor").convert("RGB")


def metal():
    iron = scan("corrugated_iron",(109,112,101),1.52,.38)
    d = ImageDraw.Draw(iron)
    d.rectangle((0,96,127,127),fill="#53564b")
    d.line((0,96,127,96),fill="#8a8063",width=3)
    bolts(d,[(x,103) for x in (6,36,66,96,121)])
    copper = scan("corrugated_iron",(121,78,50),1.28,.36,turn=True)
    d = ImageDraw.Draw(copper)
    for x,y,length in ((14,16,43),(51,23,29),(86,15,52),(113,31,23)):
        d.line((x,y,x-1,y+length-9,x+2,y+length),fill="#617063",width=2)
        d.line((x+1,y+2,x,y+length-12),fill="#758174")
    for x in (21,79,119):
        d.line((x,8,x-1,104),fill="#564537",width=2)
        d.line((x+1,14,x,100),fill="#a4764f")
    for y in (5,105,117):
        d.rectangle((0,y,127,y+8),fill="#604a36",outline="#43382a")
        d.line((1,y+1,126,y+1),fill="#9d825a",width=2)
    bolts(d,[(x,111) for x in (8,32,64,97,118)])
    return weather(iron,114,16,"corrugated_iron"),weather(copper,219,19,"corrugated_iron")


def condenser():
    im = panel((204,235))
    d = ImageDraw.Draw(im)
    for x,y,w,h,leak in ((41,86,62,123,43),(108,49,52,168,31)):
        d.line((x+16,y+h-10,x+13,231),fill="#33312b",width=7)
        d.line((x+w-13,y+h-10,x+w-10,231),fill="#39362a",width=7)
        d.rounded_rectangle((x,y,x+w,y+h),18,fill="#865e3f",outline="#41362b",width=3)
        for offset,color in ((5,"#a07851"),(10,"#bb8d5e"),(20,"#966d4b"),
                             (w-13,"#6d543e"),(w-6,"#4d4a3b")):
            d.line((x+offset,y+20,x+offset,y+h-18),fill=color,width=4)
        for rib in (y+28,y+h-29):
            d.polygon(((x-2,rib),(x+w+1,rib-1),(x+w+1,rib+5),(x+w-8,rib+7),
                       (x+5,rib+8),(x-2,rib+5)),fill="#625747",outline="#473c2c")
            d.line((x+2,rib+2,x+w-2,rib+1),fill="#aa8a61")
            bolts(d,[(x+5,rib+4),(x+w-6,rib+3)])
        d.line((x+23,y+37,x+22,y+h-30),fill="#5d4839",width=2)
        d.line((x+25,y+37,x+24,y+h-30),fill="#ae845d")
        d.polygon(((x+leak-7,y+33),(x+leak+4,y+33),(x+leak+2,y+44),
                   (x+leak-1,y+61),(x+leak-4,y+73),(x+leak-4,y+50)),fill="#617368")
        d.line((x+leak-4,y+35,x+leak-4,y+54,x+leak-8,y+63),fill="#7f8b70",width=2)
        d.line((x+leak+5,y+40,x+leak+4,y+61),fill="#524e3f",width=2)
        d.line((x+9,y+h-43,x+15,y+h-39,x+30,y+h-45),fill="#76563d",width=3)
        d.line((x+10,y+h-39,x+16,y+h-36,x+28,y+h-41),fill="#b58a5f")
    pipe = ((71,85),(71,38),(91,19),(141,19),(143,52))
    d.line(pipe,fill="#493a2a",width=15,joint="curve")
    d.line(pipe,fill="#9c714b",width=10,joint="curve")
    d.line(((67,83),(67,38),(89,16),(142,16)),fill="#b78a63",width=3,joint="curve")
    for seam in (44,65):
        d.rectangle((62,seam,78,seam+6),fill="#5c5748",outline="#413b31")
        d.line((63,seam+1,75,seam+1),fill="#aa9066",width=2)
    d.ellipse((130,34,154,56),fill="#3d3a32",outline="#a47d50",width=2)
    d.ellipse((135,39,150,51),fill="#b7a685",outline="#716146",width=2)
    d.line((143,46,146,42),fill="#71392e",width=2)
    d.line(((159,84),(183,84),(183,221)),fill="#725344",width=12)
    d.line(((160,81),(181,81),(181,217)),fill="#a17a56",width=3)
    d.polygon(((178,177),(190,176),(192,194),(186,219),(177,222),(180,198)),fill="#48463b")
    d.line((180,180,179,194,181,212),fill="#736851",width=2)
    d.rectangle((175,146,190,153),fill="#566359",outline="#383c33")
    bolts(d,[(177,150),(188,150)])
    return weather(im,106,26,"corrugated_iron")


def bottle_rack():
    im = panel((104,48))
    d = ImageDraw.Draw(im)
    for i,(x,y) in enumerate(((11,10),(22,7),(36,6),(44,15),(58,5),(73,10),(85,4))):
        fill = ("#555e41","#625a38","#82664b")[i%3]
        d.rounded_rectangle((x,y+12,x+11,42),3,fill=fill,outline="#343625")
        d.rectangle((x+4,y+2,x+7,y+15),fill=fill,outline="#453e30")
        d.line((x+2,y+19,x+2,38),fill="#aaa07c")
        d.rectangle((x+2,y+22,x+9,y+27),fill="#ada077")
        d.line((x+3,y+2,x+8,y+2),fill="#a28661",width=2)
    d.line((6,44,99,44),fill="#664c34",width=4)
    return weather(im,48,19)


def machinery(bell, active):
    im=panel((102,118))
    d=ImageDraw.Draw(im)
    d.polygon(((17,12),(87,8),(93,99),(84,109),(16,106)),fill="#5a4938",outline="#302925",width=3)
    d.rectangle((23,16,82,103),fill="#6c5b46",outline="#928064",width=2)
    if bell:
        d.line((25,31,77,31),fill="#34342b",width=6)
        d.polygon(((44,42),(58,41),(65,50),(68,65),(76,73),(69,77),(34,77),(30,72),
                   (39,63),(39,52)),fill="#af8d4f" if active else "#8b7048",outline="#372c23",width=2)
        d.line((42,53,39,66,33,72),fill="#d5b579",width=2)
        d.line((56,75,67 if active else 54,103,61 if active else 55,115),fill="#c6b18c",width=4)
    else:
        d.rectangle((31,38,74,93),fill="#333834",outline="#9b8d67",width=3)
        d.polygon(((34,65),(62,58),(74,65),(73,86),(34,86)),fill="#555b50",outline="#252822")
        d.line((45,76,67 if active else 49,44 if active else 57),fill="#af8051",width=7)
        d.line((48,74,65 if active else 49,47 if active else 58),fill="#d19d62",width=2)
        d.rectangle((51,94,67,100),fill="#a7ac74" if active else "#b36648")
    bolts(d,[(x,y) for x in (26,78) for y in (23,97)])
    return weather(im,32 if bell else 73,18,"corrugated_iron")


def feed_delivery():
    plank=scan("weathered_plank_siding",(105,80,61),1.30,.35,turn=True)
    d=ImageDraw.Draw(plank)
    d.rectangle((0,78,127,127),fill="#6d6554")
    for x in range(4,128,17):
        d.line((x,78,x-2,127),fill="#514637",width=2)
    for y in (76,86,122):
        d.line((0,y,127,y),fill="#867b61",width=3)
    weather(plank,73,16).convert("RGB").save(TILES/"feed_wash.png")
    sacks=panel((132,68))
    d=ImageDraw.Draw(sacks)
    for x,y,color in ((17,30,"#928167"),(48,34,"#9a8465"),(78,31,"#897555"),
                       (66,16,"#a3916f"),(26,13,"#b29b70")):
        d.polygon(((x,y+8),(x+8,y+2),(x+34,y),(x+42,y+10),(x+41,y+20),(x+8,y+23)),
                  fill=color,outline="#594a39",width=2)
        d.line((x+8,y+4,x+6,y+18),fill="#c0a77b",width=2)
        d.line((x+11,y+12,x+32,y+9),fill="#876b4d",width=2)
    for x,y in ((108,48),(115,52),(102,51),(119,57),(112,60),(121,49)):
        d.ellipse((x,y,x+4,y+3),fill="#bba077")
    weather(sacks,94,22,"worn_concrete_floor").save(ART/"split_feed_sacks.png")


def paint():
    stone().save(TILES/"quarry_face.png")
    dust = wet_surface("brown_mud_03",(128,117,96),112).convert("RGB")
    dry = scan("asphalt_02",(128,115,91),1.02,.20).convert("RGB")
    Image.blend(dust,dry,.48).save(TILES/"quarry_dust.png")
    iron,copper=metal()
    iron.convert("RGB").save(TILES/"quarry_iron.png")
    copper.convert("RGB").save(TILES/"quarry_copper.png")
    feed_delivery()
    pavilion=scan("weathered_plank_siding",(95,59,62),1.2,.19).convert("RGB")
    border=ImageDraw.Draw(pavilion)
    border.rectangle((2,8,125,120),outline="#2c2323",width=4)
    border.rectangle((6,14,121,113),outline="#b19368",width=3)
    paint_sign(pavilion,"PRIZE PAVILION",(9,30,110,72),"#efd5a5")
    weather(pavilion,107,7).convert("RGB").save(TILES/"fair_marquee.png")
    wet_surface("worn_concrete_floor",(105,99,77),152).convert("RGB").save(TILES/"quarry_shed.png")
    sky(((35,38,45),(102,95,88)),411,True).save(TILES/"quarry_sky.png")
    plates = {
        "quarry_scale": ("STILLWATER CUT","TRUCK SCALE"),
        "quarry_bottling": ("BOTTLING WORKS","NO OPEN FLAMES"),
        "quarry_safety": ("SAMPLE LOCKER","CHECK THE LOOSE TIN"),
        "quarry_ledger": ("WEIGH TICKET","TARE BEFORE PROOF"),
        "quarry_blast": ("DUST TRAP","MIND THE FALSE WALL"),
        "survey_peg": ("COUNTY LINE","PIN 19"),
        "service_detour": ("SERVICE TURN","FEED TRUCKS ONLY"),
        "powder_notice": ("DRY POWDER","KEEP SMOKING OUTSIDE"),
        "packing_notice": ("COLD LOCKER","LATCH STICKS IN DAMP"),
        "delivery_plaque": ("SACK DROP","NO CREDIT IN THE RAIN"),
        "mill_overflow": ("SPILLWAY","FOLLOW THE DRY MARKS"),
    }
    for key,(title,subtitle) in plates.items():
        plaque = sign(title,subtitle,"#594b38","#f0dbac")
        if key in ("quarry_scale","survey_peg"):
            plaque = mounted(plaque)
        plaque.save(ART/f"{key}.png")
    condenser().save(ART/"quarry_tower.png")
    bottle_rack().save(ART/"quarry_bottles.png")
    for stem,bell in (("fair_bell",True),("mill_brake",False)):
        for suffix,active in (("off",False),("on",True)):
            machinery(bell,active).save(ART/f"{stem}_{suffix}.png")


if __name__ == "__main__":
    paint()
