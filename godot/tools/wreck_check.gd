## Broken scenery in real pieces (src/features/wreckage.gd; tools/check_all.gd
## runs it, quick too; this also runs on its own):
##
##   godot --headless --path godot --script res://tools/wreck_check.gd [-- levels=hickston,fair]
##
## On the chapters, County Run maps and the hub it breaks one of every kind of
## breakable that has `pieces` (breakables.cfg), a few windows and the fence
## cells that open, and checks that each throws real pieces (cut from its own
## model or picture), that they all come to rest (asleep, costing nothing) on
## a floor within TOL and never inside a wall, a floor, a deck or furniture,
## and that nothing breaks into pieces on the 5v5 and 2v2 maps. Then the cap:
## many breaks at once never leave more than `most` pieces once the oldest
## have shrunk away; a save put back throws nothing; and a tick with every
## piece asleep costs next to nothing.
extends SceneTree

const DT := 1.0 / 60.0
const TOL := .03
## Between them every kind that has `pieces` (levels=... for others: fair,
## quarry, sawmill, county_hickston, county_bayou).
const LEVELS := [
	"hickston",
	"bayou",
	"mothership",
	"speedway",
	"moonshine",
	"range",
	"hub",
	"county_quarry",
]
const VERSUS := ["grainyard", "pineacres"]

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var levels: Array = LEVELS
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("levels="):
			levels = Array(String(arg).substr(7).split(",", false))
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	for id: String in levels:
		print("\n%s" % id.to_upper())
		_level(_game(main, id))
	print("\nVERSUS MAPS")
	for id: String in VERSUS:
		var g := _game(main, id)
		_check(not g.features["wreckage"].on, "%s: no pieces on a versus map" % id)
	print("\nCAP, SAVES, COST")
	_cap(_game(main, "hickston"))
	_saves(_game(main, "hickston"))
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("WRECK CHECK OK" if failures.is_empty() else "%d WRECK CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main: Control, id: String) -> Game:
	var game: Game = main.make_game(id)
	game.configure({})
	game.cheats.god = true
	for e: Enemy in game.enemies:
		e.dormant = true
	return game


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
	else:
		print("  FAIL ", text)
		failures.append(text)


func _ticks(game: Game, n: int) -> void:
	var held := Game.Controls.new()
	for i in n:
		game.tick(DT, held)


## Every kind on the level broken, its pieces thrown, all at rest on floors.
func _level(game: Game) -> void:
	var wreck = game.features["wreckage"]
	var breaks = game.features["breakables"]
	var walls = game.features["wall_breaks"]
	_check(wreck.on, "%s: pieces are on" % game.level.id)
	wreck.most = 1000
	var kinds := {}
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if str(p.spec.get("pieces", "")) != "" and not kinds.has(p.image):
			kinds[p.image] = i
	for image: String in kinds:
		var i: int = kinds[image]
		var p = breaks.pieces[i]
		if p.broken:
			continue  # set off by a blast already (its pieces were checked with it)
		var before: int = wreck.wrecks.size()
		var t0 := Time.get_ticks_usec()
		breaks.strike(i, 9999.0, 1.0, 0.0)
		_ticks(game, 1)
		var took := (Time.get_ticks_usec() - t0) / 1000.0
		var made: int = wreck.wrecks.size() - before
		_check(made > 0, "%s: %s throws pieces (%d, %.1f ms)" % [game.level.id, image, made, took])
		if made > 0:
			print("  ok   %-28s %2d pieces  %5.1f ms" % [image, made, took])
		_ticks(game, 20)
	var windows := 0
	for face in walls.windows:
		if windows >= 3:
			break
		if face.broken:
			continue
		var before: int = wreck.wrecks.size()
		walls._break_window(face, false)
		_ticks(game, 1)
		_check(wreck.wrecks.size() > before, "%s: a window's glass flies" % game.level.id)
		windows += 1
	var fences := 0
	for f in walls.fences.values():
		if fences >= 2 or not f.opens or f.stage != 0:
			continue
		var before: int = wreck.wrecks.size()
		walls._knock(f, f.most * .5, 1.0, 0.0)
		_ticks(game, 1)
		var shot: int = wreck.wrecks.size() - before
		walls._knock(f, f.most * 2.0, 1.0, 0.0)
		_ticks(game, 1)
		var through: int = wreck.wrecks.size() - before - shot
		_check(
			shot > 0 and through > 0,
			"%s: a fence's boards fly (%d, %d)" % [game.level.id, shot, through]
		)
		fences += 1
	if windows + fences > 0:
		print("  ok   %d windows, %d fence cells" % [windows, fences])
	var waited := 0
	var busiest := 0.0
	while wreck.physics.moving() and waited < 900:
		var t0 := Time.get_ticks_usec()
		wreck._tick(DT)
		busiest = maxf(busiest, (Time.get_ticks_usec() - t0) / 1000.0)
		_ticks(game, 9)
		waited += 10
	print("  ..   the pieces' busiest tick while settling: %.1f ms" % busiest)
	_check(
		not wreck.physics.moving(),
		"%s: every piece comes to rest (%.1f s)" % [game.level.id, waited * DT]
	)
	var shown := 0
	for w in wreck.wrecks:
		if w.body.awake and shown < 6:
			shown += 1
			print(
				(
					"       still moving: %s#%d at %s v %s w %s"
					% [w.key, w.index, w.body.p, w.body.v, w.body.w]
				)
			)
	var worst := 0.0
	var where := ""
	var worst_body = null
	for w in wreck.wrecks:
		if w.floats == 2 or w.fading >= 0.0:
			continue
		var d: float = wreck.physics.inside(w.body)
		if d > worst:
			worst = d
			worst_body = w.body
			where = (
				"%s at %.2f,%.2f,%.2f floats %d awake %s"
				% [w.key, w.body.p.x, w.body.p.y, w.body.p.z, w.floats, w.body.awake]
			)
	if worst > TOL:
		var b = worst_body
		var turn := Basis(b.q)
		for k in 8:
			var c: Vector3 = b.p + turn * b.points[k]
			print(
				(
					"       corner %s floor %.3f blocked %s solid %s ground %.2f"
					% [
						c,
						Tumble.floor_at(game.world, c.x, c.y, maxf(c.z, b.p.z) + .02),
						game.world.blocked(c.x, c.y, 0.0, c.z),
						wreck.physics.solid(c),
						game.world.elevation(c.x, c.y)
					]
				)
			)
	_check(
		worst <= TOL,
		"%s: no piece rests inside anything (worst %.3f %s)" % [game.level.id, worst, where]
	)
	var floating := 0
	var hung := ""
	for w in wreck.wrecks:
		if w.floats == 2 or w.fading >= 0.0:
			continue
		if wreck.physics.unsupported(w.body):
			floating += 1
			var low := Vector3(0, 0, INF)
			for k in 8:
				var c: Vector3 = w.body.p + Basis(w.body.q) * w.body.points[k]
				if c.z < low.z:
					low = c
			hung = (
				"%s#%d at %s lowest %s floor %.3f awake %s"
				% [
					w.key,
					w.index,
					w.body.p,
					low,
					Tumble.floor_at(game.world, low.x, low.y, w.body.p.z + .02),
					w.body.awake
				]
			)
			print("       hangs: " + hung)
	_check(
		floating == 0,
		(
			"%s: every piece lies on something (%d hang%s)"
			% [game.level.id, floating, ": " + hung if hung != "" else ""]
		)
	)
	# A stave or a board never rests on its end or edge unless it leans on
	# something (a wall, another piece).
	var on_end := 0
	var leaning := 0
	for w in wreck.wrecks:
		var b: WreckPhysics.Body = w.body
		if w.fading >= 0.0:
			continue  # shrinking away (wedged where nothing fits)
		b.turn = Basis(b.q)
		if WreckPhysics.standing(b):
			if b.propped:
				leaning += 1
			else:
				on_end += 1
				print(
					(
						"       on its end: %s#%d at %s half %s (tipped %.1f s, kicked %.1f, turn %s)"
						% [w.key, w.index, b.p, b.half, b.tipping, b.kicked, b.turn]
					)
				)
	_check(
		on_end == 0,
		(
			"%s: no piece rests on its end unless propped (%d; %d leaning)"
			% [game.level.id, on_end, leaning]
		)
	)
	print(
		(
			"  ok   %d pieces at rest after %.1f s, worst %.3f in"
			% [wreck.wrecks.size(), waited * DT, worst]
		)
	)


## Many breaks at once: never more than `most` once the oldest shrank away.
func _cap(game: Game) -> void:
	var wreck = game.features["wreckage"]
	var breaks = game.features["breakables"]
	wreck.most = 48
	# The breakables alone: a set piece brought down by them (a shed whose
	# propane goes up) keeps throwing pieces for seconds (set_piece_check
	# holds those). Kept by `sets` (its tick still runs), out of wreckage's sight.
	var sets = game.features.get("set_pieces")
	game.features.erase("set_pieces")
	var top := 0
	var busiest := 0.0
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if p.broken or str(p.spec.get("pieces", "")) == "":
			continue
		breaks.strike(i, 9999.0, 0.0, 1.0)
		_ticks(game, 1)
		var t0 := Time.get_ticks_usec()
		wreck._tick(DT)
		busiest = maxf(busiest, (Time.get_ticks_usec() - t0) / 1000.0)
		top = maxi(top, wreck.wrecks.size())
	print("  ..   breaking everything at once, 48 at most: busiest tick %.1f ms" % busiest)
	_check(top <= 48 + 24, "the pieces never pile past most + 24 (%d)" % top)
	_ticks(game, 60)
	var live := 0
	for w in wreck.wrecks:
		if w.fading < 0.0:
			live += 1
	_check(
		wreck.wrecks.size() <= 48 and live <= 48,
		"after the oldest shrink away, at most `most` lie about (%d)" % wreck.wrecks.size()
	)
	print("  ok   cap: at most %d at once, %d after" % [top, wreck.wrecks.size()])
	if sets != null:
		game.features["set_pieces"] = sets


## A save put back throws nothing; all asleep costs next to nothing.
func _saves(game: Game) -> void:
	var wreck = game.features["wreckage"]
	var breaks = game.features["breakables"]
	var struck := 0
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if (
			struck < 4
			and not p.broken
			and str(p.spec.get("pieces", "")) != ""
			and not p.spec.has("blast")
		):
			breaks.strike(i, 9999.0, 1.0, 0.0)
			struck += 1
	_ticks(game, 2)
	var saved: Dictionary = breaks.save()
	var fresh: Game = game  # the same level put back from its save
	Features.restore_all(fresh, {"breakables": saved})
	_ticks(fresh, 5)
	_check(fresh.features["wreckage"].wrecks.is_empty(), "a save put back throws no pieces")
	# Every piece asleep: a tick of the feature costs next to nothing.
	struck = 0
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if (
			struck < 3
			and not p.broken
			and str(p.spec.get("pieces", "")) != ""
			and not p.spec.has("blast")
		):
			breaks.strike(i, 9999.0, 1.0, 0.0)
			struck += 1
	var waited := 0
	while wreck.physics.moving() and waited < 900:
		_ticks(game, 10)
		waited += 10
	# Each piece is asked once whether it still lies on something.
	_ticks(game, 60)
	while wreck.physics.moving() and waited < 1800:
		_ticks(game, 10)
		waited += 10
	var t0 := Time.get_ticks_usec()
	for k in 120:
		wreck._tick(DT)
	var idle := (Time.get_ticks_usec() - t0) / 120.0
	_check(idle < 150.0, "a tick with %d pieces asleep costs %.0f us" % [wreck.wrecks.size(), idle])
	print("  ok   %d pieces asleep: %.0f us a tick" % [wreck.wrecks.size(), idle])
