"""Bounded offline cues for authored breakables and mechanisms."""
import math

import numpy as np

from sound_production import RATE, edge, eq, peak, take, time


def make_scenery_audio(write):
    rng=np.random.default_rng(315)
    for name,duration,hits,top,level in (
        ("cans",.56,((.004,616),(.094,452),(.19,717),(.27,383)),4400,.43),
        ("prize",.34,((.003,163),(.061,249),(.13,312)),2400,.52),
        ("scrap",.46,((.005,128),(.031,232),(.076,414),(.21,157)),3150,.55),
        ("belt",.50,((.003,118),(.044,292),(.118,433),(.27,99)),2400,.53),
        ("pipe",.71,((.006,337),(.061,520),(.112,264)),3400,.46),
    ):
        t=time(duration)
        grit=eq(rng.uniform(-1.,1.,len(t)),124,top)
        sample=np.zeros_like(t)
        for i,(start,freq) in enumerate(hits):
            delta=np.maximum(0.,t-start)
            env=np.minimum(1.,delta*420)*np.exp(-delta*(13+i*3))
            ring=sum(np.sin(math.tau*freq*ratio*delta)*amount
                     for ratio,amount in ((1.,.48),(1.41,.25),(2.72,.10)))
            sample+=(ring+grit*.57)*env/(i*.45+1)
        if name=="pipe":
            sample+=eq(grit,200,1590)*np.minimum(t*20,1)*np.exp(-t*5)*.83
        write(f"scenery_{name}",edge(peak(sample,level)))
