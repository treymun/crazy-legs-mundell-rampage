## How broken things' pieces move, knock and rest (src/wreck_physics.gd,
## src/features/wreckage.gd; tools/check_all.gd runs it, quick too):
##
##   godot --headless --path godot --script res://tools/wreck_motion_check.gd
##
## On hickston's open ground: a ring of staves left standing on their ends,
## all touching, goes over (none stays standing; a stave leaning on a wall
## may); a hoop set rolling on its edge rolls on, stays on its rim a while,
## wobbles down and lies flat, much further than a box of its size pushed
## the same; a can on its side rolls; a lid spun on its edge spins down flat;
## a glass shard skids to a stop sooner than a tin piece; a tin sheet falls
## slower than a board. Knocks: a shot through a lying board knocks it at
## the hit point (off its middle it spins, the other way on the other side);
## a blast throws near pieces harder than far ones; a player, one of the
## county's hands and a vehicle going through pieces kick them. Breaks: the
## same barrel broken by a shot on its left and on its right comes apart
## clearly differently; broken twice the same way it comes apart the same. A
## hard knock on glass cracks it (WreckPhysics.cracked). Knock sounds stay
## under wreck.cfg's [knock] sounds_most a second through a heap of breaks.
extends SceneTree

const DT := 1.0 / 60.0

var failures: Array = []
var passes := 0
var game: Game
var at := Vector2.ZERO
var ground := 0.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	game = main.make_game("hickston")
	game.configure({})
	game.cheats.god = true
	for e: Enemy in game.enemies:
		e.dormant = true
	at = _spot()
	ground = Tumble.floor_at(game.world, at.x, at.y, 99.0)
	print("WRECK MOTION (open ground at %.1f, %.1f)" % [at.x, at.y])
	_staves()
	_hoop()
	_can()
	_lid()
	_skid()
	_sheet()
	_shot()
	_blast()
	_kicks()
	_breaks(main)
	_crack()
	_hollow()
	_cues()
	_sounds(main)
	PhysCore.space(game.world).boxes = []
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print(
		(
			"WRECK MOTION OK"
			if failures.is_empty()
			else "%d WRECK MOTION CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


## The open cell nearest the start with plain ground three cells every way.
func _spot() -> Vector2:
	var w := game.world
	var from := Vector2(game.player.x, game.player.y)
	var best := from
	var near := INF
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var c := Vector2(cx + .5, cy + .5)
			var d := c.distance_squared_to(from)
			if d < near and not is_nan(PhysCore.plain_under(w, Vector3(c.x, c.y, 0.0), 2.5)):
				near = d
				best = c
	return best


func _fresh() -> WreckPhysics:
	return WreckPhysics.new(game.world)


static func _settle(physics: WreckPhysics, most := 900) -> int:
	for t in most:
		if not physics.moving():
			return t
		physics.step(DT, 2)
	return most


## A ring of eight staves stood on their ends, touching: none stays standing.
func _staves() -> void:
	var physics := _fresh()
	var r := .3
	for k in 8:
		var a := TAU * k / 8.0
		var q := Quaternion(Vector3(0.0, 0.0, 1.0), a + PI * .5)
		var b := physics.add(
			Vector3(at.x + cos(a) * r, at.y + sin(a) * r, ground + .46),
			q,
			Vector3(.11, .022, .45),
			"wood",
			"stave",
			1
		)
		b.born = -9.0
	_settle(physics, 1200)
	var standing := 0
	for b: WreckPhysics.Body in physics.bodies:
		b.turn = Basis(b.q)
		standing += 1 if WreckPhysics.standing(b) else 0
	_check(
		standing == 0 and not physics.moving(),
		"a ring of 8 staves left standing all goes over and lies still (%d standing)" % standing
	)


## A hoop set rolling on its edge rolls on and wobbles down flat, far further
## than a box of its size pushed the same.
func _hoop() -> void:
	var physics := _fresh()
	var stood := Quaternion(Vector3(1.0, 0.0, 0.0), PI * .5)
	var hoop := physics.add(
		Vector3(at.x - 1.5, at.y, ground + .3), stood, Vector3(.3, .3, .025), "steel", "ring"
	)
	hoop.v = Vector3(2.4, 0.0, 0.0)
	hoop.turned()
	hoop.w = Vector3(0.0, 2.4 / .3, 0.0)
	var on_rim := 0.0
	var lowest_gap := INF
	for t in 900:
		if not physics.moving():
			break
		physics.step(DT, 2)
		var axis: Vector3 = Basis(hoop.q).z
		if absf(axis.z) < .5:
			on_rim += DT
		var low := INF
		for k in 8:
			low = minf(low, (hoop.p + Basis(hoop.q) * hoop.points[k]).z)
		lowest_gap = minf(lowest_gap, low - ground)
	var rolled := Vector2(hoop.p.x - (at.x - 1.5), hoop.p.y - at.y).length()
	var flat := absf(Basis(hoop.q).z.z) > .9
	var box_physics := _fresh()
	var box := box_physics.add(
		Vector3(at.x - 1.5, at.y, ground + .3), stood, Vector3(.3, .3, .025), "steel", ""
	)
	box.v = Vector3(2.4, 0.0, 0.0)
	_settle(box_physics)
	var slid := Vector2(box.p.x - (at.x - 1.5), box.p.y - at.y).length()
	_check(
		rolled > 1.2 and rolled > slid * 2.0,
		"a hoop rolls on its edge (%.2f cells; a box pushed the same %.2f)" % [rolled, slid]
	)
	_check(on_rim > .5, "it stays up on its rim a while (%.1f s)" % on_rim)
	_check(
		flat and not hoop.awake,
		"then wobbles down and lies flat, asleep (axis up %.2f)" % absf(Basis(hoop.q).z.z)
	)
	_check(lowest_gap > -.03, "it never sinks into the ground (%.3f)" % lowest_gap)


## A can lying on its side, pushed across its length, rolls.
func _can() -> void:
	var physics := _fresh()
	var lying := Quaternion(Vector3(1.0, 0.0, 0.0), PI * .5)
	var can := physics.add(
		Vector3(at.x, at.y - 1.0, ground + .06), lying, Vector3(.06, .06, .12), "tin", "can"
	)
	can.v = Vector3(1.6, 0.0, 0.0)
	var turned := 0.0
	var was := can.q
	for t in 600:
		if not physics.moving():
			break
		physics.step(DT, 2)
		turned += can.q.angle_to(was)
		was = can.q
	var went := can.p.x - at.x
	_check(
		went > .6 and turned > went / .06 * .5,
		"a can on its side rolls (%.2f cells, turned %.1f rad)" % [went, turned]
	)


## A lid spun on its edge spins down and lies flat.
func _lid() -> void:
	var physics := _fresh()
	var tilt := Quaternion(Vector3(1.0, 0.0, 0.0), PI * .5 - .35)
	var lid := physics.add(
		Vector3(at.x + 1.0, at.y + 1.0, ground + .26), tilt, Vector3(.25, .25, .015), "wood", "disc"
	)
	lid.w = Vector3(0.0, 0.0, 9.0)
	var t := _settle(physics, 900)
	_check(
		absf(Basis(lid.q).z.z) > .9 and t > 40,
		"a lid spun on its edge spins down flat (%.1f s)" % (t * DT)
	)


## A glass shard skids to a stop sooner than a piece of tin pushed the same.
func _skid() -> void:
	var went := {}
	for stuff: String in ["glass", "tin"]:
		var physics := _fresh()
		var b := physics.add(
			Vector3(at.x, at.y + 1.0, ground + .012),
			Quaternion.IDENTITY,
			Vector3(.08, .06, .012),
			stuff,
			"shard" if stuff == "glass" else "sheet"
		)
		b.v = Vector3(2.5, 0.0, 0.0)
		_settle(physics)
		went[stuff] = b.p.x - at.x
	_check(
		went["glass"] < went["tin"] * .8,
		"a glass shard skids to a stop sooner than tin (%.2f, %.2f)" % [went["glass"], went["tin"]]
	)


## A tin sheet dropped face down falls slower than a board.
func _sheet() -> void:
	var took := {}
	for form: String in ["sheet", "board"]:
		var physics := _fresh()
		var b := physics.add(
			Vector3(at.x - 1.0, at.y + 1.0, ground + 2.0),
			Quaternion(Vector3(1.0, 0.0, 0.0), .15),
			Vector3(.3, .25, .01),
			"tin",
			form
		)
		var t := 0
		while b.p.z > ground + .3 and t < 300:
			physics.step(DT, 2)
			t += 1
		took[form] = t
	_check(
		took["sheet"] > took["board"] + 4,
		(
			"a tin sheet flutters down slower than a board (%d, %d ticks)"
			% [took["sheet"], took["board"]]
		)
	)


## A shot through a lying board knocks it at the hit point: off its middle
## it spins, one way on one side and the other way on the other.
func _shot() -> void:
	var spins: Array = []
	for side: float in [-1.0, 1.0]:
		var physics := _fresh()
		var b := physics.add(
			Vector3(at.x, at.y, ground + .02),
			Quaternion.IDENTITY,
			Vector3(.4, .07, .02),
			"wood",
			"board"
		)
		_settle(physics)
		var from := Vector3(at.x + side * .3, at.y - 2.0, ground + 1.0)
		var to := Vector3(at.x + side * .3, at.y + 1.0, ground - .5)
		var hit := physics.ray(from, to)
		_check(not hit.is_empty() and hit[0] == b, "a shot's ray finds the board it passes into")
		if hit.is_empty():
			return
		physics.impact(hit[1], (to - from).normalized(), 3.0, "shot", -1, null, b)
		spins.append(b.w.z)
		_check(b.awake and b.v.length() > .5, "the shot knocks it (%.2f a second)" % b.v.length())
	_check(
		spins[0] * spins[1] < 0.0 and absf(spins[0]) > .5,
		"struck off its middle it spins, the other way on the other side (%.2f, %.2f)" % spins
	)


## A blast throws near pieces harder than far ones.
func _blast() -> void:
	var physics := _fresh()
	var near := physics.add(
		Vector3(at.x + .5, at.y, ground + .03), Quaternion.IDENTITY, Vector3(.15, .08, .03)
	)
	var far := physics.add(
		Vector3(at.x + 2.0, at.y, ground + .03), Quaternion.IDENTITY, Vector3(.15, .08, .03)
	)
	_settle(physics)
	physics.impact(Vector3(at.x, at.y, ground + .2), Vector3.ZERO, 7.0, "blast")
	_check(
		near.v.length() > far.v.length() * 1.5 and far.v.length() > .1,
		(
			"a blast throws a near piece harder than a far one (%.2f, %.2f)"
			% [near.v.length(), far.v.length()]
		)
	)
	_check(near.v.x > 0.0 and near.v.z > 0.0, "out from the blast and up (%s)" % near.v)


## A player, a hand and a vehicle going through pieces kick them.
func _kicks() -> void:
	var wreck = game.features["wreckage"]
	for who: String in ["player", "enemy", "ride"]:
		for w in wreck.wrecks.duplicate():
			wreck._drop(w)
		var piece: WreckPhysics.Body = wreck.physics.add(
			Vector3(at.x, at.y, ground + .03),
			Quaternion.IDENTITY,
			Vector3(.12, .06, .03),
			"wood",
			"board"
		)
		var w = wreck.Wreck.new()
		w.body = piece
		w.sprite = View.Sprite.new(at.x, at.y, "", 1.0, ground)
		wreck.wrecks.append(w)
		_settle(wreck.physics)
		var walker: Object = null
		if who == "player":
			walker = game.player
		elif who == "enemy":
			walker = game.enemies[0]
			walker.dormant = false
			walker.hp = maxf(walker.hp, 1.0)
		elif game.features.has("vehicles"):
			var cars = game.features["vehicles"]
			if cars.rides.is_empty():
				cars.rides.append(VehicleDrive.Ride.new())
			walker = cars.rides[0]
		if walker == null:
			_check(false, "a %s to walk through the pieces" % who)
			continue
		var was := piece.p
		for t in 40:
			walker.x = at.x - 1.0 + t * 2.5 * DT
			walker.y = at.y + .02
			if who == "ride":
				walker.z = ground
			if who == "player":
				walker.vx = 2.5
				walker.vy = 0.0
			wreck._kick(DT)
			wreck.physics.step(DT, 2)
		if who == "enemy":
			walker.dormant = true
		var moved: float = piece.p.distance_to(was)
		_check(moved > .1, "a %s walking through a piece kicks it (%.2f cells)" % [who, moved])
		wreck.physics.remove(piece)
		wreck.wrecks.erase(w)


## The motion of a mash barrel broken by a shot at `side` (-1 left, 1 right,
## 0 none): each piece's speed.
func _break_once(main: Control, side: float) -> Array:
	var g: Game = main.make_game("moonshine")
	g.configure({})
	for e: Enemy in g.enemies:
		e.dormant = true
	var wreck = g.features["wreckage"]
	var breaks = g.features["breakables"]
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if p.image != "town_mash_barrel":
			continue
		var foot: float = g.world.stand(p) + p.z
		g.player.x = p.x - 2.0
		g.player.y = p.y
		g.player.eye = foot + .95
		if side != 0.0:
			# Its pellets struck one side of it, high or low.
			for k in 5:
				var end := Vector3(p.x, p.y + side * p.radius * .7, foot + .3 + .1 * k)
				wreck._traced(end, "thing")
		breaks.strike(i, 9999.0, 1.0, 0.0)
		g.tick(DT, Game.Controls.new())
		for t in 6:
			wreck._tick(DT)
		var out: Array = []
		for w2 in wreck.wrecks:
			out.append(w2.body.v)
		return out
	return []


## The same barrel shot on its left and its right comes apart differently;
## shot the same twice it comes apart the same.
func _breaks(main: Control) -> void:
	var left := _break_once(main, -1.0)
	var right := _break_once(main, 1.0)
	var again := _break_once(main, -1.0)
	_check(
		left.size() > 4 and left.size() == right.size(),
		"a mash barrel breaks (%d pieces)" % left.size()
	)
	if left.size() != right.size() or left.size() != again.size():
		return
	var differ := 0.0
	var most := 0.0
	var same := 0.0
	var sum_left := Vector3.ZERO
	var sum_right := Vector3.ZERO
	for k in left.size():
		var a: Vector3 = left[k]
		var b: Vector3 = right[k]
		var c: Vector3 = again[k]
		differ += a.distance_to(b)
		most = maxf(most, a.distance_to(b))
		same += a.distance_to(c)
		sum_left += a
		sum_right += b
	differ /= left.size()
	_check(
		differ > .5 and most > 2.0,
		(
			"shot on its left and its right it comes apart differently (%.2f a piece, %.2f most)"
			% [differ, most]
		)
	)
	_check(
		sum_left.y > sum_right.y,
		(
			"struck on its left (low y) its pieces go more to its right (%.2f, %.2f)"
			% [sum_left.y, sum_right.y]
		)
	)
	_check(same < 1e-4, "shot the same twice it comes apart the same (%.5f)" % same)


## A hard knock on glass cracks it (the breaks may split it).
func _crack() -> void:
	var physics := _fresh()
	var b := physics.add(
		Vector3(at.x, at.y, ground + 1.5),
		Quaternion.IDENTITY,
		Vector3(.1, .1, .01),
		"glass",
		"shard"
	)
	b.v = Vector3(0.0, 0.0, -6.0)
	var cracked := false
	for t in 60:
		physics.step(DT, 2)
		cracked = cracked or physics.cracked.has(b)
	_check(cracked, "glass struck hard on the ground cracks (WreckPhysics.cracked)")


## Through a heap of breaks, knock sounds stay under [knock] sounds_most a
## second.
func _sounds(main: Control) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({})
	for e: Enemy in g.enemies:
		e.dormant = true
	var wreck = g.features["wreckage"]
	var breaks = g.features["breakables"]
	var most := int(WreckPhysics.tuned("knock", "sounds_most", 9.0))
	var struck := 0
	for i in breaks.pieces.size():
		var p = breaks.pieces[i]
		if struck < 8 and str(p.spec.get("pieces", "")) != "" and not p.spec.has("blast"):
			breaks.strike(i, 9999.0, 1.0, 0.0)
			struck += 1
	var peak := 0
	var heard := 0
	for t in 240:
		g.tick(DT, Game.Controls.new())
		peak = maxi(peak, wreck._heard.size())
	for w2 in wreck.wrecks:
		heard += 1 if w2.body.heard > 0.0 else 0
	_check(
		peak <= most and heard > 3,
		"knocks are heard, at most %d a second (%d; %d pieces heard)" % [most, peak, heard]
	)
	# The heap at rest: no piece lies inside another.
	for t in 600:
		if not wreck.physics.moving():
			break
		g.tick(DT, Game.Controls.new())
	var worst := 0.0
	var bodies: Array = wreck.physics.bodies
	for i in bodies.size():
		var a: WreckPhysics.Body = bodies[i]
		a.turned()
		for j in range(i + 1, bodies.size()):
			var o: WreckPhysics.Body = bodies[j]
			o.turned()
			if a.p.distance_to(o.p) > a.reach + o.reach:
				continue
			var least := WreckPhysics._least(a, o)
			# A piece's thinnest half is how far in it may be and still be beside.
			var room := minf(a.half[0], minf(a.half[1], a.half[2]))
			room = minf(room, minf(o.half[0], minf(o.half[1], o.half[2])))
			worst = maxf(worst, least.length() - room)
	_check(
		not wreck.physics.moving() and worst < .04,
		"the heap comes to rest with no piece inside another (%.3f)" % worst
	)


## A lid lying inside a hoop does not hold the hoop up on its rim.
func _hollow() -> void:
	var physics := _fresh()
	var lid := physics.add(
		Vector3(at.x, at.y, ground + .015),
		Quaternion.IDENTITY,
		Vector3(.22, .22, .015),
		"wood",
		"disc"
	)
	var hoop := physics.add(
		Vector3(at.x, at.y, ground + .3),
		Quaternion(Vector3(1.0, 0.0, 0.0), PI * .5),
		Vector3(.3, .3, .025),
		"iron",
		"ring"
	)
	_settle(physics, 900)
	_check(
		absf(Basis(hoop.q).z.z) > .9 and hoop.p.z < ground + .1 and not lid.awake,
		(
			"a hoop stood over a lid goes over and lies round it (axis up %.2f)"
			% absf(Basis(hoop.q).z.z)
		)
	)


## Every stuff's knock sounds (each take) are in the sound bank.
func _cues() -> void:
	var index: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets_gen/sfx_index.json")
	)
	var cues: Dictionary = index["cues"] if index is Dictionary else {}
	var cfg := Tuning.file(WreckPhysics.PATH)
	var missing: Array = []
	for section: String in cfg.get_sections():
		if not section.begins_with("stuff."):
			continue
		var made := WreckPhysics.stuff_of(section.substr(6))
		var names: Array = [made.spin_cue, made.cue, made.cue_hard]
		names.append_array(made.alts)
		for cue: String in names:
			if cue != "" and not cues.has(cue) and not missing.has(cue):
				missing.append(cue)
	_check(missing.is_empty(), "every stuff's knock sounds are in the bank %s" % str(missing))
