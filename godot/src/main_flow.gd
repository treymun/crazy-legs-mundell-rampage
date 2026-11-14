## The campaign (starting, travelling, the hub, checkpoints), save slots and
## the settings pages (the front-end layers are listed in main_state.gd).
class_name MainFlow
extends MainState


func start(
	level_id := "hickston", kit = null, history: Array = [], replay := false, supply_rule = null
) -> void:
	menu_note = ""
	var fresh := make_game(level_id)
	fresh.supply_rule = int(options["supply_rule"]) if supply_rule == null else int(supply_rule)
	fresh.replay = replay
	fresh.history = history
	if replay and kit == null and level_id != "hickston":
		fresh.armory.owned[Weapons.SHOTGUN] = true
		fresh.armory.owned[Weapons.RIFLE] = true
		fresh.armory.loaded[Weapons.SHOTGUN] = Weapons.CAPACITY[Weapons.SHOTGUN]
		fresh.armory.loaded[Weapons.RIFLE] = Weapons.CAPACITY[Weapons.RIFLE]
		fresh.armory.reserve[Weapons.SHOTGUN] = 16
		fresh.armory.reserve[Weapons.RIFLE] = 48
		fresh.armory.active = Weapons.SHOTGUN
		fresh.inventory["rinds"] = 2
		var bonus: Array = (
			{
				"fair": [Weapons.ROCKET, 3],
				"sawmill": [Weapons.BOWLING, 3],
				"quarry": [Weapons.COW, 3],
				"bayou": [Weapons.CROSSBOW, 6],
				"speedway": [Weapons.CROSSBOW, 6],
				"mothership": [Weapons.ARMGUN, 18],
			}
			. get(level_id, [Weapons.ROCKET, 3])
		)
		var new_weapon := int(bonus[0])
		fresh.armory.owned[new_weapon] = true
		fresh.armory.loaded[new_weapon] = Weapons.CAPACITY[new_weapon]
		fresh.armory.reserve[new_weapon] = int(bonus[1])
		for extra: Array in [[Weapons.TEAT, 60], [Weapons.KEG, 2]]:
			var slot := int(extra[0])
			fresh.armory.owned[slot] = true
			fresh.armory.loaded[slot] = Weapons.CAPACITY[slot]
			fresh.armory.reserve[slot] = int(extra[1])
	if kit != null:
		fresh.apply_loadout(kit)
	fresh.entry = fresh.loadout()
	play(fresh)


func play(target: Game) -> void:
	if not art.chapter_ready(target.level.id):
		waiting_play = target
		packs.want_first(String(CHAPTER_PACKS.get(CountyData.base_of(target.level.id), "")))
		notice("FETCHING THE CHAPTER. A MOMENT...", 4.0)
		return
	waiting_play = null
	CrashLog.note("play %s%s" % [target.level.id, " (replay)" if target.replay else ""])
	_take_mode(target)
	# Lessons are for players: tours, benches, smoke runs and demos must look the
	# same on every machine, whatever this profile was already taught.
	target.lessons = (
		view_tour == "" and view_bench == 0 and smoke_frames == 0 and not demo and not showcase
	)
	game = target
	var practice := target.level.id == RANGE_ID
	var rematch := BossRematch.active(target)
	if not practice:
		range_return = null
	if not rematch:
		rematch_return = null
	var chapter := not target.in_hub and not practice and not rematch and not target.revisiting
	chapter = chapter and not CountyMode.active(target)  # a COUNTY RUN is never the campaign
	if chapter and not target.replay:
		campaign_run = target
	if chapter and target.replay:
		replay_runs[target.level.id] = target
	if chapter:
		# A chapter under way: the other chapters' boss checkpoints go (boss_door.gd).
		BossDoor.clear_others(target.level.id, target.replay)
	target.configure(options if net == null else _net_options(net.match_info))
	target.tone = tone_table
	crouch_latched = target.player.crouched and int(options["crouch"]) != 0
	sound.pause_world()
	play_music()
	state = "play"
	block_fire = true
	grab(not target.showing_tally and not target.defeated())


## The game mode on a game about to be played (src/modes/): one started under
## --mode gets it and its partners, who bring their own kits from the game
## before; in co-op a partner far from player one (a retried fight, a loaded
## save) comes to them; each player not this machine's gets a pilot
## (tools/mode_bot.gd, project folder only). Nothing for the campaign.
func _take_mode(target: Game) -> void:
	var prior := game
	if mode_name != "" and mode_name != Modes.CAMPAIGN:
		if Modes.mode_of(target) == Modes.CAMPAIGN:
			Modes.setup(target, mode_name, mode_players, mode_options)
			if prior != null and prior != target and Modes.mode_of(prior) == mode_name:
				for i in range(1, mini(prior.players.size(), target.players.size())):
					Modes.carry(prior.players[i], target.players[i])
	if Modes.mode_of(target) == Modes.COOP:
		Modes.gather(target)
	pilots.clear()
	if Modes.is_tactical(target):
		# The 5v5 modes' own bots play everyone else, in any build.
		TacticalScreens.reset()
		TacticalScreens.human = target.local_player.slot
		TacticalScreens.footer = "" if net != null else "ENTER  REMATCH   /   ESC  TITLE"
		if net != null:
			# Online: the host's bots play the slots nobody does; a client's
			# copy plays what the host played.
			for slot: int in net.bot_slots():
				pilots[slot] = TacticalBot.new(slot)
			return
		target.local_player.name = String(options.get("player_name", "MUNDELL"))
		for p: Player in target.players:
			if p != target.local_player:
				pilots[p.slot] = TacticalBot.new(p.slot)
		return
	if target.players.size() < 2 or not DevConsole.available():
		return
	var script = load("res://tools/mode_bot.gd") if FileAccess.file_exists(BOT) else null
	if script == null:
		return
	for p: Player in target.players:
		if p != target.local_player:
			var pilot = script.new()
			pilot.as_controls = true
			pilots[p.slot] = pilot


## The title's 5V5 SHOWDOWN: the match picked there, this machine's player
## and four bots against five.
func start_showdown() -> void:
	var tag := posmod(showdown_mode, TacticalScreens.PICKER_MODES.size()) == 2
	mode_name = Modes.BOMB if tag else String(Modes.TACTICAL[posmod(showdown_mode, 2)])
	mode_players = Modes.TAGTEAM_PLAYERS if tag else Modes.MAX_PLAYERS
	var maps := TacticalScreens.picker_maps(showdown_mode)
	mode_options = {}
	if tag:
		mode_options = Modes.TAGTEAM_OPTIONS.duplicate()
	mode_options["arena"] = String(maps[posmod(showdown_map, maps.size())])
	mode_options["rounds"] = TacticalScreens.picker_rounds(showdown_mode, showdown_long)
	mode_options["store_rules"] = String(
		TacticalShop.RULE_IDS[posmod(showdown_rules, TacticalShop.RULE_IDS.size())]
	)
	showdown_on = true
	sound.play("menu_accept")
	start_match()


## Starts the versus match --mode asked for, in its arena (Modes.ARENAS).
func start_match() -> void:
	start(String(Modes.arena_of(String(mode_options.get("arena", "range")))[0]))


## COUNTY RUN on map `map_id` (src/modes/county_mode.gd): a fresh run, one
## player, never the campaign and never saved.
func start_county(map_id: String) -> void:
	mode_name = Modes.COUNTY
	mode_players = 1
	mode_options = {}
	showdown_on = true  # anything else from the title clears the mode again
	CountyScreens.reset()
	start(map_id)
	# Every run its own dice (the tools keep the game's fixed seed, to repeat).
	var run: Game = waiting_play if waiting_play != null else game
	if run != null:
		run.rng.set_state(int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFFFFFF)


## The COUNTY RUN map picker (state "county"); from a finished run the run
## is let go.
func open_county(from_run := false) -> void:
	if from_run:
		game = null
		menu_music()
		grab(false)
	state = "county"
	CountyScreens.reset()
	sound.play("menu_accept")


func open_hub(origin = null, message := "") -> void:
	if origin != null and not origin.in_hub:
		hub_origin = origin
		if not origin.replay and campaign_run != null:
			if not write_campaign(campaign_run, _entry_path()):
				message = "CROSSROADS OPEN. PROGRESS COULD NOT BE SAVED."
	var hub := make_game("hub")
	hub.in_hub = true
	hub.hub_findings = hub_findings
	hub.visited = hub_visited
	hub.world.locked_gates = []
	for gate: LevelData.Gate in hub.world.hub_gates:
		if not unlocked.has(gate.destination):
			hub.world.locked_gates.append(gate)
	for gate: LevelData.Gate in hub.world.hub_gates:
		var level_id := gate.destination
		if hub_origin != null and hub_origin.replay and hub_origin.level.id == level_id:
			hub.gate_modes[level_id] = "RESUME REPLAY"
		elif campaign_run != null and campaign_run.level.id == level_id:
			hub.gate_modes[level_id] = "REVISIT" if campaign_run.won else "CONTINUE"
		elif campaign_run != null and campaign_run.retained.has(level_id):
			hub.gate_modes[level_id] = "REVISIT"
		elif replay_runs.has(level_id):
			hub.gate_modes[level_id] = "RESUME REPLAY"
		elif campaign_run != null or level_id != "hickston":
			hub.gate_modes[level_id] = "REPLAY"
	var carried: Game = campaign_run if campaign_run != null else hub_origin
	if campaign_run != null:
		# Past the last dispatch the board stays on it (a new chapter may not have
		# its own line yet).
		hub.hub_milestone = mini(
			campaign_run.history.size() + (1 if campaign_run.won else 0),
			GameState.HUB_DISPATCH.size() - 1
		)
	if carried != null and carried.player.health > 0:
		hub.apply_loadout(carried.loadout())
	hub.player.x = float(hub.level.spawn[0])
	hub.player.y = float(hub.level.spawn[1])
	hub.player.angle = float(hub.level.spawn[2])
	hub.district = int(hub.world.area[hub.world.cell(hub.player.x, hub.player.y)])
	hub.message(message if message != "" else "COUNTY CROSSROADS. FACE A GATE AND PRESS E.", 4.5)
	play(hub)


func travel(destination: String) -> void:
	var current := game
	current.portal_request = ""
	if BossRematch.active(current):
		current.message("NO WAY OUT OF A REMATCH BUT THROUGH THE BOSS. ESC TO QUIT.", 3.0)
		return
	if destination == "hub":
		open_hub(current)
		return
	if not unlocked.has(destination):
		return
	var origin: Game = hub_origin
	var chapter: Game = null
	if campaign_run != null:
		if campaign_run.level.id == destination:
			chapter = campaign_run
		elif campaign_run.retained.has(destination):
			var held = campaign_run.retained[destination]
			if held is Game:
				chapter = held
	if origin != null and origin.replay and origin.level.id == destination and not origin.won:
		face_into_level(origin)
		play(origin)
	elif chapter != null:
		chapter.revisiting = chapter.won
		face_into_level(chapter)
		play(chapter)
	elif replay_runs.has(destination):
		var replay: Game = replay_runs[destination]
		face_into_level(replay)
		play(replay)
	else:
		start(destination, null, [], campaign_run != null or destination != "hickston", null)


func bookmark_campaign_audio(target: Game) -> void:
	var chapters: Array = [target]
	for key in target.retained:
		var chapter = target.retained[key]
		if chapter is Game:
			chapters.append(chapter)
	for chapter: Game in chapters:
		var bookmark = sound.bookmark_score(chapter.level.score)
		if bookmark != null:
			chapter.music_bookmark = bookmark


func write_campaign(target: Game, path: String) -> bool:
	bookmark_campaign_audio(target)
	return SessionStore.save(target, path)


func restore_campaign_audio(target: Game) -> void:
	var chapters: Array = [target]
	for key in target.retained:
		var chapter = target.retained[key]
		if chapter is Game:
			chapters.append(chapter)
	for chapter: Game in chapters:
		sound.restore_score(chapter.level.score, chapter.music_bookmark)


func resume_entry() -> void:
	if campaign_run != null:
		open_hub(campaign_run, "CAMPAIGN READY. USE YOUR CURRENT GATE.")
		return
	var loaded := SessionStore.read(_entry_path(), make_game, false)
	if loaded == null:
		notice("THE CAMPAIGN ENTRY COULD NOT BE LOADED.")
		return
	campaign_run = loaded
	restore_campaign_audio(loaded)
	var index := Campaign.ORDER.find(loaded.level.id)
	for i in index + 1:
		unlocked[Campaign.ORDER[i]] = true
	open_hub(loaded, "CAMPAIGN READY. USE YOUR NEXT GATE.")


func continue_campaign() -> void:
	var current := game
	if Modes.is_versus(current):
		start_match()  # another round in the same arena
		return
	if BossRematch.active(current):
		# A rematch never leads on into the campaign.
		if current.features["boss_rematch"].fell >= 0.0:
			finish_rematch()
		else:
			leave_rematch()
			return_to_title()
		return
	if current.replay:
		replay_runs.erase(current.level.id)
		if hub_origin == current:
			hub_origin = null
		return_to_title(true)
		return
	var following := Campaign.next_level(current.level.id)
	if following == "":
		open_hub(current, "THE SKY'S CLEAR. EVERY ROAD LEADS BACK TO A FINISHED CHAPTER.")
		return
	var history: Array = current.history.duplicate()
	history.append(current.result())
	start(following, current.loadout(), history, false, current.supply_rule)
	game.retained = current.retained.duplicate()
	game.retained[current.level.id] = current
	unlocked[following] = true
	var message := "GATE OPEN: " + Campaign.title_of(following)
	var merged := SessionStore.unlocks("")
	for key in merged:
		unlocked[key] = true
	if not SessionStore.save_unlocks("", unlocked):
		message = "GATE OPEN. UNLOCK COULD NOT BE SAVED."
	if int(options["classic"]) != 0:
		notice(message, 1.8)
		return
	open_hub(game, message)


func return_to_title(discard := false) -> void:
	if discard:
		game = null
	menu_music()
	state = "title"
	selection = 0
	sound.pause_world()
	grab(false)


## To the firing range from the title: the game paused there (if any) waits,
## untouched and unsaved, until the player leaves the range.
func open_range() -> void:
	if not in_range():
		range_return = game
	start(RANGE_ID)


## Off the range, back to the title with whatever was paused before it.
func leave_range() -> void:
	game = range_return
	range_return = null


## The rematch board (boss_rematch.gd), from the title.
func open_rematch_board() -> void:
	rematch_open = BossRematch.available(unlocked)
	rematch_bests = BossRematch.profile()["bests"]
	rematch_pick = posmod(rematch_pick, BossRematch.BOSSES.size())
	menu_note = ""
	state = "rematch"
	sound.pause_world()
	menu_music()
	grab(false)


## A rematch with `kind`; the game paused before it (if any) waits, untouched
## and unsaved, until the rematch is over. `board`: picked on the board, which
## only offers the bosses open to fight.
func start_rematch(kind: String, board := true) -> void:
	if board and not rematch_open.has(kind):
		sound.play("empty")
		menu_note = "BEAT %s TO GET A REMATCH." % Campaign.title_of(BossRematch.LEVEL_OF[kind])
		return
	var fight := BossRematch.build(make_game, kind)
	if fight == null:
		menu_note = "THAT FIGHT COULD NOT BE SET UP."
		return
	if not in_rematch():
		rematch_return = game
	var waiting := rematch_return
	menu_note = ""
	play(fight)
	rematch_return = waiting


## Out of the rematch: the game paused before it comes back (nothing of the
## rematch is kept).
func leave_rematch() -> void:
	game = rematch_return
	rematch_return = null


## The boss fell a moment ago: the time, its ribbon, the best kept.
func finish_rematch() -> void:
	var fight = game.features["boss_rematch"]
	var kind := String(fight.kind)
	var seconds: float = fight.seconds()
	var fresh := BossRematch.record(kind, seconds)
	rematch_result = {
		"kind": kind, "seconds": seconds, "best": BossRematch.best(kind), "fresh": fresh
	}
	leave_rematch()
	rematch_open = BossRematch.available(unlocked)
	rematch_bests = BossRematch.profile()["bests"]
	menu_note = ""
	state = "rematch_done"
	sound.pause_world()
	menu_music()
	sound.play("yee_haw")
	grab(false)


## Each frame in play: a rematch whose boss fell a moment ago ends.
func watch_rematch() -> void:
	if state == "play" and in_rematch() and game.features["boss_rematch"].finished():
		finish_rematch()


## The death screen's RETRY THE FIGHT: the boss checkpoint loaded, the player
## at the arena's door (boss_door.gd). The chapter's start when it cannot load.
func retry_fight() -> void:
	var current := game
	var loaded := BossDoor.restore(make_game, current)
	if loaded == null:
		restart_chapter(current)
		game.message("THE BOSS CHECKPOINT COULD NOT BE LOADED. THE CHAPTER STARTS OVER.", 4.0)
		return
	play(loaded)


## The death screen's retry: the chapter from its start, with the guns it was
## entered with.
func restart_chapter(target: Game) -> void:
	start(target.level.id, target.entry, target.history, target.replay, target.supply_rule)
	game.retained = target.retained


func menu_action() -> void:
	var rows := entries()
	var entry := rows[selection % rows.size()]
	menu_note = ""
	var staying := ["RESUME", "SAVE SLOTS", "SETUP", "CONTROLS", "CREDITS", "QUIT"]
	if in_range() and not entry in staying:
		# Anything that goes somewhere else leaves the range first, so nothing
		# from it (its guns least of all) is carried into the county.
		leave_range()
	if in_rematch() and not entry in staying:
		leave_rematch()  # likewise a rematch
	if showdown_on and not entry in ["RESUME", "SETUP", "CONTROLS", "CREDITS", "QUIT"]:
		# A 5v5 match was the game: what comes next is not one.
		showdown_on = false
		mode_name = ""
		mode_players = 1
		mode_options = {}
	if entry == "COUNTY RUN":
		open_county()
		return
	if entry == "MULTIPLAYER":
		state = "multi"
		net_note = ""
		sound.play("menu_accept")
		return
	if entry == "LEAVE RANGE":
		return_to_title()
		menu_note = "BACK FROM THE RANGE. NOTHING THERE WAS SAVED."
		return
	if entry == "FIRING RANGE":
		open_range()
		return
	if entry == "LEAVE REMATCH":
		return_to_title()
		menu_note = "BACK FROM THE REMATCH. NOTHING THERE WAS KEPT."
		return
	if entry == "BOSS REMATCH":
		open_rematch_board()
		return
	if entry == "RESUME":
		state = "play"
		play_music()
		grab(not game.showing_tally and not game.defeated())
	elif entry == "NEW GAME":
		BossDoor.clear_others("", false)
		start()
		if not SessionStore.save(game, _entry_path()):
			notice("CAMPAIGN ENTRY COULD NOT BE SAVED.")
	elif entry == "CONTINUE CAMPAIGN":
		resume_entry()
	elif entry == "COUNTY HUB":
		if game != null and game.armory.fuse > 0.0:
			notice("THROW THE LIT STICK BEFORE LEAVING.")
		else:
			open_hub(game)
	elif entry == "QUICKLOAD":
		load_game()
	elif entry == "REPLAY LEVEL":
		replay_selection = 0
		state = "replays"
	elif entry == "SAVE SLOTS":
		show_slots("load")
	elif entry == "SETUP" or entry == "CONTROLS" or entry == "CREDITS":
		state = entry.to_lower()
	else:
		get_tree().quit()


func save_game() -> void:
	var target := game
	var slot := current_slot()
	if target != null and target.in_hub:
		notice("ENTER A LEVEL TO QUICKSAVE.")
	elif target != null and target.level.id == RANGE_ID:
		notice("NO SAVING ON THE RANGE. IT'S ALL PRACTICE.")
	elif BossRematch.active(target):
		notice("NO SAVING IN A REMATCH. IT'S FOR THE RIBBON.")
	elif Modes.is_versus(target):
		notice("NO SAVING A MATCH. SETTLE IT.")
	elif CountyMode.active(target):
		notice("NO SAVING A COUNTY RUN. HOW LONG CAN YA LAST?")
	elif target == null or state != "play" or target.player.health <= 0 or target.showing_tally:
		notice("START A LIVE RUN TO SAVE.")
	elif target.armory.fuse > 0.0:
		notice("THROW THE LIT STICK BEFORE SAVING.")
	else:
		var source: Game = campaign_run if target.revisiting else target
		if not write_campaign(source, slot):
			notice("COULD NOT WRITE THE QUICKSAVE.")
		else:
			notice(
				(
					"CAMPAIGN SAVED. USE THE HUB TO REVISIT."
					if target.revisiting
					else "GAME SAVED. F9 TO LOAD."
				)
			)
			sound.play("menu_accept", .65)


func load_game() -> void:
	var slot := current_slot()
	if not FileAccess.file_exists(slot):
		notice("NO QUICKSAVE YET.")
		return
	var replay := slot != _save_path()
	load_checkpoint(slot, replay, game.level.id if replay and game != null else null)


func load_checkpoint(
	slot: String, replay: bool, level = null, label := "QUICKSAVE LOADED."
) -> void:
	var loaded := SessionStore.read(slot, make_game, replay, level)
	if loaded == null:
		notice("COULD NOT LOAD THAT SAVE. FILE PRESERVED.")
		return
	restore_campaign_audio(loaded)
	play(loaded)
	if not loaded.replay:
		var index := Campaign.ORDER.find(loaded.level.id)
		for i in index + 1:
			unlocked[Campaign.ORDER[i]] = true
	notice(label)
	sound.play("menu_accept", .65)


func show_slots(mode: String) -> void:
	slots_return = state
	slot_replay = game.level.id if game != null and game.replay else ""
	slot_mode = mode
	slot_index = 0
	slot_stage = "choose"
	slot_name = ""
	menu_note = ""
	state = "slots"
	sound.pause_world()
	menu_music()
	grab(false)
	refresh_slots()


func slot_commit() -> void:
	var source := slot_source()
	if source == null:
		menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."
		return
	var entry: Array = slots[slot_index]
	var path := String(entry[0])
	var digest = entry[1]
	var meta = entry[2]
	var name := slot_name.strip_edges()
	if name == "":
		name = String(meta[0]) if meta != null else "SLOT %d" % (slot_index + 1)
	bookmark_campaign_audio(source)
	if not SessionStore.save_named(source, path, name, digest):
		menu_note = "SAVE FAILED OR SLOT CHANGED. FILE PRESERVED."
	else:
		menu_note = "SAVED %s." % name
		sound.play("menu_accept")
	slot_stage = "choose"
	refresh_slots()


func key_slots(code: int) -> void:
	if slot_stage == "edit":
		if code == KEY_BACKSPACE:
			slot_name = slot_name.substr(0, maxi(0, slot_name.length() - 1))
		elif code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER:
			_text_input(false)
			slot_stage = "choose"
			if code != KEY_ESCAPE:
				if slots[slot_index][2] != null:
					slot_stage = "overwrite"
				else:
					slot_commit()
		return
	if slot_stage == "overwrite":
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			slot_commit()
		elif code == KEY_ESCAPE:
			slot_stage = "choose"
		return
	if code == KEY_ESCAPE:
		state = slots_return
		menu_note = ""
		sound.play("menu_back")
		if state == "play":
			play_music()
			block_fire = true
			grab(not game.defeated() and not game.showing_tally)
	elif code in [KEY_TAB, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN]:
		if key_echo:
			return
		slot_mode = "save" if slot_mode == "load" else "load"
		menu_note = ""
		sound.play("menu_move")
	elif code in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]:
		var step := 1 if code == KEY_DOWN or code == KEY_S else -1
		if key_echo and slot_index + step != posmod(slot_index + step, slots.size()):
			return
		slot_index = posmod(slot_index + step, slots.size())
		menu_note = ""
		sound.play("menu_move")
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		var entry: Array = slots[slot_index]
		var digest = entry[1]
		var meta = entry[2]
		if digest is String and String(digest) == "":
			menu_note = "UNREADABLE OR INCOMPATIBLE SLOT. FILE PRESERVED."
		elif slot_mode == "load":
			if meta != null:
				load_checkpoint(
					String(entry[0]), slot_replay != "", slot_replay, "NAMED SAVE LOADED."
				)
			else:
				menu_note = "THAT SLOT IS EMPTY."
		elif slot_source() != null:
			slot_name = ""
			slot_stage = "edit"
			menu_note = ""
			_text_input(true)
		else:
			menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."


func adjust_setting(direction: int) -> void:
	var item: SessionStore.Setting = option_items()[option_slot]
	change_setting(item.adjust(int(options[item.key]), direction))


## Give the picked setting a value: a step from the arrows, or a point on a
## level setting's bar (main_input.gd).
func change_setting(value: int) -> void:
	var items := option_items()
	var item: SessionStore.Setting = items[option_slot]
	var before := int(options[item.key])
	options[item.key] = clampi(value, item.low, item.high)
	if int(options[item.key]) == before:
		if drag_mode == "":
			sound.play("empty")  # already at the end of its range
		return
	reset_armed = 0.0
	menu_note = ""
	if item.key == "crouch":
		crouch_latched = false
	if item.key == "menu_music":
		menu_music()
	if item.key == "window_mode":
		change_window_mode(int(options["window_mode"]))
	if (item.key == "window_mode" or item.key == "aspect") and not smoke:
		# A display change is on trial until it is confirmed, so a mode that
		# cannot be read is never the one that gets saved.
		if display_trial.is_empty() or String(display_trial["key"]) != item.key:
			display_trial = {"key": item.key, "previous": before, "left": 10.0}
		else:
			display_trial["left"] = 10.0
		apply_options()
		sound.play("menu_move")
		return
	apply_options()
	if AUDIO_PREVIEW.has(item.key):
		sound.preview(String(AUDIO_PREVIEW[item.key]))
	else:
		sound.play("menu_move")
	persist_options()
	if menu_note == "":
		# Said where the hint goes: it took, and it is kept for next time.
		menu_note = (
			"%s: %s. APPLIED AND SAVED." % [item.label, item.format_value(options[item.key])]
		)
		if item.key == "detail":
			menu_note = _detail_note(int(options[item.key]))


## What each VIEW DETAIL draws, once it is picked.
func _detail_note(detail: int) -> String:
	if web and not OS.has_feature("threads") and detail != 1:
		return "VIEW DETAIL SAVED, BUT THIS BROWSER DRAWS LOW: IT RUNS THE VIEW ON ONE CORE."
	if detail == 3 and (cpu_view or not gpu_ready):
		return "VIEW DETAIL HD SAVED. HD NEEDS THE GRAPHICS-CARD VIEW, WHICH IS OFF HERE: HIGH."
	var said: Array[String] = [
		"VIEW DETAIL HIGH: 320 PIXELS WIDE, AS THE GAME WAS MADE.",
		"VIEW DETAIL LOW: HALF AS WIDE AND TALL, FOR SLOW MACHINES.",
		"VIEW DETAIL AUTO: HIGH, DROPPING TO LOW ONLY WHILE FRAMES RUN LATE.",
		"VIEW DETAIL HD: 640 PIXELS WIDE, TWICE AS SHARP. THE GUN AND STATUS BAR STAY 320."
	]
	return said[clampi(detail, 0, 3)] + " APPLIED AND SAVED."


## Keep (true) or undo (false) the display change that is on trial.
func settle_display(keep: bool) -> void:
	if display_trial.is_empty():
		return
	var key := String(display_trial["key"])
	if not keep:
		options[key] = int(display_trial["previous"])
		if key == "window_mode":
			change_window_mode(int(options[key]))
		apply_options()
		menu_note = "DISPLAY CHANGE UNDONE."
	display_trial = {}
	persist_options()
	sound.play("menu_accept" if keep else "menu_back")


## Reset only the page on screen, and only on the second press.
func reset_page() -> void:
	var page_name := String(SessionStore.setup_pages()[option_page][0])
	if reset_armed <= 0.0:
		reset_armed = 3.0
		menu_note = "RESET THE %s PAGE TO DEFAULTS? PRESS AGAIN." % page_name
		sound.play("menu_move")
		return
	reset_armed = 0.0
	for raw in option_items():
		var item: SessionStore.Setting = raw
		options[item.key] = item.default_value
		if item.key == "window_mode" and fullscreen and not mobile:
			change_window_mode(0)
	crouch_latched = false
	display_trial = {}
	apply_options()
	menu_music()
	persist_options()
	menu_note = "%s PAGE RESET." % page_name
	sound.play("menu_accept")


func setup_page(step: int) -> void:
	settle_display(false)
	option_page = posmod(option_page + step, SessionStore.setup_pages().size())
	option_slot = 0
	option_scroll = 0
	menu_note = ""
	reset_armed = 0.0
	binding_action = ""
	sound.play("menu_move")


func setup_select(slot: int) -> void:
	var count := option_items().size()
	slot = posmod(slot, count)
	if slot != option_slot:
		option_slot = slot
		menu_note = ""
		reset_armed = 0.0
		sound.play("menu_move")
	option_scroll = Menu.scroll_for(option_page, option_slot, option_scroll)


## Move the list's window (wheel, drag, scroll buttons, groove) without
## dragging it back to the picked row: the pick follows into the window.
func setup_scroll_to(scroll: int) -> void:
	var target := clampi(scroll, 0, Menu.max_scroll(option_page))
	if target == option_scroll:
		return
	option_scroll = target
	var slot := Menu.slot_in_view(option_page, option_slot, option_scroll)
	if slot != option_slot:
		option_slot = slot
		menu_note = ""
		reset_armed = 0.0
	option_scroll = Menu.scroll_for(option_page, option_slot, option_scroll)


## Leave a sub-screen for the title, with the cursor where it was.
func back_to_title() -> void:
	settle_display(false)
	sound.stop_preview()
	menu_note = ""
	reset_armed = 0.0
	state = "title"
	sound.play("menu_back")


func toggle_fullscreen() -> void:
	var mode := 0 if fullscreen else fullscreen_mode
	change_window_mode(mode)
	options["window_mode"] = mode
	persist_options()


# -------------------------------------------------------------------- keys


## Load the playing level again from its file, the player kept where they
## stand (the level editor and a changed level file use this).
func reload_level_in_place() -> void:
	if game == null:
		return
	var p := game.player
	var keep := [p.x, p.y, p.angle, p.pitch]
	start(game.level.id)
	p = game.player
	p.x = keep[0]
	p.y = keep[1]
	p.angle = keep[2]
	p.pitch = keep[3]
	p.eye = .95 + game.world.stand(p)
	level_stamp = FileAccess.get_modified_time(LevelEdit.path_of(game.level.id))
	level_stamp_of = game.level.id


# -------------------------------------------------------------------- online


## The HOST ONLINE (or JOIN ONLINE) form, filled from what was used last.
func open_net_form(hosting: bool) -> void:
	var last := NetPlay.remembered()
	var name := String(last.get("name", options.get("player_name", "MUNDELL")))
	net_form = {
		"name": name,
		"lobby_name": String(last.get("lobby_name", "%s'S LOBBY" % NetPlay.clean_name(name))),
		"password": "",
		"port": str(int(last.get("port", NetSession.PORT))),
		"router": bool(last.get("router", true)),
		"address": String(last.get("address", "")),
	}
	net_row = 0
	net_note = WEB_NOTE if web else ""
	state = "nethost" if hosting else "netjoin"
	sound.play("menu_accept")


const WEB_NOTE := "ONLINE NEEDS THE DESKTOP OR ANDROID GAME FOR NOW."


## The picker's COUNTY SERVERS: the always-open lobbies, live (net_browser.gd).
func open_servers() -> void:
	var last := NetPlay.remembered()
	close_servers()
	# The browser build cannot reach them (no ENet): the list shows none.
	browser = NetBrowser.new([] if web else NetBrowser.listed())
	browser.name = String(last.get("name", options.get("player_name", "MUNDELL")))
	net_note = WEB_NOTE if web else ""
	state = "servers"
	sound.play("menu_accept")


func close_servers() -> void:
	if browser != null:
		browser.close()
	browser = null


## ENTER on a server: straight into its lobby.
func join_server(i: int) -> void:
	if browser == null or i < 0 or i >= browser.servers.size():
		return
	var why := browser.why_not_join(i)
	if why != "":
		net_note = why
		sound.play("empty")
		return
	var name := NetPlay.clean_name(browser.name)
	net_form = {"name": name, "address": browser.address_of(i), "password": ""}
	close_servers()
	net_join()
	if net == null:
		open_servers()


## OPEN THE LOBBY on the HOST ONLINE form.
func net_open_lobby() -> void:
	if web:
		net_note = WEB_NOTE
		sound.play("empty")
		return
	var port := String(net_form["port"]).to_int()
	if port < 1024 or port > 65535:
		net_note = "A PORT FROM 1024 TO 65535, PLEASE."
		sound.play("empty")
		return
	var lobby := {
		"lobby_name": NetPlay.clean_name(String(net_form["lobby_name"]), 22),
		"password": String(net_form["password"]),
	}
	var opened := NetPlay.host_lobby(
		port, String(net_form["name"]), lobby, bool(net_form["router"])
	)
	if opened == null:
		net_note = "PORT %d IS TAKEN. IS ANOTHER COPY HOSTING?" % port
		sound.play("empty")
		return
	(
		NetPlay
		. remember(
			{
				"name": net_form["name"],
				"lobby_name": net_form["lobby_name"],
				"port": port,
				"router": net_form["router"],
			}
		)
	)
	_net_ready(opened)
	sound.play("menu_accept")


## JOIN on the JOIN ONLINE form.
func net_join() -> void:
	if web:
		net_note = WEB_NOTE
		sound.play("empty")
		return
	var joined := NetPlay.join_lobby(
		String(net_form["address"]), String(net_form["name"]), String(net_form["password"])
	)
	if joined == null:
		net_note = "THAT CODE OR ADDRESS WON'T DO."
		sound.play("empty")
		return
	NetPlay.remember({"name": net_form["name"], "address": net_form["address"]})
	_net_ready(joined)
	sound.play("menu_accept")


func _net_ready(opened: NetPlay) -> void:
	net = opened
	net.make_match = net_match_game
	var sim := {}
	for key: String in ["difficulty", "gore", "aim_assist", "hit_feedback", "adaptive"]:
		if options.has(key):
			sim[key] = options[key]
	net.sim_options = sim
	net_leave = false
	net_note = ""
	lobby_row = 0
	net_kick = 0
	net_kick_armed = false
	state = "lobby"


## The game a match is played on (NetPlay.make_match): the map, the host's
## play settings and the lobby's match on it; a client's view on its slot.
func net_match_game(info: Dictionary) -> Game:
	var made: Game = make_game(String(info["level"]))
	if made == null:
		return null
	made.configure(_net_options(info))
	Modes.setup(made, String(info["mode"]), int(info["count"]), info["options"])
	var slot := int(info.get("slot", 0))
	if slot > 0 and slot < made.players.size():
		Players.set_local(made, made.players[slot])
	if net != null:
		# The lobby's CHATTER caps each player's own (presentation only).
		made.chatter = mini(made.chatter, int(net.settings.get("chatter", CussLines.CUSSIN)))
	return made


## This machine's settings with the host's play settings over them.
func _net_options(info: Dictionary) -> Dictionary:
	var out := options.duplicate()
	out.merge(info.get("sim", {}), true)
	return out


## A match began (START): play it.
func net_begin_match() -> void:
	var target := net.match_game()
	if target == null:
		return
	mode_name = ""
	showdown_on = false
	net_leave = false
	net_accum = 0.0
	net_turn = 0.0
	net_look = 0.0
	play(target)


## Everyone back in the lobby after a match.
func net_to_lobby() -> void:
	game = null
	pilots.clear()
	net_leave = false
	lobby_row = 0
	state = "lobby"
	sound.pause_world()
	menu_music()
	grab(false)


## Leaving the lobby or match by choice (the host's closes it for everyone).
func net_quit() -> void:
	if net == null:
		return
	var hosting := net.role == NetPlay.Role.HOST
	net.leave("THE HOST CLOSED THE LOBBY" if hosting else "LEFT")
	_net_gone("LOBBY CLOSED." if hosting else "YOU LEFT THE LOBBY.")


## The lobby is gone (the host left, it could not be reached, a refusal).
func net_closed() -> void:
	var why := net.reason
	_net_gone(why + ("." if not why.ends_with(".") else ""))
	sound.play("empty")


func _net_gone(note: String) -> void:
	net_old.append(net)
	net = null
	game = null
	pilots.clear()
	net_leave = false
	menu_music()
	sound.pause_world()
	grab(false)
	state = "title"
	selection = 0
	menu_note = note
