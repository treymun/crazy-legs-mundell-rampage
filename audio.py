"""Produce 16-bit PCM game audio and play it through SDL."""
from pathlib import Path
import math

import numpy as np

from campaign_score import SCORES
from resource_path import IS_WEB, get_resource_path
from score_player import ScorePlayer

AUDIO = Path(get_resource_path("assets/wav"))
RATE = 22050


class LazySamples(dict):
    """Decode a browser sound only when a cue first asks for it."""

    def __init__(self, files):
        super().__init__()
        self.files = files

    def _load(self, name):
        path = self.files.get(name)
        if path is None:
            return None
        import pygame as pg
        try:
            sample = pg.mixer.Sound(path)
        except (pg.error, OSError):
            self.files.pop(name, None)
            return None
        if name.startswith("step_"):
            sample.set_volume(.83)
        self[name] = sample
        return sample

    def __contains__(self, name):
        return dict.__contains__(self, name) or name in self.files

    def __getitem__(self, name):
        if dict.__contains__(self, name):
            return dict.__getitem__(self, name)
        sample = self._load(name)
        if sample is None:
            raise KeyError(name)
        return sample

    def get(self, name, default=None):
        if dict.__contains__(self, name):
            return dict.__getitem__(self, name)
        sample = self._load(name)
        return default if sample is None else sample
RNG = np.random.default_rng(1997)


def time(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def noise(t):
    return RNG.uniform(-1, 1, t.size)


def decay(t, speed):
    return np.minimum(1., t * 550) * np.exp(-speed * t)


def sweep(t, start, end, settle):
    phase = end * t + (start - end) * settle * (1 - np.exp(-t / settle))
    return np.sin(phase * math.tau)


def band(samples, width):
    return np.convolve(samples, np.ones(width) / width, mode="same")


def osc(t, pitch):
    return np.sin(t * pitch * math.tau)


def write(name, samples):
    import wave
    AUDIO.mkdir(parents=True, exist_ok=True)
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as file:
        file.setparams((1 if data.ndim == 1 else data.shape[1], 2, RATE, 0, "NONE", "not compressed"))
        file.writeframes(data.tobytes())


def speech(phonemes):
    """A voiced exciter plus formants gives the short quips an old sampler sound."""
    samples = []
    for seconds, pitch, f1, f2, f3, rough in phonemes:
        t = time(seconds)
        carrier = sum(osc(t, n * (pitch - 11 * t)) / n for n in range(1, 11))
        formants = .52 * osc(t, f1) + .25 * osc(t, f2) + .11 * osc(t, f3)
        env = np.minimum(1., t / .025) * np.minimum(1., (seconds - t) / .038)
        samples.append((.22 * carrier + .21 * carrier * formants + rough * noise(t)) * env)
    return np.concatenate(samples)


def mechanical(name, length, events):
    t = time(length)
    sample = np.zeros_like(t)
    for start, tone, weight in events:
        attack = np.maximum(0., t - start)
        gritty = noise(t) - .56 * band(noise(t), 6)
        ring = .44 * osc(attack, tone) + .20 * osc(attack, tone * 1.68)
        sample += (gritty * .62 + ring) * decay(attack, 28) * weight
    write(name, sample)


def synthesize():
    import wave
    for name, length, volume, speed, pitch in (
            ("revolver", .28, .72, 20, 120), ("shotgun", .43, .95, 12, 77),
            ("explosion", .82, .96, 6, 55), ("enemy", .22, .44, 18, 92),
            ("rifle", .21, .79, 28, 153), ("enemy_pistol", .23, .68, 26, 125),
            ("enemy_scatter", .38, .83, 13, 82)):
        t = time(length)
        n = noise(t)
        heavy = name in ("shotgun", "explosion", "enemy_scatter")
        crack = (n - band(n, 8)) * decay(t, speed * 4.8)
        blast = (band(n, 7) - band(n, 83)) * decay(t, speed * (1.22 if heavy else 1.85))
        slam = sweep(t, pitch * 1.7, pitch * .54, .033 if heavy else .013) * decay(t, speed * 1.32)
        body = (.89 * blast + (.49 if heavy else .30) * slam
                + .59 * band(n, 51) * decay(t, speed * .64))
        report = (1.05 if not heavy else .77) * crack + body
        for delay, gain in ((.025, .19), (.056, .14), (.121, .065)):
            samples = round(delay * RATE)
            report[samples:] += band(report[:-samples], 5) * gain
        write(name, np.tanh(report * 2.15) * volume)
    t = time(.31)
    write("crowbar", ((noise(t) - band(noise(t), 9)) * .20
                      + .33 * sweep(t, 222, 91, .049)) * decay(t, 18))
    t = time(.37)
    write("crossbow", (osc(t, 156 - 92 * t) * .48 + noise(t) * .52) * decay(t, 12) * .65)
    t = time(.28)
    write("reload", (noise(t) * .64 + osc(t, 420) * .21)
          * (decay(t, 32) + .6 * decay(np.maximum(t - .13, 0), 30)) * .53)
    for name, pitch, tail in (("eject", 1730, 26), ("load", 670, 37), ("close", 420, 19)):
        t = time(.19)
        n = noise(t)
        snap = (n * .68 + osc(t, pitch) * .19 + osc(t, pitch * 1.49) * .13) * decay(t, tail)
        write(name, snap * .64)
    with wave.open(str(AUDIO / "shotgun.wav"), "rb") as source:
        blast = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2") / 32767.
    lag = round(.018 * RATE)
    both = np.pad(blast, (0, lag)) * .94 + np.pad(np.roll(blast, 7), (lag, 0)) * .76
    write("shotgun_both", np.tanh(both * 1.42))
    for name, duration, events in (
        ("mag_out", .19, ((.004, 520, .57), (.049, 370, .24))),
        ("mag_in", .23, ((.002, 610, .45), (.086, 378, .52))),
        ("bolt_rack", .28, ((.008, 465, .47), (.086, 740, .38), (.133, 352, .51))),
        ("bow_pull", .26, ((.012, 227, .30), (.095, 340, .22))),
        ("bow_latch", .17, ((.007, 650, .57), (.056, 380, .21))),
        ("saw_latch", .17, ((.003, 810, .45), (.071, 390, .42))),
        ("saw_load", .22, ((.002, 995, .40), (.049, 550, .31), (.116, 800, .34))),
        ("enemy_pump", .27, ((.004, 335, .46), (.101, 517, .39))),
        ("crowbar_hit", .23, ((.001, 117, .74), (.022, 690, .39))),
        ("gate", .63, ((.006, 184, .48), (.110, 276, .36), (.435, 129, .68))),
        ("secret_slide", .55, ((.010, 113, .54), (.168, 178, .28), (.326, 146, .57))),
        ("weapon_pickup", .23, ((.003, 507, .49), (.067, 680, .35))),
        ("key_pickup", .27, ((.002, 1028, .54), (.072, 1483, .47))),
        ("metal_down", .46, ((.001, 220, .45), (.118, 375, .38), (.246, 176, .55))),
        ("football_bounce", .22, ((.003, 99, .50), (.046, 211, .21))),
        ("tnt_bounce", .18, ((.002, 125, .31), (.029, 245, .13))),
        ("menu_move", .085, ((.001, 735, .19),)),
        ("menu_accept", .16, ((.001, 525, .39), (.05, 724, .26))),
    ):
        mechanical(name, duration, events)
    t = time(.28)
    n = noise(t)
    hiss = (n-band(n,9))*(.78+.22*osc(t,33))
    write("match_strike", hiss*decay(t,13)*.38 + sweep(t,520,212,.018)*decay(t,22)*.11)
    write("tnt_throw", (band(n,8)*.33 + sweep(t,169,82,.05)*.19)*decay(t,13))
    t = time(.72)
    n = noise(t)
    hiss = n-band(n,8)
    write("fuse_hiss", (.083+.065*osc(t,36)**2)*hiss*np.minimum(1,np.minimum(t,.72-t)*145))
    t = time(.55)
    shatter = np.zeros_like(t)
    for start, hz in ((.001,2830),(.022,1950),(.038,2311),(.091,1510),(.142,1917)):
        u = np.maximum(0,t-start)
        grit = noise(t)
        shatter += (.29*sweep(u,hz,hz*.71,.031) + .34*(grit-band(grit,9)))*decay(u,34)
    write("glass_break",np.tanh(shatter*1.31)*.58)
    t = time(1.18)
    run = band(noise(t),12) - band(noise(t),89)
    write("sink_flush",(run*.84+sweep(t,95,62,.17)*.14) *
          np.minimum(t*13,1.)*np.minimum((1.18-t)*4,1.))
    t = time(.34)
    pull = osc(t, 236 - t * 152) * .31 + osc(t, 591 - t * 530) * .22
    write("ripsaw", (pull + band(noise(t), 7) * .49) * decay(t, 10) * .9)
    t = time(.165)
    growl = (osc(t, 113 + t * 330) + .35 * osc(t, 226 + t * 660)) * .35
    write("saw_grind", np.tanh((growl + noise(t) * .55) * 1.43) * decay(t, 8))
    t = time(.24)
    write("saw_hit", (band(noise(t), 9) * .90 + osc(t, 95 - 117 * t) * .36)
          * decay(t, 22) * .72)
    write("saw_bounce", (osc(t, 862 - t * 620) * .50 + osc(t, 1748 - t * 1160) * .29)
          * decay(t, 17) * .72)
    for name, length, base, pitch_change, speed, grit in (
        ("armgun", .42, 480, -790, 8.7, .25),
        ("arm_impact", .47, 196, -220, 10.2, .48),
        ("arm_vent", .30, 211, -82, 14, .33),
        ("arm_charge", .32, 192, 625, 4.5, .21),
        ("arm_ready", .19, 720, 131, 17, .10),
        ("alien_alert", .38, 88, 182, 7, .22),
    ):
        t = time(length)
        phase = (base * t + pitch_change * t**2 / 2) * math.tau
        motor = np.sin(phase + .62 * np.sin(phase * 1.99)) + .22 * np.sin(phase * 2.73)
        write(name, (motor * .42 + band(noise(t), 4) * grit) * decay(t, speed))
    t = time(.26)
    flutter = osc(t, 212 + 190 * t) * .36 + osc(t, 422 + 280 * t) * .16
    write("skeeter", flutter * (.65 + .35 * osc(t, 22)) * decay(t, 5.1))
    write("skeeter_bite", (noise(t) * .37 + osc(t, 147 + 20 * t) * .35) * decay(t, 24))
    write("skeeter_pop", (noise(t) * .43 + osc(t, 183 - 367 * t) * .55) * decay(t, 17))
    t = time(.45)
    whistle = osc(t, 2214 + 37 * np.sin(t * 84)) + .24 * osc(t, 2574 - t * 290)
    whistle *= np.minimum(1., t * 50) * np.minimum(1., (.45 - t) * 28)
    write("whistle", whistle * .24)
    t = time(.34)
    write("football_throw", (band(noise(t), 11) * .90 + .30 * osc(t, 241 - 430 * t))
          * decay(t, 13))
    t = time(1.0)
    call = (osc(t, 261.6) + osc(t, 329.6) * .62 + osc(t, 392) * .43) * decay(t, 5.6)
    slap = decay(np.maximum(t - .34, 0), 9)
    write("jerry_intro", (call * .24 + osc(t, 526) * slap * .18 + band(noise(t), 6) * .04)
          * np.minimum(1., (1 - t) * 50))
    for name, vowel in (
        ("billy_alert", ((.20, 119, 650, 1160, 2350, .05), (.22, 104, 510, 1480, 2570, .07))),
        ("coot_alert", ((.18, 157, 480, 1480, 2650, .11), (.17, 135, 770, 1100, 2300, .08))),
        ("varmint_down", ((.13, 139, 730, 950, 2000, .09), (.28, 73, 520, 980, 2060, .13))),
        ("player_down", ((.14, 117, 475, 1200, 2460, .13), (.32, 66, 720, 830, 2180, .15))),
        ("pig", ((.16, 93, 310, 820, 1750, .15), (.18, 81, 420, 760, 1580, .12))),
    ):
        write(name, speech(vowel))
    t = time(.39)
    cluck = osc(t, 431 - 470 * t) * (.62 + .38 * osc(t, 12))
    write("chicken", (cluck * .46 + band(noise(t), 6) * .26) * decay(t, 8.2))
    write("crunch", (noise(t) - band(noise(t), 7))
          * (decay(t, 25) + .75 * decay(np.maximum(t - .13, 0), 30)) * .38)
    t = time(.53)
    write("moonshine", (osc(t, 112 + 49 * osc(t, 7)) * .38 + band(noise(t), 8) * .23)
          * decay(t, 3.8) * (.42 + .58 * osc(t, 5)**2))
    belch = osc(t, 89 + 35 * osc(t, 7.2)) + .38 * osc(t, 165 - 72 * t)
    write("belch", belch * decay(t, 4.5) * .31)
    t = time(.63)
    write("gulp", osc(t, 111 + np.sin(t * 25) * 32) * (osc(t, 6) ** 2) * decay(t, 3) * .34)
    t = time(.43)
    write("door", (.63 * np.convolve(noise(t), np.ones(5) / 5, "same") + osc(t, 62) * .19)
          * decay(t, 4) * .47)
    t = time(.32)
    write("pickup", (osc(t, 270 + 620 * t) + osc(t, 408 + 760 * t) * .45) * decay(t, 8) * .28)
    t = time(.39)
    write("plasma", (osc(t, 240 - 175 * t) + .44 * osc(t, 395 - 218 * t)) * decay(t, 6) * .29)
    t = time(.35)
    write("empty", (noise(t) * .4 + osc(t, 430) * .27) * decay(t, 42) * .36)
    write("hurt", speech(((.10, 99, 380, 1210, 2380, .14), (.17, 77, 660, 870, 2150, .08))))
    write("yee_haw", speech(((.09, 155, 280, 2170, 2650, .05), (.24, 178, 345, 2080, 2750, .03),
                             (.09, 124, 480, 1470, 2330, .29), (.29, 117, 710, 905, 2280, .07))))
    write("got_bessie", speech(((.10, 110, 630, 1020, 2340, .11), (.13, 103, 740, 1060, 2370, .08),
                                (.13, 130, 560, 1710, 2450, .05), (.08, 109, 400, 1770, 3100, .23),
                                (.22, 114, 340, 2040, 2660, .02))))
    for kind, bass, crunch in (("gravel", 61, .48), ("wood", 98, .18), ("tile", 136, .31)):
        for step in (0, 1):
            t = time(.17)
            n = noise(t)
            shoe = .42 * osc(t, bass + 9 * step - t * 80) + crunch * (n - band(n, 7))
            write(f"step_{kind}_{step}", shoe * decay(t, 22 + step * 5) * .30)
    t = time(.26)
    write("ricochet", (osc(t, 1620 - 650 * t) + osc(t, 2100 - 1300 * t) * .46)
          * decay(t, 31) * .18)
    t = time(.34)
    early = .32 * band(noise(t), 14) + .16 * sweep(t, 163, 49, .04)
    echo = np.zeros_like(t)
    for delay, level in ((.018, .75), (.043, .58), (.071, .43), (.105, .32)):
        i = round(delay * RATE)
        echo[i:] += early[:-i] * decay(t[:-i], 17) * level
    write("report_room", echo)
    for kind, bass, grit in (("mud", 69, .21), ("grass", 98, .34), ("water", 159, .52)):
        for step in (0, 1):
            t = time(.24)
            n = noise(t)
            grit_sound = (n - band(n, 11)) * (1 if kind == "grass" else .57)
            tail = decay(np.maximum(t - .038, 0), 31)
            sole = sweep(t, bass * 1.5 + 6 * step, bass * .49, .047)
            write(f"step_{kind}_{step}", (sole * .32 + grit_sound * grit) * decay(t, 21)
                  + grit_sound * tail * grit * (.5 if kind == "water" else .16))
    t = time(.68)
    call = sweep(t, 549, 283, .15) + .52 * sweep(t, 1373, 510, .23)
    write("distant_crow", call * (.69 + .31 * osc(t, 21)) * decay(t, 4.8) * .26)
    bark = np.zeros_like(t)
    for delay, gain in ((.0, 1.), (.28, .62)):
        q = np.maximum(0, t - delay)
        bark += gain * (sweep(q, 257, 81, .074) * .6 + band(noise(t), 9) * .75) * decay(q, 15)
    write("distant_dog", bark * .42)
    t = time(7)
    crickets = np.zeros_like(t)
    for pitch, rate, offset in ((3350, 1.33, 0), (2870, .99, .54), (4080, .68, 1.06)):
        chirp = np.maximum(0, osc(t + offset, rate))**14 * np.maximum(0, osc(t, 17))**2
        crickets += osc(t, pitch) * chirp * .040
    edges = np.minimum(1., np.minimum(t, 7 - t) * 8)
    wind = band(noise(t), 181) * (.24 + .16 * osc(t, .43))
    write("amb_yard", (crickets + wind) * edges)
    room = osc(t, 60) * .018 + osc(t, 120) * .013 + band(noise(t), 31) * .032
    write("amb_room", room * edges)
    write("amb_barn", (crickets * .36 + wind * .68 + osc(t, 83) * .011 *
                       (.48 + .52 * osc(t, .43))) * edges)
    water = (band(noise(t), 24) * .28 + band(noise(t), 71) * .13) * (.76 + .20 * osc(t, 1.2))
    write("amb_creek", (water + crickets * .46 + wind * .45) * edges)
    from sound_production import field_mix, make_score, weapon_mix
    weapon_mix(write)
    field_mix(write)
    synthesize_encounters()
    make_score(write)
    from expansion_audio import make_audio
    make_audio()
    from scenery_audio import make_scenery_audio
    make_scenery_audio(write)
    from weapon_sound import make_weapon_audio
    make_weapon_audio(write)
    from chatter_audio import bake as bake_chatter
    from signature_audio import bake as bake_signatures
    bake_chatter(write)
    bake_signatures(write)
    from room_zones import bake as bake_rooms
    bake_rooms()


def synthesize_encounters():
    from sound_production import edge, eq, peak, take
    for name, plate, length, pace, high, level in (
        ("enemy","rifle_c",.25,.89,2780,.56),
        ("enemy_pistol","pistol_b",.26,.93,2910,.56),
        ("enemy_scatter","shotgun",.39,.84,2450,.65),
        ("enemy_pump","reload",.25,.87,2400,.52),
        ("clone_bolt","reload",.22,1.18,3800,.36),
        ("coot_cock","reload_alt",.17,1.18,3900,.31),
        ("clone_alert","holler_a",.48,.91,3100,.37),
        ("coot_alert","grunt_b",.29,1.27,2900,.48),
        ("billy_alert","grunt_a",.39,.80,2800,.45),
    ):
        write(name,edge(peak(eq(take(plate,length,pace),85,high),level)))
    for name, length, base, drift, speed, rough in (
        ("skeeter_dive",.36,167,430,4.6,.19),
        ("guard_charge",.35,213,755,3.6,.11),
        ("saucer_spot",.37,276,-308,5.9,.16),
        ("saucer_charge",.56,268,800,2.7,.16),
        ("saucer_shot",.31,421,-938,8.4,.17),
        ("sheriff_spot",.44,138,-110,4.7,.23),
        ("sheriff_siren",.49,552,446,2.7,.20),
        ("sheriff_shot",.44,240,-335,6.2,.22),
    ):
        t=time(length)
        phase=(base*t + drift*t*t*.5)*math.tau
        phase+=.27*osc(t,12 if name.startswith("sheriff") else 21)
        motor=np.sin(phase + .73*np.sin(phase*1.81)) + .26*np.sin(phase*2.42)
        flutter=.69+.31*osc(t,36 if name=="skeeter_dive" else 14)**2
        write(name,edge((motor*.39+rough*band(noise(t),5))*flutter*decay(t,speed),.012,.042))
    actor_foley()


def actor_foley():
    from sound_production import delay, edge, eq, peak, take

    shout = eq(take("holler_b",.46,.94),125,3070)
    write("county_fall_back",edge(peak(shout,.64),.008,.060))
    for name,plate,length,rate,top in (("plaster","crash",.14,1.32,3600),("dirt","foot_mud_1",.13,1.29,1500)):
        write("impact_"+name,edge(peak(eq(take(plate,length,rate),135,top),.44),.002,.042))

    for material,clip,length,pace,upper,weight in (
        ("cloth","grunt_b",.28,1.05,3250,92),
        ("shell","bottle_clink",.29,.86,3060,185),
        ("tool","reload_alt",.32,.80,3210,125),
    ):
        for event in ("pain","down"):
            down = event=="down"
            seconds = length+(.26 if down else 0.)
            t = time(seconds)
            field = eq(take(clip,seconds,pace*(.82 if down else 1.)),110,upper)
            contact = eq(take("heavy",seconds,.88 if material=="tool" else 1.08),54,1300)
            note = .21*osc(t,weight)*decay(t,19)
            if material=="cloth" and down:
                field = field*.49+eq(take("grunt_down",seconds,1.05),100,upper)*.79
            if down:
                contact = delay(contact,.13 if material=="tool" else .09)
            sound = field*.78+contact*(.60 if down else .27)+note
            write(f"actor_{material}_{event}",edge(peak(np.tanh(sound*1.3),.63 if down else .48),.004,.064))


class Sound:
    PRIORITY = frozenset(("revolver","shotgun","shotgun_both","rifle","armgun","explosion","hurt",
                          "player_down","glass_break","match_strike","pressure_gun","riveter_pair",
                          "bottle_launcher","rocket_pop"))
    WARNS = frozenset(("boiler_priming","chalk_cough","rudy_warn","foreman_warn","baron_warn",
                       "sheriff_siren","whistle","barker_wind","millhand_rev","lantern_charge",
                       "deputy_work","tosser_rattle","chain_raise","rat_hiss",
                       "saucer_charge","guard_charge","skeeter_dive","enemy_pump","coot_cock","clone_bolt",
                       "pressure_vent"))
    REPORT_GAIN = {"revolver":.84,"shotgun":.82,"shotgun_both":.64,"rifle":.83,
                   "explosion":.82,"rocket_pop":.88,"riveter_pair":.88,"bottle_launcher":.94,
                   "crowbar":.77,"slingblade":.72,"sling_hit":.70,"ripsaw":.62,"saw_bounce":.56,
                   "saw_hit":.58,"armgun":.79,
                   # Keep the report and warning cues clear when a blast downs an actor.
                   "actor_cloth_down":.75,"actor_shell_down":.75,"actor_tool_down":.75}
    TOOL_GAIN = .26
    VARIANTS = {"rifle":("rifle","rifle_alt","rifle_alt2"),"revolver":("revolver","revolver_alt"),
                "hurt":("hurt","hurt_alt","hurt_alt2"),"yee_haw":("yee_haw","yee_haw_alt")}
    STREAMS = {"title","victory",*(track for bank in SCORES.values() for track in bank)}

    def __init__(self):
        import pygame as pg
        self.pg = pg
        self.music = False
        self.score_player = None
        self.score = "title"
        self.variations = {}
        self.samples = {}
        self.room = None
        self.ambience = ()
        self.room_slot = 0
        self.radio = None
        self.priority = None
        self.fuse = None
        self.warning = None
        self.warning_alt = None
        self.score_sting = None
        self.tool = None
        self.voice = None
        self.radio_gain = 0.
        self.effects_gain = 1.
        self.footstep_gain = 1.
        self.voice_gain = .8
        self.music_gain = .50
        self.ambient_gain = 1.
        self.mix_headroom = 1.
        self.pan_width = .70
        if pg.mixer.get_init():
            self.score_player=ScorePlayer(pg.mixer.music,AUDIO)
            files = {}
            for path in sorted(AUDIO.iterdir()):
                if path.suffix.lower() not in (".wav", ".ogg", ".opus"):
                    continue
                if path.stem in self.STREAMS:
                    continue
                if path.suffix.lower() == ".wav" or path.stem not in files:
                    files[path.stem] = path
            if IS_WEB:
                # Browsers choke when every one of the ~320 effects is decoded up
                # front, so the web build resolves files the first time they play.
                self.samples = LazySamples(files)
            else:
                for stem, path in files.items():
                    sample = pg.mixer.Sound(path)
                    if stem.startswith("step_"):
                        # Keep headroom when a footfall overlaps the saw and a hit cue.
                        sample.set_volume(.83)
                    self.samples[stem] = sample
            pg.mixer.music.set_volume(.50)
            pg.mixer.set_num_channels(24)
            pg.mixer.set_reserved(10)
            self.ambience = (pg.mixer.Channel(0), pg.mixer.Channel(1))
            self.radio = pg.mixer.Channel(2)
            self.priority = pg.mixer.Channel(3)
            self.fuse = pg.mixer.Channel(4)
            self.warning = pg.mixer.Channel(5)
            self.score_sting = pg.mixer.Channel(6)
            self.tool = pg.mixer.Channel(7)
            self.voice = pg.mixer.Channel(8)
            self.warning_alt = pg.mixer.Channel(9)
            self.toggle_music()

    def play(self, name, volume=1., pan=0.):
        variation = self.VARIANTS.get(name)
        if variation:
            index = self.variations.get(name,0)
            sample = self.samples.get(variation[index%len(variation)],self.samples.get(name))
            self.variations[name] = index+1
        else:
            sample = self.samples.get(name)
        if sample and self.effects_gain:
            channel = None
            if name in self.WARNS:
                if sample.get_num_channels():
                    return
                warnings = (self.warning,self.warning_alt)
                channel = next((active for active in warnings if active and not active.get_busy()),None)
                if channel is not None:
                    channel.play(sample)
            if channel is None:
                channel = sample.play()
            if channel is None:
                channel=self.priority if name in self.PRIORITY else None
                if channel:
                    channel.play(sample)
            if channel:
                scale = (self.ambient_gain if name.startswith("distant_") else
                         self.footstep_gain if name.startswith("step_") else
                         .72 if name.startswith("room_") else self.REPORT_GAIN.get(name,1.))
                gain = min(1.,self.effects_gain*volume*scale)*.82*self.mix_headroom
                channel.set_volume(gain * (1 - max(0., pan) * self.pan_width),
                                   gain * (1 + min(0., pan) * self.pan_width))

    def set_room(self, room):
        name = None if room is None else "amb_" + room
        if self.ambience and self.room != name:
            self.room = name
            self.ambience[self.room_slot].fadeout(330)
            self.room_slot ^= 1
            if name in self.samples:
                channel = self.ambience[self.room_slot]
                channel.play(self.samples[name], loops=-1, fade_ms=330)
                channel.set_volume(.78*self.ambient_gain*self.mix_headroom)

    def set_radio(self, playing, volume=0., pan=0.):
        if self.radio is None:
            return
        sample = self.samples.get("jukebox")
        if playing and sample:
            if not self.radio.get_busy():
                self.radio.play(sample,loops=-1)
            gain = self.effects_gain*volume*self.mix_headroom
            self.radio.set_volume(gain*(1-max(0.,pan)*self.pan_width),
                                  gain*(1+min(0.,pan)*self.pan_width))
        elif self.radio.get_busy():
            self.radio.stop()
        gain = min(.80,volume*1.28) if playing else 0.
        if abs(self.radio_gain-gain) >= .018 or not playing and self.radio_gain:
            self.radio_gain = gain
            self.score_player.level(self.music_gain*(1-gain))

    def set_levels(self, effects, music, ambience=1., stereo=2):
        # Reserve peak room when loud music and combat play together.
        # Keep the stock mix and the balance between warnings and reports.
        self.mix_headroom = 1.-.14*effects*max(0.,2*music-1.)
        self.effects_gain = effects
        self.music_gain = music*.86*self.mix_headroom
        self.ambient_gain = ambience
        self.pan_width = (0., .35, .70, .93)[stereo]
        if self.pg.mixer.get_init():
            self.score_player.level(self.music_gain*(1-self.radio_gain))
            if self.ambience:
                self.ambience[self.room_slot].set_volume(.78*ambience*self.mix_headroom)
            if self.fuse is not None and self.fuse.get_busy():
                self.fuse.set_volume(.64*effects*self.mix_headroom)
            if self.tool is not None and self.tool.get_busy():
                self.tool.set_volume(self.TOOL_GAIN*effects*self.mix_headroom)
            self.score_sting.set_volume(.84*self.music_gain)

    def set_fuse(self, burning):
        if self.fuse is None:
            return
        if burning and not self.fuse.get_busy() and "fuse_hiss" in self.samples:
            self.fuse.play(self.samples["fuse_hiss"],loops=-1)
            self.fuse.set_volume(.64*self.effects_gain*self.mix_headroom)
        elif not burning and self.fuse.get_busy():
            self.fuse.stop()

    def set_tool(self, active):
        if self.tool is None:
            return
        if active and not self.tool.get_busy() and "saw_motor" in self.samples:
            self.tool.play(self.samples["saw_motor"],loops=-1,fade_ms=28)
            self.tool.set_volume(self.TOOL_GAIN*self.effects_gain*self.mix_headroom)
        elif not active and self.tool.get_busy():
            self.tool.stop()

    def play_voice(self, name, volume, pan):
        sample = self.samples.get(name)
        if self.voice is None or sample is None:
            return 1.55
        if self.voice_gain and not (self.voice.get_busy() and self.voice.get_sound()==sample):
            gain = volume*self.voice_gain*.88*self.mix_headroom
            self.voice.play(sample)
            self.voice.set_volume(gain*(1-max(0.,pan)*self.pan_width),
                                  gain*(1+min(0.,pan)*self.pan_width))
        return sample.get_length()

    def stop_voice(self):
        if self.voice is not None:
            self.voice.stop()

    def pause_world(self):
        self.set_room(None)
        self.set_radio(False)
        self.set_fuse(False)
        self.set_tool(False)
        self.stop_voice()
        for name in self.WARNS:
            if name in self.samples:
                self.samples[name].stop()
        if self.priority:
            self.priority.stop()

    def set_score(self, cue):
        if cue != self.score and self.score_sting:
            self.score_sting.stop()
        self.score=cue
        if self.score_player:
            self.score_player.request(cue)

    def pause_score(self,paused):
        if self.score_player:
            self.score_player.pause(paused)
            if paused:
                self.score_sting.pause()
            else:
                self.score_sting.unpause()

    def tick_score(self,dt):
        if self.score_player:
            self.score_player.update(dt)

    def bookmark_score(self,context):
        return self.score_player.bookmark(context) if self.score_player else None

    def restore_score(self,context,value):
        if self.score_player:
            self.score_player.restore(context,value)

    def sting(self,cue):
        sample=self.samples.get(cue)
        if self.music and sample and self.score_sting:
            self.score_sting.play(sample)
            self.score_sting.set_volume(.84*self.music_gain)

    def toggle_music(self):
        if self.score_player:
            self.music = not self.music
            self.score_player.set_enabled(self.music)
            if not self.music:
                self.score_sting.stop()


if __name__ == "__main__":
    synthesize()

