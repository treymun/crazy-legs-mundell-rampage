"""Paint the county road plates on the same boards that carry them in the world."""
from pathlib import Path

from PIL import Image, ImageDraw
import pygame as pg

from pixel_type import label
from world_art import paint_sign, scan

PLATES = {
    "hickston": ("HICKSTON", (69,62,50)),
    "fair": ("COUNTY FAIR", (77,53,54)),
    "sawmill": ("BLACKWATER", (56,68,61)),
    "quarry": ("STILLWATER CUT", (83,61,43)),
    "hub": ("COUNTY CROSSROADS", (67,61,48)),
}


def paint():
    folder = Path(__file__).resolve().parent / "assets" / "tiles"
    for name, (words, wood) in PLATES.items():
        plank = scan("weathered_plank_siding",wood,1.26,.17).convert("RGB")
        ink = ImageDraw.Draw(plank)
        ink.rectangle((3,9,124,118),outline="#1f1c18",width=3)
        ink.rectangle((6,17,121,110),outline="#9a7d57",width=2)
        for x in (10,117):
            for y in (28,99):
                ink.ellipse((x-2,y-4,x+2,y+4),fill="#2b2520")
                ink.point((x-1,y-2),fill="#a49372")
        typeface = label(words,"body",(238,219,175))
        face = Image.frombytes("RGBA",typeface.get_size(),pg.image.tobytes(typeface,"RGBA"))
        width = min(102, 12+8*len(words))
        face = face.resize((width,66),Image.Resampling.NEAREST)
        left = (128-width)//2
        plank.paste((27,22,18),(left+1,34),face.getchannel("A"))
        plank.paste(face,(left,30),face)
        plank.save(folder/f"route_{name}.png")

    gate = scan("weathered_plank_siding",(79,65,50),1.32,.20).convert("RGB")
    hardware = ImageDraw.Draw(gate)
    for y in (3,30,89,122):
        hardware.rectangle((1,y,126,y+5),fill="#484039",outline="#302820")
    hardware.polygon(((3,108),(125,18),(125,38),(3,126)),fill="#8b6f50",outline="#4d3c30")
    for x in (8,39,70,101):
        hardware.rectangle((x,45,x+19,61),fill="#ad8553",outline="#392b21")
        hardware.line((x+3,49,x+17,49),fill="#dfb079",width=2)
    gate.save(folder/"route_closed.png")
    stripe=scan("asphalt_02",(95,89,74),1.18,.24).convert("RGB")
    paint=ImageDraw.Draw(stripe)
    paint.polygon(((0,60),(22,61),(51,59),(96,63),(127,60),(127,68),
                   (91,71),(66,66),(25,70),(0,69)),fill="#ab9d7c")
    for x,y in ((4,61),(14,66),(26,64),(32,67),(47,63),(59,64),(76,67),(94,64),(107,67),(116,63)):
        paint.rectangle((x,y,x+3,y+1),fill="#847964")
    stripe.save(folder/"route_threshold.png")
    directory = scan("weathered_plank_siding",(82,70,52),1.22,.20).resize((240,84)).convert("RGBA")
    frame = ImageDraw.Draw(directory)
    frame.rectangle((1,1,238,82),outline="#2e251d",width=3)
    frame.rectangle((5,5,234,78),outline="#9d8055",width=2)
    back = directory.copy()
    wood = ImageDraw.Draw(back)
    for y in (30,58):
        wood.line((4,y,235,y),fill="#362e24",width=2)
        wood.line((4,y+2,235,y+2),fill="#9a7956")
    for x in (35,205):
        wood.rectangle((x-5,4,x+5,82),fill="#766146",outline="#3c3228",width=2)
        for y in (14,67):
            wood.ellipse((x-2,y-2,x+2,y+2),fill="#3b322b")
    frame.rectangle((10,11,114,71),fill="#3d493e",outline="#6f7358")
    frame.rectangle((125,11,229,71),fill="#4f4231",outline="#806749")
    chalk = "#f2dfb2"
    for x,heading,names in ((11,-1,("HICKSTON","FAIR")),(126,1,("MILL","QUARRY"))):
        anchor = x+16 if heading<0 else x+87
        frame.polygon([(anchor+dx*heading,41+dy) for dx,dy in
                       ((-8,-4),(1,-4),(1,-10),(12,0),(1,10),(1,4),(-8,4))],
                      fill=chalk,outline="#211b17")
        for y,words in zip((18,47),names):
            paint_sign(directory,words,(x+(31 if heading<0 else 5),y,67,17),chalk)
    stand=Image.new("RGBA",(240,114))
    posts=ImageDraw.Draw(stand)
    for x in (30,201):
        posts.rectangle((x,54,x+9,113),fill="#71604b",outline="#453829",width=2)
        posts.line((x+2,67,x+2,109),fill="#ad8f65")
    reverse = stand.copy()
    reverse.alpha_composite(back)
    reverse.save(folder.parent/"art"/"hub_directory_back.png")
    stand.alpha_composite(directory)
    stand.save(folder.parent/"art"/"hub_directory.png")
    small=Image.new("RGBA",(99,103))
    painted=ImageDraw.Draw(small)
    painted.rectangle((48,26,56,102),fill="#665745",outline="#3c352b",width=2)
    painted.line((50,53,50,96),fill="#968168",width=2)
    painted.polygon(((2,4),(86,4),(97,28),(86,50),(2,50)),fill="#625342",outline="#2c2420",width=3)
    painted.line((4,8,85,8,91,26),fill="#ad8d60",width=2)
    back = small.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    wood = ImageDraw.Draw(back)
    wood.line((15,28,94,28),fill="#483c2e",width=2)
    wood.rectangle((42,8,50,47),fill="#796248",outline="#413628")
    back.save(folder.parent/"art"/"hub_road_stake_back.png")
    ink_surface=label("HUB >","body",(238,217,177))
    ink=Image.frombytes("RGBA",ink_surface.get_size(),pg.image.tobytes(ink_surface,"RGBA"))
    ink=ink.resize((64,20),Image.Resampling.NEAREST)
    small.paste(ink,(11,16),ink)
    small.save(folder.parent/"art"/"hub_road_stake.png")


if __name__ == "__main__":
    paint()
