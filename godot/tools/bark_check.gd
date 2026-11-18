## The county's talk in a real game (features/enemy_barks.gd, barks.gd,
## features/boss_voices.gd), headless: the balance bot plays chapters with an
## ear that keeps every line played on the game clock and how long it lasts.
## The hands' barks fire at a sane rate (lines a minute within RATE), never
## the same line twice running, never over another line still playing (a
## boss's line and a tough guy's piece cut in by design and are left out),
## Mundell sizes up the chapter, and the game played with the talk is the
## same as with CHATTER OFF (barks are sound and captions, their own dice:
## play exact). Since pass 10: until then enemy_barks looked for its signals
## on the game, which has none since GameEvents, and none of this was heard.
##
##   godot --headless --path godot --script res://tools/bark_check.gd
##       [-- chapters=hickston,sawmill] [seconds=240]
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const STEP := 1.0 / 60.0
## The hands' lines a minute of play a chapter must come to (at the bot's
## pace, NORMAL), and how long a stretch is played.
const RATE := [1.5, 14.0]

var main
var failures: Array = []
var seconds := 240.0


## Every cue is there; keeps what was played and when, and says someone is
## talking while a spoken line (Sound.SPEECH) is still going, by its length.
class Ear:
	extends QuietSound
	var art: Assets
	var game: Game
	## [clock, cue, length] of every spoken line played.
	var said: Array = []
	var talking_until := -1.0

	func has(_cue: String) -> bool:
		return true

	func _length(cue: String) -> float:
		var stream := art.cue(cue) if art != null else null
		return stream.get_length() if stream != null else 1.6

	func _note(cue: String) -> float:
		var speech := false
		for prefix: String in Sound.SPEECH:
			speech = speech or cue.begins_with(prefix)
		if not speech:
			return 0.0
		var length := _length(cue)
		said.append([game.clock, cue, length])
		talking_until = maxf(talking_until, game.clock + length)
		return length

	func play(name: String, _volume := 1.0, _pan := 0.0, _cutoff := 0.0) -> void:
		_note(name)

	func play_voice(name: String, _volume := 1.0, _pan := 0.0) -> float:
		return _note(name)

	func talking() -> bool:
		return game != null and game.clock < talking_until

	func hush_speech() -> void:
		talking_until = game.clock if game != null else -1.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var chapters: Array = ["hickston", "sawmill"]
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("chapters="):
			chapters = Array(a.substr(9).split(",", false))
		elif a.begins_with("seconds="):
			seconds = float(a.substr(8))
	print("BARKS IN PLAY (the balance bot, NORMAL, %d s a chapter)" % int(seconds))
	for chapter: String in chapters:
		_chapter(str(chapter))
	_exact(str(chapters[0]))
	print("")
	print("BARK CHECK OK" if failures.is_empty() else "%d BARK CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## The chapter from its kit, the bot playing it `seconds` (or to its end)
## with talk set to `chatter`. [the game, its ear].
func _play(chapter: String, chatter: int) -> Array:
	main.start(chapter, null, [], false, null)
	var g: Game = main.game
	NetCoop.chapter_kit(g, chapter)
	g.configure({"difficulty": 1})
	g.rng = GameState.Rng.new(1009)
	g.chatter = chatter
	g.barks.enabled = true
	var ear := Ear.new()
	ear.art = main.art
	ear.game = g
	g.sound = ear
	g.speaker = ear
	g.cheats.god = true
	var pilot := Pilot.new(2, 1)
	while g.clock < seconds and not g.won:
		g.tick(STEP, pilot.steer(g))
		pilot.moved(g)
	return [g, ear]


func _chapter(chapter: String) -> void:
	var made := _play(chapter, CussLines.CUSSIN)
	var g: Game = made[0]
	var ear: Ear = made[1]
	var hands := 0
	var mundell := 0
	var bosses := 0
	var other := 0
	var repeats := 0
	var over: Array = []
	var last_hand := ""
	var busy_until := -1.0
	for row: Array in ear.said:
		var at: float = row[0]
		var cue: String = row[1]
		var length: float = row[2]
		# A boss's line and a tough guy's piece cut in (hush_speech).
		var boss := cue.begins_with("boss_") or cue.begins_with("bark_tough_")
		var his := cue.contains("mundell_")
		var hand := (
			cue.begins_with("bark_")
			or (cue.begins_with("cuss_") and not his and not cue.begins_with("cuss_dj"))
		)
		if boss:
			bosses += 1
		elif his:
			mundell += 1
		elif hand:
			hands += 1
			if cue == last_hand:
				repeats += 1
			last_hand = cue
		else:
			other += 1  # the level's radio talk, a shout
		if not boss and at < busy_until - .001:
			over.append("%s at %.1f s" % [cue, at])
		# A boss's line cuts in (hush_speech): what it cut off is over.
		busy_until = maxf(busy_until if not boss else at, at + length)
	# Said aloud, or shown while someone else was talking (Barks).
	var opened: bool = g.barks.last_at.has("start")
	var minutes := maxf(.1, g.clock / 60.0)
	var rate := hands / minutes
	print(
		(
			"  %-9s %.0f s: hands %d (%.1f a minute), Mundell %d, bosses %d, other talk %d"
			% [chapter, g.clock, hands, rate, mundell, bosses, other]
		)
	)
	_check(
		rate >= RATE[0] and rate <= RATE[1],
		(
			"%s: the hands talk %.1f lines a minute (band %.1f to %.1f)"
			% [chapter, rate, RATE[0], RATE[1]]
		)
	)
	_check(repeats == 0, "%s: no hand says the same line twice running (%d)" % [chapter, repeats])
	_check(over.is_empty(), "%s: no line starts over another still playing %s" % [chapter, over])
	_check(opened, "%s: Mundell sizes the chapter up as it starts" % chapter)


## The same stretch with the talk and with CHATTER OFF: the same game.
func _exact(chapter: String) -> void:
	var keep := seconds
	seconds = 60.0
	var talk: Game = _play(chapter, CussLines.CUSSIN)[0]
	var a := GameSnapshot.capture(talk)
	var quiet: Game = _play(chapter, CussLines.OFF)[0]
	var b := GameSnapshot.capture(quiet)
	seconds = keep
	_check(
		GameSnapshot.same(a, b) and is_equal_approx(talk.clock, quiet.clock),
		"%s: a minute played with the talk is the same game as with CHATTER OFF" % chapter
	)
