## The county radio (content pass 8: src/radio_station.gd, features/radio.gd,
## sound.gd), headless:
##
##   Godot --headless --path <project> --script res://tools/radio_check.gd
##
## Every line of data/tuning/radio_lines.json is made and in the bank, with a
## caption that fits two lines; a gap between songs gets an ID, the talk and a
## way back to the band, and the news first (a boss down before the rest);
## lines are dealt so none comes round again soon; the scanner calls trouble
## with the chapter's place; three deaths make a rough night, two do not;
## CUSSIN' says the crude lines, CLEAN their copies, CHATTER OFF neither; the
## RADIO setting (MUSIC ONLY: no talk, OFF: the sets hushed too); a boss fight
## holds the radio and a boss's line hushes it; anyone talking ducks it, Dub
## talking over the music ducks the music; a vehicle taken tunes its set in;
## in a game the events reach the station (a blast, a boss down, a burnt-out
## car, drunk, a secret, a rampage) and its lines are captioned; the feature
## is looks only (a host has none, game.rng untouched).
extends SceneTree

var failures: Array = []


## Plays nothing: notes each cue and says it lasts two seconds.
class Air:
	extends RefCounted
	var played: Array = []
	var stopped := 0

	func play(_channel: int, cue: String) -> float:
		played.append(cue)
		return 2.0

	func stop(_channel: int) -> void:
		stopped += 1


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("\nTHE COUNTY RADIO")
	_lines(main)
	_breaks()
	_scanner()
	_settings(main)
	_sound(main)
	_in_game(main)
	print("")
	print("RADIO CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## A station on the air with nothing playing for real.
func _station(air: Air) -> RadioStation:
	var st := RadioStation.new()
	st.player = air.play
	st.stopper = air.stop
	return st


## Runs `st` for `seconds` in steps of a tenth.
func _spin(st: RadioStation, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		st.update(.1)
		t += .1


func _lines(main) -> void:
	var data := RadioStation.data()
	var missing: Array = []
	var long: Array = []
	var count := 0
	for part: Array in [["dj", "dj_", "KPSM: "], ["scanner", "scan_", "SCANNER: "]]:
		var groups: Dictionary = data.get(part[0], {})
		for group: String in groups:
			var lines: Array = groups[group]
			for n in lines.size():
				count += 1
				var cue := "%s%s_%d" % [part[1], group, n]
				if not main.art.has_cue(cue):
					missing.append(cue)
				if PixelType.wrap(str(part[2]) + str(lines[n]), 288 - 14).size() > 2:
					long.append(cue)
	for topic: String in data.get("cuss", {}):
		var crude: Array = data["cuss"][topic]
		for n in crude.size():
			for chatter in [CussLines.CLEAN, CussLines.CUSSIN]:
				var cue := CussLines.cue("dj", topic, n, chatter)
				if not main.art.has_cue(cue):
					missing.append(cue)
	for cue in ["radio_tune", "scan_squelch"]:
		if not main.art.has_cue(cue):
			missing.append(cue)
	check(count >= 80, "the radio has its lines (%d)" % count)
	check(
		missing.is_empty(),
		"every radio line, CLEAN copy and the set's sounds are in the bank %s" % [missing]
	)
	check(long.is_empty(), "every radio caption fits two lines %s" % [long])
	var bosses := load("res://src/features/boss_voices.gd")
	var unsaid: Array = []
	for who: String in bosses.LINES:
		if RadioStation.lines("dj", "boss_" + who).is_empty():
			unsaid.append(who)
	check(unsaid.is_empty(), "Dub has a line for every boss's fall %s" % [unsaid])


func _breaks() -> void:
	var air := Air.new()
	var st := _station(air)
	var took := 0
	for i in 20:
		if st.take_break():
			took += 1
			_spin(st, 30.0)
	check(took >= 9 and took <= 19, "a quiet night: Dub takes most gaps, not all (%d of 20)" % took)
	check(not st.in_break, "and each break ends")
	var ids: Array = []
	var outros := 0
	var back_to_back := false
	for cue: String in air.played:
		if cue.begins_with("dj_id_"):
			if not ids.is_empty() and ids[ids.size() - 1] == cue:
				back_to_back = true
			ids.append(cue)
		if cue.begins_with("dj_outro_"):
			outros += 1
	check(
		ids.size() == took and outros == took,
		"every break opens with an ID and ends on the way back"
	)
	check(not back_to_back, "no ID twice in a row")
	var first: Dictionary = {}
	for i in mini(5, ids.size()):
		first[ids[i]] = true
	check(
		first.size() == mini(5, ids.size()),
		"the first five IDs are all different (dealt, not drawn)"
	)
	# The news first, a boss's fall before the rest.
	air.played.clear()
	st.news("drunk")
	st.news("boss_sheriff")
	check(st.fresh_topics().size() == 2, "the news waits for the next gap")
	check(st.take_break(), "a gap with news always gets talk")
	_spin(st, 30.0)
	check(
		air.played.size() >= 4 and air.played[1] == "dj_boss_sheriff_0",
		"the sheriff's fall is told first %s" % [air.played]
	)
	var drunk_told := false
	for cue: String in air.played:
		drunk_told = drunk_told or cue.begins_with("dj_drunk_") or cue.begins_with("cuss_dj_drunk")
	check(drunk_told, "and the drunk after it")
	st.news("drunk")
	check(st.fresh_topics().is_empty(), "a topic just told is not news again soon")
	# Deaths.
	st.news("death")
	st.news("death")
	check(st.fresh_topics().is_empty(), "two deaths are not news")
	st.news("death")
	check(st.fresh_topics() == ["deaths"], "three in a night are")
	# Crude lines by CHATTER.
	for chatter in [CussLines.CUSSIN, CussLines.CLEAN, CussLines.OFF]:
		var said := {}
		var s2 := _station(Air.new())
		s2.chatter = chatter
		for i in 40:
			s2.news("boom" if i % 2 == 0 else "wreck")
			s2.now += RadioStation.TOLD_HOLDS + 1.0
			var pair: Array = s2._reaction("boom" if i % 2 == 0 else "wreck")
			said[str(pair[0])] = str(pair[1])
		var crude := 0
		var clean := 0
		var hidden := true
		for cue: String in said:
			if cue.begins_with("cuss_dj_"):
				crude += 1
				clean += 1 if cue.ends_with("_clean") else 0
				hidden = (
					hidden
					and not str(said[cue]).contains("hell")
					and not str(said[cue]).contains("damn")
				)
		match chatter:
			CussLines.CUSSIN:
				check(crude > 0 and clean == 0, "CUSSIN': Dub says a crude line now and then")
			CussLines.CLEAN:
				check(
					crude > 0 and clean == crude and hidden, "CLEAN: their copies, the words hidden"
				)
			_:
				check(crude == 0, "CHATTER OFF: none")
	# Held.
	var s3 := _station(Air.new())
	s3.hold = true
	check(not s3.take_break(), "no break in a boss fight")
	s3.hold = false
	s3.take_break()
	_spin(s3, 1.0)
	s3.hold = true
	_spin(s3, 30.0)
	check(not s3.in_break, "a boss fight starting ends a break")
	var s4 := _station(Air.new())
	s4.take_break()
	_spin(s4, 1.0)
	s4.hush()
	check(not s4.in_break and not s4.on_air(), "hushed at once")


func _scanner() -> void:
	var air := Air.new()
	var st := _station(air)
	st.place = "bayou"
	st.news("shots")
	_spin(st, 20.0)
	check(
		air.played.has("scan_squelch") and _has_prefix(air.played, "scan_shots_"),
		"shots fired go out on the scanner %s" % [air.played]
	)
	check(air.played.has("scan_place_bayou_0"), "with the units sent to the chapter's place")
	air.played.clear()
	st.news("shots")
	_spin(st, 5.0)
	check(air.played.is_empty(), "not again a moment later")
	var air2 := Air.new()
	var st2 := _station(air2)
	st2.news("shots")
	_spin(st2, 1.0)
	st2.news("boom")
	_spin(st2, 20.0)
	check(not _has_prefix(air2.played, "scan_boom_"), "nor another call on top of one")
	_spin(st, 20.0)
	st.news("boom")
	_spin(st, 20.0)
	check(_has_prefix(air.played, "scan_boom_"), "a blast later on is called in")
	air.played.clear()
	st.now += 100.0
	st.others_talking = true
	st.news("wreck")
	_spin(st, 3.0)
	check(air.played.is_empty(), "a call waits while someone talks")
	st.others_talking = false
	_spin(st, 10.0)
	check(_has_prefix(air.played, "scan_wreck_"), "and goes out once they stop")


func _has_prefix(list: Array, prefix: String) -> bool:
	for cue: String in list:
		if cue.begins_with(prefix):
			return true
	return false


func _settings(main) -> void:
	var air := Air.new()
	var st := _station(air)
	st.mode = RadioStation.MUSIC_ONLY
	check(not st.take_break(), "MUSIC ONLY: no talk between songs")
	st.news("shots")
	_spin(st, 10.0)
	check(not _has_prefix(air.played, "scan_"), "and no scanner")
	st.tune_in()
	_spin(st, 5.0)
	check(air.played == ["radio_tune"], "a set tuned in only clicks on %s" % [air.played])
	st.mode = RadioStation.OFF
	air.played.clear()
	st.tune_in()
	_spin(st, 5.0)
	check(air.played.is_empty(), "OFF: nothing at all")
	var st2 := _station(air)
	st2.tune_in()
	_spin(st2, 8.0)
	check(
		(
			air.played.size() == 2
			and air.played[0] == "radio_tune"
			and str(air.played[1]).begins_with("dj_drive_")
		),
		"DJ + MUSIC: a vehicle taken tunes in and Dub says one for the road"
	)
	var before: Dictionary = main.options.duplicate()
	main.options["radio"] = RadioStation.MUSIC_ONLY
	main.apply_options()
	check(
		main.sound.station.mode == RadioStation.MUSIC_ONLY, "the RADIO setting reaches the station"
	)
	main.options["radio"] = RadioStation.OFF
	main.apply_options()
	main.sound.set_radio(true, .5, 0.0)
	check(not main.sound._radio.player.playing, "OFF hushes the sets (a jukebox, a truck's radio)")
	main.options = before
	main.apply_options()
	check(SessionStore.settings("").has("radio"), "RADIO is a stored setting")


func _sound(main) -> void:
	var sound: Sound = main.sound
	var st: RadioStation = sound.station
	check(sound.score_player.station == st, "the music asks the station at each song's end")
	var length: float = sound._radio_play(RadioStation.DJ, "dj_id_0")
	check(length > 1.0, "Dub's line plays on his own channel (%.2f s)" % length)
	if not sound._dj.player.playing:
		check(true, "(no audio playback headless: the levels are not measured)")
	else:
		st.others_talking = false
		sound._radio_levels(.02)
		var open := Sound.level_of(sound._dj.player)
		st.others_talking = true
		sound._radio_levels(.02)
		var ducked := Sound.level_of(sound._dj.player)
		check(
			open > 0.0 and absf(ducked - open * Sound.RADIO_DUCK) < .01,
			"anyone talking ducks the radio (%.3f -> %.3f)" % [open, ducked]
		)
		st.others_talking = false
		for i in 60:
			sound._radio_levels(.05)
		check(
			absf(sound._music_duck - Sound.MUSIC_UNDER_DJ) < .01,
			"Dub talking over the music ducks it (%.2f)" % sound._music_duck
		)
	st.take_break()
	sound.hush_speech()
	check(not st.in_break and not sound._dj.player.playing, "a boss's line hushes the radio")
	for i in 60:
		sound._radio_levels(.05)
	check(absf(sound._music_duck - 1.0) < .01, "and the music comes back up")
	st.take_break()
	sound.pause_world()
	check(not st.in_break, "pausing the game hushes it too")


func _in_game(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	var radio = g.features.get("radio")
	check(radio != null, "a chapter has the radio feature")
	check(Features.LOOKS.has("radio") and GameSnapshot.LOOKS_FEATURES.has("radio"), "looks only")
	var air := Air.new()
	var st := _station(air)
	radio.station = st
	radio._tick(1.0)
	check(st.place == "hickston", "the scanner knows the chapter (%s)" % st.place)
	g.events.exploded.emit(g.local_player.x, g.local_player.y, 0.0, false)
	check(st.fresh_topics().has("boom"), "a blast is news")
	var sheriff: Enemy = null
	for e: Enemy in g.enemies:
		if e.kind == "boss":
			sheriff = e
	if sheriff != null:
		g.events.boss_down.emit(sheriff, 30.0)
		check(st.fresh_topics().has("boss_sheriff"), "the sheriff down is news")
	g.local_player.drunk = 80.0
	g.secrets += 1
	radio._look_left = 0.0
	radio._tick(1.0)
	check(st.fresh_topics().has("drunk"), "drunk is news")
	check(st.fresh_topics().has("secret"), "a secret found is news")
	var dice_before: int = g.rng.state
	var kills := 0
	for e: Enemy in g.enemies:
		if kills < radio.get_script().KILLS and not e.kind.contains("deputy"):
			radio._killed(e)
			kills += 1
	check(st.fresh_topics().has("rampage"), "a run of kills is news")
	var rides = g.features.get("vehicles")
	if rides != null and not rides.rides.is_empty():
		rides.rides[0].wreck = 0.0
		radio._look_left = 0.0
		radio._tick(1.0)
		check(st.fresh_topics().has("wreck"), "a vehicle burnt out is news")
		rides.rides[0].wreck = -1.0
	# Captioned.
	g.voice_captions = true
	g.caption_until = 0.0
	st.take_break()
	_spin(st, 1.5)
	radio._look_left = 0.0
	radio._tick(1.0)
	check(g.caption.begins_with("KPSM: "), "Dub's lines are captioned (%s)" % g.caption)
	check(g.rng.state == dice_before, "the radio's looks and captions never touch the game's dice")
	# A boss fight holds the radio.
	var music = g.features.get("fight_music")
	music.boss_fight = true
	radio._look_left = 0.0
	radio._tick(1.0)
	check(st.hold, "a boss fight holds the radio")
	music.boss_fight = false
