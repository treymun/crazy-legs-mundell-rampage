"""Bake the photo-backed player's work clothes and eight-way mirror poses."""
from functools import lru_cache
import math

import numpy as np
from PIL import Image, ImageDraw, ImageOps

from actor_models import INK, LEATHER, STEEL, SpriteCamera, band, fabric, joint, trouser, volume
from face_pipeline import ART, BODY_PLATE, digitize, wanted_art
from weapon_models import Mesh, render


SIZE = (120,214)
DENIM = (68,88,106,"denim",.04)
SEAM = fabric(116,125,126)
FLANNEL = (137,84,61,"flannel",.04)
SKIN = (153,112,82,"skin",.08)
CAP = fabric(100,106,75)
HAT_MESH = fabric(127,114,80)
BRASS = fabric(165,130,65)
RAG = fabric(142,72,51)


@lru_cache(maxsize=1)
def wardrobe():
    return Image.open(BODY_PLATE).convert("RGBA").resize((104,198),Image.Resampling.LANCZOS)


def front(head, step):
    image=Image.new("RGBA",(144,256))
    plate=wardrobe()
    pixels=np.array(plate)
    yy,xx=np.indices(pixels.shape[:2])
    leg=np.where(xx<plate.width/2,1,-1)
    swing=np.clip((yy-100)/89.,0.,1.)*leg*step
    u=np.clip(np.rint(xx+swing*7),0,plate.width-1).astype(int)
    v=np.clip(np.rint(yy+swing*5),0,plate.height-1).astype(int)
    pixels=pixels[v,u].copy()
    # Canvas scuffs at the thighs and knees are graded into the photo folds.
    colors=pixels[:,:,:3].astype(np.float32)
    denim=(colors[:,:,2]>colors[:,:,0]+4)&(yy>35)
    patch=np.exp(-((xx-32)/19)**2-((yy-136)/24)**2)
    colors[denim] += (patch[denim]*np.clip(colors[denim].mean(axis=1)/80,0,1))[:,None]*[23,15,7]
    pixels[:,:,:3]=np.clip(colors,0,255).astype(np.uint8)
    image.alpha_composite(Image.fromarray(pixels),(20,53))
    d=ImageDraw.Draw(image)
    d.polygon(((57,58),(63,60),(73,59),(83,56),(78,65),(71,75),(68,69),(59,66)),
              fill="#713c30",outline="#462b25")
    d.line((60,63,70,67,77,62),fill="#ab6850",width=2)
    d.polygon(((49,170),(61,170),(64,179),(62,190),(48,188),(46,180)),
              fill="#6b6552",outline="#3c3b32")
    for x,y in ((49,173),(54,173),(59,173),(49,186),(54,187),(60,187)):
        d.point((x,y),fill="#b0a17a")
    # These loops sit on the bib; the portrait and beard remain unobscured.
    for x in (78,82,86):
        d.line((x,110,x,117),fill="#9c7247",width=2)
        d.point((x,116),fill="#c2a06b")
    head=head.resize((39,50),Image.Resampling.LANCZOS)
    tint=np.array(head)
    tint[:,:,:3]=np.clip(tint[:,:,:3]*[.90,.88,.84]+[3,4,4],0,255)
    image.alpha_composite(Image.fromarray(tint),(47,12+abs(step)))
    d=ImageDraw.Draw(image)
    d.polygon(((47,29),(48,19),(54,13),(64,11),(74,12),(82,17),(85,25),(78,28),(65,27)),
              fill="#606746",outline="#333b2d")
    d.polygon(((47,26),(62,23),(78,24),(87,27),(86,30),(73,30),(61,29),(50,31)),
              fill="#47533d",outline="#2d3528")
    d.line((54,17,64,14,75,15,80,20),fill="#8d8a61")
    d.rectangle((58,17,69,22),fill="#ada072",outline="#625a41")
    d.line((60,19,67,19),fill="#776747")
    return digitize(image,SIZE)


def fieldhand(step):
    m=Mesh()
    sway=.037*step
    for side in (-1,1):
        x=side*.18
        shift=side*step
        toe=(x,.14+max(0,shift)*.040,shift*.25)
        knee=(x+side*.027,.49,shift*.14-.065)
        hip=(x+sway,.94,.033)
        volume(m,[(toe[1]-.10,x,toe[2]-.058,.121,.175),
                  (toe[1]-.05,x,toe[2]-.042,.127,.164),
                  (toe[1]+.016,x,toe[2]+.015,.093,.114)],LEATHER,n=14)
        band(m,(x-.087,toe[1]-.06,toe[2]-.153),(x+.087,toe[1]-.06,toe[2]-.154),INK,.017)
        trouser(m,toe,knee,hip,(.106,.13,.149),DENIM)
        band(m,(x+side*.09,.205,toe[2]+.01),(knee[0]+side*.102,.53,knee[2]),SEAM,.012)
        if side<0:
            band(m,(knee[0]-.085,.48,knee[2]-.11),(knee[0]+.071,.56,knee[2]-.11),
                 fabric(137,127,93),.036)
    volume(m,[(.80,sway,.017,.293,.168),(.98,sway-.022,.019,.324,.184),
              (1.07,sway,.020,.306,.18),(1.30,sway+.015,.019,.348,.190),
              (1.43,sway+.037,.034,.339,.161),(1.50,sway+.029,.037,.341,.155),
              (1.60,sway,.042,.188,.106)],FLANNEL,n=16)
    volume(m,[(.87,sway,.019,.313,.18),(1.01,sway,.020,.299,.181),
              (1.18,sway,.031,.227,.188),(1.29,sway,.040,.183,.173)],DENIM,n=16)
    for side in (-1,1):
        band(m,(sway+side*.205,1.54,.04),(sway+side*.096,1.26,.202),DENIM,.052)
        band(m,(sway+side*.108,1.29,.209),(sway+side*.143,1.08,.191),SEAM,.016)
        band(m,(sway+side*.216,1.53,-.063),(sway+side*.133,1.26,-.181),DENIM,.048)
        m.block(sway+side*.133,1.266,-.209,.054,.044,.034,BRASS)
        hand=(sway+side*.22,1.123,-.264-.03*side)
        elbow=(sway+side*.414,1.224,.023)
        cuff=(sway+side*.359,1.17,-.105)
        m.link(((sway+side*.32,1.467,.011),elbow,cuff),(.112,.090,.069),FLANNEL)
        band(m,elbow,cuff,fabric(111,70,53),.073)
        m.tube(cuff,hand,.063,.057,SKIN,n=12)
        joint(m,hand,(.073,.059,.062),SKIN)
    m.block(sway+.169,1.04,.181,.122,.139,.033,fabric(84,93,101))
    band(m,(sway-.149,.98,.197),(sway-.134,.90,.185),LEATHER,.035)
    volume(m,[(1.52,sway,.030,.105,.087),(1.584,sway,.019,.119,.098)],RAG,n=12)
    joint(m,(sway,1.638,.012),(.084,.101,.081),SKIN)
    volume(m,[(1.604,sway,-.035,.062,.073),(1.69,sway,.014,.105,.098),
              (1.788,sway,.02,.119,.108),(1.897,sway,.031,.090,.095)],SKIN,n=16)
    joint(m,(sway,1.682,-.070),(.092,.083,.068),fabric(108,91,76))
    joint(m,(sway,1.765,-.083),(.026,.041,.060),SKIN)
    for side in (-1,1):
        joint(m,(sway+side*.107,1.745,.009),(.029,.040,.026),SKIN)
    volume(m,[(1.813,sway,.031,.121,.117),(1.866,sway,.027,.127,.120),
              (1.916,sway,.034,.086,.101)],HAT_MESH,n=18)
    m.loft([(-.218,sway,1.816,.098,.014),(-.068,sway,1.842,.126,.014)],CAP,box=True)
    band(m,(sway-.075,1.817,.136),(sway+.081,1.811,.138),LEATHER,.019)
    # The front-facing long gun is occluded naturally when the body turns away.
    start=(sway-.29,1.035,-.241)
    breech=(sway+.07,1.149,-.307)
    muzzle=(sway+.51,1.327,-.359)
    m.tube(start,breech,.062,.041,LEATHER,n=11)
    for dx in (0.,.041):
        m.tube((breech[0]+dx,*breech[1:]),(muzzle[0]+dx,*muzzle[1:]),.025,.021,STEEL,n=10)
    return m


def make_player():
    head=Image.open(ART/"face_idle_center.png").convert("RGBA")
    head=head.crop(head.getbbox())
    for step in (-1,0,1):
        straight=front(head,step)
        straight.save(ART/f"player_front_{step}.png")
        if not step:
            straight.save(ART/"full_body_player.png")
            wanted_art(straight).save(ART/"wanted_poster.png")
        mesh=fieldhand(step)
        for name,yaw in (("quarter",-.72),("side",-1.55),("away",-2.35),("back",-math.pi)):
            model=render(mesh,SpriteCamera(yaw)).crop((99,23,221,163))
            if name=="quarter":
                face=head.resize((24,29),Image.Resampling.LANCZOS)
                pixels=np.array(face)
                pixels[:,:,:3]=np.clip(pixels[:,:,:3]*[.80,.77,.73]+[5,5,4],0,255)
                model.alpha_composite(Image.fromarray(pixels),(55+round(step*2),11))
                d=ImageDraw.Draw(model)
                d.line((57+step*2,13,69+step*2,12,78+step*2,15),fill="#555d41",width=3)
            digitize(model,SIZE).save(ART/f"player_{name}_{step}.png")


if __name__=="__main__":
    from world_art import screen_art, wanted_tile

    make_player()
    screen_art(ART)
    wanted_tile().save(ART.parent/"tiles"/"wanted.png")
