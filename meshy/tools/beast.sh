#!/bin/sh
# Build, install and make-sheet one animal or boss on its old armature.
#   meshy/tools/beast.sh <kind> <NN>     (SKIP_BUILD=1: sheet only)
K=$1; NN=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
B="/c/Users/treym/AppData/Local/Programs/Blender/blender.exe"
cd "$SP/p16-meshy"
if [ -z "$SKIP_BUILD" ]; then
  "$B" -b --python-exit-code 1 -P meshy/tools/build_beast.py -- meshy/kinds/$K.json > "$SP/meshy-work/${K}_build.log" 2>&1 || { echo BUILD FAILED; grep -E "Error|Traceback|line [0-9]" "$SP/meshy-work/${K}_build.log" | tail -5; exit 1; }
  grep -E "BEAST" "$SP/meshy-work/${K}_build.log" | grep -v "fit turn"
  sh meshy/tools/install.sh ../meshy-work/raw $K | tail -2
fi
O=$SP/meshy-work/old
rm -rf "$SP/meshy-work/make/$K"
"$B" -b -P meshy/tools/beast_sheet.py -- $K $O/$K.glb $O/actor3d_$K.png godot/assets3d/actors/$K.glb assets/art/actor3d_$K.png "$SP/meshy-work/make/$K" > "$SP/meshy-work/make_$K.log" 2>&1
grep -E "Traceback|Error" "$SP/meshy-work/make_$K.log"
.venv/Scripts/python.exe meshy/tools/beast_sheet.py sheet "$SP/meshy-work/make/$K" $K "$SP/meshy-previews/${NN}_${K}_make.png" "$NN $K: old vs new on the old armature, every key"
sh "$SP/meshy-work/unchurn.sh" > /dev/null
