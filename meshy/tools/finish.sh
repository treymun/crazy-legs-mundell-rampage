#!/bin/sh
# Build one kind and make its previews and checks (scratch profile).
#   meshy/tools/finish.sh <kind> <NN> [ahead]
K=$1; NN=$2; AHEAD=${3:-2.4}
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
cd "$SP/p16-meshy"
[ -n "$SKIP_BUILD" ] || { sh meshy/tools/build.sh $K $NN | grep -v "gear part" || exit 1; }
grep -E "MESHY (item|.* hold:|.*short|held things|held thing)" "$SP/meshy-work/${K}_build.log" | sort -u
sh meshy/tools/make_sheet.sh $K "$SP/meshy-previews/${NN}_${K}_make.png" "$NN $K: Blender, old vs new Meshy model, rig, keys, hands" | tail -1
sh meshy/tools/ingame.sh $K $AHEAD > /dev/null
.venv/Scripts/python.exe meshy/tools/ingame_sheet.py $K "$SP/meshy-work/ingame/${K}_old" "$SP/meshy-work/ingame/${K}_new" "$SP/meshy-previews/${NN}_${K}_ingame.png" "$NN $K"
cd "$SP/meshy-work"
rm -rf live/${K}_probe; mkdir -p live/${K}_probe
./gd.sh --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/live_frames.gd -- out=$(pwd -W)/live/${K}_probe rows=chest,legs,arm,head,running,stacked,buckshot,knock kind=$K probe 2>&1 | grep -E "PROBE|ARMS|SCRIPT ERROR" > probe_$K.txt; cat probe_$K.txt
rm -rf death/${K}_new; mkdir -p death/${K}_new
./gd.sh --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/death_frames.gd -- out=$(pwd -W)/death/${K}_new audit rows=billy_shotgun_near,billy_head kind=$K 2>&1 | grep -E "SCRIPT ERROR"
"/c/Users/treym/AppData/Local/Programs/Blender/blender.exe" -b -P scripts/hands_render.py -- "$SP/p16-meshy/godot/assets3d/actors/$K.glb" "$SP/p16-meshy/assets/art/actor3d_$K.png" q/h_$K 0,2,6,8 > /dev/null 2>&1
"$SP/p16-meshy/.venv/Scripts/python.exe" -c "
from PIL import Image
s=Image.new('RGB',(6*170,8*170))
for r,(f,sd) in enumerate([(f,sd) for f in (0,2,6,8) for sd in ('hand_l','hand_r')]):
  for i in range(6):
    try: s.paste(Image.open(f'q/h_${K}_{f}_{sd}_{i}.png').resize((170,170)),(i*170,r*170))
    except Exception: pass
s.save('q/hands_$K.png')"
echo "finished $K"
