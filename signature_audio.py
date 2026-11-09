"""Distinct source, action and impact sounds for the four county-wing roles."""
import numpy as np

from audio import band, decay, osc, sweep, time


def bake(write):
    rng = np.random.default_rng(8017)
    cues = (
        ("deputy_work",.47,((.01,235,.59),(.16,482,.57),(.34,182,.27)),5),
        ("deputy_shot",.31,((.00,122,1.),(.09,97,.19),(.18,83,.085)),8),
        ("tosser_rattle",.52,((.02,710,.25),(.06,566,.27),(.23,955,.49),(.39,729,.23)),4),
        ("tosser_throw",.29,((.01,190,.25),(.13,337,.33)),2),
        ("tosser_glass",.34,((.00,1140,.77),(.035,2342,.42),(.064,1758,.39),(.133,2219,.24)),3),
        ("chain_raise",.70,((.00,301,.37),(.11,668,.48),(.31,473,.31),(.47,218,.38)),8),
        ("chain_crack",.46,((.03,244,.56),(.08,1190,.71),(.142,292,.55),(.29,142,.29)),3),
        ("rat_hiss",.66,((.00,367,.32),(.13,492,.38),(.27,651,.35),(.44,587,.46)),5),
        ("rat_blow",.36,((.00,131,.79),(.08,341,.41),(.17,173,.31)),8),
    )
    for name,length,pulses,width in cues:
        t = time(length)
        source = rng.uniform(-1.,1.,len(t))
        hiss = band(source,width)-.7*band(source,width*7)
        sample = np.zeros_like(t)
        for start,frequency,gain in pulses:
            age = np.maximum(0.,t-start)
            ring = .49*sweep(age,frequency*1.46,frequency,.043)+.17*osc(age,frequency*2.33)
            sample += gain*(.67*hiss+ring)*decay(age, 29 if name!="rat_hiss" else 14)
        write(name,.87*np.tanh(sample))

    # When power is cut, leave only wind and sheet-metal chatter in the same spaces.
    t = time(11.6)
    air = band(rng.uniform(-1.,1.,len(t)),138)
    gust = (.57+.32*osc(t,.259)+.11*osc(t,.603))
    quarry = air*gust*.63+.011*osc(t,119)*np.maximum(0.,osc(t,.18))
    fair = air*gust*.57+.018*osc(t,231)*np.maximum(0.,osc(t,.264))**12
    blend = np.minimum(1.,np.minimum(t,11.6-t)/.09)
    write("amb_quarry_after",quarry*blend)
    write("amb_fair_after",fair*blend)
