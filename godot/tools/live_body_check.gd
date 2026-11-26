## The living bodies (pass 15, PUNCH; the active bodies' step one), headless:
##
##   Godot --headless --path godot --script res://tools/live_body_check.gd [-- print]
##
## Play's half (src/stagger.gd): a hit's shove is an impulse on an inverted
## pendulum that catches itself with steps; bigger pushes take more catch
## steps and travel further, a push too big for the steps puts him down, a
## leg hit buckles the knee (less reach: down sooner), a man hit on the run
## goes on forward, a second hit while reeling knocks him further; the same
## hits give the same reel twice, no dice drawn (game.rng untouched), walls
## stop it; off (Stagger.ON false) the old jumps.
## The looks' half (src/live_body.gd, driven as ActorView drives it, on a
## coot's real rig): the same push at the chest, the head, an arm and a leg
## gives four different measured reactions (the torso's lean and turn, the
## head's run, the hips' drop); the balance controller takes catch steps (and
## more for a bigger push); a hand goes to a chest wound and stays near it;
## a leg hit folds that knee; with the muscles off the body falls in a heap
## (it is the physics holding him up, not the animation); with them on he is
## back in his pose after; nothing stretches or flies off. Play is the same
## to the bit with the live bodies stepped beside it or not.
extends SceneTree

const DT := 1.0 / 60.0

var failures: Array = []
var verbose := false
var rig: RagdollRig


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	verbose = OS.get_cmdline_user_args().has("print")
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var data: Dictionary = ActorModels.new(Assets.new()).kinds
	# (A coot: arms and legs that bend; billy's are each one piece,
	# RagdollRig.stiff, and bend nowhere.)
	var view: Node = load("res://scenes/actors/coot.tscn").instantiate()
	root.add_child(view)
	rig = RagdollRig.of("coot", view, data["coot"])
	view.free()
	print("LIVING BODIES: PLAY'S STAGGER, THE LOOKS' PHYSICS")
	_play(main)
	_looks(main)
	print("")
	print("LIVE BODY OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main: Node) -> Game:
	var g: Game = main.make_game("hickston")
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 99.0
	return g


## A billy (play) or a coot (the looks) alone on open floor at `at`, facing
## west (the shooter's way).
static func _billy(g: Game, at: Vector2, kind := "billy") -> Enemy:
	for o: Enemy in g.enemies:
		o.dormant = true
	var e := Enemy.new(kind, at.x, at.y, PI)
	e.floor_z = g.world.stand(e)
	e.hp = 900.0
	e.max_hp = 900.0
	g.enemies.append(e)
	return e


## Open floor with room all round (5 cells).
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


## One hit on `e` from `far` cells west: gun `how`, `amount`, zone height
## `up` (share of the body) and `aside` cells off its middle.
static func _hit(
	g: Game, e: Enemy, how: String, amount: float, far: float, up: float, aside := 0.0, pellets := 1
) -> void:
	var p := g.player
	p.x = e.x - far
	p.y = e.y
	g.hit_from = Vector2(p.x, p.y)
	var feet: float = g.world.stand(e) + e.z
	for _k in pellets:
		g.hit_point = Vector3(e.x - e.radius * .8, e.y + aside, feet + e.height * e.variant * up)
		e.hurt(amount / pellets, g, false, false, null, how)
	e.hp = maxf(e.hp, 500.0)


static func _tick(g: Game, e: Enemy) -> void:
	g.clock += DT
	Stagger.tick(e, DT, g)


## [cells travelled, catch steps, went down, seconds reeling] for a hit.
static func _reel(
	main: Node, how: String, amount: float, far: float, up: float, pellets := 1, run := false
) -> Array:
	var g := _game(main)
	var at := _open(g)
	var e := _billy(g, at)
	if run:
		# On the move toward the shooter (west).
		e.angle = PI
		e.pose = 1.0
		e.last_stride = 1.0
	_hit(g, e, how, amount, far, up, 0.0, pellets)
	var steps := 0.0
	var down := false
	var t := 0.0
	while Stagger.reeling(e) and t < 4.0:
		var s := Stagger.of(e)
		steps = maxf(steps, s[Stagger.STEPS])
		down = down or float(s[Stagger.DOWN]) != 0.0
		_tick(g, e)
		t += DT
	var travel := Vector2(e.x, e.y).distance_to(at) * (1.0 if e.x >= at.x else -1.0)
	return [travel, int(steps), down, t]


func _play(main: Node) -> void:
	var on := Stagger.ON
	var light: Array = _reel(main, "revolver", 22.0, 6.0, .6)
	var mid: Array = _reel(main, "revolver", 34.0, 2.5, .6)
	var heavy: Array = _reel(main, "shotgun", 48.0, 1.4, .6, 8)
	var both: Array = _reel(main, "shotgun", 90.0, 1.0, .6, 16)
	var legs: Array = _reel(main, "revolver", 34.0, 2.5, .3)
	var running: Array = _reel(main, "revolver", 22.0, 3.0, .6, 1, true)
	if verbose:
		for row: Array in [
			["light", light],
			["mid", mid],
			["heavy", heavy],
			["both", both],
			["legs", legs],
			["run", running]
		]:
			var r: Array = row[1]
			print(
				"    %s: travel %.2f steps %d down %s for %.2f s" % [row[0], r[0], r[1], r[2], r[3]]
			)
	_check(
		light[0] > .02 and mid[0] > light[0] and heavy[0] > mid[0],
		"a bigger push reels him further (%.2f, %.2f, %.2f cells)" % [light[0], mid[0], heavy[0]]
	)
	_check(
		int(heavy[1]) > int(light[1]),
		"a bigger push takes more catch steps (%d against %d)" % [heavy[1], light[1]]
	)
	_check(
		both[2] and not light[2] and not mid[2],
		"both barrels at arm's length are more than his steps can catch: down he goes; a pistol does not"
	)
	_check(
		legs[2] or int(legs[1]) > int(mid[1]) or float(legs[0]) < float(mid[0]),
		(
			"a leg hit buckles the knee: shorter steps (down %s, %d steps, %.2f against %.2f cells)"
			% [legs[2], legs[1], legs[0], mid[0]]
		)
	)
	_check(
		running[0] < 0.0,
		"a man hit on the run goes on forward (%.2f cells toward the gun)" % running[0]
	)
	# Staggers stack: a second hit while reeling knocks him further.
	var g := _game(main)
	var at := _open(g)
	var e := _billy(g, at)
	_hit(g, e, "revolver", 30.0, 3.0, .6)
	for _k in 12:
		_tick(g, e)
	_hit(g, e, "revolver", 30.0, 3.0, .6)
	for _k in 240:
		_tick(g, e)
	var two := Vector2(e.x, e.y).distance_to(at)
	var one: Array = _reel(main, "revolver", 30.0, 3.0, .6)
	_check(
		two > float(one[0]) * 1.3,
		"a second hit while reeling knocks him further (%.2f against %.2f cells)" % [two, one[0]]
	)
	# The same twice, no dice: game.rng is where it was.
	var runs: Array = []
	for _k in 2:
		g = _game(main)
		e = _billy(g, _open(g))
		var before: int = g.rng.state
		_hit(g, e, "shotgun", 48.0, 1.4, .6, 8)
		var drawn: int = g.rng.state
		var trace := PackedFloat64Array()
		for _t in 120:
			_tick(g, e)
			trace.append_array([e.x, e.y, e.stun])
		var after: int = g.rng.state
		runs.append([trace, drawn == after, before])
	var a: Array = runs[0]
	var b: Array = runs[1]
	_check(a[0] == b[0], "the same hits reel him the same way twice")
	_check(a[1] and b[1], "the reel draws no dice (game.rng untouched while it runs)")
	# A wall stops him.
	g = _game(main)
	at = _open(g)
	e = _billy(g, at)
	var wall_at := at.x + 2.0
	var hit_wall := false
	_hit(g, e, "shotgun", 48.0, 1.4, .6, 8)
	for _k in 200:
		_tick(g, e)
		hit_wall = hit_wall or g.world.blocked(e.x + e.radius, e.y, 0.0)
	_check(not g.world.blocked(e.x, e.y, e.radius * .9), "the reel never puts him in a wall")
	# Off: the old jump, at once.
	Stagger.ON = false
	g = _game(main)
	at = _open(g)
	e = _billy(g, at)
	_hit(g, e, "revolver", 30.0, 3.0, .6)
	var jumped := Vector2(e.x, e.y).distance_to(at)
	_check(
		jumped > .05 and not Stagger.reeling(e),
		"off, a shove is the old jump at once (%.2f cells)" % jumped
	)
	Stagger.ON = on
	if verbose:
		print("    wall %.1f (%s)" % [wall_at, hit_wall])


## A live body on the coot's rig standing at `at` on the floor `z`, facing west.
func _live(at: Vector2, z: float) -> LiveBody:
	var xf := _xf(at, z)
	return LiveBody.made_live(rig, xf, rig.points)


func _xf(at: Vector2, z: float) -> Transform3D:
	var size := 1.51 / 1.7
	# Facing west (map -x): the model's front (+z) turned onto the heading.
	var turn := PI * .5 - PI
	return Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(at.x, z, at.y)
	)


## The rig's standing pose under `xf`, map points.
func _aim(xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in RagdollRig.POINTS:
		out.append(Ragdoll.to_map(xf, rig.points[i]))
	return out


## What a hit did to a live body over `secs` (play's stagger beside it):
## {lean (the torso's most from upright, radians), turn (its most about the
## upright), head (the head's furthest from its pose), drop (the hips' most
## below their pose), knee (the most a knee folded past its pose, radians),
## catches, gap (the clutching hand's distance from the wound at .5 s),
## low (the head's lowest share of its height), done, apart (the most a rigid
## link was off its length)}.
func _measure(
	main: Node,
	how: String,
	amount: float,
	far: float,
	up: float,
	aside: float,
	pellets := 1,
	muscles := true,
	secs := 3.0
) -> Dictionary:
	var g := _game(main)
	var at := _open(g)
	var e := _billy(g, at, "coot")
	var z := g.world.stand(e)
	var xf := _xf(at, z)
	var live := _live(at, z)
	live.muscles = muscles
	live.omega = Stagger.rate(e)
	var aim := _aim(xf)
	var head_tall := aim[RagdollRig.HEAD].z - z
	_hit(g, e, how, amount, far, up, aside, pellets)
	var note := Stagger.of(e)
	var j := Vector2.ZERO
	var hz := .6
	var lat := 0.0
	if not note.is_empty():
		var jx: float = note[Stagger.JX]
		var jy: float = note[Stagger.JY]
		j = Vector2(jx, jy)
		hz = note[Stagger.HZ]
		lat = note[Stagger.LAT]
	live.hit(j, hz, lat, e.last_zone if e.last_zone != "" else "body", 7)
	var out := {
		"lean": 0.0,
		"turn": 0.0,
		"head": 0.0,
		"drop": 0.0,
		"knee": 0.0,
		"gap": INF,
		"clutch": -1,
		"low": 1.0,
		"apart": 0.0
	}
	var rest_knee := _knee(aim, 0)
	var t := 0.0
	var origin := at
	var finite := true
	while t < secs:
		_tick(g, e)
		var moved := Vector3(e.x - origin.x, e.y - origin.y, 0.0)
		var now := PackedVector3Array()
		for p in aim:
			now.append(p + moved)
		var down := Stagger.down_of(e)
		var s := Stagger.of(e)
		var pitch: float = 0.0 if s.is_empty() else s[Stagger.PITCH]
		live.aim(now, Vector3(e.x, e.y, z), 1)
		live.play_says(not s.is_empty(), 1 if down > 0.0 else -1 if down < 0.0 else 0, pitch > .5)
		Ragdoll.budget = 1 << 30
		live.advance(g.world, DT)
		t += DT
		var f := LiveBody._torso_frame(live.pos)
		var ft := LiveBody._torso_frame(now)
		if t < .3:
			# The reaction itself (not the steps after).
			out["lean"] = maxf(out["lean"], f.y.angle_to(ft.y))
			var ah := Vector2(f.z.x, f.z.y)
			var at2 := Vector2(ft.z.x, ft.z.y)
			out["turn"] = maxf(out["turn"], absf(ah.angle_to(at2)))
			out["head"] = maxf(
				out["head"], live.pos[RagdollRig.HEAD].distance_to(now[RagdollRig.HEAD])
			)
		var hips := (live.pos[0] + live.pos[1]) * .5
		var hips_t := (now[0] + now[1]) * .5
		out["drop"] = maxf(out["drop"], hips_t.z - hips.z)
		if t < .5:
			# One knee folded more than the other (a buckle, not a crouch).
			out["knee"] = maxf(out["knee"], absf(_knee(live.pos, 0) - _knee(live.pos, 1)))
		if absf(t - .5) < DT * .5:
			out["gap"] = live.hand_gap()
			out["clutch"] = live.clutch_hand
		out["low"] = minf(out["low"], (live.pos[RagdollRig.HEAD].z - z) / head_tall)
		for k in live.la.size():
			if live.lmin[k] == live.lmax[k]:
				var d := live.pos[live.la[k]].distance_to(live.pos[live.lb[k]])
				var off := absf(d - live.lmin[k]) / live.lmin[k]
				if off > out["apart"]:
					out["apart"] = off
					out["worst"] = "%d-%d at %.2f s" % [live.la[k], live.lb[k], t]
		for p in live.pos:
			finite = finite and p.is_finite()
	out["catches"] = live.catches
	out["done"] = live.done()
	out["finite"] = finite
	out["play"] = Vector2(e.x, e.y).distance_to(at)
	out["end_head"] = (live.pos[RagdollRig.HEAD].z - z) / head_tall
	return out


## How far knee `leg` is folded (radians from straight).
static func _knee(at: PackedVector3Array, leg: int) -> float:
	var hip: int = [RagdollRig.HIP_L, RagdollRig.HIP_R][leg]
	var knee: int = [RagdollRig.KNEE_L, RagdollRig.KNEE_R][leg]
	var foot: int = [RagdollRig.FOOT_L, RagdollRig.FOOT_R][leg]
	return PI - (at[hip] - at[knee]).angle_to(at[foot] - at[knee])


func _looks(main: Node) -> void:
	var chest := _measure(main, "revolver", 30.0, 3.0, .62, .08)
	var head := _measure(main, "revolver", 30.0, 3.0, .93, 0.0)
	var arm := _measure(main, "revolver", 30.0, 3.0, .64, .26)
	var legs := _measure(main, "revolver", 30.0, 3.0, .3, .1)
	var big := _measure(main, "shotgun", 40.0, 2.0, .6, 0.0, 8)
	var limp := _measure(main, "revolver", 30.0, 3.0, .62, .08, 1, false)
	var still := _measure(main, "revolver", 1.0, 30.0, .62, 0.0)
	# A light hit from afar (no catch step): the knee alone.
	var leg_light := _measure(main, "revolver", 10.0, 9.0, .3, .1)
	var chest_light := _measure(main, "revolver", 10.0, 9.0, .62, .08)
	# The coot holds his pistol (right) and his jug (left): a hand holding a
	# thing never lets go of it to clutch (RagdollRig.holds, actors.json
	# "rides", LiveBody._holding), so his own chest hit clutches with
	# neither. The clutch itself is measured on his rig bare-handed, and
	# with the pistol alone the free left hand takes the wound.
	var holds := rig.holds
	rig.holds = PackedByteArray([0, 0])
	var bare := _measure(main, "revolver", 30.0, 3.0, .62, .08)
	rig.holds = PackedByteArray([0, 1])
	var pistol := _measure(main, "revolver", 30.0, 3.0, .62, .08)
	rig.holds = holds
	if verbose:
		for row: Array in [
			["chest", chest],
			["head", head],
			["arm", arm],
			["legs", legs],
			["big", big],
			["limp", limp],
			["still", still],
			["leg_light", leg_light],
			["chest_light", chest_light]
		]:
			var m: Dictionary = row[1]
			print(
				(
					(
						"    %s: lean %.2f turn %.2f head %.2f drop %.2f knee %.2f catches %d"
						+ " gap %.3f low %.2f end %.2f done %s apart %.3f %s play %.2f"
					)
					% [
						row[0],
						m["lean"],
						m["turn"],
						m["head"],
						m["drop"],
						m["knee"],
						m["catches"],
						m["gap"],
						m["low"],
						m["end_head"],
						m["done"],
						m["apart"],
						m.get("worst", ""),
						m["play"]
					]
				)
			)
	# Four places, four reactions.
	var rows := [chest, head, arm, legs]
	var names := ["chest", "head", "arm", "leg"]
	var apart_all := true
	for i in 4:
		for k in range(i + 1, 4):
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[k]
			var diff := (
				absf(a["lean"] - b["lean"])
				+ absf(a["turn"] - b["turn"])
				+ absf(a["head"] - b["head"])
				+ absf(a["drop"] - b["drop"])
				+ absf(a["knee"] - b["knee"])
			)
			if diff < .05:
				apart_all = false
				print("    %s and %s react alike (%.3f)" % [names[i], names[k], diff])
	_check(
		apart_all, "the same push at the chest, head, an arm and a leg reacts four different ways"
	)
	_check(
		head["head"] > chest["head"],
		(
			"a head hit snaps the head further than a chest hit (%.2f against %.2f)"
			% [head["head"], chest["head"]]
		)
	)
	_check(
		leg_light["knee"] > chest_light["knee"] + .1,
		(
			"a leg hit buckles that knee (folded %.2f rad more than the other; a chest hit %.2f)"
			% [leg_light["knee"], chest_light["knee"]]
		)
	)
	_check(
		int(chest["catches"]) >= 1 and int(still["catches"]) == 0,
		(
			"the balance controller takes catch steps for a hit (%d), none for a tap (%d)"
			% [chest["catches"], still["catches"]]
		)
	)
	_check(
		big["low"] < .8 and big["end_head"] > .93,
		(
			"knocked down by play's reel he drops (head to %.2f of its height) and gets back up (%.2f)"
			% [big["low"], big["end_head"]]
		)
	)
	_check(
		bare["gap"] < .12,
		"a hand goes to the chest wound and holds it (%.3f off at half a second)" % bare["gap"]
	)
	_check(
		int(pistol["clutch"]) == 0 and pistol["gap"] < .12,
		(
			"a pistol in the right hand: the left takes the wound (hand %d, %.3f off)"
			% [pistol["clutch"], pistol["gap"]]
		)
	)
	_check(
		int(chest["clutch"]) == -1,
		(
			"both hands holding things (pistol, jug): neither lets go to clutch (hand %d)"
			% chest["clutch"]
		)
	)
	_check(
		limp["low"] < .45,
		(
			"with the muscles off he falls in a heap (the head down to %.2f of its height)"
			% limp["low"]
		)
	)
	_check(
		chest["low"] > .75 and chest["end_head"] > .93,
		(
			"with the muscles on he stays up and is back in his pose (head at %.2f at worst, %.2f after)"
			% [chest["low"], chest["end_head"]]
		)
	)
	_check(
		chest["done"] and still["done"], "the live body hands back to the animation once settled"
	)
	var tight := true
	for m: Dictionary in [chest, head, arm, legs, big]:
		tight = tight and float(m["apart"]) < .12 and bool(m["finite"])
	_check(tight, "no rigid link more than 12% off its length at any step, nothing flies off")
	_same_play(main)


## Play is the same to the bit with live bodies stepped beside it or not (the
## looks never write play).
func _same_play(main: Node) -> void:
	var traces: Array = []
	for with_live: bool in [false, true]:
		var g := _game(main)
		var at := _open(g)
		var e := _billy(g, at)
		var z := g.world.stand(e)
		var live := _live(at, z)
		var aim := _aim(_xf(at, z))
		var trace := PackedFloat64Array()
		for shot in 3:
			_hit(
				g,
				e,
				"shotgun" if shot == 1 else "revolver",
				40.0 if shot == 1 else 28.0,
				2.0,
				.3 + shot * .3,
				.05,
				8 if shot == 1 else 1
			)
			if with_live:
				live.hit(Vector2(1.0, 0.0), .5, 0.0, e.last_zone, shot)
			for _k in 50:
				g.clock += DT
				e.tick(DT, g)
				if with_live:
					var moved := Vector3(e.x - at.x, e.y - at.y, 0.0)
					var now := PackedVector3Array()
					for p in aim:
						now.append(p + moved)
					live.aim(now, Vector3(e.x, e.y, z), 1)
					live.advance(g.world, DT)
				trace.append_array([e.x, e.y, e.stun, e.hp, e.cooldown])
		trace.append(g.rng.state)
		traces.append(trace)
	_check(traces[0] == traces[1], "play is the same to the bit with live bodies stepped beside it")
