#!/bin/sh
# Put a built Meshy actor into the game (scratch profile; the main session
# only merges this branch after pass 15 ships).
#   meshy/tools/install.sh <raw dir> <kind,kind...>
set -e
RAW=$(cd "$1" && pwd -W)
KINDS=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
GD="$SP/meshy-work/gd.sh"
cd "$SP/p16-meshy"
for k in $(echo "$KINDS" | tr ',' ' '); do
  "$GD" --headless --path godot --script res://tools/art/build_actor_meshes.gd -- no-render raw="$RAW/$k" kinds=$k 2>&1 | grep -E "actor meshes|ERROR|run --import" || true
  .venv/Scripts/python.exe meshy/tools/gear_paste.py "$RAW/$k" $k
done
"$GD" --headless --path godot --script res://tools/pack_assets.gd > "$SP/meshy-work/pack_last.log" 2>&1
"$GD" --headless --path godot --import > "$SP/meshy-work/import_last.log" 2>&1 || true
for k in $(echo "$KINDS" | tr ',' ' '); do
  "$GD" --headless --path godot --script res://tools/art/build_actor_meshes.gd -- no-render raw="$RAW/$k" kinds=$k rig-only 2>&1 | grep -E "actor meshes|ERROR|run --import" || true
done
"$GD" --headless --path godot --import > "$SP/meshy-work/import_last2.log" 2>&1 || true
"$GD" --headless --path godot --script res://tools/art/bake_rigs.gd 2>&1 | grep -E "RIGS|ERROR" || true
echo installed $KINDS
