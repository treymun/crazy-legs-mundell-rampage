"""Localized material finishing for the original sprite sets and county crew."""
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from expansion_art import weather

MECHANICAL = {"saucer","skeeter","alien","crawler","lantern"}
WORKWEAR = {"clone","billy","coot","boss","barker","millhand","boilerback","chalk_spitter",
            "rudy","foreman","baron","yard_deputy","bottle_tosser","chain_hand","valve_rat"}
DETAIL = {
    "clone":(.37,.55,(106,111,106)), "billy":(.61,.58,(111,113,110)),
    "coot":(.60,.57,(135,112,77)), "boss":(.44,.57,(96,113,120)),
    "barker":(.61,.59,(118,85,77)), "millhand":(.38,.55,(142,122,78)),
    "boilerback":(.64,.61,(122,132,103)), "chalk_spitter":(.42,.54,(148,136,104)),
    "rudy":(.41,.48,(138,77,57)), "foreman":(.54,.55,(86,111,105)),
    "baron":(.41,.58,(134,93,63)), "yard_deputy":(.46,.59,(117,99,69)),
    "bottle_tosser":(.64,.63,(104,69,66)), "chain_hand":(.45,.58,(99,112,84)),
    "valve_rat":(.49,.60,(102,108,96)),
}
WORK_GRADES = {
    "clone":(78,91,73), "billy":(77,99,130), "coot":(99,104,72), "boss":(120,101,69),
    "barker":(126,68,77), "millhand":(137,113,58), "boilerback":(113,122,84),
    "chalk_spitter":(142,131,96), "rudy":(133,73,52), "foreman":(74,97,89),
    "baron":(132,83,51), "yard_deputy":(102,97,65), "bottle_tosser":(118,72,64),
    "chain_hand":(84,101,77), "valve_rat":(86,105,89),
}


@lru_cache(maxsize=3)
def cloth_plate(material):
    """Reuse the wardrobe plate's fabric folds as a neutral shading source."""
    source = Path(__file__).resolve().parent/"source_art"/"body_plate.png"
    cuts = {"denim":(43,228,110,375),"flannel":(35,44,87,133),"canvas":(129,78,185,145)}
    with Image.open(source) as plate:
        image = plate.crop(cuts[material]).convert("L").resize((64,96),Image.Resampling.LANCZOS)
    fine = np.asarray(image,dtype=np.float32)
    base = np.asarray(image.filter(ImageFilter.GaussianBlur(3.0)),dtype=np.float32)
    return np.clip((fine-base)*.017+(base-np.median(base))*.0035,-.19,.18)


def finish(image, kind, frame, *, sampled=False):
    if kind not in WORKWEAR|MECHANICAL or frame=="down":
        return image
    seed = sum(ord(letter) for letter in kind)
    mechanical = kind in MECHANICAL
    if not sampled:
        image = weather(image,seed,9,"corrugated_iron" if mechanical else "weathered_plank_siding")
    rgba = np.array(image.convert("RGBA"))
    left,top,right,bottom = image.getchannel("A").getbbox()
    height,width = rgba.shape[:2]
    py,px = np.indices((height,width))
    x = (px-left)/max(1,right-left)
    y = (py-top)/max(1,bottom-top)
    rgb = rgba[:,:,:3].astype(np.float32)
    lum = rgb.mean(axis=2)
    light = np.clip((lum-43.)/79.,0.,1.)
    if mechanical:
        # Oxidized rubs follow the trim and shell edge, away from bright emission cels.
        seam = .52+.055*np.cos(x*9.+seed)
        rub = np.exp(-((y-seam)/.082)**2)*np.clip((156.-lum)/83.,0.,1.)
        streak = .55+.45*np.sin(px*.74+py*.18)
        rgb += (rub*streak)[:,:,None]*np.array((9.,5.,-4.))
    else:
        # Cloth and boot grime remain coherent across poses and light directions.
        folds = np.exp(-((y-(.67+.056*np.cos((x-.4)*7.)))/.054)**2)
        fold_rim = np.exp(-((y-(.69+.052*np.cos((x-.4)*7.)))/.037)**2)
        boots = np.clip((y-.80)/.19,0.,1.)*(.40+.43*np.sin(px*.22+py*.36)**2)
        stain = np.exp(-((x-.47)/.28)**2-((y-.69)/.18)**2)*(.35+.30*np.sin(px*.12+py*.14)**2)
        rgb += ((fold_rim*.14-folds*.17-stain*.17)*lum*light)[:,:,None]*np.array((1.06,1.,.94))
        rgb = rgb*(1-boots[:,:,None]*.13)+boots[:,:,None]*np.array((7.,4.,1.))
        material = "denim" if kind in ("clone","billy","coot","millhand","yard_deputy") else (
                   "flannel" if kind in ("rudy","barker","bottle_tosser","chain_hand") else "canvas")
        weave = cloth_plate(material)
        uv_x = ((x*(92 if kind in ("clone","billy") else 69)+seed)%64).astype(int)
        uv_y = ((y*122+seed*.6)%96).astype(int)
        cloth = np.clip((y-.22)*8.,0.,1.)*np.clip((.91-y)*7.,0.,1.)*light
        rgb *= 1.+(cloth*weave[uv_y,uv_x])[:,:,None]
        # Local sun-bleach, seams and rubbing leave each costume its own color read.
        tone = np.asarray(WORK_GRADES[kind],dtype=np.float32)
        flare = (tone-tone.mean())*.28
        shadow = np.clip((lum-45)/50,0.,1.)
        if kind=="billy":
            shadow *= (rgb[:,:,2]>rgb[:,:,0]-.5)
        wash = cloth*shadow*(.55+.45*np.cos(px*.07-py*.17+seed)**2)
        rgb += wash[:,:,None]*flare
        sx,sy,thread = DETAIL[kind]
        patch = Image.new("L",(width,height))
        draw = ImageDraw.Draw(patch)
        w,h = right-left,bottom-top
        cx,cy = left+round(w*sx),top+round(h*sy)
        for i in range(-2,3):
            at = cx+round(i*max(1,w*.025))
            draw.line((at,cy+round(abs(i)*h*.008),at+1,cy+round(h*.022)),fill=110,width=1)
        opacity = np.asarray(patch,dtype=np.float32)/255*light
        rgb = rgb*(1-opacity[:,:,None])+opacity[:,:,None]*thread
    rgba[:,:,:3] = np.clip(rgb,0,255).astype("uint8")
    return Image.fromarray(rgba)
