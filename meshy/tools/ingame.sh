#!/bin/sh
# In-game pictures of one kind, old (the untouched worktree) and new.
#   meshy/tools/ingame.sh <kind> [ahead] [old]
K=$1; AHEAD=${2:-2.4}
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
# (MESHY_WT / MESHY_WORK: a second agent's own worktree and work folder)
WT=${MESHY_WT:-$SP/p16-meshy}; MW=${MESHY_WORK:-$SP/meshy-work}
cd "$MW"
"$WT/.venv/Scripts/python.exe" "$WT/meshy/tools/tour_for.py" $K tour_$K.json $AHEAD
T=$(pwd -W)/tour_$K.json
if [ "$3" = "old" ] || [ ! -d ingame/${K}_old ]; then
  rm -rf ingame/${K}_old; mkdir -p ingame/${K}_old
  ./gd_old.sh --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=$T --view-out=$(pwd -W)/ingame/${K}_old > tour_old_$K.log 2>&1
fi
rm -rf ingame/${K}_new; mkdir -p ingame/${K}_new
./gd.sh --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=$T --view-out=$(pwd -W)/ingame/${K}_new > tour_new_$K.log 2>&1
ls ingame/${K}_new | wc -l
