#!/bin/sh
# Large hand crops (512 px) of a kind at the standing and aim keys, both hands,
# three sides: <out.png>
K=$1; OUTP=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
# (MESHY_WT / MESHY_WORK: a second agent's own worktree and work folder)
WT=${MESHY_WT:-$SP/p16-meshy}; MW=${MESHY_WORK:-$SP/meshy-work}
cd "$MW"
KEYS=$("$WT/.venv/Scripts/python.exe" -c "import json;f=json.load(open('$WT/godot/assets3d/actors/actors.json'))['$K']['frames'];print(','.join(str(int(f[k])) for k in ('0','aim') if k in f))")
# (the crop grows with a giant: Maw is 4.4 m)
OSC=$("$WT/.venv/Scripts/python.exe" -c "import json;h=json.load(open('$WT/godot/assets3d/actors/actors.json'))['$K'].get('height',1.8);print(round(.24*max(1.0,h/2.0),3))")
RES=400 OS_=$OSC "/c/Users/treym/AppData/Local/Programs/Blender/blender.exe" -b -P scripts/hands_render.py -- "$WT/godot/assets3d/actors/$K.glb" "$WT/assets/art/actor3d_$K.png" q/hb_$K $KEYS > /dev/null 2>&1
"$WT/.venv/Scripts/python.exe" - "$K" "$KEYS" "$OUTP" <<'PY'
import sys
from PIL import Image, ImageDraw
k, keys, out = sys.argv[1], sys.argv[2].split(","), sys.argv[3]
rows = [(f, sd) for f in keys for sd in ("hand_l", "hand_r")]
s = Image.new("RGB", (3 * 400, len(rows) * 400 + 30), (24, 24, 28))
d = ImageDraw.Draw(s)
d.text((8, 8), "%s - hands close up (key %s): left and right hand, three sides each" % (k, " / ".join(keys)), fill=(255, 240, 200))
for r, (f, sd) in enumerate(rows):
    for j, i in enumerate((0, 1, 5)):
        try:
            s.paste(Image.open("q/hb_%s_%s_%s_%d.png" % (k, f, sd, i)), (j * 400, 30 + r * 400))
        except Exception:
            pass
    d.text((6, 34 + r * 400), "frame %s %s" % (f, sd), fill=(255, 255, 255))
s.save(out, optimize=True)
PY
