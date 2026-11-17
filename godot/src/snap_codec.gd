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
##   {"@T": [class, names, keys, columns]}  a feature's NET_GUARDED list or
##                       dictionary of objects of one class, as one table
##                       (guarded(), table()): a column a field, packed
##                       where its type allows
## A dictionary with an object for a key is {"@D": [[key, value], ...]}.
## Decoding works in place where it can: an object of the same class, an
## array or a dictionary already there is filled, not replaced, so what it
## does not carry (a sprite, a cache) and who else holds it stay.
class_name SnapCodec
extends RefCounted

const SKIP := {"@skip": 1}
## Classes a snapshot never carries (presentation).
const VIEW_CLASSES := [
	"View.Sprite", "View.GroundMark", "View.WallMark", "PlayerVoice", "Sound", "HUD", "QuietSound"
]
## Fields of a class a snapshot leaves out: worked out from others (Enemy
## alive, z), presentation (a player's voice and gun sway), wiring, or what
## the level makes the same on every machine and never changes (a feature's
## tuning, its lookups over the level's walls).
const SKIP_FIELDS := {
	"Enemy": ["alive", "z"],
	"Player": ["voice", "weapon_lag", "weapon_turn", "weapon_pose"],
	"Weapons.Armory": ["boxes", "drawn", "leaving"],
	"wall_breaks": ["by_cell", "win", "_faces", "_loose", "gaps"],
	"breakables": ["_feels", "_cfg", "_resting", "_resting_dirty", "_crack_seen"],
	# What the level makes the same everywhere (tuning, what each cell has to
	# burn), this machine's view of it (what it last put in step, the held
	# picture, the marks) and a furniture base each machine frees itself.
	"carry": ["_shown_version", "_cfg", "_specs", "_feels", "_brutes", "_bk"],
	# A thing's board is the level's own (the breakables' piece shares it):
	# put in step from the thing every tick, never carried twice.
	"carry.Thing": ["base", "board"],
	"fire":
	[
		"_cfg",
		"_fuel",
		"_catch",
		"_z",
		"_rain",
		"_lights",
		"_spills",
		"_at",
		"_seen",
		"_marks",
		"_crackle_at",
		"_barrels"
	],
	"stills": ["_cfg", "_images"],
	# The set pieces as the level makes them, and this machine's looks.
	"set_pieces":
	[
		"_specs",
		"shapes",
		"_ground",
		"trails",
		"_boxes",
		"_tile",
		"_sprites",
		"_draw_plan",
		"_drawn_version",
		"mark_cache",
		"_hiss_at",
		"_to_shut",
		"ray_d",
		"ray_hit"
	],
	"vehicles": ["_looks", "_dice"],
	"vehicle_runs": ["defs"],
	# A shut boss arena: what this machine put on its own world.
	"boss_lock": ["_applied", "_solid", "_clear", "_held", "_gates", "_edge", "_ground", "_kinds"],
	# A boss arena's wreck: its steps and their bosses (the level makes them
	# the same everywhere), the lamps it took (sprites, to put back), when the
	# next water ring shows, how a flung prop moves; the gear's feels.
	"arena_wreck": ["steps", "foes", "_taken", "_ring_next", "_fly_feel"],
	"boss_gear": ["_feels"],
	# A hound's walking body (put in step from him each move) and the numbers.
	"hound": ["_body", "_n"],
	"events": ["_body", "_n"],
	# The arena lights this machine's player is near (looks: each machine its own).
	"boss_arena": ["_lights", "_light_used"],
	# How bodies move (set in attach, the same everywhere; a body names its own).
	"corpses": ["_feel", "_slick", "_flung"],
	# The hazard props of the level (worked out the same everywhere).
	"brawl": ["_spots", "_spots_of"],
	# Looks kept in a simulation feature: the specks' own dice (how many a
	# hit throws hangs on the specks already about, which are never carried)
	# and when HEADSHOT! was last called (this machine's callouts).
	"critters": ["speck_dice"],
	"hit_reads": ["speck_dice", "_call_at"],
	# When a hat, a gun or a bit came down and how it was turned: only how
	# the 3D view settles it (each machine its own).
	"hit_reads.Bit": ["landed", "spin0"],
	"breakables.Bit": ["landed", "spin0"],
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
## Value types passed through as they are (no objects inside them, nothing
## shared: packed arrays are not here, being shared by reference, so encode()
## and decode() copy them; a snapshot never changes as the game goes on, and a
## game never shares an array with a snapshot).
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
}
const DEPTH := 14
## Tables (table()): kept on a feature under this meta; a column's form on the
## wire by its field's type (COL_FIELDS, untyped: an Array of encoded values).
const TABLE_META := &"_net_table"
const COL_ANY := 0
const COL_BOOL := 3
const COL_FIELDS := [TYPE_NIL, TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_VECTOR2]
const COL_TYPES := [
	TYPE_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY,
]
const COL_MAKE := [
	"[]",
	"PackedFloat64Array()",
	"PackedInt64Array()",
	"PackedByteArray()",
	"PackedStringArray()",
	"PackedVector2Array()",
]
const TABLER_WARNINGS := (
	'"untyped_declaration", "unsafe_property_access", "unsafe_method_access",'
	+ ' "unsafe_call_argument"'
)

var game: Game
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
## Per script: a packer() for all its carried fields (null: read one by one).
static var _packs := {}
## Scripts made to read many fields at once, by the fields' names (null: one
## could not be made, so they are read one by one).
static var _packers := {}
## The classes always carried by value (inner classes but a level's doors,
## stations and scenery and the renderer's marks): encoded without the tests
## for what a snapshot names instead.
static var _value_keys := {}
## Fewer fields than this are read one by one.
const PACK_FROM := 8
static var _made := {}
## Per script: the table reader and writer (_tabler, null: none) and its
## columns' forms.
static var _tablers := {}
## Per script: the writer of all its carried fields (_putter, null: none).
static var _putters := {}
## Per script: the reader of all its carried fields into a row (_rower, null:
## none) and the fields it must look at again.
static var _rowers := {}
## Per script: its carried field names as an Array (to hold a row's keys to).
static var _name_lists := {}
static var _row_fix := {}
## Off: every snapshot encodes the guarded lists again (net_check holds the
## kept ones against it: something changed one without bumping net_version).
static var keep_tables := true
static var _table_kinds := {}


func _init(p_game: Game) -> void:
	game = p_game
	if _by_key.is_empty():
		_register_all()
	for e: Enemy in game.enemies:
		iids[e.get_instance_id()] = e.uid


# ------------------------------------------------------------------ encode


func encode(value: Variant, depth := 0) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			var o: Object = value
			return _encode_object(o, depth)
		TYPE_ARRAY:
			var list: Array = value
			var out: Array = []
			out.resize(list.size())
			for i in list.size():
				var v: Variant = list[i]
				out[i] = v if PLAIN.has(typeof(v)) else encode(v, depth + 1)
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var plain := true
			for key: Variant in dict:
				if typeof(key) == TYPE_OBJECT or (typeof(key) == TYPE_INT and iids.has(key)):
					plain = false
					break
			if plain:
				var out := {}
				for key: Variant in dict:
					var v: Variant = dict[key]
					out[key] = v if PLAIN.has(typeof(v)) else encode(v, depth + 1)
				return out
			var rows: Array = []
			for key: Variant in dict:
				rows.append([encode(key, depth + 1), encode(dict[key], depth + 1)])
			return {"@D": rows}
		TYPE_INT:
			if iids.has(value):
				return {"@iid": iids[value]}
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return SKIP
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return packed_copy(value)
	return value


## A deep copy of plain data with every array untyped (a save document holds
## the game's own arrays: a snapshot must not change as the game goes on).
static func plain(value: Variant) -> Variant:
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return packed_copy(value)
	if value is Array:
		var list: Array = value
		var out: Array = []
		out.resize(list.size())
		for i in list.size():
			out[i] = plain(list[i])
		return out
	if value is Dictionary:
		var dict: Dictionary = value
		var out := {}
		for key: Variant in dict:
			out[key] = plain(dict[key])
		return out
	return value


## A copy of a packed array (each kind is shared by reference).
static func packed_copy(value: Variant) -> Variant:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY:
			var a: PackedByteArray = value
			return a.duplicate()
		TYPE_PACKED_INT32_ARRAY:
			var a: PackedInt32Array = value
			return a.duplicate()
		TYPE_PACKED_INT64_ARRAY:
			var a: PackedInt64Array = value
			return a.duplicate()
		TYPE_PACKED_FLOAT32_ARRAY:
			var a: PackedFloat32Array = value
			return a.duplicate()
		TYPE_PACKED_FLOAT64_ARRAY:
			var a: PackedFloat64Array = value
			return a.duplicate()
		TYPE_PACKED_STRING_ARRAY:
			var a: PackedStringArray = value
			return a.duplicate()
		TYPE_PACKED_VECTOR2_ARRAY:
			var a: PackedVector2Array = value
			return a.duplicate()
		TYPE_PACKED_VECTOR3_ARRAY:
			var a: PackedVector3Array = value
			return a.duplicate()
		TYPE_PACKED_COLOR_ARRAY:
			var a: PackedColorArray = value
			return a.duplicate()
		TYPE_PACKED_VECTOR4_ARRAY:
			var a: PackedVector4Array = value
			return a.duplicate()
	return value


## Every carried field of `o` (a player, an enemy...) as plain values.
func encode_fields(o: Object) -> Dictionary:
	var script: Script = o.get_script()
	return _fields_of_object(o, script, fields_of(o, class_key(script)), 1)


## o's carried fields `names`, each encoded at `depth` (most are plain: no
## call for them), read in one call where a packer can be made.
func _fields_of_object(
	o: Object, script: Script, names: PackedStringArray, depth: int
) -> Dictionary:
	var rower := _rower(o, script)
	if rower != null:
		# Every field read into one dictionary in one call; then only those
		# whose type may need encoding looked at again.
		var row: Dictionary = rower.call("row", o)
		for i: int in _row_fix[script]:
			var name := names[i]
			var v: Variant = row[name]
			if not PLAIN.has(typeof(v)):
				row[name] = encode(v, depth)
		return row
	var fields := {}
	var pack: GDScript = _packs.get(script)
	if pack != null:
		var vals: Array = []
		pack.call("pack", o, vals)
		for i in names.size():
			var v: Variant = vals[i]
			fields[names[i]] = v if PLAIN.has(typeof(v)) else encode(v, depth)
		return fields
	var snames: Array[StringName] = _snames[script]
	for i in names.size():
		var v: Variant = o.get(snames[i])
		fields[names[i]] = v if PLAIN.has(typeof(v)) else encode(v, depth)
	return fields


## A script whose pack(o, into) appends o's fields `names` to `into` in one
## call: reading them as written member accesses is about twice as fast as
## Object.get() name by name. Made once per list of names; null for a short
## list or when it cannot be made.
static func packer(names: Array[StringName]) -> GDScript:
	if names.size() < PACK_FROM:
		return null
	var key := ",".join(names)
	if _packers.has(key):
		return _packers[key]
	var reads := PackedStringArray()
	for name: StringName in names:
		reads.append("o." + String(name))
	var script := GDScript.new()
	# It reads whatever fields the class has, by name: the project's typing
	# warnings (errors here) stay off inside it.
	script.source_code = (
		(
			'@warning_ignore_start("untyped_declaration", "unsafe_property_access")\n'
			+ "extends RefCounted\n\n\nstatic func pack(o: Object, into: Array) -> void:\n"
			+ "\tinto.append_array([%s])\n"
		)
		% ", ".join(reads)
	)
	var made: GDScript = script if script.reload() == OK else null
	_packers[key] = made
	return made


## A flow field: where it was measured from and when next, whether its first
## walk is done, and the steps of the cells its last walk reached (every
## other cell is FAR: flow_field.gd keeps it so).
static func encode_flow(f: FlowField) -> Dictionary:
	var at := f._touched
	var most := 0
	for cell in at:
		most = maxi(most, f.steps[cell])
	var steps: Variant = null
	if most < 255:
		var narrow := PackedByteArray()
		narrow.resize(at.size())
		steps = narrow
	else:
		var wide := PackedInt32Array()
		wide.resize(at.size())
		steps = wide
	for i in at.size():
		steps[i] = f.steps[at[i]]
	return {"@flow": [f.origin.x, f.origin.y, f.next_at, f._walked, at.duplicate(), steps]}


## Puts an encode_flow() back: the steps it carries, FAR elsewhere, and no walk
## left half done (the scratch field a walk fills is all FAR, as update()
## leaves it before every walk).
static func decode_flow(f: FlowField, row: Array) -> void:
	f.origin = Vector2i(_int(row[0]), _int(row[1]))
	f.next_at = row[2]
	f._walked = row[3]
	var cells: PackedInt32Array = row[4]
	var at: PackedInt32Array = cells.duplicate()
	var steps: Variant = row[5]
	f.steps.fill(FlowField.FAR)
	for i in at.size():
		f.steps[at[i]] = steps[i]
	f._touched = at
	f._next.fill(FlowField.FAR)
	f._next_touched = PackedInt32Array()
	f._queue = PackedInt32Array()
	f._head = 0


func _encode_object(o: Object, depth: int) -> Variant:
	if o == null:
		return null
	var script: Script = o.get_script()
	if script != null and depth <= DEPTH:
		var value_key: Variant = _value_keys.get(script)
		if value_key != null:
			var carried: String = value_key
			fields_of(o, carried)
			var names: PackedStringArray = _fields[script]
			return {"@o": value_key, "f": _fields_of_object(o, script, names, depth + 1)}
	if o is Player:
		return {"@p": (o as Player).slot}
	if o is Enemy:
		return {"@e": (o as Enemy).uid}
	if o == game:
		return {"@game": 1}
	if o is GameFeature:
		return {"@feature": (o as GameFeature).id()}
	if o is LevelData:
		return {"@world": 1}
	if o is LevelData.Door:
		return {"@door": game.world.doors.find(o)}
	if o is LevelData.Station:
		return {"@station": game.world.stations.find(o)}
	if o is LevelData.Scenery:
		return {"@scenery": game.world.scenery.find(o)}
	if o is RandomNumberGenerator:
		var dice := o as RandomNumberGenerator
		return {"@rng": [dice.seed, dice.state]}
	if o is FlowField:
		return encode_flow(o as FlowField)
	if o is View.Sprite or o is View.GroundMark or o is View.WallMark:
		return SKIP
	if script == null or not (o is RefCounted) or depth > DEPTH:
		return SKIP
	var key := class_key(script)
	if key == "":
		var names: Array = []
		for prop: Dictionary in o.get_property_list():
			var usage: int = prop["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and names.size() < 4:
				names.append(prop["name"])
		unknown["an object with " + ", ".join(names)] = true
		return SKIP
	if VIEW_CLASSES.has(key):
		return SKIP
	return {"@o": key, "f": _fields_of_object(o, script, fields_of(o, key), depth + 1)}


# ------------------------------------------------------------------ decode


## The live value for `value`, filling `existing` in place where it can.
func decode(value: Variant, existing: Variant = null) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			var list: Array = value
			var out: Array = []
			out.resize(list.size())
			var old: Array = existing if existing is Array else []
			for i in list.size():
				out[i] = decode(list[i], old[i] if i < old.size() else null)
			if existing is Array:
				old.assign(out)
				return existing
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			return _decode_dictionary(dict, existing)
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return packed_copy(value)
	return value


func _decode_dictionary(value: Dictionary, existing: Variant) -> Variant:
	if value.has("@skip"):
		return existing
	if value.has("@p"):
		var slot := _int(value["@p"])
		return game.players[slot] if slot < game.players.size() else null
	if value.has("@e"):
		return by_uid.get(_int(value["@e"]))
	if value.has("@iid"):
		var e: Enemy = by_uid.get(_int(value["@iid"]))
		return e.get_instance_id() if e != null else 0
	if value.has("@game"):
		return game
	if value.has("@feature"):
		return game.features.get(str(value["@feature"]))
	if value.has("@world"):
		return game.world
	if value.has("@door"):
		return _at(game.world.doors, _int(value["@door"]))
	if value.has("@station"):
		return _at(game.world.stations, _int(value["@station"]))
	if value.has("@scenery"):
		return _at(game.world.scenery, _int(value["@scenery"]))
	if value.has("@rng"):
		var rng: RandomNumberGenerator = (
			existing if existing is RandomNumberGenerator else RandomNumberGenerator.new()
		)
		rng.seed = _int(value["@rng"][0])
		rng.state = _int(value["@rng"][1])
		return rng
	if value.has("@o"):
		var fields: Dictionary = value["f"]
		return _decode_object(str(value["@o"]), fields, existing)
	if value.has("@T"):
		var table_row: Array = value["@T"]
		return _decode_table(table_row, existing)
	if value.has("@flow"):
		# Only ever onto the flow field already there (it needs its level).
		if existing is FlowField:
			var flow: FlowField = existing
			var row: Array = value["@flow"]
			decode_flow(flow, row)
		return existing
	var into: Dictionary = existing if existing is Dictionary else {}
	var old := into.duplicate()
	into.clear()
	if value.has("@D"):
		for row: Array in value["@D"]:
			var key: Variant = decode(row[0])
			into[key] = decode(row[1], old.get(key))
		return into
	for key: Variant in value:
		into[key] = decode(value[key], old.get(key))
	return into


func _decode_object(key: String, fields: Dictionary, existing: Variant) -> Variant:
	var script: GDScript = _by_key.get(key)
	if script == null:
		unknown[key] = true
		return existing
	var o: Object = existing if existing is Object else null
	if o == null or o.get_script() != script:
		o = _make(script)
		if o == null:
			unknown[key + " (cannot be made)"] = true
			return existing
	for name: String in fields:
		set_field(o, name, fields[name])
	return o


## Every carried field of `o` from `row` (encode_fields()' form, perhaps with
## "@"-keys besides): the values decoded against what `o` holds, then written
## in one call (a script made per class, _putter: member writes about twice
## as fast as Object.set() name by name). False when `row` does not hold
## exactly those fields (nothing is set then).
func put_fields(o: Object, row: Dictionary) -> bool:
	var script: Script = o.get_script()
	var names: PackedStringArray = fields_of(o, class_key(script))
	var putter := _putter(script)
	var pack: GDScript = _packs.get(script)
	if putter == null or pack == null:
		return false
	var n := names.size()
	var now: Array = []
	var keys: Array = row.keys()
	if keys.size() >= n and _rower(o, script) != null:
		# The row's keys are the fields in order (an enemy's "@id" after them):
		# its values as they stand, only the fields whose type may need
		# decoding looked at.
		keys.resize(n)
		if keys == _name_lists[script]:
			var in_order: Array = row.values()
			in_order.resize(n)
			for i: int in _row_fix[script]:
				var w: Variant = in_order[i]
				if typeof(w) >= TYPE_DICTIONARY:
					if now.is_empty():
						pack.call("pack", o, now)
					in_order[i] = decode(w, now[i])
			putter.call("put", o, in_order)
			return true
	var vals: Array = []
	vals.resize(n)
	for i in n:
		var name := names[i]
		if not row.has(name):
			return false
		var v: Variant = row[name]
		if typeof(v) >= TYPE_DICTIONARY:
			if now.is_empty():
				pack.call("pack", o, now)
			v = decode(v, now[i])
		vals[i] = v
	putter.call("put", o, vals)
	return true


## A script whose row(o) is o's carried fields as a dictionary (the order of
## fields_of), made from its class's field list; _row_fix[script] the indices
## of the fields whose declared type is not always plain (untyped, int,
## objects, arrays...). Null (none) for a short list.
static func _rower(o: Object, script: Script) -> GDScript:
	if _rowers.has(script):
		return _rowers[script]
	var names: PackedStringArray = _fields.get(script, PackedStringArray())
	var made: GDScript = null
	if names.size() >= PACK_FROM:
		var types := {}
		for prop: Dictionary in o.get_property_list():
			var usage: int = prop["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				types[str(prop["name"])] = prop["type"]
		var fix := PackedInt32Array()
		var pairs := PackedStringArray()
		for i in names.size():
			pairs.append('"%s": o.%s' % [names[i], names[i]])
			var t: int = types.get(names[i], TYPE_NIL)
			if not PLAIN.has(t) or t == TYPE_NIL:
				fix.append(i)
		var source := (
			"@warning_ignore_start(%s)\n" % TABLER_WARNINGS
			+ "extends RefCounted\n\n\nstatic func row(o: Object) -> Dictionary:\n"
			+ "\treturn {%s}\n" % ", ".join(pairs)
		)
		made = GDScript.new()
		made.source_code = source
		if made.reload() != OK:
			made = null
		_row_fix[script] = fix
	_rowers[script] = made
	return made


## A script whose put(o, values) writes `script`'s carried fields in order.
static func _putter(script: Script) -> GDScript:
	if _putters.has(script):
		return _putters[script]
	var names: PackedStringArray = _fields.get(script, PackedStringArray())
	var made: GDScript = null
	if not names.is_empty():
		var writes := PackedStringArray()
		for i in names.size():
			writes.append("\to.%s = v[%d]\n" % [names[i], i])
		var source := (
			"@warning_ignore_start(%s)\n" % TABLER_WARNINGS
			+ "extends RefCounted\n\n\nstatic func put(o: Object, v: Array) -> void:\n"
			+ "".join(writes)
		)
		made = GDScript.new()
		made.source_code = source
		if made.reload() != OK:
			made = null
	_putters[script] = made
	return made


## Sets one field of `o` from its snapshot value (in place for an array, a
## dictionary or an object of the same class).
func set_field(o: Object, name: String, value: Variant) -> void:
	var now: Variant = o.get(name)
	var made: Variant = decode(value, now)
	if (typeof(now) == TYPE_ARRAY or typeof(now) == TYPE_DICTIONARY) and is_same(made, now):
		return
	o.set(name, made)


static func _at(list: Array, i: int) -> Variant:
	return list[i] if i >= 0 and i < list.size() else null


## A new object of `script` when its _init needs no arguments, else null.
static func _make(script: GDScript) -> Object:
	if not _made.has(script):
		var ok := true
		for m: Dictionary in script.get_script_method_list():
			if m["name"] == "_init":
				var args: Array = m["args"]
				var defaults: Array = m["default_args"]
				ok = args.size() <= defaults.size()
				break
		_made[script] = ok
	return script.new() if _made[script] else null


# ------------------------------------------------------------------ tables


## A feature's NET_GUARDED field as a snapshot carries it: a list or a
## dictionary (plain keys) of objects of one class carried by value (a level's
## windows, fences, breakable pieces, things) is one table, the rest as
## encode() has it. Kept on the feature (a meta, never a script variable)
## until its net_version moves: anything that changes one of those objects
## bumps it (net_track.gd holds the same rule), so a snapshot of a level whose
## fences stand as they did costs nothing for them. Each call hands out its
## own outer dictionary (a caller may patch it in place).
func guarded(feature: Object, name: String) -> Variant:
	var version: Variant = feature.get("net_version")
	var kept: Dictionary = feature.get_meta(TABLE_META, {})
	var row: Array = kept.get(name, [])
	var enc: Variant = null
	if keep_tables and version != null and not row.is_empty() and row[0] == version:
		enc = row[1]
	else:
		enc = table(feature.get(name))
		if keep_tables and version != null:
			if kept.is_empty():
				feature.set_meta(TABLE_META, kept)
			kept[name] = [version, enc]
	if enc is Dictionary:
		var d: Dictionary = enc
		return d.duplicate()
	return enc


## Whether `value` (a snapshot's form of `feature`'s guarded field `name`) is
## what the feature holds now, as far as its kept table knows (false when it
## does not know): putting it on can be skipped.
static func guarded_same(feature: Object, name: String, value: Variant) -> bool:
	var kept: Dictionary = feature.get_meta(TABLE_META, {})
	var row: Array = kept.get(name, [])
	if not keep_tables or row.is_empty() or row[0] != feature.get("net_version"):
		return false
	var had: Variant = row[1]
	if had is Dictionary and value is Dictionary:
		var a: Dictionary = had
		var b: Dictionary = value
		if a.has("@T") and b.has("@T") and is_same(a["@T"], b["@T"]):
			return true
	return var_to_bytes(had) == var_to_bytes(value)


## After a snapshot was put on: the feature's guarded field `name` is `value`
## at the net_version it has now.
static func guarded_now(feature: Object, name: String, value: Variant) -> void:
	var kept: Dictionary = feature.get_meta(TABLE_META, {})
	if kept.is_empty():
		feature.set_meta(TABLE_META, kept)
	var keep: Variant = value
	if value is Dictionary:
		var d: Dictionary = value
		keep = d.duplicate()
	kept[name] = [feature.get("net_version"), keep]


## After a delta that left `feature`'s guarded field `name` alone was put
## on: what was kept at net_version `was` is what it holds at the new one.
static func guarded_moved(feature: Object, name: String, was: Variant) -> void:
	var kept: Dictionary = feature.get_meta(TABLE_META, {})
	var row: Array = kept.get(name, [])
	if not row.is_empty() and row[0] == was:
		row[0] = feature.get("net_version")


## `value` as a table: {"@T": [class, names, keys, columns]} for a list (keys
## null) or a dictionary of objects all of one class carried by value, each
## column a packed array where its field is typed (float, int, bool as bytes,
## String, Vector2), else an Array of encoded values. Anything else (empty, a
## mix, a key that is not plain) as encode() has it.
func table(value: Variant) -> Variant:
	var items: Array = []
	var keys: Variant = null
	if value is Dictionary:
		var dict: Dictionary = value
		var key_list: Array = dict.keys()
		for k: Variant in key_list:
			var t := typeof(k)
			if not PLAIN.has(t) and (t != TYPE_INT or iids.has(k)):
				return encode(value)
		keys = key_list
		items = dict.values()
	elif value is Array:
		items = value
	if items.is_empty() or typeof(items[0]) != TYPE_OBJECT or items[0] == null:
		return encode(value)
	var first: Object = items[0]
	var script: Script = first.get_script()
	var key: Variant = _value_keys.get(script)
	if key == null:
		return encode(value)
	var tabler := _tabler(first, str(key))
	if tabler == null:
		return encode(value)
	var cols: Array = tabler.call("take", items, script)
	if cols.is_empty():
		return encode(value)
	var kinds: PackedByteArray = _table_kinds[script]
	for j in kinds.size():
		if kinds[j] == COL_ANY:
			var col: Array = cols[j]
			for i in col.size():
				var v: Variant = col[i]
				if not PLAIN.has(typeof(v)):
					col[i] = encode(v, 2)
	return {"@T": [key, _fields[script], keys, cols]}


func _decode_table(row: Array, existing: Variant) -> Variant:
	var key := str(row[0])
	var names: PackedStringArray = row[1]
	var keys: Variant = row[2]
	var cols: Array = row[3]
	var script: GDScript = _by_key.get(key)
	if script == null:
		unknown[key] = true
		return existing
	var key_list: Array = keys if keys is Array else []
	var n := key_list.size()
	if not (keys is Array) and not cols.is_empty():
		n = len(cols[0])
	var old_list: Array = existing if existing is Array and not (keys is Array) else []
	var old_dict: Dictionary = existing if existing is Dictionary and keys is Array else {}
	var items: Array = []
	items.resize(n)
	for i in n:
		var o: Variant = null
		if keys is Array:
			o = old_dict.get(key_list[i])
		elif i < old_list.size():
			o = old_list[i]
		var obj: Object = o if typeof(o) == TYPE_OBJECT else null
		if obj == null or obj.get_script() != script:
			obj = _make(script)
			if obj == null:
				unknown[key + " (cannot be made)"] = true
				return existing
		items[i] = obj
	var tabler: GDScript = null
	if n > 0:
		var first: Object = items[0]
		tabler = _tabler(first, key)
	var kinds: PackedByteArray = _table_kinds.get(script, PackedByteArray())
	var fast: bool = tabler != null and names == _fields[script] and cols.size() == names.size()
	for j in kinds.size():
		if fast and kinds[j] != COL_ANY and COL_TYPES[kinds[j]] != typeof(cols[j]):
			fast = false
	if fast:
		tabler.call("put", items, cols)
	for j in mini(names.size(), cols.size()):
		if fast and kinds[j] != COL_ANY:
			continue
		var col: Variant = cols[j]
		var bytes := typeof(col) == TYPE_PACKED_BYTE_ARRAY
		for i in n:
			var obj: Object = items[i]
			var v: Variant = col[i]
			set_field(obj, names[j], (v != 0) if bytes else v)
	if keys is Array:
		var into: Dictionary = existing if existing is Dictionary else {}
		if into.keys() != key_list:
			into.clear()
			for i in n:
				into[key_list[i]] = items[i]
		return into
	if existing is Array:
		old_list.assign(items)
		return existing
	return items


## A script whose take(items, script) reads every carried field of each item
## (all of them `script`'s objects, else []) into columns, and put(items,
## columns) writes the typed columns back (the Array columns are the
## caller's), for the class of `o` (`key`); null when one cannot be made.
static func _tabler(o: Object, key: String) -> GDScript:
	var script: Script = o.get_script()
	if _tablers.has(script):
		return _tablers[script]
	var names: PackedStringArray = fields_of(o, key)
	var types := {}
	for prop: Dictionary in o.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			types[str(prop["name"])] = prop["type"]
	var kinds := PackedByteArray()
	var make := PackedStringArray()
	var takes := PackedStringArray()
	var puts := PackedStringArray()
	var reads := PackedStringArray()
	var cols := PackedStringArray()
	for j in names.size():
		var name := names[j]
		var t: int = types.get(name, TYPE_NIL)
		var kind := COL_FIELDS.find(t)
		if kind < 0:
			kind = COL_ANY
		kinds.append(kind)
		cols.append("c%d" % j)
		make.append("\tvar c%d := %s\n\tc%d.resize(n)\n" % [j, COL_MAKE[kind], j])
		if kind == COL_BOOL:
			takes.append("\t\tc%d[i] = 1 if o.%s else 0\n" % [j, name])
			puts.append("\t\to.%s = c%d[i] != 0\n" % [name, j])
		else:
			takes.append("\t\tc%d[i] = o.%s\n" % [j, name])
			if kind != COL_ANY:
				puts.append("\t\to.%s = c%d[i]\n" % [name, j])
		if kind != COL_ANY:
			var packed_type: String = COL_MAKE[kind]
			reads.append("\tvar c%d: %s = cols[%d]\n" % [j, packed_type.trim_suffix("()"), j])
	var source := (
		"@warning_ignore_start(%s)\n" % TABLER_WARNINGS
		+ "extends RefCounted\n\n\nstatic func take(items: Array, s: Script) -> Array:\n"
		+ "\tvar n := items.size()\n"
		+ "".join(make)
		+ "\tfor i in n:\n\t\tvar o = items[i]\n"
		+ "\t\tif typeof(o) != TYPE_OBJECT or o == null or o.get_script() != s:\n"
		+ "\t\t\treturn []\n"
		+ "".join(takes)
		+ "\treturn [%s]\n\n\n" % ", ".join(cols)
		+ "static func put(items: Array, cols: Array) -> void:\n"
		+ "".join(reads)
		+ "\tfor i in items.size():\n\t\tvar o = items[i]\n"
		+ "".join(puts)
		+ "\t\tpass\n"
	)
	var made := GDScript.new()
	made.source_code = source
	var tabler: GDScript = made if made.reload() == OK else null
	_tablers[script] = tabler
	_table_kinds[script] = kinds
	return tabler


# --------------------------------------------------------------- classes


## The name a snapshot gives `script`'s objects ("" when it has none).
static func class_key(script: Script) -> String:
	if _by_key.is_empty():
		_register_all()
	return str(_by_script.get(script, ""))


## The fields of `o` a snapshot carries: its script variables, less SKIP_FIELDS.
static func fields_of(o: Object, key: String) -> PackedStringArray:
	var script: Script = o.get_script()
	if _fields.has(script):
		return _fields[script]
	var skip: Array = SKIP_FIELDS.get(key, [])
	var only: Array = ONLY_FIELDS.get(key, [])
	var names := PackedStringArray()
	for prop: Dictionary in o.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := str(prop["name"])
		if not skip.has(name) and (only.is_empty() or only.has(name)):
			names.append(name)
	_fields[script] = names
	_name_lists[script] = Array(names)
	var snames := names_of(names)
	_snames[script] = snames
	_packs[script] = packer(snames)
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
		"View": View,
		"Tumble": Tumble,
		"PlayerVoice": PlayerVoice,
		"Sound": Sound,
		"HUD": HUD,
		"VehicleDrive": VehicleDrive,
	}
	for script: GDScript in Features.ALL:
		roots[script.resource_path.get_file().get_basename()] = script
	# Every root under its own name first, then what each holds: a feature's
	# inner classes are named by its file (wall_breaks.Fence) even when another
	# root reaches that script through a preload first (SKIP_FIELDS and
	# ONLY_FIELDS name them so; before snapshot version 3 some were named by
	# that path, so their lists never applied and a feature reached that way
	# was carried by value).
	for key: String in roots:
		var root: Script = roots[key]
		if not _by_script.has(root):
			_by_script[root] = key
			_by_key[key] = root
	for key: String in roots:
		var root: Script = roots[key]
		_register(key, root)
	var named := [
		"LevelData.Door",
		"LevelData.Station",
		"LevelData.Scenery",
		"View.Sprite",
		"View.GroundMark",
		"View.WallMark",
	]
	for script: Script in _by_script:
		var key: String = _by_script[script]
		if key.contains(".") and not named.has(key) and not VIEW_CLASSES.has(key):
			_value_keys[script] = key


static func _register(key: String, script: Script) -> void:
	if _by_script.get(script, key) != key:
		return
	_by_script[script] = key
	_by_key[key] = script
	for name: String in script.get_script_constant_map():
		var inner: Variant = script.get_script_constant_map()[name]
		if inner is GDScript and not _by_script.has(inner):
			var inner_script: GDScript = inner
			_register(key + "." + name, inner_script)


## int() of a value read from data or a dictionary, typed (the same
## result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v
