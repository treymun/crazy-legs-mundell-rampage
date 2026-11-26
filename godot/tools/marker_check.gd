## Trail markers (pass 15, src/features/trail_marker.gd, src/chapter_marks.gd)
## and the way the pin is walked after a load (pass 15's 1.11 stall), headless:
##   - a marker is taken on the clock, on an objective (a key, a station) and
##     on first standing in a district, never before gap_least of the last,
##     and not while it is unsafe (hurt this second, in the air, on a ladder,
##     a hand on top of the player, a hostile shot or a fire near, in a boss's
##     arena, a feature holding it back, a partner down);
##   - a death offers BACK TO THE MARKER (its lines, the tap's halves), and it
##     puts the game back exactly as the marker has it (the [marker] floor
##     given: health and rounds), R the chapter's start; dead again straight
##     after coming back, the marker before it;
##   - taking markers changes nothing in play (a bot's run with them and with
##     CHECKPOINTS on BOSSES ONLY end the same, tick for tick), a marker loads
##     the same twice, and a run from one plays back from its replay;
##   - co-op: the party's own file, both players back;
##   - saves: the feature's state round trips a quicksave, an older save loads
##     with none, a replay run's file is its own;
##   - BOSSES ONLY takes none and the death screen is as before;
##   - the pin's way after a load: the game's own key ring, and walked again
##     once a door has stopped swinging;
##   - the program closing (main leaving the tree) waits for a marker still
##     being written on a worker (a write never waited for crashed a window
##     --play-bench on quit, pass 15).
##
##   godot --headless --path godot --script res://tools/marker_check.gd
##   godot ... -- stall     (also the 1.11 run: HARD, REGULAR bot, seed 1,
##                           Hickston with RETRY THE FIGHT on Jerry; minutes)
## Writes its files under the cache folder only.
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const Marker := preload("res://src/features/trail_marker.gd")
const STEP := 1.0 / 60.0


## A feature that holds every marker back (a director's peak, say).
class Veto:
	extends GameFeature

	func id() -> String:
		return "veto"

	func marker_ready() -> bool:
		return false


var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	ChapterMarks.clear_all()
	_rules()
	_unsafe()
	_back()
	_bad_spot()
	_same_play()
	_twice_and_replay()
	_coop()
	_saves()
	_bosses_only()
	_route()
	if OS.get_cmdline_user_args().has("stall"):
		_stall()
	_exit_waits()
	ChapterMarks.clear_all()
	tally.stop()
	check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("MARKER CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	# (Out of the tree already: _exit_waits.)
	main.free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


# ------------------------------------------------------------------ helpers


## A chapter started as the front end starts one (its kit), PLAY page
## defaults but BLUE and the county events off, `marking` the CHECKPOINTS
## choice; every hand asleep when `quiet`.
func _start(level := "hickston", marking := 0, quiet := true) -> Game:
	for key: String in SessionStore.defaults():
		main.options[key] = SessionStore.defaults()[key]
	main.options["hound"] = 0
	main.options["events"] = 0
	main.options["openers"] = 2
	main.options["checkpoints"] = marking
	main.start(level)
	var g: Game = main.game
	g.rng = GameState.Rng.new(4242)
	if quiet:
		for e: Enemy in g.enemies:
			e.dormant = true
			e.alerted = false
	return g


func _feature(g: Game):
	return g.features["trail_marker"]


func _play(g: Game, seconds: float, c: Game.Controls = null) -> void:
	var controls := c if c != null else Game.Controls.new()
	for _t in int(seconds / STEP):
		g.tick(STEP, controls)


## Ticks until the feature's count passes `count` or `seconds` go by.
func _until_marker(g: Game, count: int, seconds: float) -> bool:
	var f = _feature(g)
	for _t in int(seconds / STEP):
		g.tick(STEP, Game.Controls.new())
		if f.count > count:
			return true
	return false


## The nearest open ground cell of a district not yet stood in.
func _new_district(g: Game) -> Vector2:
	var w := g.world
	var f = _feature(g)
	var p := g.player
	var best := Vector2.INF
	for cy in w.height:
		for cx in w.width:
			var x := cx + .5
			var y := cy + .5
			var area := int(w.area[cy * w.width + cx])
			if f.seen.has(area) or w.blocked(x, y, .35) or w.deep_at(x, y):
				continue
			if w.geo != null and w.geo.cells[cy * w.width + cx] != 0:
				continue
			var at := Vector2(x, y)
			if (
				best == Vector2.INF
				or at.distance_to(Vector2(p.x, p.y)) < best.distance_to(Vector2(p.x, p.y))
			):
				best = at
	return best


func _put(g: Game, p: Player, at: Vector2) -> void:
	Modes.place(g, p, at.x, at.y, p.angle)
	p.floor_z = g.world.elevation(at.x, at.y)


## Plain values (a save's JSON as read back) with the keys in `skip` left out.
static func _plain(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


## The first place two plain documents differ ("" when none).
static func _differs(a: Variant, b: Variant, at := "") -> String:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		for key: Variant in da:
			if not db.has(key):
				return "%s.%s missing" % [at, key]
			var inner := _differs(da[key], db[key], "%s.%s" % [at, key])
			if inner != "":
				return inner
		for key: Variant in db:
			if not da.has(key):
				return "%s.%s extra" % [at, key]
		return ""
	if a is Array and b is Array:
		var la: Array = a
		var lb: Array = b
		if la.size() != lb.size():
			return "%s: %d items, %d" % [at, la.size(), lb.size()]
		for i in la.size():
			var inner := _differs(la[i], lb[i], "%s[%d]" % [at, i])
			if inner != "":
				return inner
		return ""
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return "" if absf(float(a) - float(b)) < 1e-4 else "%s: %s, %s" % [at, str(a), str(b)]
	return "" if a == b else "%s: %s, %s" % [at, str(a), str(b)]


# -------------------------------------------------------------------- rules


func _rules() -> void:
	print("TAKEN")
	var g := _start()
	var f = _feature(g)
	_play(g, 1.0)
	check(
		f.last_at >= 0.0 and f.count == 0 and f.seen.size() == 1,
		"the chapter's start counts as the first (no file)"
	)
	check(
		_until_marker(g, 0, Marker.GAP_MOST + 1.0),
		"one on the clock, %.0f s in (gap_most)" % f.taken_at
	)
	var file := ChapterMarks.path_of(ChapterMarks.MARKER, g)
	ChapterMarks.settle()
	check(
		FileAccess.file_exists(file) and file.ends_with("marker-hickston.json"),
		"written to its own file: %s" % file.get_file()
	)
	check(f.stamp_until > g.clock, "the stamp is up (%s)" % Marker.STAMP)
	# An objective too soon after: none.
	_play(g, 2.0)
	g.events.pickup_taken.emit("key_brass")
	check(
		not _until_marker(g, 1, 1.0),
		(
			"a key taken %.0f s after the last: none (gap_least %.0f)"
			% [g.clock - f.last_at, Marker.GAP_LEAST]
		)
	)
	_play(g, Marker.GAP_LEAST)
	g.events.pickup_taken.emit("key_brass")
	check(_until_marker(g, 1, 1.0) and f.count == 2, "a key taken: one")
	_play(g, Marker.GAP_LEAST + .5)
	g.events.station_done.emit("anything")
	check(_until_marker(g, 2, 1.0), "a station done: one")
	_play(g, Marker.GAP_LEAST + .5)
	var at := _new_district(g)
	var before: int = f.seen.size()
	_put(g, g.player, at)
	check(
		_until_marker(g, 3, 1.0) and f.seen.size() == before + 1,
		"first standing in a new district (%.0f, %.0f): one" % [at.x, at.y]
	)
	g.events.pickup_taken.emit("shells")
	check(not _until_marker(g, 4, Marker.GAP_LEAST + 2.0), "shells are no objective")


# ------------------------------------------------------------------- unsafe


func _unsafe() -> void:
	print("NOT TAKEN")
	var g := _start()
	var f = _feature(g)
	_play(g, 1.0)
	var p := g.player
	check(f._safe(), "safe standing at the start, nothing about")
	f.hurt_at = g.clock
	check(not f._safe(), "hurt this second")
	f.hurt_at = -INF
	p.air = .4
	check(not f._safe(), "in the air")
	p.air = 0.0
	p.ladder = 0
	check(not f._safe(), "on a ladder")
	p.ladder = -1
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		if e.hostile and not BossKit.is_boss(e):
			foe = e
			break
	var was := Vector2(foe.x, foe.y)
	foe.dormant = false
	foe.alerted = true
	foe.x = p.x + 1.5
	foe.y = p.y
	check(not f._safe(), "an awake hand on top of the player")
	check(f._safe(true), "but a clock's marker long due is taken with it there (press_after)")
	f.hurt_at = g.clock - Marker.PRESS_CALM * .5
	check(not f._safe(true), "not while hurt within press_calm, though")
	f.hurt_at = -INF
	foe.alerted = false
	check(f._safe(), "a hand asleep beside them does not count")
	foe.dormant = true
	foe.x = was.x
	foe.y = was.y
	var shot := Game.Shot.new()
	shot.x = p.x + 2.0
	shot.y = p.y
	shot.enemy = true
	g.shots.append(shot)
	check(not f._safe(), "a hostile shot in the air near")
	g.shots.clear()
	var fire := Game.Hazard.new()
	fire.x = p.x + .5
	fire.y = p.y
	fire.radius = .8
	g.hazards.append(fire)
	check(not f._safe(), "a fire at their feet")
	g.hazards.clear()
	g.features["veto"] = Veto.new(g)
	check(not f._safe(), "a feature holding it back (marker_ready)")
	g.features.erase("veto")
	g.armory.fuse = 2.0
	check(not f._safe(), "a lit stick")
	g.armory.fuse = 0.0
	# The sheriff awake, the player in his arena.
	var sheriff: Enemy = g.boss
	if sheriff != null:
		sheriff.dormant = false
		sheriff.alerted = true
		_put(g, p, Vector2(sheriff.x - 2.0, sheriff.y))
		check(not f._safe(), "beside an awake boss (his arena or on the way in)")
		sheriff.alerted = false
		sheriff.dormant = true
		_put(g, p, Vector2(float(g.level.spawn[0]), float(g.level.spawn[1])))
	check(f._safe(), "safe again with all of it gone")
	# Hurt the whole time: the clock's marker waits, then comes once it stops.
	var count: int = f.count
	var held := 0.0
	while held < Marker.GAP_MOST + 3.0:
		g.events.player_hurt.emit(1.0, "TEST")
		_play(g, .5)
		held += .5
	check(
		f.count == count and f.want == "clock",
		"hurt every half second past gap_most: none yet (it waits)"
	)
	check(_until_marker(g, count, Marker.CALM_FOR + 1.0), "taken once the hurting stopped")


# --------------------------------------------------------------------- back


func _back() -> void:
	print("BACK TO THE MARKER")
	var g := _start()
	var f = _feature(g)
	_play(g, 3.0)
	var p := g.player
	p.health = 80
	var least_of: Dictionary = ModeData.get_value("marker", "rounds")
	for gun: String in least_of:
		var slot := Weapons.NAMES.find(gun)
		g.armory.reserve[slot] = maxi(g.armory.reserve[slot], int(least_of[gun]) + 16)
	f.take()
	ChapterMarks.settle()
	var file := ChapterMarks.path_of(ChapterMarks.MARKER, g)
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	check(
		doc is Dictionary and int(doc.get("version", 0)) == SessionStore.VERSION,
		"the marker is a save of the current version"
	)
	var at := Vector2(p.x, p.y)
	var clock_at := g.clock
	# Play on: walk off, a hand down, then dead.
	var walk := Game.Controls.new()
	walk.forward = 1.0
	_play(g, 3.0, walk)
	for e: Enemy in g.enemies:
		if e.hostile and e.alive and not BossKit.is_boss(e):
			e.hp = 0
			e.alive = false
			break
	p.health = 0
	g.tick(STEP, Game.Controls.new())
	check(g.defeated() and f.offered(), "dead: BACK TO THE MARKER on offer")
	var lines: Array = f.death_lines()
	check(
		lines.size() == 2 and str(lines[0]).contains("BACK TO THE MARKER"),
		"the death screen says it: %s" % str(lines)
	)
	g.use_key = "Y"
	check(str(f.death_lines()[0]).begins_with("A  BACK"), "on a pad: %s" % str(f.death_lines()))
	g.use_key = "USE"
	check(str(f.death_lines()[1]).begins_with("TAP HERE"), "by touch: %s" % str(f.death_lines()))
	g.use_key = "E"
	main.retry_death(g)
	var back: Game = main.game
	check(back != g, "ENTER: a game loaded from the marker")
	var now := _plain(SessionStore.snapshot(back))
	var then := _plain(doc)
	# The moment's grace, the notice and when it was come back to are the only
	# changes (the floor gives nothing at 80 health and 40 rounds).
	for d: Dictionary in [now, then]:
		var game_part: Dictionary = d["game"]
		for key: String in ["spawn_grace", "notice", "message_until"]:
			game_part.erase(key)
		var marks: Dictionary = d["features"]["trail_marker"]
		marks.erase("back_at")
		marks.erase("back_token")
	var where := _differs(then, now)
	check(
		where == "", "back exactly as the marker had it%s" % ("" if where == "" else ": " + where)
	)
	check(
		(
			Vector2(back.player.x, back.player.y).distance_to(at) < .001
			and absf(back.clock - clock_at) < .001
		),
		"at the marker's spot and clock (%.1f s)" % back.clock
	)
	# The floor: a marker taken at 20 health and 3 rounds.
	back.player.health = 20
	back.armory.reserve[Weapons.REVOLVER] = 3
	var shotgun_owned: bool = back.armory.owned[Weapons.SHOTGUN]
	back.armory.reserve[Weapons.SHOTGUN] = 0
	_feature(back).take()
	back.player.health = 0
	back.tick(STEP, Game.Controls.new())
	main.retry_death(back)
	var floored: Game = main.game
	var least: Dictionary = ModeData.get_value("marker", "rounds")
	check(
		(
			floored.player.health == Marker.HEALTH
			and floored.armory.reserve[Weapons.REVOLVER] == int(least["revolver"])
		),
		(
			"the floor: %d health, %d rounds for the revolver"
			% [floored.player.health, floored.armory.reserve[Weapons.REVOLVER]]
		)
	)
	check(
		shotgun_owned or floored.armory.reserve[Weapons.SHOTGUN] == 0,
		"a gun not carried gets no rounds"
	)
	# R: the chapter's start.
	floored.player.health = 0
	floored.tick(STEP, Game.Controls.new())
	main.restart_chapter(floored)
	var start: Game = main.game
	var spawn := Vector2(float(start.level.spawn[0]), float(start.level.spawn[1]))
	check(
		(
			Vector2(start.player.x, start.player.y).distance_to(spawn) < .01
			and start.clock < 1.0
			and start.player.health == 100
		),
		"R: the chapter's start, from its kit"
	)
	check(
		not _feature(start).offered() and _feature(start).token == "",
		"a chapter started over has no marker of its own yet"
	)


## Two markers; dead within bad_within of coming back to the newest, the one
## before it; dead later, the newest again.
func _bad_spot() -> void:
	print("A BAD SPOT")
	var g := _start()
	var f = _feature(g)
	_play(g, 1.0)
	f.take()
	var first := Vector2(g.player.x, g.player.y)
	_put(g, g.player, first + Vector2(1.0, 0.0))
	_play(g, 2.0)
	f.take()
	var second := Vector2(g.player.x, g.player.y)
	g.player.health = 0
	g.tick(STEP, Game.Controls.new())
	main.retry_death(g)
	var a: Game = main.game
	check(
		Vector2(a.player.x, a.player.y).distance_to(second) < .01, "first death: the newest marker"
	)
	_play(a, 2.0)
	a.player.health = 0
	a.tick(STEP, Game.Controls.new())
	check(
		_feature(a).falls_back(),
		"dead %.0f s after coming back (bad_within %.0f): the one before" % [2.0, Marker.BAD_WITHIN]
	)
	main.retry_death(a)
	var b: Game = main.game
	check(
		(
			Vector2(b.player.x, b.player.y).distance_to(first) < .01
			and b.notice.contains("DEATH TRAP")
		),
		"back one more marker: %s" % b.notice
	)
	var on_file := ChapterMarks.state_on_file(
		ChapterMarks.path_of(ChapterMarks.MARKER, b), "hickston", "trail_marker"
	)
	check(
		_feature(b).token != "" and str(on_file.get("token", "")) == _feature(b).token,
		"it is the newest on file again"
	)
	_play(b, Marker.BAD_WITHIN + 1.0)
	b.player.health = 0
	b.tick(STEP, Game.Controls.new())
	check(
		_feature(b).offered() and not _feature(b).falls_back(),
		"dead well after: BACK TO THE MARKER, that one"
	)
	main.retry_death(b)
	check(
		Vector2(main.game.player.x, main.game.player.y).distance_to(first) < .01,
		"the same marker again"
	)


# ---------------------------------------------------------------- same play


## A bot's 100 s with markers and with BOSSES ONLY: the same, tick for tick.
func _same_play() -> void:
	print("PLAY UNCHANGED")
	var ends: Array = []
	var counts: Array = []
	for marking in [0, 1]:
		var g := _start("hickston", marking, false)
		var pilot := Pilot.new(2, 7)
		for _t in int(100.0 / STEP):
			g.tick(STEP, pilot.steer(g))
			pilot.moved(g)
		ends.append([Replay.state_hash(g), Replay.capture_quiet(g)])
		counts.append(_feature(g).count)
	check(
		counts[0] >= 1 and counts[1] == 0,
		"markers taken with them on (%d), none on BOSSES ONLY" % counts[0]
	)
	var same := GameSnapshot.same(ends[0][1], ends[1][1])
	check(
		ends[0][0] == ends[1][0] and same,
		(
			"the same game either way after 100 s%s"
			% ("" if same else ": " + GameSnapshot.first_difference(ends[0][1], ends[1][1]))
		)
	)


## A marker loaded twice plays on the same; a run from one plays back.
func _twice_and_replay() -> void:
	print("DETERMINISM")
	var g := _start("hickston", 0, false)
	var pilot := Pilot.new(2, 3)
	for _t in int(30.0 / STEP):
		g.tick(STEP, pilot.steer(g))
		pilot.moved(g)
	_feature(g).take()
	var hashes: Array = []
	var last: Game = null
	for _k in 2:
		var loaded := Marker.restore_from(Callable(main, "make_game"), g)
		var bot := Pilot.new(2, 11)
		for _t in int(20.0 / STEP):
			loaded.tick(STEP, bot.steer(loaded))
			bot.moved(loaded)
		hashes.append(Replay.state_hash(loaded))
		if last != null:
			last.dispose()
		last = loaded
	check(hashes[0] == hashes[1], "loaded twice, the same 20 s after")
	var loaded := Marker.restore_from(Callable(main, "make_game"), g)
	var rec := Replay.record(loaded, {"difficulty": 1})
	var bot := Pilot.new(2, 5)
	bot.as_controls = true
	for _t in 900:
		var c := bot.steer(loaded)
		if c.use:
			c.use = false
			rec.act(["use"])
		if c.weapon >= 0:
			rec.act(["select", c.weapon])
			c.weapon = -1
		if c.cycle != 0:
			rec.act(["cycle", c.cycle])
			c.cycle = 0
		rec.tick(STEP, c)
		loaded.tick(STEP, c)
		rec.ticked()
		bot.moved(loaded)
	var pb := Replay.Playback.new(Replay.from_bytes(rec.to_bytes()))
	pb.start(Callable(main, "make_game"))
	pb.run()
	check(
		pb.diverged < 0 and pb.hashes > 0 and pb.end_matches(),
		"a run from a marker plays back from its replay (%d hashes)" % pb.hashes
	)
	if last != null:
		last.dispose()


# --------------------------------------------------------------------- co-op


func _coop() -> void:
	print("CO-OP")
	ChapterMarks.clear_all()
	main.mode_name = Modes.COOP
	main.mode_players = 2
	var g := _start()
	main.mode_name = ""
	main.mode_players = 1
	var f = _feature(g)
	check(g.players.size() == 2, "two players")
	var a := g.players[0]
	var b := g.players[1]
	_put(g, b, Vector2(a.x + 1.0, a.y))
	_play(g, .5)
	b.health = 30
	check(f._safe(), "both up: safe")
	b.health = 0
	check(not f._safe(), "a partner down: not safe")
	b.health = 30
	f.take()
	ChapterMarks.settle()
	var file := ChapterMarks.path_of(ChapterMarks.MARKER, g)
	check(
		file.ends_with("marker-hickston-party.json") and FileAccess.file_exists(file),
		"the party's own file"
	)
	var spots := [Vector2(a.x, a.y), Vector2(b.x, b.y)]
	var walk := Game.Controls.new()
	walk.forward = 1.0
	_play(g, 2.0, walk)
	a.health = 0
	b.health = 0
	g.tick(STEP, Game.Controls.new())
	check(g.defeated() and f.offered(), "everyone down: BACK TO THE MARKER")
	main.retry_death(g)
	var back: Game = main.game
	var ok := back.players.size() == 2
	for i in mini(2, back.players.size()):
		var q := back.players[i]
		var spot: Vector2 = spots[i]
		ok = ok and q.health >= Marker.HEALTH and Vector2(q.x, q.y).distance_to(spot) < .05
	check(
		ok,
		(
			"both back at the marker, each with the floor (%d, %d health)"
			% [back.players[0].health, back.players[1].health]
		)
	)
	check(
		not FileAccess.file_exists(ChapterMarks.path("marker", "hickston", false)),
		"the host's own marker file untouched"
	)


# --------------------------------------------------------------------- saves


func _saves() -> void:
	print("SAVES")
	var g := _start()
	var f = _feature(g)
	_play(g, 1.0)
	f.take()
	_play(g, Marker.GAP_LEAST + 1.0)
	g.events.pickup_taken.emit("key_steel")
	_play(g, 1.0)
	var file := OS.get_cache_dir().path_join("clmr-marker-check").path_join("quick.json")
	check(SessionStore.save(g, file), "a quicksave with markers taken")
	var loaded := SessionStore.read(file, Callable(main, "make_game"), false, "hickston")
	var f2 = _feature(loaded) if loaded != null else null
	check(
		(
			f2 != null
			and f2.token == f.token
			and f2.count == f.count
			and f2.seen == f.seen
			and absf(f2.last_at - f.last_at) < .001
		),
		"its markers' state comes back with it (%d taken)" % f.count
	)
	# (v10: made before the markers; pass 15 remade v11's with them in)
	var old := SessionStore.read(
		"res://tools/saves/v10_hickston_fight.json", Callable(main, "make_game")
	)
	check(
		old != null and _feature(old).last_at < 0.0 and _feature(old).token == "",
		"an older save loads with no marker state"
	)
	if old != null:
		old.player.health = 0
		check(not _feature(old).offered(), "and offers none")
	g.replay = true
	check(
		ChapterMarks.path_of(ChapterMarks.MARKER, g).ends_with("marker-hickston-replay.json"),
		"a replay run's marker is its own file"
	)
	g.replay = false


# ---------------------------------------------------------------- bosses only


func _bosses_only() -> void:
	print("BOSSES ONLY")
	ChapterMarks.clear_all()
	var g := _start("hickston", 1)
	var f = _feature(g)
	_play(g, Marker.GAP_MOST + 3.0)
	g.events.pickup_taken.emit("key_brass")
	_play(g, 2.0)
	check(
		f.count == 0 and not FileAccess.file_exists(ChapterMarks.path_of(ChapterMarks.MARKER, g)),
		"none taken, no file"
	)
	g.player.health = 0
	g.tick(STEP, Game.Controls.new())
	check(
		not f.offered() and f.death_lines().is_empty(),
		"the death screen as before (no marker lines)"
	)
	main.retry_death(g)
	check(main.game.clock < 1.0, "ENTER: the chapter's start")


# --------------------------------------------------------------------- route


func _route() -> void:
	print("THE PIN'S WAY")
	var g := _start()
	g.keys["key_brass"] = true
	var file := OS.get_cache_dir().path_join("clmr-marker-check").path_join("keys.json")
	SessionStore.save(g, file)
	var loaded := SessionStore.read(file, Callable(main, "make_game"), false, "hickston")
	loaded.objective_route(
		Vector2(float(loaded.level.spawn[0]) + 3.0, float(loaded.level.spawn[1]))
	)
	check(
		is_same(loaded.route.keys, loaded.keys) and loaded.route.keys.has("key_brass"),
		"after a load the way is walked with the game's own key ring (it walked every key door shut)"
	)
	# A way walked while something stood in it (Jerry's gate mid-swing):
	# made not to reach the player, it is walked again within a second or so.
	var target := Vector2(float(loaded.level.spawn[0]) + 6.0, float(loaded.level.spawn[1]))
	loaded.objective_route(target)
	var p := loaded.player
	var reached: int = loaded.route.distance(p.x, p.y, loaded.world.stand(p))
	loaded.route.steps.fill(FlowField.FAR)
	loaded.route.next_at = loaded.clock
	var lost := int(loaded.objective_route(target)[1])
	var again := -1
	for _t in 120:
		loaded.tick(STEP, Game.Controls.new())
		again = int(loaded.objective_route(target)[1])
		if again >= 0:
			break
	check(
		reached < FlowField.FAR and lost < 0 and again >= 0,
		"a way that stopped short of the player is walked again (1.11: the bot stood 880 s)"
	)


## 1.11 itself: HARD, the REGULAR bot, seed 1 dies at Jerry, RETRY THE FIGHT,
## and now walks on to Bessie (it stood 880 s by the rodeo grandstand).
## A marker's write left going on a worker as the program closes: main's
## _exit_tree waits for it (ChapterMarks.settle). Takes main out of the tree.
func _exit_waits() -> void:
	var g := _start()
	ChapterMarks.write_soon(ChapterMarks.MARKER, g)
	check(ChapterMarks._task >= 0, "a marker's write goes on a worker")
	root.remove_child(main)
	check(ChapterMarks._task == -1, "the program closing waits for a marker's write")


func _stall() -> void:
	print("THE 1.11 RUN (HARD, REGULAR, seed 1)")
	for key: String in SessionStore.defaults():
		main.options[key] = SessionStore.defaults()[key]
	main.options["difficulty"] = 2
	main.options["bench"] = 1
	main.options["opener"] = 0
	main.options["openers"] = 0
	main.start("hickston", null, [], false, null)
	var attempt := 0
	var won := false
	while attempt < 3 and not won:
		attempt += 1
		var g: Game = main.game
		g.rng = GameState.Rng.new(1009 + attempt)
		var pilot := Pilot.new(1, 13 + attempt)
		var start := g.clock
		while g.clock - start < 400.0:
			g.tick(STEP, pilot.steer(g))
			pilot.moved(g)
			if g.won or g.player.health <= 0:
				break
		won = g.won
		print("  attempt %d: %s at %.0f s" % [attempt, "won" if won else "down", g.clock - start])
		if not won:
			main.retry_death(g)
	check(won, "Hickston cleared after the retry")
