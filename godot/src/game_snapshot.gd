## Snapshots of the simulation, for a later network game: what a machine needs
## to carry on the game another machine is running, tick for tick.
##
##   var data := GameSnapshot.capture(game)      # a Dictionary of plain values
##   GameSnapshot.apply(fresh, data)             # fresh: Game.new(...) of that
##                                               # level, never ticked
##   var bytes := GameSnapshot.to_bytes(data)    # compact (zstd), from_bytes()
##   var d := GameSnapshot.delta(base, data)     # what changed since `base`
##   GameSnapshot.patch(base, d)                 # == data again
##
## What is SIMULATION (deterministic, from game.rng, carried) and what is
## PRESENTATION (cosmetic dice, sprites, sound, the HUD, never carried) is
## written down here and nowhere else: every field of Game is in SIM_FIELDS,
## VIEW_FIELDS or PLAYER_FIELDS, every feature in SIM_FEATURES or
## LOOKS_FEATURES, and tools/net_check.gd fails when one is in none (a new
## field or feature must be put in one). Enemies, players, shots and the
## state of the simulation's features are carried whole (every script
## variable, snap_codec.gd), less SnapCodec.SKIP_FIELDS.
##
## A snapshot holds: "save" (the save game of the moment, SessionStore's own,
## which puts back the level's doors, broken things, stations and features),
## "game" (SIM_FIELDS), "players" (by slot), "enemies" (by uid, with "order"),
## "features" (each simulation feature's variables). Entities are named by
## stable ids: a player by slot, an enemy, shot or pickup by its uid
## (game.take_uid, handed out as things come into being), a door, station or
## scenery piece by its place in the level's list, a breakable or a wall
## break by its place in its feature's list.
class_name GameSnapshot
extends RefCounted

const VERSION := 1

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
]
## Features whose state is play (carried: every variable but `game`).
const SIM_FEATURES := [
	"triggers",
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
		fields[name] = codec.encode(game.get(name))
	var players := {}
	for p: Player in game.players:
		players[str(p.slot)] = codec.encode_fields(p)
	var enemies := {}
	var order: Array = []
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		order.append(e.uid)
		var row: Dictionary = codec.encode_fields(e)
		row["@id"] = String(game.enemy_ids[i]) if i < game.enemy_ids.size() else ""
		enemies[str(e.uid)] = row
	var features := {}
	for id: String in SIM_FEATURES:
		var feature = game.features.get(id)
		if feature == null:
			continue
		var vars := {}
		for name: String in SnapCodec.fields_of(feature, id):
			if name != "game":
				vars[name] = codec.encode(feature.get(name))
		features[id] = vars
	return {
		"v": VERSION,
		"level": game.level.id,
		"layout": game.level.layout,
		"save": _save_of(game),
		"game": fields,
		"players": players,
		"enemies": enemies,
		"order": order,
		"features": features,
		"statics": _statics(codec),
		"unknown": codec.unknown.keys(),
	}


## Play kept in static variables (every game in the program shares them, by
## enemy instance id): this game's part. New play belongs on the enemy or in a
## feature instead.
static func _statics(codec: SnapCodec) -> Dictionary:
	var derby := {}
	for key in DerbyChamp.state:
		if codec.iids.has(key):
			derby[key] = DerbyChamp.state[key]
	return {"derby": codec.encode(derby)}


## The save game of the moment, less the flying specks and blast flashes (a
## save keeps them; they are looks, made with the features' own dice too).
static func _save_of(game) -> Dictionary:
	var doc := SessionStore.snapshot(game)
	doc["specks"] = []
	doc["blasts"] = []
	return SnapCodec.plain(doc)


## Puts the simulation state `data` onto `game`, a Game just made for the
## same level (Game.new, never ticked): the players it lacks join, the save
## puts back the level's state, then every carried field is set. Presentation
## options stay as `game` had them. False when `data` is for another level.
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
	if SessionStore.restore_onto(data["save"], game) != game:
		return false
	_apply_enemies(game, codec, data)
	for slot: String in players:
		var p: Player = game.players[int(slot)]
		var row: Dictionary = players[slot]
		for name: String in row:
			codec.set_field(p, name, row[name])
	# The dictionaries the party shares are one object again (Players.SHARED).
	for name: String in Players.SHARED:
		if bool(Players.SHARED[name]):
			for p: Player in game.players:
				p.set(name, game.players[0].get(name))
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
	var statics: Dictionary = data.get("statics", {})
	var derby = codec.decode(statics.get("derby", {}))
	if derby is Dictionary:
		DerbyChamp.state.merge(derby, true)
	# Caches keyed on what changed underneath them start over.
	game.shelter_key = Vector2i(-1, -1)
	game.route_sig = []
	game.player = null
	game.focus(local)
	return true


## The enemies in the snapshot's order: each one the game has at that place
## (the level's own, then a posse or backup the save brought back) or a new
## one, every carried field set; uids map for the references.
static func _apply_enemies(game, codec: SnapCodec, data: Dictionary) -> void:
	var rows: Dictionary = data["enemies"]
	var order: Array = data["order"]
	var list: Array = []
	var ids: Array = []
	for i in order.size():
		var row: Dictionary = rows[str(order[i])]
		var e: Enemy = null
		if i < game.enemies.size() and game.enemies[i].kind == String(row["kind"]):
			e = game.enemies[i]
		else:
			e = Enemy.new(String(row["kind"]), float(row["x"]), float(row["y"]))
		list.append(e)
		codec.by_uid[int(order[i])] = e
		if String(row["@id"]) != "":
			ids.append(String(row["@id"]))
	game.enemies.assign(list)
	game.enemy_ids.assign(ids)
	for i in order.size():
		var row: Dictionary = rows[str(order[i])]
		for name: String in row:
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
## carries its new value, a key gone is listed under "@gone", the keys' order
## under "@order" when it is not base's with new keys after); anything else
## that differs is carried whole. patch(base, delta(base, now)) == now.
static func delta(base, now):
	if not (base is Dictionary and now is Dictionary):
		return {"@new": now}
	var out := {}
	var gone: Array = []
	for key in base:
		if not now.has(key):
			gone.append(key)
	for key in now:
		if not base.has(key):
			out[key] = {"@new": now[key]}
		elif var_to_bytes(base[key]) != var_to_bytes(now[key]):
			out[key] = delta(base[key], now[key])
	if not gone.is_empty():
		out["@gone"] = gone
	var expected: Array = []
	for key in base:
		if now.has(key):
			expected.append(key)
	for key in now:
		if not base.has(key):
			expected.append(key)
	if var_to_bytes(expected) != var_to_bytes(now.keys()):
		out["@order"] = now.keys()
	return out


## `base` with `change` (a delta()) laid over it, as a new snapshot.
static func patch(base, change):
	if change is Dictionary and change.has("@new"):
		return change["@new"]
	var out: Dictionary = base.duplicate() if base is Dictionary else {}
	for key in change:
		if typeof(key) == TYPE_STRING and key == "@gone":
			for gone in change[key]:
				out.erase(gone)
		elif not (typeof(key) == TYPE_STRING and key == "@order"):
			out[key] = patch(out.get(key), change[key])
	if change.has("@order"):
		var ordered := {}
		for key in change["@order"]:
			ordered[key] = out[key]
		return ordered
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
