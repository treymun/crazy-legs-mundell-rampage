## Loading a save, moved out of session_store.gd: a checkpoint or save slot
## read back into a Game (read(), with the chapters it retains; restore();
## restore_onto() for GameSnapshot.apply), with the same defensive checks
## (every value's type, range and place; a failure names its line in
## SessionStore.last_error). The format and the writing side stay in
## SessionStore (VERSION, the field lists, snapshot(), save()), which hands
## read(), restore() and restore_onto() on to these.
class_name SaveRestore
extends RefCounted


static func _assign(obj: Object, key: String, value: Variant) -> bool:
	var before: Variant = obj.get(key)
	if before == null:
		if value != null:
			var pair: Array = value if value is Array else []
			if not (
				value is Array
				and pair.size() == 2
				and SessionStore._number(pair[0])
				and SessionStore._number(pair[1])
			):
				return false
			obj.set(key, [SessionStore._float(pair[0]), SessionStore._float(pair[1])])
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
			if (
				not SessionStore._number(value)
				or SessionStore._float(value) != floor(SessionStore._float(value))
			):
				return false
			obj.set(key, SessionStore._int(value))
		TYPE_FLOAT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not SessionStore._number(value):
				return false
			obj.set(key, SessionStore._float(value))
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
					if SessionStore._float(item) != floor(SessionStore._float(item)):
						return false
			live.clear()
			for item: Variant in items:
				live.append(item if want_bool else SessionStore._int(item))
		_:
			return false
	return true


static func _restore_fields(obj: Object, values: Variant, keys: Array) -> bool:
	if not (values is Dictionary):
		SessionStore.last_error = "fields not a dictionary"
		return false
	var fields: Dictionary = values
	for key: String in keys:
		if not fields.has(key):
			SessionStore.last_error = "missing field " + key
			return false
		if not _assign(obj, key, fields[key]):
			SessionStore.last_error = (
				"bad field %s (%s=%s)"
				% [key, type_string(typeof(fields[key])), str(fields[key]).substr(0, 40)]
			)
			return false
	return true


static func valid_position(world: LevelData, x: Variant, y: Variant) -> bool:
	return (
		SessionStore._number(x)
		and SessionStore._number(y)
		and SessionStore._float(x) >= 0.0
		and SessionStore._float(y) >= 0.0
		and SessionStore._float(x) < float(world.width)
		and SessionStore._float(y) < float(world.height)
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
			if obj is GameState.Shot and key in ["attack_gun", "attack_landed"]:
				continue
			if key == "kind":
				obj.set("kind", str(fields[key]))
			elif key == "enemy" or key == "resting":
				if typeof(fields[key]) != TYPE_BOOL:
					return []
				obj.set(key, fields[key])
			else:
				if typeof(fields[key]) != TYPE_INT and typeof(fields[key]) != TYPE_FLOAT:
					return []
				obj.set(key, SessionStore._float(fields[key]))
		if obj is GameState.Shot:
			var shot: GameState.Shot = obj
			var gun: Variant = fields.get("attack_gun", -1)
			var landed: Variant = fields.get("attack_landed", false)
			if not SessionStore._number(gun) or not (landed is bool):
				return []
			var source := SessionStore._int(gun)
			if source >= 0 and source < Weapons.COUNT:
				shot.attack = GameState.Attack.new(source)
				shot.attack.landed = landed
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
	if not (
		SessionStore._int(fields["health"]) >= 1 and SessionStore._int(fields["health"]) <= 100
	):
		return false
	if not owned[0]:
		return false
	if not owned[SessionStore._int(fields["active"])]:
		return false
	for i in owned.size():
		if (
			SessionStore._int(loaded[i]) < 0
			or SessionStore._int(loaded[i]) > Weapons.SAVED_CAPACITY[i]
		):
			return false
		if (
			SessionStore._int(reserve[i]) < 0
			or SessionStore._int(reserve[i]) > Weapons.MAX_RESERVE[i]
		):
			return false
	var inventory: Dictionary = fields["inventory"]
	if inventory.size() != HUD.ITEMS.size():
		return false
	for name: String in HUD.ITEMS:
		if not inventory.has(name):
			return false
		var amount := SessionStore._int(inventory[name])
		if amount < 0 or amount > 5:
			return false
	return true


## Returns a restored Game or null (with a warning) when the file is unusable.
static func read(
	path: String,
	make_game: Callable,
	expected_replay: Variant = null,
	expected_level: Variant = null
) -> Game:
	path = SessionStore.readable_path(path)
	if not FileAccess.file_exists(path):
		return SessionStore._fail_at(646)
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > SessionStore.MAX_BYTES:
		push_warning("checkpoint too large")
		return SessionStore._fail_at(650)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		push_warning("checkpoint is not an object")
		return SessionStore._fail_at(654)
	var doc := SessionStore._upgraded(parsed)
	if doc.is_empty():
		push_warning("unsupported checkpoint version")
		return SessionStore._fail_at(657)
	var game := restore(doc, make_game, expected_replay)
	if game == null:
		return SessionStore._fail_at(660)
	if (
		expected_level != null
		and str(expected_level) != ""
		and game.level.id != str(expected_level)
	):
		return SessionStore._fail_at(662)
	var retained: Variant = doc.get("retained", {})
	if retained is Dictionary and not game.replay:
		var previous: Array = []
		var index := Campaign.ORDER.find(game.level.id)
		if index > 0:
			previous = Campaign.ORDER.slice(0, index)
		for key: Variant in retained:
			if not previous.has(str(key)):
				return SessionStore._fail_at(671)
			var chapter_doc: Variant = retained[key]
			if not (chapter_doc is Dictionary):
				return SessionStore._fail_at(674)
			var chapter_fields: Dictionary = chapter_doc
			if SessionStore._int(chapter_fields.get("version", 0)) != SessionStore.VERSION:
				return SessionStore._fail_at(676)  # upgrade() brought every chapter up to VERSION
			if str(chapter_fields.get("level", "")) != str(key):
				return SessionStore._fail_at(678)
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
				return SessionStore._fail_at(681)
			game.retained[str(key)] = chapter
	return game


static func restore(doc: Dictionary, make_game: Callable, expected_replay: Variant = null) -> Game:
	var level_id := str(doc.get("level", ""))
	if not Campaign.ORDER.has(level_id):
		return SessionStore._fail_at(689)
	var game: Game = make_game.call(level_id)
	if game == null or game.level.id != level_id:
		return SessionStore._fail_at(692)
	if SessionStore._int(doc.get("layout", 1)) != game.level.layout:
		return _restart(doc, game, expected_replay)
	return restore_onto(doc, game, expected_replay)


## restore() onto `game`, a Game just made for the save's level and layout
## (GameSnapshot.apply uses it): the game back, or null when the save is bad.
static func restore_onto(doc: Dictionary, game: Game, expected_replay: Variant = null) -> Game:
	var w := game.world
	if not _restore_fields(game, doc.get("game", {}), SessionStore.GAME_FIELDS):
		return SessionStore._fail_at(695)
	var reward: Variant = doc.get("county_gallery", false)
	if typeof(reward) != TYPE_BOOL:
		return SessionStore._fail_at(698)
	if game.gallery != null:
		game.gallery.rewarded = reward
	elif reward:
		return SessionStore._fail_at(702)
	var supplies := SessionStore._int(doc.get("county_supplies", 0))
	if supplies < 0 or supplies > 2:
		return SessionStore._fail_at(705)
	game.supply_rule = supplies
	if not _restore_fields(game.player, doc.get("player", {}), SessionStore.PLAYER_FIELDS):
		return SessionStore._fail_at(708)
	if not _restore_armory(game, doc):
		return null
	if game.clock < 0.0 or game.player.health <= 0 or game.player.health > 100:
		return SessionStore._fail_at(712)
	if game.inventory_slot < 0 or game.inventory_slot >= HUD.ITEMS.size():
		return SessionStore._fail_at(714)
	if not valid_position(w, game.player.x, game.player.y):
		return SessionStore._fail_at(716)
	if game.district < 0 or game.district >= game.level.districts.size():
		return SessionStore._fail_at(718)
	# Kills can pass the level's own count: posse partners, a boss's backup and
	# Maw's crew join later (features/posse.gd counts them once they are back).
	if game.kills < 0 or game.kills > game.total_kills + 2000:
		return SessionStore._fail_at(720)
	if game.secrets < 0 or game.secrets > game.total_secrets:
		return SessionStore._fail_at(722)
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
	if not _restore_fields(game.armory, armory_doc, SessionStore.ARM_FIELDS):
		SessionStore._fail_at(710)
		return false
	return _restore_bench(game, armory_doc)


## The junk bench's scrap and mods (version 10): a mod no longer in
## bench.cfg is dropped, the scrap kept to what a player may carry.
static func _restore_bench(game: Game, armory_doc: Variant) -> bool:
	var fields: Dictionary = armory_doc if armory_doc is Dictionary else {}
	var scrap: Variant = fields.get("scrap", 0)
	if not SessionStore._number(scrap) or SessionStore._int(scrap) < 0:
		SessionStore._fail_at(711)
		return false
	var most: int = BenchMods.value("scrap", "most", 99)
	game.armory.scrap = mini(most, SessionStore._int(scrap))
	var saved: Variant = fields.get("mods", [])
	if not (saved is Array):
		SessionStore._fail_at(711)
		return false
	var list: Array = saved
	var kept: Array[String] = []
	for id: Variant in list:
		var text := str(id)
		if not BenchMods.mod(text).is_empty() and not kept.has(text):
			kept.append(text)
	kept.sort()
	game.armory.mods = kept
	return true


static func _check_armory(game: Game) -> bool:
	if game.armory.active < 0 or game.armory.active >= Weapons.COUNT:
		SessionStore._fail_at(724)
		return false
	if not game.armory.owned[game.armory.active]:
		SessionStore._fail_at(726)
		return false
	for i in Weapons.COUNT:
		if game.armory.loaded[i] < 0 or game.armory.loaded[i] > Weapons.SAVED_CAPACITY[i]:
			SessionStore._fail_at(729)
			return false
		# (a mod may let a gun carry more: the drum mag)
		var modded: float = BenchMods.firing(i, game.armory.mods).get("max_reserve", 0)
		var base_most: int = Weapons.MAX_RESERVE[i]
		var most: int = maxi(base_most, roundi(modded))
		if game.armory.reserve[i] < 0 or game.armory.reserve[i] > most:
			SessionStore._fail_at(731)
			return false
	return true


## A save of a level that has been rebuilt since (its layout is older): the
## chapter starts over on the new map, with the guns, ammunition, health and
## pockets as saved and the campaign so far. Keys and the map's state go.
static func _restart(doc: Dictionary, game: Game, expected_replay: Variant) -> Game:
	var supplies := SessionStore._int(doc.get("county_supplies", 0))
	if supplies < 0 or supplies > 2:
		return SessionStore._fail_at(705)
	game.supply_rule = supplies
	var player_doc: Dictionary = doc.get("player", {})
	var health: Variant = player_doc.get("health")
	if (
		not SessionStore._number(health)
		or SessionStore._int(health) <= 0
		or SessionStore._int(health) > 100
	):
		return SessionStore._fail_at(712)
	game.player.health = SessionStore._int(health)
	if not _restore_armory(game, doc) or not _check_armory(game):
		return null
	if not _restore_campaign(doc, game, expected_replay):
		return null
	if not _restore_inventory(doc, game):
		return null
	var game_doc: Dictionary = doc.get("game", {})
	var slot: Variant = game_doc.get("inventory_slot", 0)
	game.inventory_slot = clampi(
		SessionStore._int(slot) if SessionStore._number(slot) else 0, 0, HUD.ITEMS.size() - 1
	)
	game.music_bookmark = null
	game.layout_restarted = true
	game.message("%s HAS BEEN REBUILT. THE CHAPTER STARTS OVER." % game.level.title, 5.0)
	game.configure({})
	return game


static func _restore_campaign(doc: Dictionary, game: Game, expected_replay: Variant) -> bool:
	var campaign: Dictionary = doc.get("campaign", {})
	if typeof(campaign.get("replay", false)) != TYPE_BOOL:
		SessionStore._fail_at(813)
		return false
	game.replay = campaign["replay"]
	if expected_replay != null and game.replay != SessionStore._bool(expected_replay):
		SessionStore._fail_at(816)
		return false
	if not _validate_kit(campaign.get("entry")):
		game.entry = _normalise_kit(campaign.get("entry"))
		if game.entry.is_empty():
			SessionStore._fail_at(820)
			return false
	else:
		game.entry = _normalise_kit(campaign["entry"])
	var history: Variant = campaign.get("history", [])
	if not (history is Array):
		SessionStore._fail_at(825)
		return false
	# A player map (src/user_maps/) is no chapter: no history before it.
	var chapter := Campaign.ORDER.find(game.level.id)
	var expected_history := 0 if game.replay or chapter < 0 else chapter
	if _count(history) != expected_history:
		SessionStore._fail_at(828)
		return false
	var clean_history: Array = []
	for row: Variant in history:
		if not (row is Array) or _count(row) != 6:
			SessionStore._fail_at(832)
			return false
		var clean: Array = [str(row[0])]
		for k in range(1, 6):
			clean.append(SessionStore._int(row[k]))
		clean_history.append(clean)
	game.history = clean_history
	return true


static func _restore_inventory(doc: Dictionary, game: Game) -> bool:
	var inventory: Variant = doc.get("inventory", {})
	if not (inventory is Dictionary) or _count(inventory) != HUD.ITEMS.size():
		SessionStore._fail_at(899)
		return false
	var items: Dictionary = inventory
	game.inventory = {}
	for name: String in HUD.ITEMS:
		if not items.has(name):
			SessionStore._fail_at(903)
			return false
		var amount := SessionStore._int(items[name])
		if amount < 0 or amount > 5:
			SessionStore._fail_at(906)
			return false
		game.inventory[name] = amount
	return true


static func _restore_rest(doc: Dictionary, game: Game, expected_replay: Variant) -> Game:
	var w := game.world
	# doors
	var doors_doc: Variant = doc.get("doors", {})
	if not (doors_doc is Dictionary):
		return SessionStore._fail_at(736)
	var expected_doors := {}
	for door: LevelData.Door in w.doors:
		expected_doors[SessionStore._door_key(door)] = door
	# Doors or enemies that no longer match the level's: it was changed since
	# without a new layout number. The chapter starts over rather than the save
	# being lost.
	if _count(doors_doc) != expected_doors.size():
		return _restart(doc, game, expected_replay)
	for key: Variant in doors_doc:
		if not expected_doors.has(key):
			return _restart(doc, game, expected_replay)
		var door: LevelData.Door = expected_doors[key]
		if not _restore_fields(door, doors_doc[key], SessionStore.DOOR_FIELDS):
			return SessionStore._fail_at(747)
		if door.progress < 0.0 or door.progress > 1.0:
			return SessionStore._fail_at(749)

	# enemies
	var enemies_doc: Variant = doc.get("enemies", {})
	var ai_doc: Variant = doc.get("ai", {})
	if not (enemies_doc is Dictionary) or not (ai_doc is Dictionary):
		return SessionStore._fail_at(755)
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
		if not _restore_fields(enemy, enemies_doc[key], SessionStore.ENEMY_FIELDS):
			return SessionStore._fail_at(766)
		if not valid_position(w, enemy.x, enemy.y):
			return SessionStore._fail_at(768)
		var ai: Dictionary = ai_doc[key]
		if not _restore_fields(enemy, ai, SessionStore.AI_FIELDS + SessionStore.COMBAT_FIELDS):
			return SessionStore._fail_at(771)
		if enemy.route_slot < 0 or enemy.route_slot >= maxi(1, enemy.route.size()):
			return SessionStore._fail_at(773)
		if enemy.volley < 0 or enemy.volley > 5:
			return SessionStore._fail_at(775)
		if enemy.pressure_guard < 0.0 or enemy.pressure_guard > 1.75:
			return SessionStore._fail_at(777)
		var aim: Variant = ai.get("aim")
		if aim == null:
			enemy.aim_mark = null
		elif (
			aim is Array
			and _count(aim) == 3
			and SessionStore._number(aim[0])
			and SessionStore._number(aim[1])
			and SessionStore._number(aim[2])
		):
			enemy.aim_mark = [
				SessionStore._float(aim[0]),
				SessionStore._float(aim[1]),
				SessionStore._float(aim[2])
			]
		else:
			return SessionStore._fail_at(784)
		if enemy.windup > 0.0 and enemy.aim_mark == null:
			return SessionStore._fail_at(786)
	if seen.size() != game.enemy_ids.size():
		return SessionStore._fail_at(788)

	# reactions
	var reactions: Variant = doc.get("county_reactions", {})
	if not (reactions is Dictionary):
		return SessionStore._fail_at(793)
	for key: Variant in reactions:
		var index := game.enemy_ids.find(str(key))
		if index < 0:
			return SessionStore._fail_at(797)
		var row: Variant = reactions[key]
		if not (row is Array) or _count(row) != 3 or typeof(row[2]) != TYPE_BOOL:
			return SessionStore._fail_at(800)
		var enemy: Enemy = game.enemies[index]
		enemy.heard = _state(row[0], 4, w, game.clock)
		if row[0] != null and enemy.heard == null:
			return SessionStore._fail_at(804)
		enemy.retreat = _state(row[1], 3, w, game.clock)
		if row[1] != null and enemy.retreat == null:
			return SessionStore._fail_at(807)
		enemy.responded = row[2]
		if enemy.heard != null and enemy.heard[2] > enemy.heard[3]:
			return SessionStore._fail_at(808)
		# A retreat without `responded` is play now: a hand clear of lit
		# dynamite or of a barn creaking down (features/set_pieces.gd) runs
		# without the once-only fall-back, and one far off and asleep keeps it.
		# (Python's check refused such a save, and with it every later save
		# of the campaign that kept the chapter.)

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
		return SessionStore._fail_at(842)
	game.stations_done = {}
	for name: Variant in stations:
		if typeof(name) != TYPE_STRING:
			return SessionStore._fail_at(846)
		game.stations_done[str(name)] = true
	var known_stations := {}
	for station: LevelData.Station in w.stations:
		known_stations[station.id] = true
	for name: Variant in game.stations_done:
		if not known_stations.has(name):
			return SessionStore._fail_at(849)
	for station: LevelData.Station in w.stations:
		if game.stations_done.has(station.id):
			for required: Variant in station.requires:
				if not game.stations_done.has(str(required)):
					return SessionStore._fail_at(852)
			# A finished station keeps its sectors lit after a load, as it does
			# in the reference (session_store.py re-applies the +0.26).
			game.set_station_lights(station)
	var tasks: Variant = doc.get("tasks", [])
	var scenery: Variant = doc.get("scenery", [])
	var heard: Variant = doc.get("heard", [])
	for row: Variant in [tasks, scenery, heard]:
		if not (row is Array):
			return SessionStore._fail_at(858)
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
		return SessionStore._fail_at(870)
	game.valve_turns = {}
	for key: Variant in turns:
		game.valve_turns[str(key)] = SessionStore._int(turns[key])

	# entities
	var shot_rows: Variant = doc.get("shots", [])
	var speck_rows: Variant = doc.get("specks", [])
	var blast_rows: Variant = doc.get("blasts", [])
	var hazard_rows: Variant = doc.get("hazards", [])
	game.shots = _restore_list(
		shot_rows, func() -> Game.Shot: return Game.Shot.new(), SessionStore.SHOT_KINDS, 240
	)
	if game.shots.size() != _count(shot_rows):
		return SessionStore._fail_at(882)
	game.specks = _restore_list(
		speck_rows, func() -> Game.Speck: return Game.Speck.new(), SessionStore.SPECK_KINDS, 4000
	)
	if game.specks.size() != _count(speck_rows):
		return SessionStore._fail_at(885)
	game.blasts = _restore_list(
		blast_rows, func() -> Game.Blast: return Game.Blast.new(), ["energy", "fire"], 80
	)
	if game.blasts.size() != _count(blast_rows):
		return SessionStore._fail_at(888)
	game.hazards = _restore_list(
		hazard_rows, func() -> Game.Hazard: return Game.Hazard.new(), ["steam", "chalk"], 7
	)
	if game.hazards.size() != _count(hazard_rows):
		return SessionStore._fail_at(891)
	for shot: Game.Shot in game.shots:
		if not valid_position(w, shot.x, shot.y):
			return SessionStore._fail_at(895)
		if shot.slot < 0 or shot.slot >= game.players.size():
			shot.slot = 0
	for speck: Game.Speck in game.specks:
		if not valid_position(w, speck.x, speck.y):
			return SessionStore._fail_at(895)
	for blast: Game.Blast in game.blasts:
		if not valid_position(w, blast.x, blast.y):
			return SessionStore._fail_at(895)

	if not _restore_inventory(doc, game):
		return null

	var key_rows: Variant = doc.get("keys", [])
	if not (key_rows is Array):
		return SessionStore._fail_at(911)
	game.keys = {}
	for key: Variant in key_rows:
		if key != "key_brass" and key != "key_steel":
			return SessionStore._fail_at(915)
		game.keys[str(key)] = true

	var drums: Variant = doc.get("drums", [])
	if not (drums is Array):
		return SessionStore._fail_at(920)
	game.drums = {}
	for row: Variant in drums:
		if not (row is Array) or _count(row) != 3:
			return SessionStore._fail_at(924)
		game.drums[Vector2(SessionStore._float(row[0]), SessionStore._float(row[1]))] = (
			SessionStore._int(row[2])
		)

	var pickups: Variant = doc.get("pickups", [])
	if not (pickups is Array):
		return SessionStore._fail_at(929)
	game.pickups = []
	for row: Variant in pickups:
		if not (row is Array) or (_count(row) != 3 and _count(row) != 4):
			return SessionStore._fail_at(933)
		if not valid_position(w, row[1], row[2]):
			return SessionStore._fail_at(935)
		game.add_pickup(
			str(row[0]),
			SessionStore._float(row[1]),
			SessionStore._float(row[2]),
			SessionStore._float(row[3]) if _count(row) > 3 else NAN
		)

	var visited: Variant = doc.get("visited", [])
	if not (visited is Array):
		return SessionStore._fail_at(940)
	game.visited = {}
	for row: Variant in visited:
		if not (row is Array) or _count(row) != 2:
			return SessionStore._fail_at(944)
		if not valid_position(w, row[0], row[1]):
			return SessionStore._fail_at(946)
		game.visited[Vector2i(SessionStore._int(row[0]), SessionStore._int(row[1]))] = true

	var panes: Variant = doc.get("panes", [])
	if not (panes is Array):
		return SessionStore._fail_at(951)
	w.broken_panes = {}
	for row: Variant in panes:
		if not (row is Array) or _count(row) != 2:
			return SessionStore._fail_at(955)
		w.broken_panes[Vector2i(SessionStore._int(row[0]), SessionStore._int(row[1]))] = true

	var rng_value: Variant = doc.get("rng", null)
	if typeof(rng_value) != TYPE_INT and typeof(rng_value) != TYPE_FLOAT:
		return SessionStore._fail_at(960)
	game.rng.set_state(SessionStore._int(rng_value))

	# The loading-area wave is awake only once its shutdown station is done.
	if w.extraction != null:
		var shutdown := game.stations_done.has(w.extraction.shutdown)
		for enemy: Enemy in game.wave:
			enemy.dormant = not shutdown

	game.music_bookmark = doc.get("music", null)
	if not (game.music_bookmark is Dictionary or game.music_bookmark == null):
		return SessionStore._fail_at(971)
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
		return SessionStore._fail_at(984)
	var out: Array = []
	for item: Variant in value:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return SessionStore._fail_at(988)
		out.append(SessionStore._float(item))
	if not valid_position(world, out[0], out[1]):
		return SessionStore._fail_at(991)
	for i in range(2, out.size()):
		if out[i] < 0.0 or out[i] > clock + 3.0:
			return SessionStore._fail_at(993)
	return out


static func _normalise_kit(kit: Variant) -> Dictionary:
	if not (kit is Dictionary):
		return {}
	var fields: Dictionary = kit
	var out := {"health": SessionStore._int(fields.get("health", 100))}
	var owned: Array = []
	var loaded: Array = []
	var reserve: Array = []
	var src_owned: Array = fields.get("owned", [])
	var src_loaded: Array = fields.get("loaded", [])
	var src_reserve: Array = fields.get("reserve", [])
	for i in Weapons.COUNT:
		owned.append(
			SessionStore._bool(src_owned[i]) if i < src_owned.size() else i == Weapons.CROWBAR
		)
		loaded.append(SessionStore._int(src_loaded[i]) if i < src_loaded.size() else 0)
		reserve.append(SessionStore._int(src_reserve[i]) if i < src_reserve.size() else 0)
	out["owned"] = owned
	out["loaded"] = loaded
	out["reserve"] = reserve
	out["active"] = SessionStore._int(fields.get("active", 1))
	var inventory: Dictionary = fields.get("inventory", {})
	var clean_inv := {}
	for name: String in HUD.ITEMS:
		clean_inv[name] = SessionStore._int(inventory.get(name, 0))
	out["inventory"] = clean_inv
	out["slot"] = SessionStore._int(fields.get("slot", 0))
	# The junk bench's scrap and mods the chapter was entered with (version 10
	# on; a kit from before has none). Pass 15: they were left behind here, so
	# the chapter's start after any load (R on the death screen after a
	# quicksave, a retried fight or a trail marker) came without them.
	out["scrap"] = SessionStore._int(fields.get("scrap", 0))
	var mods: Array = []
	var src_mods: Variant = fields.get("mods", [])
	if src_mods is Array:
		var listed: Array = src_mods
		for id: Variant in listed:
			mods.append(str(id))
	out["mods"] = mods
	return out
