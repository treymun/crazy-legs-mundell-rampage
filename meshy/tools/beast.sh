#!/bin/sh
# Build, install and make-sheet one animal or boss on its old armature.
#   meshy/tools/beast.sh <kind> <NN>     (SKIP_BUILD=1: sheet only)
K=$1; NN=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
# (MESHY_WT / MESHY_WORK: a second agent's own worktree and work folder)
WT=${MESHY_WT:-$SP/p16-meshy}; MW=${MESHY_WORK:-$SP/meshy-work}
B="/c/Users/treym/AppData/Local/Programs/Blender/blender.exe"
cd "$WT"
if [ -z "$SKIP_BUILD" ]; then
  "$B" -b --python-exit-code 1 -P meshy/tools/build_beast.py -- meshy/kinds/$K.json > "$MW/${K}_build.log" 2>&1 || { echo BUILD FAILED; grep -E "Error|Traceback|line [0-9]" "$MW/${K}_build.log" | tail -5; exit 1; }
  grep -E "BEAST" "$MW/${K}_build.log" | grep -v "fit turn"
  sh meshy/tools/install.sh $MW/raw $K | tail -2
fi
O=$MW/old
rm -rf "$MW/make/$K"
"$B" -b -P meshy/tools/beast_sheet.py -- $K $O/$K.glb $O/actor3d_$K.png godot/assets3d/actors/$K.glb assets/art/actor3d_$K.png "$MW/make/$K" > "$MW/make_$K.log" 2>&1
grep -E "Traceback|Error" "$MW/make_$K.log"
.venv/Scripts/python.exe meshy/tools/beast_sheet.py sheet "$MW/make/$K" $K "$SP/meshy-previews/${NN}_${K}_make.png" "$NN $K: old vs new on the old armature, every key"
sh "$MW/unchurn.sh" > /dev/null
