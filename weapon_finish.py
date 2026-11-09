"""Localized wear on viewmodel materials, with no changes to silhouette or anchors."""
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image


# name: working material, foreground-to-receiver wear zone, rubbed edge tint,
# deposits. The finish leaves skin, bright cartridges and highlights outside
# the specified material family untouched.
WEAR = {
    "crowbar":("dark",.34,.78,(126,101,80),(69,48,34)),
    "revolver":("cool",.21,.72,(138,142,147),(53,51,49)),
    "shotgun":("cool",.20,.79,(123,132,139),(50,44,35)),
    "crossbow":("dark",.23,.67,(107,105,95),(62,57,42)),
    "rifle":("cool",.36,.73,(127,133,135),(57,59,54)),
    "ripsaw":("cool",.26,.64,(145,135,106),(58,53,39)),
    "armgun":("ochre",.25,.74,(139,142,88),(51,64,38)),
    "tnt":("red",.20,.61,(167,111,77),(86,58,43)),
    "slingblade":("ochre",.38,.70,(136,119,85),(64,51,34)),
    "bottle_launcher":("ochre",.29,.69,(145,107,72),(74,53,39)),
    "riveter":("cool",.43,.72,(143,146,122),(54,60,49)),
    "pressure_gun":("ochre",.40,.68,(148,123,80),(62,95,78)),
}


@lru_cache(maxsize=2)
def material(key):
    name = "weathered_plank_siding" if key=="paper" else "corrugated_iron"
    path = Path(__file__).resolve().parent/"source_art"/"materials"/f"{name}.png"
    im = Image.open(path).convert("L").resize((129,129),Image.Resampling.LANCZOS)
    return np.asarray(im,dtype=np.float32)


def finish_weapon(pixels, name, pose):
    family,mark_x,mark_y,edge,dirt = WEAR[name]
    yy,xx = np.nonzero(pixels[...,3]>=112)
    if not len(xx):
        return
    x0,x1,y0,y1 = xx.min(),xx.max()+1,yy.min(),yy.max()+1
    area = pixels[y0:y1,x0:x1]
    rgb = area[...,:3].astype(np.float32)
    red,green,blue = np.moveaxis(rgb,-1,0)
    luma = rgb @ (.25,.59,.16)
    mask = {
        "dark": (luma<110)&(red<blue+28),
        "cool": (red<blue+13)&(luma<158),
        "red": (red>green*1.29)&(red>blue*1.49),
        "ochre": (red>blue+15)&(green>blue+5)&(luma<146),
    }[family] & (area[...,3]>=112)
    y,x = np.indices(area.shape[:2],dtype=np.float32)
    fx,fy = x/max(1,x1-x0-1),y/max(1,y1-y0-1)
    mark = np.exp(-(((fx-mark_x)*3.8)**2+((fy-mark_y)*4.2)**2))
    scan = material("paper" if name in ("tnt","slingblade") else "metal")
    scratch = scan[(y.astype(int)*7+x.astype(int)*2)%129,(x.astype(int)*5+y.astype(int)*3)%129]
    rubbing = np.clip((scratch-120)*.006,0.,.36)*mark
    varnish = np.clip((110-scratch)*.0041,0.,.34)*mark
    if pose in ("kick","strike","grind_hot"):
        rubbing *= 1.22
    rgb += (np.asarray(edge)-rgb)*rubbing[...,None]
    rgb += (np.asarray(dirt)-rgb)*varnish[...,None]
    # Narrow exposed edges catch light. Dirt stays on recessed faces and grip seams.
    outline = np.roll(area[...,3],-1,axis=0)<112
    sheen = np.clip((luma-45)/75,0,1)*outline*(.10+mark*.19)
    rgb += (np.asarray(edge)-rgb)*sheen[...,None]
    area[...,:3][mask] = np.clip(rgb,0,255).astype(np.uint8)[mask]
