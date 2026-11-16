## A player-made map (docs/dev/levels.md "Player maps"): the file the MAP SHED
## writes to user://maps, what a lobby sends its joiners, and what a map save
## is tied to. It is small on purpose: a grid of letters (each a cell from
## data/tuning/user_maps.json's palette) and a list of things on cells. The
## game never loads one as it is: UserMapBuild compiles it into a level that
## is put in LevelData.preview, so a file can only say what the palette lets
## it say.
##
##   {"schema": "clmr-usermap", "version": 1, "name": "BUBBA'S BACK FORTY",
##    "author": "BUBBA", "note": "...", "mood": "dusk", "size": [w, h],
##    "rows": ["##D##", "#,,,#", ...], "things": [[kind, name, x, y, facing], ...]}
##
## check() holds a file to the limits (bytes, size, counts, lengths, letters,
## names), refusing anything else with one plain line, never an error: a
## map from a stranger in a lobby goes through it the same as one from disk.
## to_text() writes the one canonical form; hash_of() is its SHA-256, so two
## machines holding the same text play the same map.
class_name UserMap
extends RefCounted

const PALETTE := "res://data/tuning/user_maps.json"
const SCHEMA := "clmr-usermap"
const VERSION := 1
const ID_PREFIX := "custom_"
## The level id of a map's versus copy (no hands, lever or truck) ends so.
const VERSUS_TAIL := "v"
const KINDS := ["mark", "hand", "loot", "prop"]
## Letters a map's name, author and note may use (the pixel font's).
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,'!?-:/()"
## The deepest a file's brackets may nest before it is not even parsed (a
## map file nests three deep).
const DEPTH := 6
## What each mode is called on screen, in the order the lists show them.
const MODE_NAMES := {
	"solo": "PLAY ALONE",
	"deathmatch": "DEATHMATCH",
	"bomb": "5V5 SEARCH AND DESTROY",
	"hostage": "5V5 HOSTAGE RESCUE",
	"county": "COUNTY RUN",
}
const MODE_ORDER := ["solo", "deathmatch", "bomb", "hostage", "county"]

static var _palette := {}
static var _cells := {}
static var _things := {}
static var _tiles := {}

# ------------------------------------------------------------------ palette


static func palette() -> Dictionary:
	if _palette.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE))
		_palette = parsed if parsed is Dictionary else {}
		for v: Variant in _palette.get("cells", []):
			var entry: Dictionary = v
			_cells[str(entry["key"])] = entry
		for v: Variant in _palette.get("things", []):
			var entry: Dictionary = v
			_things["%s/%s" % [entry["kind"], entry["name"]]] = entry
	return _palette


static func limit(key: String) -> int:
	var limits: Dictionary = palette().get("limits", {})
	var value: int = limits.get(key, 0)
	return value


static func rule(key: String) -> float:
	var modes: Dictionary = palette().get("modes", {})
	var value: float = modes.get(key, 0.0)
	return value


## The palette's cells in order (each {key, group, label, tile, help, ...}).
static func cells() -> Array:
	return palette().get("cells", [])


## The cell a letter stands for ({} for none).
static func cell(key: String) -> Dictionary:
	palette()
	var out: Dictionary = _cells.get(key, {})
	return out


static func things() -> Array:
	return palette().get("things", [])


static func thing(kind: String, name: String) -> Dictionary:
	palette()
	var out: Dictionary = _things.get("%s/%s" % [kind, name], {})
	return out


static func moods() -> Array:
	return palette().get("moods", [])


static func mood(id: String) -> Dictionary:
	for v: Variant in moods():
		var m: Dictionary = v
		if str(m["id"]) == id:
			return m
	var first: Dictionary = moods()[0]
	return first


## Tile name -> index as the levels number them (data/index.json "tiles"),
## without loading the tile pictures.
static func tile_index() -> Dictionary:
	if _tiles.is_empty():
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/index.json")
		)
		var index: Dictionary = parsed if parsed is Dictionary else {}
		var names: Array = index.get("tiles", [])
		for i in names.size():
			_tiles[str(names[i])] = i
	return _tiles


static func is_wall(key: String) -> bool:
	return str(cell(key).get("group", "")) == "wall"


static func is_open(key: String) -> bool:
	var group := str(cell(key).get("group", ""))
	return group != "wall" and group != "door" and group != ""


# ------------------------------------------------------------------ making


## A new map w x h: pasture inside a hedgerow.
static func blank(w: int, h: int, name := "NEW MAP") -> Dictionary:
	var rows: Array = []
	for y in h:
		var row := ""
		for x in w:
			row += "H" if x == 0 or y == 0 or x == w - 1 or y == h - 1 else ","
		rows.append(row)
	return {
		"name": name,
		"author": "",
		"note": "",
		"mood": "dusk",
		"size": [w, h],
		"rows": rows,
		"things": [],
	}


static func width(map: Dictionary) -> int:
	var w: int = map["size"][0]
	return w


static func height(map: Dictionary) -> int:
	var h: int = map["size"][1]
	return h


## The letter at (x, y) ("" off the map).
static func at(map: Dictionary, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width(map) or y >= height(map):
		return ""
	var row: String = map["rows"][y]
	return row[x]


## The one canonical text of a map (what is written, sent and hashed).
static func to_text(map: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append('{"schema": "%s", "version": %d,' % [SCHEMA, VERSION])
	lines.append(' "name": %s,' % JSON.stringify(str(map["name"])))
	lines.append(' "author": %s,' % JSON.stringify(str(map.get("author", ""))))
	lines.append(' "note": %s,' % JSON.stringify(str(map.get("note", ""))))
	lines.append(' "mood": %s,' % JSON.stringify(str(map.get("mood", "dusk"))))
	lines.append(' "size": [%d, %d],' % [width(map), height(map)])
	lines.append(' "rows": [')
	var rows: Array = map["rows"]
	for i in rows.size():
		lines.append("  %s%s" % [JSON.stringify(str(rows[i])), "," if i < rows.size() - 1 else ""])
	lines.append(" ],")
	lines.append(' "things": [')
	var list: Array = map["things"]
	for i in list.size():
		var t: Array = list[i]
		var tx: int = t[2]
		var ty: int = t[3]
		var facing: int = t[4]
		lines.append(
			(
				'  ["%s", "%s", %d, %d, %d]%s'
				% [t[0], t[1], tx, ty, facing, "," if i < list.size() - 1 else ""]
			)
		)
	lines.append(" ]}")
	return "\n".join(lines) + "\n"


static func hash_text(text: String) -> String:
	return text.sha256_text()


static func hash_of(map: Dictionary) -> String:
	return hash_text(to_text(map))


## The level id the game knows a map by (versus: its copy for the versus
## modes and COUNTY RUN, with no hands, lever or truck).
static func level_id(map: Dictionary, versus := false) -> String:
	return ID_PREFIX + hash_of(map).substr(0, 12) + (VERSUS_TAIL if versus else "")


static func is_custom(level_id: String) -> bool:
	return level_id.begins_with(ID_PREFIX)


# ------------------------------------------------------------------ checking


## A file's bytes as a map: {"map": {...}} or {"error": "<one plain line>"}.
static func parse_bytes(raw: PackedByteArray) -> Dictionary:
	var most := limit("bytes")
	if raw.is_empty():
		return {"error": "THE FILE IS EMPTY."}
	if raw.size() > most:
		return {
			"error": "TOO BIG: %d KB. A MAP TOPS OUT AT %d KB." % [raw.size() / 1024, most / 1024]
		}
	var text := raw.get_string_from_utf8()
	if text.is_empty():
		return {"error": "THAT AIN'T TEXT."}
	return parse_text(text)


static func parse_text(text: String) -> Dictionary:
	if text.length() > limit("bytes"):
		return {"error": "TOO BIG FOR A MAP."}
	if _too_deep(text):
		return {"error": "THAT AIN'T A MAP FILE (TOO TANGLED)."}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"error": "THAT AIN'T A MAP FILE (BROKEN AT LINE %d)." % json.get_error_line()}
	return check(json.data)


## Brackets nested past DEPTH, strings skipped (so a hostile file never
## reaches the parser's own recursion).
static func _too_deep(text: String) -> bool:
	var depth := 0
	var quoted := false
	var escaped := false
	for i in text.length():
		var ch := text.unicode_at(i)
		if quoted:
			if escaped:
				escaped = false
			elif ch == 92:
				escaped = true
			elif ch == 34:
				quoted = false
			continue
		if ch == 34:
			quoted = true
		elif ch == 91 or ch == 123:
			depth += 1
			if depth > DEPTH:
				return true
		elif ch == 93 or ch == 125:
			depth -= 1
	return false


static func _whole(v: Variant, low: int, high: int) -> bool:
	if not (v is int or v is float):
		return false
	var f: float = v
	return is_finite(f) and f == floorf(f) and f >= low and f <= high


## Text that only uses LETTERS, upper-cased; null when it uses others.
static func _clean(v: Variant, most: int) -> Variant:
	if not v is String:
		return null
	var text := str(v).to_upper()
	if text.length() > most:
		return null
	for i in text.length():
		if not LETTERS.contains(text[i]):
			return null
	return text.strip_edges()


## A parsed file held to the format and its limits: {"map": the map, in the
## canonical form} or {"error": why}.
static func check(doc: Variant) -> Dictionary:
	if not doc is Dictionary:
		return {"error": "THAT AIN'T A MAP FILE."}
	var d: Dictionary = doc
	if str(d.get("schema", "")) != SCHEMA:
		return {"error": "THAT AIN'T A MAP FILE (NO MAP SHED MARK)."}
	if not _whole(d.get("version"), 1, 1000000):
		return {"error": "THE MAP'S VERSION MAKES NO SENSE."}
	var version: int = d["version"]
	if version > VERSION:
		return {"error": "MADE BY A NEWER GAME (MAP VERSION %d). UPDATE TO PLAY IT." % version}
	var name: Variant = _clean(d.get("name"), limit("name"))
	if name == null or str(name) == "":
		return {"error": "THE MAP'S NAME IS MISSING OR HAS ODD LETTERS."}
	var author: Variant = _clean(d.get("author", ""), limit("author"))
	if author == null:
		return {"error": "THE AUTHOR'S NAME HAS ODD LETTERS OR RUNS LONG."}
	var note: Variant = _clean(d.get("note", ""), limit("note"))
	if note == null:
		return {"error": "THE MAP'S NOTE HAS ODD LETTERS OR RUNS LONG."}
	var mood_id := str(d.get("mood", "dusk"))
	if not d.get("mood", "dusk") is String or str(mood(mood_id)["id"]) != mood_id:
		return {"error": "THE MAP ASKS FOR A SKY NOBODY'S HEARD OF."}
	var size: Variant = d.get("size")
	if not size is Array:
		return {"error": "THE MAP HAS NO SIZE."}
	var size_list: Array = size
	if size_list.size() != 2:
		return {"error": "THE MAP HAS NO SIZE."}
	var least := limit("least")
	var most := limit("most")
	if not _whole(size_list[0], least, most) or not _whole(size_list[1], least, most):
		return {"error": "A MAP RUNS %d TO %d CELLS A SIDE." % [least, most]}
	var w: int = size_list[0]
	var h: int = size_list[1]
	var rows_given: Variant = d.get("rows")
	if not rows_given is Array:
		return {"error": "THE MAP'S ROWS DON'T MATCH ITS SIZE."}
	var rows: Array = rows_given
	if rows.size() != h:
		return {"error": "THE MAP'S ROWS DON'T MATCH ITS SIZE."}
	var clean_rows: Array = []
	for y in h:
		var row: Variant = rows[y]
		if not row is String or str(row).length() != w:
			return {"error": "ROW %d IS THE WRONG LENGTH." % (y + 1)}
		var text := str(row)
		for x in w:
			if cell(text[x]).is_empty():
				return {"error": "A CELL AT %d,%d IS NOTHING THE SHED KNOWS." % [x, y]}
		clean_rows.append(text)
	var map := {
		"name": name,
		"author": author,
		"note": note,
		"mood": mood_id,
		"size": [w, h],
		"rows": clean_rows,
		"things": [],
	}
	var list_given: Variant = d.get("things", [])
	if not list_given is Array:
		return {"error": "THE MAP'S THINGS AREN'T A LIST."}
	var list: Array = list_given
	var placed: Array = map["things"]
	if list.size() > limit("things"):
		return {"error": "TOO MANY THINGS: %d IS THE MOST." % limit("things")}
	var counts := {}
	var taken := {}
	var hands := 0
	for v: Variant in list:
		if not v is Array:
			return {"error": "A THING ON THE MAP IS MANGLED."}
		var t: Array = v
		if t.size() != 5:
			return {"error": "A THING ON THE MAP IS MANGLED."}
		if not t[0] is String or not t[1] is String:
			return {"error": "A THING ON THE MAP IS MANGLED."}
		var kind := str(t[0])
		var thing_name := str(t[1])
		var spec := thing(kind, thing_name)
		if spec.is_empty():
			return {"error": "THE SHED DON'T KNOW ANY %s." % thing_name.to_upper().left(20)}
		if not _whole(t[2], 0, w - 1) or not _whole(t[3], 0, h - 1) or not _whole(t[4], 0, 7):
			return {"error": "A %s SITS OFF THE MAP." % str(spec["label"])}
		var x: int = t[2]
		var y: int = t[3]
		var facing: int = t[4]
		if not is_open(at(map, x, y)):
			return {"error": "A %s IS STUCK IN A WALL AT %d,%d." % [spec["label"], x, y]}
		if taken.has(Vector2i(x, y)):
			return {"error": "TWO THINGS SHARE THE CELL AT %d,%d." % [x, y]}
		taken[Vector2i(x, y)] = true
		var key := "%s/%s" % [kind, thing_name]
		var seen: int = counts.get(key, 0)
		counts[key] = seen + 1
		var only_one: bool = spec.get("one", false)
		var most_of: int = spec.get("most", 9999)
		var cap: int = 1 if only_one else most_of
		if seen + 1 > cap:
			return {"error": "ONLY %d %s ON A MAP." % [cap, spec["label"]]}
		if kind == "hand":
			hands += 1
			if hands > limit("hands"):
				return {"error": "TOO MANY HANDS: %d IS THE MOST." % limit("hands")}
		var inside_only: bool = spec.get("inside", false)
		if inside_only and str(cell(at(map, x, y)).get("group", "")) != "inside":
			return {"error": "A %s HANGS INSIDE ONLY (%d,%d)." % [spec["label"], x, y]}
		placed.append([kind, thing_name, x, y, facing])
	return {"map": map}


## Problems the shed shows that do not stop a map loading: doors that are not
## in a wall line. [[x, y, text], ...]
static func warnings(map: Dictionary) -> Array:
	var out: Array = []
	for y in height(map):
		for x in width(map):
			if at(map, x, y) == "D" and door_way(map, x, y) < 0:
				out.append(
					[x, y, "A DOOR NEEDS WALL ON TWO OPPOSITE SIDES AND OPEN ON THE OTHER TWO."]
				)
	return out


## Which way a door at (x, y) is hung: 1 walls north and south (walked
## through east-west), 0 walls east and west, -1 not in a wall line (built
## as wall).
static func door_way(map: Dictionary, x: int, y: int) -> int:
	var n := is_wall(at(map, x, y - 1))
	var s := is_wall(at(map, x, y + 1))
	var e := is_wall(at(map, x + 1, y))
	var w := is_wall(at(map, x - 1, y))
	if n and s and is_open(at(map, x + 1, y)) and is_open(at(map, x - 1, y)):
		return 1
	if e and w and is_open(at(map, x, y - 1)) and is_open(at(map, x, y + 1)):
		return 0
	return -1


# ------------------------------------------------------------------ modes


## The things of a kind and name: [[x, y, facing], ...].
static func marks(map: Dictionary, kind: String, name: String) -> Array:
	var out: Array = []
	for v: Variant in map["things"]:
		var t: Array = v
		if str(t[0]) == kind and str(t[1]) == name:
			out.append([t[2], t[3], t[4]])
	return out


static func mark(map: Dictionary, name: String) -> Variant:
	var found := marks(map, "mark", name)
	if found.is_empty():
		return null
	var first: Array = found[0]
	var fx: int = first[0]
	var fy: int = first[1]
	return Vector2i(fx, fy)


## The ground height of a cell (NAN for a wall; a door is ground level).
static func ground_of(map: Dictionary, x: int, y: int) -> float:
	var key := at(map, x, y)
	if key == "D":
		return 0.0 if door_way(map, x, y) >= 0 else NAN
	if not is_open(key):
		return NAN
	var g: float = cell(key).get("ground", 0.0)
	return g


## The cells reached on foot from `from` (doors open, a step up of at most
## a porch step, down any), not through a prop that blocks its cell.
static func reach(map: Dictionary, from: Vector2i) -> Dictionary:
	var blocked := {}
	for v: Variant in map["things"]:
		var t: Array = v
		var spec := thing(str(t[0]), str(t[1]))
		var solid: float = spec.get("solid", 0.0)
		if solid >= .4:
			var bx: int = t[2]
			var by: int = t[3]
			blocked[Vector2i(bx, by)] = true
	var out := {}
	if is_nan(ground_of(map, from.x, from.y)):
		return out
	out[from] = true
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var here := queue[head]
		head += 1
		var g := ground_of(map, here.x, here.y)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := here + step
			if out.has(next) or blocked.has(next):
				continue
			var ng := ground_of(map, next.x, next.y)
			if is_nan(ng) or ng - g > .245:
				continue
			out[next] = true
			queue.append(next)
	return out


static func _reach_of(map: Dictionary, from: Variant) -> Dictionary:
	if from == null:
		return {}
	var cell_at: Vector2i = from
	return reach(map, cell_at)


## Whether the map can host each mode: mode -> "" (it can) or why not, in
## the shed's words.
static func modes(map: Dictionary) -> Dictionary:
	var out := {}
	var start: Variant = mark(map, "start")
	var lever: Variant = mark(map, "lever")
	var goal: Variant = mark(map, "goal")
	var attack: Variant = mark(map, "attack")
	var defend: Variant = mark(map, "defend")
	var site_a: Variant = mark(map, "site_a")
	var site_b: Variant = mark(map, "site_b")
	var from_start := _reach_of(map, start)
	# PLAY ALONE (and co-op): the start, the lever and the truck, all walked to.
	if start == null:
		out["solo"] = "NEEDS YOUR START."
	elif lever == null:
		out["solo"] = "NEEDS THE BIG LEVER."
	elif goal == null:
		out["solo"] = "NEEDS THE GETAWAY TRUCK."
	elif not from_start.has(lever):
		out["solo"] = "THE LEVER CAN'T BE WALKED TO FROM YOUR START."
	elif not from_start.has(goal):
		out["solo"] = "THE TRUCK CAN'T BE WALKED TO FROM YOUR START."
	else:
		out["solo"] = ""
	# DEATHMATCH: room to spread out from wherever the game starts players.
	var middle: Variant = start if start != null else attack
	var room := _reach_of(map, middle).size()
	var want := int(rule("deathmatch_cells"))
	if middle == null:
		out["deathmatch"] = "NEEDS YOUR START."
	elif room < want:
		out["deathmatch"] = "TOO TIGHT: %d OPEN CELLS, NEEDS %d." % [room, want]
	else:
		out["deathmatch"] = ""
	# The 5v5 rounds: both starts, walked between, and a site or a hostage.
	var from_attack := _reach_of(map, attack)
	var versus := ""
	if attack == null:
		versus = "NEEDS AN ATTACK START."
	elif defend == null:
		versus = "NEEDS A DEFEND START."
	elif not from_attack.has(defend):
		versus = "THE DEFEND START CAN'T BE WALKED TO FROM THE ATTACK START."
	elif from_attack.size() < int(rule("versus_cells")):
		versus = (
			"TOO TIGHT: %d OPEN CELLS, NEEDS %d." % [from_attack.size(), int(rule("versus_cells"))]
		)
	var bomb := versus
	if bomb == "" and site_a == null:
		bomb = "NEEDS BOMB SITE A."
	elif bomb == "" and not from_attack.has(site_a):
		bomb = "SITE A CAN'T BE WALKED TO."
	elif bomb == "" and site_b != null and not from_attack.has(site_b):
		bomb = "SITE B CAN'T BE WALKED TO."
	out["bomb"] = bomb
	var hostage := versus
	var held := marks(map, "mark", "hostage")
	if hostage == "" and held.is_empty():
		hostage = "NEEDS A HOSTAGE."
	elif hostage == "":
		for h: Array in held:
			var hx: int = h[0]
			var hy: int = h[1]
			if not from_attack.has(Vector2i(hx, hy)):
				hostage = "A HOSTAGE CAN'T BE WALKED TO."
	out["hostage"] = hostage
	# COUNTY RUN: a start and a lot of ground for the horde to come over.
	var county_want := int(rule("county_cells"))
	if start == null:
		out["county"] = "NEEDS YOUR START."
	elif from_start.size() < county_want:
		out["county"] = "TOO SMALL: %d OPEN CELLS, NEEDS %d." % [from_start.size(), county_want]
	else:
		out["county"] = ""
	return out


## The modes a map can host, in MODE_ORDER.
static func hosts(map: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var all := modes(map)
	for mode: String in MODE_ORDER:
		if str(all[mode]) == "":
			out.append(mode)
	return out
