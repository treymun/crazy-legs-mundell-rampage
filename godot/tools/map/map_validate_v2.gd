## Source v2's own validation (pass 16, T7), after the build: what the
## modes a source says it supports need, the versus places standing where a
## body can, buildings standing on raised ground. map_validate.gd calls
## check() for a version 2 source.
##
## Codes: mode_missing (a mode named in "modes" lacks what it needs),
## versus_inside (a versus start, site or hostage in something solid or in
## deep water), kit_on_terrain (a kit building's footprint on terrain that
## rises under it).
extends RefCounted

const Validate := preload("res://tools/map/map_validate.gd")


static func check(out: Array, doc: Dictionary, built: Dictionary, lv: LevelData) -> void:
	var level: Dictionary = built["level"]
	var tac: Dictionary = level.get("tactical", {}) if level.get("tactical") is Dictionary else {}
	_modes(out, doc, level, tac)
	_places(out, doc, lv)
	_on_terrain(out, doc, built, lv)


## What each named mode needs (docs/dev/modes.md).
static func _modes(out: Array, doc: Dictionary, level: Dictionary, tac: Dictionary) -> void:
	var modes: Array = doc.get("modes", []) if doc.get("modes") is Array else []
	var objective := (
		not (level.get("stations", []) as Array).is_empty() or level.get("extraction") is Dictionary
	)
	for m in modes:
		var mode := str(m)
		var lack := ""
		var hint := ""
		match mode:
			"solo", "coop":
				if not objective:
					lack = "an objective: a switch or station, and an exit"
					hint = 'add {"type": "switch", ...} and {"type": "exit", ...}'
			"bomb", "hostage":
				if (tac.get("attack_spawns", []) as Array).is_empty():
					lack = "the attackers' start"
					hint = '{"type": "team_spawn", "team": "attack", "at": [x, y]}'
				elif (tac.get("defend_spawns", []) as Array).is_empty():
					lack = "the defenders' start"
					hint = '{"type": "team_spawn", "team": "defend", "at": [x, y]}'
				elif mode == "bomb" and (tac.get("sites", {}) as Dictionary).is_empty():
					lack = "a bomb site"
					hint = '{"type": "bomb_site", "site": "A", "rect": [x0, y0, x1, y1]} (and B)'
				elif mode == "hostage" and (tac.get("hostages", []) as Array).is_empty():
					lack = "a hostage"
					hint = '{"type": "hostage", "at": [x, y]} near the defenders'
		if lack != "":
			out.append(
				Validate.issue(
					"error",
					"mode_missing",
					"",
					null,
					"the map says it plays %s but has no %s" % [mode, lack],
					hint
				)
			)


## Every versus start, site middle and hostage: on open, dry floor.
static func _places(out: Array, doc: Dictionary, lv: LevelData) -> void:
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var type := str(o.get("type", ""))
		var spots: Array = []
		if type in ["dm_spawn", "hostage"] and o.get("at") is Array:
			spots.append(Vector2(float(o["at"][0]), float(o["at"][1])))
		elif type == "bomb_site" and o.get("rect") is Array:
			var r: Array = o["rect"]
			spots.append(
				Vector2((float(r[0]) + float(r[2])) * .5, (float(r[1]) + float(r[3])) * .5)
			)
		if type == "team_spawn":
			var key := "attack_spawns" if str(o.get("team", "")) == "attack" else "defend_spawns"
			for s: Array in lv.tactical.get(key, []):
				spots.append(Vector2(float(s[0]), float(s[1])))
			if (lv.tactical.get(key, []) as Array).size() < int(o.get("count", 5)):
				out.append(
					Validate.issue(
						"error",
						"versus_inside",
						str(o.get("id", "")),
						o.get("at"),
						(
							"team_spawn %s found room for only %d of its %d places"
							% [
								o.get("id"),
								(lv.tactical.get(key, []) as Array).size(),
								int(o.get("count", 5))
							]
						),
						"move it onto open ground with room round it (4 cells)"
					)
				)
		for p: Vector2 in spots:
			if p.x < 0 or p.y < 0 or p.x >= lv.width or p.y >= lv.height:
				out.append(
					Validate.issue(
						"error",
						"outside",
						str(o.get("id", "")),
						[p.x, p.y, 0],
						"%s is off the map" % type
					)
				)
				continue
			var c := lv.cell(p.x, p.y)
			var wet := lv.surface_sound(int(lv.floor_tile[c])) == "water"
			if lv.blocked(p.x, p.y, .2) or wet:
				out.append(
					Validate.issue(
						"error",
						"versus_inside",
						str(o.get("id", "")),
						[p.x, p.y, 0.0],
						(
							"%s %s at (%.1f, %.1f) stands in %s"
							% [type, o.get("id"), p.x, p.y, "water" if wet else "something solid"]
						),
						"move it onto open, dry ground"
					)
				)


## A kit building whose footprint has terrain rising under it (the kit
## builds from the ground: its floor would be under the hill).
static func _on_terrain(out: Array, doc: Dictionary, built: Dictionary, lv: LevelData) -> void:
	if lv.geo == null or lv.geo.terrain == null:
		return
	var records: Dictionary = built.get("kit_pieces", {})
	for o in doc.get("objects", []):
		if not (o is Dictionary) or not records.has(str(o.get("id", ""))):
			continue
		var fp: Array = records[str(o["id"])]
		var rise := 0.0
		for y in range(int(fp[1]), int(ceilf(float(fp[3])))):
			for x in range(int(fp[0]), int(ceilf(float(fp[2])))):
				var z := lv.geo.terrain.height_at(x + .5, y + .5)
				if not is_nan(z):
					rise = maxf(rise, z)
		if rise > .15:
			(
				out
				. append(
					(
						Validate
						. issue(
							"warning",
							"kit_on_terrain",
							str(o["id"]),
							[
								(float(fp[0]) + float(fp[2])) * .5,
								(float(fp[1]) + float(fp[3])) * .5,
								rise
							],
							(
								"%s stands where the ground rises %.2f: its floor is on the flat, under the hill"
								% [o["id"], rise]
							),
							"keep terrain brushes off building footprints (or flatten there with brush flat, height 0)"
						)
					)
				)
			)
