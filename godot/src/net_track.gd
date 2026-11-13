## What changed in a game since the last look, field by field: the host's way
## to its deltas (game_host.gd) without capturing and comparing whole
## snapshots. It keeps every carried field's last value (plain values as they
## are, arrays and dictionaries as their bytes, objects by identity, with a
## watch over each object a snapshot carries by value: a mind, a gun rack, a
## shot) and changes() compares them all once, bit for bit (a float's sign
## of zero too), encoding only what changed.
##
##   var track := NetTrack.new(game)    # the baseline: the game now
##   ... game.tick() ...
##   var d := track.changes()           # since the baseline or the last call
##   # patch(capture at the last look, d) == capture now (GameSnapshot)
##
## The form is GameSnapshot.delta's: a section or row changed carries only its
## changed fields; an object carried by value whose fields changed carries
## {"f": {those fields}}; a new player or enemy, an object replaced, an array
## or dictionary changed carries its whole value ({"@new": value} for a
## dictionary); enemies gone are listed under "@gone". Never "@order": enemies
## that change places (not only join at the end or go) send the section whole.
class_name NetTrack
extends RefCounted


## The fields of one object being watched and their last values.
class Watch:
	var obj: Object
	var names: PackedStringArray
	var snames: Array[StringName] = []
	var vals: Array = []
	## Per field: a Watch over an object carried by value, an Array of them for
	## the objects inside an array or dictionary, or null.
	var kids: Array = []
	## How deep the codec encodes this object's fields (its depth limit).
	var depth := 0
	## Carried whole when anything in it changes (a flow field, a native
	## random number generator), not as {"f": ...}.
	var whole := false
	## The bytes of its cold fields and what is inside them at the last look.
	var sum := PackedByteArray()
	## No kids: its fields are all there is.
	var leaf := true
	## The fields compared one by one every look (HOT), by index, a byte each
	## for whether a field is one; the rest, and their names.
	var hot := PackedInt32Array()
	var hot_mask := PackedByteArray()
	var cold := PackedInt32Array()
	var cold_names: Array[StringName] = []
	## A feature's NET_GUARDED fields (by index), looked through only when its
	## net_version (the field at `guard`) moved since `guard_seen`.
	var guarded := PackedInt32Array()
	var guard := -1
	var guard_seen = null
	## Reads the cold fields (or, for a kid, every field) in one call: a script
	## made for the class (_packer), null to read them one by one.
	var packer: GDScript = null
	var all_packer: GDScript = null


## The fields of a class that change nearly every look (measured over every
## chapter's bot play): compared one by one, the rest only when their bytes
## together changed. Only a matter of speed: any field may change at any time.
const HOT := {
	"Game": ["clock", "rng", "spawn_grace", "shots", "next_uid", "hazards"],
	"Enemy":
	[
		"pose",
		"cooldown",
		"see_time",
		"angle",
		"last_stride",
		"gait",
		"x",
		"y",
		"hunted_until",
		"timer",
		"patrol_pause",
		"hunted",
		"toss",
		"target",
		"hunt_until",
		"flinch"
	],
	"Player":
	[
		"x",
		"y",
		"angle",
		"vx",
		"vy",
		"bob",
		"walk_phase",
		"eye",
		"motion",
		"vertical_speed",
		"air",
		"armory",
		"pitch",
		"step_number",
		"flow",
		"sway",
		"drift",
		"flow_due"
	],
	"Weapons.Armory": ["shot_age", "cooldown", "recoil", "reload", "flash"],
}

## Value types with floats in them, whose == does not see a sign of zero.
const FLOATY := {
	TYPE_VECTOR2: true,
	TYPE_RECT2: true,
	TYPE_VECTOR3: true,
	TYPE_TRANSFORM2D: true,
	TYPE_VECTOR4: true,
	TYPE_PLANE: true,
	TYPE_QUATERNION: true,
	TYPE_AABB: true,
	TYPE_BASIS: true,
	TYPE_TRANSFORM3D: true,
	TYPE_PROJECTION: true,
	TYPE_COLOR: true,
}

var game
var codec: SnapCodec
var _game: Watch
var _players := {}
var _enemies := {}
var _order: Array = []
var _features := {}
var _doors := PackedByteArray()
var _panes := PackedByteArray()
var _facts := {}
var _statics := PackedByteArray()
## How many fields the last changes() looked at and found changed (a bench's
## numbers).
var looked := 0
var changed := 0


func _init(p_game) -> void:
	game = p_game
	reset()


## Takes the game as it is now as the baseline.
func reset() -> void:
	game.name_new()
	codec = SnapCodec.new(game)
	_game = _watch(game, PackedStringArray(GameSnapshot.SIM_FIELDS), 0, "Game")
	_players.clear()
	for p: Player in game.players:
		_players[str(p.slot)] = _watch(p, SnapCodec.fields_of(p, "Player"), 1, "Player")
	_enemies.clear()
	_order.clear()
	for e: Enemy in game.enemies:
		_order.append(e.uid)
		_enemies[str(e.uid)] = _watch(e, SnapCodec.fields_of(e, "Enemy"), 1, "Enemy")
	_features.clear()
	for id: String in GameSnapshot.SIM_FEATURES:
		var feature = game.features.get(id)
		if feature != null:
			_features[id] = _watch(feature, _feature_names(feature, id), 0, id)
	var world := GameSnapshot.world_of(game)
	_doors = var_to_bytes(world["doors"])
	_panes = var_to_bytes(world["panes"])
	_facts.clear()
	for id: String in GameSnapshot.FACT_FEATURES:
		var feature = game.features.get(id)
		if feature != null:
			_facts[id] = var_to_bytes(SnapCodec.plain(feature.save()))
	_statics = var_to_bytes(GameSnapshot.statics_of(codec))


static func _feature_names(feature, id: String) -> PackedStringArray:
	var names := PackedStringArray()
	for name: String in SnapCodec.fields_of(feature, id):
		if name != "game":
			names.append(name)
	return names


## Everything that changed since the baseline or the last call, as a delta
## (empty when nothing did); the baseline moves to now.
func changes() -> Dictionary:
	game.name_new()
	codec = SnapCodec.new(game)
	looked = 0
	changed = 0
	var out := {}
	var fields := _diff(_game)
	if not fields.is_empty():
		out["game"] = fields
	var players := {}
	for p: Player in game.players:
		var key := str(p.slot)
		var w: Watch = _players.get(key)
		if w == null or w.obj != p:
			_players[key] = _watch(p, SnapCodec.fields_of(p, "Player"), 1, "Player")
			players[key] = {"@new": codec.encode_fields(p)}
			continue
		var row := _diff(w)
		if not row.is_empty():
			players[key] = row
	if not players.is_empty():
		out["players"] = players
	_enemies_changes(out)
	var features := {}
	for id: String in _features:
		var row := _diff(_features[id])
		if not row.is_empty():
			features[id] = row
	if not features.is_empty():
		out["features"] = features
	_world_changes(out, features)
	var statics := var_to_bytes(GameSnapshot.statics_of(codec))
	if statics != _statics:
		_statics = statics
		out["statics"] = {"derby": {"@new": GameSnapshot.statics_of(codec)["derby"]}}
	return out


func _enemies_changes(out: Dictionary) -> void:
	var order: Array = []
	var rows := {}
	var fresh: Array = []
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		order.append(e.uid)
		var key := str(e.uid)
		var w: Watch = _enemies.get(key)
		if w == null or w.obj != e:
			_enemies[key] = _watch(e, SnapCodec.fields_of(e, "Enemy"), 1, "Enemy")
			rows[key] = {"@new": GameSnapshot.enemy_row(game, codec, i)}
			fresh.append(e.uid)
			continue
		var row := _diff(w)
		if not row.is_empty():
			rows[key] = row
	if order == _order:
		if not rows.is_empty():
			out["enemies"] = rows
		return
	# Who went, and whether the rest kept their places with the new at the end.
	var now := {}
	for uid in order:
		now[uid] = true
	var gone: Array = []
	var kept: Array = []
	for uid in _order:
		if now.has(uid):
			kept.append(uid)
		else:
			gone.append(str(uid))
			_enemies.erase(str(uid))
	_order = order
	out["order"] = order.duplicate()
	if kept + fresh != order:
		# Places changed: the section whole.
		var all := {}
		for i in game.enemies.size():
			all[str(game.enemies[i].uid)] = GameSnapshot.enemy_row(game, codec, i)
		out["enemies"] = {"@new": all}
		return
	if not gone.is_empty():
		rows["@gone"] = gone
	if not rows.is_empty():
		out["enemies"] = rows


## The level's doors and panes, and what a breaking feature broke (asked only
## when that feature changed).
func _world_changes(out: Dictionary, features: Dictionary) -> void:
	var world := GameSnapshot.world_of(game)
	var change := {}
	var doors := var_to_bytes(world["doors"])
	if doors != _doors:
		_doors = doors
		change["doors"] = world["doors"]
	var panes := var_to_bytes(world["panes"])
	if panes != _panes:
		_panes = panes
		change["panes"] = world["panes"]
	if not change.is_empty():
		out["world"] = change
	var facts := {}
	for id: String in _facts:
		if not features.has(id):
			continue
		var doc = SnapCodec.plain(game.features[id].save())
		var bytes := var_to_bytes(doc)
		if bytes != _facts[id]:
			_facts[id] = bytes
			facts[id] = {"@new": doc}
	if not facts.is_empty():
		out["facts"] = facts


# ---------------------------------------------------------------- watching


## A watch over `o`'s fields `names` (`key`: its class in a snapshot, for its
## HOT fields), their values now as the baseline.
func _watch(o: Object, names: PackedStringArray, depth: int, key := "", whole := false) -> Watch:
	var w := Watch.new()
	w.obj = o
	w.names = names
	w.snames = SnapCodec.names_of(names)
	w.depth = depth
	w.whole = whole
	w.vals.resize(names.size())
	w.kids.resize(names.size())
	w.hot_mask.resize(names.size())
	var hot: Array = HOT.get(key, [])
	var guarded: Array = []
	if o is GameFeature and o.get_script().get_script_constant_map().has("NET_GUARDED"):
		guarded = o.get_script().get_script_constant_map()["NET_GUARDED"]
		w.guard = names.find("net_version")
		w.guard_seen = o.get("net_version")
	for i in names.size():
		var v = o.get(w.snames[i])
		w.vals[i] = _kept(v)
		if not whole:
			w.kids[i] = _kids_of(v, depth)
			if w.kids[i] != null:
				w.leaf = false
		if guarded.has(names[i]) and w.guard >= 0:
			w.guarded.append(i)
			w.hot_mask[i] = 2
		elif hot.has(names[i]) and not whole:
			w.hot.append(i)
			w.hot_mask[i] = 1
		else:
			w.cold.append(i)
			w.cold_names.append(w.snames[i])
	if not whole:
		w.packer = SnapCodec.packer(w.cold_names)
		w.all_packer = SnapCodec.packer(w.snames)
		var now: Array = []
		_gather(w, now)
		w.sum = var_to_bytes(now)
	return w


## What is kept of a value to compare against: arrays and dictionaries as
## their bytes (objects in them by identity), anything else as it is.
static func _kept(v):
	var t := typeof(v)
	if t == TYPE_ARRAY or t == TYPE_DICTIONARY:
		return var_to_bytes(v)
	if t >= TYPE_PACKED_BYTE_ARRAY:
		# Shared by reference: a copy, or it would change with the game.
		return v.duplicate()
	return v


## The values of `w`'s cold fields, then of every field of each watch inside
## them (all of theirs, hot or cold), in one array.
static func _gather(w: Watch, into: Array) -> void:
	var o := w.obj
	if w.packer != null:
		w.packer.pack(o, into)
	else:
		for name: StringName in w.cold_names:
			into.append(o.get(name))
	if w.leaf:
		return
	for i in w.kids.size():
		var kid = w.kids[i]
		if kid == null or w.hot_mask[i]:
			continue
		if kid is Watch:
			_gather_all(kid, into)
			continue
		for each: Watch in kid:
			_gather_all(each, into)


static func _gather_all(w: Watch, into: Array) -> void:
	var o := w.obj
	if w.all_packer != null:
		w.all_packer.pack(o, into)
	else:
		for name: StringName in w.snames:
			into.append(o.get(name))
	if w.leaf:
		return
	for kid in w.kids:
		if kid == null:
			continue
		if kid is Watch:
			_gather_all(kid, into)
			continue
		for each: Watch in kid:
			_gather_all(each, into)


## The watches inside a value: over an object the codec carries by value, or
## over each such object inside an array or dictionary (null: none).
func _kids_of(v, depth: int):
	var t := typeof(v)
	if t == TYPE_OBJECT:
		return _object_watch(v, depth + 1)
	if t != TYPE_ARRAY and t != TYPE_DICTIONARY:
		return null
	var found: Array = []
	_collect(v, found, depth + 1, 0)
	return found if not found.is_empty() else null


func _collect(v, found: Array, depth: int, level: int) -> void:
	if level > SnapCodec.DEPTH:
		return
	var items: Array = v if v is Array else v.values()
	for item in items:
		var t := typeof(item)
		if t == TYPE_OBJECT:
			var w = _object_watch(item, depth + 1)
			if w != null:
				found.append(w)
		elif t == TYPE_ARRAY or t == TYPE_DICTIONARY:
			_collect(item, found, depth + 1, level + 1)


## A watch over an object the codec carries by value (its fields, at `depth`),
## or null for one it names (a player, an enemy, a door...) or never carries.
func _object_watch(o, depth: int):
	if o == null or not is_instance_valid(o):
		return null
	if o is Player or o is Enemy or o == game or o is GameFeature or o is LevelData:
		return null
	if o is LevelData.Door or o is LevelData.Station or o is LevelData.Scenery:
		return null
	if o is RandomNumberGenerator:
		return _watch(o, PackedStringArray(["seed", "state"]), depth, "", true)
	if o is FlowField:
		var names := PackedStringArray(["origin", "next_at", "_walked", "_touched", "steps"])
		return _watch(o, names, depth, "", true)
	var script = o.get_script()
	if script == null or not (o is RefCounted) or depth > SnapCodec.DEPTH:
		return null
	var key := SnapCodec.class_key(script)
	if key == "" or SnapCodec.VIEW_CLASSES.has(key):
		return null
	return _watch(o, SnapCodec.fields_of(o, key), depth, key)


## The changed fields of `w` (moving its baseline to now), encoded as a
## snapshot carries them: plain values as they are, the rest through the codec.
## The hot fields (and what is inside them) are compared one by one; the
## rest, and everything inside the objects they hold, only when their bytes
## together changed. (A kid list rebuilt makes the next look's bytes differ
## once: that look finds nothing more.)
func _diff(w: Watch) -> Dictionary:
	if w.whole:
		return _diff_whole(w)
	looked += 1
	var out := {}
	var obj := w.obj
	var vals := w.vals
	var snames := w.snames
	for i in w.hot:
		var v = obj.get(snames[i])
		var old = vals[i]
		if typeof(v) == TYPE_FLOAT:
			if typeof(old) == TYPE_FLOAT and v == old and (v != 0.0 or 1.0 / v == 1.0 / old):
				continue
		elif is_same(v, old) and typeof(v) != TYPE_OBJECT and not FLOATY.has(typeof(v)):
			continue
		_field(w, i, v, out)
	var now: Array = []
	_gather(w, now)
	var sum := var_to_bytes(now)
	if sum != w.sum:
		w.sum = sum
		var cold := w.cold
		for k in cold.size():
			_field(w, cold[k], now[k], out)
	if w.guard >= 0:
		var version = obj.get(snames[w.guard])
		if version != w.guard_seen:
			w.guard_seen = version
			for i in w.guarded:
				_field(w, i, obj.get(snames[i]), out)
	changed += out.size()
	return out


## Field i of `w`, whose value now is `v`: into `out` when it changed.
func _field(w: Watch, i: int, v, out: Dictionary) -> void:
	var old = w.vals[i]
	var t := typeof(v)
	if is_same(v, old):
		if t == TYPE_FLOAT:
			# The same but for a sign of zero?
			if v != 0.0 or 1.0 / v == 1.0 / old:
				return
		elif t == TYPE_OBJECT:
			var kid = w.kids[i]
			if kid == null:
				return
			var inner := _diff(kid)
			if not inner.is_empty():
				out[w.names[i]] = {"@new": codec.encode(v, w.depth)} if kid.whole else {"f": inner}
			return
		elif FLOATY.has(t):
			if var_to_bytes(v) == var_to_bytes(old):
				return
		else:
			return
		w.vals[i] = v
		out[w.names[i]] = v
	elif t == TYPE_ARRAY or t == TYPE_DICTIONARY:
		var bytes := var_to_bytes(v)
		var moved: bool = typeof(old) != TYPE_PACKED_BYTE_ARRAY or bytes != old
		if not moved and w.kids[i] != null:
			for kid: Watch in w.kids[i]:
				# Every kid looked at (each moves its own baseline).
				if not _diff(kid).is_empty():
					moved = true
		if not moved:
			return
		w.vals[i] = bytes
		w.kids[i] = _kids_of(v, w.depth)
		_relevel(w)
		var enc = codec.encode(v, w.depth)
		out[w.names[i]] = {"@new": enc} if enc is Dictionary else enc
	elif typeof(old) == t and t >= TYPE_PACKED_BYTE_ARRAY and _same_packed(v, old):
		return
	else:
		w.vals[i] = _kept(v)
		if t == TYPE_OBJECT or typeof(old) == TYPE_OBJECT:
			w.kids[i] = _kids_of(v, w.depth) if t == TYPE_OBJECT else null
			_relevel(w)
		if t == TYPE_OBJECT or t == TYPE_INT:
			var enc = codec.encode(v, w.depth)
			out[w.names[i]] = {"@new": enc} if enc is Dictionary else enc
		else:
			out[w.names[i]] = _kept(v) if t >= TYPE_PACKED_BYTE_ARRAY else v


## Whether `w` has no kids now (after one changed).
static func _relevel(w: Watch) -> void:
	w.leaf = true
	for kid in w.kids:
		if kid != null:
			w.leaf = false
			return


## A flow field or a native random number generator: compared field by
## field, exactly (packed arrays by value), carried whole when one changed.
func _diff_whole(w: Watch) -> Dictionary:
	var out := {}
	looked += 1
	for i in w.names.size():
		var v = w.obj.get(w.snames[i])
		var old = w.vals[i]
		if typeof(v) == typeof(old) and v == old:
			if typeof(v) != TYPE_FLOAT or v != 0.0 or 1.0 / v == 1.0 / old:
				continue
		w.vals[i] = _kept(v)
		out[w.names[i]] = true
	return out


## Packed arrays: by value (float ones bit for bit).
static func _same_packed(a, b) -> bool:
	if a != b:
		return false
	var t := typeof(a)
	if (
		t == TYPE_PACKED_FLOAT32_ARRAY
		or t == TYPE_PACKED_FLOAT64_ARRAY
		or t >= TYPE_PACKED_VECTOR2_ARRAY
	):
		return var_to_bytes(a) == var_to_bytes(b)
	return true
