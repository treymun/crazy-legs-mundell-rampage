extends SceneTree


func _init() -> void:
	var a := Assets.new()
	for id in ["hickston", "fair", "sawmill", "quarry"]:
		var d := LevelEdit.read(id)
		# 1. No change: the patch keeps the list exactly.
		var same := d.duplicate(true)
		LevelEdit.patch_walls(d, same, a.tile_index)
		var unchanged: bool = str(same["walls"]) == str(d["walls"])
		# 2. Write and read back: same values.
		var text := LevelEdit._json(d)
		var back = JSON.parse_string(text)
		var round_trip: bool = str(back) == str(d)
		# 3. Open a solid cell next to open ground and close it again: back to the start.
		var w := int(d["width"])
		var cell := -1
		for i in d["solid"].size():
			if (
				int(d["solid"][i]) >= 0
				and i % w > 1
				and int(d["solid"][i + 1]) < 0
				and int(d["solid"][i - 1]) < 0
			):
				cell = i
				break
		var opened := d.duplicate(true)
		opened["solid"][cell] = -1
		LevelEdit.patch_walls(d, opened, a.tile_index)
		var closed := opened.duplicate(true)
		closed["solid"][cell] = d["solid"][cell]
		LevelEdit.patch_walls(opened, closed, a.tile_index)
		print(
			(
				"%-9s unchanged %s  round trip %s  walls %d -> opened %d -> closed %d  (%d bytes vs %d)"
				% [
					id,
					unchanged,
					round_trip,
					d["walls"].size(),
					opened["walls"].size(),
					closed["walls"].size(),
					text.length(),
					FileAccess.get_file_as_string(LevelEdit.path_of(id)).length()
				]
			)
		)
	quit()
