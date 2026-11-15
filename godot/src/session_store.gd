## Port of session_store.py: versioned checkpoints, named save slots, options,
## chapter unlocks and the Crossroads road notes.
##
## The port keeps the same document layout (version 4) and the same defensive
## validation, but writes into Godot's own ``user://`` folder so the Python
## build's profile is never touched. The RNG is the port's LCG, so ``rng`` is a
## single integer here instead of Python's Mersenne state.
class_name SessionStore
extends RefCounted

## The save format. A change to what a save holds bumps VERSION and adds a
## step to save_upgrade.gd that turns a save of the version before into this
## one, so every save back to OLDEST_VERSION still loads. tools/save_fixtures.gd
## keeps real saves of each version (tools/saves/) and checks they still do.
const VERSION := 8
const OLDEST_VERSION := 4
const SLOT := "hickston-quick.json"
const SETTINGS_FILE := "options.json"
const UNLOCKS_FILE := "campaign-unlocks.json"
const ENTRY_FILE := "campaign-entry.json"
const ROAD_NOTES_FILE := "county-road-notes.json"
const MANUAL_SLOTS := 4
const LABEL_LENGTH := 24
const MAX_BYTES := 600_000

const GAME_FIELDS := [
	"clock",
	"inventory_slot",
	"kills",
	"secrets",
	"face_until",
	"message_until",
	"face",
	"notice",
	"hurt_flash",
	"blast_flash",
	"sprint",
	"step_number",
	"next_belch",
	"map",
	"district",
	"district_until",
	"amb_clock",
	"jukebox_on",
	"flush_until",
	"won",
	"radio_check",
	"wall_sound",
	"legacy_completed",
	"legacy_key_route"
]
const ARM_FIELDS := [
	"active",
	"owned",
	"loaded",
	"reserve",
	"cooldown",
	"reload",
	"recoil",
	"flash",
	"switch",
	"empty",
	"shot_age",
	"last_spent",
	"holstered",
	"lower",
	"rifle_heat",
	"grinding",
	"swing_hit",
	"fuse",
	"tnt_latched"
]
const DOOR_FIELDS := ["progress", "opened", "discovered"]
const PLAYER_FIELDS := [
	"x",
	"y",
	"angle",
	"health",
	"gut",
	"drunk",
	"pitch",
	"eye",
	"bob",
	"sway",
	"drift",
	"walk_phase",
	"motion",
	"air",
	"vertical_speed",
	"jump_held",
	"vx",
	"vy",
	"crouched",
	"floor_z"
]
const ENEMY_FIELDS := [
	"kind",
	"x",
	"y",
	"timer",
	"pose",
	"stun",
	"alerted",
	"cooldown",
	"angle",
	"hp",
	"explosive",
	"gait",
	"face_left",
	"dormant",
	"windup",
	"attacks",
	"target",
	"floor_z"
]
const AI_FIELDS := [
	"route_slot", "patrol_pause", "recovery", "chase_turn", "see_time", "player_seen", "last_stride"
]
const COMBAT_FIELDS := ["pressure_guard", "volley", "volley_timer", "volley_angle", "volley_slope"]

const SHOT_KINDS := [
	"bolt",
	"blade",
	"arm_bolt",
	"plasma",
	"football",
	"tnt",
	"barker_bolt",
	"lantern_bolt",
	"bottle_rocket",
	"chalk_lob",
	"rudy_horn",
	"foreman_cut",
	"deputy_slug",
	"fair_bottle",
	"chain_hook",
	"valve_slug",
	"bowling",
	"keg",
	"cow",
	"milk"
]
const SPECK_KINDS := [
	"spark", "plasma", "feather", "gore", "dust", "glass", "splash", "chips", "powder", "soil"
]


## Mirrors session_store.Setting.
class Setting:
	var label := ""
	var key := ""
	var default_value := 0
	var low := 0
	var high := 0
	var step := 1
	var choices: Array = []
	var hint := ""

	func _init(
		p_label: String,
		p_key: String,
		p_default: int,
		p_low: int,
		p_high: int,
		p_step := 1,
		p_choices: Array = [],
		p_hint := ""
	) -> void:
		label = p_label
		key = p_key
		default_value = p_default
		low = p_low
		high = p_high
		step = p_step
		choices = p_choices
		hint = p_hint

	func format_value(value: int) -> String:
		if not choices.is_empty():
			return str(choices[clampi(value - low, 0, choices.size() - 1)])
		return "%d%%" % value

	func adjust(value: int, direction: int) -> int:
		if not choices.is_empty():
			return low + posmod(value - low + direction, choices.size())
		return clampi(value + direction * step, low, high)


## A control's key (the KEYS page): shown by name, changed by pressing a new
## key (main_input.gd), never stepped.
class KeySetting:
	extends Setting

	var action := ""

	func _init(p_action: String, p_label: String, p_default: int) -> void:
		super(
			p_label,
			KeyBindings.option_key(p_action),
			p_default,
			0,
			0x7FFFFFFF,
			1,
			[],
			"THE KEY FOR %s IN PLAY. RESET PAGE PUTS EVERY KEY BACK." % p_label
		)
		action = p_action

	func format_value(value: int) -> String:
		return KeyBindings.key_name(value)

	func adjust(value: int, _direction: int) -> int:
		return value


static var _pages: Array = []
static var _options: Array = []
static var _defaults := {}
## Diagnostic for the last failed restore (probes and bug reports only).
static var last_error := ""


static func _fail() -> Variant:
	return null


static func _fail_at(line: int) -> Variant:
	last_error = "line %d: %s" % [line, last_error]
	return null


static func _note(reason: String) -> Variant:
	last_error = reason
	return null


static func choices(
	label: String, key: String, default_value: int, values: Array, hint: String
) -> Setting:
	return Setting.new(label, key, default_value, 0, values.size() - 1, 1, values, hint)


static func toggle(label: String, key: String, default_value: int, hint: String) -> Setting:
	return choices(label, key, default_value, ["OFF", "ON"], hint)


static func setup_pages() -> Array:
	if _pages.is_empty():
		_pages = SetupPages.build()
		for page: Array in _pages:
			for item: Setting in page[1]:
				_options.append(item)
				_defaults[item.key] = item.default_value
	return _pages


static func options_list() -> Array:
	setup_pages()
	return _options


static func defaults() -> Dictionary:
	setup_pages()
	return _defaults


# ------------------------------------------------------------------ folders


## Writable profile folder. Godot's own user:// keeps this well clear of the
## Python build's %APPDATA%/CrazyLegsMundellRampage profile.
static func data_directory() -> String:
	return "user://"


static func _path(name: String) -> String:
	return data_directory().path_join(name)


## Save helpers accept "" to mean "the default profile file", like the Python
## build's optional `path=None` arguments.
static func _resolve(path: String, name: String) -> String:
	return path if path != "" else _path(name)


# -------------------------------------------------------------- serialising


static func _selected(obj: Object, keys: Array) -> Dictionary:
	var out := {}
	for key: String in keys:
		out[key] = obj.get(key)
	return out


static func snapshot(game: Game) -> Dictionary:
	var doors := {}
	for door: LevelData.Door in game.world.doors:
		doors[_door_key(door)] = _selected(door, DOOR_FIELDS)
	var enemies := {}
	var ai := {}
	var reactions := {}
	for i in game.enemy_ids.size():
		var key := str(game.enemy_ids[i])
		var enemy: Enemy = game.enemies[i]
		enemies[key] = _selected(enemy, ENEMY_FIELDS)
		var row := _selected(enemy, AI_FIELDS + COMBAT_FIELDS)
		row["aim"] = enemy.aim_mark
		ai[key] = row
		if enemy.heard != null or enemy.retreat != null or enemy.responded:
			reactions[key] = [enemy.heard, enemy.retreat, enemy.responded]
	var shots: Array = []
	for shot: Game.Shot in game.shots:
		shots.append(
			{
				"x": shot.x,
				"y": shot.y,
				"z": shot.z,
				"vx": shot.vx,
				"vy": shot.vy,
				"vz": shot.vz,
				"kind": shot.kind,
				"life": shot.life,
				"enemy": shot.enemy,
				"damage": shot.damage,
				"bounces": shot.bounces,
				"travelled": shot.travelled,
				"resting": shot.resting
			}
		)
	var specks: Array = []
	for speck: Game.Speck in game.specks:
		specks.append(
			{
				"x": speck.x,
				"y": speck.y,
				"z": speck.z,
				"vx": speck.vx,
				"vy": speck.vy,
				"vz": speck.vz,
				"life": speck.life,
				"kind": speck.kind
			}
		)
	var blasts: Array = []
	for blast: Game.Blast in game.blasts:
		blasts.append(
			{"x": blast.x, "y": blast.y, "z": blast.z, "age": blast.age, "kind": blast.kind}
		)
	var hazards: Array = []
	for hazard: Game.Hazard in game.hazards:
		hazards.append(
			{
				"kind": hazard.kind,
				"x": hazard.x,
				"y": hazard.y,
				"radius": hazard.radius,
				"warning": hazard.warning,
				"life": hazard.life,
				"damage": hazard.damage,
				"age": hazard.age,
				"next_hit": hazard.next_hit
			}
		)
	var drums: Array = []
	for point: Vector2 in game.drums:
		drums.append([point.x, point.y, _int(game.drums[point])])
	var visited: Array = []
	for cell: Vector2i in game.visited:
		visited.append([cell.x, cell.y])
	var panes: Array = []
	for cell: Vector2i in game.world.broken_panes:
		panes.append([cell.x, cell.y])
	return {
		"version": VERSION,
		"level": game.level.id,
		"layout": game.level.layout,
		"game": _selected(game, GAME_FIELDS),
		"player": _selected(game.player, PLAYER_FIELDS),
		"armory": _selected(game.armory, ARM_FIELDS),
		"doors": doors,
		"enemies": enemies,
		"ai": ai,
		"campaign": {"history": game.history, "entry": game.entry, "replay": game.replay},
		"county_gallery": bool(game.gallery != null and game.gallery.rewarded),
		"county_supplies": game.supply_rule,
		"county_reactions": reactions,
		"music": game.music_bookmark,
		"stations": _sorted_keys(game.stations_done),
		"features": Features.save_all(game),
		"tasks": _sorted_keys(game.task_items),
		"valve_turns": game.valve_turns.duplicate(),
		"scenery": _sorted_keys(game.scenery_spent),
		"heard": _sorted_keys(game.heard_exchanges),
		"shots": shots,
		"specks": specks,
		"blasts": blasts,
		"hazards": hazards,
		"inventory": game.inventory.duplicate(),
		"keys": _sorted_keys(game.keys),
		"drums": drums,
		"pickups": _pickup_rows(game),
		"visited": visited,
		"panes": panes,
		"rng": game.rng.get_state(),
	}


## The pickups as a save keeps them: [name, x, y] (the stable id each has in
## play is handed out again when they load), and the floor one lies on when it
## is a deck (level format 2).
static func _pickup_rows(game: Game) -> Array:
	var rows: Array = []
	for entry: Array in game.pickups:
		var row: Array = [entry[0], entry[1], entry[2]]
		rows.append(row)
		if entry.size() > 4:
			row.append(entry[4])
	return rows


static func _door_key(door: LevelData.Door) -> String:
	if door.id != "":
		return door.id
	return "%d,%d" % [door.x, door.y]


static func _sorted_keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return keys


# ------------------------------------------------------------------- files


static func _write_atomic(path: String, text: String) -> bool:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		push_error("checkpoint too large: " + path)
		return false
	var global := ProjectSettings.globalize_path(path)
	var folder := global.get_base_dir()
	DirAccess.make_dir_recursive_absolute(folder)
	var temporary := global + ".tmp"
	var handle := FileAccess.open(temporary, FileAccess.WRITE)
	if handle == null:
		push_error("cannot write " + temporary)
		return false
	handle.store_string(text)
	handle.close()
	if FileAccess.file_exists(global):
		DirAccess.remove_absolute(global)
	if DirAccess.rename_absolute(temporary, global) != OK:
		push_error("cannot replace " + global)
		return false
	return true


static func save(game: Game, path: String, manual: Variant = null) -> bool:
	var doc := snapshot(game)
	if not game.retained.is_empty():
		var retained := {}
		for key: Variant in game.retained:
			var chapter: Variant = game.retained[key]
			if chapter is Game:
				var chapter_game: Game = chapter
				retained[str(key)] = snapshot(chapter_game)
		if not retained.is_empty():
			doc["retained"] = retained
	if manual is Dictionary:
		doc["manual"] = manual
	return _write_atomic(path, JSON.stringify(doc, "", false))


## The Python build documents its exact float formatting; the port only has to
## read its own files, so plain JSON floats are fine.


static func slot_directory(replay_level: Variant = null) -> String:
	var root := _path("save-slots")
	if replay_level == null or str(replay_level) == "":
		return root.path_join("campaign")
	return root.path_join("replay").path_join(str(replay_level))


static func slot_label(text: String) -> String:
	var allowed := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _.-'"
	var out := ""
	for ch in text.to_upper():
		if allowed.contains(ch):
			out += ch
	return out.substr(0, LABEL_LENGTH)


static func _sha256(raw: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return context.finish().hex_encode()


## Returns [fingerprint, meta] exactly like the Python helper; an empty
## fingerprint means "unreadable or incompatible", null meta means "empty".
static func slot_metadata(path: String, replay_level: Variant = null) -> Array:
	if not FileAccess.file_exists(path):
		return [null, null]
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > MAX_BYTES:
		return ["", null]
	var fingerprint := _sha256(raw)
	var doc := _upgraded(JSON.parse_string(raw.get_string_from_utf8()))
	if doc.is_empty():
		return ["", null]
	if not Campaign.ORDER.has(str(doc.get("level", ""))):
		return ["", null]
	var campaign: Dictionary = doc.get("campaign", {})
	# The menu passes "" for the campaign's own slots; Python tests truthiness,
	# so None and "" both mean "not a replay".
	var replaying := replay_level != null and str(replay_level) != ""
	if _bool(campaign.get("replay", false)) != replaying:
		return ["", null]
	if replaying and str(doc["level"]) != str(replay_level):
		return ["", null]
	var meta: Variant = doc.get("manual")
	if not (meta is Dictionary):
		return ["", null]
	var manual: Dictionary = meta
	var name := str(manual.get("label", ""))
	if name != slot_label(name).strip_edges() or name == "":
		return ["", null]
	var goal := str(manual.get("objective", ""))
	var stamp := str(manual.get("timestamp", ""))
	if goal.length() > 100 or stamp.length() > 32:
		return ["", null]
	return [fingerprint, [name, str(doc["level"]), goal, stamp.replace("T", " ").substr(0, 16)]]


## SaveUpgrade.upgrade() of a parsed file, {} where it gives null (it gives
## null for anything but a dictionary, and a save is never an empty one).
static func _upgraded(parsed: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return {}
	var parsed_doc: Dictionary = parsed
	var doc: Variant = SaveUpgrade.upgrade(parsed_doc)
	if doc == null:
		return {}
	return doc


static func save_named(game: Game, path: String, name: String, fingerprint: Variant) -> bool:
	var clean := slot_label(name).strip_edges()
	if clean == "" or (fingerprint is String and str(fingerprint) == ""):
		return false
	# Python passes None for "this slot was empty when the menu read it".
	var exists := FileAccess.file_exists(path)
	if exists:
		if (
			not (fingerprint is String)
			or _sha256(FileAccess.get_file_as_bytes(path)) != str(fingerprint)
		):
			return false
	elif fingerprint != null:
		return false
	var stamp := _local_iso_stamp()
	return save(
		game,
		path,
		{"label": clean, "objective": game.objective().substr(0, 100), "timestamp": stamp}
	)


## Python writes ``datetime.now().astimezone().isoformat(timespec="seconds")``.
static func _local_iso_stamp() -> String:
	var utc := Time.get_datetime_dict_from_system(true)
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var tz := Time.get_datetime_dict_from_unix_time(
		Time.get_unix_time_from_datetime_dict(utc) + bias * 60
	)
	var sign := "+" if bias >= 0 else "-"
	var offset := absi(bias)
	return (
		"%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d"
		% [
			_int(tz["year"]),
			_int(tz["month"]),
			_int(tz["day"]),
			_int(tz["hour"]),
			_int(tz["minute"]),
			_int(tz["second"]),
			sign,
			offset / 60,
			offset % 60
		]
	)


static func settings(path := "") -> Dictionary:
	var target := path if path != "" else _path(SETTINGS_FILE)
	var values := {}
	if FileAccess.file_exists(target):
		var raw := FileAccess.get_file_as_bytes(target)
		if raw.size() > 4096:
			raw = raw.slice(0, 4096)
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			values = parsed
	if not values.has("window_mode") and _int(values.get("startup_fullscreen", 0)) == 1:
		values["window_mode"] = 1
	var out := {}
	for item: Setting in options_list():
		var value: Variant = values.get(item.key)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			out[item.key] = clampi(_int(value), item.low, item.high)
		else:
			out[item.key] = item.default_value
	return out


## Whether this profile has saved settings (false on a first run).
static func settings_saved() -> bool:
	return FileAccess.file_exists(_path(SETTINGS_FILE))


static func save_settings(path: String, values: Dictionary) -> bool:
	return _write_atomic(_resolve(path, SETTINGS_FILE), JSON.stringify(values, "", false))


static func unlocks(path := "") -> Dictionary:
	var target := path if path != "" else _path(UNLOCKS_FILE)
	var result := {"hickston": true}
	if FileAccess.file_exists(target):
		var raw := FileAccess.get_file_as_bytes(target)
		if raw.size() > 4096:
			raw = raw.slice(0, 4096)
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Array:
			var listed: Array = parsed
			for level_id: String in Campaign.ORDER.slice(1):
				if not listed.has(level_id):
					break
				result[level_id] = true
	return result


static func save_unlocks(path: String, unlocked: Dictionary) -> bool:
	var rows: Array = []
	for level_id: String in Campaign.ORDER:
		if unlocked.has(level_id):
			rows.append(level_id)
	return _write_atomic(_resolve(path, UNLOCKS_FILE), JSON.stringify(rows, "", false))


static func road_notes(path := "") -> Dictionary:
	var target := path if path != "" else _path(ROAD_NOTES_FILE)
	var out := {}
	if FileAccess.file_exists(target):
		var raw := FileAccess.get_file_as_bytes(target)
		if raw.size() > 1024:
			raw = raw.slice(0, 1024)
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Array:
			for key: Variant in parsed:
				if key == "ledger" or key == "survey":
					out[key] = true
	return out


static func save_notes(path: String, notes: Dictionary) -> bool:
	var keys: Array = notes.keys()
	keys.sort()
	return _write_atomic(_resolve(path, ROAD_NOTES_FILE), JSON.stringify(keys, "", false))


# ------------------------------------------------------------- validation


static func _number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(_float(value))
		and absf(_float(value)) <= 1e7
	)


## int(), float() and bool() of a value read from a file, which may hold
## anything: text reads as int() and float() read it; anything else converts
## as a typed variable converts it, which is how those constructors convert it.
static func _int(value: Variant) -> int:
	if value is String:
		var text: String = value
		return int(text)
	var out: int = value
	return out


static func _float(value: Variant) -> float:
	if value is String:
		var text: String = value
		return float(text)
	var out: float = value
	return out


static func _bool(value: Variant) -> bool:
	var out: bool = value
	return out


static func _assign(obj: Object, key: String, value: Variant) -> bool:
	var before: Variant = obj.get(key)
	if before == null:
		if value != null:
			var pair: Array = value if value is Array else []
			if not (value is Array and pair.size() == 2 and _number(pair[0]) and _number(pair[1])):
				return false
			obj.set(key, [_float(pair[0]), _float(pair[1])])
		return true
	match typeof(before):
		TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				return false
			obj.set(key, value)
		TYPE_STRING:
			if typeof(value) != TYPE_STRING or str(value).length() > 128:
				return false
			obj.set(key, value)
		TYPE_INT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not _number(value) or _float(value) != floor(_float(value)):
				return false
			obj.set(key, _int(value))
		TYPE_FLOAT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not _number(value):
				return false
			obj.set(key, _float(value))
		TYPE_ARRAY:
			# GDScript's typed arrays (Array[bool], Array[int]) reject obj.set()
			# with an untyped Array, so refill the existing array in place.
			var live: Array = before
			var items: Array = value if value is Array else []
			if not (value is Array) or items.size() != live.size():
				return false
			var want_bool := key == "owned"
			for item: Variant in items:
				if want_bool:
					if typeof(item) != TYPE_BOOL:
						return false
				else:
					if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
						return false
					if _float(item) != floor(_float(item)):
						return false
			live.clear()
			for item: Variant in items:
				live.append(item if want_bool else _int(item))
		_:
			return false
	return true


static func _restore_fields(obj: Object, values: Variant, keys: Array) -> bool:
	if not (values is Dictionary):
		last_error = "fields not a dictionary"
		return false
	var fields: Dictionary = values
	for key: String in keys:
		if not fields.has(key):
			last_error = "missing field " + key
			return false
		if not _assign(obj, key, fields[key]):
			last_error = (
				"bad field %s (%s=%s)"
				% [key, type_string(typeof(fields[key])), str(fields[key]).substr(0, 40)]
			)
			return false
	return true


static func _valid_position(world: LevelData, x: Variant, y: Variant) -> bool:
	return (
		_number(x)
		and _number(y)
		and _float(x) >= 0.0
		and _float(y) >= 0.0
		and _float(x) < float(world.width)
		and _float(y) < float(world.height)
	)


## How many a saved list holds, as its size() counts them.
static func _count(rows: Variant) -> int:
	if rows is Dictionary:
		var table: Dictionary = rows
		return table.size()
	var list: Array = rows
	return list.size()


static func _restore_list(rows: Variant, factory: Callable, kinds: Array, cap: int) -> Array:
	if not (rows is Array) or _count(rows) > cap:
		return []
	var out: Array = []
	for row: Variant in rows:
		if not (row is Dictionary):
			return []
		var fields: Dictionary = row
		if not kinds.has(str(fields.get("kind", ""))):
			return []
		var obj: Object = factory.call()
		for key: String in fields:
			if key == "kind":
				obj.set("kind", str(fields[key]))
			elif key == "enemy" or key == "resting":
				if typeof(fields[key]) != TYPE_BOOL:
					return []
				obj.set(key, fields[key])
			else:
				if typeof(fields[key]) != TYPE_INT and typeof(fields[key]) != TYPE_FLOAT:
					return []
				obj.set(key, _float(fields[key]))
		out.append(obj)
	return out


static func _validate_kit(kit: Variant) -> bool:
	if not (kit is Dictionary):
		return false
	var fields: Dictionary = kit
	var needed := ["health", "owned", "loaded", "reserve", "active", "inventory", "slot"]
	for key: String in needed:
		if not fields.has(key):
			return false
	var owned: Array = fields["owned"]
	var loaded: Array = fields["loaded"]
	var reserve: Array = fields["reserve"]
	# A save from before a gun was added has fewer: the rest start empty.
	if (
		owned.size() > Weapons.COUNT
		or owned.size() != loaded.size()
		or owned.size() != reserve.size()
		or owned.size() < 1
	):
		return false
	if typeof(fields["health"]) != TYPE_INT and typeof(fields["health"]) != TYPE_FLOAT:
		return false
	if not (_int(fields["health"]) >= 1 and _int(fields["health"]) <= 100):
		return false
	if not owned[0]:
		return false
	if not owned[_int(fields["active"])]:
		return false
	for i in owned.size():
		if _int(loaded[i]) < 0 or _int(loaded[i]) > Weapons.SAVED_CAPACITY[i]:
			return false
		if _int(reserve[i]) < 0 or _int(reserve[i]) > Weapons.MAX_RESERVE[i]:
			return false
	var inventory: Dictionary = fields["inventory"]
	if inventory.size() != HUD.ITEMS.size():
		return false
	for name: String in HUD.ITEMS:
		if not inventory.has(name):
			return false
		var amount := _int(inventory[name])
		if amount < 0 or amount > 5:
			return false
	return true


# ------------------------------------------------------------------- load


## Returns a restored Game or null (with a warning) when the file is unusable.
static func read(
	path: String,
	make_game: Callable,
	expected_replay: Variant = null,
	expected_level: Variant = null
) -> Game:
	if not FileAccess.file_exists(path):
		return _fail_at(646)
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > MAX_BYTES:
		push_warning("checkpoint too large")
		return _fail_at(650)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		push_warning("checkpoint is not an object")
		return _fail_at(654)
	var doc := _upgraded(parsed)
	if doc.is_empty():
		push_warning("unsupported checkpoint version")
		return _fail_at(657)
	var game := restore(doc, make_game, expected_replay)
	if game == null:
		return _fail_at(660)
	if (
		expected_level != null
		and str(expected_level) != ""
		and game.level.id != str(expected_level)
	):
		return _fail_at(662)
	var retained: Variant = doc.get("retained", {})
	if retained is Dictionary and not game.replay:
		var previous: Array = []
		var index := Campaign.ORDER.find(game.level.id)
		if index > 0:
			previous = Campaign.ORDER.slice(0, index)
		for key: Variant in retained:
			if not previous.has(str(key)):
				return _fail_at(671)
			var chapter_doc: Variant = retained[key]
			if not (chapter_doc is Dictionary):
				return _fail_at(674)
			var chapter_fields: Dictionary = chapter_doc
			if _int(chapter_fields.get("version", 0)) != VERSION:
				return _fail_at(676)  # upgrade() brought every chapter up to VERSION
			if str(chapter_fields.get("level", "")) != str(key):
				return _fail_at(678)
			var chapter := restore(chapter_fields, make_game, false)
			if chapter != null and chapter.layout_restarted:
				# A finished chapter whose level has been rebuilt since: it
				# stays finished, its new map cleared.
				var chapter_game: Dictionary = chapter_fields.get("game", {})
				var finished: Variant = chapter_game.get("won", false)
				chapter.won = finished is bool and finished
				for enemy: Enemy in chapter.enemies:
					if enemy.hostile:
						enemy.hp = 0.0
				chapter.kills = chapter.total_kills
			if chapter == null or not chapter.won:
				return _fail_at(681)
			game.retained[str(key)] = chapter
	return game


static func restore(doc: Dictionary, make_game: Callable, expected_replay: Variant = null) -> Game:
	var level_id := str(doc.get("level", ""))
	if not Campaign.ORDER.has(level_id):
		return _fail_at(689)
	var game: Game = make_game.call(level_id)
	if game == null or game.level.id != level_id:
		return _fail_at(692)
	if _int(doc.get("layout", 1)) != game.level.layout:
		return _restart(doc, game, expected_replay)
	return restore_onto(doc, game, expected_replay)


## restore() onto `game`, a Game just made for the save's level and layout
## (GameSnapshot.apply uses it): the game back, or null when the save is bad.
static func restore_onto(doc: Dictionary, game: Game, expected_replay: Variant = null) -> Game:
	var w := game.world
	if not _restore_fields(game, doc.get("game", {}), GAME_FIELDS):
		return _fail_at(695)
	var reward: Variant = doc.get("county_gallery", false)
	if typeof(reward) != TYPE_BOOL:
		return _fail_at(698)
	if game.gallery != null:
		game.gallery.rewarded = reward
	elif reward:
		return _fail_at(702)
	var supplies := _int(doc.get("county_supplies", 0))
	if supplies < 0 or supplies > 2:
		return _fail_at(705)
	game.supply_rule = supplies
	if not _restore_fields(game.player, doc.get("player", {}), PLAYER_FIELDS):
		return _fail_at(708)
	if not _restore_armory(game, doc):
		return null
	if game.clock < 0.0 or game.player.health <= 0 or game.player.health > 100:
		return _fail_at(712)
	if game.inventory_slot < 0 or game.inventory_slot >= HUD.ITEMS.size():
		return _fail_at(714)
	if not _valid_position(w, game.player.x, game.player.y):
		return _fail_at(716)
	if game.district < 0 or game.district >= game.level.districts.size():
		return _fail_at(718)
	# Kills can pass the level's own count: posse partners, a boss's backup and
	# Maw's crew join later (features/posse.gd counts them once they are back).
	if game.kills < 0 or game.kills > game.total_kills + 2000:
		return _fail_at(720)
	if game.secrets < 0 or game.secrets > game.total_secrets:
		return _fail_at(722)
	if not _check_armory(game):
		return null
	return _restore_rest(doc, game, expected_replay)


## The guns as saved: a save from before a gun existed has it empty.
static func _restore_armory(game: Game, doc: Dictionary) -> bool:
	var armory_doc: Variant = doc.get("armory", {})
	if armory_doc is Dictionary:
		var fields: Dictionary = armory_doc
		fields = fields.duplicate(true)
		armory_doc = fields
		for key: String in ["owned", "loaded", "reserve"]:
			var saved: Variant = fields.get(key)
			var list: Array = saved if saved is Array else []
			if saved is Array and list.size() < Weapons.COUNT:
				# Saved before a gun was added: the new ones start empty.
				for k in Weapons.COUNT - list.size():
					list.append(false if key == "owned" else 0)
	if not _restore_fields(game.armory, armory_doc, ARM_FIELDS):
		_fail_at(710)
		return false
	return true


static func _check_armory(game: Game) -> bool:
	if game.armory.active < 0 or game.armory.active >= Weapons.COUNT:
		_fail_at(724)
		return false
	if not game.armory.owned[game.armory.active]:
		_fail_at(726)
		return false
	for i in Weapons.COUNT:
		if game.armory.loaded[i] < 0 or game.armory.loaded[i] > Weapons.SAVED_CAPACITY[i]:
			_fail_at(729)
			return false
		if game.armory.reserve[i] < 0 or game.armory.reserve[i] > Weapons.MAX_RESERVE[i]:
			_fail_at(731)
			return false
	return true


## A save of a level that has been rebuilt since (its layout is older): the
## chapter starts over on the new map, with the guns, ammunition, health and
## pockets as saved and the campaign so far. Keys and the map's state go.
static func _restart(doc: Dictionary, game: Game, expected_replay: Variant) -> Game:
	var supplies := _int(doc.get("county_supplies", 0))
	if supplies < 0 or supplies > 2:
		return _fail_at(705)
	game.supply_rule = supplies
	var player_doc: Dictionary = doc.get("player", {})
	var health: Variant = player_doc.get("health")
	if not _number(health) or _int(health) <= 0 or _int(health) > 100:
		return _fail_at(712)
	game.player.health = _int(health)
	if not _restore_armory(game, doc) or not _check_armory(game):
		return null
	if not _restore_campaign(doc, game, expected_replay):
		return null
	if not _restore_inventory(doc, game):
		return null
	var game_doc: Dictionary = doc.get("game", {})
	var slot: Variant = game_doc.get("inventory_slot", 0)
	game.inventory_slot = clampi(_int(slot) if _number(slot) else 0, 0, HUD.ITEMS.size() - 1)
	game.music_bookmark = null
	game.layout_restarted = true
	game.message("%s HAS BEEN REBUILT. THE CHAPTER STARTS OVER." % game.level.title, 5.0)
	game.configure({})
	return game


static func _restore_campaign(doc: Dictionary, game: Game, expected_replay: Variant) -> bool:
	var campaign: Dictionary = doc.get("campaign", {})
	if typeof(campaign.get("replay", false)) != TYPE_BOOL:
		_fail_at(813)
		return false
	game.replay = campaign["replay"]
	if expected_replay != null and game.replay != _bool(expected_replay):
		_fail_at(816)
		return false
	if not _validate_kit(campaign.get("entry")):
		game.entry = _normalise_kit(campaign.get("entry"))
		if game.entry.is_empty():
			_fail_at(820)
			return false
	else:
		game.entry = _normalise_kit(campaign["entry"])
	var history: Variant = campaign.get("history", [])
	if not (history is Array):
		_fail_at(825)
		return false
	var expected_history := 0 if game.replay else Campaign.ORDER.find(game.level.id)
	if _count(history) != expected_history:
		_fail_at(828)
		return false
	var clean_history: Array = []
	for row: Variant in history:
		if not (row is Array) or _count(row) != 6:
			_fail_at(832)
			return false
		var clean: Array = [str(row[0])]
		for k in range(1, 6):
			clean.append(_int(row[k]))
		clean_history.append(clean)
	game.history = clean_history
	return true


static func _restore_inventory(doc: Dictionary, game: Game) -> bool:
	var inventory: Variant = doc.get("inventory", {})
	if not (inventory is Dictionary) or _count(inventory) != HUD.ITEMS.size():
		_fail_at(899)
		return false
	var items: Dictionary = inventory
	game.inventory = {}
	for name: String in HUD.ITEMS:
		if not items.has(name):
			_fail_at(903)
			return false
		var amount := _int(items[name])
		if amount < 0 or amount > 5:
			_fail_at(906)
			return false
		game.inventory[name] = amount
	return true


static func _restore_rest(doc: Dictionary, game: Game, expected_replay: Variant) -> Game:
	var w := game.world
	# doors
	var doors_doc: Variant = doc.get("doors", {})
	if not (doors_doc is Dictionary):
		return _fail_at(736)
	var expected_doors := {}
	for door: LevelData.Door in w.doors:
		expected_doors[_door_key(door)] = door
	# Doors or enemies that no longer match the level's: it was changed since
	# without a new layout number. The chapter starts over rather than the save
	# being lost.
	if _count(doors_doc) != expected_doors.size():
		return _restart(doc, game, expected_replay)
	for key: Variant in doors_doc:
		if not expected_doors.has(key):
			return _restart(doc, game, expected_replay)
		var door: LevelData.Door = expected_doors[key]
		if not _restore_fields(door, doors_doc[key], DOOR_FIELDS):
			return _fail_at(747)
		if door.progress < 0.0 or door.progress > 1.0:
			return _fail_at(749)

	# enemies
	var enemies_doc: Variant = doc.get("enemies", {})
	var ai_doc: Variant = doc.get("ai", {})
	if not (enemies_doc is Dictionary) or not (ai_doc is Dictionary):
		return _fail_at(755)
	var enemy_rows: Dictionary = enemies_doc
	var ai_rows: Dictionary = ai_doc
	# The level's own enemies (a bigger posse is the posse feature's to restore).
	var own := game.enemy_ids.size()
	if enemy_rows.size() != own or ai_rows.size() != own:
		return _restart(doc, game, expected_replay)
	var seen := {}
	for i in game.enemy_ids.size():
		var key := str(game.enemy_ids[i])
		var enemy: Enemy = game.enemies[i]
		if not enemy_rows.has(key) or not ai_rows.has(key):
			return _restart(doc, game, expected_replay)
		seen[key] = true
		if not _restore_fields(enemy, enemies_doc[key], ENEMY_FIELDS):
			return _fail_at(766)
		if not _valid_position(w, enemy.x, enemy.y):
			return _fail_at(768)
		var ai: Dictionary = ai_doc[key]
		if not _restore_fields(enemy, ai, AI_FIELDS + COMBAT_FIELDS):
			return _fail_at(771)
		if enemy.route_slot < 0 or enemy.route_slot >= maxi(1, enemy.route.size()):
			return _fail_at(773)
		if enemy.volley < 0 or enemy.volley > 5:
			return _fail_at(775)
		if enemy.pressure_guard < 0.0 or enemy.pressure_guard > 1.75:
			return _fail_at(777)
		var aim: Variant = ai.get("aim")
		if aim == null:
			enemy.aim_mark = null
		elif (
			aim is Array
			and _count(aim) == 3
			and _number(aim[0])
			and _number(aim[1])
			and _number(aim[2])
		):
			enemy.aim_mark = [_float(aim[0]), _float(aim[1]), _float(aim[2])]
		else:
			return _fail_at(784)
		if enemy.windup > 0.0 and enemy.aim_mark == null:
			return _fail_at(786)
	if seen.size() != game.enemy_ids.size():
		return _fail_at(788)

	# reactions
	var reactions: Variant = doc.get("county_reactions", {})
	if not (reactions is Dictionary):
		return _fail_at(793)
	for key: Variant in reactions:
		var index := game.enemy_ids.find(str(key))
		if index < 0:
			return _fail_at(797)
		var row: Variant = reactions[key]
		if not (row is Array) or _count(row) != 3 or typeof(row[2]) != TYPE_BOOL:
			return _fail_at(800)
		var enemy: Enemy = game.enemies[index]
		enemy.heard = _state(row[0], 4, w, game.clock)
		if row[0] != null and enemy.heard == null:
			return _fail_at(804)
		enemy.retreat = _state(row[1], 3, w, game.clock)
		if row[1] != null and enemy.retreat == null:
			return _fail_at(807)
		enemy.responded = row[2]
		if enemy.heard != null and enemy.heard[2] > enemy.heard[3]:
			return _fail_at(808)
		if enemy.retreat != null and not enemy.responded:
			return _fail_at(809)

	# campaign
	if not _restore_campaign(doc, game, expected_replay):
		return null

	# The features (src/features/) each take back their own state, or start
	# afresh when the save has none for them.
	var saved_features: Variant = doc.get("features", {})
	# (restore_all takes anything but a dictionary as {})
	var features_doc: Dictionary = saved_features if saved_features is Dictionary else {}
	Features.restore_all(game, features_doc)

	# task state
	var stations: Variant = doc.get("stations", [])
	if not (stations is Array):
		return _fail_at(842)
	game.stations_done = {}
	for name: Variant in stations:
		if typeof(name) != TYPE_STRING:
			return _fail_at(846)
		game.stations_done[str(name)] = true
	var known_stations := {}
	for station: LevelData.Station in w.stations:
		known_stations[station.id] = true
	for name: Variant in game.stations_done:
		if not known_stations.has(name):
			return _fail_at(849)
	for station: LevelData.Station in w.stations:
		if game.stations_done.has(station.id):
			for required: Variant in station.requires:
				if not game.stations_done.has(str(required)):
					return _fail_at(852)
			# A finished station keeps its sectors lit after a load, as it does
			# in the reference (session_store.py re-applies the +0.26).
			game.set_station_lights(station)
	var tasks: Variant = doc.get("tasks", [])
	var scenery: Variant = doc.get("scenery", [])
	var heard: Variant = doc.get("heard", [])
	for row: Variant in [tasks, scenery, heard]:
		if not (row is Array):
			return _fail_at(858)
	game.task_items = {}
	for name: Variant in tasks:
		game.task_items[str(name)] = true
	game.scenery_spent = {}
	for name: Variant in scenery:
		game.scenery_spent[str(name)] = true
	game.heard_exchanges = {}
	for name: Variant in heard:
		game.heard_exchanges[str(name)] = true
	var turns: Variant = doc.get("valve_turns", {})
	if not (turns is Dictionary):
		return _fail_at(870)
	game.valve_turns = {}
	for key: Variant in turns:
		game.valve_turns[str(key)] = _int(turns[key])

	# entities
	var shot_rows: Variant = doc.get("shots", [])
	var speck_rows: Variant = doc.get("specks", [])
	var blast_rows: Variant = doc.get("blasts", [])
	var hazard_rows: Variant = doc.get("hazards", [])
	game.shots = _restore_list(
		shot_rows, func() -> Game.Shot: return Game.Shot.new(), SHOT_KINDS, 240
	)
	if game.shots.size() != _count(shot_rows):
		return _fail_at(882)
	game.specks = _restore_list(
		speck_rows, func() -> Game.Speck: return Game.Speck.new(), SPECK_KINDS, 4000
	)
	if game.specks.size() != _count(speck_rows):
		return _fail_at(885)
	game.blasts = _restore_list(
		blast_rows, func() -> Game.Blast: return Game.Blast.new(), ["energy", "fire"], 80
	)
	if game.blasts.size() != _count(blast_rows):
		return _fail_at(888)
	game.hazards = _restore_list(
		hazard_rows, func() -> Game.Hazard: return Game.Hazard.new(), ["steam", "chalk"], 7
	)
	if game.hazards.size() != _count(hazard_rows):
		return _fail_at(891)
	for shot: Game.Shot in game.shots:
		if not _valid_position(w, shot.x, shot.y):
			return _fail_at(895)
	for speck: Game.Speck in game.specks:
		if not _valid_position(w, speck.x, speck.y):
			return _fail_at(895)
	for blast: Game.Blast in game.blasts:
		if not _valid_position(w, blast.x, blast.y):
			return _fail_at(895)

	if not _restore_inventory(doc, game):
		return null

	var key_rows: Variant = doc.get("keys", [])
	if not (key_rows is Array):
		return _fail_at(911)
	game.keys = {}
	for key: Variant in key_rows:
		if key != "key_brass" and key != "key_steel":
			return _fail_at(915)
		game.keys[str(key)] = true

	var drums: Variant = doc.get("drums", [])
	if not (drums is Array):
		return _fail_at(920)
	game.drums = {}
	for row: Variant in drums:
		if not (row is Array) or _count(row) != 3:
			return _fail_at(924)
		game.drums[Vector2(_float(row[0]), _float(row[1]))] = _int(row[2])

	var pickups: Variant = doc.get("pickups", [])
	if not (pickups is Array):
		return _fail_at(929)
	game.pickups = []
	for row: Variant in pickups:
		if not (row is Array) or (_count(row) != 3 and _count(row) != 4):
			return _fail_at(933)
		if not _valid_position(w, row[1], row[2]):
			return _fail_at(935)
		game.add_pickup(
			str(row[0]), _float(row[1]), _float(row[2]), _float(row[3]) if _count(row) > 3 else NAN
		)

	var visited: Variant = doc.get("visited", [])
	if not (visited is Array):
		return _fail_at(940)
	game.visited = {}
	for row: Variant in visited:
		if not (row is Array) or _count(row) != 2:
			return _fail_at(944)
		if not _valid_position(w, row[0], row[1]):
			return _fail_at(946)
		game.visited[Vector2i(_int(row[0]), _int(row[1]))] = true

	var panes: Variant = doc.get("panes", [])
	if not (panes is Array):
		return _fail_at(951)
	w.broken_panes = {}
	for row: Variant in panes:
		if not (row is Array) or _count(row) != 2:
			return _fail_at(955)
		w.broken_panes[Vector2i(_int(row[0]), _int(row[1]))] = true

	var rng_value: Variant = doc.get("rng", null)
	if typeof(rng_value) != TYPE_INT and typeof(rng_value) != TYPE_FLOAT:
		return _fail_at(960)
	game.rng.set_state(_int(rng_value))

	# The loading-area wave is awake only once its shutdown station is done.
	if w.extraction != null:
		var shutdown := game.stations_done.has(w.extraction.shutdown)
		for enemy: Enemy in game.wave:
			enemy.dormant = not shutdown

	game.music_bookmark = doc.get("music", null)
	if not (game.music_bookmark is Dictionary or game.music_bookmark == null):
		return _fail_at(971)
	game.total_kills = 0
	for enemy: Enemy in game.enemies:
		if enemy.hostile:
			game.total_kills += 1
	game.configure({})
	return game


## A saved reaction is [x, y, time...] or null. As in the reference, the point
## must be a valid position and every time must lie between 0 and the saved
## clock plus three seconds.
static func _state(value: Variant, length: int, world: LevelData, clock: float) -> Variant:
	if value == null:
		return null
	if not (value is Array) or _count(value) != length:
		return _fail_at(984)
	var out: Array = []
	for item: Variant in value:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return _fail_at(988)
		out.append(_float(item))
	if not _valid_position(world, out[0], out[1]):
		return _fail_at(991)
	for i in range(2, out.size()):
		if out[i] < 0.0 or out[i] > clock + 3.0:
			return _fail_at(993)
	return out


static func _normalise_kit(kit: Variant) -> Dictionary:
	if not (kit is Dictionary):
		return {}
	var fields: Dictionary = kit
	var out := {"health": _int(fields.get("health", 100))}
	var owned: Array = []
	var loaded: Array = []
	var reserve: Array = []
	var src_owned: Array = fields.get("owned", [])
	var src_loaded: Array = fields.get("loaded", [])
	var src_reserve: Array = fields.get("reserve", [])
	for i in Weapons.COUNT:
		owned.append(_bool(src_owned[i]) if i < src_owned.size() else i == Weapons.CROWBAR)
		loaded.append(_int(src_loaded[i]) if i < src_loaded.size() else 0)
		reserve.append(_int(src_reserve[i]) if i < src_reserve.size() else 0)
	out["owned"] = owned
	out["loaded"] = loaded
	out["reserve"] = reserve
	out["active"] = _int(fields.get("active", 1))
	var inventory: Dictionary = fields.get("inventory", {})
	var clean_inv := {}
	for name: String in HUD.ITEMS:
		clean_inv[name] = _int(inventory.get(name, 0))
	out["inventory"] = clean_inv
	out["slot"] = _int(fields.get("slot", 0))
	return out
