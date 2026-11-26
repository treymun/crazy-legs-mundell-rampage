## The active bodies' steps two and three (pass 15, T11), headless:
##
##   Godot --headless --path godot --script res://tools/active_body_check.gd [-- print]
##
## Play's half (src/body_play.gd): a reel the steps cannot stop next to a rail
## holds on to it (the same reel on open floor goes down); a man driven hard
## into a low rail goes over it (gently, he does not; a high wall stops him);
## a boot's slide slammed into a wall puts him down; a vehicle that leaves him
## up reels him; a drunk lurches as he walks and now and then goes down; all
## of it the same twice and no dice drawn; off ([bodies] play=false) none of
## it. The looks' half (src/active_body.gd, src/dying_doll.gd) on a coot's
## real rig: shoves at different points and strengths give different
## measured reactions; going over, the hands reach the floor before the head
## and the arms point at where he lands (with the behaviours off they do
## not); a hand grabs a rail in reach, holds (pinned) and lets go; feet step
## down a stair's treads; a body carried over a rail goes over its top, not
## through it; a drunk takes more and wider steps than a sober man walking
## the same line; a dying man goes slack over a second or more (a plain
## ragdoll at once), writhes or crawls on the ground and then lies still;
## the muscles off, every one of them is a plain ragdoll. Play is the same to
## the bit with the active bodies stepped beside it or not.
extends SceneTree

const DT := 1.0 / 60.0
const R := preload("res://src/view3d/ragdoll_rig.gd")

var failures: Array = []
var verbose := false
var rig: RagdollRig


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _say(text: String) -> void:
	if verbose:
		print("    ", text)


func _run() -> void:
	verbose = OS.get_cmdline_user_args().has("print")
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var data: Dictionary = ActorModels.new(Assets.new()).kinds
	var view: Node = load("res://scenes/actors/coot.tscn").instantiate()
	root.add_child(view)
	rig = RagdollRig.of("coot", view, data["coot"])
	view.free()
	print("ACTIVE BODIES: PLAY'S SAY, THE BODY'S PHYSICS")
	_play(main)
	print("")
	print("ACTIVE BODY OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main: Node, level := "hickston") -> Game:
	var g: Game = main.make_game(level)
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 99.0
	for o: Enemy in g.enemies:
		o.dormant = true
	return g


static func _man(g: Game, at: Vector2, angle: float, kind := "billy") -> Enemy:
	var e := Enemy.new(kind, at.x, at.y, angle)
	e.floor_z = g.world.stand(e)
	e.floor_z = g.world.floor_under(at.x, at.y, 9.0)
	e.floor_z = g.world.stand(e)
	e.last_floor = e.floor_z
	e.hp = 900.0
	e.max_hp = 900.0
	e.uid = 77
	g.enemies.append(e)
	return e




## Hickston's loft by its rail (the rail along x at y 9.5, top .95 over the
## loft's floor at 1.55; open ground 1.55 below past it).
const LOFT := Vector2(44.0, 9.12)


## Play's reel of `e` stepped `secs` (Stagger, the note's expiry, the fall
## off an edge): [far side of the rail, held on, went down, rng drawn].
static func _reel(g: Game, e: Enemy, secs: float) -> Dictionary:
	var out := {"down": false, "held": false, "over": false, "drawn": false, "z": e.floor_z}
	var rng: int = g.rng.state
	var t := 0.0
	while t < secs:
		g.clock += DT
		if e.notes.has(Stagger.KEY):
			Stagger.tick(e, DT, g)
		if e.notes.has(BodyPlay.KEY):
			var n: Array = e.notes[BodyPlay.KEY]
			out["held"] = out["held"] or int(n[BodyPlay.MODE]) == BodyPlay.HOLDING
			out["over"] = out["over"] or int(n[BodyPlay.MODE]) == BodyPlay.OVER
			BodyPlay.tick(e, g)
		if e.climb_z > 0.0 or e.floor_z < e.last_floor - Climbing.DROP:
			Climbing.enemy_step(e, DT, g)
		e.stun = maxf(0.0, e.stun - DT)
		out["down"] = out["down"] or Stagger.down_of(e) > 0.0
		t += DT
	out["drawn"] = g.rng.state != rng
	out["z"] = e.floor_z
	out["at"] = Vector2(e.x, e.y)
	return out


func _play(main: Node) -> void:
	# Into the loft's rail hard: over it and down to the ground below.
	var g := _game(main)
	var e := _man(g, LOFT, -PI * .5)
	Stagger.point = Vector3.INF
	Stagger.push(e, g, Vector2(0.0, 3.0))
	var hard := _reel(g, e, 3.0)
	_say("hard into the rail: %s" % hard)
	_check(
		hard["over"] and float(hard["at"].y) > 9.6 and float(hard["z"]) < .2 and hard["down"],
		(
			"a man driven hard into a low rail goes over it and falls to the ground below (at y %.2f, floor %.2f)"
			% [hard["at"].y, hard["z"]]
		)
	)
	g = _game(main)
	e = _man(g, LOFT, -PI * .5)
	Stagger.push(e, g, Vector2(0.0, .7))
	var soft := _reel(g, e, 3.0)
	_check(
		not soft["over"] and float(soft["at"].y) < 9.5,
		"pushed gently into it he stays on his side (y %.2f)" % soft["at"].y
	)
	# A reel his steps cannot stop by the rail: he holds on; on open floor
	# the same goes down.
	g = _game(main)
	e = _man(g, Vector2(44.0, 9.05), PI)
	Stagger.push(e, g, Vector2(3.2, 0.0))
	var by_rail := _reel(g, e, 3.0)
	g = _game(main)
	var open := _open(g)
	e = _man(g, open, PI)
	Stagger.push(e, g, Vector2(3.2, 0.0))
	var in_open := _reel(g, e, 3.0)
	_say("by the rail %s / in the open %s" % [by_rail, in_open])
	_check(
		by_rail["held"] and not by_rail["down"] and in_open["down"] and not in_open["held"],
		"a reel his steps cannot catch holds on to the rail in reach (in the open he goes down)"
	)
	# A boot's slide into a wall: down.
	g = _game(main)
	open = _open(g)
	e = _man(g, open, PI)
	var slam := BodyPlay.slide_stopped(e, g, Vector2(6.0, 0.0), 2.6)
	_check(
		not slam and Stagger.down_of(e) > 0.0,
		"a boot's slide slammed into a wall puts him down (%.2f s)" % Stagger.down_of(e)
	)
	# Run into by a vehicle and still up: a reel off his feet.
	g = _game(main)
	e = _man(g, _open(g), PI)
	var from := Vector2(e.x, e.y)
	BodyPlay.rammed(e, g, Vector2(6.0, 0.0))
	var rammed := _reel(g, e, 3.0)
	_check(
		rammed["down"] and from.distance_to(rammed["at"]) > .3,
		"a vehicle that leaves him up knocks him off his feet (%.2f cells)" % from.distance_to(rammed["at"])
	)
	# The drunk's walk: lurches, now and then down; the same twice, no dice.
	var walks: Array = []
	for _k in 2:
		walks.append(_drunk_walk(main, 30.0))
	var a: Array = walks[0]
	var b: Array = walks[1]
	_say("drunk walk: lurches %d downs %d" % [a[1], a[2]])
	_check(
		int(a[1]) >= 5 and int(a[2]) >= 1,
		"a drunk lurches as he walks (%d in 30 s) and goes down now and then (%d)" % [a[1], a[2]]
	)
	_check(a[0] == b[0] and not a[3], "the same twice to the bit, no dice drawn")
	# (Up to the landing: the dust it raises is Climbing's, drawn as ever.)
	g = _game(main)
	e = _man(g, LOFT, -PI * .5)
	Stagger.push(e, g, Vector2(0.0, 3.0))
	var going := _reel(g, e, .3)
	_check(
		going["over"] and not going["drawn"] and not by_rail["drawn"],
		"going over the rail and holding on draw no dice"
	)
	# Off: none of it.
	BodyPlay.ON = false
	g = _game(main)
	e = _man(g, LOFT, -PI * .5)
	Stagger.push(e, g, Vector2(0.0, 3.0))
	var off_rail := _reel(g, e, 3.0)
	g = _game(main)
	e = _man(g, Vector2(44.0, 9.05), PI)
	Stagger.push(e, g, Vector2(3.2, 0.0))
	var off_hold := _reel(g, e, 3.0)
	var off_walk := _drunk_walk(main, 30.0)
	BodyPlay.ON = true
	_check(
		not off_rail["over"] and not off_hold["held"] and int(off_walk[1]) == 0,
		"off ([bodies] play=false): no rail gone over, nothing held, no lurch"
	)


## A drunk coot walking a line on open floor for `secs`: [trace, lurches,
## times down, rng drawn].
func _drunk_walk(main: Node, secs: float) -> Array:
	var g := _game(main)
	var at := _open(g)
	var e := _man(g, at + Vector2(-4.0, 0.0), 0.0, "drunk_coot")
	var rng: int = g.rng.state
	var trace := PackedFloat64Array()
	var lurches := 0
	var downs := 0
	var reeling := false
	var was_down := false
	var t := 0.0
	var way := 1.0
	while t < secs:
		g.clock += DT
		e.pose += DT
		if e.notes.has(Stagger.KEY):
			Stagger.tick(e, DT, g)
		e.stun = maxf(0.0, e.stun - DT)
		if e.stun <= 0.0 and not Stagger.reeling(e):
			if absf(e.x - at.x) > 4.0:
				way = -signf(e.x - at.x)
			e.advance(DT, g, 0.0 if way > 0.0 else PI, 1.0)
		var now := Stagger.reeling(e)
		if now and not reeling:
			lurches += 1
		reeling = now
		var down := Stagger.down_of(e) > 0.0
		if down and not was_down:
			downs += 1
		was_down = down
		trace.append_array([e.x, e.y, e.stun])
		t += DT
	return [trace, lurches, downs, g.rng.state != rng]


## Open floor with room all round (5 cells), nearest the start.
static func _open(g: Game) -> Vector2:
	var w := g.world
	var start := Vector2(g.player.x, g.player.y)
	var best := Vector2.INF
	for y in range(6, w.height - 6):
		for x in range(6, w.width - 6):
			var at := Vector2(x + .5, y + .5)
			if best != Vector2.INF and at.distance_to(start) > best.distance_to(start):
				continue
			if PhysCore.plain_rect(w, x - 5, y - 5, x + 5, y + 5):
				best = at
	return best
