#!/bin/sh
# Blender turnaround tiles + the make sheet for one installed kind.
#   meshy/tools/make_sheet.sh <kind> <out.png> <title> [keys]
K=$1; OUTP=$2; TITLE=$3; KEYS=${4:-w1,w3,aim,fire,pain,die_2,down}
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
cd "$SP/p16-meshy"
O=$SP/meshy-work/old
rm -rf "$SP/meshy-work/make/$K"
"/c/Users/treym/AppData/Local/Programs/Blender/blender.exe" -b -P meshy/tools/render_make.py -- $K $O/$K.glb $O/actor3d_$K.png godot/assets3d/actors/$K.glb assets/art/actor3d_$K.png "$SP/meshy-work/make/$K" $KEYS > "$SP/meshy-work/make_$K.log" 2>&1
grep -E "DONE|Traceback|Error" "$SP/meshy-work/make_$K.log"
.venv/Scripts/python.exe meshy/tools/sheets.py make "$SP/meshy-work/make/$K" $K "$OUTP" "$TITLE" $KEYS
