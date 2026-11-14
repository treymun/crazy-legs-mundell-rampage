## A map's authoritative source: godot/maps/<id>.map.json ("clmr-map" version
## 1). Either a whole map (size, districts, objects) or objects laid over a
## level's plan (base: {"plan": "<id>"}: tools/levels/<id>_plan.gd runs first,
## then these). Every object has a stable id and a type from TYPES; the
## compiler (map_compile.gd) turns them into builder and geometry calls.
##
## Units: a cell is 1 map unit; x runs east, y south, z up from the ground; the
## eye is .95 over a floor, a door 1.85 high, a step at most .245, a body .2
## round and 1.12 tall. Every rect is [x0, y0, x1, y1] in map units, x1 and y1
## exclusive; a grid type (it changes cells) wants whole numbers and covers
## cells x0..x1-1, y0..y1-1. Angles in degrees, 0 east, 90 south.
##
## Keys an object has that its type does not know are kept as they are on
## load and save (and reported by validate as warnings), never dropped.
extends RefCounted

const SCHEMA := "clmr-map"
const VERSION := 1
const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const MAPS_DIR := "res://maps"

## type -> {"grid": changes cells, "req": required keys, "opt": optional keys
## with their defaults, "doc": what it is}. The JSON Schema
## (docs/map_schema.json) and the catalog are made from this table.
const TYPES := {
	"yard":
	{
		"grid": true,
		"req": ["rect", "floor"],
		"opt": {"district": "", "ground": 0.0, "light": .97},
		"doc": "Open ground under the sky over whole cells.",
	},
	"room":
	{
		"grid": true,
		"req": ["rect", "floor"],
		"opt":
		{
			"district": "",
			"roof": 2.2,
			"ground": 0.0,
			"light": .78,
			"ceiling": "ceiling",
			"skin": ""
		},
		"doc": "Open floor under a roof `roof` high (cells); walls come from solid cells round it.",
	},
	"building":
	{
		"grid": true,
		"req": ["rect"],
		"opt":
		{
			"district": "",
			"wall": "brick",
			"roof": 2.2,
			"floor": "wood",
			"windows": 0,
			"ceiling": "ceiling",
			"light": .74,
			"parapet": .28
		},
		"doc": "A ring of wall cells round a room; cut doors with `door`.",
	},
	"solid":
	{
		"grid": true,
		"req": ["rect", "tile"],
		"opt": {"top": 2.0, "band": false},
		"doc": "Solid cells: a wall, hedge, rock or fence `top` high.",
	},
	"fence":
	{
		"grid": true,
		"req": ["rect"],
		"opt": {"tile": "stockyard", "top": 1.24},
		"doc": "A fence of solid cells (breakable where breakables.cfg says).",
	},
	"paint":
	{
		"grid": true,
		"req": ["rect", "floor"],
		"opt": {},
		"doc": "A floor tile over cells (a path, a rug, mud).",
	},
	"raise":
	{
		"grid": true,
		"req": ["rect", "ground"],
		"opt": {},
		"doc": "Cells' ground raised (or sunk) to `ground` (a step up needs <= .245).",
	},
	"light":
	{
		"grid": true,
		"req": ["at"],
		"opt": {"reach": 4.0, "amount": .25},
		"doc": "A pool of lamp light on the cells round `at`.",
	},
	"door":
	{
		"grid": true,
		"req": ["cell"],
		"opt":
		{
			"vertical": false,
			"from": "",
			"key": "",
			"style": "hinge",
			"secret": false,
			"tile": "door",
			"opened": false
		},
		"doc": "A door in a wall cell (a grid door: 1 cell wide, 1.85 high).",
	},
	"gap":
	{
		"grid": true,
		"req": ["cell", "from"],
		"opt": {},
		"doc": "An open doorway in a wall cell, no door.",
	},
	"pane":
	{
		"grid": true,
		"req": ["cell"],
		"opt": {},
		"doc": "A breakable glass pane across a cell.",
	},
	"deck":
	{
		"grid": false,
		"req": ["rect", "top"],
		"opt":
		{
			"thick": .15,
			"tile": "porch",
			"under": "ceiling",
			"edge": "",
			"cuts": [],
			"light": .85,
			"district": ""
		},
		"doc": "A floor walked on and under (a loft, a landing, a catwalk), `thick` thick.",
	},
	"block":
	{
		"grid": false,
		"req": ["rect", "top"],
		"opt":
		{"tile": "porch", "edge": "", "cuts": [], "light": .85, "district": "", "walk": true},
		"doc": "A solid block standing on the ground (a plinth, a dock, a stage), walked on.",
	},
	"ramp":
	{
		"grid": false,
		"req": ["rect", "from", "to", "toward"],
		"opt":
		{
			"tile": "porch",
			"edge": "",
			"thick": -1.0,
			"under": "ceiling",
			"light": .85,
			"district": ""
		},
		"doc":
		"A slope from z `from` up to `to` toward n/e/s/w (solid to the ground unless `thick`).",
	},
	"stairs":
	{
		"grid": false,
		"req": ["rect", "from", "to", "toward"],
		"opt":
		{"tile": "porch", "edge": "", "rise": .2, "thick": -1.0, "light": .85, "district": ""},
		"doc": "Stairs from `from` up to `to` toward n/e/s/w, treads `rise` high at most.",
	},
	"wall":
	{
		"grid": false,
		"req": ["a", "b"],
		"opt":
		{
			"z0": 0.0,
			"z1": 2.2,
			"thick": .12,
			"tile": "plaster",
			"openings": [],
			"light": .85,
			"district": ""
		},
		"doc":
		"A free wall a to b; `openings` [{id, at, width, sill, head}] cut doors and windows.",
	},
	"rail":
	{
		"grid": false,
		"req": ["a", "b"],
		"opt": {"z": 0.0, "height": .95, "tile": "stockyard", "district": ""},
		"doc": "A rail standing on z: stops bodies, not looks or shots.",
	},
	"cover":
	{
		"grid": false,
		"req": ["a", "b"],
		"opt": {"z": 0.0, "height": 1.0, "thick": .3, "tile": "crate_side", "district": ""},
		"doc": "Low solid cover a to b: stops bodies, looks and shots under its top.",
	},
	"balcony":
	{
		"grid": false,
		"req": ["rect", "top", "open"],
		"opt":
		{
			"thick": .15,
			"tile": "porch",
			"under": "ceiling",
			"edge": "",
			"gaps": [],
			"rail_tile": "stockyard",
			"district": ""
		},
		"doc": "A deck railed on the `open` sides (n, e, s, w); `gaps` [[side, from, to]].",
	},
	"bridge":
	{
		"grid": false,
		"req": ["rect", "top"],
		"opt":
		{
			"thick": .2,
			"tile": "bayou_planks",
			"under": "bayou_planks",
			"edge": "",
			"rail_tile": "stockyard",
			"district": ""
		},
		"doc": "A deck across a gap at `top`, railed along its long sides; walk under it.",
	},
	"ceiling":
	{
		"grid": false,
		"req": ["rect", "z"],
		"opt": {"tile": "ceiling", "cuts": [], "light": .8, "district": ""},
		"doc": "A flat surface overhead (an overhang, a porch roof, an upper room's ceiling).",
	},
	"room_poly":
	{
		"grid": true,
		"req": ["points", "floor"],
		"opt":
		{
			"district": "",
			"roof": 2.2,
			"wall": "plaster",
			"thick": .16,
			"openings": [],
			"light": .78
		},
		"doc": "A room of any outline, a wall on each edge; `openings` [[edge, {at, width}]].",
	},
	"corridor":
	{
		"grid": true,
		"req": ["points", "floor"],
		"opt": {"width": 2, "district": "", "roof": 2.2, "light": .78, "ceiling": "ceiling"},
		"doc":
		"A roofed passage `width` cells wide along a path of cell centres (straight legs, n/s/e/w).",
	},
	"fixture":
	{
		"grid": false,
		"req": ["rect", "top"],
		"opt": {"side": "counter", "cap": "counter_top", "bottom": 0.0},
		"doc": "A box of furniture (a counter, a crate stack): stops bodies; not walked on.",
	},
	"prop":
	{
		"grid": false,
		"req": ["name", "at"],
		"opt": {"z": 0.0, "angle": 0.0},
		"doc": "A modelled prop (town_props.json names) standing at `at`.",
	},
	"sign":
	{
		"grid": false,
		"req": ["image", "at", "height"],
		"opt": {"z": 0.0, "glow": false},
		"doc": "A flat picture standing at `at` (a sign, a board).",
	},
	"enemy":
	{
		"grid": false,
		"req": ["kind", "at"],
		"opt": {"z": 0.0, "route": []},
		"doc": "A hand of `kind` (enemies.cfg) standing at `at`, on the floor at or under z.",
	},
	"pickup":
	{
		"grid": false,
		"req": ["name", "at"],
		"opt": {"z": 0.0},
		"doc": "A pickup lying at `at`.",
	},
	"station":
	{
		"grid": false,
		"req": ["at", "label"],
		"opt": {"message": "", "requires": [], "opens": [], "prop": "", "z": 0.0},
		"doc":
		"An objective: a quest station used at `at`; `opens` door cells; `prop` a town_quest_<name>.",
	},
	"exit":
	{
		"grid": false,
		"req": ["at", "label"],
		"opt": {"shutdown": "", "z": 0.0},
		"doc": "The level's exit (extraction) at `at`, open once `shutdown` is done.",
	},
	"spawn_point":
	{
		"grid": false,
		"req": ["at"],
		"opt": {"z": 0.0, "angle": 0.0, "team": ""},
		"doc": "A named place a player or bot can start a playtest from (and a versus spawn).",
	},
	"label":
	{
		"grid": false,
		"req": ["text", "at"],
		"opt": {},
		"doc": "A name on the automap.",
	},
	"allow_overlap":
	{
		"grid": false,
		"req": ["objects", "reason"],
		"opt": {},
		"doc": "Says two or more objects overlap on purpose (validate stops calling it an error).",
	},
}

## Keys whose values are tile names (the material swap looks in these).
const TILE_KEYS := [
	"floor", "tile", "wall", "edge", "under", "side", "cap", "ceiling", "skin", "rail_tile"
]
## Keys whose values are positions (move shifts these).
const POINT_KEYS := ["at", "a", "b", "cell"]


static func path_of(map_id: String) -> String:
	return "%s/%s.map.json" % [MAPS_DIR, map_id]


static func exists(map_id: String) -> bool:
	return FileAccess.file_exists(path_of(map_id))


## A new, empty map source.
static func blank(map_id: String, w: int, h: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"id": map_id,
		"size": [w, h],
		"border": "hedgerow",
		"meta": {"title": map_id.to_upper(), "sky": "sky", "layout": 1},
		"districts": [{"id": "outside", "name": "OUTSIDE"}],
		"spawn": {"at": [1.5, 1.5], "angle": 0.0, "z": 0.0},
		"objects":
		[{"id": "ground", "type": "yard", "rect": [1, 1, w - 1, h - 1], "floor": "dirt"}],
	}


## The source as read (an empty dictionary with `errors` filled when it
## cannot be): JSON parsed, numbers that were whole kept as floats.
static func read(map_id: String, errors: Array = []) -> Dictionary:
	var path := path_of(map_id)
	if not FileAccess.file_exists(path):
		errors.append({"code": "no_source", "message": "no map source at " + path})
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append(
			{
				"code": "bad_json",
				"message":
				"%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
			}
		)
		return {}
	if not (json.data is Dictionary):
		errors.append({"code": "bad_json", "message": path + " is not a JSON object"})
		return {}
	return json.data


## Write a source back: two-space indent, keys in the order they were, one
## object a line where it fits (a diff then shows the object that changed).
static func write(map_id: String, doc: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAPS_DIR))
	var file := FileAccess.open(ProjectSettings.globalize_path(path_of(map_id)), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_text(doc))
	file.close()
	return true


static func to_text(doc: Dictionary) -> String:
	var lines := PackedStringArray(["{"])
	var keys := doc.keys()
	for k in keys.size():
		var key = keys[k]
		var comma := "," if k < keys.size() - 1 else ""
		var value = doc[key]
		if key == "objects" and value is Array:
			lines.append('  "objects": [')
			for i in (value as Array).size():
				var more := "," if i < (value as Array).size() - 1 else ""
				lines.append("    " + compact(value[i]) + more)
			lines.append("  ]" + comma)
		else:
			lines.append("  %s: %s%s" % [JSON.stringify(str(key)), compact(value), comma])
	lines.append("}")
	return "\n".join(lines) + "\n"


## JSON on one line, whole numbers without a decimal point.
static func compact(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for key in value:
				parts.append(JSON.stringify(str(key)) + ": " + compact(value[key]))
			return "{" + ", ".join(parts) + "}"
		TYPE_ARRAY:
			var items := PackedStringArray()
			for item in value:
				items.append(compact(item))
			return "[" + ", ".join(items) + "]"
		TYPE_FLOAT:
			if value == floorf(value) and absf(value) < 1e15:
				return str(int(value))
			return str(snappedf(value, .0001))
		TYPE_INT:
			return str(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
	return JSON.stringify(value)


## The object with this id (null when none) and its place in the list.
static func find(doc: Dictionary, object_id: String) -> int:
	var objects: Array = doc.get("objects", [])
	for i in objects.size():
		if objects[i] is Dictionary and String(objects[i].get("id", "")) == object_id:
			return i
	return -1


## Problems with the source's shape (not yet the geometry it makes): each
## {severity, code, object, message, hint}. tile_index and the name lists
## let it say a tile, prop, enemy or pickup does not exist.
static func check(doc: Dictionary, names: Dictionary) -> Array:
	var out: Array = []
	if String(doc.get("schema", "")) != SCHEMA:
		out.append(
			_issue(
				"error", "schema", "", 'schema must be "%s"' % SCHEMA, 'add "schema": "clmr-map"'
			)
		)
	var version := int(doc.get("version", 0))
	if version < 1 or version > VERSION:
		out.append(
			_issue(
				"error",
				"version",
				"",
				"version %d is not one this build reads (1..%d)" % [version, VERSION],
				""
			)
		)
	var id_re := RegEx.create_from_string(ID_PATTERN)
	if not id_re.search(String(doc.get("id", ""))):
		out.append(
			_issue(
				"error", "bad_id", "", "map id %s must match %s" % [doc.get("id"), ID_PATTERN], ""
			)
		)
	var base = doc.get("base")
	var size: Array = doc.get("size", [])
	if base == null:
		if (
			size.size() != 2
			or float(size[0]) < 4
			or float(size[1]) < 4
			or float(size[0]) > 256
			or float(size[1]) > 256
		):
			out.append(_issue("error", "size", "", "size must be [w, h], 4..256 each", ""))
	elif not (base is Dictionary) or not (base as Dictionary).has("plan"):
		out.append(_issue("error", "base", "", 'base must be {"plan": "<level id>"}', ""))
	var districts := {}
	for d in doc.get("districts", []):
		if d is Dictionary:
			districts[String(d.get("id", ""))] = true
	var seen := {}
	var objects = doc.get("objects", [])
	if not (objects is Array):
		out.append(_issue("error", "objects", "", "objects must be a list", ""))
		return out
	for i in (objects as Array).size():
		var o = objects[i]
		if not (o is Dictionary):
			out.append(
				_issue("error", "object", "#%d" % i, "object %d is not a JSON object" % i, "")
			)
			continue
		var oid := String(o.get("id", ""))
		var where := oid if oid != "" else "#%d" % i
		if not id_re.search(oid):
			out.append(
				_issue(
					"error",
					"bad_id",
					where,
					"object %d: id %s must match %s" % [i, oid, ID_PATTERN],
					""
				)
			)
		elif seen.has(oid):
			out.append(
				_issue(
					"error",
					"duplicate_id",
					oid,
					"id %s is used twice (objects %d and %d)" % [oid, seen[oid], i],
					"give each object its own id"
				)
			)
		seen[oid] = i
		var type := String(o.get("type", ""))
		if not TYPES.has(type):
			out.append(
				_issue(
					"error",
					"unknown_type",
					where,
					(
						"type %s is not one of: %s"
						% [type, ", ".join(PackedStringArray(TYPES.keys()))]
					),
					"see docs/map_schema.json"
				)
			)
			continue
		var spec: Dictionary = TYPES[type]
		for key: String in spec["req"]:
			if not o.has(key):
				out.append(
					_issue(
						"error",
						"missing",
						where,
						"%s %s has no %s" % [type, oid, key],
						"required: " + ", ".join(PackedStringArray(spec["req"]))
					)
				)
		for key in o:
			if (
				key != "id"
				and key != "type"
				and not (key in spec["req"])
				and not (spec["opt"] as Dictionary).has(key)
				and not String(key).begins_with("_")
			):
				out.append(
					_issue(
						"warning",
						"unknown_key",
						where,
						"%s %s: key %s is not one %s knows (kept, unused)" % [type, oid, key, type],
						"prefix a note key with _ to keep it quietly"
					)
				)
		_check_values(out, o, type, where, base == null, size, names, districts)
	if not (doc.get("spawn") is Dictionary) and base == null:
		out.append(_issue("error", "spawn", "", "no spawn {at, angle, z}", ""))
	return out


static func _check_values(
	out: Array,
	o: Dictionary,
	type: String,
	where: String,
	whole: bool,
	size: Array,
	names: Dictionary,
	districts: Dictionary
) -> void:
	var spec: Dictionary = TYPES[type]
	if o.has("rect"):
		var r = o["rect"]
		if not (r is Array) or (r as Array).size() != 4:
			out.append(_issue("error", "rect", where, "rect must be [x0, y0, x1, y1]", ""))
		else:
			if float(r[2]) <= float(r[0]) or float(r[3]) <= float(r[1]):
				out.append(
					_issue(
						"error",
						"rect",
						where,
						"rect %s is empty (x1 > x0 and y1 > y0)" % [r],
						"",
						_mid(r)
					)
				)
			if bool(spec["grid"]):
				for v in r:
					if float(v) != floorf(float(v)):
						out.append(
							_issue(
								"error",
								"grid_rect",
								where,
								(
									"a %s covers whole cells: rect %s must be whole numbers"
									% [type, r]
								),
								"round it",
								_mid(r)
							)
						)
						break
			if whole and size.size() == 2:
				if (
					float(r[0]) < 0
					or float(r[1]) < 0
					or float(r[2]) > float(size[0])
					or float(r[3]) > float(size[1])
				):
					out.append(
						_issue(
							"error",
							"outside",
							where,
							"rect %s leaves the map (0..%s, 0..%s)" % [r, size[0], size[1]],
							"",
							_mid(r)
						)
					)
	for key: String in POINT_KEYS:
		if o.has(key):
			var p = o[key]
			if not (p is Array) or (p as Array).size() < 2:
				out.append(_issue("error", "point", where, "%s must be [x, y]" % key, ""))
	if o.has("toward") and not (String(o["toward"]) in ["n", "e", "s", "w"]):
		out.append(_issue("error", "toward", where, "toward must be n, e, s or w", ""))
	if (type == "ramp" or type == "stairs") and o.has("from") and o.has("to"):
		if float(o["to"]) <= float(o["from"]):
			out.append(
				_issue(
					"error",
					"rise",
					where,
					"%s rises from %s to %s: `to` must be higher" % [type, o["from"], o["to"]],
					"swap them and turn `toward` round"
				)
			)
	var tiles: Dictionary = names.get("tiles", {})
	for key: String in TILE_KEYS:
		if (
			o.has(key)
			and String(o[key]) != ""
			and not tiles.is_empty()
			and not tiles.has(String(o[key]))
		):
			out.append(
				_issue(
					"error",
					"no_tile",
					where,
					"%s: no tile named %s" % [key, o[key]],
					"map.gd -- catalog lists the tiles"
				)
			)
	if (
		type == "prop"
		and names.has("props")
		and not (names["props"] as Dictionary).has(String(o.get("name", "")))
	):
		out.append(
			_issue(
				"error",
				"no_prop",
				where,
				"no prop named %s" % o.get("name"),
				"map.gd -- catalog lists the props"
			)
		)
	if (
		type == "enemy"
		and names.has("enemies")
		and not (names["enemies"] as Dictionary).has(String(o.get("kind", "")))
	):
		out.append(
			_issue(
				"error",
				"no_enemy",
				where,
				"no enemy kind %s" % o.get("kind"),
				"see data/tuning/enemies.cfg"
			)
		)
	if (
		type == "pickup"
		and names.has("pickups")
		and not (names["pickups"] as Dictionary).has(String(o.get("name", "")))
	):
		out.append(
			_issue(
				"error",
				"no_pickup",
				where,
				"no pickup named %s" % o.get("name"),
				"map.gd -- catalog lists the pickups"
			)
		)
	if (
		o.has("district")
		and String(o["district"]) != ""
		and not districts.has(String(o["district"]))
	):
		out.append(
			_issue(
				"error",
				"no_district",
				where,
				(
					"no district %s (districts: %s)"
					% [o["district"], ", ".join(PackedStringArray(districts.keys()))]
				),
				""
			)
		)
	if o.has("cuts") and (o["cuts"] as Array).size() > 2:
		out.append(
			_issue(
				"error",
				"cuts",
				where,
				"at most two cut lines (the shader view draws two)",
				"split it into two objects"
			)
		)


static func _mid(r: Array) -> Array:
	return [(float(r[0]) + float(r[2])) * .5, (float(r[1]) + float(r[3])) * .5]


static func _issue(
	severity: String, code: String, object_id: String, message: String, hint: String, at = null
) -> Dictionary:
	var d := {"severity": severity, "code": code, "object": object_id, "message": message}
	if hint != "":
		d["hint"] = hint
	if at != null:
		d["at"] = at
	return d
