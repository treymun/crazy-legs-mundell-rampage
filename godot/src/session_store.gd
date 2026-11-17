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
const VERSION := 10
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
			KeyBindings.hint(p_action, p_label)
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


## The guns as a save keeps them: ARM_FIELDS, and the junk bench's scrap and
## mods (version 10; src/bench_mods.gd).
static func _armory_doc(armory: Weapons.Armory) -> Dictionary:
	var out := _selected(armory, ARM_FIELDS)
	out["scrap"] = armory.scrap
	out["mods"] = Array(armory.mods)
	return out


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
		"armory": _armory_doc(game.armory),
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
	# Player one's save, whoever this machine shows (watching a partner) or
	# whoever is acting.
	var acting := game.player
	if acting != game.players[0]:
		game.focus(game.players[0])
	var doc := snapshot(game)
	if acting != game.player:
		game.focus(acting)
	# Co-op: player one down when it was taken comes back on their feet, as a
	# partner down does (Modes.gather), or the save would never load.
	var lead: Dictionary = doc["player"]
	var lead_health: int = lead.get("health", 100)
	if lead_health <= 0 and Modes.mode_of(game) == Modes.COOP:
		lead["health"] = CoopMode.REVIVE_HEALTH
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


# ------------------------------------------------------------------- load


## SaveRestore.read (save_restore.gd).
static func read(
	path: String,
	make_game: Callable,
	expected_replay: Variant = null,
	expected_level: Variant = null
) -> Game:
	return SaveRestore.read(path, make_game, expected_replay, expected_level)


## SaveRestore.restore (save_restore.gd).
static func restore(doc: Dictionary, make_game: Callable, expected_replay: Variant = null) -> Game:
	return SaveRestore.restore(doc, make_game, expected_replay)


## SaveRestore.restore_onto (save_restore.gd).
static func restore_onto(doc: Dictionary, game: Game, expected_replay: Variant = null) -> Game:
	return SaveRestore.restore_onto(doc, game, expected_replay)
