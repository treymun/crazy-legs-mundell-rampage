"""Hand-lettered notices and silhouette props for the chapter districts."""
from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFont

from expansion_art import sign
from world_art import scan


ART=Path(__file__).resolve().parent/"assets"/"art"
SIGNS={
    "town_service":("COUNTY SERVICE","STOCK REGISTRY EAST","#56483a","#e7d4a6"),
    "town_tires":("SECOND CHANCE","USED TIRES / COLD BEER","#4c5040","#e7c797"),
    "town_feed":("HOG WEIGH-IN","NO ARGUMENTS ON SCALES","#71533e","#ead8ae"),
    "town_pen_off":("FEED AND BOARD","BRING YOUR OWN BUCKET","#573f34","#e7c096"),
    "town_pen_on":("BESSIE'S HOME","BACK TO REGULAR RATIONS","#575747","#e7cfa8"),
    "town_hatch_off":("FEED HATCH","SLIDE BOLT","#4b483e","#e9cd9b"),
    "town_hatch_on":("FEED HATCH","BOLT FREE","#534e3a","#d3c093"),
    "town_registry":("STOCK REGISTRY","PASTURE KEYS INSIDE","#46514a","#efe1b7"),
    "town_register":("STEEL PASTURE KEY","CHECK THE STOCK REGISTRY","#575245","#e4ca9e"),
    "town_legacy_key":("STEEL PASTURE KEY","AT THE BARN FEED SCALE","#575245","#e4ca9e"),
    "town_tow":("COUNTY TOW LOT","COLLECT BEFORE SUNDOWN","#5e4e43","#d9c6a0"),
    "town_radio":("COUNTY WIRELESS","REPORT STRAY LIGHTS","#534837","#ead8a9"),
    "town_rail":("FEED RAILHEAD","PARK OUTSIDE THE PEN","#5f4738","#dfc196"),
    "fair_freight":("BACKSTAGE FREIGHT","PA BOOTH VIA SIDESHOW","#644a43","#eed9a6"),
    "fair_receipts":("RAFFLE OFFICE","NO CREDIT ON A WIN","#72564b","#edcba0"),
    "fair_sideshow":("STRONGMAN ALLEY","DO NOT FEED THE PRIZES","#664449","#f1ce91"),
    "fair_rope":("QUEUE STARTS HERE","NO RUNNING FROM PRIZES","#455956","#e8ce9d"),
    "fair_pa_off":("BACKSTAGE PA","PATCH JACK B","#5a453e","#f1d8ae"),
    "fair_pa_on":("PA OFF AIR","LAST SHOW CANCELLED","#52463d","#dec7a1"),
    "mill_sort":("GREEN CHAIN SORT","DRY KILNS AHEAD","#4a584d","#e0d0a6"),
    "mill_kiln":("DRY KILNS","KEEP THE FLAPS SHUT","#594e45","#e7c48d"),
    "mill_belt_off":("KILN BELT","CUT POWER AT THE BOX","#575346","#e8d1a0"),
    "mill_belt_on":("BELT CUT","LOCK OUT THE KILN","#49423a","#d7bc83"),
    "mill_rain":("RAIN STORAGE","STACK ABOVE WATER","#424e4d","#e4cfab"),
    "mill_ledger":("DRY STACK OFFICE","COUNT WET BOARDS TWICE","#484b3e","#e7cb99"),
    "quarry_cut":("LOWER CUT ROAD","COPPER RECOVERY EAST","#635044","#e8d8ae"),
    "quarry_danger":("WATCH FOR CHALK","MASKS IN THE OFFICE","#644b3a","#ebd3a2"),
    "quarry_terrace":("LIMESTONE BENCH","LOADED WAGONS ONLY","#5f5547","#eee0b9"),
    "quarry_wash":("BOTTLE WASH","CLEAR A PATH TO DRAIN","#654e3a","#eed0a1"),
    "quarry_condenser_off":("COPPER RECOVERY","DIVERT BEFORE BOTTLING","#594737","#ead2a2"),
    "quarry_condenser_on":("FLOW DIVERTED","COOLING LINE / NO TAPS","#4d4d41","#dfc497"),
    "quarry_latch_off":("WASH CARTS","LIFT LATCH","#595346","#e7d1a5"),
    "quarry_latch_on":("WASH CARTS","WAY OPEN","#53594a","#ead5a8"),
    "quarry_weight":("CHECK WEIGHT","WET STONE COUNTS","#645440","#decba2"),
}


def workstations():
    font = ImageFont.load_default(size=13)
    dial = scan("worn_concrete_floor",(109,97,72),1.14,.24).resize((148,89)).convert("RGBA")
    ink = ImageDraw.Draw(dial)
    ink.rectangle((2,2,145,86),outline="#4a3d2e",width=3)
    ink.ellipse((12,12,77,78),fill="#453b32",outline="#302923",width=4)
    ink.ellipse((21,20,68,70),fill="#b19b69",outline="#776442",width=2)
    for mark in range(11):
        a = (.77+mark*.15)*math.pi
        ink.line((45+19*math.cos(a),45+19*math.sin(a),45+23*math.cos(a),45+23*math.sin(a)),fill="#493729",width=2)
    ink.line((45,46,54,27),fill="#7d3e2c",width=3)
    ink.ellipse((41,42,49,49),fill="#503c2e")
    ink.text((85,22),"HOG",font=font,fill="#e9c68c")
    ink.text((85,39),"SCALE",font=font,fill="#e9c68c")
    ink.text((83,63),"COUNTY 4",font=ImageFont.load_default(size=9),fill="#513a2c")
    dial.save(ART/"wing_town_scale.png")

    case = scan("weathered_plank_siding",(119,73,57),1.18,.27).resize((152,111)).convert("RGBA")
    ink = ImageDraw.Draw(case)
    ink.rectangle((3,3,148,107),outline="#4b332c",width=3)
    ink.rectangle((9,10,142,85),fill="#3b3b31",outline="#a07b54",width=2)
    ink.line((15,72,132,72),fill="#746044",width=2)
    with Image.open(ART/"pig_0.png") as source:
        pig = source.convert("RGBA")
        pig = pig.crop(pig.getchannel("A").getbbox()).resize((104,57),Image.Resampling.LANCZOS)
    case.alpha_composite(pig,(27,21))
    extra = pig.crop((0,0,39,36)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    case.alpha_composite(extra,(103,22))
    ink.rectangle((86,16,90,79),fill="#554532")
    ink.line((94,23,120,18),fill="#998967")
    ink.text((14,89),"THE DOUBLE  HOG",font=font,fill="#edc690")
    case.save(ART/"wing_fair_double_hog.png")

    rollers = scan("corrugated_iron",(104,113,91),1.31,.25).resize((189,61)).convert("RGBA")
    ink = ImageDraw.Draw(rollers)
    ink.rectangle((1,5,187,57),outline="#3f4335",width=3)
    ink.rectangle((7,13,181,45),fill="#393b30")
    for i,x in enumerate(range(14,176,18)):
        y = 29+int(math.sin(i*2.5)*3)
        ink.ellipse((x-5,y-6,x+6,y+6),fill="#717565",outline="#968968",width=2)
        ink.point((x,y),fill="#b39a70")
        ink.arc((x-7,y-9,x+8,y+10),25,154,fill="#463b30",width=2)
    ink.line((4,52,181,50),fill="#ae9870",width=2)
    rollers.save(ART/"wing_mill_sort_rollers.png")

    wash = scan("corrugated_iron",(117,100,73),1.27,.30).resize((162,104)).convert("RGBA")
    ink = ImageDraw.Draw(wash)
    ink.rectangle((2,2,159,102),outline="#493729",width=3)
    ink.line(((13,19),(42,19),(42,39),(134,39),(134,13)),fill="#4c372b",width=12)
    ink.line(((13,18),(42,18),(42,37),(134,37),(134,13)),fill="#986944",width=7)
    for x,y in ((25,61),(55,63),(85,60),(117,63)):
        ink.line((x,40,x,y),fill="#765e49",width=6)
        ink.ellipse((x-11,y-5,x+12,y+18),fill="#4d4635",outline="#988261",width=3)
        ink.arc((x-10,y-4,x+9,y+13),40,163,fill="#b49466",width=2)
        ink.line((x+2,y+15,x+4,y+23),fill="#60736b",width=2)
    ink.text((12,83),"COLD  WASH  /  REJECTS",font=font,fill="#d8bc88")
    wash.save(ART/"wing_quarry_wash_rack.png")


def make_wings():
    for key,parts in SIGNS.items():
        sign(*parts).save(ART/f"wing_{key}.png")
    still=Image.new("RGBA",(114,128))
    ink=ImageDraw.Draw(still)
    outline = "#312820"
    # Repairs change direction around the vessel instead of marching in uniform rows.
    ink.line(((31,38),(29,18),(54,17),(54,9),(89,9),(89,67),(99,78),(98,115)),
             fill=outline,width=13)
    ink.line(((31,38),(29,18),(54,17),(54,9),(89,9),(89,67),(99,78),(98,115)),
             fill="#8d6542",width=8)
    ink.ellipse((11,27,76,70),fill="#9d6a47",outline=outline,width=3)
    ink.polygon(((11,47),(14,99),(30,111),(60,111),(73,100),(76,48)),
                fill="#a17452",outline=outline,width=3)
    ink.rectangle((18,108,29,125),fill="#4c3e31")
    ink.rectangle((58,108,67,125),fill="#4c3e31")
    alpha=still.getchannel("A")
    tone=scan("corrugated_iron",(131,99,66),1.08,.25).resize(still.size).convert("RGBA")
    still=Image.composite(Image.blend(still,tone,.58),still,alpha)
    still.putalpha(alpha)
    ink=ImageDraw.Draw(still)
    ink.arc((12,31,76,69),0,155,fill="#b68b56",width=3)
    ink.arc((14,77,72,110),-1,162,fill="#725742",width=3)
    ink.arc((14,83,70,113),15,170,fill="#6b6450",width=4)
    for points in (((19,62),(20,77),(23,83),(23,97)),((62,61),(62,80),(60,85),(61,106)),
                   ((86,61),(84,77),(93,84),(94,108)),((39,43),(42,50),(37,65),(37,81))):
        ink.line(points,fill="#5d6957",width=3)
    ink.ellipse((34,48,55,69),fill="#504335",outline="#322b26",width=2)
    ink.ellipse((39,52,51,65),fill="#d1bc8b")
    ink.line((45,60,49,55),fill="#743f31",width=2)
    still.save(ART/"wing_quarry_still.png")
    for key in ("town_pen","fair_pa","mill_belt","quarry_condenser"):
        (ART/f"wing_{key}.png").unlink(missing_ok=True)
    workstations()


if __name__=="__main__":
    make_wings()
