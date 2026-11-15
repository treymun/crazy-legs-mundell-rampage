## Loose things on the levels' real 3D shape (tools/check_all.gd runs it; this
## also runs on its own):
##
##   godot --headless --path godot --script res://tools/physics_check.gd [-- levels=hickston,quarry]
##
## On each level with geometry (decks, ramps, stair slabs) it drops a gib, a
## small gib, a casing, a crate's chunk and a body (each with the feel its
## feature gives it, tumble.gd) onto the decks, the ramps and the stair treads,
## from just above and falling fast, flings them up under a deck, and throws
## them hard at walls; ticks them and checks they come to rest on a surface
## (within TOL of the floor really under them), never inside a wall, a deck or
## furniture at any moment, never through a wall or up through a deck, and
## that brass slides down a ramp. Then the features themselves on a loft
## (hickston's hay loft): a revolver's brass dumped there lies on the boards, a
## blast's scorch and a burst's blood land on the boards, the gibs come to rest
## on surfaces and turn over in the air and lie flat, a chunk left hanging over
## nothing falls, a body thrown on the loft lies on a floor; and the same throw
## twice moves the same (play's bodies stay in step).
extends SceneTree

const DT := 1.0 / 60.0
const TOL := .03
const LEVELS := ["hickston", "feedstore", "quarry", "sawmill", "county_hickston", "mothership"]

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
		var game: Game = main.make_game(id)
		game.configure({})
		print("\n%s" % id.to_upper())
		_level(game)
	print("\nFEATURES ON A LOFT")
	_features(main)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("PHYSICS OK" if failures.is_empty() else "%d PHYSICS CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
	else:
		print("  FAIL ", text)
		failures.append(text)


func _ok(text: String) -> void:
	print("  ok   ", text)


## What is dropped: [name, feel, half steps (a body: two a tick, as corpses.gd)].
func _things(game: Game) -> Array:
	var gore: Gore = game.gore_fx
	var debris = game.features.get("debris")
	var breaks = game.features.get("breakables")
	var corpses = game.features.get("corpses")
	var out := [["gib", gore._feel(.24), false], ["eye", gore._feel(.09), false]]
	if debris != null:
		out.append(["casing", debris._case_feel, false])
	if breaks != null:
		out.append(["chunk", breaks._feel("fx_brk_wood_0"), false])
	if corpses != null:
		out.append(["body", corpses._flung, true])
	return out


## Moves one body for `seconds` (or until it rests). Returns [body, inside count,
## the highest it reached].
func _drop(
	world: LevelData, feel: Tumble.Feel, at: Vector3, v: Vector3, halves: bool, seconds := 6.0
) -> Array:
	var b := Tumble.Body.new()
	b.x = at.x
	b.y = at.y
	b.z = at.z
	b.vx = v.x
	b.vy = v.y
	b.vz = v.z
	var inside := 0
	var top := b.z
	var t := 0.0
	while t < seconds and not b.rest:
		for _k in 2 if halves else 1:
			var hit := Tumble.step(world, b, feel, DT * (.5 if halves else 1.0))
			if _inside(world, b, feel):
				inside += 1
			top = maxf(top, b.z)
			if hit & Tumble.RESTED:
				b.rest = true
				break
		t += DT
	return [b, inside, top]


## Whether a body is inside a wall, furniture or a slab (its middle, at half
## its own radius: it is kept a radius clear).
func _inside(world: LevelData, b: Variant, feel: Tumble.Feel) -> bool:
	var bottom: float = b.z - feel.lift
	return world.blocked(b.x, b.y, feel.radius * .5, bottom + feel.radius)


## Whether a body lies on the floor really under it, within TOL.
func _resting_on_floor(world: LevelData, b: Variant, feel: Tumble.Feel) -> bool:
	var floor_z := Tumble.floor_at(world, b.x, b.y, b.z - feel.lift + .01, feel.radius) + feel.lift
	return absf(b.z - floor_z) < TOL


func _level(game: Game) -> void:
	var world := game.world
	if world.geo == null:
		_check(false, "%s has no geometry to drop things on" % game.level.id)
		return
	var things := _things(game)
	var decks := 0
	var ramps := 0
	var stairs := 0
	for s: LevelGeometry.Slab in world.geo.slabs:
		if not s.walk:
			continue
		var mid := _middle(s)
		if mid == Vector2.INF:
			continue
		var top := s.top_at(mid.x, mid.y)
		if world.blocked(mid.x, mid.y, .3, top + .3):
			continue
		if s.sloped():
			if ramps < 3:
				ramps += 1
				_ramp(game, s, mid, things)
		elif s.kind == "stair":
			if stairs < 3:
				stairs += 1
				_onto(game, s, mid, top, things, "stair %s" % s.id)
		elif s.thick > 0.0:
			if decks < 3:
				decks += 1
				_onto(game, s, mid, top, things, "deck %s" % s.id)
				_under(game, s, mid, top, things)
	_check(decks + ramps + stairs > 0, "%s: something to drop on" % game.level.id)
	_ok("%d decks, %d ramps, %d stairs" % [decks, ramps, stairs])
	_walls(game, things)


## The slab's footprint middle (INF when it is not inside its own cuts).
func _middle(s: LevelGeometry.Slab) -> Vector2:
	var mid := Vector2((s.x0 + s.x1) * .5, (s.y0 + s.y1) * .5)
	return mid if s.inside(mid.x, mid.y) else Vector2.INF


## Dropped onto a slab's top from just above, and falling fast from high up.
func _onto(
	game: Game, s: LevelGeometry.Slab, mid: Vector2, top: float, things: Array, what: String
) -> void:
	var world := game.world
	var room := world.roof_over(mid.x, mid.y, top + .05)
	var high := 3.0 if room == 0.0 else minf(3.0, room - top - .3)
	var bad := 0
	for thing: Array in things:
		var feel: Tumble.Feel = thing[1]
		for drop: Array in [[.4, 0.0], [high, -9.0]]:
			var r := _drop(
				world,
				feel,
				Vector3(mid.x, mid.y, top + float(drop[0])),
				Vector3(.2, .1, drop[1]),
				thing[2]
			)
			var b: Tumble.Body = r[0]
			var on_it := absf(b.z - feel.lift - top) < TOL
			var fine: bool = r[1] == 0 and b.rest and _resting_on_floor(world, b, feel)
			# Straight down onto the middle of a wide slab: it stays on it (off a
			# narrow stair tread a bounce may take it onto the next one).
			if minf(s.x1 - s.x0, s.y1 - s.y0) >= 1.0:
				fine = fine and on_it
			if not fine:
				bad += 1
				_check(
					false,
					(
						"%s: %s from %.1f up lies at %.3f (top %.3f, rest %s, inside %d)"
						% [what, thing[0], drop[0], b.z, top, b.rest, r[1]]
					)
				)
	if bad == 0:
		_check(true, what)
		_ok("%s: everything dropped on it (fast too) rests on its top" % what)


## Flung up from the ground under a deck: it never comes up through it.
func _under(game: Game, s: LevelGeometry.Slab, mid: Vector2, top: float, things: Array) -> void:
	var world := game.world
	var ground := world.elevation(mid.x, mid.y)
	var bottom := top - s.thick
	if bottom - ground < .6 or world.blocked(mid.x, mid.y, .3, ground + .3):
		return
	var bad := 0
	for thing: Array in things:
		var feel: Tumble.Feel = thing[1]
		var r := _drop(
			world, feel, Vector3(mid.x, mid.y, ground + .1), Vector3(.3, 0.0, 9.0), thing[2]
		)
		var b: Tumble.Body = r[0]
		var top_reached: float = r[2]
		if top_reached > bottom or r[1] != 0 or not _resting_on_floor(world, b, feel):
			bad += 1
			_check(
				false,
				(
					"under %s: %s flung up reached %.2f (underside %.2f), lies at %.2f"
					% [s.id, thing[0], top_reached, bottom, b.z]
				)
			)
	if bad == 0:
		_check(true, "under %s" % s.id)
		_ok("under deck %s: flung up hard, nothing comes through it" % s.id)


## Dropped on a ramp: it rests on a floor, and brass slides down it.
func _ramp(game: Game, s: LevelGeometry.Slab, mid: Vector2, things: Array) -> void:
	var world := game.world
	var top := s.top_at(mid.x, mid.y)
	var bad := 0
	for thing: Array in things:
		var feel: Tumble.Feel = thing[1]
		var r := _drop(world, feel, Vector3(mid.x, mid.y, top + .3), Vector3.ZERO, thing[2], 8.0)
		var b: Tumble.Body = r[0]
		if r[1] != 0 or not b.rest or not _resting_on_floor(world, b, feel):
			bad += 1
			_check(
				false,
				(
					"ramp %s: %s lies at %.2f,%.2f,%.3f (v %.2f,%.2f rest %s, inside %d, ground %.2f)"
					% [
						s.id,
						thing[0],
						b.x,
						b.y,
						b.z,
						b.vx,
						b.vy,
						b.rest,
						r[1],
						world.elevation(b.x, b.y)
					]
				)
			)
			continue
		if thing[0] == "casing":
			var down := Vector2(b.x - mid.x, b.y - mid.y).dot(Vector2(-s.gx, -s.gy))
			if down <= .2:
				bad += 1
				_check(false, "ramp %s: brass did not slide down it (%.2f)" % [s.id, down])
	if bad == 0:
		_check(true, "ramp %s" % s.id)
		_ok("ramp %s: all rest on a floor, brass slides down it" % s.id)


## Thrown hard at walls (ground cells with a solid cell east): never through.
func _walls(game: Game, things: Array) -> void:
	var world := game.world
	var found := 0
	var bad := 0
	var y := 2
	while y < world.height - 2 and found < 4:
		for x in range(3, world.width - 1):
			if found >= 4:
				break
			if world.solid[y * world.width + x + 1] < 0:
				continue
			var ok_run := true
			for k in 3:
				var c := y * world.width + x - k
				ok_run = ok_run and world.solid[c] < 0
				ok_run = ok_run and absf(world.ground[c] - world.ground[y * world.width + x]) < .01
			var from := Vector2(x - 1.5, y + .5)
			var ground := world.elevation(from.x, from.y)
			if not ok_run or world.blocked(from.x, from.y, .35, ground + .3):
				continue
			if world.geo != null and not world.geo.clear_at(x + .5, y + .5):
				continue
			found += 1
			var face := float(x + 1)
			for thing: Array in things:
				var feel: Tumble.Feel = thing[1]
				var r := _drop(
					world,
					feel,
					Vector3(from.x, from.y, ground + .5),
					Vector3(7.0, 0.0, 1.0),
					thing[2]
				)
				var b: Tumble.Body = r[0]
				if b.x >= face or r[1] != 0 or not _resting_on_floor(world, b, feel):
					bad += 1
					_check(
						false,
						(
							"wall at %d,%d: %s thrown at it ends at %.2f,%.2f z %.2f (face %.1f, inside %d)"
							% [x + 1, y, thing[0], b.x, b.y, b.z, face, r[1]]
						)
					)
		y += maxi(1, world.height / 9)
	if found > 0 and bad == 0:
		_check(true, "walls")
		_ok("%d walls: everything thrown hard at them bounces back and lies on the floor" % found)


# ------------------------------------------------------------ the features


func _features(main) -> void:
	var game: Game = main.make_game("hickston")
	game.configure({})
	var world := game.world
	var loft: LevelGeometry.Slab = null
	for s: LevelGeometry.Slab in world.geo.slabs:
		if s.id == "hay_loft":
			loft = s
	if loft == null:
		_check(false, "hickston has its hay loft")
		return
	var mid := Vector2((loft.x0 + loft.x1) * .5, (loft.y0 + loft.y1) * .5)
	var top := loft.top
	var on_loft := func(x: float, y: float) -> bool: return loft.inside(x, y)
	# Brass dumped on the loft lies on its boards.
	var p := game.player
	p.x = mid.x
	p.y = mid.y
	p.floor_z = top
	p.eye = top + .95
	var debris = game.features["debris"]
	debris.bits.clear()
	game.events.gun_reloading.emit(Weapons.REVOLVER)
	for _t in 360:
		debris._tick(DT)
	var lying := 0
	var wrong := 0
	for bit in debris.bits:
		if bit.kind != "casing":
			continue
		var floor_z := Tumble.floor_at(world, bit.x, bit.y, bit.z + .01, debris._case_feel.radius)
		if not bit.rest or absf(bit.z - floor_z) > TOL:
			wrong += 1
		elif on_loft.call(bit.x, bit.y) and absf(bit.z - top) < TOL:
			lying += 1
	_check(
		wrong == 0 and lying >= 3,
		"revolver brass lies on the loft (%d on it, %d wrong)" % [lying, wrong]
	)
	_ok("a revolver's brass dumped on the loft: %d lie on its boards, %d wrong" % [lying, wrong])
	# A blast's scorch on the boards.
	game.events.exploded.emit(mid.x + .5, mid.y, top + .4, false)
	var scorch: Array = debris.scorches[debris.scorches.size() - 1]
	var mark: View.GroundMark = scorch[8]
	_check(
		absf(mark.z - top) < .01,
		"a blast on the loft scorches its boards (%.3f, top %.3f)" % [mark.z, top]
	)
	_ok("a blast on the loft scorches its boards (z %.3f)" % mark.z)
	# A burst on the loft: the gibs fly, turn, rest on surfaces; the blood lands on the boards.
	var gore: Gore = game.gore_fx
	gore.gibs.clear()
	gore.blood_marks.clear()
	var e: Enemy = null
	for one: Enemy in game.enemies:
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind) and not GoreExtras.metal(one):
			e = one
			break
	e.x = mid.x
	e.y = mid.y
	e.floor_z = top
	p.x = mid.x - 2.0
	gore.burst(e)
	var spun := false
	for t in 480:
		gore.tick(DT)
		if t == 8:
			for g: Gore.Gib in gore.gibs:
				spun = spun or (not g.rest and g.spin != 0.0)
	var resting := 0
	var flat := 0
	var off := 0
	for g: Gore.Gib in gore.gibs:
		var feel := gore._feel(g.size)
		if g.rest and _resting_on_floor(world, g, feel) and not _inside(world, g, feel):
			resting += 1
		else:
			off += 1
			print(
				(
					"    %s at %.2f,%.2f,%.3f rest %s v %.2f,%.2f,%.2f floor %.3f inside %s"
					% [
						g.image,
						g.x,
						g.y,
						g.z,
						g.rest,
						g.vx,
						g.vy,
						g.vz,
						Tumble.floor_at(world, g.x, g.y, g.z + .05),
						_inside(world, g, feel)
					]
				)
			)
		if is_equal_approx(fposmod(g.spin + .001, PI), .001) or g.spin == 0.0:
			flat += 1
	_check(off == 0, "a burst's gibs all rest on surfaces (%d off)" % off)
	_check(spun, "gibs turn over in the air")
	_check(flat == gore.gibs.size(), "gibs at rest lie flat (%d of %d)" % [flat, gore.gibs.size()])
	_ok("a burst on the loft: %d gibs rest on surfaces, turned in the air, lie flat" % resting)
	var stains := 0
	var sunk := 0
	for m: View.GroundMark in gore.blood_marks:
		if on_loft.call(m.x, m.y) and Vector2(m.x - mid.x, m.y - mid.y).length() < 1.0:
			stains += 1
			if absf(m.z - top) > .01:
				sunk += 1
	_check(
		stains > 0 and sunk == 0,
		"the burst's blood lands on the loft boards (%d, %d not)" % [stains, sunk]
	)
	_ok("its blood lands on the loft's boards (%d marks)" % stains)
	# A chunk left lying on nothing falls and lies on the floor.
	var hanging := Gore.Gib.new()
	hanging.x = mid.x
	hanging.y = mid.y
	hanging.z = top + 1.0
	hanging.size = .2
	hanging.rest = true
	gore.gibs.append(hanging)
	for _t in 300:
		gore.tick(DT)
	_check(
		hanging.rest and absf(hanging.z - top) < TOL,
		"a chunk left over nothing falls to the boards (%.3f)" % hanging.z
	)
	_ok("a chunk left hanging over nothing falls and lies on the boards")
	# A body thrown along the loft lies on a floor, the same both times.
	var corpses = game.features["corpses"]
	var lies: Array = []
	for k in 2:
		e.alive = false
		e.died_at = game.clock
		e.x = mid.x
		e.y = mid.y
		e.toss = 0.0
		e.floor_z = top
		corpses.moving.clear()
		corpses._push(e, 3.2, .4, 2.0)
		for _t in 600:
			if corpses.moving.is_empty():
				break
			corpses._move(DT)
		lies.append(Vector3(e.x, e.y, e.toss))
	var z: float = world.floor_under(e.x, e.y, top + 1.0) + e.toss
	var floor_z := Tumble.floor_at(world, e.x, e.y, z + .01, corpses._feel.radius)
	_check(
		corpses.moving.is_empty() and absf(z - floor_z) < TOL,
		"a body thrown on the loft lies on a floor"
	)
	_check(lies[0] == lies[1], "the same throw twice lies the same (%s, %s)" % [lies[0], lies[1]])
	_ok("a body thrown along the loft lies on a floor, the same both times")
