## Snapshots of the simulation, for a network game: what a machine needs to
## carry on the game another machine is running, tick for tick.
##
##   var data := GameSnapshot.capture(game)      # a Dictionary of plain values
##   GameSnapshot.apply(game, data)              # onto a Game of that level:
##                                               # fresh, or one already running
##   var bytes := GameSnapshot.to_bytes(data)    # compact (zstd), from_bytes()
##   var d := GameSnapshot.delta(base, data)     # what changed since `base`
##   GameSnapshot.patch(base, d)                 # == data again
##   GameSnapshot.apply_delta(game, d, data)     # only what d touches, from data
##
## The host (game_host.gd) does not capture and compare whole snapshots: its
## NetTrack (net_track.gd) finds what changed field by field and hands out the
## same deltas; a GameMirror puts them onto a client's game with apply_delta.
##
## What is SIMULATION (deterministic, from game.rng, carried) and what is
## PRESENTATION (cosmetic dice, sprites, sound, the HUD, never carried) is
## written down here and nowhere else: every field of Game is in SIM_FIELDS,
## VIEW_FIELDS or PLAYER_FIELDS, every feature in SIM_FEATURES or
## LOOKS_FEATURES, and tools/net_check.gd fails when one is in none (a new
## field or feature must be put in one). Enemies, players, shots and the
## state of the simulation's features are carried whole (every script
## variable, snap_codec.gd), less SnapCodec.SKIP_FIELDS and what its
## ONLY_FIELDS leave out of things the level makes the same everywhere.
##
## A snapshot holds: "game" (SIM_FIELDS), "world" (each door's progress,
## opened and discovered by its place in the level's list; the panes broken,
## in the order they broke), "facts" (the save() of each feature in
## FACT_FEATURES: what it broke, which changes the level's walls and floor;
## apply hands it to the feature's restore(), which puts back only what is
## not broken yet), "players" (by slot), "enemies" (by uid, with "order"),
## "features" (each simulation feature's variables), "statics". A finished
## station's lights follow stations_done. Entities are named by stable ids: a
## player by slot, an enemy, shot or pickup by its uid (game.take_uid, handed
## out as things come into being), a door, station or scenery piece by its
## place in the level's list, a breakable or a wall break by its place in its
## feature's list.
class_name GameSnapshot
extends RefCounted

const VERSION := 2
## Features whose save() is how the level's walls and floor are put back (a
## piece broken leaves its base, a fence shot through opens its cell).
const FACT_FEATURES := ["breakables", "wall_breaks"]
## The game's simulation state: carried and put back.
const SIM_FIELDS := [
	"clock",
	"rng",
	"next_uid",
	"kills",
	"secrets",
	"total_kills",
	"total_secrets",
	"spawn_grace",
	"pickups",
	"drums",
	"stations_done",
	"scenery_spent",
	"bowled",
	"valve_turns",
	"next_valve_turn",
	"triggers_fired",
	"triggers_inside",
	"shots",
	"hazards",
	"won",
	"legacy_completed",
	"legacy_key_route",
	"supply_rule",
	"gate_modes",
	"hub_findings",
	"hub_milestone",
	"hub_dispatch_until",
	"portal_request",
	"entry",
	"history",
	"replay",
	"revisiting",
	"retained",
	"in_hub",
	"layout_restarted",
	"hitstop",
	"hitstop_next",
	"slowmo",
	"boss_hold",
	"boss_hold_for",
	"boss_hold_of",
	"boss_hold_armed",
	"boss_backup",
	"flush_until",
	"jukebox_on",
	"wave",
	"boss",
	"jerry",
	"bessie",
	"finale",
	"gallery",
	"cheats",
	"difficulty",
	"sharpness",
	"ammo_scale",
	"incoming",
	"hit_feedback",
	"adaptive",
	"aim_assist",
	"touch_aim",
	"lessons",
]
## Each player's own (Player carries them; these Game names only point at the
## acting player's): carried under "players".
const PLAYER_FIELDS := [
	"players",
	"local_player",
	"player",
	"armory",
	"flow",
	"inventory",
	"keys",
	"task_items",
	"inventory_slot",
	"sprint",
	"step_number",
	"next_belch",
	"_idle",
	"own_step",
]
## Presentation, wiring, caches and things worked out again: never carried.
## (enemies and enemy_ids are carried under "enemies"; partners, route,
## dangers and the use/aim caches are worked out from the level or the tick.)
const VIEW_FIELDS := [
	"_named_enemies",
	"place_log",
	"specks",
	"blasts",
	"art",
	"hud",
	"sound",
	"speaker",
	"level",
	"world",
	"renderer",
	"enemy_ids",
	"enemies",
	"partners",
	"route",
	"route_sig",
	"dangers",
	"props",
	"fixed_sprites",
	"fixed_sprites_late",
	"fixed_windmills",
	"fixed_sprites_key",
	"fixed_blocks",
	"late_blocks",
	"view_cone",
	"fixed_cull",
	"late_cull",
	"sprite_pool",
	"sprite_pool_n",
	"dress_list",
	"dress_at",
	"dress_of",
	"shelter_key",
	"shelter_alert",
	"lamp_props",
	"lamp_boards",
	"lamps_of",
	"music_bookmark",
	"barks",
	"duck",
	"barks_off_by_code",
	"chatter",
	"last_low_bark",
	"face_until",
	"message_until",
	"face",
	"notice",
	"hurt_flash",
	"blast_flash",
	"damage_feedback",
	"item_feedback",
	"hit_mark_until",
	"hit_mark_kill",
	"hit_tick_next",
	"shake",
	"gore_fx",
	"wall_marks",
	"wall_sound",
	"map",
	"exchanges",
	"heard_exchanges",
	"exchange_next",
	"exchange_pending",
	"caption",
	"caption_until",
	"visited",
	"district",
	"district_until",
	"pin_top",
	"amb_clock",
	"aim_cache",
	"use_key",
	"use_aim",
	"map_panel",
	"map_signature",
	"radio_check",
	"bob_scale",
	"look_bands",
	"gpu_look",
	"layered",
	"scene_live",
	"drunk_k",
	"hurt_alpha",
	"look_live",
	"tone_live",
	"flash_scale",
	"gore",
	"shake_scale",
	"adapt",
	"sights_next",
	"sights_last",
	"trigger_lights",
	"bark_next",
	"hit_point",
	"hit_from",
	"blast_kind",
	"hit_mark_at",
	"hit_mark_head",
	"impact_kind",
	"view_kick",
	"feel_turn",
	"feel_landed",
	"view_eye",
	"lightning",
	"callout",
	"callout_until",
	"features",
	"district_labels",
	"hints",
	"hud_style",
	"weapon_view",
	"voice_captions",
	"bullet_marks",
	"retro_look",
	"flicker",
	"crosshair_tint",
	"tone",
	"showing_tally",
	"_render_open",
	"scene_hook",
	"_grit_r",
	"_grit_g",
	"_grit_b",
	"_dither",
	"_look_threads",
	"_look_rows_per",
	"_look_gain",
	"_look_frame",
	"_look_blast",
	"_look_tone",
	"_map_image",
	"_map_built_scale",
	"_map_painted",
	"_map_hidden",
	"_map_origin",
	"_map_scale_now",
	"_map_region_now",
	"map_zoom",
	"_map_texture",
	"stage_ms",
	"host",
	"net_facts",
	"lit_stations",
	"flow_walks",
	"body_cells",
	"body_cells_on",
]
## Features whose state is play (carried: every variable but `game`).
const SIM_FEATURES := [
	"triggers",
	"county",
	"posse",
	"boss_fight",
	"race_laps",
	"range",
	"bayou",
	"mothership",
	"corpses",
	"breakables",
	"wall_breaks",
	"boss_rematch",
	"boss_arena",
	"boss_arenas",
	"hit_reads",
	"critters",
	"variants",
	"squad",
	"mode",
]
## Features that only look or sound (their own dice; never carried).
const LOOKS_FEATURES := [
	"lessons",
	"stats",
	"weather",
	"debris",
	"weapon_fx",
	"ambient",
	"callouts",
	"tally",
	"fight_music",
	"water",
	"impacts",
	"dust",
	"gun_fx",
	"feel",
	"soundscape",
	"boss_voices",
	"enemy_barks",
	"boss_checkpoint",
]


## The simulation state of `game` now, as plain values.
static func capture(game) -> Dictionary:
	game.name_new()
	var codec := SnapCodec.new(game)
	var fields := {}
	for name: String in SIM_FIELDS:
		var v = game.get(name)
		fields[name] = v if SnapCodec.PLAIN.has(typeof(v)) else codec.encode(v)
	var players := {}
	for p: Player in game.players:
		players[str(p.slot)] = codec.encode_fields(p)
	var enemies := {}
	var order: Array = []
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		order.append(e.uid)
		enemies[str(e.uid)] = enemy_row(game, codec, i)
	var features := {}
	for id: String in SIM_FEATURES:
		var feature = game.features.get(id)
		if feature != null:
			features[id] = feature_row(codec, feature, id)
	return {
		"v": VERSION,
		"level": game.level.id,
		"layout": game.level.layout,
		"game": fields,
		"world": world_of(game),
		"facts": facts_of(game),
		"players": players,
		"enemies": enemies,
		"order": order,
		"features": features,
		"statics": statics_of(codec),
		"unknown": codec.unknown.keys(),
	}


## The carried fields of game.enemies[i], with "@id" its id in the level ("" for
## one that joined later).
static func enemy_row(game, codec: SnapCodec, i: int) -> Dictionary:
	var row: Dictionary = codec.encode_fields(game.enemies[i])
	row["@id"] = String(game.enemy_ids[i]) if i < game.enemy_ids.size() else ""
	return row


## A simulation feature's variables (all but `game`).
static func feature_row(codec: SnapCodec, feature, id: String) -> Dictionary:
	var vars := {}
	for name: String in SnapCodec.fields_of(feature, id):
		if name != "game":
			var v = feature.get(name)
			vars[name] = v if SnapCodec.PLAIN.has(typeof(v)) else codec.encode(v)
	return vars


## The level's own changing state: each door's progress, opened and
## discovered (by its place in the level's list), the panes broken.
static func world_of(game) -> Dictionary:
	var doors: Array = []
	for door: LevelData.Door in game.world.doors:
		doors.append([door.progress, door.opened, door.discovered])
	var panes: Array = []
	for cell: Vector2i in game.world.broken_panes:
		panes.append(cell)
	return {"doors": doors, "panes": panes}


## What each FACT_FEATURES feature broke, in its save's own form.
static func facts_of(game) -> Dictionary:
	var out := {}
	for id: String in FACT_FEATURES:
		var feature = game.features.get(id)
		if feature != null:
			out[id] = SnapCodec.plain(feature.save())
	return out


## Play kept in static variables (every game in the program shares them, by
## enemy instance id): this game's part. New play belongs on the enemy or in a
## feature instead.
static func statics_of(codec: SnapCodec) -> Dictionary:
	var derby := {}
	for key in DerbyChamp.state:
		if codec.iids.has(key):
			derby[key] = DerbyChamp.state[key]
	return {"derby": codec.encode(derby)}


## Puts the simulation state `data` onto `game`, a Game of the same level and
## layout: one just made (Game.new) or one already running (a client keeping
## up with a host). The players it lacks join, the level's doors, panes and
## broken things are put as they were (only what is not broken yet breaks),
## then every carried field is set. Presentation options stay as `game` had
## them. False when `data` is for another level.
static func apply(game, data: Dictionary) -> bool:
	if String(data.get("level", "")) != game.level.id:
		return false
	if int(data.get("layout", 0)) != game.level.layout:
		return false
	var codec := SnapCodec.new(game)
	var players: Dictionary = data["players"]
	while game.players.size() < players.size():
		Players.join(game, game.player.x, game.player.y, 0.0)
	var local: Player = game.local_player
	game.focus(game.players[0])
	_apply_world(game, data.get("world", {}))
	_apply_enemies(game, codec, data, {})
	_apply_facts(game, data.get("facts", {}))
	for slot: String in players:
		var p: Player = game.players[int(slot)]
		var row: Dictionary = players[slot]
		for name: String in row:
			codec.set_field(p, name, row[name])
	_share(game)
	var fields: Dictionary = data["game"]
	for name: String in SIM_FIELDS:
		if fields.has(name):
			codec.set_field(game, name, fields[name])
	var features: Dictionary = data["features"]
	for id: String in features:
		var feature = game.features.get(id)
		if feature == null:
			continue
		var vars: Dictionary = features[id]
		for name: String in vars:
			codec.set_field(feature, name, vars[name])
	_apply_statics(game, codec, data.get("statics", {}))
	_settle(game, local)
	return true


## Puts onto `game` only what `change` (a delta whose patch gives `full`, the
## whole snapshot it now matches) touches, each field from `full`: what a
## client does with every delta from its host. `game` must hold the state of
## the snapshot `change` was taken against.
static func apply_delta(game, change: Dictionary, full: Dictionary) -> void:
	var codec := SnapCodec.new(game)
	var players: Dictionary = full["players"]
	while game.players.size() < players.size():
		Players.join(game, game.player.x, game.player.y, 0.0)
	var local: Player = game.local_player
	game.focus(game.players[0])
	if change.has("world"):
		_apply_world(game, full["world"])
	if change.has("enemies") or change.has("order"):
		_apply_enemies(game, codec, full, change.get("enemies", {}))
	else:
		for e: Enemy in game.enemies:
			codec.by_uid[e.uid] = e
	if change.has("facts"):
		_apply_facts(game, full["facts"])
	var players_change: Dictionary = change.get("players", {})
	for slot in players_change:
		if typeof(slot) == TYPE_STRING and String(slot).begins_with("@"):
			continue
		var row: Dictionary = players[slot]
		var p: Player = game.players[int(slot)]
		for name: String in _touched(players_change[slot], row):
			codec.set_field(p, name, row[name])
	if not players_change.is_empty():
		_share(game)
	var fields: Dictionary = full["game"]
	for name: String in _touched(change.get("game", {}), fields):
		codec.set_field(game, name, fields[name])
	var features_change: Dictionary = change.get("features", {})
	for id in features_change:
		var feature = game.features.get(id)
		if feature == null or not full["features"].has(id):
			continue
		var vars: Dictionary = full["features"][id]
		for name: String in _touched(features_change[id], vars):
			codec.set_field(feature, name, vars[name])
	if change.has("statics"):
		_apply_statics(game, codec, full["statics"])
	_settle(game, local)


## The field names a row's change touches (all of the row for a new one).
static func _touched(change, row: Dictionary) -> Array:
	if not (change is Dictionary) or change.has("@new"):
		return row.keys()
	var out: Array = []
	for name in change:
		if typeof(name) == TYPE_STRING and not String(name).begins_with("@"):
			out.append(name)
	return out


## The dictionaries the party shares are one object again (Players.SHARED).
static func _share(game) -> void:
	for name: String in Players.SHARED:
		if bool(Players.SHARED[name]):
			for p: Player in game.players:
				p.set(name, game.players[0].get(name))


static func _apply_statics(game, codec: SnapCodec, statics: Dictionary) -> void:
	var derby = codec.decode(statics.get("derby", {}))
	if derby is Dictionary:
		# Ours only (the dictionary is every game's): the old part of it goes.
		for e: Enemy in game.enemies:
			if not derby.has(e.get_instance_id()):
				DerbyChamp.state.erase(e.get_instance_id())
		DerbyChamp.state.merge(derby, true)


## After a snapshot: a finished station's lights, and the caches keyed on what
## changed underneath them start over; the local player is acting again.
static func _settle(game, local: Player) -> void:
	for station: LevelData.Station in game.world.stations:
		if game.stations_done.has(station.id) and not game.lit_stations.has(station.id):
			game.set_station_lights(station)
	game.shelter_key = Vector2i(-1, -1)
	game.route_sig = []
	game._named_enemies = game.enemies.size()
	game.player = null
	game.focus(local)


## Each door as the snapshot has it, and the panes broken.
static func _apply_world(game, world: Dictionary) -> void:
	var doors: Array = world.get("doors", [])
	var list: Array = game.world.doors
	for i in mini(doors.size(), list.size()):
		var door: LevelData.Door = list[i]
		var row: Array = doors[i]
		door.progress = float(row[0])
		door.opened = bool(row[1])
		door.discovered = bool(row[2])
	var panes: Array = world.get("panes", [])
	if panes.size() != game.world.broken_panes.size():
		var broken := {}
		for cell in panes:
			broken[cell] = true
		game.world.broken_panes = broken


## What FACT_FEATURES broke, onto the level: each feature's restore() breaks
## what is not broken yet (quietly). Only when it differs from what this game
## was last given (game.net_facts), so a running game is not asked each time.
static func _apply_facts(game, facts: Dictionary) -> void:
	for id: String in facts:
		var feature = game.features.get(id)
		if feature == null:
			continue
		var state = facts[id]
		var key := var_to_bytes(state)
		if game.net_facts.get(id) == key:
			continue
		game.net_facts[id] = key
		feature.restore(state if state is Dictionary else {})


## The enemies in the snapshot's order: each one the game has with that uid,
## else a new one; every carried field set (for a delta, only the fields
## `change` touches of the enemies it names, every field of a new one); uids
## map for the references.
static func _apply_enemies(game, codec: SnapCodec, data: Dictionary, change) -> void:
	var rows: Dictionary = data["enemies"]
	var order: Array = data["order"]
	var had := {}
	for e: Enemy in game.enemies:
		had[e.uid] = e
	var whole: bool = not (change is Dictionary) or change.is_empty() or change.has("@new")
	var list: Array = []
	var ids: Array = []
	var made := {}
	for i in order.size():
		var uid := int(order[i])
		var row: Dictionary = rows[str(uid)]
		var e: Enemy = had.get(uid)
		if e == null:
			e = Enemy.new(String(row["kind"]), float(row["x"]), float(row["y"]))
			made[uid] = true
		list.append(e)
		codec.by_uid[uid] = e
		if String(row["@id"]) != "":
			ids.append(String(row["@id"]))
	game.enemies.assign(list)
	game.enemy_ids.assign(ids)
	for i in order.size():
		var uid := int(order[i])
		var key := str(uid)
		var row: Dictionary = rows[key]
		var names: Array
		if whole or made.has(uid):
			names = row.keys()
		elif change.has(key):
			names = _touched(change[key], row)
		else:
			continue
		for name: String in names:
			if name != "@id":
				codec.set_field(list[i], name, row[name])


# ------------------------------------------------------------------ forms


## The compact form: var_to_bytes, zstd.
static func to_bytes(data: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(data)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {}
	var size := bytes.decode_u32(0)
	var raw := bytes.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var data = bytes_to_var(raw)
	return data if data is Dictionary else {}


## Whether two snapshots are the same, value for value (bit for bit, so a NaN
## equals itself).
static func same(a: Dictionary, b: Dictionary) -> bool:
	return var_to_bytes(_without_unknown(a)) == var_to_bytes(_without_unknown(b))


static func _without_unknown(d: Dictionary) -> Dictionary:
	if not d.has("unknown"):
		return d
	var out := d.duplicate()
	out.erase("unknown")
	return out


## What changed from `base` to `now`: dictionaries are walked (a changed key
## carries its new value: a dictionary as {"@new": value}, anything else as
## it is; a key gone is listed under "@gone", the keys' order under "@order"
## when it is not base's with new keys after). patch(base, delta(base, now))
## == now. Each value is compared once, bit for bit.
static func delta(base, now):
	if not (base is Dictionary and now is Dictionary):
		return {"@new": now} if now is Dictionary else now
	var out := {}
	var gone: Array = []
	for key in base:
		if not now.has(key):
			gone.append(key)
	for key in now:
		var n = now[key]
		if not base.has(key):
			out[key] = {"@new": n} if n is Dictionary else n
			continue
		var b = base[key]
		if b is Dictionary and n is Dictionary:
			var inner = delta(b, n)
			if not inner.is_empty():
				out[key] = inner
		elif typeof(b) != typeof(n) or var_to_bytes(b) != var_to_bytes(n):
			out[key] = {"@new": n} if n is Dictionary else n
	if not gone.is_empty():
		out["@gone"] = gone
	var expected: Array = []
	for key in base:
		if now.has(key):
			expected.append(key)
	for key in now:
		if not base.has(key):
			expected.append(key)
	if expected != now.keys():
		out["@order"] = now.keys()
	return out


## `base` with `change` (a delta()) laid over it, as a new snapshot.
static func patch(base, change):
	if not (change is Dictionary):
		return change
	if change.has("@new"):
		return change["@new"]
	var out: Dictionary = base.duplicate() if base is Dictionary else {}
	if change.has("@gone"):
		for gone in change["@gone"]:
			out.erase(gone)
	for key in change:
		if typeof(key) == TYPE_STRING and (key == "@gone" or key == "@order"):
			continue
		out[key] = patch(out.get(key), change[key])
	if change.has("@order"):
		var ordered := {}
		for key in change["@order"]:
			ordered[key] = out[key]
		return ordered
	return out


## patch() into `base` itself, which must be the caller's own (a client's copy
## of the last snapshot): only the dictionaries the change touches change.
static func patch_into(base: Dictionary, change: Dictionary) -> Dictionary:
	if change.has("@new"):
		return change["@new"]
	if change.has("@gone"):
		for gone in change["@gone"]:
			base.erase(gone)
	for key in change:
		if typeof(key) == TYPE_STRING and (key == "@gone" or key == "@order"):
			continue
		var c = change[key]
		var b = base.get(key)
		if c is Dictionary and not c.has("@new") and b is Dictionary:
			base[key] = patch_into(b, c)
		else:
			base[key] = patch(b, c)
	if change.has("@order"):
		var ordered := {}
		for key in change["@order"]:
			ordered[key] = base[key]
		return ordered
	return base


## Two deltas one after the other as one: patch(patch(b, older), newer) ==
## patch(b, merge(older, newer)). Neither may carry "@order" (the host's never
## do); null when one does.
static func merge(older, newer):
	if not (newer is Dictionary) or newer.has("@new"):
		return newer
	if newer.has("@order"):
		return null
	if not (older is Dictionary):
		return newer
	if older.has("@new"):
		return {"@new": patch(older["@new"], newer)}
	if older.has("@order"):
		return null
	var out: Dictionary = older.duplicate()
	var gone: Array = (out.get("@gone", []) as Array).duplicate()
	for key in newer.get("@gone", []):
		out.erase(key)
		if not gone.has(key):
			gone.append(key)
	for key in newer:
		if typeof(key) == TYPE_STRING and key == "@gone":
			continue
		# (A key back again after it went stays under "@gone" too: patch()
		# takes it away first, then puts it at the end, as it came.)
		if out.has(key):
			var merged = merge(out[key], newer[key])
			if merged == null:
				return null
			out[key] = merged
		else:
			out[key] = newer[key]
	out.erase("@gone")
	if not gone.is_empty():
		out["@gone"] = gone
	return out


## The first place two snapshots differ ("" when they do not), for a check's
## report: a path of keys and both values, shortened.
static func first_difference(a, b, path := "") -> String:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if typeof(key) == TYPE_STRING and key == "unknown":
				continue
			if not b.has(key):
				return "%s/%s: only in the first" % [path, key]
			var inner := first_difference(a[key], b[key], "%s/%s" % [path, key])
			if inner != "":
				return inner
		for key in b:
			if not a.has(key) and not (typeof(key) == TYPE_STRING and key == "unknown"):
				return "%s/%s: only in the second" % [path, key]
		# The same keys in another order (a loop over them would go otherwise).
		if var_to_bytes(a.keys()) != var_to_bytes(b.keys()):
			return (
				"%s: keys in another order (%s against %s)"
				% [path, str(a.keys()).left(60), str(b.keys()).left(60)]
			)
		if var_to_bytes(a) != var_to_bytes(b):
			return "%s: the dictionaries are typed otherwise" % path
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: %d items against %d" % [path, a.size(), b.size()]
		for i in a.size():
			var inner := first_difference(a[i], b[i], "%s[%d]" % [path, i])
			if inner != "":
				return inner
		if var_to_bytes(a) != var_to_bytes(b):
			return "%s: typed %s against %s" % [path, a.get_typed_builtin(), b.get_typed_builtin()]
		return ""
	if var_to_bytes(a) != var_to_bytes(b):
		return "%s: %s against %s" % [path, str(a).left(80), str(b).left(80)]
	return ""


## Fields of `game` and features it has that are in no list here (a check
## fails on them: say whether each is simulation or presentation).
static func unclassified(game) -> Array:
	var known := {}
	for name: String in SIM_FIELDS + PLAYER_FIELDS + VIEW_FIELDS:
		known[name] = true
	var out: Array = []
	for prop: Dictionary in game.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if not known.has(String(prop["name"])):
			out.append("Game." + String(prop["name"]))
	for id: String in game.features:
		if not SIM_FEATURES.has(id) and not LOOKS_FEATURES.has(id):
			out.append("feature " + id)
	return out
