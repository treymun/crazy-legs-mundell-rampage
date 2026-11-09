"""Compose the original chapter soundtrack from the included guitar and drum plates."""
from dataclasses import dataclass
from functools import lru_cache
import json
import math
from pathlib import Path
import wave

import numpy as np

from sound_production import RATE, close_loop, eq, peak, pluck, source, take
from score_codec import write_opus


@dataclass(frozen=True)
class Arrangement:
    bpm: int
    beats: int
    verse: tuple[int, ...]
    bridge: tuple[int, ...]
    bass: tuple[tuple[float,int], ...]
    rhythm: tuple[float, ...]
    drums: tuple[tuple[float,...], tuple[float,...], tuple[float,...]]
    motif: tuple[tuple[float,int,float], ...]
    reply: tuple[tuple[float,int,float], ...]
    mode: str


# Each piece has its own meter, harmony, rhythm section and two authored
# phrases. Pitch offsets in motifs are from that bar's guitar root.
PIECES = {
    "music": Arrangement(141,4,(40,40,45,45,40,40,47,45),(40,43,45,45,40,43,47,45),
        ((0,0),(.57,0),(1.01,7),(1.59,9),(2.02,10),(2.59,9),(3.,7),(3.58,3)),
        (.02,.56,1.06,1.61,2.02,2.58,3.06,3.65),((0.,1.57,2.1),(1.02,3.02),(.58,1.58,2.58,3.58)),
        ((0.,24,.145),(.65,27,.155),(1.05,29,.285),(1.83,27,.13),(2.11,24,.34),(3.14,22,.15)),
        ((.13,19,.13),(.62,22,.11),(1.04,24,.35),(1.87,27,.12),(2.14,29,.175),(3.24,27,.295)),"rough"),
    "county_line": Arrangement(105,4,(38,38,41,43,38,45,41,38),(34,41,36,43,34,41,45,45),
        ((0,0),(1.4,7),(2.6,10),(3.46,3)),(.25,1.75,2.25,3.54),
        ((0,2.6),(1.04,3.12),(.51,1.5,2.48,3.5)),
        ((.12,19,.55),(1.29,22,.28),(2.22,24,.74)),((.56,17,.39),(1.55,15,.32),(3.04,19,.55)),"dry"),
    "porchlight_stomp": Arrangement(158,4,(43,43,46,48,43,46,50,43),(45,45,48,50,45,46,48,50),
        ((0,0),(.52,0),(1.08,4),(1.53,7),(2,9),(2.62,7),(3.22,4)),(.10,1.0,1.6,2.2,3.0,3.55),
        ((0,1.75,2.47),(1.,3.),(.5,1.5,2.5,3.5)),
        ((.03,16,.18),(.52,19,.17),(1.12,24,.27),(2.32,21,.20),(3.06,19,.17)),
        ((.48,12,.26),(1.31,16,.23),(2.05,19,.23),(3.42,22,.18)),"rough"),
    "fair_score": Arrangement(113,3,(42,42,39,41,42,45,39,41),(38,41,44,41,38,37,40,42),
        ((0,0),(1.20,7),(2.19,6)),(.02,1.06,2.08),
        ((0,),(1.12,2.2),(.53,1.5,2.5)),
        ((.10,24,.25),(.57,19,.24),(1.05,21,.31),(2.10,15,.37)),
        ((.51,14,.21),(1.15,17,.44),(2.03,12,.39),(2.66,11,.14)),"warped"),
    "tickets_after_dark": Arrangement(102,5,(40,35,38,37,40,43,37,35),(31,36,38,35,31,34,37,39),
        ((0,0),(1.56,0),(2.96,5),(4.03,7)),(.80,2.42,4.02),
        ((0,3.14),(1.83,4.1),(.98,2.93,4.62)),
        ((.53,19,.70),(2.0,17,.49),(3.73,15,.28)),((.09,12,.58),(1.85,16,.43),(4.02,11,.42)),"spare"),
    "closing_time_shuffle": Arrangement(137,4,(41,41,44,46,44,41,39,41),(46,48,41,41,46,44,49,48),
        ((0,0),(.65,7),(1.12,10),(2.10,9),(3.17,6)),(.28,1.17,1.74,2.65,3.36),
        ((0,2.10),(1.10,3.08),(.33,1.52,2.34,3.61)),
        ((.14,14,.20),(.79,16,.31),(1.68,20,.21),(2.28,22,.36),(3.52,17,.16)),
        ((.06,24,.20),(.65,20,.26),(1.48,17,.17),(2.51,14,.30),(3.49,13,.17)),"rough"),
    "mill_score": Arrangement(89,4,(33,40,35,33,38,41,36,33),(36,36,39,41,36,40,43,35),
        ((0,0),(2.29,7)),(1.12,2.65,3.38),
        ((0,),(2.16,),(.73,3.11)),
        ((.30,19,.76),(1.81,22,.62),(3.16,17,.40)),((.87,15,.92),(2.67,11,.53)),"spare"),
    "green_chain": Arrangement(119,4,(36,36,39,41,36,38,43,42),(38,41,38,43,38,40,42,43),
        ((0,0),(.78,3),(1.58,7),(2.35,10),(3.33,7)),(.0,.84,2.12,2.76,3.7),
        ((0,1.58,2.93),(1.05,3.13),(.6,1.69,2.62,3.55)),
        ((.35,22,.34),(1.17,19,.22),(2.1,18,.22),(3.18,15,.28)),
        ((.12,16,.31),(1.03,18,.22),(2.02,19,.33),(3.60,24,.15)),"dry"),
    "apron_run": Arrangement(147,4,(40,45,40,38,47,45,43,38),(42,42,47,48,44,43,42,45),
        ((0,0),(.48,7),(.98,0),(1.82,3),(2.15,4),(2.7,6),(3.18,7)),(.05,.60,1.65,2.27,3.48),
        ((0,1.18,2.5,3.71),(1.03,3.03),(.49,1.49,2.57,3.49)),
        ((.12,12,.26),(.70,15,.18),(1.27,17,.25),(2.36,19,.33),(3.50,22,.17)),
        ((.09,24,.15),(.55,21,.15),(1.26,18,.20),(2.0,17,.18),(3.00,15,.33)),"rough"),
    "quarry_score": Arrangement(122,4,(35,35,42,38,40,35,38,42),(40,43,40,42,40,38,37,42),
        ((0,0),(.85,0),(1.89,6),(2.78,7),(3.40,10)),(.02,1.18,2.07,3.05),
        ((0,.75,2.7),(1.10,3.16),(.29,1.49,2.18,3.56)),
        ((.31,12,.25),(1.20,17,.38),(2.27,18,.25),(3.38,15,.22)),
        ((.04,10,.23),(.75,12,.28),(2.45,17,.40),(3.54,18,.19)),"iron"),
    "copper_and_steam": Arrangement(97,3,(43,43,39,41,43,46,44,41),(38,41,43,45,41,39,44,45),
        ((0,0),(.80,4),(1.56,7),(2.55,10)),(.06,1.47,2.13),
        ((0,1.72),(1.13,2.35),(.54,1.58,2.58)),
        ((.22,19,.44),(1.13,20,.24),(2.01,24,.55)),
        ((.03,22,.24),(.76,19,.35),(1.58,17,.24),(2.39,15,.25)),"dry"),
    "last_load": Arrangement(154,4,(37,37,40,44,42,40,44,39),(38,45,41,41,46,43,40,45),
        ((0,0),(.58,7),(1.40,7),(2.02,5),(2.51,0),(3.18,3),(3.68,4)),(.25,.91,1.47,2.22,2.78,3.54),
        ((0,.59,2.12,3.42),(1.09,3.09),(.31,1.45,2.57,3.65)),
        ((.04,15,.18),(.61,19,.22),(1.22,18,.21),(1.98,23,.27),(3.33,21,.28)),
        ((.1,24,.21),(.81,23,.18),(1.53,19,.18),(2.17,17,.26),(3.54,12,.16)),"iron"),
}


# Forms are separate arrangements. a/b recall the original verse and answer,
# x adds new harmony, s is a lead break, d a reduced-band breakdown, r the return.
# The final tuple is a newly authored lead answer, in beats, semitones and seconds.
DEVELOPMENTS = {
    "music": ("iabxasbdxar", (43,43,48,48,45,43,47,47),
              ((.04,28,.36),(.72,24,.28),(1.56,21,.41),(2.79,22,.30),(3.59,23,.14))),
    "county_line": ("iabdxsabra", (40,43,40,45,43,40,36,38),
                    ((.16,26,.51),(1.31,21,.23),(2.17,19,.33),(3.24,17,.62))),
    "porchlight_stomp": ("iabaxsdbarxs", (48,48,45,50,48,51,50,43),
                         ((.13,20,.19),(.51,24,.29),(1.65,25,.26),(2.34,21,.21),(3.08,16,.31))),
    "fair_score": ("iabxdsabrxa", (39,44,40,39,45,40,38,41),
                   ((.14,17,.32),(.65,20,.30),(1.19,23,.33),(2.21,24,.45))),
    "tickets_after_dark": ("iabdxsra", (38,40,33,38,42,37,39,35),
                           ((.22,24,.51),(1.46,19,.61),(3.34,16,.30),(4.22,14,.53))),
    "closing_time_shuffle": ("iabasdxbrxa", (47,45,42,44,47,49,44,43),
                             ((.08,18,.25),(.64,23,.31),(1.51,24,.21),(2.45,18,.34),(3.4,13,.23))),
    "mill_score": ("iabdxsra", (35,33,38,36,43,39,35,33),
                   ((.39,16,1.03),(1.91,18,.66),(3.21,22,.48))),
    "green_chain": ("iabxdsabra", (41,39,36,41,43,40,39,36),
                    ((.11,19,.38),(1.17,21,.26),(2.29,24,.42),(3.51,17,.25))),
    "apron_run": ("iabaxdsbrax", (45,43,45,42,47,45,41,40),
                  ((.04,22,.20),(.68,17,.23),(1.19,14,.17),(2.02,20,.34),(3.38,24,.25))),
    "quarry_score": ("iabxasdbra", (42,37,40,42,43,40,38,35),
                     ((.18,20,.24),(.82,16,.26),(1.62,18,.25),(2.35,23,.36),(3.29,21,.27))),
    "copper_and_steam": ("iabxdasbrax", (41,44,43,41,38,42,45,43),
                         ((.11,20,.43),(.94,23,.34),(1.78,24,.46),(2.47,22,.29))),
    "last_load": ("iabaxdsbrxas", (42,40,42,45,43,42,39,37),
                  ((.10,13,.26),(.81,18,.20),(1.53,22,.28),(2.24,24,.24),(3.10,19,.27))),
}


@lru_cache(maxsize=450)
def note(pitch,length,voice,bend=0.,mute=False):
    return pluck(pitch,length,voice,bend=bend,mute=mute)


def arrange(part, development):
    beat = 60/part.bpm
    form,harmony,lead = development
    sections = {"i":part.verse[:4], "a":part.verse,"b":part.bridge, "x":harmony,
                "d":harmony[-4:]+part.bridge[:4], "s":harmony[:4]+part.verse[-4:],
                "r":part.bridge[:4]+part.verse[-4:], "o":(*part.verse[-3:],part.verse[0])}
    bars = [(section,j,root) for section in form+"o"
            for j,root in enumerate(sections[section])]
    length = round(len(bars)*part.beats*beat*RATE)
    track = np.zeros((length,2))
    rng = np.random.default_rng(part.bpm*541+part.beats)
    low = part.mode=="spare"
    # Upbeat honky-tonk numbers get a hotter lead and snappier kit.
    honky = part.bpm >= 135
    drum_tracks = ("kick","snare_alt","hat")

    def put(at,sample,gain,pan=0.):
        start = round(at*beat*RATE)
        frames = (start+np.arange(len(sample)))%length
        track[frames,0] += sample*gain*math.sqrt((1-pan)/2)
        track[frames,1] += sample*gain*math.sqrt((1+pan)/2)

    for i,(section,jbar,root) in enumerate(bars):
        at=i*part.beats
        turn = jbar%4==3
        bridge = section in "bxs"
        reduced = section in "id"
        full = section in "sr"
        final = section=="o" and jbar==3
        bass = part.bass[:2] if reduced or final else part.bass
        for step,interval in bass:
            pitch=root-12+(interval if not turn or step<part.beats-1 else (interval+2)%12)
            put(at+step,note(pitch,.66 if low or reduced else .30,"bass"),.39 if low else .29,-.06)
        for kind,times in zip(drum_tracks,part.drums):
            for step in times:
                if (reduced and (kind=="snare_alt" or step>part.beats*.53)) or final and step>1:
                    continue
                vol = {"kick":.28,"snare_alt":.23,"hat":.073}[kind]
                if honky:
                    vol *= 1.10
                if low:
                    vol*=.51
                if full:
                    vol*=1.16
                put(at+step+float(rng.uniform(-.012,.012)),source(kind),vol,.22 if kind=="hat" else -.06)
        if turn and not reduced and not final:
            put(at+part.beats-.38,source("snare"),.098 if low else .16,.14)
        rhythm = part.rhythm[::2] if reduced else part.rhythm
        for j,step in enumerate(rhythm):
            if final and step>1.8:
                break
            offsets=(0,7,10) if not bridge else (0,3,7,12)
            if section=="d":
                offsets=(0,12)
            elif full:
                offsets=(*offsets,14)
            if j%2:
                offsets=offsets[::-1]
            for k,interval in enumerate(offsets):
                dry = j%2==1 and not low
                clip=note(root+interval,.17 if dry else .38,"rhythm",mute=dry)
                put(at+step+k*.025,clip,.104 if low else .076,-.57)
                if not dry and (bridge or part.mode in ("iron","rough")):
                    put(at+step+k*.025+.031,clip,.043,.55)
        if (not reduced or jbar%2==0) and not final:
            phrase=lead if section in "xs" else part.reply if turn or bridge and i%2 else part.motif
            for j,(step,interval,sec) in enumerate(phrase):
                if section=="s" and jbar>=4:
                    interval += 5 if jbar%2==0 else -2
                bend = (-43 if j%2 else 28) if part.mode=="warped" else 84 if section=="s" else 54 if j==2 else 0
                clip=note(root+interval,sec,"lead",bend)
                put(at+step,clip,(.23 if low else .27)*(1.12 if honky else 1.),.42)
                if section=="r" and j%2==0:
                    put(at+step+.04,note(root+interval-5,sec,"lead"),.115,-.39)
                if not low or j==0:
                    put(at+step+.34,clip,.061,-.54)
        if part.mode=="iron" and i%2==0:
            hit=eq(take("reload_alt",.12,.62),530,2600)
            put(at+part.beats-.23,hit,.17,-.30)
        if part.mode=="warped" and i%3==1:
            organ=eq(note(root+22,.58,"lead",-39),375,1800)
            put(at+.6,organ,.096,-.50)
        if jbar==0 and section in "bsr" and not low:
            put(at,source("crash"),.12,.31)
        if final:
            put(at+.35,note(root+24,1.26,"lead",35),.18,.25)
    saturated=np.tanh(track*1.16)
    for channel in range(2):
        saturated[:,channel]+=.047*np.roll(saturated[:,1-channel],round(RATE*(.029+channel*.016)))
    return np.tanh(saturated)


def presence(x, high_gain=2.6, k=9):
    """Lift the pick attack and cymbal air without thinning the low end."""
    low = np.convolve(x, np.ones(k) / k, mode="same")
    return low + (x - low) * high_gain


def make_tracks(write):
    folder = Path(__file__).resolve().parent/"assets"/"music"
    folder.mkdir(parents=True,exist_ok=True)
    manifest = {}
    for name,part in PIECES.items():
        mix = arrange(part,DEVELOPMENTS[name])
        mixed = np.stack([presence(mix[:,channel]) for channel in range(mix.shape[1])],axis=1)
        pcm = close_loop(peak(mixed.mean(axis=1),.72))
        write(name,close_loop(peak(mixed,.72)) if name=="music" else pcm)
        manifest[name] = write_opus(folder/f"{name}.opus",pcm,RATE)
    (folder/"durations.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    write_playback_ends(folder)


def write_playback_ends(folder):
    """Mark the end of each coda before the mastered silence and loop join."""
    ends = {}
    for name in PIECES:
        master = folder.parent/"wav"/f"{name}.wav"
        with wave.open(str(master),"rb") as pcm:
            rate,frames = pcm.getframerate(),pcm.getnframes()
            start = max(0,frames-rate*5)
            stop = frames-round(.024*rate)  # Ignore the eight-ms loop-join blend.
            pcm.setpos(start)
            tail = np.frombuffer(pcm.readframes(stop-start),"<i2").reshape(-1,pcm.getnchannels())
        mono = tail.mean(axis=1)/32768.
        window = rate//40
        blocks = mono[:len(mono)//window*window].reshape(-1,window)
        sounding = np.flatnonzero(np.mean(blocks**2,axis=1)>=.0001)
        ends[name] = round(frames/rate,3)
        if sounding.size:
            end = (start+(int(sounding[-1])+1)*window)/rate+.074
            ends[name] = round(min(frames/rate,end),3)
    (folder/"playback_ends.json").write_text(json.dumps(ends,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--ends-only",action="store_true")
    if parser.parse_args().ends_only:
        write_playback_ends(Path(__file__).resolve().parent/"assets"/"music")
    else:
        from audio import write
        make_tracks(write)
