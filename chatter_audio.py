"""Bake original filtered two-way radio voices using short formant gestures."""
import numpy as np

from audio import RATE, band, time
from chatter import EXCHANGES
from county_events import HUB_DISPATCH

WORDS = {
    "WHO":"H U", "TOOK":"T U K", "THE":"D X", "TRUCK":"T R A K",
    "ASK":"AE S K", "PIG":"P I G", "KEEP":"K EE P", "KEY":"K EE",
    "DRY":"D R AI", "THEN":"D E N", "FIX":"F I K S", "ROOF":"R U F",
    "SAVE":"S EI V", "THAT":"D AE T", "ROPE":"R O P", "FOR":"F O R",
    "SHOW":"SH O", "CLEAR":"K L EE R", "STAGE":"S T EI J",
    "TELL":"T E L", "GOAT":"G O T", "HEAR":"H EE R", "BELT":"B E L T",
    "SOUNDS":"S AW N D Z", "LIKE":"L AI K", "TEETH":"T EE TH",
    "KILL":"K I L", "DRIVE":"D R AI V", "YOU":"Y U", "FIRST":"F X R S T",
    "TASTE":"T EI S T", "MUD":"M A D", "NEEDS":"N EE D Z",
    "MORE":"M O R", "SALT":"S O L T", "CLOSE":"K L O Z",
    "TAP":"T AE P", "WHICH":"W I CH", "RED":"R E D", "ONE":"W A N",
    "LOOK":"L U K","HOG":"H O G","IS":"I Z","HOME":"H O M","CHECK":"CH E K",
    "BLUE":"B L U","TRUNK":"T R A N K","LAST":"L AE S T","LOAD":"L O D","TAG":"T AE G",
}
FORMANTS = {
    "U":(340,850,2350), "X":(450,1350,2050), "A":(720,1150,2480),
    "AE":(690,1740,2600), "I":(420,1970,2610), "EE":(300,2210,3030),
    "E":(530,1820,2450), "O":(450,920,2450), "R":(410,1130,1550),
    "N":(260,1530,2480), "M":(290,870,2290), "L":(440,1250,2540),
    "W":(320,760,2240), "Y":(310,2050,2800), "AI":("A","EE"),
    "EI":("E","EE"), "AW":("A","U"),
}
FRICATION = {"S":.87,"Z":.76,"SH":.66,"CH":.64,"J":.55,"TH":.47,"F":.47,"V":.39,"H":.28}


def line(phrase, second, rng):
    chunks = [np.zeros(int(RATE*.08))]
    words = phrase.split(": ",1)[1].rstrip("?.").split()
    syllable = 0
    for word in words:
        for phone in WORDS[word].split():
            voiced = phone in FORMANTS
            bend = FORMANTS.get(phone, ())
            length = (.144 if len(bend)==2 else .098 if voiced else
                      .064 if phone in FRICATION else .048)
            t = time(length)
            n = rng.normal(0., .33, t.shape)
            envelope = np.minimum(1., t/.017)*np.minimum(1., (length-t)/.020)
            if voiced:
                start,end = (tuple(np.array(FORMANTS[key]) for key in bend)
                             if len(bend)==2 else (np.array(bend),np.array(bend)))
                formants = start[:,None]+(end-start)[:,None]*(t/length)**1.3
                pitch = (126 if second else 98) + 8*np.sin(syllable*1.4) - 17*t
                phase = np.cumsum(pitch)*2*np.pi/RATE
                data = np.zeros_like(t)
                for harmonic in range(1,32):
                    weight = np.exp(-.5*((formants-harmonic*pitch)/np.array(((112,),(154,),(235,))))**2)
                    data += np.sin(harmonic*phase)*(weight[0]+.62*weight[1]+.37*weight[2])/harmonic**.69
                sample = .53*data + .11*n
                syllable += 1
            elif phone in FRICATION:
                edge = FRICATION[phone]
                sample = (n-band(n,7))*edge + band(n,9)*(.90-edge)
            else:
                release = np.maximum(0.,t-.019)
                sample = n*(release>0)*np.exp(-release*105)
            chunks.append(envelope*sample)
        chunks.append(np.zeros(int(RATE*.024)))
    chunks.append(np.zeros(int(RATE*.08)))
    signal = np.concatenate(chunks)
    filtered = band(signal,4)-.88*band(signal,36)
    return .73*np.tanh(filtered/(.11+np.max(np.abs(filtered))*.34))


def bake(write):
    rng = np.random.default_rng(446)
    for exchanges in EXCHANGES.values():
        for exchange in exchanges:
            for index,phrase in enumerate(exchange.lines):
                write(f"talk_{exchange.id}_{index}",line(phrase,index==1,rng))
    for index,(_,_,phrase) in enumerate(HUB_DISPATCH):
        write(f"county_dispatch_{index}",line(phrase,False,rng))
