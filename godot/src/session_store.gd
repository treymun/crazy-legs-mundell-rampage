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
const VERSION := 7
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
	"crouched"
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
	"target"
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
			return String(choices[clampi(value - low, 0, choices.size() - 1)])
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


static func _selected(obj, keys: Array) -> Dictionary:
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
		var key := String(game.enemy_ids[i])
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
		drums.append([point.x, point.y, int(game.drums[point])])
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
		"pickups": game.pickups.duplicate(true),
		"visited": visited,
		"panes": panes,
		"rng": game.rng.get_state(),
	}


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


static func save(game: Game, path: String, manual = null) -> bool:
	var doc := snapshot(game)
	if not game.retained.is_empty():
		var retained := {}
		for key in game.retained:
			var chapter = game.retained[key]
			if chapter is Game:
				retained[String(key)] = snapshot(chapter)
		if not retained.is_empty():
			doc["retained"] = retained
	if manual is Dictionary:
		doc["manual"] = manual
	return _write_atomic(path, JSON.stringify(doc, "", false))


## The Python build documents its exact float formatting; the port only has to
## read its own files, so plain JSON floats are fine.


static func slot_directory(replay_level = null) -> String:
	var root := _path("save-slots")
	if replay_level == null or String(replay_level) == "":
		return root.path_join("campaign")
	return root.path_join("replay").path_join(String(replay_level))


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
static func slot_metadata(path: String, replay_level = null) -> Array:
	if not FileAccess.file_exists(path):
		return [null, null]
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > MAX_BYTES:
		return ["", null]
	var fingerprint := _sha256(raw)
	var doc = SaveUpgrade.upgrade(JSON.parse_string(raw.get_string_from_utf8()))
	if doc == null:
		return ["", null]
	if not Campaign.ORDER.has(String(doc.get("level", ""))):
		return ["", null]
	var campaign: Dictionary = doc.get("campaign", {})
	# The menu passes "" for the campaign's own slots; Python tests truthiness,
	# so None and "" both mean "not a replay".
	var replaying := replay_level != null and String(replay_level) != ""
	if bool(campaign.get("replay", false)) != replaying:
		return ["", null]
	if replaying and String(doc["level"]) != String(replay_level):
		return ["", null]
	var meta = doc.get("manual")
	if not (meta is Dictionary):
		return ["", null]
	var name := String(meta.get("label", ""))
	if name != slot_label(name).strip_edges() or name == "":
		return ["", null]
	var goal := String(meta.get("objective", ""))
	var stamp := String(meta.get("timestamp", ""))
	if goal.length() > 100 or stamp.length() > 32:
		return ["", null]
	return [fingerprint, [name, String(doc["level"]), goal, stamp.replace("T", " ").substr(0, 16)]]


static func save_named(game: Game, path: String, name: String, fingerprint) -> bool:
	var clean := slot_label(name).strip_edges()
	if clean == "" or (fingerprint is String and String(fingerprint) == ""):
		return false
	# Python passes None for "this slot was empty when the menu read it".
	var exists := FileAccess.file_exists(path)
	if exists:
		if (
			not (fingerprint is String)
			or _sha256(FileAccess.get_file_as_bytes(path)) != String(fingerprint)
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
			int(tz["year"]),
			int(tz["month"]),
			int(tz["day"]),
			int(tz["hour"]),
			int(tz["minute"]),
			int(tz["second"]),
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
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			values = parsed
	if not values.has("window_mode") and int(values.get("startup_fullscreen", 0)) == 1:
		values["window_mode"] = 1
	var out := {}
	for item: Setting in options_list():
		var value = values.get(item.key)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			out[item.key] = clampi(int(value), item.low, item.high)
		else:
			out[item.key] = item.default_value
	return out


static func save_settings(path: String, values: Dictionary) -> bool:
	return _write_atomic(_resolve(path, SETTINGS_FILE), JSON.stringify(values, "", false))


static func unlocks(path := "") -> Dictionary:
	var target := path if path != "" else _path(UNLOCKS_FILE)
	var result := {"hickston": true}
	if FileAccess.file_exists(target):
		var raw := FileAccess.get_file_as_bytes(target)
		if raw.size() > 4096:
			raw = raw.slice(0, 4096)
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Array:
			for level_id in Campaign.ORDER.slice(1):
				if not parsed.has(level_id):
					break
				result[level_id] = true
	return result


static func save_unlocks(path: String, unlocked: Dictionary) -> bool:
	var rows: Array = []
	for level_id in Campaign.ORDER:
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
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Array:
			for key in parsed:
				if key == "ledger" or key == "survey":
					out[key] = true
	return out


static func save_notes(path: String, notes: Dictionary) -> bool:
	var keys: Array = notes.keys()
	keys.sort()
	return _write_atomic(_resolve(path, ROAD_NOTES_FILE), JSON.stringify(keys, "", false))


# ------------------------------------------------------------- validation


static func _number(value) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and absf(float(value)) <= 1e7
	)


static func _assign(obj, key: String, value) -> bool:
	var before = obj.get(key)
	if before == null:
		if value != null:
			if not (
				value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])
			):
				return false
			obj.set(key, [float(value[0]), float(value[1])])
		return true
	match typeof(before):
		TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				return false
			obj.set(key, value)
		TYPE_STRING:
			if typeof(value) != TYPE_STRING or String(value).length() > 128:
				return false
			obj.set(key, value)
		TYPE_INT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not _number(value) or float(value) != floor(float(value)):
				return false
			obj.set(key, int(value))
		TYPE_FLOAT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not _number(value):
				return false
			obj.set(key, float(value))
		TYPE_ARRAY:
			# GDScript's typed arrays (Array[bool], Array[int]) reject obj.set()
			# with an untyped Array, so refill the existing array in place.
			var live: Array = before
			if not (value is Array) or value.size() != live.size():
				return false
			var want_bool := key == "owned"
			for item in value:
				if want_bool:
					if typeof(item) != TYPE_BOOL:
						return false
				else:
					if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
						return false
					if float(item) != floor(float(item)):
						return false
			live.clear()
			for item in value:
				live.append(item if want_bool else int(item))
		_:
			return false
	return true


static func _restore_fields(obj, values, keys: Array) -> bool:
	if not (values is Dictionary):
		last_error = "fields not a dictionary"
		return false
	for key: String in keys:
		if not values.has(key):
			last_error = "missing field " + key
			return false
		if not _assign(obj, key, values[key]):
			last_error = (
				"bad field %s (%s=%s)"
				% [key, type_string(typeof(values[key])), str(values[key]).substr(0, 40)]
			)
			return false
	return true


static func _valid_position(world: LevelData, x, y) -> bool:
	return (
		_number(x)
		and _number(y)
		and float(x) >= 0.0
		and float(y) >= 0.0
		and float(x) < float(world.width)
		and float(y) < float(world.height)
	)


static func _restore_list(rows, factory: Callable, kinds: Array, cap: int) -> Array:
	if not (rows is Array) or rows.size() > cap:
		return []
	var out: Array = []
	for row in rows:
		if not (row is Dictionary):
			return []
		if not kinds.has(String(row.get("kind", ""))):
			return []
		var obj = factory.call()
		for key in row:
			if key == "kind":
				obj.set("kind", String(row[key]))
			elif key == "enemy" or key == "resting":
				if typeof(row[key]) != TYPE_BOOL:
					return []
				obj.set(key, row[key])
			else:
				if typeof(row[key]) != TYPE_INT and typeof(row[key]) != TYPE_FLOAT:
					return []
				obj.set(key, float(row[key]))
		out.append(obj)
	return out


static func _validate_kit(kit) -> bool:
	if not (kit is Dictionary):
		return false
	var needed := ["health", "owned", "loaded", "reserve", "active", "inventory", "slot"]
	for key in needed:
		if not kit.has(key):
			return false
	var owned: Array = kit["owned"]
	var loaded: Array = kit["loaded"]
	var reserve: Array = kit["reserve"]
	# A save from before a gun was added has fewer: the rest start empty.
	if (
		owned.size() > Weapons.COUNT
		or owned.size() != loaded.size()
		or owned.size() != reserve.size()
		or owned.size() < 1
	):
		return false
	if typeof(kit["health"]) != TYPE_INT and typeof(kit["health"]) != TYPE_FLOAT:
		return false
	if not (int(kit["health"]) >= 1 and int(kit["health"]) <= 100):
		return false
	if not owned[0]:
		return false
	if not owned[int(kit["active"])]:
		return false
	for i in owned.size():
		if int(loaded[i]) < 0 or int(loaded[i]) > Weapons.SAVED_CAPACITY[i]:
			return false
		if int(reserve[i]) < 0 or int(reserve[i]) > Weapons.MAX_RESERVE[i]:
			return false
	var inventory: Dictionary = kit["inventory"]
	if inventory.size() != HUD.ITEMS.size():
		return false
	for name in HUD.ITEMS:
		if not inventory.has(name):
			return false
		var amount := int(inventory[name])
		if amount < 0 or amount > 5:
			return false
	return true


# ------------------------------------------------------------------- load


## Returns a restored Game or null (with a warning) when the file is unusable.
static func read(
	path: String, make_game: Callable, expected_replay = null, expected_level = null
) -> Game:
	if not FileAccess.file_exists(path):
		return _fail_at(646)
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > MAX_BYTES:
		push_warning("checkpoint too large")
		return _fail_at(650)
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		push_warning("checkpoint is not an object")
		return _fail_at(654)
	var doc = SaveUpgrade.upgrade(parsed)
	if doc == null:
		push_warning("unsupported checkpoint version")
		return _fail_at(657)
	var game := restore(doc, make_game, expected_replay)
	if game == null:
		return _fail_at(660)
	if (
		expected_level != null
		and String(expected_level) != ""
		and game.level.id != String(expected_level)
	):
		return _fail_at(662)
	var retained = doc.get("retained", {})
	if retained is Dictionary and not game.replay:
		var previous: Array = []
		var index := Campaign.ORDER.find(game.level.id)
		if index > 0:
			previous = Campaign.ORDER.slice(0, index)
		for key in retained:
			if not previous.has(String(key)):
				return _fail_at(671)
			var chapter_doc = retained[key]
			if not (chapter_doc is Dictionary):
				return _fail_at(674)
			if int(chapter_doc.get("version", 0)) != VERSION:
				return _fail_at(676)  # upgrade() brought every chapter up to VERSION
			if String(chapter_doc.get("level", "")) != String(key):
				return _fail_at(678)
			var chapter := restore(chapter_doc, make_game, false)
			if chapter != null and chapter.layout_restarted:
				# A finished chapter whose level has been rebuilt since: it
				# stays finished, its new map cleared.
				var finished = chapter_doc.get("game", {}).get("won", false)
				chapter.won = finished is bool and finished
				for enemy: Enemy in chapter.enemies:
					if enemy.hostile:
						enemy.hp = 0.0
				chapter.kills = chapter.total_kills
			if chapter == null or not chapter.won:
				return _fail_at(681)
			game.retained[String(key)] = chapter
	return game


static func restore(doc: Dictionary, make_game: Callable, expected_replay = null) -> Game:
	var level_id := String(doc.get("level", ""))
	if not Campaign.ORDER.has(level_id):
		return _fail_at(689)
	var game: Game = make_game.call(level_id)
	if game == null or game.level.id != level_id:
		return _fail_at(692)
	var w := game.world
	if int(doc.get("layout", 1)) != game.level.layout:
		return _restart(doc, game, expected_replay)
	if not _restore_fields(game, doc.get("game", {}), GAME_FIELDS):
		return _fail_at(695)
	var reward = doc.get("county_gallery", false)
	if typeof(reward) != TYPE_BOOL:
		return _fail_at(698)
	if game.gallery != null:
		game.gallery.rewarded = reward
	elif reward:
		return _fail_at(702)
	var supplies := int(doc.get("county_supplies", 0))
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
	if game.kills < 0 or game.kills > game.total_kills:
		return _fail_at(720)
	if game.secrets < 0 or game.secrets > game.total_secrets:
		return _fail_at(722)
	if not _check_armory(game):
		return null
	return _restore_rest(doc, game, expected_replay)


## The guns as saved: a save from before a gun existed has it empty.
static func _restore_armory(game: Game, doc: Dictionary) -> bool:
	var armory_doc = doc.get("armory", {})
	if armory_doc is Dictionary:
		armory_doc = armory_doc.duplicate(true)
		for key in ["owned", "loaded", "reserve"]:
			var saved = armory_doc.get(key)
			if saved is Array and saved.size() < Weapons.COUNT:
				# Saved before a gun was added: the new ones start empty.
				for k in Weapons.COUNT - saved.size():
					saved.append(false if key == "owned" else 0)
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
static func _restart(doc: Dictionary, game: Game, expected_replay) -> Game:
	var supplies := int(doc.get("county_supplies", 0))
	if supplies < 0 or supplies > 2:
		return _fail_at(705)
	game.supply_rule = supplies
	var health = doc.get("player", {}).get("health")
	if not _number(health) or int(health) <= 0 or int(health) > 100:
		return _fail_at(712)
	game.player.health = int(health)
	if not _restore_armory(game, doc) or not _check_armory(game):
		return null
	if not _restore_campaign(doc, game, expected_replay):
		return null
	if not _restore_inventory(doc, game):
		return null
	var slot = doc.get("game", {}).get("inventory_slot", 0)
	game.inventory_slot = clampi(int(slot) if _number(slot) else 0, 0, HUD.ITEMS.size() - 1)
	game.music_bookmark = null
	game.layout_restarted = true
	game.message("%s HAS BEEN REBUILT. THE CHAPTER STARTS OVER." % game.level.title, 5.0)
	game.configure({})
	return game


static func _restore_campaign(doc: Dictionary, game: Game, expected_replay) -> bool:
	var campaign: Dictionary = doc.get("campaign", {})
	if typeof(campaign.get("replay", false)) != TYPE_BOOL:
		_fail_at(813)
		return false
	game.replay = campaign["replay"]
	if expected_replay != null and game.replay != bool(expected_replay):
		_fail_at(816)
		return false
	if not _validate_kit(campaign.get("entry")):
		game.entry = _normalise_kit(campaign.get("entry"))
		if game.entry.is_empty():
			_fail_at(820)
			return false
	else:
		game.entry = _normalise_kit(campaign["entry"])
	var history = campaign.get("history", [])
	if not (history is Array):
		_fail_at(825)
		return false
	var expected_history := 0 if game.replay else Campaign.ORDER.find(game.level.id)
	if history.size() != expected_history:
		_fail_at(828)
		return false
	var clean_history: Array = []
	for row in history:
		if not (row is Array) or row.size() != 6:
			_fail_at(832)
			return false
		var clean: Array = [String(row[0])]
		for k in range(1, 6):
			clean.append(int(row[k]))
		clean_history.append(clean)
	game.history = clean_history
	return true


static func _restore_inventory(doc: Dictionary, game: Game) -> bool:
	var inventory = doc.get("inventory", {})
	if not (inventory is Dictionary) or inventory.size() != HUD.ITEMS.size():
		_fail_at(899)
		return false
	game.inventory = {}
	for name in HUD.ITEMS:
		if not inventory.has(name):
			_fail_at(903)
			return false
		var amount := int(inventory[name])
		if amount < 0 or amount > 5:
			_fail_at(906)
			return false
		game.inventory[name] = amount
	return true


static func _restore_rest(doc: Dictionary, game: Game, expected_replay) -> Game:
	var w := game.world
	# doors
	var doors_doc = doc.get("doors", {})
	if not (doors_doc is Dictionary):
		return _fail_at(736)
	var expected_doors := {}
	for door: LevelData.Door in w.doors:
		expected_doors[_door_key(door)] = door
	# Doors or enemies that no longer match the level's: it was changed since
	# without a new layout number. The chapter starts over rather than the save
	# being lost.
	if doors_doc.size() != expected_doors.size():
		return _restart(doc, game, expected_replay)
	for key in doors_doc:
		if not expected_doors.has(key):
			return _restart(doc, game, expected_replay)
		var door: LevelData.Door = expected_doors[key]
		if not _restore_fields(door, doors_doc[key], DOOR_FIELDS):
			return _fail_at(747)
		if door.progress < 0.0 or door.progress > 1.0:
			return _fail_at(749)

	# enemies
	var enemies_doc = doc.get("enemies", {})
	var ai_doc = doc.get("ai", {})
	if not (enemies_doc is Dictionary) or not (ai_doc is Dictionary):
		return _fail_at(755)
	# The level's own enemies (a bigger posse is the posse feature's to restore).
	var own := game.enemy_ids.size()
	if enemies_doc.size() != own or ai_doc.size() != own:
		return _restart(doc, game, expected_replay)
	var seen := {}
	for i in game.enemy_ids.size():
		var key := String(game.enemy_ids[i])
		var enemy: Enemy = game.enemies[i]
		if not enemies_doc.has(key) or not ai_doc.has(key):
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
		var aim = ai.get("aim")
		if aim == null:
			enemy.aim_mark = null
		elif (
			aim is Array
			and aim.size() == 3
			and _number(aim[0])
			and _number(aim[1])
			and _number(aim[2])
		):
			enemy.aim_mark = [float(aim[0]), float(aim[1]), float(aim[2])]
		else:
			return _fail_at(784)
		if enemy.windup > 0.0 and enemy.aim_mark == null:
			return _fail_at(786)
	if seen.size() != game.enemy_ids.size():
		return _fail_at(788)

	# reactions
	var reactions = doc.get("county_reactions", {})
	if not (reactions is Dictionary):
		return _fail_at(793)
	for key in reactions:
		var index := game.enemy_ids.find(String(key))
		if index < 0:
			return _fail_at(797)
		var row = reactions[key]
		if not (row is Array) or row.size() != 3 or typeof(row[2]) != TYPE_BOOL:
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
	Features.restore_all(game, doc.get("features", {}))

	# task state
	var stations = doc.get("stations", [])
	if not (stations is Array):
		return _fail_at(842)
	game.stations_done = {}
	for name in stations:
		if typeof(name) != TYPE_STRING:
			return _fail_at(846)
		game.stations_done[String(name)] = true
	var known_stations := {}
	for station: LevelData.Station in w.stations:
		known_stations[station.id] = true
	for name in game.stations_done:
		if not known_stations.has(name):
			return _fail_at(849)
	for station: LevelData.Station in w.stations:
		if game.stations_done.has(station.id):
			for required in station.requires:
				if not game.stations_done.has(String(required)):
					return _fail_at(852)
			# A finished station keeps its sectors lit after a load, as it does
			# in the reference (session_store.py re-applies the +0.26).
			game.set_station_lights(station)
	var tasks = doc.get("tasks", [])
	var scenery = doc.get("scenery", [])
	var heard = doc.get("heard", [])
	for row in [tasks, scenery, heard]:
		if not (row is Array):
			return _fail_at(858)
	game.task_items = {}
	for name in tasks:
		game.task_items[String(name)] = true
	game.scenery_spent = {}
	for name in scenery:
		game.scenery_spent[String(name)] = true
	game.heard_exchanges = {}
	for name in heard:
		game.heard_exchanges[String(name)] = true
	var turns = doc.get("valve_turns", {})
	if not (turns is Dictionary):
		return _fail_at(870)
	game.valve_turns = {}
	for key in turns:
		game.valve_turns[String(key)] = int(turns[key])

	# entities
	var shot_rows = doc.get("shots", [])
	var speck_rows = doc.get("specks", [])
	var blast_rows = doc.get("blasts", [])
	var hazard_rows = doc.get("hazards", [])
	game.shots = _restore_list(shot_rows, func(): return Game.Shot.new(), SHOT_KINDS, 240)
	if game.shots.size() != shot_rows.size():
		return _fail_at(882)
	game.specks = _restore_list(speck_rows, func(): return Game.Speck.new(), SPECK_KINDS, 4000)
	if game.specks.size() != speck_rows.size():
		return _fail_at(885)
	game.blasts = _restore_list(blast_rows, func(): return Game.Blast.new(), ["energy", "fire"], 80)
	if game.blasts.size() != blast_rows.size():
		return _fail_at(888)
	game.hazards = _restore_list(
		hazard_rows, func(): return Game.Hazard.new(), ["steam", "chalk"], 7
	)
	if game.hazards.size() != hazard_rows.size():
		return _fail_at(891)
	for row in [game.shots, game.specks, game.blasts]:
		for obj in row:
			if not _valid_position(w, obj.x, obj.y):
				return _fail_at(895)

	if not _restore_inventory(doc, game):
		return null

	var key_rows = doc.get("keys", [])
	if not (key_rows is Array):
		return _fail_at(911)
	game.keys = {}
	for key in key_rows:
		if key != "key_brass" and key != "key_steel":
			return _fail_at(915)
		game.keys[String(key)] = true

	var drums = doc.get("drums", [])
	if not (drums is Array):
		return _fail_at(920)
	game.drums = {}
	for row in drums:
		if not (row is Array) or row.size() != 3:
			return _fail_at(924)
		game.drums[Vector2(float(row[0]), float(row[1]))] = int(row[2])

	var pickups = doc.get("pickups", [])
	if not (pickups is Array):
		return _fail_at(929)
	game.pickups = []
	for row in pickups:
		if not (row is Array) or row.size() != 3:
			return _fail_at(933)
		if not _valid_position(w, row[1], row[2]):
			return _fail_at(935)
		game.pickups.append([String(row[0]), float(row[1]), float(row[2])])

	var visited = doc.get("visited", [])
	if not (visited is Array):
		return _fail_at(940)
	game.visited = {}
	for row in visited:
		if not (row is Array) or row.size() != 2:
			return _fail_at(944)
		if not _valid_position(w, row[0], row[1]):
			return _fail_at(946)
		game.visited[Vector2i(int(row[0]), int(row[1]))] = true

	var panes = doc.get("panes", [])
	if not (panes is Array):
		return _fail_at(951)
	w.broken_panes = {}
	for row in panes:
		if not (row is Array) or row.size() != 2:
			return _fail_at(955)
		w.broken_panes[Vector2i(int(row[0]), int(row[1]))] = true

	var rng_value = doc.get("rng", null)
	if typeof(rng_value) != TYPE_INT and typeof(rng_value) != TYPE_FLOAT:
		return _fail_at(960)
	game.rng.set_state(int(rng_value))

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
static func _state(value, length: int, world: LevelData, clock: float):
	if value == null:
		return null
	if not (value is Array) or value.size() != length:
		return _fail_at(984)
	var out: Array = []
	for item in value:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return _fail_at(988)
		out.append(float(item))
	if not _valid_position(world, out[0], out[1]):
		return _fail_at(991)
	for i in range(2, out.size()):
		if out[i] < 0.0 or out[i] > clock + 3.0:
			return _fail_at(993)
	return out


static func _normalise_kit(kit) -> Dictionary:
	if not (kit is Dictionary):
		return {}
	var out := {"health": int(kit.get("health", 100))}
	var owned: Array = []
	var loaded: Array = []
	var reserve: Array = []
	var src_owned: Array = kit.get("owned", [])
	var src_loaded: Array = kit.get("loaded", [])
	var src_reserve: Array = kit.get("reserve", [])
	for i in Weapons.COUNT:
		owned.append(bool(src_owned[i]) if i < src_owned.size() else i == Weapons.CROWBAR)
		loaded.append(int(src_loaded[i]) if i < src_loaded.size() else 0)
		reserve.append(int(src_reserve[i]) if i < src_reserve.size() else 0)
	out["owned"] = owned
	out["loaded"] = loaded
	out["reserve"] = reserve
	out["active"] = int(kit.get("active", 1))
	var inventory: Dictionary = kit.get("inventory", {})
	var clean_inv := {}
	for name in HUD.ITEMS:
		clean_inv[name] = int(inventory.get(name, 0))
	out["inventory"] = clean_inv
	out["slot"] = int(kit.get("slot", 0))
	return out
