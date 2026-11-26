"""Write meshy/kinds/<kind>.json for a kind whose Meshy model is in
meshy-work/meshy_out/<kind>_rig (extra keys as key=json-value).

    python meshy/tools/kind_config.py <kind> [key=value ...]
"""
import json
import sys

kind = sys.argv[1]
cfg = {
    "kind": kind,
    "rigged": "../meshy-work/meshy_out/%s_rig/rigged.glb" % kind,
    "poses": "../meshy-work/dump/%s_poses.json" % kind,
    "old_glb": "../meshy-work/old/%s.glb" % kind,
    "old_tex": "../meshy-work/old/actor3d_%s.png" % kind,
    "out": "../meshy-work/raw/%s" % kind,
    "tris": 10000,
    "texture": 512,
    "gear": "old",
}
for a in sys.argv[2:]:
    k, v = a.split("=", 1)
    cfg[k] = json.loads(v)
json.dump(cfg, open("meshy/kinds/%s.json" % kind, "w"), indent=1)
