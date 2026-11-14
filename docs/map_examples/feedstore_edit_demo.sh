#!/usr/bin/env bash
# A targeted-edit round on the demo map, with every step's output kept in
# docs/map_examples/edit_demo/: a dry run, moving a doorway along its wall,
# swapping a material in one object, the change summaries, validation, plans
# before and after, a playtest, then undo back to the source as committed.
# Run from the repo root: GODOT=/path/to/godot bash docs/map_examples/feedstore_edit_demo.sh
set -e
GODOT="${GODOT:-godot}"
OUT=docs/map_examples/edit_demo
mkdir -p "$OUT"
map() { "$GODOT" --headless --path godot --script res://tools/map.gd -- "$@" 2>/dev/null | grep -v "^Godot Engine" | grep -v "^$" || true; }

cp godot/maps/feedstore.map.json "$OUT/source_before.json"
map render feedstore out="$PWD/$OUT/before" overlay=nav,spawns,objects,unreachable > "$OUT/01_render_before.txt"
# 1. A dry run: what moving the partition a cell south would change. Nothing is written.
map move feedstore partition by=0,1 dry > "$OUT/02_move_dry.txt"
# 2. Move the stock-room doorway one unit along the partition (y 7.5 to 8.5).
map resize feedstore partition opening=stock_door at=3.1 > "$OUT/03_move_doorway.txt"
# 3. Plaster to brick on the partition only (the office keeps its plaster).
map material feedstore plaster brick in=partition > "$OUT/04_material.txt"
map validate feedstore > "$OUT/05_validate.txt"
map render feedstore out="$PWD/$OUT/after" overlay=nav,spawns,objects,unreachable > "$OUT/06_render_after.txt"
map playtest feedstore > "$OUT/07_playtest.txt"
map history feedstore > "$OUT/08_history.txt"
# 4. Undo both edits: the source is the committed one again, byte for byte.
map undo feedstore > "$OUT/09_undo_1.txt"
map undo feedstore > "$OUT/10_undo_2.txt"
if cmp -s godot/maps/feedstore.map.json "$OUT/source_before.json"; then
	echo "UNDONE: the source is byte for byte as it was" | tee "$OUT/11_result.txt"
else
	echo "NOT THE SAME after undo" | tee "$OUT/11_result.txt"
	exit 1
fi
