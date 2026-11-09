import os, glob, wave, json
import numpy as np
SR=22050
def feat(x, sr=SR):
    x=x.astype(np.float32)
    if len(x)<512: return None
    rms=float(np.sqrt((x**2).mean())); peak=float(np.abs(x).max())
    n=min(len(x),sr*20); seg=x[:n]
    sp=np.abs(np.fft.rfft(seg*np.hanning(len(seg))))+1e-9; fr=np.fft.rfftfreq(len(seg),1/sr)
    cen=float((sp*fr).sum()/sp.sum())
    tot=sp.sum(); lo=sp[fr<250].sum()/tot; mid=sp[(fr>=250)&(fr<2500)].sum()/tot; hi=sp[fr>=2500].sum()/tot
    return dict(rms_db=round(20*np.log10(rms+1e-9),1),peak_db=round(20*np.log10(peak+1e-9),1),centroid=round(cen),low=round(float(lo),2),mid=round(float(mid),2),high=round(float(hi),2))
def events(x, sr=SR, thr_db=-38, gap=.12):
    env=np.abs(x.astype(np.float32)); k=int(sr*.01); env=np.convolve(env,np.ones(k)/k,'same')
    on=env>10**(thr_db/20); ev=[]; i=0; n=len(on); g=int(gap*sr)
    while i<n:
        if on[i]:
            j=i; last=i
            while j<n and j-last<g:
                if on[j]: last=j
                j+=1
            ev.append((i,last)); i=last+1
        else: i+=1
    return ev
def tempo(x, sr=SR):
    x=x[:sr*90].astype(np.float32); hop=256
    fr=np.abs(x[:len(x)//hop*hop].reshape(-1,hop)).mean(axis=1); d=np.maximum(0,np.diff(fr)); d-=d.mean()
    ac=np.correlate(d,d,'full')[len(d)-1:]; fs=sr/hop
    lo,hi=int(fs*60/200),int(fs*60/60); lag=lo+int(np.argmax(ac[lo:hi]))
    return round(60*fs/lag,1)
R={}
for k in ("music","sfx","voice"):
    m=np.load(f"ref_{k}.npy").astype(np.float32); R[k]=m
    print(k, feat(m))
print("music tempo (BPM est):", tempo(R["music"]))
# SFX / voice event stats
for k in ("sfx","voice"):
    ev=events(R[k]); durs=np.array([(b-a)/SR for a,b in ev]); 
    d=durs[(durs>.05)&(durs<12)]
    print(k,"events",len(ev),"median dur %.2fs p10 %.2f p90 %.2f"%(np.median(d),np.percentile(d,10),np.percentile(d,90)))
    pk=[20*np.log10(np.abs(R[k][a:b+1]).max()+1e-9) for a,b in ev]
    print("  event peak dB median %.1f"%np.median(pk))
# game audio
G={}
for p in glob.glob("assets/wav/*.wav"):
    n=os.path.basename(p)[:-4]
    with wave.open(p) as w:
        sr=w.getframerate(); ch=w.getnchannels(); raw=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float32)/32768
    if ch>1: raw=raw.reshape(-1,ch).mean(axis=1)
    f=feat(raw,sr)
    if f: f["dur"]=round(len(raw)/sr,2); G[n]=f
json.dump(G,open("game_audio_audit.json","w"),indent=1)
def grp(names): return [G[n] for n in G if any(n.startswith(s) for s in names)]
def summ(label, rows):
    if not rows: return
    print(f"{label:14s} n={len(rows):3d} rms {np.median([r['rms_db'] for r in rows]):6.1f} peak {np.median([r['peak_db'] for r in rows]):6.1f} centroid {np.median([r['centroid'] for r in rows]):6.0f} low {np.mean([r['low'] for r in rows]):.2f} hi {np.mean([r['high'] for r in rows]):.2f}")
print("\nGAME groups (median):")
summ("guns",grp(["shotgun","revolver","rifle","armgun","crossbow","ripsaw","pressure_gun","riveter","bottle_launcher"]))
summ("explosions",grp(["explosion","rocket_pop","arm_impact"]))
summ("enemy alerts",grp(["billy_alert","clone_alert","coot_alert","alien_alert","sheriff"]))
summ("pain/down",grp(["actor_","hurt","player_down","varmint"]))
summ("steps",grp(["step_"]))
summ("ambience",grp(["amb_"]))
summ("voice talk",grp(["talk_","yee_haw","county_dispatch"]))
print("\nclipping/weak:")
print(" hot (peak>-0.5dB):",[n for n,r in G.items() if r["peak_db"]>-0.5][:20])
print(" quiet (peak<-18dB):",[n for n,r in G.items() if r["peak_db"]<-18][:30])
print(" ultra-short (<0.05s):",[n for n,r in G.items() if r["dur"]<.05][:20])
