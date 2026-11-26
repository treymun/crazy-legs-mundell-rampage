"""A view tour (main.gd --view-tour) showing one kind close up by day and by
night, standing and mid-stride, and a few cells off.

    python meshy/tools/tour_for.py <kind> <out.json> [ahead]
"""
import json
import sys

kind, out = sys.argv[1], sys.argv[2]
near = float(sys.argv[3]) if len(sys.argv) > 3 else 2.4
DAY = {"level": "grainyard", "x": 44.4, "y": 6.6, "angle": -1.5708, "pitch": 0.0, "weapon": False}
# A long street view by day (Hickston) for the shot a few cells off.
DAY_FAR = {"level": "hickston", "x": 60.5, "y": 44.5, "angle": 1.5708, "pitch": 0.0, "weapon": False}
NIGHT = {"level": "moonshine", "x": 86.5, "y": 91.7, "angle": -0.02, "pitch": 0.0, "weapon": False, "contrast": 6.5}
shots = []
for tod, base in (("day", DAY), ("night", NIGHT)):
    for tag, spec in (("idle", {"state": "idle", "turn": 0.35}),
                      ("walk", {"state": "walk", "gait": 0.3, "turn": 0.9}),
                      ("far", {"state": "idle", "turn": 0.2, "ahead": near * 2.6}),
                      ("aim", {"state": "aim", "turn": 0.5}),
                      ("wind", {"state": "windup", "left": 0.15, "turn": 0.0})):
        a = {"kind": kind, "ahead": near, "side": 0.0}
        a.update(spec)
        s = dict(DAY_FAR if (tod == "day" and tag == "far") else base)
        s["tag"] = "%s_%s_%s" % (kind, tod, tag)
        s["actors"] = [a]
        shots.append(s)
json.dump(shots, open(out, "w"), indent=1)
