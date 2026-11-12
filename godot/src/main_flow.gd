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
				"speedway": [Weapons.CROSSBOW, 6]
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
		packs.want_first(String(CHAPTER_PACKS.get(target.level.id, "")))
		notice("FETCHING THE CHAPTER. A MOMENT...", 4.0)
		return
	waiting_play = null
	# Lessons are for players: tours, benches, smoke runs and demos must look the
	# same on every machine, whatever this profile was already taught.
	target.lessons = (
		view_tour == "" and view_bench == 0 and smoke_frames == 0 and not demo and not showcase
	)
	game = target
	var practice := target.level.id == RANGE_ID
	if not practice:
		range_return = null
	if not target.replay and not target.in_hub and not target.revisiting and not practice:
		campaign_run = target
	if target.replay:
		replay_runs[target.level.id] = target
	target.configure(options)
	target.tone = tone_table
	crouch_latched = target.player.crouched and int(options["crouch"]) != 0
	sound.pause_world()
	play_music()
	state = "play"
	block_fire = true
	grab(not target.showing_tally and target.player.health > 0)


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
		hub.hub_milestone = campaign_run.history.size() + (1 if campaign_run.won else 0)
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
	if current.replay:
		replay_runs.erase(current.level.id)
		if hub_origin == current:
			hub_origin = null
		return_to_title(true)
		return
	var following := Campaign.next_level(current.level.id)
	if following == "":
		open_hub(current, "SHIFT COMPLETE. OPEN ROADS LEAD BACK TO FINISHED CHAPTERS.")
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


func menu_action() -> void:
	var rows := entries()
	var entry := rows[selection % rows.size()]
	menu_note = ""
	if in_range() and not entry in ["RESUME", "SAVE SLOTS", "SETUP", "CONTROLS", "CREDITS", "QUIT"]:
		# Anything that goes somewhere else leaves the range first, so nothing
		# from it (its guns least of all) is carried into the county.
		leave_range()
	if entry == "LEAVE RANGE":
		return_to_title()
		menu_note = "BACK FROM THE RANGE. NOTHING THERE WAS SAVED."
		return
	if entry == "FIRING RANGE":
		open_range()
		return
	if entry == "RESUME":
		state = "play"
		play_music()
		grab(not game.showing_tally and game.player.health > 0)
	elif entry == "NEW GAME":
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
			grab(game.player.health > 0 and not game.showing_tally)
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
	p.eye = .95 + game.world.elevation(p.x, p.y)
	level_stamp = FileAccess.get_modified_time(LevelEdit.path_of(game.level.id))
	level_stamp_of = game.level.id
