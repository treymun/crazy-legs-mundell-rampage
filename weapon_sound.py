"""Offline armory transients, mechanisms and space tails."""
import math

import numpy as np

from sound_production import RATE, close_loop, delay, edge, eq, peak, take, time


# Stems stay stable. Distinct source plates, body pitch, duration and decay
# preserve the report family of each tool.
REPORTS = {
    "crowbar":(.24,None,154,8.,(.014,.059),.46),
    "revolver":(.34,"pistol_a",128,25.,(.002,.071),.81),
    "shotgun":(.51,"shotgun",77,12.,(.004,.118),.88),
    "crossbow":(.41,"reload_alt",176,14.,(.011,.058),.76),
    "rifle":(.28,"rifle_a",147,31.,(.003,.035),.80),
    "ripsaw":(.36,None,269,12.,(.001,.064),.63),
    "armgun":(.44,None,303,8.,(.015,.096),.65),
    "match_strike":(.44,"bottle_cap",510,18.,(.028,.087),.43),
    "tnt_throw":(.32,None,84,12.,(.039,.109),.45),
    "slingblade":(.29,None,104,12.,(.034,.091),.49),
    "bottle_launcher":(.31,"bottle_cap",126,17.,(.003,.032),.72),
    "riveter":(.30,"reload",201,24.,(.003,.041),.67),
    "pressure_gun":(.53,"reload_alt",117,14.,(.017,.194),.66),
}
EQUIPMENT = {
    "crowbar":(172,216,89),"revolver":(703,413,527),"shotgun":(341,218,506),
    "crossbow":(257,328,489),"rifle":(433,539,317),"ripsaw":(310,268,592),
    "armgun":(419,368,189),"tnt":(122,179,132),"slingblade":(97,136,202),
    "bottle_launcher":(188,246,312),"riveter":(582,401,471),"pressure_gun":(278,366,196),
}
MECHANISMS = {
    "rev_cylinder":(491,.26),"rev_extract":(302,.22),"rev_lock":(645,.19),
    "shot_hinge":(206,.25),"shot_extract":(363,.27),"shot_shell":(472,.21),"shot_lock":(284,.23),
    "bow_hook":(299,.22),"bow_seat":(482,.25),
    "saw_seat":(382,.28),"arm_cell":(214,.33),
    "rocket_breech":(236,.31),"rocket_case":(286,.22),"rocket_seat":(430,.28),"rocket_lock":(324,.26),
    "rivet_mag":(601,.22),"rivet_strip":(427,.19),"rivet_lock":(379,.26),
    "pressure_seal":(196,.32),"pressure_charge":(349,.29),
}
REPORT_CONTACTS = {
    "crowbar":("reload_alt",225,.029,.27),"revolver":("reload",633,.044,.18),
    "shotgun":("heavy",83,.023,.30),"crossbow":("reload_alt",343,.027,.31),
    "rifle":("rifle_c",198,.016,.19),"ripsaw":("crash",365,.046,.24),
    "armgun":("bottle_clink",270,.062,.19),"match_strike":("reload",720,.036,.16),
    "tnt_throw":("foot_grass_0",111,.064,.27),"slingblade":("crash",94,.051,.26),
    "bottle_launcher":("reload_alt",224,.026,.27),"riveter":("reload_alt",511,.021,.29),
    "pressure_gun":("heavy",119,.042,.25),
}


def spectrum(t, frequency, change, damping):
    phase = math.tau*(frequency*t + change*.032*(1-np.exp(-t/.032)))
    wave = np.sin(phase)+.38*np.sin(phase*1.84)+.16*np.sin(phase*2.61)
    return wave*np.minimum(t*620.,1.)*np.exp(-t*damping)


def make_weapon_audio(write):
    rng=np.random.default_rng(1831)
    rendered={}
    for name,(seconds,plate,frequency,decay,hits,level) in REPORTS.items():
        t=time(seconds)
        source=eq(take(plate,seconds,.86 if name=="shotgun" else 1.06),55,4420) if plate else np.zeros_like(t)
        # The shorter launcher uses the same part of the shared noise stream as
        # its longer predecessor, so the subsequent reports keep their mix.
        noise_frames = round(.57*RATE) if name=="bottle_launcher" else len(t)
        wind=eq(rng.uniform(-1.,1.,noise_frames)[:len(t)],172,2890 if name=="armgun" else 5480)
        sample=source*(.72+.22*np.exp(-t*27.))
        sample+=spectrum(t,frequency,frequency*.67,decay)*(.28 if plate else .48)
        for i,at in enumerate(hits):
            d=np.maximum(0.,t-at)
            sample+=wind*np.minimum(d*480.,1.)*np.exp(-d*(decay+i*12))*(.24 if plate else .62)
        if name in ("pressure_gun","armgun","match_strike"):
            tail=eq(wind,261,1660)
            sample+=tail*np.minimum(1.,t*15.)*np.exp(-t*5.8)*(.41 if name=="pressure_gun" else .32)
        if name in ("crowbar","slingblade","tnt_throw"):
            sample *= np.minimum(1.,t*(21 if name=="slingblade" else 36))
        if name=="ripsaw":
            sample += spectrum(t,143,398,11.)*.45
        if name=="crossbow":
            sample += spectrum(t,352,22,15.)*.39
        if name=="riveter":
            sample += spectrum(np.maximum(0.,t-.047),446,117,31.)*.29
        plate_name,fundamental,at,weight = REPORT_CONTACTS[name]
        contact = eq(take(plate_name,seconds,.95),83 if fundamental<190 else 235,3850)
        dt=np.maximum(0.,t-at)
        sample += weight*delay(contact,at)*np.exp(-dt*21)
        sample += weight*.53*spectrum(dt,fundamental,fundamental*.41,23)
        rendered[name]=edge(peak(np.tanh(sample*1.47),level),.002,.055)
        write(name,rendered[name])
    for name,original,plate in (("revolver_alt","revolver","pistol_b"),("rifle_alt","rifle","rifle_b"),
                                ("rifle_alt2","rifle","rifle_c")):
        source=rendered[original]
        clip=take(plate,len(source)/RATE,.97)
        write(name,edge(peak(np.tanh(source*.57+eq(clip,65,4430)*.76),.80),.002,.055))

    for name,original,offset,level in (("shotgun_both","shotgun",.022,.90),("riveter_pair","riveter",.036,.74)):
        hit=np.pad(rendered[original],(0,round(.07*RATE)))
        rendered[name]=edge(peak(np.tanh(hit+delay(hit,offset)*.79),level),.002,.063)
        write(name,rendered[name])
    for name in ("revolver","shotgun","shotgun_both","rifle","bottle_launcher","riveter","riveter_pair","pressure_gun"):
        samples=np.pad(eq(rendered[name],79,2200),(0,round(.14*RATE)))
        tail=.62*delay(samples,.039)+.39*delay(samples,.081)+.27*delay(samples,.113)
        write("room_"+name,edge(peak(tail,.28),.002,.081))

    for name, tones in EQUIPMENT.items():
        for mode,seconds,gain in (("equip",.27,.27),("dry",.17,.31)):
            t=time(seconds)
            raw=eq(take("reload_alt" if mode=="equip" else "reload",seconds,.79+tones[0]/2000),220,3500)
            x=raw*.33+spectrum(t,tones[0],tones[1]*.31,30.)*.39
            x+=spectrum(np.maximum(0.,t-.074),tones[2],75,33.)*.24
            write(f"{mode}_{name}",edge(peak(x,gain),.003,.040))
    for name,(pitch,length) in MECHANISMS.items():
        t=time(length)
        foley=eq(take("reload",length,.81+pitch/1500),147,3390)
        mix=foley*.56+spectrum(t,pitch,pitch*.51,29)*.24
        mix+=spectrum(np.maximum(0.,t-.082),pitch*.76,90,32.)*.25
        write(name,edge(peak(mix,.43),.002,.045))
    t=time(.74)
    motor=(np.sin(math.tau*133*t+.37*np.sin(math.tau*11*t))
           +.46*np.sin(math.tau*243*t)+.23*np.sin(math.tau*519*t))
    rasp=eq(rng.uniform(-1.,1.,len(t)),244,3890)
    write("saw_motor",close_loop(peak(np.tanh(motor*.68+rasp*.73),.48)))
    write("impact_rivet",edge(peak(spectrum(time(.22),702,339,24),.54)))
    write("impact_pressure",edge(peak(spectrum(time(.31),158,229,16)
                                     +eq(rng.uniform(-1,1,round(.31*RATE)),240,3500)*np.exp(-time(.31)*15),.51)))

    t = time(.30)
    rasp = eq(rng.uniform(-1.,1.,len(t)),960,3860)
    phase = math.tau*(830*t+230*t*t-810*t**3)
    fizz = rasp*(.66+.16*np.sin(math.tau*34*t)) + np.sin(phase)*.20 + np.sin(phase*1.61)*.04
    window = np.minimum(1.,t*35)*np.exp(-t*7.1)
    write("rocket_whistle",edge(peak(fizz*window,.42),.008,.069))

    t = time(.34)
    noise = eq(rng.uniform(-1.,1.,len(t)),180,5100)
    snap = eq(take("pistol_b",.34,1.48),244,5250)*np.exp(-t*31)
    belly = spectrum(t,101,98,29)
    scatter = np.zeros_like(t)
    for offset in (.029,.052,.091):
        tail = np.maximum(t-offset,0.)
        scatter += delay(noise,offset)*np.exp(-tail*53)
    pop = snap*.64+belly*.47+noise*np.minimum(1.,t*680)*np.exp(-t*53)*.67+scatter*.19
    write("rocket_pop",edge(peak(np.tanh(pop*1.35),.84),.001,.059))
