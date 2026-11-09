import os, glob, wave
os.environ["SDL_AUDIODRIVER"]="dummy"; os.environ["SDL_VIDEODRIVER"]="dummy"
import numpy as np, pygame as pg
pg.mixer.pre_init(48000,-16,1,512); pg.init()
SR=22050
src=open("audio_audit.py",encoding="utf-8-sig").read().split("R={}")[0]; exec(src)
def wavf(p):
    with wave.open(p) as w:
        sr=w.getframerate(); ch=w.getnchannels(); r=np.frombuffer(w.readframes(w.getnframes()),"<i2").astype(np.float32)/32768
    return (r.reshape(-1,ch).mean(axis=1) if ch>1 else r),sr
def opf(p):
    s=pg.mixer.Sound(p); a=pg.sndarray.array(s).astype(np.float32)/32768
    return (a.mean(axis=1) if a.ndim>1 else a),48000
def grp(root,names,kind):
    rows=[]
    for p in glob.glob(f"{root}/{'wav/*.wav' if kind=='w' else 'music/*.opus'}"):
        n=os.path.basename(p).rsplit(".",1)[0]
        if kind=="w" and not any(n==s or n.startswith(s) for s in names): continue
        x,sr=wavf(p) if kind=="w" else opf(p); f=feat(x,sr)
        if f: rows.append(f)
    return rows
def line(label,b,a):
    mb=lambda k,r: np.median([x[k] for x in r])
    print(f"| {label} | rms {mb('rms_db',b):.1f} -> {mb('rms_db',a):.1f} dB | low {np.mean([x['low'] for x in b]):.2f} -> {np.mean([x['low'] for x in a]):.2f} | high {np.mean([x['high'] for x in b]):.2f} -> {np.mean([x['high'] for x in a]):.2f} | centroid {mb('centroid',b):.0f} -> {mb('centroid',a):.0f} Hz | peak {mb('peak_db',b):.1f} -> {mb('peak_db',a):.1f} |")
import audio_master as M
for label,names,k in (("Guns",M.GUNS,"w"),("Explosions",M.BOOMS,"w"),("Ambience",["amb_"],"w"),("Music",[],"m")):
    line(label,grp("assets_orig_audio",names,k),grp("assets",names,k))
a=[ (n,feat(wavf(p)[0],22050)["peak_db"]) for p in glob.glob("assets/wav/*.wav") for n in [os.path.basename(p)]]
print("hot peaks >-0.3 dB:",[n for n,v in a if v>-0.3]); 
amb=[feat(wavf(p)[0],22050)["peak_db"] for p in glob.glob("assets/wav/amb_*.wav")]; print("min ambience peak",round(min(amb),1))

