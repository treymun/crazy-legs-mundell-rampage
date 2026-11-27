## The active bodies' steps two and three (pass 15, T11), headless:
##
##   Godot --headless --path godot --script res://tools/active_body_check.gd [-- print]
##       [kind=billy]
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
## the bit with the active bodies stepped beside it or not. `kind=` runs the
## looks' half on another humanoid's rig and model (its own play body when it
## is an enemy, else a coot's), sized against the coot as the game sizes it.
extends SceneTree

const DT := 1.0 / 60.0
const R := preload("res://src/view3d/ragdoll_rig.gd")

var failures: Array = []
var verbose := false
var rig: RagdollRig
## The rig's kind (kind=) and the play body's (the kind itself when it is an
## enemy, else a coot).
var kind := "coot"
var body := "coot"
## The model's size against SIZE (the game's height over canvas, the coot's 1).
static var size_k := 1.0


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
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("kind="):
			kind = a.substr(5)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var data: Dictionary = ActorModels.new(Assets.new()).kinds
	body = kind if Enemy.KINDS.has(kind) else "coot"
	var view: Node = load("res://scenes/actors/%s.tscn" % kind).instantiate()
	root.add_child(view)
	rig = RagdollRig.of(kind, view, data[kind])
	view.free()
	if kind != "coot":
		var tall: float = Enemy.KINDS[body][3]
		var coot_tall: float = Enemy.KINDS["coot"][3]
		var canvas: Array = data[kind].get("canvas", [1.0, tall])
		var coot_canvas: Array = data["coot"].get("canvas", [1.0, coot_tall])
		var fit: float = data[kind].get("scale", 1.0)
		var coot_fit: float = data["coot"].get("scale", 1.0)
		var mine: float = tall / float(canvas[1]) * fit
		var coots: float = coot_tall / float(coot_canvas[1]) * coot_fit
		size_k = mine / coots
		print("kind %s (play body %s, size %.3f of the coot's)" % [kind, body, size_k])
	print("ACTIVE BODIES: PLAY'S SAY, THE BODY'S PHYSICS")
	_play(main)
	_looks(main)
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
	e.uid = 987654
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
			"driven hard into a low rail he goes over and falls below (y %.2f, floor %.2f)"
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
		"a vehicle that leaves him up knocks him flat (%.2f cells)" % from.distance_to(rammed["at"])
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


# ------------------------------------------------------------------ looks

const SIZE := 1.51 / 1.7


## The model's transform for a coot standing at `at` on floor `z` facing `angle`.
static func _xf(at: Vector2, z: float, angle: float) -> Transform3D:
	var turn := PI * .5 - angle
	return Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3.ONE * SIZE * size_k), Vector3(at.x, z, at.y)
	)


func _pose(xf: Transform3D, model: PackedVector3Array = PackedVector3Array()) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in R.POINTS:
		out.append(Ragdoll.to_map(xf, model[i] if model.size() > i else rig.points[i]))
	return out


func _active(at: Vector2, z: float, angle: float) -> ActiveBody:
	var live := ActiveBody.made_active(rig, _xf(at, z, angle), rig.points)
	live.dice.seed = 5
	return live


## A live body driven beside play's man `e` for `secs` (play's reel ticked as
## _reel does); `each` is called every tick with [live, t]. The standing pose
## carried with play's body is the target. Returns the body.
func _drive(g: Game, e: Enemy, live: ActiveBody, secs: float, each: Callable) -> ActiveBody:
	var start := Vector3(e.x, e.y, e.floor_z)
	var rest := _pose(_xf(Vector2(e.x, e.y), e.floor_z, e.angle))
	live.omega = Stagger.rate(e)
	var t := 0.0
	while t < secs:
		g.clock += DT
		if e.notes.has(Stagger.KEY):
			Stagger.tick(e, DT, g)
		if e.notes.has(BodyPlay.KEY):
			BodyPlay.tick(e, g)
		if e.climb_z > 0.0 or e.floor_z < e.last_floor - Climbing.DROP:
			Climbing.enemy_step(e, DT, g)
		e.stun = maxf(0.0, e.stun - DT)
		var body := Vector3(e.x, e.y, e.floor_z + e.climb_z)
		var moved := body - start
		var now := PackedVector3Array()
		for p in rest:
			now.append(p + moved)
		live.aim(now, body, 1)
		var down := Stagger.down_of(e)
		var s := Stagger.of(e)
		var pitch: float = 0.0 if s.is_empty() else s[Stagger.PITCH]
		live.stunned = e.stun > .05
		live.grab_point = BodyPlay.holding(e, g.clock)
		live.play_says(not s.is_empty(), 1 if down > 0.0 else -1 if down < 0.0 else 0, pitch > .5)
		Ragdoll.budget = 1 << 30
		live.advance(g.world, DT)
		t += DT
		if each.is_valid():
			each.call(live, t)
	return live


## A shove at `at_share` of the body's height (play's reel from it, the
## looks' impulse there) of `strength`: {lean, head, catches, mill, drop}.
func _shove(main: Node, at_share: float, strength: float) -> Dictionary:
	var g := _game(main)
	var open := _open(g)
	var e := _man(g, open, PI, body)
	var live := _active(open, e.floor_z, PI)
	var z := e.floor_z
	var tall := 1.51 * size_k
	Stagger.point = Vector3(e.x - .2, e.y, z + tall * at_share)
	Stagger.shove(e, g, strength, 0.0)
	var note := Stagger.of(e)
	var jx: float = note[Stagger.JX]
	var jy: float = note[Stagger.JY]
	var zone := "head" if at_share > .85 else "legs" if at_share < .4 else "body"
	live.aim(_pose(_xf(open, z, PI)), Vector3(open.x, open.y, z), 1)
	live.hit(Vector2(jx, jy), note[Stagger.HZ], 0.0, zone, 3)
	var out := {"lean": 0.0, "head": 0.0, "mill": 0.0, "drop": 0.0}
	var rest := _pose(_xf(open, z, PI))
	var head0 := rest[R.HEAD]
	var hips0 := (rest[R.HIP_L] + rest[R.HIP_R]) * .5
	var start := Vector2(e.x, e.y)
	var measure := func(b: ActiveBody, _t: float) -> void:
		var f := LiveBody._torso_frame(b.pos)
		# (How far he tips from his own stance - the pose he holds - not from
		# upright: a body standing hunched over would read a blow tipping him
		# back up as less.)
		out["lean"] = maxf(out["lean"], f.y.angle_to(LiveBody._torso_frame(b.target).y))
		var moved := Vector3(e.x - start.x, e.y - start.y, 0.0)
		out["head"] = maxf(out["head"], b.pos[R.HEAD].distance_to(head0 + moved))
		var hips := (b.pos[R.HIP_L] + b.pos[R.HIP_R]) * .5
		out["drop"] = maxf(out["drop"], hips0.z - hips.z)
		if b.milling:
			out["mill"] = float(out["mill"]) + DT
	_drive(g, e, live, 2.0, measure)
	out["catches"] = live.catches
	out["play"] = start.distance_to(Vector2(e.x, e.y))
	return out


func _looks(main: Node) -> void:
	# Shoves: the same push at the hips, the chest and the head, and a bigger
	# one at the chest, react four measured ways.
	var hips := _shove(main, .5, .3)
	var chest := _shove(main, .72, .3)
	var head := _shove(main, .95, .3)
	var big := _shove(main, .72, .7)
	var rows := [hips, chest, head, big]
	var names := ["hips", "chest", "head", "big chest"]
	for k in 4:
		var m: Dictionary = rows[k]
		_say(
			(
				"shove %s: lean %.2f head %.2f drop %.2f catches %d mill %.2f s play %.2f"
				% [names[k], m["lean"], m["head"], m["drop"], m["catches"], m["mill"], m["play"]]
			)
		)
	var apart := true
	for i in 4:
		for k in range(i + 1, 4):
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[k]
			var diff := (
				absf(a["lean"] - b["lean"])
				+ absf(a["head"] - b["head"])
				+ absf(a["drop"] - b["drop"])
				+ absf(float(a["catches"]) - float(b["catches"])) * .1
			)
			apart = apart and diff > .04
	_check(apart, "the same shove at the hips, chest and head, and a bigger one, react four ways")
	_check(
		head["lean"] > hips["lean"] and int(big["catches"]) >= int(chest["catches"]),
		(
			"higher on him tips him further (%.2f against %.2f); harder, more steps (%d, %d)"
			% [head["lean"], hips["lean"], big["catches"], chest["catches"]]
		)
	)
	_check(float(big["mill"]) > 0.0, "shoved hard he windmills his arms (%.2f s)" % big["mill"])
	_brace_check(main)
	_grab_check(main)
	_stairs_check(main)
	_rail_check(main)
	_drunk_check(main)
	_dying_check(main)
	_same_play(main)


## Knocked off his feet (play's down, pitched): the hands get to the floor
## before the head or a shoulder and the arms point where he lands; with the
## behaviours off (muscles still on) they do not.
func _brace_check(main: Node) -> void:
	var runs: Array = []
	for acts: bool in [true, false]:
		var g := _game(main)
		var open := _open(g)
		var e := _man(g, open, PI, body)
		var live := _active(open, e.floor_z, PI)
		live.acts = acts
		BodyPlay.knock_down(e, g, Vector2(1.8, 0.0), Stagger.PITCH_FOR * 1.4)
		var st := {"hand": -1.0, "torso": -1.0, "aim": PI, "low": INF}
		var z := e.floor_z
		var each := func(b: ActiveBody, t: float) -> void:
			for hand: int in [R.HAND_L, R.HAND_R]:
				if float(st["hand"]) < 0.0 and b.pos[hand].z - b.radius[hand] < z + .02:
					st["hand"] = t
			for i: int in [R.HEAD, R.SH_L, R.SH_R]:
				if float(st["torso"]) < 0.0 and b.pos[i].z - b.radius[i] < z + .02:
					st["torso"] = t
			st["low"] = minf(st["low"], b.pos[R.HEAD].z - z)
			var ab := b
			if ab.bracing and float(st["hand"]) < 0.0 and ab.brace_at != Vector3.INF:
				for arm in 2:
					var sh := b.pos[R.SH_L if arm == 0 else R.SH_R]
					var hand := b.pos[R.HAND_L if arm == 0 else R.HAND_R]
					st["aim"] = minf(st["aim"], (hand - sh).angle_to(ab.brace_at - sh))
		live.aim(_pose(_xf(open, z, PI)), Vector3(open.x, open.y, z), 1)
		live.hit(Vector2(1.8, 0.0), .55, 0.0, "body", 3)
		_drive(g, e, live, 1.6, each)
		runs.append(st)
	var on: Dictionary = runs[0]
	var off: Dictionary = runs[1]
	_say("brace on %s / off %s" % [on, off])
	_check(
		(
			float(on["hand"]) >= 0.0
			and (float(on["torso"]) < 0.0 or float(on["hand"]) < float(on["torso"]))
		),
		(
			"knocked over, a hand reaches the floor first (%.2f s; head or shoulder %.2f s)"
			% [on["hand"], on["torso"]]
		)
	)
	_check(
		float(on["aim"]) < .6,
		"on the way down the arms point at where he lands (within %.2f rad)" % on["aim"]
	)
	_check(
		float(on["low"]) > .3 and float(off["hand"]) < 0.0,
		(
			"the head is held off the floor (lowest %.2f over it); without the behaviours no hand goes down"
			% on["low"]
		)
	)


## A reel beside the loft's rail his steps cannot stop: play says he held on
## (its point); the near hand goes there, is pinned (stays on the point while
## held) and lets go after.
func _grab_check(main: Node) -> void:
	var g := _game(main)
	var at := Vector2(44.0, 9.05)
	var e := _man(g, at, PI, body)
	var live := _active(at, e.floor_z, PI)
	Stagger.push(e, g, Vector2(3.2, 0.0))
	var st := {"slip": 0.0, "held": 0.0}
	var each := func(b: ActiveBody, _t: float) -> void:
		if b.grab_hand >= 0 and b.grabbed_at >= 0.0:
			var hand := R.HAND_L if b.grab_hand == 0 else R.HAND_R
			var want := b.grab_at + Vector3(0.0, 0.0, b.radius[hand] * .6)
			st["slip"] = maxf(st["slip"], b.pos[hand].distance_to(want))
			st["held"] = float(st["held"]) + DT
	_drive(g, e, live, 3.0, each)
	_say("grab: log %s slip %.3f held %.2f s" % [live.grab_log, st["slip"], st["held"]])
	var done := not live.grab_log.is_empty() and live.grab_hand < 0
	var why: String = live.grab_log[0][3] if done else ""
	_check(
		float(st["held"]) > .25 and float(st["slip"]) < .02 and done and why != "missed",
		(
			"a hand grabs the rail in reach and is held there (%.2f s, %.3f off) and lets go (%s)"
			% [st["held"], st["slip"], why]
		)
	)


## Carried down the feed store's stairs (reeling, so the feet are the
## balance controller's): the feet are put down on the treads, at more than
## one height, each on the floor under it.
func _stairs_check(main: Node) -> void:
	var g := _game(main, "feedstore")
	var top := Vector2(10.9, 4.6)
	var way := Vector2(-1.0, 0.0)
	var e := _man(g, top, 0.0, body)
	var live := _active(top, e.floor_z, 0.0)
	var start := e.floor_z
	var t := 0.0
	var rest := _pose(_xf(top, start, 0.0))
	while t < 1.6:
		g.clock += DT
		g.move_actor(e, way.x * 1.3 * DT, way.y * 1.3 * DT, e.radius)
		var body := Vector3(e.x, e.y, e.floor_z)
		var now := PackedVector3Array()
		for p in rest:
			now.append(p + body - Vector3(top.x, top.y, start))
		live.aim(now, body, 1)
		live.play_says(true, 0, false)
		Ragdoll.budget = 1 << 30
		live.advance(g.world, DT)
		t += DT
	var heights := []
	var on_floor := true
	for row: Array in live.step_log:
		var p: Vector3 = row[3]
		var under := g.world.floor_under(p.x, p.y, p.z + .1)
		on_floor = on_floor and absf(p.z - under - live._foot_up(R.FOOT_L)) < .06
		var h := snappedf(under, .05)
		if not heights.has(h):
			heights.append(h)
	_say(
		(
			"stairs: %d steps, tread heights %s, went %.2f down"
			% [live.step_log.size(), heights, start - e.floor_z]
		)
	)
	_check(
		heights.size() >= 2 and on_floor and start - e.floor_z > .2,
		"down the stairs his feet step onto the treads (%d heights)" % heights.size()
	)


## Play takes him over the loft's rail: his legs are held back by it (a foot
## still on his side while his hips are past it) and every ball crosses over
## the rail's top, none through it.
func _rail_check(main: Node) -> void:
	var g := _game(main)
	var e := _man(g, LOFT, -PI * .5, body)
	var live := _active(LOFT, e.floor_z, -PI * .5)
	Stagger.push(e, g, Vector2(0.0, 3.0))
	var line := 9.55
	var top := 2.5
	var st := {"held_back": false, "through": 0, "over": 0, "was": live.pos.duplicate()}
	var each := func(b: ActiveBody, _t: float) -> void:
		var hips := (b.pos[R.HIP_L] + b.pos[R.HIP_R]) * .5
		if hips.y > line + .05 and minf(b.pos[R.FOOT_L].y, b.pos[R.FOOT_R].y) < line:
			st["held_back"] = true
		var was: PackedVector3Array = st["was"]
		for i in R.POINTS:
			if (was[i].y < line) != (b.pos[i].y < line) and absf(b.pos[i].x - 44.0) < 2.0:
				# (Its middle's height where it crossed the bar's line.)
				var k := clampf((line - was[i].y) / (b.pos[i].y - was[i].y), 0.0, 1.0)
				var at_line := lerpf(was[i].z, b.pos[i].z, k)
				if at_line < top - .02 and minf(was[i].z, b.pos[i].z) > 1.55:
					st["through"] = int(st["through"]) + 1
				else:
					st["over"] = int(st["over"]) + 1
		st["was"] = b.pos.duplicate()
	_drive(g, e, live, 2.5, each)
	st.erase("was")
	_say("rail: %s, hips end y %.2f" % [st, (live.pos[0].y + live.pos[1].y) * .5])
	_check(
		st["held_back"] and int(st["through"]) == 0 and int(st["over"]) >= 10,
		(
			"over the rail his legs catch and go over its top, none through (%d over, %d through)"
			% [st["over"], st["through"]]
		)
	)


## A drunk walking a straight line (play's body, no lurch) against the same
## body sober: more and wider steps, off the line both ways.
func _drunk_check(main: Node) -> void:
	var rows: Array = []
	for drunk: float in [0.0, 1.0]:
		var g := _game(main)
		var open := _open(g)
		var start := open + Vector2(-2.0, 0.0)
		var live := _active(start, g.world.elevation(start.x, start.y), 0.0)
		live.drunk = drunk
		var z := g.world.elevation(start.x, start.y)
		var rest := _pose(_xf(start, z, 0.0))
		var t := 0.0
		while t < 5.0:
			var body := Vector3(start.x + t * .8, start.y, z)
			var now := PackedVector3Array()
			for p in rest:
				now.append(p + body - Vector3(start.x, start.y, z))
			live.aim(now, body, 1)
			live.play_says(true, 0, false)
			Ragdoll.budget = 1 << 30
			live.advance(g.world, DT)
			t += DT
		var off := 0.0
		var sides := 0
		var last := 0.0
		for row: Array in live.step_log:
			var p: Vector3 = row[3]
			var d := p.y - start.y
			off += absf(d)
			if signf(d) != signf(last) and absf(d) > .05:
				sides += 1
			last = d
		rows.append([live.step_log.size(), off / maxf(1.0, live.step_log.size()), sides])
	var sober: Array = rows[0]
	var drunk_row: Array = rows[1]
	_say("walk sober %s drunk %s" % [sober, drunk_row])
	_check(
		float(drunk_row[1]) > float(sober[1]) * 1.4 and int(drunk_row[2]) >= 2,
		(
			"a drunk's steps go wide of his line both ways (%.2f off against %.2f sober; %d side changes)"
			% [drunk_row[1], sober[1], drunk_row[2]]
		)
	)


## Play is the same to the bit with the active bodies stepped beside it.
func _same_play(main: Node) -> void:
	var traces: Array = []
	for with_live: bool in [false, true]:
		var g := _game(main)
		var e := _man(g, LOFT, -PI * .5, body)
		var live := _active(LOFT, e.floor_z, -PI * .5)
		Stagger.push(e, g, Vector2(.4, 3.0))
		var trace := PackedFloat64Array()
		var each := func(b: ActiveBody, _t: float) -> void:
			trace.append_array([e.x, e.y, e.stun, e.floor_z, e.climb_z])
			if not with_live:
				return
			b.hit(Vector2(1.0, 0.0), .5, 0.0, "body", 1)
		if with_live:
			_drive(g, e, live, 2.0, each)
		else:
			var t := 0.0
			while t < 2.0:
				g.clock += DT
				if e.notes.has(Stagger.KEY):
					Stagger.tick(e, DT, g)
				if e.notes.has(BodyPlay.KEY):
					BodyPlay.tick(e, g)
				if e.climb_z > 0.0 or e.floor_z < e.last_floor - Climbing.DROP:
					Climbing.enemy_step(e, DT, g)
				e.stun = maxf(0.0, e.stun - DT)
				t += DT
				each.call(live, t)
		trace.append(g.rng.state)
		traces.append(trace)
	_check(
		traces[0] == traces[1],
		"play is the same to the bit with the active bodies stepped beside it"
	)


# ------------------------------------------------------------------ dying


## A dying body standing at `at` facing `angle`, knocked along +x at the chest.
func _dying(g: Game, at: Vector2, kind_of: int, muscles := true, plain := false) -> Ragdoll:
	var z := g.world.elevation(at.x, at.y)
	var xf := _xf(at, z, PI)
	var doll: Ragdoll
	if plain:
		doll = Ragdoll.made(rig, xf, rig.standing())
	else:
		doll = DyingDoll.made_dying(rig, xf, rig.standing())
	doll.fit()
	doll.follow(Vector3(at.x, at.y, z), 0.0, 0.0)
	var chest := (doll.pos[R.SH_L] + doll.pos[R.SH_R] + doll.pos[R.BELLY]) / 3.0
	# (From behind: he goes over forwards, the way he faces.)
	doll.strike(chest, Vector3(-1.0, 0.0, .1).normalized(), 2.2)
	var dying := doll as DyingDoll
	if dying != null:
		var e := Enemy.new(body, at.x, at.y, PI)
		e.last_zone = "body"
		e.killed_by = "revolver"
		dying.begin(e, 9)
		dying.style = kind_of
		dying.muscles = muscles
	return doll


## Each limb ball's distance from where the death pose holds it from its
## parent (torso frame), summed: how far the body has let go.
static func _let_go(doll: Ragdoll, held: PackedVector3Array) -> float:
	var fr := LiveBody._torso_frame(doll.pos)
	var sum := 0.0
	for i: int in [R.ELBOW_L, R.HAND_L, R.ELBOW_R, R.HAND_R, R.HEAD]:
		var par: int = LiveBody.PARENT_OF[i]
		var from := (doll.pos[R.SH_L] + doll.pos[R.SH_R]) * .5 if par == -2 else doll.pos[par]
		sum += (fr.transposed() * (doll.pos[i] - from)).distance_to(held[i])
	return sum


func _dying_check(main: Node) -> void:
	var g := _game(main)
	var open := _open(g)
	# Slack over time: the tone fades over a second or more, and the arms
	# hold their pose that long (a plain ragdoll's let go at once).
	var dying := _dying(g, open, DyingDoll.LIMP) as DyingDoll
	var plain := _dying(_game(main), open, 0, true, true)
	var held := dying.held.duplicate()
	var tones := []
	var gone := []
	var t := 0.0
	var first_hand := -1.0
	var first_torso := -1.0
	var aim := PI
	var works := [0.0, 0.0, 0.0]
	var body := Vector3(open.x, open.y, g.world.elevation(open.x, open.y))
	while t < 2.6:
		Ragdoll.budget = 1 << 30
		dying.follow(body, 0.0, DT)
		plain.follow(body, 0.0, DT)
		dying.advance(g.world, DT)
		plain.advance(g.world, DT)
		t += DT
		var slot := 0 if t < .3 else 1 if t > .9 and t < 1.3 else 2 if t > 2.3 else -1
		if slot >= 0:
			works[slot] = float(works[slot]) + dying.work
		for at: float in [.1, .25, 1.0, 2.5]:
			if absf(t - at) < DT * .5:
				tones.append(dying.env)
				gone.append([_let_go(dying, held), _let_go(plain, held)])
		if dying.brace_at != Vector3.INF and dying.hand_down_at < 0.0:
			for arm in 2:
				var sh := dying.pos[R.SH_L if arm == 0 else R.SH_R]
				var hand := dying.pos[R.HAND_L if arm == 0 else R.HAND_R]
				aim = minf(aim, (hand - sh).angle_to(dying.brace_at - sh))
	first_hand = dying.hand_down_at
	first_torso = dying.torso_down_at
	_say(
		(
			"dying tones %s, let go (dying, plain) %s, slack over %.2f s"
			% [tones, gone, dying.slack_for]
		)
	)
	_check(
		float(tones[0]) > .9 and float(tones[1]) > .2 and float(tones[3]) < .02,
		"a dying man goes slack over time (tone %.2f, %.2f, %.2f, %.2f)" % tones
	)
	_check(
		float(works[0]) > float(works[1]) and float(works[1]) > 0.0 and float(works[2]) == 0.0,
		(
			"his muscles still work a second in, less than at first, none once slack (%.3f, %.3f, %.3f)"
			% works
		)
	)
	var g0: Array = gone[0]
	_check(
		float(g0[0]) < float(g0[1]) * .8,
		(
			"at first his arms hold the pose he was hit in (let go %.2f against a plain ragdoll's %.2f)"
			% g0
		)
	)
	_say("dying fall: hand %.2f torso %.2f aim %.2f" % [first_hand, first_torso, aim])
	_check(
		first_hand >= 0.0 and (first_torso < 0.0 or first_hand <= first_torso) and aim < .7,
		(
			"falling, he half catches himself: a hand down first (%.2f s, the head or a shoulder %.2f s)"
			% [first_hand, first_torso]
		)
	)
	# On the ground: writhing works the muscles for seconds, then nothing;
	# crawling drags him along; the muscles off, nothing.
	var results: Array = []
	for row: Array in [
		[DyingDoll.WRITHE, true], [DyingDoll.CRAWL, true], [DyingDoll.WRITHE, false]
	]:
		var style: int = row[0]
		var on: bool = row[1]
		var gg := _game(main)
		var spot := _open(gg)
		var doll := _dying(gg, spot, style, on) as DyingDoll
		if style == DyingDoll.CRAWL:
			_face_down(doll)
		var busy := 0.0
		var late := 0.0
		var lay_mid := Vector3.INF
		var tt := 0.0
		var lie := Vector3(spot.x, spot.y, gg.world.elevation(spot.x, spot.y))
		while tt < 7.0:
			Ragdoll.budget = 1 << 30
			doll.follow(lie, 0.0, DT)
			doll.advance(gg.world, DT)
			tt += DT
			if doll.lay_at >= 0.0 and lay_mid == Vector3.INF:
				lay_mid = doll.middle()
			var since := tt - doll.lay_at
			if doll.lay_at >= 0.0 and since < doll.behave_for:
				busy += doll.work
			elif doll.lay_at >= 0.0 and since > doll.behave_for + DyingDoll.SLACK_END + .3:
				late += doll.work
		var went := 0.0
		if lay_mid != Vector3.INF:
			went = Vector2(doll.middle().x - lay_mid.x, doll.middle().y - lay_mid.y).length()
		results.append([busy, late, went, doll.lay_at])
		_say(
			"style %d muscles %s: work %.3f then %.4f, went %.2f, lay at %.2f" % (row + results[-1])
		)
	var writhe: Array = results[0]
	var crawl: Array = results[1]
	var off: Array = results[2]
	_check(
		float(writhe[0]) > .05 and float(writhe[1]) < float(writhe[0]) * .02,
		(
			"on the ground he writhes (muscle work %.3f) and then lies still (%.4f)"
			% [writhe[0], writhe[1]]
		)
	)
	_check(
		float(crawl[2]) > .1 and float(crawl[2]) > float(writhe[2]),
		"face down he crawls a little way (%.2f cells; writhing %.2f)" % [crawl[2], writhe[2]]
	)
	_check(
		float(off[0]) == 0.0 and float(off[1]) == 0.0,
		"the muscles off, a dying man is a plain ragdoll (no work at all)"
	)


## Turned onto its face where it stands (a body about to crawl).
static func _face_down(doll: DyingDoll) -> void:
	var fr := LiveBody._torso_frame(doll.pos)
	var mid := doll.middle()
	var lay := Basis(fr.x, PI * .5)
	for i in doll.pos.size():
		doll.pos[i] = mid + lay * (doll.pos[i] - mid)
		doll.old[i] = doll.pos[i]
