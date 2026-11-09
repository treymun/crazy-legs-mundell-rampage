import os, math
os.environ["SDL_VIDEODRIVER"]="dummy"; os.environ["SDL_AUDIODRIVER"]="dummy"
import pygame as pg
from PIL import Image
from main import Desktop
from game import Controls
from weapons import NAMES, BOWLING, KEG, COW, TEAT
d=Desktop(smoke=True); d.start("hickston"); g=d.game
for e in g.enemies: e.dormant=True
shots=[]
def snap(tag):
    g.draw(d.canvas,grade=d.palette.grade); 
    shots.append(Image.frombytes("RGB",d.canvas.get_size(),pg.image.tobytes(d.canvas,"RGB")))
for w in (BOWLING,KEG,COW,TEAT):
    a=g.armory; a.owned[w]=True; a.loaded[w]=1 if w!=TEAT else 30; a.reserve[w]=5; a.select(w,g)
    for _ in range(20): g.tick(1/60,Controls())
    snap(NAMES[w])
    g.tick(1/60,Controls(fire=True))
    for _ in range(5): g.tick(1/60,Controls())
    snap(NAMES[w]+"_fire")
# view scenery: face the nearest interactable
props=[p for p in g.world.scenery if p.id.startswith("x2")]
print(len(props),"new interactables on hickston;",[(p.kind,round(p.x),round(p.y)) for p in props][:8])
p0=props[0]; pl=g.player; pl.x,pl.y=p0.x-1.6,p0.y
if g.world.blocked(pl.x,pl.y,.2): pl.x,pl.y=p0.x+1.6,p0.y
pl.angle=math.atan2(p0.y-pl.y,p0.x-pl.x)
for _ in range(5): g.tick(1/60,Controls())
snap("scenery_before")
g.hit_scenery(p0)
for _ in range(10): g.tick(1/60,Controls())
snap("scenery_after")
W,H=shots[0].size; sheet=Image.new("RGB",(W*2,H*5))
for i,s in enumerate(shots): sheet.paste(s,((i%2)*W,(i//2)*H))
sheet=sheet.resize((W*4,H*10),Image.NEAREST); sheet.save("bot_shots/new_features.png"); print(sheet.size)
