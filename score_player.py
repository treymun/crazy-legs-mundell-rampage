"""Single-stream chapter music with shuffled bags, fades and resumable Opus seeks."""
from functools import lru_cache
from io import BytesIO
import json
import random

from campaign_score import SCORES
from resource_path import IS_ANDROID, IS_WEB

FADE = .24
CODA_FADE = .12


class ShuffleBank:
    def __init__(self,tracks,rng):
        self.tracks,self.rng = tracks,rng
        self.bag=[]
        self.track=None
        self.offset=0.

    def advance(self):
        if not self.bag:
            self.bag=list(self.tracks)
            self.rng.shuffle(self.bag)
            if self.bag[-1]==self.track:
                self.bag[-1],self.bag[0] = self.bag[0],self.bag[-1]
        self.track=self.bag.pop()
        self.offset=0.


@lru_cache(maxsize=8)
def manifest(folder):
    marker = folder/"durations.json"
    return json.loads(marker.read_text(encoding="utf-8")) if marker.is_file() else {}


@lru_cache(maxsize=20)
def duration(path):
    if path.suffix in (".opus", ".ogg"):
        for folder in (path.parent, path.parent.parent/"music"):
            lengths = manifest(folder)
            if path.stem in lengths:
                return lengths[path.stem]
        return 0.
    import wave
    with wave.open(str(path),"rb") as stream:
        return stream.getnframes()/stream.getframerate()


@lru_cache(maxsize=4)
def playback_ends(folder):
    marker = folder/"playback_ends.json"
    return json.loads(marker.read_text(encoding="utf-8")) if marker.is_file() else {}


def tail_from(path,offset):
    """SDL's WAV decoder starts at the first frame. Present the remaining PCM."""
    import wave
    pcm=BytesIO()
    with wave.open(str(path),"rb") as source:
        start=min(source.getnframes()-1,round(offset*source.getframerate()))
        source.setpos(max(0,start))
        with wave.open(pcm,"wb") as tail:
            tail.setparams(source.getparams())
            tail.writeframes(source.readframes(source.getnframes()-start))
    pcm.seek(0)
    return pcm


class ScorePlayer:
    def __init__(self,device,directory,*,seed=None):
        self.device,self.directory=device,directory
        rng=random.Random(seed)
        self.banks={key:ShuffleBank(tracks,rng) for key,tracks in SCORES.items()}
        self.files={}
        self.requested="title"
        self.active=None
        self.track=None
        self.buffer=None
        self.offset=0.
        self.end=0.
        self.last_position=0.
        self.gain=0.
        self.master=.5
        self.enabled=False
        self.paused=False
        self.reopen=False

    def request(self,context):
        self.requested=context
        if self.active is None and self.enabled and not self.paused:
            self.start(context)

    def level(self,gain):
        self.master=gain
        self.device.set_volume(self.master*self.gain)

    def set_enabled(self,value):
        self.enabled=value
        self.sync_pause()

    def pause(self,value):
        if self.paused!=value:
            self.paused=value
            self.sync_pause()

    def sync_pause(self):
        if not self.enabled or self.paused:
            self.time()
            self.device.pause()
        elif self.active is None:
            self.start(self.requested)
        else:
            self.device.unpause()

    def time(self):
        position=self.device.get_pos()
        if position>=0:
            self.last_position=self.offset+position/1000
        return self.last_position

    def path(self, track):
        if track not in self.files:
            music = self.directory.parent/"music"
            order = (".ogg", ".opus") if IS_ANDROID or IS_WEB else (".opus", ".ogg")
            for suffix in order:
                encoded = music/f"{track}{suffix}"
                if encoded.is_file():
                    self.files[track] = encoded
                    break
            else:
                order = (".ogg", ".opus", ".wav") if IS_ANDROID or IS_WEB else (".wav", ".ogg", ".opus")
                for suffix in order:
                    direct = self.directory/f"{track}{suffix}"
                    if direct.is_file():
                        self.files[track] = direct
                        break
                else:
                    self.files[track] = self.directory/f"{track}.wav"
        return self.files[track]

    def play_end(self,track):
        path = self.path(track)
        encoded = path.suffix in (".opus", ".ogg")
        folder = path.parent if encoded else path.parent.parent/"music"
        length = duration(path)
        return min(length,playback_ends(folder).get(track,length))

    def start(self,context,store=True):
        if store and self.active in self.banks:
            bank=self.banks[self.active]
            if self.device.get_busy():
                bank.offset=self.time()
            else:
                bank.advance()
        if context in self.banks:
            bank=self.banks[context]
            if bank.track is None:
                bank.advance()
            if bank.offset>self.play_end(bank.track)-.48:
                bank.advance()
            track,offset,loops=bank.track,bank.offset,0
        else:
            track,offset,loops=context,0.,0 if context=="victory" else -1
        path=self.path(track)
        seek = offset>=.05 and path.suffix in (".opus", ".ogg")
        if offset>=.05 and not seek:
            self.buffer=tail_from(path,offset)
            self.device.load(self.buffer,"wav")
        else:
            self.buffer=None
            self.device.load(path)
        self.active,self.track,self.offset=context,track,offset
        self.end=self.play_end(track) if context in self.banks else 0.
        self.last_position=offset
        self.gain=0.
        self.reopen=False
        self.device.set_volume(0.)
        if seek:
            self.device.play(loops,start=offset)
        else:
            self.device.play(loops)

    def update(self,dt):
        if not self.enabled or self.paused:
            return
        bank=self.banks.get(self.active)
        remaining = self.end-self.time() if bank else 0.
        switching=self.active!=self.requested or self.reopen
        if switching:
            self.gain=max(0.,self.gain-dt/FADE)
            if self.gain==0. or not self.device.get_busy():
                self.start(self.requested,store=not self.reopen)
        elif bank and (remaining<=0. or not self.device.get_busy()):
            bank.advance()
            self.start(self.active,store=False)
        else:
            cap=1. if not bank else max(0.,min(1.,remaining/CODA_FADE))
            self.gain=min(cap,self.gain+dt/FADE)
        self.device.set_volume(self.master*self.gain)

    def bookmark(self,context):
        bank=self.banks.get(context)
        if bank is None or bank.track is None:
            return None
        offset=self.time() if self.active==context and not self.reopen else bank.offset
        return {"track":bank.track,"remaining":bank.bag.copy(),"offset":offset}

    def restore(self,context,value):
        if value is None or context not in self.banks:
            return
        bank=self.banks[context]
        bank.track,bank.offset=value["track"],value["offset"]
        bank.bag=value["remaining"].copy()
        self.reopen=self.reopen or self.active==context
