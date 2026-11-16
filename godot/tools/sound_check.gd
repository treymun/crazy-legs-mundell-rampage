## The sound's checks (tools/check_fixes.gd runs them; this also runs on its
## own):
##
##   Godot --headless --path <project> --script res://tools/sound_check.gd
##
## Hearing (src/hearing.gd): on a level with decks, a source in plain sight is
## heard open, one behind a wall dull, one a doorway round only a little dull,
## a body on the floor above through the floor; it never changes play, and
## asking costs little. The bank: every take VARIANTS deals and every cue the
## game names at run time (barks, boss lines, enemies' cries, guns, floors,
## materials) is made, or made in code (Assets.MADE_CUES). A voice's level
## reaches the mixer only when it changes, and never for a playing voice with
## no window (Sound.set_level: what kept long checks from quitting). Nobody listens
## here: this says the sounds are there and placed, not how they sound.
extends SceneTree

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(main, func(ok: bool, text: String) -> void: _check(ok, text))
	print("")
	print("SOUND CHECK OK" if failures.is_empty() else "%d SOUND CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func run(main, check: Callable) -> void:
	print("\nSOUND (HEARING, THE BANK)")
	_hearing(main, check)
	_bank(main, check)
	_levels(main, check)


## Sound.set_level: a level only reaches the mixer when it changes, and with no
## window a playing voice's is only noted (each change of a playing voice's
## level costs the mixer a record whose clean-up grows with the square of how
## many: checks that tick minutes in one frame stalled for minutes after OK).
static func _levels(main, check: Callable) -> void:
	var voice := AudioStreamPlayer.new()
	main.sound.add_child(voice)
	var hush := AudioStreamWAV.new()
	hush.format = AudioStreamWAV.FORMAT_16_BITS
	hush.mix_rate = 22050
	var quiet := PackedByteArray()
	quiet.resize(22050 * 4)
	hush.data = quiet
	voice.stream = hush
	Sound.set_level(voice, .5)
	var stopped_set := is_equal_approx(voice.volume_linear, .5)
	voice.play()
	for i in 20000:
		Sound.set_level(voice, .2 + .6 * fposmod(i * .37, 1.0))
	Sound.set_level(voice, .3)
	check.call(
		(
			stopped_set
			and voice.playing
			and is_equal_approx(voice.volume_linear, .5)
			and is_equal_approx(Sound.level_of(voice), .3)
		),
		(
			"headless, a playing voice's level is noted (%.2f) and not handed to the mixer (%.2f)"
			% [Sound.level_of(voice), voice.volume_linear]
		)
	)
	voice.stop()
	Sound.set_level(voice, .3)
	check.call(is_equal_approx(voice.volume_linear, .3), "a stopped voice's level is set as ever")
	voice.queue_free()


## Every cell near the player, sorted by what lies between: open, round a
## corner, through a wall; and a body on a deck over the player's head.
static func _hearing(main, check: Callable) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	var p := g.local_player
	p.flow.update(p.x, p.y, g.clock, g.world.stand(p))
	var w := g.world
	var kinds := {}
	var round_dull := true
	var before := var_to_str([p.x, p.y, p.eye, g.rng.state, g.enemies.size()])
	var places: Array[Vector2] = []
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var x := floorf(p.x) + dx + .5
			var y := floorf(p.y) + dy + .5
			if x >= 0.0 and y >= 0.0 and x < w.width and y < w.height and not w.blocked(x, y):
				places.append(Vector2(x, y))
	for at in places:
		g.clock += .001
		var cut := g.sound_cutoff(at.x, at.y)
		var gain := g.hearing.gain(g, at.x, at.y)
		var kind := "other"
		if gain == 1.0:
			kind = "open"
		elif gain == Hearing.ROUND_GAIN:
			kind = "round"
			round_dull = round_dull and cut <= Hearing.ROUND_CUTOFF
		elif gain == Hearing.THROUGH_WALL_GAIN:
			kind = "wall"
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	check.call(
		int(kinds.get("open", 0)) > 0, "in plain sight is heard open (%d)" % kinds.get("open", 0)
	)
	check.call(int(kinds.get("wall", 0)) > 0, "behind walls is muffled (%d)" % kinds.get("wall", 0))
	check.call(
		int(kinds.get("round", 0)) > 0 and round_dull,
		"a doorway round is only a little dull (%d)" % kinds.get("round", 0)
	)
	check.call(not kinds.has("other"), "every place is open, round or through a wall")
	# What it cost before 3.0.0: two flat sight tests per place.
	var started := Time.get_ticks_usec()
	for at in places:
		w.visible(p.x, p.y, at.x, at.y)
		w.visible(p.x, p.y, at.x, at.y)
	var old := float(Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	for at in places:
		g.clock += .001
		g.sound_position(at.x, at.y)
		g.sound_cutoff(at.x, at.y)
	var now := float(Time.get_ticks_usec() - started)
	check.call(
		now < old * 3.0 + 2000.0,
		(
			"hearing a place costs little (%.0f us, was %.0f)"
			% [now / places.size(), old / places.size()]
		)
	)
	_through_floor(g, check)
	var after := var_to_str([p.x, p.y, p.eye, g.rng.state, g.enemies.size()])
	check.call(before == after, "hearing changes nothing in play")


## A body standing on a deck right over the player is heard through the floor:
## quieter and duller than the same body on the player's own floor.
static func _through_floor(g: Game, check: Callable) -> void:
	var w := g.world
	var p := g.local_player
	var e: Enemy = null
	for one: Enemy in g.enemies:
		e = one
		break
	check.call(e != null and w.geo != null, "hickston has decks and a hand to stand on one")
	if e == null or w.geo == null:
		return
	var spot := Vector2.INF
	var deck := 0.0
	for y in w.height:
		for x in w.width:
			var cx := x + .5
			var cy := y + .5
			if w.blocked(cx, cy):
				continue
			var top := w.floor_under(cx, cy, 100.0)
			if top > w.elevation(cx, cy) + 1.2:
				spot = Vector2(cx, cy)
				deck = top
				break
		if spot != Vector2.INF:
			break
	check.call(spot != Vector2.INF, "hickston has a deck over open floor")
	if spot == Vector2.INF:
		return
	var keep := [p.x, p.y, p.eye, p.floor_z, e.x, e.y, e.floor_z]
	p.x = spot.x + .3
	p.y = spot.y
	p.floor_z = w.elevation(p.x, p.y)
	p.eye = p.floor_z + .95
	e.x = spot.x - .3
	e.y = spot.y
	e.floor_z = deck
	g.clock += .001
	var above := g.sound_position(e.x, e.y)
	var above_cut := g.sound_cutoff(e.x, e.y)
	e.floor_z = w.elevation(e.x, e.y)
	g.clock += .001
	var level := g.sound_position(e.x, e.y)
	var level_cut := g.sound_cutoff(e.x, e.y)
	check.call(
		above.x < level.x * .6 and above_cut <= Hearing.THROUGH_FLOOR_CUTOFF,
		(
			"a hand on the deck overhead is heard through the floor (%.2f vs %.2f, %d Hz)"
			% [above.x, level.x, above_cut]
		)
	)
	check.call(level_cut == Sound.OPEN_CUTOFF, "the same hand beside the player is heard open")
	p.x = keep[0]
	p.y = keep[1]
	p.eye = keep[2]
	p.floor_z = keep[3]
	e.x = keep[4]
	e.y = keep[5]
	e.floor_z = keep[6]


static func _bank(main, check: Callable) -> void:
	var art: Assets = main.art
	var missing: Array = []
	var asked := 0
	var names: Array = []
	for key: String in Sound.VARIANTS:
		names.append_array(Sound.VARIANTS[key])
	var barks = load("res://src/features/enemy_barks.gd")
	for who: String in barks.LINES:
		for moment: String in barks.LINES[who]:
			for n in (barks.LINES[who][moment] as Array).size():
				names.append("bark_%s_%s_%d" % [who, moment, n])
	var bosses = load("res://src/features/boss_voices.gd")
	for who: String in bosses.LINES:
		for moment: String in bosses.MOMENTS:
			names.append("boss_%s_%s" % [who, moment])
	for kind: String in Enemy.VOICES:
		var voice := str(Enemy.VOICES[kind])
		var takes: int = Enemy.VOICE_TAKES.get(voice, 1)
		for moment: String in ["pain", "down"]:
			if moment == "pain" and Enemy.DEATH_ONLY.has(voice):
				continue
			if takes == 1:
				names.append("%s_%s" % [voice, moment])
			else:
				for t in takes:
					names.append("%s_%s_%d" % [voice, moment, t + 1])
	for material: String in ["cloth", "shell", "tool"]:
		names.append("actor_%s_pain" % material)
		names.append("actor_%s_down" % material)
	for slot in Weapons.NAMES.size():
		var gun := str(Weapons.NAMES[slot])
		names.append("equip_" + gun)
		if not gun in ["crowbar", "slingblade"]:
			names.append("dry_" + gun)
	for surface: Variant in LevelData.SURFACE_SOUNDS.values():
		for k in 2:
			names.append("step_%s_%d" % [surface, k])
	for cue: Variant in Materials.CUES.values():
		names.append(str(cue))
	names.append("metal_down")
	for name: String in names:
		asked += 1
		if not art.has_cue(name) and not Assets.MADE_CUES.has(name):
			missing.append(name)
	check.call(
		missing.is_empty(), "every cue the game names is made (%d asked) %s" % [asked, missing]
	)
