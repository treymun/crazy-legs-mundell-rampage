"""Write meshy/kinds/<kind>.json for a kind whose Meshy model is in
meshy-work/meshy_out/<kind>_rig (extra keys as key=json-value).

    python meshy/tools/kind_config.py <kind> [key=value ...]
"""
import json
import os
import sys

kind = sys.argv[1]
# (MESHY_WORK: a second agent's own work folder, written relative to the worktree)
MW = os.path.relpath(os.environ["MESHY_WORK"]).replace(os.sep, "/") if os.environ.get("MESHY_WORK") else "../meshy-work"
cfg = {
    "kind": kind,
    "rigged": MW + "/meshy_out/%s_rig/rigged.glb" % kind,
    "poses": MW + "/dump/%s_poses.json" % kind,
    "old_glb": MW + "/old/%s.glb" % kind,
    "old_tex": MW + "/old/actor3d_%s.png" % kind,
    "out": MW + "/raw/%s" % kind,
    "tris": 10000,
    "texture": 512,
    "gear": "old",
}
for a in sys.argv[2:]:
    k, v = a.split("=", 1)
    cfg[k] = json.loads(v)
json.dump(cfg, open("meshy/kinds/%s.json" % kind, "w"), indent=1)
