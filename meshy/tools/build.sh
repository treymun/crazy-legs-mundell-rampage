#!/bin/sh
# Build, install and preview one kind (Blender + the game, scratch profile).
#   meshy/tools/build.sh <kind> <NN>
K=$1; NN=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
cd "$SP/p16-meshy"
[ -f "$SP/meshy-work/dump/${K}_poses.json" ] || "$SP/meshy-work/gd_old.sh" --headless --path godot --script res://tools/meshy/dump_actor.gd -- kinds=$K out="$SP/meshy-work/dump" 2>&1 | grep dumped
"/c/Users/treym/AppData/Local/Programs/Blender/blender.exe" -b --python-exit-code 1 -P meshy/tools/build_actor.py -- meshy/kinds/$K.json > "$SP/meshy-work/${K}_build.log" 2>&1 || { echo BUILD FAILED; grep -E "Error|Traceback|line [0-9]" "$SP/meshy-work/${K}_build.log" | tail -5; exit 1; }
grep -E "MESHY (gear|hands|gain|skin fix|weights|ACTOR)" "$SP/meshy-work/${K}_build.log"
sh meshy/tools/install.sh ../meshy-work/raw $K | tail -1
