import os, glob, json
os.environ["SDL_AUDIODRIVER"]="dummy"; os.environ["SDL_VIDEODRIVER"]="dummy"
import numpy as np, pygame as pg
pg.mixer.pre_init(22050,-16,2,512); pg.init()
exec(open("audio_audit.py",encoding="utf-8-sig").read().split("R={}")[0])
ref=np.load("ref_music.npy").astype(np.float32)
# tempo per 90s window across the reference soundtrack
t=[tempo(ref[i*SR*120:(i+1)*SR*120]) for i in range(0,12)]
print("ref tempo by window:",t)
rows=[]
for p in sorted(glob.glob("assets/music/*.opus")):
    try:
        s=pg.mixer.Sound(p); a=pg.sndarray.array(s).astype(np.float32)/32768; m=a.mean(axis=1) if a.ndim>1 else a
        f=feat(m); rows.append((os.path.basename(p),tempo(m),f["rms_db"],f["peak_db"],f["centroid"],f["low"],f["high"]))
    except Exception as e: rows.append((os.path.basename(p),"err",str(e)[:60]))
for r in rows: print(r)
f=feat(ref[SR*30:SR*600]); print("ref music body:",f)

