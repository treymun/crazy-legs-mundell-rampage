## The looks layer in one call (pass 16, LOOKS): moods by area, water, set
## pieces, vignettes and foliage laid over a built level dictionary, in that
## order (water first so the plants and dressing see it; foliage last so it
## keeps clear of everything else). For the map compilers (a source's,
## a player map's): build the level, then
##
##   var report := MapLooks.apply(level, {
##       "mood": "farm_dusk",
##       "areas": [{"name": "THE BARN", "rect": [30, 6, 41, 15], "mood": "barn_dark"}],
##       "water": [{"type": "pond", "at": [12, 30], "radius": 3.5}],
##       "set_pieces": [{"kind": "tower", "id": "tank", "at": [44.5, 20.5], "falls": [0]}],
##       "vignettes": [{"id": "porch_sittin", "at": [12, 7], "wall": "n"}],
##       "dress": [{"theme": "farm", "area": [2, 2, 40, 30], "count": 3, "seed": 1}],
##       "foliage": [{"kind": "grass", "area": [4, 30, 60, 46], "density": .6, "seed": 3}],
##   })
##
## Everything is opt-in: an empty `looks` changes nothing. The report:
## {"problems": [[code, line]...], "vignettes": [the vignette objects the
## dress objects chose, to write back into a source], "plants": count,
## "water_cells": count}. Each problem is a short plain line; the codes are
## in docs/map_notes/t6.md.
class_name MapLooks
extends RefCounted


static func apply(level: Dictionary, looks: Dictionary) -> Dictionary:
	var problems: Array = []
	var ms := {}
	var report := {"problems": problems, "vignettes": [], "plants": 0, "water_cells": 0, "ms": ms}
	if looks.is_empty():
		return report
	var t0 := Time.get_ticks_usec()
	var reach_before := _reach(MapLooksGrid.of(level))
	ms["reach"] = (Time.get_ticks_usec() - t0) / 1000.0
	var water_cells := 0
	var plants := 0
	for a: Variant in _list(looks, "areas"):
		var area: Dictionary = a
		var rect: Array = area.get("rect", []) if area.get("rect") is Array else []
		if rect.size() != 4:
			problems.append(["area_rect", "an area wants rect [x0, y0, x1, y1]"])
			continue
		add_area(
			level,
			str(area.get("name", "")),
			rect,
			str(area.get("mood", "")),
			area.get("tint", [1.0, 1.0, 1.0])
		)
	problems.append_array(moods(level, str(looks.get("mood", "")), looks.get("area_moods", {})))
	t0 = Time.get_ticks_usec()
	var grid := MapLooksGrid.of(level)
	for w: Variant in _list(looks, "water"):
		var spec: Dictionary = w
		var kind := str(spec.get("type", "pond"))
		var done := {}
		match kind:
			"pond":
				done = MapWater.pond(grid, spec)
			"creek":
				done = MapWater.creek(grid, spec)
			"trough":
				done = MapWater.trough(grid, spec)
			_:
				done = {
					"cells": 0,
					"problems": [["water_type", "water is pond, creek or trough, not %s" % kind]]
				}
		var cells: int = done.get("cells", 0)
		water_cells += cells
		report["water_cells"] = water_cells
		problems.append_array(_got(done, "problems"))
		grid = MapLooksGrid.of(level)
	ms["water"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for s: Variant in _list(looks, "set_pieces"):
		var spec: Dictionary = s
		var done := MapSetPieces.add(grid, spec)
		problems.append_array(_got(done, "problems"))
	for v: Variant in _list(looks, "vignettes"):
		var choice: Dictionary = v
		var why := MapDressing.stand(grid, choice)
		if why != "":
			problems.append(["vignette", why])
	var chosen: Array = report["vignettes"]
	for d: Variant in _list(looks, "dress"):
		var spec: Dictionary = d
		var done := MapDressing.place(grid, spec)
		chosen.append_array(_got(done, "placed"))
		problems.append_array(_got(done, "problems"))
	ms["dress"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	# The way again, now to the set pieces too and round the vignettes.
	grid = MapLooksGrid.of(level)
	for f: Variant in _list(looks, "foliage"):
		var spec: Dictionary = f
		var done := MapFoliage.scatter(grid, spec)
		var placed: int = done.get("placed", 0)
		plants += placed
		report["plants"] = plants
		problems.append_array(_got(done, "problems"))
	ms["foliage"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var reach_after := _reach(MapLooksGrid.of(level))
	var first: float = ms["reach"]
	ms["reach"] = first + (Time.get_ticks_usec() - t0) / 1000.0
	for goal: Vector2 in reach_before:
		if not reach_after.has(goal):
			problems.append(
				["looks_blocked", "the looks shut the way to %s: move what stands in it" % goal]
			)
	return report


## A district over `rect` (cells, both corners in): its name on the HUD, its
## tint and its mood. Returns its index.
static func add_area(
	level: Dictionary, name: String, rect: Array, mood: String, tint: Variant = [1.0, 1.0, 1.0]
) -> int:
	var names: Array = level.get("districts", [])
	names.append(name)
	level["districts"] = names
	var tints: Array = level.get("tints", [])
	var t: Array = tint if tint is Array else []
	if t.size() != 3:
		t = [1.0, 1.0, 1.0]
	tints.append([MapLooksGrid.f(t[0]), MapLooksGrid.f(t[1]), MapLooksGrid.f(t[2])])
	level["tints"] = tints
	var index := names.size() - 1
	var w: int = level["width"]
	var h: int = level["height"]
	var area: Array = level["area"]
	var x0 := clampi(int(MapLooksGrid.f(rect[0])), 0, w - 1)
	var y0 := clampi(int(MapLooksGrid.f(rect[1])), 0, h - 1)
	var x1 := clampi(int(MapLooksGrid.f(rect[2])), 0, w - 1)
	var y1 := clampi(int(MapLooksGrid.f(rect[3])), 0, h - 1)
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			area[y * w + x] = index
	if mood != "":
		var listed: Dictionary = level.get("area_moods", {})
		listed[str(index)] = mood
		level["area_moods"] = listed
	return index


## The level's mood and its districts' (by index or by name), checked against
## effects.cfg; each district's room sound and far-off cue come from its mood
## where the level names none. Returns problems.
static func moods(level: Dictionary, mood: String, by_area: Variant) -> Array:
	var problems: Array = []
	if mood != "":
		if Effects.MOODS.has(mood):
			level["mood"] = mood
		else:
			problems.append(
				["mood_unknown", "no mood %s (%s)" % [mood, ", ".join(Effects.MOODS.keys())]]
			)
	var listed: Dictionary = level.get("area_moods", {})
	var names: Array = level.get("districts", [])
	var asked: Dictionary = by_area if by_area is Dictionary else {}
	var keys: Array = asked.keys()
	keys.sort()
	for k: Variant in keys:
		var key := str(k)
		var index := names.find(key)
		if index < 0 and key.is_valid_int():
			index = key.to_int()
		if index < 0 or index >= maxi(names.size(), 1):
			problems.append(["mood_area", "no district %s" % key])
			continue
		listed[str(index)] = str(asked[k])
	for key: Variant in listed.keys():
		var named := str(listed[key])
		if not Effects.MOODS.has(named):
			problems.append(
				["mood_unknown", "no mood %s (%s)" % [named, ", ".join(Effects.MOODS.keys())]]
			)
			listed.erase(key)
	if listed.is_empty():
		return problems
	level["area_moods"] = listed
	var sounds: Dictionary = level.get("area_sounds", {})
	var cues: Dictionary = level.get("area_cues", {})
	var sorted: Array = listed.keys()
	sorted.sort()
	for key: Variant in sorted:
		var named := str(listed[key])
		var sound := str(Effects.preset(named, "sound", ""))
		var cue := str(Effects.preset(named, "cue", ""))
		if sound != "" and not sounds.has(key):
			sounds[key] = sound
		if cue != "" and not cues.has(key):
			cues[key] = cue
	if not sounds.is_empty():
		level["area_sounds"] = sounds
	if not cues.is_empty():
		level["area_cues"] = cues
	return problems


## The objectives the start walks to (MapLooksGrid's way).
static func _reach(grid: MapLooksGrid) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var starts := grid.spawns()
	if starts.is_empty():
		return out
	var from := grid.cell(starts[0].x, starts[0].y)
	for goal in grid.objectives():
		if not grid.way(from, grid.cell(goal.x, goal.y)).is_empty():
			out.append(goal)
	return out


static func _list(looks: Dictionary, key: String) -> Array:
	var found: Variant = looks.get(key, [])
	var out: Array = []
	if found is Array:
		for item: Variant in found:
			if item is Dictionary:
				out.append(item)
	return out


static func _got(done: Dictionary, key: String) -> Array:
	var found: Variant = done.get(key, [])
	var out: Array = found if found is Array else []
	return out
