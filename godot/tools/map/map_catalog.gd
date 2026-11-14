## The searchable catalog of what a map can use, made from the game's own
## files: docs/map_catalog/catalog.json (everything, for an agent to search),
## catalog.md (the same as tables for a person) and thumbs/ (a picture of each
## tile, prop, enemy and pickup). And the JSON Schema of a map source
## (docs/map_schema.json), made from map_source.gd's TYPES.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")
const THUMB := 48


static func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()


static func _town_sizes() -> Dictionary:
	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(_repo("assets/art/town_props.json"))
	)
	return parsed if parsed is Dictionary else {}


static func prop_names() -> Dictionary:
	var out := {}
	for name in _town_sizes():
		out[String(name)] = true
	for name in GameState.PROP_HEIGHTS:
		out[String(name)] = true
	return out


static func enemy_names() -> Dictionary:
	var out := {}
	for name in Enemy.DEFS:
		out[String(name)] = true
	return out


static func pickup_names(assets: Assets) -> Dictionary:
	var out := {}
	for name: String in assets.art_index:
		if name.begins_with("item_"):
			out[name.substr(5)] = true
	return out


static func _thumb(img: Image, size := THUMB) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var k := float(size) / maxf(w, h)
	var t := img.duplicate() as Image
	t.convert(Image.FORMAT_RGBA8)
	t.resize(maxi(1, int(w * k)), maxi(1, int(h * k)), Image.INTERPOLATE_NEAREST)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(
		t,
		Rect2i(0, 0, t.get_width(), t.get_height()),
		Vector2i((size - t.get_width()) / 2, size - t.get_height())
	)
	return out


static func _art_image(assets: Assets, name: String) -> Image:
	if not assets.has_art(name):
		return null
	var a := assets.art(name)
	return Image.create_from_data(int(a["w"]), int(a["h"]), false, Image.FORMAT_RGBA8, a["data"])


## Writes the catalog under `dir`; fills `result` with counts and paths.
static func write(dir: String, assets: Assets, result: Dictionary) -> int:
	var root := (
		ProjectSettings.globalize_path(dir)
		if dir.begins_with("res://") or dir.begins_with("user://")
		else dir
	)
	root = root.simplify_path()
	DirAccess.make_dir_recursive_absolute(root.path_join("thumbs"))
	var lv := LevelData.new()
	lv.tile_names = assets.tile_names
	lv.tile_index = assets.tile_index
	var tiles: Array = []
	for name: String in assets.tile_names:
		var path := _repo("assets/tiles/%s.png" % name)
		var thumb := ""
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				thumb = "thumbs/tile_%s.png" % name
				_thumb(img, 32).save_png(root.path_join(thumb))
		var id := lv.tile_id(name)
		var base := name.trim_suffix("_win").trim_suffix("_lit").trim_suffix("_brk")
		(
			tiles
			. append(
				{
					"id": name,
					"kind": "tile",
					"strikes_as": Materials.of_name(name),
					"footstep": lv.surface_sound(id),
					"variants": _variants(assets, base),
					"use": "floor, wall, edge, under, ceiling: any tile",
					"thumb": thumb,
				}
			)
		)
	var props: Array = []
	var sizes := _town_sizes()
	for name: String in sizes:
		var size: Array = sizes[name]
		var thumb := ""
		var img := _art_image(assets, "town_" + name)
		if img != null:
			thumb = "thumbs/prop_%s.png" % name
			_thumb(img).save_png(root.path_join(thumb))
		(
			props
			. append(
				{
					"id": name,
					"kind": "prop",
					"width": size[0],
					"height": size[1],
					"collision":
					"none unless the plan gives it a base (prop objects stand free; add a fixture to block)",
					"example":
					{"id": "my_" + name, "type": "prop", "name": name, "at": [10.5, 8.5]},
					"thumb": thumb,
				}
			)
		)
	for name: String in GameState.PROP_HEIGHTS:
		var thumb := ""
		var img := _art_image(assets, "prop_" + name)
		if img == null:
			img = _art_image(assets, "prop_%s_0" % name)
		if img != null:
			thumb = "thumbs/flat_%s.png" % name
			_thumb(img).save_png(root.path_join(thumb))
		(
			props
			. append(
				{
					"id": name,
					"kind": "flat prop",
					"height": GameState.PROP_HEIGHTS[name],
					"collision": "none",
					"example":
					{"id": "my_" + name, "type": "prop", "name": name, "at": [10.5, 8.5]},
					"thumb": thumb,
				}
			)
		)
	var enemies: Array = []
	for name: String in Enemy.DEFS:
		var d: Dictionary = Enemy.DEFS[name]
		var spec: Array = Enemy.KINDS.get(name, [])
		var thumb := ""
		var img := _art_image(assets, "%s_0" % String(d.get("art", name)))
		if img != null:
			thumb = "thumbs/enemy_%s.png" % name
			_thumb(img).save_png(root.path_join(thumb))
		(
			enemies
			. append(
				{
					"id": name,
					"kind": "enemy",
					"brain": String(d.get("brain", name)),
					"health": spec[0] if spec.size() > 0 else null,
					"boss": d.has("title"),
					"swims": bool(d.get("swims", false)),
					"example":
					{"id": "a_" + name, "type": "enemy", "kind": name, "at": [12.5, 9.5]},
					"thumb": thumb,
				}
			)
		)
	var pickups: Array = []
	for name: String in pickup_names(assets):
		var thumb := ""
		var img := _art_image(assets, "item_" + name)
		if img != null:
			thumb = "thumbs/pickup_%s.png" % name
			_thumb(img, 32).save_png(root.path_join(thumb))
		(
			pickups
			. append(
				{
					"id": name,
					"kind": "pickup",
					"example":
					{"id": "some_" + name, "type": "pickup", "name": name, "at": [6.5, 4.5]},
					"thumb": thumb,
				}
			)
		)
	var components: Array = []
	for type: String in Source.TYPES:
		var spec: Dictionary = Source.TYPES[type]
		(
			components
			. append(
				{
					"id": type,
					"kind": "component",
					"changes_cells": spec["grid"],
					"required": spec["req"],
					"optional": spec["opt"],
					"doc": spec["doc"],
					"example": example(type),
				}
			)
		)
	var catalog := {
		"generated_by": "godot --headless --path godot --script res://tools/map.gd -- catalog",
		"units":
		"1 map unit = 1 cell; eye .95 over a floor; door 1.85; step .245; body radius .2, height 1.12",
		"components": components,
		"tiles": tiles,
		"props": props,
		"enemies": enemies,
		"pickups": pickups,
	}
	var f := FileAccess.open(root.path_join("catalog.json"), FileAccess.WRITE)
	if f == null:
		result["error"] = "could not write " + root
		return 3
	f.store_string(JSON.stringify(catalog, " ", false) + "\n")
	f.close()
	f = FileAccess.open(root.path_join("catalog.md"), FileAccess.WRITE)
	f.store_string(_markdown(catalog))
	f.close()
	result["path"] = root.path_join("catalog.json")
	result["counts"] = {
		"components": components.size(),
		"tiles": tiles.size(),
		"props": props.size(),
		"enemies": enemies.size(),
		"pickups": pickups.size()
	}
	print("wrote %s %s" % [result["path"], result["counts"]])
	return 0


static func _variants(assets: Assets, base: String) -> Array:
	var out: Array = []
	for suffix in ["", "_win", "_lit", "_brk"]:
		if assets.tile_index.has(base + suffix):
			out.append(base + suffix)
	return out


## A small valid object of each type, for the docs and the catalog.
static func example(type: String) -> Dictionary:
	var e := {"id": "example_" + type, "type": type}
	var spec: Dictionary = Source.TYPES[type]
	var fill := {
		"rect": [4, 4, 8, 7],
		"floor": "dirt",
		"top": 1.6,
		"from": 0.0,
		"to": 1.6,
		"toward": "e",
		"a": [4, 4],
		"b": [10, 4],
		"at": [6.5, 5.5],
		"cell": [6, 4],
		"tile": "plaster",
		"ground": .2,
		"z": 2.4,
		"open": "s",
		"points": [[4, 4], [10, 4], [12, 8], [4, 8]],
		"name": "outhouse",
		"image": "wanted",
		"height": 1.0,
		"kind": "billy",
		"label": "THROW THE RELAY",
		"text": "FEED STORE",
		"objects": ["a_deck", "a_wall"],
		"reason": "the wall stands on the deck's edge on purpose",
	}
	for key: String in spec["req"]:
		e[key] = fill.get(key, "")
	if type == "pickup":
		e["name"] = "shells"
	if type == "wall":
		e["openings"] = [
			{"id": "front_door", "at": 2.5, "width": 1.0},
			{"id": "front_window", "at": 4.5, "width": 1.0, "sill": .9, "head": 1.7}
		]
	if type == "corridor":
		e["points"] = [[4, 5], [12, 5]]
	if type == "gap":
		e["from"] = "s"
	return e


static func _markdown(c: Dictionary) -> String:
	var lines := PackedStringArray(
		[
			"# Map catalog",
			"",
			(
				"Made by `"
				+ String(c["generated_by"])
				+ "`; do not edit by hand. "
				+ String(c["units"])
				+ "."
			),
			""
		]
	)
	lines.append("## Components (object types)")
	lines.append("")
	lines.append("| type | cells | required | what it is |")
	lines.append("| --- | --- | --- | --- |")
	for comp: Dictionary in c["components"]:
		lines.append(
			(
				"| `%s` | %s | %s | %s |"
				% [
					comp["id"],
					"yes" if comp["changes_cells"] else "no",
					", ".join(PackedStringArray(comp["required"])),
					comp["doc"]
				]
			)
		)
	lines.append("")
	for section in [
		["tiles", "Tiles (materials)"],
		["props", "Props"],
		["enemies", "Enemies"],
		["pickups", "Pickups"]
	]:
		lines.append("## " + String(section[1]))
		lines.append("")
		lines.append("| | id | notes |")
		lines.append("| --- | --- | --- |")
		for item: Dictionary in c[section[0]]:
			var notes := ""
			match String(section[0]):
				"tiles":
					notes = (
						"strikes as %s, footstep %s, variants %s"
						% [
							item["strikes_as"],
							item["footstep"],
							", ".join(PackedStringArray(item["variants"]))
						]
					)
				"props":
					notes = "%s, %s high" % [item["kind"], item.get("height")]
					if item.has("width"):
						notes += ", %s wide" % item["width"]
				"enemies":
					notes = (
						"brain %s, health %s%s"
						% [item["brain"], item["health"], ", boss" if item["boss"] else ""]
					)
			var thumb := "" if String(item["thumb"]) == "" else "![](%s)" % item["thumb"]
			lines.append("| %s | `%s` | %s |" % [thumb, item["id"], notes])
		lines.append("")
	return "\n".join(lines) + "\n"


# ------------------------------------------------------------- schema


static func write_schema(path: String, result: Dictionary) -> int:
	var file := (
		ProjectSettings.globalize_path(path).simplify_path() if path.begins_with("res://") else path
	)
	var number := {"type": "number"}
	var point := {"type": "array", "items": number, "minItems": 2, "maxItems": 3}
	var rect := {
		"type": "array",
		"items": number,
		"minItems": 4,
		"maxItems": 4,
		"description": "[x0, y0, x1, y1] map units, x1 y1 exclusive"
	}
	var known := {
		"rect": rect,
		"at": point,
		"a": point,
		"b": point,
		"cell": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2},
		"points": {"type": "array", "items": point, "minItems": 2},
		"cuts":
		{
			"type": "array",
			"maxItems": 2,
			"items": {"type": "array", "items": number, "minItems": 3, "maxItems": 3},
			"description": "lines [nx, ny, c]: inside where nx*x + ny*y <= c"
		},
		"toward": {"enum": ["n", "e", "s", "w"]},
		"openings":
		{
			"type": "array",
			"items":
			{
				"type": "object",
				"required": ["at"],
				"properties":
				{
					"id": {"type": "string"},
					"at": number,
					"width": number,
					"sill": number,
					"head": number
				}
			}
		},
		"objects": {"type": "array", "items": {"type": "string"}},
		"route": {"type": "array"},
		"requires": {"type": "array", "items": {"type": "string"}},
		"opens": {"type": "array", "items": {"type": "array", "items": {"type": "integer"}}},
		"gaps": {"type": "array", "items": {"type": "array"}},
	}
	var variants: Array = []
	for type: String in Source.TYPES:
		var spec: Dictionary = Source.TYPES[type]
		var props := {
			"id": {"type": "string", "pattern": Source.ID_PATTERN}, "type": {"const": type}
		}
		for key: String in spec["req"]:
			props[key] = known.get(key, _type_of(_default_of(key, spec)))
		if type == "gap":
			props["from"] = {"enum": ["n", "e", "s", "w"]}
		for key in spec["opt"]:
			props[key] = known.get(key, _type_of(spec["opt"][key]))
		var req: Array = ["id", "type"]
		req.append_array(spec["req"])
		variants.append(
			{
				"title": type,
				"description": spec["doc"],
				"type": "object",
				"required": req,
				"properties": props,
				"patternProperties": {"^_": {}},
				"additionalProperties": false
			}
		)
	var schema := {
		"$schema": "https://json-schema.org/draft/2020-12/schema",
		"$id": "https://github.com/treymun/crazy-legs-mundell-rampage/docs/map_schema.json",
		"title": "Crazy Legs Mundell Rampage map source (clmr-map version %d)" % Source.VERSION,
		"description":
		(
			"godot/maps/<id>.map.json. 1 map unit = 1 cell; x east, y south, z up; "
			+ "eye .95, door 1.85, step .245, body .2 round, 1.12 tall. From tools/map.gd -- schema."
		),
		"type": "object",
		"required": ["schema", "version", "id", "objects"],
		"properties":
		{
			"schema": {"const": Source.SCHEMA},
			"version": {"type": "integer", "minimum": 1, "maximum": Source.VERSION},
			"id": {"type": "string", "pattern": Source.ID_PATTERN},
			"base":
			{
				"type": "object",
				"required": ["plan"],
				"properties": {"plan": {"type": "string"}},
				"description":
				"build on tools/levels/<plan>_plan.gd; then size/districts come from it"
			},
			"size":
			{
				"type": "array",
				"items": {"type": "integer", "minimum": 4, "maximum": 256},
				"minItems": 2,
				"maxItems": 2
			},
			"border":
			{"type": "string", "description": "the tile of the solid cells round everything"},
			"meta":
			{
				"type": "object",
				"description":
				(
					"title, sky, score, ambience, intro, heading, layout "
					+ "(bump layout when the map changes: old saves start the chapter over)"
				)
			},
			"districts":
			{
				"type": "array",
				"items":
				{
					"type": "object",
					"required": ["id"],
					"properties":
					{
						"id": {"type": "string"},
						"name": {"type": "string"},
						"tint": {"type": "array", "items": number}
					}
				}
			},
			"spawn":
			{
				"type": "object",
				"required": ["at"],
				"properties": {"at": point, "angle": number, "z": number}
			},
			"playtest":
			{
				"type": "object",
				"properties":
				{
					"routes":
					{
						"type": "array",
						"items":
						{
							"type": "object",
							"required": ["from", "to"],
							"properties":
							{"id": {"type": "string"}, "from": {}, "to": {}, "seconds": number}
						}
					},
					"enemies": {"type": "boolean"},
					"perf": {"type": "boolean"}
				}
			},
			"objects": {"type": "array", "items": {"oneOf": variants}},
		},
		"patternProperties": {"^_": {}},
		"additionalProperties": false,
	}
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		result["error"] = "could not write " + file
		return 3
	f.store_string(JSON.stringify(schema, "  ", false) + "\n")
	f.close()
	result["path"] = file
	print("wrote " + file)
	return 0


static func _default_of(key: String, _spec: Dictionary):
	match key:
		"floor", "tile", "name", "kind", "image", "label", "text", "open", "reason", "from":
			return "" if key != "from" else 0.0
		"top", "z", "to", "ground", "height":
			return 0.0
	return null


static func _type_of(value) -> Dictionary:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return {"type": "number"}
		TYPE_BOOL:
			return {"type": "boolean"}
		TYPE_STRING:
			return {"type": "string"}
		TYPE_ARRAY:
			return {"type": "array"}
	return {}
