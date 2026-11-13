## Turns the game's live objects into plain values and back, for snapshots
## (game_snapshot.gd). Plain values (numbers, strings, vectors, packed arrays)
## pass through; arrays and dictionaries are walked; an object becomes:
##   {"@p": slot}        a Player          {"@e": uid}      an Enemy
##   {"@world": 1}       the level         {"@door"/"@station"/"@scenery": i}
##   {"@feature": id}    a GameFeature     {"@game": 1}     the game itself
##   {"@rng": [seed, state]}               a RandomNumberGenerator
##   {"@iid": uid}       an enemy's instance id (a shot's thrower, a feature's
##                       dictionary keyed by enemy): another machine's differ
##   {"@o": class, "f": {field: value}}    any other script object, by its
##                                         class's name (REGISTRY roots)
##   {"@flow": [ox, oy, next_at, walked, cells, steps]}   a FlowField: only
##                       the cells its last walk reached and their steps (the
##                       rest is FAR; its open floor follows the level)
##   {"@skip": 1}        what a snapshot never carries (sprites, images,
##                       threads, callables): apply leaves it as it is.
## A dictionary with an object for a key is {"@D": [[key, value], ...]}.
## Decoding works in place where it can: an object of the same class, an
## array or a dictionary already there is filled, not replaced, so what it
## does not carry (a sprite, a cache) and who else holds it stay.
class_name SnapCodec
extends RefCounted

const SKIP := {"@skip": 1}
## Classes a snapshot never carries (presentation).
const VIEW_CLASSES := [
	"Renderer.Sprite",
	"Renderer.GroundMark",
	"Renderer.WallMark",
	"PlayerVoice",
	"Sound",
	"HUD",
	"QuietSound"
]
## Fields of a class a snapshot leaves out: worked out from others (Enemy
## alive, z), presentation (a player's voice and gun sway), wiring, or what
## the level makes the same on every machine and never changes (a feature's
## tuning, its lookups over the level's walls).
const SKIP_FIELDS := {
	"Enemy": ["alive", "z"],
	"Player": ["voice", "weapon_lag"],
	"Weapons.Armory": ["boxes"],
	"wall_breaks": ["by_cell", "win", "_faces", "_loose", "gaps"],
	"breakables": ["_feels", "_cfg", "_resting", "_resting_dirty"],
}
## Classes of which a snapshot carries only these fields: things a level
## makes the same on every machine (a window, a fence cell, a breakable
## piece, a board) whose other fields never change once made. Only ever
## decoded onto the same thing made by the same level.
const ONLY_FIELDS := {
	"wall_breaks.WindowFace": ["broken"],
	"wall_breaks.Fence": ["hp", "stage"],
	"breakables.Piece": ["x", "y", "hp", "broken", "board"],
	"LevelData.Billboard": ["x", "y", "image", "height"],
}
## Value types passed through as they are (no objects inside them).
const PLAIN := {
	TYPE_NIL: true,
	TYPE_BOOL: true,
	TYPE_FLOAT: true,
	TYPE_STRING: true,
	TYPE_STRING_NAME: true,
	TYPE_VECTOR2: true,
	TYPE_VECTOR2I: true,
	TYPE_VECTOR3: true,
	TYPE_VECTOR3I: true,
	TYPE_VECTOR4: true,
	TYPE_RECT2: true,
	TYPE_RECT2I: true,
	TYPE_COLOR: true,
	TYPE_PACKED_BYTE_ARRAY: true,
	TYPE_PACKED_INT32_ARRAY: true,
	TYPE_PACKED_INT64_ARRAY: true,
	TYPE_PACKED_FLOAT32_ARRAY: true,
	TYPE_PACKED_FLOAT64_ARRAY: true,
	TYPE_PACKED_STRING_ARRAY: true,
	TYPE_PACKED_VECTOR2_ARRAY: true,
	TYPE_PACKED_VECTOR3_ARRAY: true,
}
const DEPTH := 14

var game
## Enemies by uid while decoding, and their instance ids -> uid while
## encoding (both filled from game.enemies).
var by_uid := {}
var iids := {}
## Class names met that it could not carry (diagnostics: net_check prints them).
var unknown := {}

static var _by_script := {}
static var _by_key := {}
static var _fields := {}
static var _snames := {}
static var _made := {}


func _init(p_game) -> void:
	game = p_game
	if _by_key.is_empty():
		_register_all()
	for e: Enemy in game.enemies:
		iids[e.get_instance_id()] = e.uid


# ------------------------------------------------------------------ encode


func encode(value, depth := 0):
	match typeof(value):
		TYPE_OBJECT:
			return _encode_object(value, depth)
		TYPE_ARRAY:
			var out: Array = []
			out.resize(value.size())
			for i in value.size():
				var v = value[i]
				out[i] = v if PLAIN.has(typeof(v)) else encode(v, depth + 1)
			return out
		TYPE_DICTIONARY:
			var plain := true
			for key in value:
				if typeof(key) == TYPE_OBJECT or (typeof(key) == TYPE_INT and iids.has(key)):
					plain = false
					break
			if plain:
				var out := {}
				for key in value:
					var v = value[key]
					out[key] = v if PLAIN.has(typeof(v)) else encode(v, depth + 1)
				return out
			var rows: Array = []
			for key in value:
				rows.append([encode(key, depth + 1), encode(value[key], depth + 1)])
			return {"@D": rows}
		TYPE_INT:
			if iids.has(value):
				return {"@iid": iids[value]}
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return SKIP
	return value


## A deep copy of plain data with every array untyped (a save document holds
## the game's own arrays: a snapshot must not change as the game goes on).
static func plain(value):
	if value is Array:
		var out: Array = []
		out.resize(value.size())
		for i in value.size():
			out[i] = plain(value[i])
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = plain(value[key])
		return out
	return value


## Every carried field of `o` (a player, an enemy...) as plain values.
func encode_fields(o: Object) -> Dictionary:
	var key := class_key(o.get_script())
	var fields := {}
	var names := fields_of(o, key)
	var snames: Array[StringName] = _snames[o.get_script()]
	for i in names.size():
		var v = o.get(snames[i])
		# Most fields are plain: no call for them.
		fields[names[i]] = v if PLAIN.has(typeof(v)) else encode(v, 1)
	return fields


## A flow field: where it was measured from and when next, whether its first
## walk is done, and the steps of the cells its last walk reached (every
## other cell is FAR: flow_field.gd keeps it so).
static func encode_flow(f: FlowField) -> Dictionary:
	var at := f._touched
	var most := 0
	for cell in at:
		most = maxi(most, f.steps[cell])
	var steps: Variant = PackedByteArray() if most < 255 else PackedInt32Array()
	steps.resize(at.size())
	for i in at.size():
		steps[i] = f.steps[at[i]]
	return {"@flow": [f.origin.x, f.origin.y, f.next_at, f._walked, at, steps]}


## Puts an encode_flow() back: the steps it carries, FAR elsewhere, and no walk
## left half done (the scratch field a walk fills is all FAR, as update()
## leaves it before every walk).
static func decode_flow(f: FlowField, row: Array) -> void:
	f.origin = Vector2i(int(row[0]), int(row[1]))
	f.next_at = float(row[2])
	f._walked = bool(row[3])
	var at := PackedInt32Array(row[4])
	var steps = row[5]
	f.steps.fill(FlowField.FAR)
	for i in at.size():
		f.steps[at[i]] = int(steps[i])
	f._touched = at
	f._next.fill(FlowField.FAR)
	f._next_touched = PackedInt32Array()
	f._queue = PackedInt32Array()
	f._head = 0


func _encode_object(o: Object, depth: int):
	if o == null:
		return null
	if o is Player:
		return {"@p": o.slot}
	if o is Enemy:
		return {"@e": o.uid}
	if o == game:
		return {"@game": 1}
	if o is GameFeature:
		return {"@feature": o.id()}
	if o is LevelData:
		return {"@world": 1}
	if o is LevelData.Door:
		return {"@door": game.world.doors.find(o)}
	if o is LevelData.Station:
		return {"@station": game.world.stations.find(o)}
	if o is LevelData.Scenery:
		return {"@scenery": game.world.scenery.find(o)}
	if o is RandomNumberGenerator:
		return {"@rng": [o.seed, o.state]}
	if o is FlowField:
		return encode_flow(o)
	if o is Renderer.Sprite or o is Renderer.GroundMark or o is Renderer.WallMark:
		return SKIP
	var script = o.get_script()
	if script == null or not (o is RefCounted) or depth > DEPTH:
		return SKIP
	var key := class_key(script)
	if key == "":
		var names: Array = []
		for prop: Dictionary in o.get_property_list():
			if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and names.size() < 4:
				names.append(prop["name"])
		unknown["an object with " + ", ".join(names)] = true
		return SKIP
	if VIEW_CLASSES.has(key):
		return SKIP
	var fields := {}
	var names := fields_of(o, key)
	var snames: Array[StringName] = _snames[script]
	for i in names.size():
		var v = o.get(snames[i])
		fields[names[i]] = v if PLAIN.has(typeof(v)) else encode(v, depth + 1)
	return {"@o": key, "f": fields}


# ------------------------------------------------------------------ decode


## The live value for `value`, filling `existing` in place where it can.
func decode(value, existing = null):
	match typeof(value):
		TYPE_ARRAY:
			var out: Array = []
			out.resize(value.size())
			var old: Array = existing if existing is Array else []
			for i in value.size():
				out[i] = decode(value[i], old[i] if i < old.size() else null)
			if existing is Array:
				existing.assign(out)
				return existing
			return out
		TYPE_DICTIONARY:
			return _decode_dictionary(value, existing)
	return value


func _decode_dictionary(value: Dictionary, existing):
	if value.has("@skip"):
		return existing
	if value.has("@p"):
		var slot := int(value["@p"])
		return game.players[slot] if slot < game.players.size() else null
	if value.has("@e"):
		return by_uid.get(int(value["@e"]))
	if value.has("@iid"):
		var e = by_uid.get(int(value["@iid"]))
		return e.get_instance_id() if e != null else 0
	if value.has("@game"):
		return game
	if value.has("@feature"):
		return game.features.get(String(value["@feature"]))
	if value.has("@world"):
		return game.world
	if value.has("@door"):
		return _at(game.world.doors, int(value["@door"]))
	if value.has("@station"):
		return _at(game.world.stations, int(value["@station"]))
	if value.has("@scenery"):
		return _at(game.world.scenery, int(value["@scenery"]))
	if value.has("@rng"):
		var rng: RandomNumberGenerator = (
			existing if existing is RandomNumberGenerator else RandomNumberGenerator.new()
		)
		rng.seed = int(value["@rng"][0])
		rng.state = int(value["@rng"][1])
		return rng
	if value.has("@o"):
		return _decode_object(String(value["@o"]), value["f"], existing)
	if value.has("@flow"):
		# Only ever onto the flow field already there (it needs its level).
		if existing is FlowField:
			decode_flow(existing, value["@flow"])
		return existing
	var into: Dictionary = existing if existing is Dictionary else {}
	var old := into.duplicate()
	into.clear()
	if value.has("@D"):
		for row: Array in value["@D"]:
			var key = decode(row[0])
			into[key] = decode(row[1], old.get(key))
		return into
	for key in value:
		into[key] = decode(value[key], old.get(key))
	return into


func _decode_object(key: String, fields: Dictionary, existing):
	var script = _by_key.get(key)
	if script == null:
		unknown[key] = true
		return existing
	var o = existing
	if o == null or not (o is Object) or o.get_script() != script:
		o = _make(script)
		if o == null:
			unknown[key + " (cannot be made)"] = true
			return existing
	for name: String in fields:
		set_field(o, name, fields[name])
	return o


## Sets one field of `o` from its snapshot value (in place for an array, a
## dictionary or an object of the same class).
func set_field(o: Object, name: String, value) -> void:
	var now = o.get(name)
	var made = decode(value, now)
	if (typeof(now) == TYPE_ARRAY or typeof(now) == TYPE_DICTIONARY) and is_same(made, now):
		return
	o.set(name, made)


static func _at(list: Array, i: int):
	return list[i] if i >= 0 and i < list.size() else null


## A new object of `script` when its _init needs no arguments, else null.
static func _make(script: Script) -> Object:
	if not _made.has(script):
		var ok := true
		for m: Dictionary in script.get_script_method_list():
			if m["name"] == "_init":
				ok = m["args"].size() <= m["default_args"].size()
				break
		_made[script] = ok
	return script.new() if _made[script] else null


# --------------------------------------------------------------- classes


## The name a snapshot gives `script`'s objects ("" when it has none).
static func class_key(script: Script) -> String:
	if _by_key.is_empty():
		_register_all()
	return String(_by_script.get(script, ""))


## The fields of `o` a snapshot carries: its script variables, less SKIP_FIELDS.
static func fields_of(o: Object, key: String) -> PackedStringArray:
	var script: Script = o.get_script()
	if _fields.has(script):
		return _fields[script]
	var skip: Array = SKIP_FIELDS.get(key, [])
	var only: Array = ONLY_FIELDS.get(key, [])
	var names := PackedStringArray()
	for prop: Dictionary in o.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := String(prop["name"])
		if not skip.has(name) and (only.is_empty() or only.has(name)):
			names.append(name)
	_fields[script] = names
	_snames[script] = names_of(names)
	return names


## The names as StringNames (Object.get() takes those without converting).
static func names_of(names: PackedStringArray) -> Array[StringName]:
	var out: Array[StringName] = []
	for name in names:
		out.append(StringName(name))
	return out


static func _register_all() -> void:
	var roots := {
		"GameState": GameState,
		"Enemy": Enemy,
		"Player": Player,
		"FlowField": FlowField,
		"Weapons": Weapons,
		"Squad": Squad,
		"LevelData": LevelData,
		"Renderer": Renderer,
		"Tumble": Tumble,
		"PlayerVoice": PlayerVoice,
		"Sound": Sound,
		"HUD": HUD,
	}
	for script: GDScript in Features.ALL:
		roots[script.resource_path.get_file().get_basename()] = script
	for key: String in roots:
		_register(key, roots[key])


static func _register(key: String, script: Script) -> void:
	if _by_script.has(script):
		return
	_by_script[script] = key
	_by_key[key] = script
	for name: String in script.get_script_constant_map():
		var inner = script.get_script_constant_map()[name]
		if inner is GDScript and not _by_script.has(inner):
			_register(key + "." + name, inner)
