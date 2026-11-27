## Source v2 ("clmr-map" version 2, pass 16 T7): the high-level types an
## outside AI or a person writes. Every v1 type stays as it was
## (map_source.gd TYPES_V1); these come on top:
##
## - every piece of the map kit (src/map_kit/, data/tuning/map_kit.json) as a
##   type of its own: {"id": "home", "type": "farmhouse", "at": [20, 12]};
##   the five whose names are v1 types (stairs, ramp, fence, bridge, wall)
##   and any other piece also as {"type": "kit", "piece": "fence", ...};
## - land: terrain (brushes), road, creek, pond, trough;
## - looks: foliage, dress, vignette, set_piece (and a district's mood);
## - logic: switch, key, kill_gate, wake_zone, message, trigger;
## - versus: dm_spawn, team_spawn, bomb_site, hostage, rescue_zone,
##   bot_route, bot_hold (and the top-level "modes" list);
## - prefab (objects defined once, placed anywhere turned and mirrored) and
##   via (a nav point by hand).
##
## v2 keys on v1 types: a door's z, span and bar (style "barn" slides), a
## wall's curve, an opening's pane, a district's mood and rect. Top-level:
## mood, modes, prefabs, seed.
##
## A source is version 2 as soon as it uses any of these (needed()); an
## untouched v1 source reads, builds and saves exactly as before.
extends RefCounted

## Kit pieces whose names are already v1 types: only {"type": "kit", "piece": ...}.
const KIT_ONLY := ["stairs", "ramp", "fence", "bridge", "wall"]
## The keys every kit object takes besides the piece's own options.
const KIT_COMMON := ["at", "w", "d", "face", "turn", "mirror", "style", "variant", "district"]
## Top-level keys that make a source version 2.
const TOP_V2 := ["mood", "modes", "prefabs", "seed"]
## The modes a source may say it supports (docs/dev/modes.md).
const MODES := ["solo", "coop", "deathmatch", "team_deathmatch", "bomb", "hostage", "county"]
## A road's surface -> its floor tile.
const SURFACES := {
	"blacktop": "asphalt",
	"gravel": "gravel",
	"dirt": "track_dirt",
	"concrete": "concrete",
	"oil": "oil_asphalt",
}
const BRUSHES := ["hill", "ditch", "plateau", "ramp", "flat", "smooth", "noise", "heights"]
const KEYS := ["brass", "steel"]
const TEAMS := ["attack", "defend"]

## One line on each kit piece (the catalog and schema say it).
const KIT_DOCS := {
	"house": "A plain house: storeys of walls with windows, inside stairs, any roof.",
	"farmhouse":
	"A two-storey clapboard farmhouse: porch, gable roof, chimney, balcony, ladder to the roof.",
	"shack": "One room of planks under a lean-to roof, a door front and back.",
	"trailer": "A single-wide trailer on cinder blocks, steps up to its doors, an awning.",
	"outhouse": "A plank outhouse with a narrow door.",
	"barn":
	"A tall red barn: big sliding doors front and back, a hayloft up a ladder, bales, gambrel roof.",
	"pole_barn": "A tin roof on posts, open on three sides, bales inside.",
	"silo": "A round stave silo, a cone roof, a cage ladder up to a railed platform.",
	"grain_bin": "A round corrugated bin whose cone roof you can climb onto.",
	"water_tower": "Four legs, a railed balcony round a tank, a ladder (a set piece: it can fall).",
	"store": "A general store: boardwalk, awning, false front, counter and shelves, roof ladder.",
	"gas_station": "A cinder box and a canopy over pump islands, a flat roof to walk on.",
	"church": "A whitewashed church: pews, coloured glass, a bell tower with a belfry.",
	"porch": "A deck with posts, rails and a shed roof; put its north side against a wall.",
	"stairs": "Stairs rising toward the local north (straight, l, switchback).",
	"ramp": "A slope rising toward the local north.",
	"ladder": "A ladder leaning on the face along its cell's local north edge.",
	"fence": "A fence along the local x axis (rail, wire, picket, stock), a gate gap.",
	"bridge": "A plank or covered bridge across the local y axis, ramps at both ends.",
	"wall": "A free wall along the local x axis with doorways and windows on each storey.",
	"arch": "A thick wall with a way through its middle under a stepped arch.",
	"curved_wall": "A wall round the footprint's middle (an arc), a doorway in its middle.",
	"chimney": "A brick stack.",
	"dock": "A loading dock (waist-high cover), steps up its west end.",
	"catwalk": "A mesh deck on legs along the local x axis, rails, a ladder.",
	"tower": "A hunting stand: four legs, a deck behind knee walls, a tin roof.",
	"roof": "A roof alone over the footprint: gable, hip, shed, gambrel, quonset, cone, flat.",
}

## The non-kit v2 types, as map_source.gd's TYPES rows (grid, req, opt, doc)
## plus "ex": the catalog's example (what an AI should copy).
const TYPES := {
	"kit":
	{
		"grid": true,
		"req": ["piece", "at"],
		"opt": {"district": ""},
		"doc":
		(
			"Any kit piece by name (piece): needed for stairs, ramp, fence, bridge and wall,"
			+ " whose names are v1 types. Takes the piece's own keys."
		),
		"ex": {"piece": "fence", "at": [4, 20], "w": 12, "kind": "picket", "gate": 6},
	},
	"terrain":
	{
		"grid": true,
		"req": ["rect"],
		"opt":
		{
			"brush": "hill",
			"height": 2.0,
			"falloff": 3,
			"toward": "n",
			"seed": 1,
			"scale": 4.0,
			"passes": 2,
			"heights": [],
			"floor": "",
			"cliff": "",
			"light": -1.0
		},
		"doc":
		(
			"Ground shaped over rect: brush hill (a round rise `height` high), ditch (a trench"
			+ " along the long side), plateau (flat top, `falloff` cells of slope), ramp (up toward"
			+ " n/e/s/w), flat (set to height), smooth, noise (seeded bumps up to height), heights"
			+ " ((w+1)*(h+1) corner heights). Brushes add up; steeper than 1 in 1 is a cliff."
		),
		"ex": {"rect": [30, 4, 42, 14], "brush": "hill", "height": 2.0},
	},
	"road":
	{
		"grid": true,
		"req": ["points"],
		"opt":
		{"width": 3, "surface": "blacktop", "shoulder": -1, "ditch": false, "district": ""},
		"doc":
		(
			"A road along points, `width` cells wide: surface blacktop, gravel, dirt, concrete or"
			+ " oil; `shoulder` cells of gravel each side (blacktop 1, others 0); `ditch` a shallow"
			+ " ditch beyond them. Plants keep off it; a creek crossing it gets a bridge."
		),
		"ex": {"points": [[1, 24], [62, 24]], "surface": "blacktop"},
	},
	"creek":
	{
		"grid": true,
		"req": ["points"],
		"opt": {"width": 1.8, "depth": .35, "tile": "creek", "shore": "bayou_bank"},
		"doc": "A creek along points, `width` wide, its bed carved `depth` down, a shore round it.",
		"ex": {"points": [[1, 30], [20, 31], [62, 29]], "width": 1.8},
	},
	"pond":
	{
		"grid": true,
		"req": [],
		"opt":
		{
			"at": [],
			"radius": 3.0,
			"rect": [],
			"polygon": [],
			"depth": .35,
			"deep": true,
			"tile": "creek",
			"shore": "bayou_bank"
		},
		"doc":
		(
			"A pond: `at` + `radius`, a `rect` or a `polygon`. Flat water, a shore, deep water"
			+ " (nobody wades it) in its middle unless `deep` is false."
		),
		"ex": {"at": [12, 36], "radius": 3.5},
	},
	"trough":
	{
		"grid": false,
		"req": ["at"],
		"opt": {"along": "x", "length": 2.0},
		"doc": "A stock trough with water in it: furniture .45 high, `length` .8 to 4 along x or y.",
		"ex": {"at": [20.5, 12.5], "along": "x", "length": 2.0},
	},
	"foliage":
	{
		"grid": false,
		"req": ["kind"],
		"opt": {"rect": [], "polygon": [], "density": 1.0, "seed": 1, "rows": false},
		"doc":
		(
			"Plants scattered on natural ground in rect or polygon (the whole map when neither):"
			+ " grass, weeds, scrub, tree, pine, cypress, snag, corn (rows), reeds (by water)."
			+ " Never on a road, a route, by a door or a spawn."
		),
		"ex": {"kind": "pine", "rect": [1, 30, 15, 47], "density": 0.8},
	},
	"dress":
	{
		"grid": false,
		"req": ["rect", "theme"],
		"opt": {"count": 2, "seed": 1},
		"doc":
		(
			"`count` hand-made vignettes of a theme set against walls in rect: farm, junk, church,"
			+ " fair, yard_sale, shine, garage, swamp, house, store."
		),
		"ex": {"rect": [2, 2, 22, 20], "theme": "farm", "count": 2},
	},
	"vignette":
	{
		"grid": false,
		"req": ["name", "at", "wall"],
		"opt": {},
		"doc":
		(
			"One vignette by name (dressing.json: porch_sittin, junk_pile, wood_pile...) with its"
			+ " back to the wall on side `wall` (n, e, s, w) of cell `at`."
		),
		"ex": {"name": "wood_pile", "at": [10, 15], "wall": "n"},
	},
	"set_piece":
	{
		"grid": false,
		"req": ["kind", "at"],
		"opt": {"turn": 0, "falls": [0, 1, 2, 3]},
		"doc":
		(
			"A chapter-style big break: kind barn (comes down when its posts are shot),"
			+ " tower (falls and floods), fuel (a fuel line that burns). `falls`: ways it may go."
		),
		"ex": {"kind": "tower", "at": [57.5, 13.5], "falls": [1, 3]},
	},
	"switch":
	{
		"grid": false,
		"req": ["at"],
		"opt":
		{
			"label": "THROW THE SWITCH",
			"message": "",
			"opens": [],
			"requires": [],
			"prop": "quest_switch",
			"z": 0.0
		},
		"doc":
		(
			"A lever (an objective station): used, it opens the doors named in `opens` (door ids,"
			+ " a kit building's doors too: <id>_door_s); those doors have no handle of their own."
			+ " `requires`: switches to throw first."
		),
		"ex": {"at": [33.5, 8.5], "label": "OPEN THE BARN", "opens": ["barn_door"]},
	},
	"key":
	{
		"grid": false,
		"req": ["at", "doors"],
		"opt": {"color": "brass", "z": 0.0},
		"doc": "A key (brass or steel) lying at `at`; the doors named in `doors` need it.",
		"ex": {"at": [8.5, 30.5], "color": "brass", "doors": ["shed_door"]},
	},
	"kill_gate":
	{
		"grid": false,
		"req": ["rect", "opens"],
		"opt": {"message": ""},
		"doc":
		(
			"When every hand standing in rect is down, the doors in `opens` open (they have no"
			+ " handle till then)."
		),
		"ex": {"rect": [40, 4, 52, 16], "opens": ["back_gate"], "message": "THE BACK GATE'S OPEN."},
	},
	"wake_zone":
	{
		"grid": false,
		"req": ["rect"],
		"opt": {"trigger": [], "message": ""},
		"doc":
		(
			"The hands in rect sleep until a player walks into `trigger` (a rect; rect itself"
			+ " when left out), then they all come at once."
		),
		"ex": {"rect": [40, 4, 52, 16], "trigger": [36, 4, 40, 16]},
	},
	"message":
	{
		"grid": false,
		"req": ["rect", "text"],
		"opt": {"seconds": 3.0, "once": true},
		"doc": "Words on the screen when a player walks into rect.",
		"ex": {"rect": [20, 20, 24, 24], "text": "SMELLS LIKE HOGS."},
	},
	"trigger":
	{
		"grid": false,
		"req": ["when", "do"],
		"opt": {"once": true},
		"doc":
		(
			"A level trigger as src/triggers.gd has it (when: area, key, station, kills, after,"
			+ " down; do: message, sound, open, close, lock, wake, alert, light, shake, pickup)."
			+ " open, close and lock may name a door id; area is a rect."
		),
		"ex":
		{
			"when": {"station": "pump"},
			"do": [{"light": {"at": [30, 10], "radius": 6}}, {"sound": "lever_clunk"}]
		},
	},
	"prefab":
	{
		"grid": true,
		"req": ["name", "at"],
		"opt": {"turn": 0, "mirror": false},
		"doc":
		(
			"A group of objects defined once (the source's prefabs, or maps/prefabs/<name>.json)"
			+ " placed with its north-west corner at `at`, turned quarter turns clockwise and"
			+ " mirrored. Its objects' ids become <id>_<their id>."
		),
		"ex": {"name": "hog_pen", "at": [24, 30], "turn": 1},
	},
	"via":
	{
		"grid": false,
		"req": ["at"],
		"opt": {"z": 0.0},
		"doc": "A nav point by hand: where a way passes that the cells' middles miss.",
		"ex": {"at": [20.25, 8.0]},
	},
	"dm_spawn":
	{
		"grid": false,
		"req": ["at"],
		"opt": {"angle": -1.0},
		"doc":
		(
			"A deathmatch and team deathmatch start (give 6 or more, spread out). `angle` in"
			+ " degrees; left out, it faces the map's middle."
		),
		"ex": {"at": [6.5, 6.5]},
	},
	"team_spawn":
	{
		"grid": false,
		"req": ["team", "at"],
		"opt": {"count": 5, "angle": -1.0},
		"doc":
		(
			"A 5v5 side's start: team attack (the outlaws, who plant or rescue) or defend."
			+ " `count` places (5) are spread round `at`, facing the other side's start."
		),
		"ex": {"team": "attack", "at": [5.5, 24.5]},
	},
	"bomb_site":
	{
		"grid": false,
		"req": ["site", "rect"],
		"opt": {},
		"doc": "Search and destroy: bomb site A or B over rect.",
		"ex": {"site": "A", "rect": [46, 4, 54, 12]},
	},
	"hostage":
	{
		"grid": false,
		"req": ["at"],
		"opt": {},
		"doc": "Hostage rescue: a hostage held at `at` (near the defenders).",
		"ex": {"at": [52.5, 6.5]},
	},
	"rescue_zone":
	{
		"grid": false,
		"req": ["rect"],
		"opt": {},
		"doc": "Hostage rescue: where the attackers carry a hostage to (round their start).",
		"ex": {"rect": [2, 20, 10, 30]},
	},
	"bot_route":
	{
		"grid": false,
		"req": ["site", "points"],
		"opt": {},
		"doc": "A way the 5v5 bots walk to site A or B (points). Left out, they go straight.",
		"ex": {"site": "A", "points": [[8.5, 20.5], [30.5, 10.5], [50.5, 8.5]]},
	},
	"bot_hold":
	{
		"grid": false,
		"req": ["site", "at"],
		"opt": {"angle": 0.0},
		"doc": "Where a defending bot holds (site A, B or mid), facing `angle` degrees.",
		"ex": {"site": "A", "at": [52.5, 10.5], "angle": 180},
	},
}

## v2 keys on v1 types (their defaults); using one makes a source version 2.
const V1_KEYS := {
	"door": {"z": 0.0, "span": 1, "bar": ""},
	"wall": {"curve": {}},
}


## Every v2 type: TYPES plus one per kit piece (not KIT_ONLY), each row
## marked "v": 2 (and "kit": true for a kit piece).
static func types() -> Dictionary:
	var out := {}
	for type: String in TYPES:
		var row: Dictionary = (TYPES[type] as Dictionary).duplicate(true)
		row["v"] = 2
		out[type] = row
	for piece: String in KitPiece.names():
		if piece in KIT_ONLY:
			continue
		out[piece] = kit_row(piece)
	return out


## A kit piece as a type row: `at` needed, the piece's size, turn, style and
## options with their defaults.
static func kit_row(piece: String) -> Dictionary:
	var entry := KitPiece.catalog(piece)
	var opt := {
		"w": _default(entry.get("w", [1])),
		"d": _default(entry.get("d", [1])),
		"face": "s",
		"turn": 0,
		"mirror": false,
		"style": str(entry.get("style", "")),
		"variant": 0,
		"district": "",
	}
	var options: Dictionary = entry.get("options", {})
	for key: String in options:
		opt[key] = _default(options[key])
	var ex := {"at": [10, 8]}
	return {
		"grid": true,
		"req": ["at"],
		"opt": opt,
		"doc": str(KIT_DOCS.get(piece, "A kit piece.")),
		"ex": ex,
		"v": 2,
		"kit": true,
	}


## A kit option's default: the first of a [default, min, max] or [default,
## choices...] rule, or the value itself.
static func _default(rule: Variant) -> Variant:
	if rule is Array:
		var list: Array = rule
		return list[0] if not list.is_empty() else null
	return rule


## The version a source needs: 2 when anything in it is v2, else 1.
static func needed(doc: Dictionary, all_types: Dictionary) -> int:
	for key: String in TOP_V2:
		if doc.has(key):
			return 2
	for d in doc.get("districts", []):
		if d is Dictionary and ((d as Dictionary).has("mood") or (d as Dictionary).has("rect")):
			return 2
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var type := str(o.get("type", ""))
		if int((all_types.get(type, {}) as Dictionary).get("v", 1)) >= 2:
			return 2
		for key: String in V1_KEYS.get(type, {}):
			if o.has(key):
				return 2
		if type == "door" and str(o.get("style", "")) == "barn":
			return 2
		for hole in o.get("openings", []):
			if hole is Dictionary and ((hole as Dictionary).has("pane")):
				return 2
	return 1


# ------------------------------------------------------------------ prefabs


## The source with every prefab object replaced by its objects, placed,
## turned, mirrored and renamed (<prefab id>_<object id>), references
## inside it renamed too. Problems go to `out` (prefab_missing,
## prefab_loop, prefab). A source without prefabs comes back as it is.
static func expand(doc: Dictionary, out: Array) -> Dictionary:
	var has := false
	for o in doc.get("objects", []):
		if o is Dictionary and str(o.get("type", "")) == "prefab":
			has = true
			break
	if not has:
		return doc
	var full := doc.duplicate(true)
	var objects: Array = []
	for o in doc.get("objects", []):
		_expand_one(o, doc, objects, out, [])
	full["objects"] = objects
	return full


static func _expand_one(o: Variant, doc: Dictionary, into: Array, out: Array, chain: Array) -> void:
	if not (o is Dictionary) or str(o.get("type", "")) != "prefab":
		into.append(o)
		return
	var oid := str(o.get("id", ""))
	var name := str(o.get("name", ""))
	if name in chain:
		out.append(
			_issue(
				"error",
				"prefab_loop",
				oid,
				"prefab %s places itself (%s)" % [name, " > ".join(PackedStringArray(chain + [name]))],
				"a prefab may place other prefabs, never itself"
			)
		)
		return
	var def := prefab(doc, name)
	if def.is_empty():
		out.append(
			_issue(
				"error",
				"prefab_missing",
				oid,
				"no prefab named %s" % name,
				(
					'define it in the source\'s "prefabs" or in godot/maps/prefabs/%s.json (%s)'
					% [name, ", ".join(PackedStringArray(prefab_names(doc)))]
				)
			)
		)
		return
	var at: Array = o.get("at", [0, 0])
	var size: Array = def.get("size", [0, 0])
	var place := {
		"x": float(at[0]),
		"y": float(at[1]),
		"w": float(size[0]),
		"d": float(size[1]),
		"turn": posmod(int(o.get("turn", 0)), 4),
		"mirror": bool(o.get("mirror", false)),
	}
	var ids := {}
	for p in def.get("objects", []):
		if p is Dictionary:
			ids[str(p.get("id", ""))] = "%s_%s" % [oid, p.get("id", "")]
	for p in def.get("objects", []):
		if not (p is Dictionary):
			continue
		var moved := place_object(p, place)
		moved["id"] = ids.get(str(p.get("id", "")), oid)
		_rename_refs(moved, ids)
		_expand_one(moved, doc, into, out, chain + [name])


## A prefab's definition: {size: [w, d], objects: [...]} from the source's
## "prefabs" or godot/maps/prefabs/<name>.json ({} when there is none).
static func prefab(doc: Dictionary, name: String) -> Dictionary:
	var own: Variant = doc.get("prefabs", {})
	if own is Dictionary and (own as Dictionary).has(name):
		var def: Variant = own[name]
		if def is Array:
			return {"size": _extent(def), "objects": def}
		if def is Dictionary:
			var d: Dictionary = def
			if not d.has("size"):
				d = d.duplicate()
				d["size"] = _extent(d.get("objects", []))
			return d
		return {}
	var path := "res://maps/prefabs/%s.json" % name
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if not d.has("size"):
		d["size"] = _extent(d.get("objects", []))
	return d


static func prefab_names(doc: Dictionary) -> Array:
	var out: Array = []
	var own: Variant = doc.get("prefabs", {})
	if own is Dictionary:
		out.append_array((own as Dictionary).keys())
	if DirAccess.dir_exists_absolute("res://maps/prefabs"):
		for f: String in DirAccess.get_files_at("res://maps/prefabs"):
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out


## How far a list of objects reaches east and south of (0, 0), in whole cells.
static func _extent(objects: Variant) -> Array:
	var w := 0.0
	var d := 0.0
	if objects is Array:
		for o in objects:
			if not (o is Dictionary):
				continue
			for p: Vector2 in _points_of(o):
				w = maxf(w, p.x)
				d = maxf(d, p.y)
	return [ceilf(w), ceilf(d)]


static func _points_of(o: Dictionary) -> Array:
	var out: Array = []
	for key: String in ["at", "a", "b"]:
		if o.get(key) is Array and (o[key] as Array).size() >= 2:
			out.append(Vector2(float(o[key][0]), float(o[key][1])))
	if o.get("cell") is Array:
		out.append(Vector2(float(o["cell"][0]) + 1.0, float(o["cell"][1]) + 1.0))
	for key: String in ["rect", "trigger"]:
		var r: Variant = o.get(key)
		if r is Array and (r as Array).size() == 4:
			out.append(Vector2(float(r[2]), float(r[3])))
	for key: String in ["points", "polygon"]:
		var list: Variant = o.get(key)
		if list is Array:
			for p in list:
				if p is Array and (p as Array).size() >= 2:
					out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A point of a prefab (local, its footprint w x d) on the map.
static func put(p: Vector2, place: Dictionary) -> Vector2:
	var w: float = place["w"]
	var d: float = place["d"]
	var q := p
	if place["mirror"]:
		q.x = w - q.x
	match int(place["turn"]):
		1:
			q = Vector2(d - q.y, q.x)
		2:
			q = Vector2(w - q.x, d - q.y)
		3:
			q = Vector2(q.y, w - q.x)
	return Vector2(snappedf(q.x + float(place["x"]), .0001), snappedf(q.y + float(place["y"]), .0001))


## A side (n, e, s, w) turned and mirrored as the prefab is.
static func put_side(side: String, place: Dictionary) -> String:
	const ORDER := ["n", "e", "s", "w"]
	var i := ORDER.find(side)
	if i < 0:
		return side
	if place["mirror"] and (side == "e" or side == "w"):
		i = (i + 2) % 4
	return ORDER[(i + int(place["turn"])) % 4]


static func _rect_on(r: Array, place: Dictionary) -> Array:
	var a := put(Vector2(float(r[0]), float(r[1])), place)
	var b := put(Vector2(float(r[2]), float(r[3])), place)
	return [minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y)]


static func _pt(v: Vector2) -> Array:
	return [v.x, v.y]


## One prefab object placed on the map (a copy).
static func place_object(o: Dictionary, place: Dictionary) -> Dictionary:
	var m := o.duplicate(true)
	var turn: int = place["turn"]
	var mirror: bool = place["mirror"]
	var type := str(o.get("type", ""))
	var kit := (type == "kit" or KitPiece.names().has(type)) and type != "prefab"
	if type in KIT_ONLY:
		kit = false
	if kit and o.get("at") is Array:
		# A kit piece's footprint turns with the prefab; its own turn adds on.
		var piece := str(o.get("piece", type))
		var res := KitPiece.resolve(_kit_spec(o, piece))
		if not res.has("error"):
			var own: int = res["turn"]
			var fw: float = res["w"] if own % 2 == 0 else res["d"]
			var fd: float = res["d"] if own % 2 == 0 else res["w"]
			var x0 := float(o["at"][0])
			var y0 := float(o["at"][1])
			var r := _rect_on([x0, y0, x0 + fw, y0 + fd], place)
			m["at"] = [r[0], r[1]]
			var new_turn := own
			if mirror:
				new_turn = (4 - own) % 4 if own % 2 == 1 else own
				m["mirror"] = not bool(o.get("mirror", false))
			m["turn"] = (new_turn + turn) % 4
			m.erase("face")
		return m
	if o.get("rect") is Array and (o["rect"] as Array).size() == 4:
		m["rect"] = _rect_on(o["rect"], place)
	if o.get("trigger") is Array and (o["trigger"] as Array).size() == 4:
		m["trigger"] = _rect_on(o["trigger"], place)
	for key: String in ["at", "a", "b"]:
		if o.get(key) is Array and (o[key] as Array).size() >= 2:
			var p := put(Vector2(float(o[key][0]), float(o[key][1])), place)
			var arr: Array = (o[key] as Array).duplicate()
			arr[0] = p.x
			arr[1] = p.y
			m[key] = arr
	if o.get("cell") is Array:
		var c := put(Vector2(float(o["cell"][0]) + .5, float(o["cell"][1]) + .5), place)
		m["cell"] = [int(floorf(c.x)), int(floorf(c.y))]
		if turn % 2 == 1:
			m["vertical"] = not bool(o.get("vertical", false))
	for key: String in ["points", "polygon"]:
		if o.get(key) is Array:
			var pts: Array = []
			for p in o[key]:
				pts.append(_pt(put(Vector2(float(p[0]), float(p[1])), place)))
			m[key] = pts
	for key: String in ["toward", "from", "wall"]:
		if o.has(key) and o[key] is String:
			m[key] = put_side(str(o[key]), place)
	if o.has("open") and o["open"] is String:
		var sides := ""
		for ch in str(o["open"]):
			sides += put_side(ch, place)
		m["open"] = sides
	var auto_angle := type in ["dm_spawn", "team_spawn"] and float(o.get("angle", -1.0)) < 0.0
	if o.has("angle") and not auto_angle:
		var ang := float(o["angle"])
		if mirror:
			ang = 180.0 - ang
		m["angle"] = fposmod(ang + 90.0 * turn, 360.0)
	if o.has("along") and turn % 2 == 1:
		m["along"] = "y" if str(o["along"]) == "x" else "x"
	return m


## A kit object as KitPiece's spec: piece, id, x and y from `at`, its own
## keys, `district` (a name) left to the compiler.
static func _kit_spec(o: Dictionary, piece: String) -> Dictionary:
	var spec := {"piece": piece, "id": str(o.get("id", "piece"))}
	for key: String in o:
		if key in ["id", "type", "piece", "at", "district"] or key.begins_with("_"):
			continue
		spec[key] = o[key]
	var at: Array = o.get("at", [0, 0]) if o.get("at") is Array else [0, 0]
	if at.size() >= 2:
		spec["x"] = at[0]
		spec["y"] = at[1]
	return spec


## Ids named inside a placed prefab object (doors a switch opens, objects an
## allow_overlap names) renamed to the placed ones.
static func _rename_refs(o: Dictionary, ids: Dictionary) -> void:
	for key: String in ["opens", "doors", "requires", "objects", "close"]:
		if o.get(key) is Array:
			var named: Array = []
			for v in o[key]:
				named.append(ids.get(str(v), v) if v is String else v)
			o[key] = named


static func _issue(
	severity: String, code: String, object_id: String, message: String, hint: String
) -> Dictionary:
	var d := {"severity": severity, "code": code, "object": object_id, "message": message}
	if hint != "":
		d["hint"] = hint
	return d


# ------------------------------------------------------------------- checks


## The words a key may take, said in a problem: "one of a, b, c".
static func _one_of(list: Array) -> String:
	return "one of " + ", ".join(PackedStringArray(list))


static func _bad(out: Array, code: String, where: String, message: String, hint: String) -> void:
	out.append(_issue("error", code, where, message, hint))


static func _rect_ok(r: Variant) -> bool:
	if not (r is Array) or (r as Array).size() != 4:
		return false
	return float(r[2]) > float(r[0]) and float(r[3]) > float(r[1])


static func _points_ok(list: Variant, least: int) -> bool:
	if not (list is Array) or (list as Array).size() < least:
		return false
	for p in list:
		if not (p is Array) or (p as Array).size() < 2:
			return false
	return true


## A v2 object's own values (the shape map_source.gd checks for every type
## is done already): names that must exist, words from short lists.
static func check_object(
	out: Array, o: Dictionary, type: String, where: String, names: Dictionary, _seen: Dictionary
) -> void:
	var dressing: Dictionary = MapLooksGrid.tuning()
	match type:
		"door":
			if o.has("span") and not (int(o["span"]) in [1, 2, 3]):
				_bad(out, "door", where, "span is 1, 2 or 3 cells", "a barn door is span 3")
			if float(o.get("z", 0.0)) < 0.0 or float(o.get("z", 0.0)) > 100.0:
				_bad(out, "door", where, "z is 0 to 100", "the floor the door stands on")
			if str(o.get("bar", "")) != "" and not (str(o["bar"]) in ["n", "e", "s", "w"]):
				_bad(out, "door", where, "bar is n, e, s or w (the side it is barred from)", "")
			if not (str(o.get("style", "hinge")) in ["hinge", "slide", "barn"]):
				_bad(out, "door", where, "style is hinge, slide or barn", "")
		"wall":
			var curve: Variant = o.get("curve", {})
			if curve is Dictionary and not (curve as Dictionary).is_empty():
				var c: Dictionary = curve
				if not _points_ok([c.get("centre")], 1) or float(c.get("radius", 0.0)) <= .3:
					_bad(
						out,
						"curve",
						where,
						"curve wants centre [x, y] and a radius over .3",
						'"curve": {"centre": [20, 12], "radius": 4, "from": 180, "to": 360}'
					)
		"kit":
			if not KitPiece.names().has(str(o.get("piece", ""))):
				_bad(
					out,
					"kit",
					where,
					"no kit piece named %s" % o.get("piece"),
					_one_of(KitPiece.names())
				)
		"terrain":
			var brush := str(o.get("brush", "hill"))
			if not (brush in BRUSHES):
				_bad(out, "terrain_brush", where, "brush %s is not %s" % [brush, _one_of(BRUSHES)], "")
			if brush == "heights" and o.get("rect") is Array and _rect_ok(o["rect"]):
				var r: Array = o["rect"]
				var want := (int(r[2]) - int(r[0]) + 1) * (int(r[3]) - int(r[1]) + 1)
				if not (o.get("heights") is Array) or (o["heights"] as Array).size() != want:
					_bad(
						out,
						"terrain_brush",
						where,
						"brush heights wants %d corner heights ((w + 1) * (h + 1))" % want,
						"row by row from the north-west corner, in map units"
					)
			if absf(float(o.get("height", 2.0))) > 40.0:
				_bad(out, "terrain_brush", where, "height is -40 to 40", "")
		"road":
			if not _points_ok(o.get("points"), 2):
				_bad(out, "points", where, "a road wants two or more points [x, y]", "")
			if not SURFACES.has(str(o.get("surface", "blacktop"))):
				_bad(out, "road", where, "surface is %s" % _one_of(SURFACES.keys()), "")
			if float(o.get("width", 3)) < 1 or float(o.get("width", 3)) > 12:
				_bad(out, "road", where, "width is 1 to 12 cells", "")
		"creek":
			if not _points_ok(o.get("points"), 2):
				_bad(out, "points", where, "a creek wants two or more points [x, y]", "")
		"pond":
			var shaped := (
				(o.has("at") and _points_ok([o.get("at")], 1) and float(o.get("radius", 3.0)) > 0.5)
				or (o.has("rect") and _rect_ok(o.get("rect", [])))
				or (o.has("polygon") and _points_ok(o.get("polygon", []), 3))
			)
			if not shaped:
				_bad(
					out,
					"pond",
					where,
					"a pond wants at and radius, a rect, or a polygon of 3 or more points",
					'{"type": "pond", "at": [12, 36], "radius": 3.5}'
				)
		"foliage":
			var kinds: Dictionary = dressing.get("foliage", {})
			if not kinds.has(str(o.get("kind", ""))):
				_bad(
					out,
					"foliage_kind",
					where,
					"no foliage kind %s" % o.get("kind"),
					_one_of(kinds.keys())
				)
		"dress":
			var themes: Array = dressing.get("themes", [])
			if not themes.has(str(o.get("theme", ""))):
				_bad(out, "dress_theme", where, "no theme %s" % o.get("theme"), _one_of(themes))
		"vignette":
			var known: Dictionary = dressing.get("vignettes", {})
			if not known.has(str(o.get("name", ""))):
				_bad(out, "vignette", where, "no vignette %s" % o.get("name"), _one_of(known.keys()))
			if not (str(o.get("wall", "")) in ["n", "e", "s", "w"]):
				_bad(out, "vignette", where, "wall is n, e, s or w", "")
		"set_piece":
			if not (str(o.get("kind", "")) in ["barn", "tower", "fuel"]):
				_bad(out, "set_piece_kind", where, "kind is barn, tower or fuel", "")
		"key":
			if not (str(o.get("color", "brass")) in KEYS):
				_bad(out, "key", where, "color is brass or steel", "")
			if not (o.get("doors") is Array) or (o["doors"] as Array).is_empty():
				_bad(
					out, "logic_target", where, "a key opens nothing: doors is empty", "name its doors"
				)
		"kill_gate":
			var opens: Variant = o.get("opens", [])
			if not (opens is Array) or (opens as Array).is_empty():
				_bad(
					out,
					"logic_target",
					where,
					"a kill gate opens nothing: opens is empty",
					"name the door ids it opens"
				)
		"team_spawn":
			if not (str(o.get("team", "")) in TEAMS):
				_bad(out, "team", where, "team is attack or defend", "")
			if int(o.get("count", 5)) < 1 or int(o.get("count", 5)) > 8:
				_bad(out, "team", where, "count is 1 to 8", "")
		"bomb_site", "bot_route":
			if not (str(o.get("site", "")) in ["A", "B"]):
				_bad(out, "site", where, "site is A or B", "")
			if type == "bot_route" and not _points_ok(o.get("points"), 1):
				_bad(out, "points", where, "a route wants points [x, y]", "")
		"bot_hold":
			if not (str(o.get("site", "")) in ["A", "B", "mid"]):
				_bad(out, "site", where, "site is A, B or mid", "")
		"message":
			if str(o.get("text", "")) != str(o.get("text", "")).to_upper():
				out.append(
					_issue(
						"warning",
						"message",
						where,
						"words on the screen are upper case in this game",
						"write it in capitals"
					)
				)
	for key: String in ["rect", "trigger"]:
		if o.has(key) and o[key] is Array and not (o[key] as Array).is_empty():
			if not _rect_ok(o[key]):
				_bad(out, "rect", where, "%s must be [x0, y0, x1, y1], x1 > x0, y1 > y0" % key, "")
	var tiles: Dictionary = names.get("tiles", {})
	if type in ["terrain", "creek", "pond"]:
		for key: String in ["floor", "cliff", "tile", "shore"]:
			if str(o.get(key, "")) != "" and not tiles.is_empty() and not tiles.has(str(o[key])):
				_bad(out, "no_tile", where, "%s: no tile named %s" % [key, o[key]], "")


## The top-level v2 keys: modes, mood, prefabs, districts' moods.
static func check_top(out: Array, doc: Dictionary, _names: Dictionary) -> void:
	var modes: Variant = doc.get("modes", [])
	if not (modes is Array):
		_bad(out, "modes", "", "modes is a list of %s" % _one_of(MODES), "")
	else:
		for m in modes:
			if not (str(m) in MODES):
				_bad(out, "modes", "", "no mode %s: modes are %s" % [m, _one_of(MODES)], "")
	var moods: Array = Effects.MOODS.keys()
	var mood := str(doc.get("mood", ""))
	if mood != "" and not moods.has(mood):
		_bad(out, "mood_unknown", "", "no mood %s" % mood, _one_of(moods))
	for d in doc.get("districts", []):
		if not (d is Dictionary):
			continue
		var dm := str(d.get("mood", ""))
		if dm != "" and not moods.has(dm):
			_bad(out, "mood_unknown", str(d.get("id", "")), "no mood %s" % dm, _one_of(moods))
		if d.has("rect") and not _rect_ok(d["rect"]):
			_bad(out, "rect", str(d.get("id", "")), "a district's rect is [x0, y0, x1, y1]", "")
	var prefabs: Variant = doc.get("prefabs", {})
	if not (prefabs is Dictionary):
		_bad(out, "prefab", "", 'prefabs is {"name": {"size": [w, d], "objects": [...]}}', "")
