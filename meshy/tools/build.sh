#!/bin/sh
# Build, install and preview one kind (Blender + the game, scratch profile).
#   meshy/tools/build.sh <kind> <NN>
K=$1; NN=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
# (MESHY_WT / MESHY_WORK: a second agent's own worktree and work folder)
WT=${MESHY_WT:-$SP/p16-meshy}; MW=${MESHY_WORK:-$SP/meshy-work}
cd "$WT"
[ -f "$MW/dump/${K}_poses.json" ] || "$MW/gd_old.sh" --headless --path godot --script res://tools/meshy/dump_actor.gd -- kinds=$K out="$MW/dump" 2>&1 | grep dumped
"/c/Users/treym/AppData/Local/Programs/Blender/blender.exe" -b --python-exit-code 1 -P meshy/tools/build_actor.py -- meshy/kinds/$K.json > "$MW/${K}_build.log" 2>&1 || { echo BUILD FAILED; grep -E "Error|Traceback|line [0-9]" "$MW/${K}_build.log" | tail -5; exit 1; }
grep -E "MESHY (gear|hands|gain|skin fix|weights|ACTOR)" "$MW/${K}_build.log"
sh meshy/tools/install.sh $MW/raw $K | tail -1
