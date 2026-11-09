"""Reproducible painted and photo-textured county road art."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from world_art import paint_sign, scan

ROOT = Path(__file__).resolve().parent / "assets"


def paint_road_markers():
    for key,title,subtitle,tint in (
        ("hickston","HICKSTON","TOWN ROAD",(96,72,48)),
        ("fair","COUNTY FAIR","MIDWAY ROAD",(111,68,60)),
        ("mill","BLACKWATER","LOGGING ROAD",(77,91,79)),
        ("quarry","STILLWATER","QUARRY HAUL ROAD",(100,89,69)),
    ):
        marker = scan("weathered_plank_siding",tint,1.04,.24).resize((138,36)).convert("RGBA")
        ink = ImageDraw.Draw(marker)
        ink.rectangle((1,1,136,34),outline="#352c22",width=2)
        ink.line((4,4,132,4),fill="#aa8c63")
        for x in (5,132):
            ink.ellipse((x-1,16,x+2,19),fill="#3f3327")
            ink.point((x,16),fill="#b99a69")
        paint_sign(marker,title,(10,6,118,12),"#f2d9a4")
        paint_sign(marker,subtitle,(10,22,118,8),"#d9c198")
        marker.save(ROOT/"art"/f"hub_{key}_marker.png")


def make_crossroads():
    patch = scan("asphalt_02",(82,81,73),1.34,.27).convert("RGB")
    paint = ImageDraw.Draw(patch)
    paint.line(((0,23),(17,26),(33,21),(67,25),(101,18),(127,20)),fill="#7c7464",width=2)
    paint.line(((0,26),(23,31),(45,29),(77,36),(110,29),(127,28)),fill="#383530",width=2)
    paint.line(((42,31),(47,44),(43,59),(53,69),(51,96)),fill="#2f2f2a",width=2)
    patch.save(ROOT/"tiles"/"hub_patch.png")
    concrete = scan("worn_concrete_floor",(114,105,87),1.14,.28).convert("RGB")
    paint = ImageDraw.Draw(concrete)
    for x,y,ex in ((3,18,6),(27,3,9),(55,11,4),(78,0,8),(107,13,9)):
        paint.polygon(((x,y),(x+ex,y),(x+ex//2,72+ex),(x+1,94)),fill="#5e5849")
    paint.line(((0,18),(127,20)),fill="#aaa084",width=2)
    concrete.save(ROOT/"tiles"/"hub_service_wall.png")
    scan("forest_ground_04",(79,77,67),1.19,.36).convert("RGB").save(ROOT/"tiles"/"hub_runoff.png")
    screen = scan("weathered_plank_siding",(112,98,73),1.23,.27).convert("RGB")
    ink = ImageDraw.Draw(screen)
    ink.rectangle((3,3,124,124),outline="#786a51",width=3)
    ink.line(((1,67),(127,70)),fill="#b39369",width=2)
    ink.line(((49,1),(49,126)),fill="#9b8564",width=2)
    ink.line(((20,117),(67,87)),fill="#7e644d",width=3)
    screen.save(ROOT/"tiles"/"hub_screen.png")

    tower = scan("corrugated_iron",(117,96,70),1.29,.29).convert("RGB")
    ink = ImageDraw.Draw(tower)
    for y in (3,120):
        ink.line((0,y,127,y),fill="#ae8f66",width=2)
        ink.line((0,y+3,127,y+3),fill="#514234",width=3)
    for x,extent in ((18,14),(31,36),(89,29),(102,17),(119,38)):
        ink.line((x,13,x-2,14+extent),fill="#79583b",width=2)
        ink.point((x+1,11),fill="#d0ad7b")
    tower.save(ROOT/"tiles"/"hub_tank_shell.png")
    label = Image.new("RGBA",(129,30))
    ink = ImageDraw.Draw(label)
    ink.text((8,3),"COUNTY  WATER",font=ImageFont.load_default(size=14),fill="#dec597",
             stroke_width=1,stroke_fill="#4a3e31")
    ink.text((49,19),"NO. 2",font=ImageFont.load_default(size=9),fill="#beac83")
    label.save(ROOT/"art"/"hub_tank_label.png")
    (ROOT/"art"/"hub_tank.png").unlink(missing_ok=True)
    board = scan("weathered_plank_siding",(100,78,53),1.21,.20).resize((131,31)).convert("RGBA")
    ink = ImageDraw.Draw(board)
    ink.rectangle((1,1,129,29),outline="#43372a",width=2)
    ink.text((9,5),"COUNTY ROAD DEPT.",font=ImageFont.load_default(size=12),
             fill="#e1ca94",stroke_width=1,stroke_fill="#4b3b28")
    ink.text((28,18),"REPORT WASHOUTS",font=ImageFont.load_default(size=8),fill="#bbac7b")
    board.save(ROOT/"art"/"hub_road_dept.png")
    paint_road_markers()

    dust = Image.new("RGBA",(83,97))
    ink = ImageDraw.Draw(dust)
    for layer in range(8):
        ink.polygon(((15+layer,5+layer*3),(40-layer,6+layer*3),
                     (70-layer*2,87-layer*2),(8+layer*2,87-layer*2)),
                    fill=(202,175,120,18+layer*7))
    for x,y,s in ((19,35,1),(25,51,2),(37,67,1),(46,56,1),(20,74,1),(43,79,1),(32,63,1)):
        ink.rectangle((x,y,x+s,y+s),fill=(228,198,142,79))
    dust.save(ROOT/"art"/"hub_dust.png")


if __name__ == "__main__":
    make_crossroads()
