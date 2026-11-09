import os, time
os.environ["SDL_VIDEODRIVER"]="dummy"; os.environ["SDL_AUDIODRIVER"]="dummy"
import pygame as pg
from PIL import Image
from main import Desktop
from game import Controls
d=Desktop(smoke=True); out=[]
for lvl in ("hickston","fair","sawmill","quarry"):
    d.start(lvl); g=d.game
    for e in g.enemies: e.dormant=True
    for _ in range(10): g.tick(1/60,Controls())
    res={}
    for on in (False,True):
        g.retro_look=on; t=time.perf_counter()
        for _ in range(20): g.draw(d.canvas,grade=d.palette.grade)
        res[on]=(time.perf_counter()-t)/20*1000
        out.append(Image.frombytes("RGB",d.canvas.get_size(),pg.image.tobytes(d.canvas,"RGB")))
    print(lvl,"ms/frame off %.1f  on %.1f"%(res[False],res[True]))
W,H=out[0].size; s=Image.new("RGB",(W*2,H*4))
for i,im in enumerate(out): s.paste(im,((i%2)*W,(i//2)*H))
s.resize((W*3,H*6),Image.NEAREST).save("bot_shots/look.png")
