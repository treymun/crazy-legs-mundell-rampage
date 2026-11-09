"""Rampage 2.0 content art + audio: four weapons, items, projectiles, interactables.
Everything is drawn/synthesised in code (original work)."""
import math, wave
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parent; ART=ROOT/"assets"/"art"; WAV=ROOT/"assets"/"wav"
RATE=22050
OL="#2a1d16"

def hand(d, x, y, s=1.0):
    d.ellipse((x-9*s,y-6*s,x+9*s,y+7*s),fill="#b9825f",outline=OL)
    d.rectangle((x-4*s,y+4*s,x+16*s,y+14*s),fill="#9a6a4c",outline=OL)

def canvas(): return Image.new("RGBA",(320,120),(0,0,0,0))

def bowling(pose):
    im=canvas(); d=ImageDraw.Draw(im)
    lift={"idle":0,"kick":8,"recover":3,"open":14,"eject":18,"load":10,"close":4}.get(pose,0)
    cx,cy=232,92+lift
    d.ellipse((cx-22,cy-22,cx+22,cy+22),fill="#23303a",outline=OL,width=2)
    d.ellipse((cx-17,cy-18,cx+3,cy-2),fill="#3d5260")
    for ox,oy in ((-4,-7),(5,-10),(1,-1)): d.ellipse((cx+ox-2,cy+oy-2,cx+ox+2,cy+oy+2),fill="#0f151a")
    hand(d,cx+12,cy+22)
    return im

def keg(pose):
    im=canvas(); d=ImageDraw.Draw(im)
    lift={"idle":0,"kick":8,"recover":3,"open":12,"eject":14,"load":8,"close":3}.get(pose,0)
    x,y=212,64+lift
    d.rectangle((x,y,x+44,y+50),fill="#8a5a34",outline=OL,width=2)
    for yy in (y+10,y+38): d.rectangle((x,yy,x+44,yy+4),fill="#4b4036",outline=OL)
    for xx in (x+11,x+22,x+33): d.line((xx,y+2,xx,y+48),fill="#6b4426")
    d.rectangle((x+18,y+17,x+34,y+30),fill="#d8c48e",outline=OL); d.text((x+20,y+19),"TNT",fill="#a02a1a")
    d.line((x+22,y,x+26,y-10),fill="#3a2d22",width=2)
    if pose in("idle","recover"): d.ellipse((x+23,y-14,x+29,y-8),fill="#f4b84a" if pose=="idle" else "#fff0b0")
    hand(d,x+8,y+52); hand(d,x+40,y+50)
    return im

def cow(pose):
    im=canvas(); d=ImageDraw.Draw(im)
    lift={"idle":0,"kick":10,"recover":4,"open":16,"eject":20,"load":10,"close":4}.get(pose,0)
    x,y=140,70+lift
    d.polygon(((x,y+6),(x+110,y),(x+118,y+16),(x+10,y+28)),fill="#6b4a2e",outline=OL)
    d.rectangle((x+104,y-4,x+124,y+20),fill="#3c3a36",outline=OL,width=2)
    if pose in("idle","kick","recover"):
        d.ellipse((x+110,y-6,x+132,y+14),fill="#f2ece0",outline=OL)
        d.ellipse((x+116,y-3,x+124,y+4),fill="#2c2620"); d.polygon(((x+130,y-4),(x+135,y-9),(x+133,y))),
    d.rectangle((x+20,y+22,x+34,y+36),fill="#4a4036",outline=OL)
    hand(d,x+28,y+40)
    return im

def teat(pose):
    im=canvas(); d=ImageDraw.Draw(im)
    lift={"idle":0,"kick":3,"recover":1,"open":10,"eject":13,"load":7,"close":2}.get(pose,0)
    x,y=166,36+lift
    # Galvanized milking can, pressure gauge and a hose feeding the udder pump.
    d.rounded_rectangle((x,y+8,x+40,y+62),7,fill="#8d9894",outline=OL,width=2)
    d.rectangle((x+4,y+15,x+36,y+19),fill="#bcc5be")
    d.line((x+9,y+24,x+9,y+57),fill="#6d7874",width=2)
    d.line((x+31,y+24,x+31,y+57),fill="#aeb8b1",width=2)
    d.rectangle((x+8,y+30,x+32,y+44),fill="#d8c48e",outline=OL)
    d.text((x+10,y+33),"MILK",fill="#8a2a1a")
    d.rectangle((x+5,y+2,x+35,y+9),fill="#5a6662",outline=OL)
    d.ellipse((x+15,y-9,x+31,y+7),fill="#e4ddbd",outline=OL,width=2)
    d.line((x+23,y-4,x+27,y+1),fill="#8a2a1a",width=2)
    d.arc((x+15,y-9,x+31,y+7),210,330,fill="#6a5a3a")
    # Ribbed hose loops forward to a brass valve and a stubby spray nozzle.
    d.line((x+36,y+50,x+55,y+40,x+75,y+50,x+92,y+42),fill="#3d3a36",width=7,joint="curve")
    d.line((x+36,y+48,x+55,y+38,x+75,y+48,x+92,y+40),fill="#6f6a62",width=2)
    d.rectangle((x+88,y+34,x+104,y+50),fill="#9a7a3c",outline=OL,width=2)
    d.ellipse((x+96,y+38,x+110,y+50),fill="#c9a85e",outline=OL)
    d.rectangle((x+108,y+40,x+120,y+48),fill="#5a6662",outline=OL)
    # The udder is the pump bulb: four teats feed the pressure line.
    d.ellipse((x+48,y+42,x+88,y+72),fill="#e7c0b0",outline=OL,width=2)
    d.arc((x+54,y+46,x+82,y+66),200,340,fill="#c98e86")
    for i in range(4):
        tx=x+55+i*8
        d.rounded_rectangle((tx,y+68+i%2*2,tx+5,y+82),2,fill="#c98e86",outline=OL)
    if pose=="kick":
        for i,dy in enumerate((-2,2,6)):
            d.ellipse((x+112,y+42+dy,x+120,y+50+dy),fill="#f4f0e8",outline="#c9c2b0")
    hand(d,x+6,y+44)
    hand(d,x+50,y+64)
    return im

POSES=("idle","kick","recover","open","eject","load","close")
def make_weapons():
    for name,fn in (("bowling_ball",bowling),("powder_keg",keg),("cow_launcher",cow),("teat_gun",teat)):
        for p in POSES: fn(p).save(ART/f"gun_{name}_{p}.png")

def make_items():
    def item(name,fn):
        im=Image.new("RGBA",(48,48)); fn(ImageDraw.Draw(im)); im.save(ART/f"item_{name}.png")
    def whiskey(d):
        d.rounded_rectangle((16,18,32,42),3,fill="#9a5c1c",outline=OL,width=2)
        d.rectangle((20,8,28,19),fill="#8e5a1a",outline=OL); d.rectangle((19,6,29,10),fill="#3a2a1e",outline=OL)
        d.rectangle((17,26,31,36),fill="#e6d2a0",outline=OL); d.text((19,27),"XXX",fill="#7a2a1a")
    def pie(d):
        d.ellipse((9,24,39,42),fill="#5a3b1e",outline=OL,width=2)
        d.ellipse((13,18,35,34),fill="#6b4724",outline=OL); d.ellipse((18,11,30,24),fill="#7a5530",outline=OL)
        for p in ((15,40),(30,38),(23,42)): d.ellipse((p[0]-2,p[1]-1,p[0]+2,p[1]+2),fill="#8a6a40")
        for sx,sy in ((14,10),(33,12),(24,5)): d.line((sx,sy,sx+2,sy-4),fill="#c9c27a",width=1)
    def ball(d):
        d.ellipse((10,12,38,40),fill="#23303a",outline=OL,width=2); d.ellipse((15,16,23,23),fill="#4a6070")
        for p in ((22,22),(28,19),(25,28)): d.ellipse((p[0]-2,p[1]-2,p[0]+2,p[1]+2),fill="#0f151a")
    def kegi(d):
        d.rectangle((12,14,36,42),fill="#8a5a34",outline=OL,width=2)
        d.rectangle((12,20,36,23),fill="#4b4036"); d.rectangle((12,34,36,37),fill="#4b4036")
        d.rectangle((18,25,30,31),fill="#d8c48e"); d.line((24,14,27,6),fill=OL,width=2)
    def cowi(d):
        d.rectangle((8,16,40,34),fill="#6b4a2e",outline=OL,width=2); d.ellipse((26,10,44,28),fill="#f2ece0",outline=OL)
        d.ellipse((31,14,36,19),fill="#2c2620")
    def teati(d):
        d.ellipse((8,16,38,40),fill="#e7c0b0",outline=OL,width=2)
        for x in (14,21,28): d.rounded_rectangle((x,36,x+4,45),2,fill="#c98e86",outline=OL)
    def teatammo(d):
        d.rounded_rectangle((12,10,36,42),6,fill="#e8e4d4",outline=OL,width=2); d.rectangle((12,18,36,28),fill="#3a6aa8")
        d.text((16,18),"MILK",fill="#f4f0e0")
    for n,f in (("whiskey",whiskey),("cowpie",pie),("bowling_ball",ball),("powder_keg",kegi),("cow_launcher",cowi),
                ("teat_gun",teati),("bowling_ammo",ball),("keg_ammo",kegi),("cow_ammo",cowi),("milk_ammo",teatammo)):
        item(n,f)

def make_projectiles():
    for name,size,fn in (("bowling",(24,24),lambda d:(d.ellipse((1,1,22,22),fill="#23303a",outline=OL),d.ellipse((5,5,10,10),fill="#4a6070"))),
                         ("keg",(28,30),lambda d:(d.rectangle((2,3,25,27),fill="#8a5a34",outline=OL),d.rectangle((2,9,25,12),fill="#4b4036"),d.line((13,3,16,0),fill="#f4b84a"))),
                         ("cow",(40,28),lambda d:(d.rectangle((3,6,30,22),fill="#6b4a2e",outline=OL),d.ellipse((22,2,38,20),fill="#f2ece0",outline=OL),d.ellipse((28,7,32,11),fill="#2c2620"))),
                         ("milk",(14,14),lambda d:(d.ellipse((2,2,11,11),fill="#f4f0e8",outline="#9aa")))):
        im=Image.new("RGBA",size); fn(ImageDraw.Draw(im)); im.save(ART/f"fx_{name}.png")

# ---- interactables ----
def make_interactables():
    def cel(kind,spent):
        im=Image.new("RGBA",(68,66)); d=ImageDraw.Draw(im)
        if kind=="tv":
            d.rectangle((8,18,60,56),fill="#4a3c30",outline=OL,width=2)
            if spent:
                d.rectangle((13,23,55,47),fill="#101214",outline=OL); d.line((16,26,40,44),fill="#cfd6d6"); d.line((40,44,52,28),fill="#cfd6d6")
                d.line((34,14,28,5),fill="#8a8a8a",width=2)
            else:
                d.rectangle((13,23,55,47),fill="#7ea0a8",outline=OL)
                for yy in range(25,47,4): d.line((13,yy,55,yy),fill="#a9c7cd")
                d.line((34,18,24,6),fill="#9a9a9a",width=2); d.line((34,18,46,6),fill="#9a9a9a",width=2)
        elif kind=="toilet":
            d.rounded_rectangle((16,6,50,26),4,fill="#e8e4d6",outline=OL,width=2)
            d.rounded_rectangle((12,24,56,44),8,fill="#f0ecde",outline=OL,width=2); d.rectangle((22,44,46,60),fill="#d6d2c4",outline=OL)
            if spent:
                d.polygon(((10,56),(26,48),(34,60),(14,62)),fill="#7ab0c8"); d.line((40,34,46,56),fill="#9ad0e8",width=2)
            else:
                d.ellipse((20,28,48,40),fill="#79a8b8",outline=OL)
        elif kind=="vending":
            d.rectangle((10,3,58,62),fill="#a8322a" if not spent else "#7a2a24",outline=OL,width=2)
            d.rectangle((16,9,42,40),fill="#dfe8e4" if not spent else "#30363a",outline=OL)
            if not spent:
                for r in range(3):
                    for c in range(3): d.rectangle((18+c*8,11+r*9,22+c*8,17+r*9),fill=("#4a7ad0","#d0a02a","#c04a4a")[(r+c)%3])
            else:
                d.line((16,9,42,40),fill="#9aa6a8"); d.line((42,9,16,40),fill="#9aa6a8")
                for p in ((46,48),(20,56),(34,54)): d.rectangle((p[0],p[1],p[0]+6,p[1]+4),fill="#c0a02a")
            d.rectangle((46,12,54,34),fill="#2a2a2a"); d.rectangle((18,46,42,56),fill="#1c1c1c")
        elif kind=="window":
            d.rectangle((6,6,62,60),fill="#5a4636",outline=OL,width=2)
            if spent:
                d.polygon(((10,10),(58,10),(30,34)),fill="#a8d0e0",outline="#e6f4f8"); d.polygon(((10,56),(26,40),(58,56)),fill="#a8d0e0")
                d.line((10,10,32,32),fill="#fff"); d.rectangle((6,6,62,60),outline=OL,width=2)
            else:
                d.rectangle((11,11,57,55),fill="#9cc4d8",outline=OL); d.line((34,11,34,55),fill=OL,width=2); d.line((11,33,57,33),fill=OL,width=2)
                d.line((15,14,26,26),fill="#e8f6fa",width=2)
        elif kind=="cancan":
            if spent:
                for x,y in ((10,50),(30,54),(46,46)): d.ellipse((x,y,x+16,y+7),fill="#90715a",outline=OL)
            else:
                d.rectangle((26,28,42,58),fill="#a8403a",outline=OL,width=2); d.ellipse((26,25,42,32),fill="#cfc8b8",outline=OL)
                d.rectangle((26,38,42,46),fill="#e8dcc0")
        elif kind=="jukebox":
            d.rounded_rectangle((12,6,56,62),10,fill="#7a3a22" if not spent else "#4a2a1c",outline=OL,width=2)
            d.rounded_rectangle((18,12,50,36),8,fill="#e8c05a" if not spent else "#2c2a26",outline=OL)
            if not spent:
                d.arc((22,16,46,40),180,360,fill="#c0402a",width=3)
        return im
    for k in ("tv","toilet","vending","window","cancan","jukebox"):
        for s in (False,True): cel(k,s).save(ART/f"scenery_{k}_{'spent' if s else 'whole'}.png")

# ---- audio ----
def wr(name,x):
    x=np.clip(x,-1,1); d=(x*32767).astype("<i2")
    with wave.open(str(WAV/f"{name}.wav"),"wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(d.tobytes())
def tt(s): return np.arange(int(RATE*s))/RATE
def nz(n,seed): return np.random.default_rng(seed).uniform(-1,1,n)
def lp(x,k): return np.convolve(x,np.ones(k)/k,"same")
def thump(t,f0,f1,dec): return np.sin(2*np.pi*np.cumsum(f1+(f0-f1)*np.exp(-t/(dec*.4)))/RATE)*np.exp(-t/dec)
def ring(t, partials):
    s=np.zeros_like(t)
    for f,a,d in partials:
        s+=a*np.sin(2*np.pi*f*t)*np.exp(-t*d)
    return s
def level(x,peak=.88):
    m=float(np.abs(x).max()) if len(x) else 0.
    return x*(peak/m) if m>1e-6 else x

def make_audio():
    t=tt(.9); n=nz(len(t),1)
    roll=lp(n,60)*np.minimum(t*8,1)*np.exp(-t*2.2)*4
    wr("bowling_ball",roll*.35+thump(t,120,60,.3)*.5)
    t=tt(.55); n=nz(len(t),2)
    pins=ring(t,((1350,.30,14.),(1810,.26,11.),(2380,.20,9.),(3050,.15,7.)))
    wr("bowling_hit",level(thump(t,300,90,.10)*.55+(n-lp(n,3))*np.exp(-t*40)*.5+pins*.55))
    t=tt(.7); wr("powder_keg",thump(t,90,45,.25)*.7+lp(nz(len(t),3),8)*np.exp(-t*10)*.5)
    t=tt(.9); wr("cow_launcher",(thump(t,110,50,.3)*.7+lp(nz(len(t),4),6)*np.exp(-t*8)*.5))
    t=tt(.9); moo=np.sin(2*np.pi*np.cumsum(190-60*np.minimum(t/.8,1))/RATE)*(1+.4*np.sin(2*np.pi*5*t))
    moo+=.5*np.sin(2*np.pi*np.cumsum(380-120*np.minimum(t/.8,1))/RATE); wr("cow_moo",moo*np.minimum(t*10,1)*np.exp(-t*2.5)*.5)
    t=tt(.22); wr("teat_gun",lp(nz(len(t),5),3)*np.exp(-t*30)*.6+np.sin(2*np.pi*np.cumsum(500-300*t/.22)/RATE)*np.exp(-t*25)*.5)
    t=tt(.5); wr("splat",lp(nz(len(t),6),9)*np.exp(-t*14)*.9+thump(t,140,60,.1)*.5)
    t=tt(.6); pop=(nz(len(t),7)-lp(nz(len(t),7),2))*np.exp(-t*60)*.7
    wr("tv_pop",level(pop+np.sin(2*np.pi*3200*t)*np.exp(-t*35)*.35
                      +np.sin(2*np.pi*4700*t)*np.exp(-t*50)*.22
                      +thump(t,180,70,.12)*.5+lp(nz(len(t),8),6)*np.exp(-t*5)*.25*(t>.05)))
    t=tt(1.1); surge=np.sin(2*np.pi*np.cumsum(120-60*np.minimum(t/1.,1))/RATE)*np.exp(-t*3)*.35
    wr("toilet_burst",level(surge+lp(nz(len(t),9),7)*np.exp(-t*4)*1.1
                            +(nz(len(t),21)-lp(nz(len(t),21),4))*np.exp(-t*6)*.5
                            +lp(nz(len(t),22),2)*np.exp(-t*9)*.3*(np.sin(2*np.pi*13*t)>0)))
    t=tt(.85); sh=np.clip(t-.30,0,None)
    wr("vending_clunk",level(thump(t,240,90,.14)*.8
        +ring(t,((780,.18,13.),(1170,.14,10.),(1690,.10,8.)))
        +(t>.30)*thump(sh,360,160,.06)*.45+(t>.30)*lp(nz(len(t),10),3)*np.exp(-sh*14)*.35))
    t=tt(.55); wr("window_smash",nz(len(t),11)*np.exp(-t*8)*.6*(lp(nz(len(t),12),2)>-.9)+np.sin(2*np.pi*2400*t)*np.exp(-t*30)*.3)
    t=tt(.5); wr("can_kick",level(thump(t,220,120,.09)*.55
        +ring(t,((900,.22,18.),(1420,.16,14.),(2050,.12,11.),(2740,.08,9.)))
        +lp(nz(len(t),13),2)*np.exp(-t*28)*.35))
    t=tt(1.2); wr("jukebox_hit",np.sin(2*np.pi*(220*(1+.5*(t>.3))*t))*np.exp(-t*4)*.3+lp(nz(len(t),14),3)*np.exp(-t*25)*.5)
    t=tt(.5); wr("whiskey_glug",np.sin(2*np.pi*(220+80*np.sin(2*np.pi*9*t))*t)*np.exp(-t*3)*.5)
    t=tt(.5); wr("cowpie_pick",lp(nz(len(t),15),12)*np.exp(-t*10)*.7)
    # equip / dry cues for new weapons
    for n_ in ("bowling_ball","powder_keg","cow_launcher","teat_gun"):
        t=tt(.28); wr("equip_"+n_,lp(nz(len(t),hash(n_)%99),4)*np.exp(-t*14)*.5+thump(t,260,150,.06)*.4)
        t=tt(.16); wr("dry_"+n_,thump(t,520,380,.03)*.5+lp(nz(len(t),3),2)*np.exp(-t*60)*.3)
    t=tt(.5); wr("honk",np.sign(np.sin(2*np.pi*(310)*t))*.35*np.minimum(t*40,1)*np.exp(-t*3))

def run():
    ART.mkdir(exist_ok=True); WAV.mkdir(exist_ok=True)
    make_weapons(); make_items(); make_projectiles(); make_interactables(); make_audio()
if __name__=="__main__":
    run(); print("ok")
