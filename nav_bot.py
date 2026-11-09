"""Navigation bot: BFS path to the nearest live hostile, fires only with line of sight.
Run: python nav_bot.py [seconds]   -> prints per-level kills, damage, deaths, stuck count."""
import math, os, sys
os.environ.setdefault("SDL_VIDEODRIVER","dummy"); os.environ.setdefault("SDL_AUDIODRIVER","dummy")
from collections import deque
from campaign import BY_ID
from game import Controls
from main import Desktop
from weapons import SHOTGUN, RIFLE, REVOLVER

def path(world, a, b, limit=6000):
    h,w=world.solid.shape; s=(int(a[0]),int(a[1])); t=(int(b[0]),int(b[1]))
    prev={s:None}; q=deque([s]); n=0
    while q and n<limit:
        c=q.popleft(); n+=1
        if c==t: break
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
            nx,ny=c[0]+dx,c[1]+dy
            if not(0<=nx<w and 0<=ny<h) or (nx,ny) in prev or world.solid[ny,nx]>=0: continue
            if dx and dy and (world.solid[c[1],nx]>=0 or world.solid[ny,c[0]]>=0): continue
            prev[(nx,ny)]=c; q.append((nx,ny))
    if t not in prev: return []
    out=[]; c=t
    while c: out.append((c[0]+.5,c[1]+.5)); c=prev[c]
    return out[::-1]

def run(seconds=60, god=False):
    d=Desktop(smoke=True); rows=[]
    for level in BY_ID:
        d.start(level); g=d.game; p=g.player; g.cheats.god=god
        for i in range(len(g.armory.owned)): g.armory.owned[i]=True
        g.armory.reserve=[40]*len(g.armory.reserve)
        for i in (SHOTGUN,RIFLE,REVOLVER): g.armory.loaded[i]=max(g.armory.loaded[i],2)
        g.armory.select(RIFLE,g)
        stuck=0; last=(p.x,p.y); route=[]; repath=0; dmg0=p.health
        for step in range(60*seconds):
            live=[e for e in g.enemies if e.alive and e.hostile]
            c=Controls()
            if live:
                t=min(live,key=lambda e:math.hypot(e.x-p.x,e.y-p.y))
                dist=math.hypot(t.x-p.x,t.y-p.y); los=g.world.visible(p.x,p.y,t.x,t.y)
                if not t.alerted and dist<14 and los: t.wake(g,p.x,p.y)
                if los and dist<9:
                    want=math.atan2(t.y-p.y,t.x-p.x); c.forward=0. if dist<3.5 else .6
                    c.fire=True
                else:
                    repath-=1
                    if repath<=0 or not route: route=path(g.world,(p.x,p.y),(t.x,t.y)); repath=45
                    while len(route)>1 and math.hypot(route[0][0]-p.x,route[0][1]-p.y)<.55: route.pop(0)
                    tgt=route[0] if route else (t.x,t.y); want=math.atan2(tgt[1]-p.y,tgt[0]-p.x); c.forward=1.
                diff=(want-p.angle+math.pi)%math.tau-math.pi
                c.turn=max(-.07,min(.07,diff))
                if c.fire and abs(diff)>.3: c.fire=False
            if step%20==0:
                for door in g.world.doors:
                    if not door.opened and not door.secret and math.hypot(door.center[0]-p.x,door.center[1]-p.y)<1.6:
                        g.toggle_door(door,True)
            g.tick(1/60,c)
            if p.health<=0: break
            if step%120==0:
                if math.hypot(p.x-last[0],p.y-last[1])<.25: stuck+=1
                last=(p.x,p.y)
        rows.append((level,g.kills,g.total_kills,max(0,p.health),int(g.clock),stuck,p.health<=0))
    return rows

if __name__=="__main__":
    secs=int(sys.argv[1]) if len(sys.argv)>1 else 60
    print("level      kills        hp  secs stuck died")
    for lvl,k,tk,hp,cl,st,dead in run(secs): print(f"{lvl:10s} {k:3d}/{tk:<3d}  {hp:5d} {cl:5d} {st:5d} {dead}")
