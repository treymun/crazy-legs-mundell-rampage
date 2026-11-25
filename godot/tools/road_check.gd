## Between chapters and the chapter's end card (pass 15: src/between_chapters.gd,
## src/tally_card.gd, src/chapter_bests.gd, features/tally.gd), headless,
## through the real front end:
##
##   Godot --headless --path <project> --script res://tools/road_check.gd
##
## STRAIGHT ON: from a won chapter one ENTER (once the rows are down) starts
## the next chapter with the kit carried, the campaign entry and the unlocks
## written, the won chapter kept for a revisit; a press in the moment of the
## win does nothing, one while the rows come down puts them all down; the
## next chapter's opener plays the first time, one key skips all of it.
## The MAP key: the Crossroads standing at the next chapter's gate, facing it
## (USE takes it: CONTINUE into the chapter under way); every chapter's gate
## has room in front of it. THE CROSSROADS setting swaps the two.
## The bests: a first run kept (no NEW BEST), a slower run keeps the old
## bests, a better one sets NEW BEST and the show adds the stamp; none kept
## with cheats or in co-op. TRY TO BEAT IT: the chapter again as the hub's
## REPLAY (its gate's kit) with the campaign gone on unseen; the replay won,
## HIT THE ROAD into the next chapter. The card's layout at every row
## count with every chapter's last word, the bests' column, the plates and
## the stamp in the 7-pixel letters and SMALL TEXT; every chapter's card
## drawn. Writes nothing to the profile (bests under the cache folder).
extends SceneTree

const TallyFeature := preload("res://src/features/tally.gd")

## The profile's files the campaign's own flow writes (main_state.gd
## _entry_path, SessionStore.save_unlocks).
const PROFILE_FILES := [
	"user://campaign-entry.json",
	"user://campaign-unlocks.json",
	"user://county-road-notes.json",
	"user://lessons.json",
]

var failures: Array = []
var main
var kept_files := {}


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	_keep_profile()
	_clean()
	for key: String in SessionStore.defaults():
		main.options[key] = SessionStore.defaults()[key]
	main.options["hound"] = 0
	main.options["events"] = 0
	main.options["openers"] = ChapterOpener.OFF
	main.apply_options()
	_check(BetweenChapters.straight(main.options), "BETWEEN CHAPTERS is STRAIGHT ON by default")
	_straight_on()
	_crossroads()
	_gates()
	_bests()
	_try_to_beat_it()
	_opener()
	_layout()
	_clean()
	_put_back_profile()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%s)" % tally.first_errors[0])
		)
	)
	print("")
	print("ROAD CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The bests (under the cache folder in a tool run) and the checkpoints gone.
func _clean() -> void:
	if FileAccess.file_exists(ChapterBests.path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ChapterBests.path()))
	ChapterMarks.clear_all()


## The campaign entry and unlocks the walk writes through the real flow
## (user://): kept as they were before it and put back after it, so a run
## outside check_all's scratch profile leaves a player's own as it found them.
func _keep_profile() -> void:
	for path: String in PROFILE_FILES:
		kept_files[path] = (
			FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		)


func _put_back_profile() -> void:
	for path: String in PROFILE_FILES:
		var was = kept_files.get(path)
		if was == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(was)
			file.close()


## A chapter of a campaign (the chapters before it in its history, as a save
## of it needs), won with these numbers.
func _won(level_id: String, seconds: float, kills: int, secrets: int) -> Game:
	var history: Array = []
	for i in Campaign.ORDER.find(level_id):
		history.append([Campaign.ORDER[i], 0, 0, 0, 0, 0])
	main.start(level_id, null, history)
	var g: Game = main.game
	g.lessons = false
	g.clock = seconds
	g.kills = kills
	g.secrets = secrets
	g.finish_level("")
	return g


## The card's rows as drawn (the show's row count), then the moment of the
## win long gone, so a key goes on.
func _rows_down(g: Game) -> void:
	main.watch_tally()
	var show = g.features["tally"]
	show.rows_shown(TallyCard.rows_of(g).size())
	show.won_at -= 60000
	show.thuds = 99


func _straight_on() -> void:
	print("STRAIGHT ON")
	var g := _won("hickston", 300.0, 40, 1)
	g.player.armory.owned[Weapons.NAMES.find("shotgun")] = true
	g.player.armory.reserve[Weapons.NAMES.find("shotgun")] = 17
	g.player.health = 63
	var kit: Dictionary = g.loadout()
	main.watch_tally()
	var show = g.features["tally"]
	_check(show.choices.size() == 3, "three plates: %s" % str(show.choices))
	_check(
		str(show.choices[0][1]) == "NEXT CHAPTER" and str(show.choices[0][0]) == "ENTER",
		"the one tap's plate: ENTER  NEXT CHAPTER"
	)
	_check(str(show.choices[1][1]) == "THE CROSSROADS", "the other: THE CROSSROADS")
	_check(str(show.choices[2][1]) == "TRY TO BEAT IT", "and TRY TO BEAT IT")
	show.rows_shown(TallyCard.rows_of(g).size())
	main.key(KEY_ENTER)
	_check(main.game == g, "ENTER in the moment of the win does nothing")
	show.won_at -= TallyFeature.KEY_WAIT + 10
	main.key(KEY_ENTER)
	_check(
		main.game == g and show.thuds == TallyCard.rows_of(g).size() + 1,
		"ENTER while the rows come down puts them all down, the ribbon too (%d)" % show.thuds
	)
	main.key(KEY_ENTER)
	var fair: Game = main.game
	_check(
		fair != g and fair.level.id == "fair" and not fair.in_hub and main.state == "play",
		"the next ENTER: straight into the fair (%s)" % fair.level.id
	)
	var now: Dictionary = fair.loadout()
	_check(
		now["owned"] == kit["owned"] and now["reserve"] == kit["reserve"] and now["health"] == 63,
		"the kit carried (guns, rounds, health)"
	)
	_check(
		main.campaign_run == fair and fair.retained.has("hickston"), "hickston kept for a revisit"
	)
	_check(fair.history.size() == 1, "its result in the history")
	_check(SessionStore.read(main._entry_path(), main.make_game, false) != null, "the entry loads")
	var entry: Game = SessionStore.read(main._entry_path(), main.make_game, false)
	_check(entry != null and entry.level.id == "fair", "the campaign entry written: the fair")
	_check(SessionStore.unlocks("").has("fair"), "the fair's gate unlocked and saved")
	var best: Dictionary = ChapterBests.best("hickston", 1)
	_check(
		float(best.get("time", 0.0)) == 300.0 and int(best.get("kills", 0)) == 40,
		"the run's bests kept: %s" % str(best)
	)


func _crossroads() -> void:
	print("THE CROSSROADS")
	var g := _won("fair", 280.0, 30, 0)
	_rows_down(g)
	main.key(KEY_TAB)
	var hub: Game = main.game
	_check(hub.in_hub, "the MAP key: the Crossroads")
	var gate = GameUse.portal_target(hub)
	_check(
		gate != null and gate.destination == "sawmill",
		"standing at the sawmill's gate, facing it (%s)" % (gate.destination if gate else "none")
	)
	_check(hub.gate_modes.get("sawmill", "") == "CONTINUE", "its gate says CONTINUE")
	_check(hub.gate_modes.get("fair", "") == "REVISIT", "the fair's says REVISIT")
	var entry: Game = SessionStore.read(main._entry_path(), main.make_game, false)
	_check(
		entry != null and entry.level.id == "sawmill",
		"the campaign entry written: the sawmill (%s)" % (entry.level.id if entry else "none")
	)
	var sawmill: Game = main.campaign_run
	main.key(KEY_E)
	_check(
		main.game == sawmill and sawmill.level.id == "sawmill", "USE: into the sawmill under way"
	)
	print("THE CROSSROADS SETTING")
	main.options["between"] = BetweenChapters.THE_CROSSROADS
	g = _won("quarry", 250.0, 20, 0)
	_rows_down(g)
	_check(
		str(g.features["tally"].choices[0][1]) == "THE CROSSROADS",
		"THE CROSSROADS: the one tap's plate"
	)
	main.key(KEY_ENTER)
	_check(main.game.in_hub, "ENTER: the Crossroads")
	g = _won("quarry", 250.0, 20, 0)
	_rows_down(g)
	main.key(KEY_TAB)
	_check(main.game.level.id == "bayou" and not main.game.in_hub, "the MAP key: straight on")
	main.options["between"] = BetweenChapters.STRAIGHT_ON


func _gates() -> void:
	print("EVERY GATE")
	for level_id: String in Campaign.ORDER:
		main.unlocked[level_id] = true
	for level_id: String in Campaign.ORDER:
		main.open_hub(null, "", level_id)
		var hub: Game = main.game
		var gate = GameUse.portal_target(hub)
		_check(
			gate != null and gate.destination == level_id,
			"%s: in front of its gate, USE takes it" % level_id
		)


func _bests() -> void:
	print("BESTS")
	_clean()
	var g := _won("sawmill", 200.0, 30, 1)
	main.watch_tally()
	var card: Dictionary = g.features["tally"].card
	_check(card.get("kept_bests", false) and card["old"].is_empty(), "a first run: kept")
	_check(not g.features["tally"].fresh(), "a first run: no NEW BEST")
	g = _won("sawmill", 260.0, 25, 0)
	main.watch_tally()
	card = g.features["tally"].card
	var best: Dictionary = ChapterBests.best("sawmill", 1)
	_check(
		(
			not g.features["tally"].fresh()
			and float(best["time"]) == 200.0
			and int(best["kills"]) == 30
		),
		"a slower run keeps the old bests %s" % str(best)
	)
	var rows := TallyCard.rows_of(g)
	_check(
		str(rows[0][2][0]) == "BEST 30", "VARMINTS shows the best beside it: %s" % str(rows[0][2])
	)
	g = _won("sawmill", 150.0, 33, 2)
	main.watch_tally()
	card = g.features["tally"].card
	best = ChapterBests.best("sawmill", 1)
	_check(
		card["time"] and card["kills"] and card["secrets"] and float(best["time"]) == 150.0,
		"a better run: NEW BEST, kept %s" % str(best)
	)
	var count := TallyCard.rows_of(g).size()
	g.features["tally"].won_at -= 60000
	_check(
		g.features["tally"].rows_shown(count) == count + 2,
		"the show: the rows, the ribbon, the stamp"
	)
	g = _won("sawmill", 300.0, 31, 0)
	main.watch_tally()
	_check(ChapterBests.best("sawmill", 1)["kills"] == 33, "one best beaten, the rest kept")
	main.options["difficulty"] = 3
	g = _won("sawmill", 400.0, 10, 0)
	main.watch_tally()
	_check(
		(
			g.features["tally"].card["old"].is_empty()
			and ChapterBests.best("sawmill", 3)["time"] == 400.0
		),
		"bests by difficulty: HOG WILD its own"
	)
	main.options["difficulty"] = 1
	g = _won("sawmill", 100.0, 99, 3)
	g.cheats.used = true
	main.watch_tally()
	_check(
		(
			ChapterBests.best("sawmill", 1)["time"] == 150.0
			and g.features["tally"].choices.size() == 2
		),
		"with cheats: nothing kept, no TRY TO BEAT IT"
	)
	main.start("sawmill")
	g = main.game
	Modes.setup(g, Modes.COOP, 2)
	g.clock = 90.0
	g.finish_level("")
	main.watch_tally()
	_check(ChapterBests.best("sawmill", 1)["time"] == 150.0, "co-op keeps no bests")
	_check(
		(
			ChapterBests.pace("sawmill", ChapterBests.par("sawmill")) == 1.0
			and (
				ChapterBests.pace("sawmill", ChapterBests.par("sawmill") * ChapterBests.SLACK)
				== 0.0
			)
		),
		"the ribbon's pace: full at par, none at slack times par"
	)


func _try_to_beat_it() -> void:
	print("TRY TO BEAT IT")
	var g := _won("speedway", 180.0, 20, 0)
	_rows_down(g)
	main.key(KEY_R)
	var replay: Game = main.game
	_check(
		replay.level.id == "speedway" and replay.replay and not replay.won,
		"the speedway again, as a replay"
	)
	_check(
		main.campaign_run != null and main.campaign_run.level.id == "moonshine",
		"the campaign gone on unseen: the moonshine run waits"
	)
	var entry: Game = SessionStore.read(main._entry_path(), main.make_game, false)
	_check(entry != null and entry.level.id == "moonshine", "its entry written")
	var kit: Game = main.make_game("speedway")
	NetCoop.chapter_kit(kit, "speedway")
	_check(replay.loadout()["owned"] == kit.loadout()["owned"], "with the gate's replay kit")
	replay.clock = 150.0
	replay.kills = 25
	replay.finish_level("")
	_rows_down(replay)
	var plates: Array = replay.features["tally"].choices
	_check(
		plates.size() == 3 and str(plates[0][1]) == "HIT THE ROAD",
		"the replay's card: HIT THE ROAD first %s" % str(plates)
	)
	_check(replay.features["tally"].fresh(), "a faster replay: NEW BEST")
	main.key(KEY_ENTER)
	_check(
		main.game == main.campaign_run and main.game.level.id == "moonshine",
		"ENTER: the moonshine run"
	)


func _opener() -> void:
	print("THE OPENER")
	var op: ChapterOpener = main.opener
	op.tools_write = true
	op.seen_path = OS.get_cache_dir().path_join("clmr_road_check_seen.json")
	DirAccess.remove_absolute(op.seen_path)
	op.seen.clear()
	main.options["openers"] = ChapterOpener.FIRST_TIME
	main.apply_options()
	var g := _won("hickston", 300.0, 1, 0)
	_rows_down(g)
	main.key(KEY_ENTER)
	_check(
		op.pending == main.game and op.start(main), "straight on: the fair's opener the first time"
	)
	main.key(KEY_SPACE)
	_check(not op.playing and main.game.level.id == "fair", "one key skips all of it")
	g = _won("hickston", 300.0, 1, 0)
	_rows_down(g)
	main.key(KEY_ENTER)
	_check(op.pending == null, "not the next time")
	op.tools_write = false
	DirAccess.remove_absolute(op.seen_path)
	main.options["openers"] = ChapterOpener.OFF
	main.apply_options()


## The card's rows, last word, bests' column, plates and stamp kept apart and
## inside the panel and the picture.
func _layout() -> void:
	print("THE CARD'S LAYOUT")
	var bad := []
	for small: bool in [false, true]:
		PixelType.clear_small = small
		var font := "SMALL TEXT" if small else "7-PIXEL"
		for level_id: String in Campaign.ORDER:
			var said := PixelType.wrap(Campaign.ending_of(level_id), 186, "body")
			for count in range(0, TallyCard.MOST_ROWS + 1):
				var gap: int = TallyCard.GAPS[count]
				var bar := mini(15, gap - 1)
				var rows_end := TallyCard.ROW_TOP + (count - 1) * gap + bar if count > 0 else 72
				var top := mini(rows_end + 3, TallyCard.WORD_FOOT - said.size() * 9)
				if top <= rows_end or top + said.size() * 9 > 186:
					bad.append("%s %s, %d rows: the last word at %d" % [font, level_id, count, top])
		# Every chapter's real rows with bests: label, best, number apart.
		for level_id: String in Campaign.ORDER:
			var g: Game = main.make_game(level_id)
			g.configure(main.options)
			g.kills = 188
			g.secrets = 12
			g.clock = 3599.0
			var show = g.features["tally"]
			show.card = {
				"settled": true,
				"kept_bests": true,
				"difficulty": "HOG WILD",
				"old": {"time": 3599.0, "kills": 188, "secrets": 12},
			}
			for row: Array in TallyCard.rows_of(g):
				var label_end := 26 + PixelType.text_width(str(row[0]), "body")
				var value_left := 202 - PixelType.text_width(str(row[1]), "body")
				var beside: Array = row[2]
				var left := value_left
				if not beside.is_empty():
					left = TallyCard.BEST_RIGHT - PixelType.text_width(str(beside[0]), "mini")
					if TallyCard.BEST_RIGHT + 4 > value_left:
						bad.append(
							"%s %s %s: the best runs into the number" % [font, level_id, row[0]]
						)
				if label_end + 4 > left:
					bad.append(
						"%s %s %s: the label runs into what is beside it" % [font, level_id, row[0]]
					)
		for label: String in [
			"NEXT CHAPTER", "THE CROSSROADS", "TRY TO BEAT IT", "HIT THE ROAD", "RETURN TO TITLE"
		]:
			if PixelType.text_width(label, "body") > TallyCard.PLATE_W - 6:
				bad.append("%s plate %s too wide" % [font, label])
		for word: String in ["ENTER", "TAB", "BACKSPACE", "TAP"]:
			if PixelType.text_width(word, "mini") > TallyCard.PLATE_W - 6:
				bad.append("%s key word %s too wide" % [font, word])
	PixelType.clear_small = false
	_check(bad.is_empty(), "every row count, chapter and font fits: %s" % str(bad.slice(0, 4)))
	var last := TallyCard.plate_rect(TallyCard.PLATE_TOPS.size() - 1)
	_check(
		last.end.y <= 198 and last.end.x <= 320 and TallyCard.plate_rect(0).position.y > 107,
		"the plates under the ribbon, inside the picture"
	)
	_check(
		TallyCard.STAMP.end.x <= 320 and TallyCard.STAMP.end.y <= 56 + 2,
		"the stamp inside the picture, over the ribbon's top"
	)
	var widest := 0
	for level_id: String in Campaign.ORDER:
		for line: String in Campaign.heading_of(level_id):
			widest = maxi(widest, 21 + PixelType.text_width(line, "heading"))
	_check(
		(
			PixelType.text_width("BEST", "heading") <= TallyCard.STAMP.size.x - 8
			and TallyCard.STAMP.position.x > widest + 4
		),
		"NEW BEST fits its stamp, clear of every chapter's heading (out to %d)" % widest
	)
	# Every chapter's card drawn, with its plates and the stamp.
	for level_id: String in Campaign.ORDER:
		var g: Game = main.make_game(level_id)
		g.configure(main.options)
		g.won = true
		main.game = g
		main.state = "play"
		main.watch_tally()
		g.features["tally"].card["time"] = true
		main.hud.intermission(main.canvas, g)
	var g: Game = main.make_game("hickston")
	g.configure(main.options)
	g.won = true
	main.game = g
	main.watch_tally()
	_check(
		(
			TallyCard.zone_at(g, TallyCard.plate_rect(1).get_center()) == BetweenChapters.OTHER
			and TallyCard.zone_at(g, Vector2i(80, 120)) == BetweenChapters.GO
			and TallyCard.plate_at(g, Vector2i(80, 120)) == -1
		),
		"a tap on a plate is its way on, anywhere else the one tap's"
	)
	main.game = null
	main.state = "title"
