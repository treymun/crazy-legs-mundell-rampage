"""County road material layout and bounded surface effects."""
from functools import lru_cache
from math import cos, pi, sin

import numpy as np


TOWER_X, TOWER_Y = 19.05, 45.16
HUB_WIDTH = 50


def tank_faces(tile):
    """Fixed segmented tank silhouette."""
    for lo,hi,width,depth,tint in ((2.98,3.14,.84,.66,.76),(3.14,4.26,1.21,.90,1.05),
                                  (4.26,4.42,1.06,.79,.92),(4.42,4.54,.78,.58,.89)):
        rim = [(TOWER_X+width*cos(i*pi/6),TOWER_Y+depth*sin(i*pi/6)) for i in range(12)]
        for i,((x,y),(a,b)) in enumerate(zip(rim,rim[1:]+rim[:1])):
            yield x,y,a,b,tile,tint*(.84+.16*sin((i+.5)*pi/6)),lo,hi,11


def service_road(world):
    """Build inside the old hub perimeter, away from the gate approaches."""
    world.room(10, 46, 21, 47, "hub_patch", 11, light=1.05)
    world.room(17, 48, 24, 50, "hub_patch", 11, light=1.04)
    world.room(21, 47, 24, 47, "hub_patch", 11, light=1.04)
    world.room(20, 51, 28, 54, "hub_patch", 11, light=1.04)
    world.room(10, 44, 14, 45, "shoulder", 11, light=.98)
    world.room(27, 41, 30, 43, "tracks", 11, light=1.01)
    world.room(38, 47, 42, 49, "quarry_dust", 11, light=1.08)
    world.room(27, 49, 34, 50, "hub_runoff", 11, light=1.04)
    world.ground[49:51, 27:35] = -.14
    world.room(26, 49, 26, 50, "shoulder", 11, light=1.04)
    world.room(35, 49, 35, 50, "shoulder", 11, light=.96)
    world.room(29, 43, 33, 47, "porch", 11, 2.24, .90, "joists")
    world.wall(29, 42, 33, 42, "barn", 2.54)
    world.wall(34, 43, 34, 47, "mill_tin", 2.32)
    world.wall(28, 43, 28, 45, "barn", 2.41)


def tower_shadow(x, y, z, time, detail):
    """Project a fixed tank and four legs from a low directional light."""
    if detail == 2:
        # A small immutable light volume keeps the still-mode footprint off the
        # per-frame trigonometry path, including when it crosses the low wall.
        ix,iy,iz = (np.rint((value-base)*16).astype(np.intp)
                    for value,base in ((x,17.),(y,43.),(np.broadcast_to(z,x.shape),0.)))
        lut = still_shadow()
        valid = (ix>=0)&(ix<lut.shape[0])&(iy>=0)&(iy<lut.shape[1])&(iz>=0)&(iz<lut.shape[2])
        result = np.ones(x.shape,dtype=np.float32)
        result[valid] = lut[ix[valid],iy[valid],iz[valid]]
        return result
    gust = sin(time * .83) * (.13 if detail == 0 else .045)
    lx, ly = 1.15 + gust, .73 + gust*.32
    rx, ry = x-TOWER_X, y-TOWER_Y
    tank_x, tank_y = rx - lx*(3.83-z), ry - ly*(3.83-z)
    tank = np.clip((1.18 - np.hypot(tank_x/1.31,tank_y/.92)) * 3.4, 0., 1.)
    dx,dy = rx+lx*z,ry+ly*z
    vector = lx*lx+ly*ly
    posts = np.zeros_like(tank)
    for ax,ay in ((-.72,-.52),(.72,-.52),(-.72,.52),(.72,.52)):
        qx,qy = dx-ax,dy-ay
        h = np.clip((qx*lx+qy*ly)/vector, 0., 3.55)
        d = np.abs(qx-h*lx)+np.abs(qy-h*ly)
        posts = np.maximum(posts,np.clip((.21-d)*5,0.,.80))
    # Scrubby growth below the tank breaks up the edge as the wind moves.
    fringe = np.clip((1.1-np.hypot((rx-2.72)/1.70,(ry-1.59)/.86))*1.55,0.,1.)
    stems = np.clip((np.sin(rx*14.3+ry*5.1+gust*8)-.25)*1.2,0.,1.)
    return 1.-.36*np.maximum(np.maximum(tank,posts),fringe*stems*.51)


@lru_cache(maxsize=1)
def still_shadow():
    x,y,z = np.ogrid[17.:27.0625:.0625,43.:51.0625:.0625,0.:1.0625:.0625]
    return tower_shadow(x,y,z,0.,0).astype(np.float32)


def running_water(gravel, x, y, time, detail):
    if detail == 2:
        time = 0.
    edge = np.clip(np.minimum(y-49.,51.-y)*1.9,0.,1.)
    drift = time * (1.9 if detail == 0 else .72)
    line = np.sin(13.*y+1.7*np.sin(x*2.1-drift)+.8*np.sin(x*4.3-drift*1.6))
    streak = np.sin(x*6.7-drift*3.0 + .8*np.sin(y*22.))
    ripples = np.clip((line + .36*streak-.63)*.62,0.,.62)*edge
    mix = (edge*.38+ripples*.52)[:,None]
    water = np.asarray((88,120,132)) + ripples[:,None]*np.asarray((154,150,123))
    return np.rint(gravel*(1.-mix)+water*mix).astype(np.uint8)


def screen_holes(u, v):
    # Large areas of old hardware cloth alternate with boarded repairs.
    margin = (u>=7)&(u<=120)&(v>=7)&(v<=119)
    bars = ((u>=48)&(u<=54))|((v>=67)&(v<=73))
    patched = (v>95)&(u<42+v//5)
    wires = (((u+v)%17)<2)|(((u-v)%18)<2)
    return margin & ~bars & ~patched & ~wires
