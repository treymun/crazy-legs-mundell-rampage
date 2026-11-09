"""Offline soundtrack and sample editing. The game only plays the resulting PCM."""
from functools import lru_cache
from pathlib import Path
import math
import wave

import numpy as np

RATE = 22050
SOURCE = Path(__file__).resolve().parent / "source_art" / "audio"


@lru_cache(maxsize=40)
def source(name):
    with wave.open(str(SOURCE / f"{name}.wav"),"rb") as wav:
        if (wav.getnchannels(),wav.getsampwidth(),wav.getframerate()) != (1,2,RATE):
            raise ValueError(f"Unexpected source plate format: {name}")
        return np.frombuffer(wav.readframes(wav.getnframes()),"<i2").astype(np.float64)/32768.


def time(seconds):
    return np.arange(round(RATE*seconds))/RATE


def eq(x,low,high):
    freq = np.fft.rfftfreq(len(x),1/RATE)
    # Smooth gain curves preserve the transient rather than ringing around it.
    gain = (1-np.exp(-.72*(freq/low)**2))/np.sqrt(1+(freq/high)**6)
    return np.fft.irfft(np.fft.rfft(x)*gain,n=len(x))


def peak(x,level=.85):
    return x*(level/max(.01,float(np.max(np.abs(x)))))


def edge(x,head=.002,tail=.035):
    n,m = min(len(x),round(RATE*head)),min(len(x),round(RATE*tail))
    x[:n] *= np.linspace(0,1,n)
    x[-m:] *= np.linspace(1,0,m)
    return x


def close_loop(samples):
    """Join endpoints over eight milliseconds while retaining the downbeat."""
    frames=min(round(RATE*.008),len(samples)//4)
    mix=np.cos(np.linspace(0.,math.pi/2,frames))**2
    if samples.ndim==2:
        mix=mix[:,None]
    join=(samples[0]+samples[-1])*.5
    samples[:frames]=samples[:frames]*(1-mix)+join*mix
    samples[-frames:]=samples[-frames:]*(1-mix[::-1])+join*mix[::-1]
    return samples


def take(name,seconds=None,pitch=1.):
    plate = source(name)
    if seconds is None:
        seconds = len(plate)/RATE/pitch
    i = np.arange(round(seconds*RATE))*pitch
    return np.interp(i,np.arange(len(plate)),plate,right=0.)


def delay(x,seconds):
    n = round(RATE*seconds)
    out = np.zeros_like(x)
    if 0<n<len(x):
        out[n:] = x[:-n]
    return out


def weapon_mix(write):
    rng = np.random.default_rng(162)
    for name,plate,sec,pace,top,fund,level in (
        ("revolver","pistol_a",.30,1.04,4500,124,.82),
        ("revolver_alt","pistol_b",.31,1.0,4210,116,.82),
        ("rifle","rifle_a",.24,1.09,5030,139,.80),
        ("rifle_alt","rifle_b",.24,1.10,4800,149,.80),
        ("rifle_alt2","rifle_c",.23,1.06,4950,153,.79),
        ("shotgun","shotgun",.49,.93,3870,79,.88),
    ):
        t = time(sec)
        x = eq(take(plate,sec,pace),54,top)
        field = x * (.39+.61*np.exp(-t*(15 if name=="shotgun" else 25)))
        click = eq(rng.uniform(-1,1,len(t)),900,7200)*np.exp(-t*135)*.22
        chamber = np.sin(2*math.pi*(fund*t+(fund*1.08)*.027*(1-np.exp(-t/.027))))
        low = chamber*np.exp(-t*(19 if name=="shotgun" else 32))*.28
        mix = np.tanh(field*1.48+click+low)
        mix += .10*delay(eq(mix,107,2800),.037)
        write(name,edge(peak(mix,level),head=.001,tail=.049))

    shotgun = np.pad(take("shotgun",.46,.94),(0,round(.10*RATE)))
    t = np.arange(len(shotgun))/RATE
    first = eq(shotgun,50,4110)*np.exp(-t*7)
    second = delay(eq(shotgun,63,3550),.021)
    low = np.sin(math.tau*(66*t+86*.038*(1-np.exp(-t/.038))))*np.exp(-t*11)
    write("shotgun_both",edge(peak(np.tanh(first*1.53+second*.81+low*.33),.93),.001,.062))
    t = time(.93)
    rumble = eq(rng.uniform(-1,1,len(t)),36,196)*np.exp(-t*3.55)
    debris = eq(rng.uniform(-1,1,len(t)),191,2900)*np.exp(-t*8.5)
    blast = eq(take("heavy",.93,.82),40,3600)*np.exp(-t*11)
    sub = np.sin(math.tau*(45*t+76*.072*(1-np.exp(-t/.072))))*np.exp(-t*7.6)
    mix = np.tanh(blast*1.02+sub*.46+rumble*1.71+debris*.65)
    write("explosion",edge(peak(mix+.21*delay(mix,.068)+.11*delay(eq(mix,55,500),.156),.92),.001,.075))

    for name,plate,speed,sec,volume in (
        ("reload","reload_alt",.87,.24,.48),
        ("eject","reload",1.20,.16,.52),
        ("load","reload_alt",.94,.20,.49),
        ("close","reload",.79,.23,.57),
        ("mag_out","reload_alt",.88,.22,.53),
        ("mag_in","reload",1.06,.21,.59),
        ("bolt_rack","reload",.78,.25,.57),
    ):
        mechanical = eq(take(plate,sec,speed),143,5870)
        if name in ("mag_in","close","bolt_rack"):
            mechanical += .24*delay(mechanical,.039)
        write(name,edge(peak(mechanical,volume),.001,.026))

    # Single sharp hooks and real recorded clicks, through different mechanisms.
    for name,pitch,duration,velocity in (("crowbar_hit",.63,.24,.75),("ripsaw",.50,.35,.76),
                                        ("crossbow",.78,.31,.65),("empty",1.60,.13,.32)):
        t = time(duration)
        wood = eq(take("reload_alt",duration,pitch),182,4310)*np.exp(-t*7)
        note = {"crowbar_hit":811,"ripsaw":343,"crossbow":178,"empty":930}[name]
        ring = np.sin(math.tau*(note*t-note*.22*t*t))*np.exp(-t*(23 if name=="crossbow" else 17))
        dirt = eq(rng.uniform(-1.,1.,len(t)),122,2030)*np.exp(-t*18)
        if name=="crossbow":
            ring = eq(take("bass",duration,2.76),106,2470)*np.exp(-t*15)*2.3
        write(name,edge(peak(np.tanh(wood*.73+ring*.20+dirt*.23),velocity),.001,.036))
    t=time(.23)
    turn = math.tau*(137*t+104*.046*(1-np.exp(-t/.046)))
    motor = sum(np.sin(turn*k)*(.77**k)/max(1,k**.33) for k in range(1,14))
    filings = eq(rng.uniform(-1,1,len(t)),950,4300)
    saw = np.tanh(motor*.79+filings*.71)*np.exp(-t*5)
    write("saw_grind",edge(peak(saw,.79),.001,.036))


def field_mix(write):
    for name,plate,pitch,seconds,vol in (
        ("hurt","grunt_a",1.02,.39,.63),("hurt_alt","grunt_b",1.01,.41,.64),
        ("hurt_alt2","grunt_c",.98,.45,.63),("player_down","grunt_down",.95,1.38,.67),
        ("yee_haw","holler_a",.99,1.30,.76),("yee_haw_alt","holler_b",.96,1.45,.73),
        ("got_bessie","holler_win",.98,1.13,.73),
    ):
        x = eq(take(plate,seconds,pitch),115,3500)
        talk = np.tanh(1.62*x)
        write(name,edge(peak(talk+.085*delay(talk,.034),vol),.002,.036))

    rng = np.random.default_rng(276)
    field = source("field_crickets")
    t = time(12)
    night = eq(field[:len(t)],320,4000)*.115
    air = eq(rng.uniform(-1,1,len(t)),52,350)
    breeze = air*(.14+.08*np.sin(t*1.55)+.063*np.sin(t*.49+1.))
    water = eq(rng.uniform(-1,1,len(t)),480,3400)*(.073+.026*np.sin(t*1.81))
    motor = (np.sin(t*math.tau*60)+.28*np.sin(t*math.tau*120))*.008
    for name,bed in (("yard",night+breeze),("barn",night*.36+breeze*.73+motor*.3),
                     ("room",eq(night,82,570)*.29+motor+breeze*.18),
                     ("creek",night*.39+water+breeze*.53)):
        write("amb_"+name,edge(bed.copy(),.16,.21))

    # Foley layers are short and percussive, with softer tails than the reports.
    for name,frequency,hardness,clip in (
        ("wood",94,.58,"reload_alt"),("tile",125,.65,"reload"),("mud",72,.28,None),
        ("grass",96,.32,None),("water",118,.39,None),("gravel",83,.50,None),
    ):
        for variant in (0,1):
            plate = SOURCE/f"foot_{name}_{variant}.wav"
            if plate.is_file():
                foot = take(plate.stem,.25,1.+variant*.026)
            else:
                t = time(.24)
                contact = eq(rng.uniform(-1,1,len(t)),95 if name=="mud" else 280,4700)
                n = eq(rng.uniform(-1,1,len(t)),88,680)
                crack = contact*(.76*np.exp(-t*78)+.26*np.exp(-t*20))
                sole = np.sin(math.tau*(frequency*t+frequency*.55*.035*(1-np.exp(-t/.035))))
                foot = sole*np.exp(-t*37)*.21+n*np.exp(-t*21)*.30+crack*hardness
                if clip:
                    foot += eq(take(clip,.24,1.3+variant*.14),96,1900)*.17*np.exp(-t*21)
                if name=="water":
                    foot += delay(eq(contact,900,4400),.029)*np.exp(-t*16)*.22
            write(f"step_{name}_{variant}",edge(peak(foot,.49 if name!="grass" else .38),.001,.036))
    for name,plate,high in (("wood","foot_wood_0",3720),("stone","foot_tile_0",5110)):
        t=time(.19)
        dust=eq(rng.uniform(-1,1,len(t)),330,high)*np.exp(-t*35)
        texture=eq(take(plate,.19,1.78),180,high)*np.exp(-t*17)
        write("impact_"+name,edge(peak(dust*.39+texture*.7,.63),.001,.035))
    for name,plate,speed,length,lvl in (
        ("crunch","snack",1.13,.38,.65),("belch","burp",.91,.67,.58),
        ("gulp","swallow",.97,.64,.64),("moonshine","swallow_alt",1.08,.79,.65),
    ):
        x = eq(take(plate,length,speed),125,4510)
        if name in ("gulp","moonshine"):
            x = .87*delay(x,.13)
            x += eq(take("bottle_cap" if name=="gulp" else "bottle_clink",length),180,5480)*.49
            if name=="gulp":
                x += .33*delay(eq(take("swallow_alt",length,1.39),115,3500),.36)
        if name=="crunch":
            x += .23*delay(eq(take("snack",length,1.36),205,5450),.122)
        write(name,edge(peak(np.tanh(x*1.6),lvl),.002,.036))


GUITAR_NOTES = (36,41,45,48,52,55,59,64,67,71,74,80)


def pluck(note,seconds,part,bend=0.,fine=0.,mute=False):
    bass = part == "bass"
    base = 28 if bass else min(GUITAR_NOTES,key=lambda n:abs(n-note))
    wavelet = source("bass" if bass else f"guitar_{base}")
    t = time(seconds)
    cents = fine + bend*np.clip((t-.016)/.105,0,1)
    if part == "lead":
        cents += 12*np.sin(t*34)*np.clip((t-.096)*5,0,1)
    track = np.cumsum(2**((note-base+cents/100)/12))
    x = np.interp(track,np.arange(len(wavelet)),wavelet,right=0.)
    if bass:
        x = eq(x,31,1190)
        out = np.tanh(2.5*x)+.11*x
    elif part == "lead":
        x = eq(x,105,4800)
        out = eq(np.tanh(3.35*x+.21*x*x),115,4720)+.21*x
    else:
        x = eq(x,92,4590)
        out = eq(np.tanh(2.3*x),96,4240)
    if mute:
        out *= np.exp(-t*25)
    return edge(out,.002,.027 if mute else .049)


RHYTHM = {
    40:(40,47,52,56,59),
    45:(45,52,55,61,64),
    47:(47,54,57,63,66),
    43:(43,50,55,59,62),
    38:(38,45,50,54,57),
}
HOOK_A = ((0.,64,.145,0),(.65,67,.155,24),(1.05,69,.285,92),(1.83,67,.13,0),
          (2.11,64,.34,0),(3.14,62,.15,18),(3.68,64,.225,0))
HOOK_B = ((.13,59,.13,0),(.62,62,.11,0),(1.04,64,.35,0),(1.87,67,.12,0),
          (2.14,69,.175,110),(2.68,71,.155,0),(3.24,67,.295,-8))
TURN = ((0.,71,.15,0),(.56,69,.105,0),(.89,67,.115,0),(1.17,64,.30,23),
        (2.13,62,.15,0),(2.77,59,.15,0),(3.23,62,.12,32),(3.64,63,.15,35))


def song(stage):
    rng = np.random.default_rng({"title":212,"play":451,"victory":514,"radio":181}[stage])
    progressions = {
        "title":(40,40,43,45,40,40,47,45,40,43,45,47,40,40,45,47),
        "play":(40,40,40,40,45,45,40,40,47,45,40,47,
                40,43,45,45,40,43,47,45,40,43,45,47,
                38,45,40,40,47,45,40,47),
        "victory":(40,43,45,40),
        "radio":(40,40,45,45,40,40,47,45,40,40,45,47),
    }
    roots = progressions[stage]
    beat = 60/{"title":145,"play":141,"victory":143,"radio":117}[stage]
    length = round((4*len(roots)+(1.2 if stage=="victory" else 0))*beat*RATE)
    score = np.zeros((length,2))

    def put(at,samples,gain,pan=0.):
        if not len(samples):
            return
        start = round(at*beat*RATE)
        index = (start+np.arange(len(samples)))%length
        if stage=="victory":
            absolute = start+np.arange(len(samples))
            mask = (absolute>=0)&(absolute<length)
            index,samples = index[mask],samples[mask]
        score[index,0] += samples*gain*math.sqrt((1-pan)*.5)
        score[index,1] += samples*gain*math.sqrt((1+pan)*.5)

    drums = {k:source(k) for k in ("kick","snare","snare_alt","hat","hat_open","crash")}
    for j,root in enumerate(roots):
        offset = j*4
        chorus = stage in ("title","victory") or 11 < j < 24
        end = stage=="victory" and j==len(roots)-1
        jitter = lambda:float(rng.uniform(-.021,.021))
        bassline = ((0,0),(.57,0),(1.01,7),(1.59,9),(2.02,10),(2.59,9),(3.,7),(3.58,3))
        if j%4==3:
            bassline = ((0,0),(.59,3),(1.02,4),(1.56,7),(2.01,10),(2.58,7),(3.05,5),(3.59,4))
        for b,interval in bassline:
            if end and b>2.04:
                break
            put(offset+b+jitter(),pluck(root-12+interval,.23 if b!=0 else .28,"bass",fine=jitter()*86),.29,-.03)
        for b in (0.,1.57,2.0,2.72) if chorus else (0.,1.61,2.1):
            if not end or b<=2.1:
                put(offset+b,drums["kick"],.33 if b in (0.,2.0) else .24)
        for b in (1.02,3.02):
            if not end or b<2:
                put(offset+b+jitter(),drums["snare" if j%2==0 else "snare_alt"],.29,.04)
        if j%4==3 and not end:
            put(offset+3.55,drums["snare_alt"],.16,.10)
            put(offset+3.79,drums["snare"],.12,-.10)
        for b in (0,.58,1,1.58,2,2.58,3,3.58):
            if not end or b<=2:
                clip = "hat_open" if b==3.58 and j%2 else "hat"
                put(offset+b+jitter(),drums[clip],.085 if int(b)==b else .054,.30)
        if j in (0,8,12,20,24) or end:
            put(offset,drums["crash"],.13,-.28)
        for k,b in enumerate((.02,.56,1.06,1.61,2.02,2.58,3.06,3.65)):
            if end and b>2.1:
                break
            bright = k%2==0 and (chorus or k in (0,4))
            chord = RHYTHM[root] if bright else RHYTHM[root][:3]
            notes = chord if k%2==0 else reversed(chord)
            for n,note in enumerate(notes):
                at = offset+b+n*(.027 if bright else .015)+jitter()
                clip = pluck(note,.30 if bright else .125,"rhythm",fine=jitter()*132,mute=not bright)
                put(at,clip,.105 if bright else .072,-.62)
                if bright and chorus and n>=2:
                    put(at+.041,pluck(note,.245,"rhythm",fine=4.2),.065,.68)
        if chorus or j%4 in (0,3):
            phrase = TURN if j%4==3 else HOOK_A if j%2==0 else HOOK_B
            for b,note,sec,bend in phrase:
                if end and b>2:
                    break
                shift = 5 if root==45 and b>2 else 2 if root in (43,47) and b>1.8 else 0
                clip = pluck(note+shift,sec,"lead",bend=bend,fine=jitter()*95)
                put(offset+b+jitter(),clip,.26,.34)
                put(offset+b+.245,clip,.061,-.55)
        elif j%4==1:
            for b,note in ((2.36,64),(2.88,67),(3.43,69)):
                put(offset+b,pluck(note,.19,"lead",bend=70 if note==69 else 0),.21,.36)
    if stage=="victory":
        t = np.linspace(1.,0.,min(round(.38*RATE),len(score)))
        score[-len(t):] *= t[:,None]
    room = np.tanh(score*1.30)
    for ch in (0,1):
        room[:,ch] += .038*delay(room[:,1-ch],.063 if ch else .042)
    if stage=="radio":
        mid = eq(room.mean(axis=1),270,2800)
        return peak(np.tanh(2.15*mid),.77)
    master=peak(np.tanh(room*.94),.72 if stage=="play" else .86)
    return close_loop(master) if stage=="play" else master


def make_score(write):
    for stem,arrangement in (("title","title"),("music","play"),("victory","victory"),("jukebox","radio")):
        write(stem,song(arrangement))
