"""Headless station, radio and soundtrack wiring check.
Run:  python radio_check.py
"""
import os
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"

from pathlib import Path

from campaign import BY_ID
from main import Desktop

ROOT = Path(__file__).resolve().parent
WAV = ROOT / "assets" / "wav"
MUSIC = ROOT / "assets" / "music"


def main():
    d = Desktop(smoke=True)
    problems = []
    for lid, level in BY_ID.items():
        d.start(lid)
        g = d.game
        h, w = g.world.solid.shape
        stations = list(g.world.stations)
        if not stations:
            problems.append(f"{lid}: no stations")
        for station in stations:
            if not (0 <= station.x < w and 0 <= station.y < h):
                problems.append(f"{lid}: station {station.id} off map")
            if not (WAV / f"{station.cue}.wav").exists():
                problems.append(f"{lid}: missing cue {station.cue}.wav")
        track = MUSIC / f"{level.score}.opus"
        if not track.exists():
            problems.append(f"{lid}: missing score {track.name}")
        try:
            g.jukebox_on = False
            g.jukebox_on = True
            g.sound.set_radio(True, .35, 0.)
            g.sound.set_radio(False)
            if stations:
                g.activate_station(stations[0])
        except Exception as exc:
            problems.append(f"{lid}: radio/station raised {exc!r}")
        print(f"{lid}: {len(stations)} stations, score {track.name}")
    if not (WAV / "jukebox.wav").exists():
        problems.append("missing jukebox.wav")
    for line in problems:
        print("  PROBLEM", line)
    print(f"{len(problems)} problem(s)")
    print("RADIO CHECK PASSED" if not problems else "RADIO CHECK FAILED")
    return 0 if not problems else 1


if __name__ == "__main__":
    raise SystemExit(main())
