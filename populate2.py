"""Reachable, seeded placement of interactables and new pickups on every level."""
import math, zlib
from collections import deque
import numpy as np
from scenery import Reactive

KINDS=(("tv",.75,.0),("cancan",.40,.0),("vending",1.5,.0),("toilet",.82,.0),("window",1.2,.0),("jukebox",1.4,.0),("cancan",.40,.0))
LEVEL_WEAPON={"hickston":"teat_gun","fair":"powder_keg"}
LEVEL_AMMO={"hickston":("milk_ammo","milk_ammo","bowling_ammo"),"fair":("milk_ammo","keg_ammo","keg_ammo"),
            "sawmill":("milk_ammo","bowling_ammo","cow_ammo"),"quarry":("milk_ammo","cow_ammo","keg_ammo")}

def reachable(world, start):
    h,w=world.solid.shape; sx,sy=int(start[0]),int(start[1])
    dist={(sx,sy):0}; q=deque([(sx,sy)])
    while q:
        x,y=q.popleft()
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if 0<=nx<w and 0<=ny<h and (nx,ny) not in dist and world.solid[ny,nx]<0:
                dist[(nx,ny)]=dist[(x,y)]+1; q.append((nx,ny))
    return dist

def populate(game):
    world=game.world; level=game.level
    dist=reachable(world,level.spawn)
    rng=np.random.default_rng(zlib.crc32(level.id.encode()))
    taken=[(e.x,e.y) for e in game.enemies]+[(x,y) for _,x,y in game.pickups]+[(p.x,p.y) for p in game.props]
    taken+=[(tx+.5,ty+.5) for tx,ty in world.fuel_drums]+[level.spawn]
    for door in world.doors: taken.append(door.center)
    for st in getattr(world,"stations",()): taken.append((st.x,st.y))
    def free(x,y,gap):
        return (not world.blocked(x,y,.34) and all(math.hypot(x-t[0],y-t[1])>=gap for t in taken))
    cells=[(c,d) for c,d in dist.items() if d>=4]
    order=rng.permutation(len(cells))
    placed=[]; want=len(KINDS)+1 if level.id!="crossroads" else len(KINDS)
    # interactables
    existing=tuple(world.scenery)
    extra=[]
    indoor_kinds={"tv","toilet","vending","jukebox","window"}
    for pass_indoor in (True,False):
        for i in order:
            if len(extra)>=want: break
            (cx,cy),d=cells[i]; x,y=cx+.5,cy+.5
            kind,height,z=KINDS[len(extra)%len(KINDS)]
            roofed=world.roof[cy,cx]>0
            if pass_indoor and (kind in indoor_kinds)!=bool(roofed) : continue
            if not free(x,y,3.2): continue
            extra.append(Reactive(f"x2-{level.id}-{len(extra)}",kind,x,y,height,z,.30))
            taken.append((x,y))
    world.scenery=existing+tuple(extra)
    # new weapon / ammo pickups at spread-out distances
    far=sorted(cells,key=lambda c:c[1])
    def spot(frac):
        for (cx,cy),d in far[int(len(far)*frac):]:
            if free(cx+.5,cy+.5,1.6): return cx+.5,cy+.5
        return None
    adds=[]
    if level.id in LEVEL_WEAPON: adds.append((LEVEL_WEAPON[level.id],.45))
    for k,name in enumerate(LEVEL_AMMO.get(level.id,("milk_ammo",))):
        adds.append((name,.30+.22*k))
    for name,frac in adds:
        s=spot(frac)
        if s: game.pickups.append((name,*s)); taken.append(s)
    # whiskey and cow pies beside existing booze and food
    for name,x,y in list(game.pickups):
        pick={"beer":"whiskey","moonshine":"cowpie"}.get(name)
        if pick:
            for ox,oy in ((.8,0),(-.8,0),(0,.8),(0,-.8)):
                if not world.blocked(x+ox,y+oy,.3):
                    game.pickups.append((pick,x+ox,y+oy)); break

