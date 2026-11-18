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
## piece asleep costs next to nothing. And the breaks themselves (pass 11):
## two breaks of a kind struck the same way come apart differently; the side
## struck matters (the pieces go away from it, the fracture's origin is on
## it); buckshot at arm's length throws harder than a revolver round; every
## piece names its stuff and shape and has raw cut faces; a break throws fine
## debris, never more than its cap; a shot that does not break a thing
## chips it.
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
	print("\nBREAKS DIFFER")
	_breaks(_game(main, "hickston"))
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
					"       still moving: %s#%d at %s v %s w %s awake %.1f s"
					% [w.key, w.index, w.body.p, w.body.v, w.body.w, w.body.awake_for]
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


## A breakable of `image` on the game's level, whole, or null.
func _piece_of(game: Game, image: String):
	for p in game.features["breakables"].pieces:
		if p.image == image and not p.broken:
			return p
	return null


## The pieces one break of `p` throws when struck at its side `side` (a
## unit way across the map) with `force`: [variant, turn, [middles], mean
## speed, mean way]. The pieces are taken away again after.
func _strike(wreck, p, side: Vector3, force: float) -> Array:
	var src: Dictionary = wreck._source(p)
	var hit = wreck.Impact.new()
	var foot: float = wreck.game.world.stand(p) + p.z
	hit.at = Vector3(p.x, p.y, foot + p.height * .5) + side * p.radius * .8
	hit.way = -side
	hit.force = force
	hit.kind = "shot"
	var before: int = wreck.wrecks.size()
	wreck._burst_apart(src, hit, [], wreck.per_break, 1.0)
	var middles: Array = []
	var speed := 0.0
	var way := Vector3.ZERO
	var made: Array = wreck.wrecks.slice(before)
	for w in made:
		middles.append(w.body.p)
		speed += w.body.v.length()
		way += w.body.v
	for w in made:
		wreck._drop(w)
	var n := maxf(1.0, made.size())
	return [wreck.last_variant, wreck.last_turn, middles, speed / n, way / n]


func _breaks(game: Game) -> void:
	var wreck = game.features["wreckage"]
	wreck.most = 1000
	var forms := ["board", "stave", "ring", "disc", "shard", "sheet", "clump", "chunk"]
	for image: String in ["prop_barrel", "prop_crate", "town_propane_tank", "town_range_hay_bale"]:
		var p = _piece_of(game, image)
		if p == null:
			_check(false, "hickston has a whole %s" % image)
			continue
		# Every variant cut (as the level's first frames would).
		var key: String = wreck._source(p)["key"]
		for v in WreckCuts.variants(key):
			WreckCuts.parts(game.art, key if v == 0 else "%s^%d" % [key, v])
		var west := Vector3(-1, 0, 0)
		var a := _strike(wreck, p, west, 1.0)
		var b := _strike(wreck, p, west, 1.0)
		var same: bool = a[0] == b[0] and absf(float(a[1]) - float(b[1])) < .01
		var am: Array = a[2]
		var bm: Array = b[2]
		if same and am.size() == bm.size():
			for i in am.size():
				if (am[i] as Vector3).distance_to(bm[i]) > .01:
					same = false
					break
		elif am.size() != bm.size():
			same = false
		_check(not same, "%s: two breaks struck the same way differ (%s, %s)" % [image, a[0], b[0]])
		# Struck from the west the pieces go east, from the east west.
		var east := _strike(wreck, p, Vector3(1, 0, 0), 1.0)
		var wa: Vector3 = a[4]
		var ea: Vector3 = east[4]
		_check(
			wa.x > .3 and ea.x < -.3,
			"%s: pieces go away from the side struck (%.2f, %.2f)" % [image, wa.x, ea.x]
		)
		# The fracture's origin is on the side struck (a round thing's turned
		# to it).
		var src: Dictionary = wreck._source(p)
		var turn: Basis = src["basis"]
		var o: Vector3 = WreckCuts.origin(east[0])
		o = Basis(Vector3(0, 0, 1), float(east[1])) * o
		var world_o: Vector3 = turn * o
		_check(
			world_o.x > 0.0,
			"%s: the fracture starts on the side struck (%.2f)" % [image, world_o.x]
		)
		var soft := _strike(wreck, p, west, .4)
		var hard := _strike(wreck, p, west, 1.3)
		_check(
			float(hard[3]) > float(soft[3]) * 1.3,
			(
				"%s: buckshot at arm's length throws harder than a revolver round (%.2f, %.2f)"
				% [image, hard[3], soft[3]]
			)
		)
		var parts: Array = WreckCuts.parts(game.art, a[0])
		var named := true
		var raw := false
		for part in parts:
			named = named and part.material != "" and forms.has(part.form)
			for c: Color in part.colors:
				if c.a < .5:
					raw = true
					break
		_check(named, "%s: every piece names its stuff and shape" % image)
		_check(raw, "%s: its pieces have raw cut faces" % image)
		print("  ok   %-22s %s vs %s, %d pieces" % [image, a[0], b[0], am.size()])
	# A real break throws fine debris, capped.
	var p = _piece_of(game, "prop_crate")
	if p != null:
		var i: int = game.features["breakables"].pieces.find(p)
		game.features["breakables"].strike(i, 9999.0, 1.0, 0.0)
		_ticks(game, 1)
		_check(not wreck.debris.bits.is_empty(), "a break throws fine debris")
	var cap: int = wreck.debris.most
	for k in 40:
		var q = _piece_of(game, "prop_barrel")
		if q == null:
			break
		var j: int = game.features["breakables"].pieces.find(q)
		game.features["breakables"].strike(j, 9999.0, 1.0, 0.0)
		_ticks(game, 1)
	_check(
		wreck.debris.bits.size() <= cap,
		"the fine debris never passes its cap (%d of %d)" % [wreck.debris.bits.size(), cap]
	)
	# A shot that does not break it chips it.
	var whole = _piece_of(game, "town_outhouse")
	if whole != null:
		var had: int = wreck.debris.bits.size()
		wreck.debris.bits.clear()
		var at := Vector3(whole.x - .3, whole.y, game.world.stand(whole) + .8)
		game.events.traced.emit(at, "thing")
		game.features["breakables"].strike(
			game.features["breakables"].pieces.find(whole), 1.0, 1.0, 0.0
		)
		_check(
			not wreck.debris.bits.is_empty(), "a shot that does not break it chips it (%d)" % had
		)
	print("  ok   fine debris %d (cap %d)" % [wreck.debris.bits.size(), cap])
