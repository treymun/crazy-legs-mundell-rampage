"""Offline mastering pass. Always works from assets_orig_audio backups, so it is idempotent."""
import os, sys, json, wave, shutil, glob
os.environ.setdefault("SDL_AUDIODRIVER","dummy"); os.environ.setdefault("SDL_VIDEODRIVER","dummy")
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parent; A=ROOT/"assets"; BK=ROOT/"assets_orig_audio"

def backup():
    for sub,pat in (("wav","*.wav"),("music","*.opus")):
        (BK/sub).mkdir(parents=True,exist_ok=True)
        for p in (A/sub).glob(pat):
            if not (BK/sub/p.name).exists(): shutil.copy2(p,BK/sub/p.name)

def read_wav(p):
    with wave.open(str(p)) as w:
        sr,ch,sw=w.getframerate(),w.getnchannels(),w.getsampwidth(); raw=w.readframes(w.getnframes())
    assert sw==2
    x=np.frombuffer(raw,"<i2").astype(np.float32)/32768
    return (x.reshape(-1,ch) if ch>1 else x[:,None]),sr
def write_wav(p,x,sr):
    x=np.clip(x,-1,1); d=(x*32767).astype("<i2")
    with wave.open(str(p),"wb") as w:
        w.setnchannels(x.shape[1]); w.setsampwidth(2); w.setframerate(sr); w.writeframes(d.tobytes())

def shelf(x,sr,lo_gain_db,lo_f,hi_gain_db,hi_f):
    out=np.empty_like(x)
    for c in range(x.shape[1]):
        n=len(x); N=1<<int(np.ceil(np.log2(n)))
        S=np.fft.rfft(x[:,c],N); f=np.fft.rfftfreq(N,1/sr)
        hi=1/(1+np.exp(-(np.log2(np.maximum(f,1)/hi_f))*3)); lo=1/(1+np.exp((np.log2(np.maximum(f,1)/lo_f))*3))
        g=10**((hi_gain_db*hi+lo_gain_db*lo)/20)
        out[:,c]=np.fft.irfft(S*g,N)[:n]
    return out
def rms(x): return float(np.sqrt((x**2).mean())+1e-9)
def limit(x,peak):
    m=np.abs(x).max()
    return x*(peak/m) if m>peak else x

GUNS=["shotgun","shotgun_both","revolver","revolver_alt","rifle","rifle_alt","rifle_alt2","armgun","crossbow","ripsaw","pressure_gun","riveter","riveter_pair","bottle_launcher","enemy_pistol","enemy_pump","enemy_scatter","deputy_shot","sheriff_shot","saucer_shot","tnt_throw"]
BOOMS=["explosion","rocket_pop","arm_impact","barker_blast","clone_bolt"]
def thump(n,sr,f0,f1,dur,amp):
    t=np.arange(n)/sr; env=np.exp(-t/dur); f=f1+(f0-f1)*np.exp(-t/(dur*.5))
    ph=2*np.pi*np.cumsum(f)/sr; return (np.sin(ph)*env*amp).astype(np.float32)

def master_sfx():
    rep={}
    for p in sorted((BK/"wav").glob("*.wav")):
        n=p.stem; x,sr=read_wav(p); y=x; kind=None
        if n in GUNS or n in BOOMS:
            boom=n in BOOMS; kind="boom" if boom else "gun"
            pk=np.abs(x).max()
            th=thump(len(x),sr,95 if not boom else 70,48 if not boom else 32,.09 if not boom else .35,pk*(.55 if not boom else .8))
            # fade thump in over 2 ms to avoid click
            r=min(len(th),int(sr*.002)); th[:r]*=np.linspace(0,1,r)
            y=x+th[:,None]
            y=shelf(y,sr,0,100,1.5,2500) if not boom else y
            y=y*(rms(x)/rms(y))**.35
            y=limit(y,.95)
        elif n.startswith("amb_"):
            kind="amb"; tgt=10**(-8/20); m=np.abs(x).max(); g=min(tgt/m,5.0); y=limit(x*g,.9)
        else:
            continue
        write_wav(A/"wav"/p.name,y,sr); rep[n]=kind
    return rep

def master_music():
    import pygame as pg
    pg.mixer.pre_init(48000,-16,1,512); pg.init()
    from score_codec import write_opus
    rep={}
    for p in sorted((BK/"music").glob("*.opus")):
        s=pg.mixer.Sound(str(p)); a=pg.sndarray.array(s).astype(np.float32)/32768
        sr=pg.mixer.get_init()[0]; m=(a.mean(axis=1) if a.ndim>1 else a)[:,None]
        y=shelf(m,sr,-5,180,7,2200)
        y=y*(rms(m)/rms(y)); y=limit(y,.72)
        write_opus(A/"music"/p.name,y[:,0],sr); rep[p.stem]=1
    return rep

if __name__=="__main__":
    backup()
    print("sfx",len(master_sfx())); print("music",len(master_music()))
