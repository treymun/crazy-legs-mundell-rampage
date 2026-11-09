"""Original area scores and effects in the existing PCM WAV format."""
import math

import numpy as np

from audio import RATE, band, decay, osc, speech, time, write
from sound_production import edge, eq, peak, pluck, take


def strike(length, pitch, rng):
    t = time(length)
    body = (osc(t,pitch) + .29*osc(t,pitch*2.76)) * decay(t,11)
    click = rng.uniform(-1,1,t.shape)*decay(t,48)*.16
    return body*.68 + click


def add(destination, sample, at, gain=1.):
    index = round(at*RATE)
    n = min(len(destination)-index,len(sample))
    destination[index:index+n] += sample[:n]*gain


def calliope(notes, length, rng):
    track = time(length)*0
    for onset, pitch, duration in notes:
        t = time(duration)
        wobble = .19*osc(t,3.1) + .08*osc(t,6.5)
        phase = t*pitch*math.tau
        tone = np.sin(phase+wobble) + .36*np.sin(2*phase-wobble) + .12*np.sin(3*phase)
        add(track,edge(tone*np.exp(-t*2.1),.014,.086),onset,.52)
    return np.tanh(eq(track+.023*rng.uniform(-1,1,track.shape),180,2600)*1.45)


def beds(rng):
    t = time(14)
    wind = band(rng.uniform(-1,1,t.shape),151)
    rattle = band(rng.uniform(-1,1,t.shape),5)-band(rng.uniform(-1,1,t.shape),33)
    hum = (osc(t,59)+.18*osc(t,118.3))*(.4+.6*osc(t,.43)**2)
    write("amb_fair", edge(peak(wind*.91+rattle*.051+hum*.031,.20),.03,.06))
    roof = band(rng.uniform(-1,1,t.shape),12)
    rain = (.4+.16*osc(t,.61)+.09*osc(t,1.3))*roof + wind*.42
    for offset in rng.uniform(0,13.5,35):
        add(rain,strike(.14,rng.uniform(515,1780),rng),float(offset),.028)
    write("amb_mill", edge(peak(rain,.25),.04,.06))
    insects = np.zeros_like(t)
    for pitch, rate, phase in ((3220,1.23,.1),(3730,.83,.63),(2820,1.67,.37)):
        chirp = np.maximum(0.,osc(t+phase,rate))**13 * np.maximum(0.,osc(t,19))**2
        insects += osc(t,pitch)*chirp*.036
    write("amb_mill_bank",edge(peak(rain,.25)+insects,.04,.06))
    t = time(2.4)
    generator = (osc(t,56)+.38*osc(t,110)+.20*osc(t,175))
    generator *= (.62+.38*osc(t,13.6)**2)*(.32+.68*osc(t,1.9)**2)
    generator += band(rng.uniform(-1,1,t.shape),9)*.31
    write("distant_fair_generator",edge(peak(generator,.46),.05,.18))
    write("distant_fair_rattle",edge(peak(strike(.63,215,rng)+.61*strike(.63,373,rng),.43)))
    write("distant_fair_motif",edge(peak(calliope(((.02,391,.46),(.51,468,.40),
                    (.93,313,.65),(1.71,341,.43)),2.4,rng),.48)))
    # Mangled speaker with a corresponding in-game caption.
    pa = speech(((.15,97,690,1120,2340,.11),(.15,88,530,1190,2230,.17),
                 (.23,108,480,920,1920,.12),(.22,92,600,1480,2080,.16),
                 (.21,78,360,1140,1940,.19)))
    pa = eq(np.tanh(pa*3.4),310,1860)
    write("distant_fair_pa",edge(peak(np.r_[strike(.15,770,rng)*.46,pa,strike(.19,346,rng)*.40],.60)))
    t = time(1.75)
    creak = osc(t,74+8*osc(t,.72)) + .46*osc(t,131+12*osc(t,.59))
    creak *= np.sin(t/1.75*math.pi)**2
    write("distant_mill_timber",edge(peak(creak*.62+band(rng.uniform(-1,1,t.shape),11)*.35,.44)))
    pump = np.zeros(round(RATE*1.9))
    for offset, pitch in ((.02,69),(.17,61),(.83,73),(1.01,58)):
        add(pump,strike(.55,pitch,rng),offset,.65)
    write("distant_mill_pump",edge(peak(pump,.52)))


def devices_and_tells(rng):
    pairs = (("breaker_thunk",(113,246)),("broadcast_cut",(182,77)),
             ("mill_isolate",(72,121)),("mill_trip",(62,91)),
             ("barker_wind",(539,318)),("barker_blast",(150,233)),
             ("crawler_click",(799,463)),("millhand_rev",(105,179)),
             ("millhand_hit",(53,163)),("lantern_charge",(353,486)),("lantern_spit",(208,295)),
             ("slingblade",(227,191)),("sling_hit",(122,242)),
             ("bottle_launcher",(581,130)),("riveter",(188,647)))
    for name, pitches in pairs:
        track = np.zeros(round(RATE*.68))
        add(track,strike(.56,pitches[0],rng),.01)
        add(track,strike(.48,pitches[1],rng),.12,.73)
        write(name,edge(peak(track,.64)))


def quarry_sounds(rng):
    t=time(12)
    air=eq(rng.uniform(-1,1,t.shape),45,310)
    motor=(osc(t,53)+osc(t,106)*.19)*(.009+.008*osc(t,.21))
    chuff=eq(rng.uniform(-1,1,t.shape),280,1700)*np.maximum(0,osc(t,1.14))**7*.025
    write("amb_quarry",edge(peak(air*.72+motor+chuff,.20),.05,.09))
    write("amb_quarry_line",edge(peak(air*.22+motor*1.27+chuff*.43,.17),.05,.09))
    actions=(
        ("pressure_gun",.37,82,2800,"pistol_b",.70,.82),
        ("pressure_pump",.32,169,3350,"reload_alt",.72,.57),
        ("pressure_vent",.79,146,2300,"reload",.68,.61),
        ("pressure_interrupt",.27,332,3630,"reload_alt",1.21,.53),
        ("boiler_priming",.75,119,1640,"reload",.54,.67),
        ("boiler_release",.51,87,2870,"heavy",.68,.76),
        ("chalk_cough",.50,157,2200,"grunt_a",1.10,.64),
        ("chalk_spit",.24,175,2870,"swallow_alt",1.23,.61),
        ("chalk_pop",.26,110,2420,"foot_mud_0",1.10,.52),
        ("rudy_warn",.83,181,2430,"holler_b",.80,.69),
        ("rudy_horn",.60,285,2630,"reload",.54,.65),
        ("foreman_warn",.87,127,2750,"reload_alt",.77,.69),
        ("foreman_cut",.44,243,3010,"rifle_c",.50,.72),
        ("baron_warn",.94,101,2210,"grunt_b",.63,.73),
        ("fair_bell",.89,469,3450,"reload_alt",.61,.63),
        ("brake_ratchet",.64,146,3200,"reload",.73,.61),
        ("distant_quarry_pipe",1.30,128,2160,"reload_alt",.51,.43),
        ("distant_quarry_bottler",1.14,233,2800,"bottle_clink",.81,.47),
    )
    for name,length,pitch,top,source,pace,volume in actions:
        t=time(length)
        plate=eq(take(source,length,pace),75,top)
        breath=eq(rng.uniform(-1,1,t.shape),245,top)*(.75 if "vent" in name or "boiler" in name else .29)
        ring=(osc(t,pitch+19*osc(t,2.7))+.18*osc(t,2.27*pitch))*decay(t,7.5)
        env=np.minimum(1.,t*(15 if "warn" in name or "priming" in name else 75))*np.exp(-t*2.7)
        write(name,edge(peak(np.tanh(plate*.82+breath*env+ring*.13),volume),.004,.052))
    for name,tones in (("shakedown",(40,43,41,35)),("rudy",(54,50,57,42)),
                       ("foreman",(31,43,38,35)),("baron",(35,39,42,37))):
        for kind in ("intro","end"):
            track=np.zeros(round(RATE*1.62))
            for i,note in enumerate(tones if kind=="intro" else tones[::-1]):
                at=(.0,.22,.52,.89)[i]
                add(track,pluck(note,.67,"lead",bend=(0,24,-26,0)[i]),at,.37)
                add(track,pluck(note-12,.39,"bass"),at,.19)
            add(track,eq(take("snare_alt",.34,.74),120,4500),.02,.22)
            write(f"{name}_{kind}",edge(peak(np.tanh(track*1.26),.64),.011,.12))


def make_audio():
    rng = np.random.default_rng(421911)
    beds(rng)
    devices_and_tells(rng)
    quarry_sounds(rng)
    from soundtrack_production import make_tracks
    make_tracks(write)


if __name__ == "__main__":
    make_audio()
