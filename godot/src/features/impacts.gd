## Where a bullet lands, by what it lands in (materials.gd): sparks that fall
## and bounce once off tin and steel, splinters off planks, brick and stone
## grit and a puff of dust, clods off dirt, husks off corn and hedge, chips of
## glass that glint where they lie; out the far side of a wall a strong round
## went through (penetration.gd), the same flying on with it.
##
## And what a fight leaves on the walls and floors, kept: holes that match the
## surface (game.wall_marks, made in game_combat.gd hitscan), pocks in the
## floor, a blast's scorch up the wall beside it, and blood that runs down a
## wall from a splat over a few seconds. Each list has a cap (effects.cfg
## [debris]) and a life; past either the oldest fade out first, then go.
## Looks only: its own dice, never saved. BULLET MARKS off: no holes, pocks or
## wall scorches; GORE off: no blood to run.
extends GameFeature

const WeaponFx := preload("res://src/features/weapon_fx.gd")

## Seconds a mark takes to fade out once its time is up.
const FADE := 1.6
## Seconds blood takes to run its length down a wall, and its six stages.
const RUN_TIME := 3.2
const RUN_FRAMES := 6
## How many pellets of one load throw chips (the rest only mark).
const PELLET_BITS := 5
## How many marking shots and blasts are kept for the 3D view (thing_hits).
const THING_KEEP := 24

var dice := RandomNumberGenerator.new()
var _pellets := 0
## Each bullet hole (game.wall_marks) by instance: [picture, made at, fading since].
var _holes := {}
## Floor pocks and wall scorches: [mark, picture, made at, fading since].
var pocks: Array = []
var scorches: Array = []
## Each wall splat of blood (game.gore_fx.walls) by instance: [splat,
## picture, made at, fading since, its run or null].
var _splats := {}
var _marks_out: Array = []
## For the 3D view's marks on modelled things (view3d/thing_marks.gd): the
## latest marking shots and blasts, [serial, from, to] (a blast: from == to),
## each with a serial so the view takes each once. Looks only.
var thing_hits: Array = []
var thing_serial := 0


func id() -> String:
	return "impacts"


func attach() -> void:
	dice.seed = 1949
	game.events.shot_fired.connect(_fired)
	game.events.traced.connect(_traced)
	game.events.pierced.connect(_pierced)
	game.events.exploded.connect(_exploded)
	tick_with(_tick)


func _cap(key: String, fallback: float) -> float:
	var cap: float = Effects.DEBRIS.get(key, fallback)
	return cap


func _fx() -> WeaponFx:
	return game.features.get("weapon_fx")


func _fired(_gun: int) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_fired.bind(_gun), "shot")
		return
	_pellets = 0


func own_shot(gun: int) -> void:
	_fired(gun)


# ------------------------------------------------------------------ striking


func _traced(end: Vector3, struck: String) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_traced.bind(end, struck), "trace")
		return
	var gun: int = game.armory.active
	var firing: Dictionary = Weapons.FIRING[gun]
	var mode := str(firing.get("fire", ""))
	if mode != "hitscan" and mode != "pellets":
		return
	if gun == Weapons.PRESSURE or gun == Weapons.TEAT:
		return
	var p := game.player
	var dir := (end - Vector3(p.x, p.y, p.eye)).normalized()
	if _marks_gun(gun) and struck != "enemy":
		_thing_hit(Vector3(p.x, p.y, p.eye), end)
	if struck == "glass":
		# A pane going: chips of it everywhere, glinting where they land.
		for _k in 8:
			_bit(
				"glint", end, _away(dir, 1.6, 1.2) + dir * 1.4, dice.randf_range(4.0, 7.0), .03, 9.0
			)
		return
	# "wall:" alone is a pellet that only shows its streak (no material known).
	if not struck.begins_with("wall:") or struck == "wall:":
		return
	_pellets += 1
	var kind: String = game.impact_kind
	if not (gun == Weapons.SHOTGUN and _pellets > PELLET_BITS):
		_chips(end - dir * .05, kind, -dir, gun)
	# Into the floor it struck: a deck's boards, a stair, a ramp, the ground.
	var floor_z: float = Tumble.floor_at(game.world, end.x, end.y, end.z + .1)
	if end.z < floor_z + .1 and _marks_gun(gun):
		_pock(end, kind)
	_adopt_holes()


func own_trace(end: Vector3, struck: String) -> void:
	_traced(end, struck)


## What flies off `kind` at `at`, thrown back along `out` (toward the gun for a
## hit, on through for a round coming out the far side).
func _chips(at: Vector3, kind: String, out: Vector3, gun: int) -> void:
	var fx := _fx()
	if fx == null:
		return
	match kind:
		"tin", "steel", "mesh":
			if gun != Weapons.RIVETER:
				var count: int = {"tin": 4, "steel": 6, "mesh": 2}[kind]
				fx.sparks(at, count, 2.4)
		"wood", "timber":
			for _k in 3:
				var v: Vector3 = fx.scatter(1.5, 1.6) + out * 1.3
				_bit("splinter", at, v, dice.randf_range(.9, 1.5), .055, 8.0)
			_puff(at, out, .08, .5)
		"brick", "stone":
			for _k in 4 if kind == "brick" else 3:
				var v: Vector3 = fx.scatter(1.4, 1.4) + out * 1.0
				_bit("grit_" + kind, at, v, dice.randf_range(.7, 1.1), .035, 9.0)
			_puff(at, out, .11 if kind == "stone" else .09, .7)
		"dirt":
			for _k in 3:
				var v: Vector3 = fx.scatter(1.2, 1.6) + out * .8
				_bit("clod", at, v, dice.randf_range(.5, .8), .035, 9.0)
			_puff(at, out, .12, .8)
		"brush":
			for _k in 4:
				var v: Vector3 = fx.scatter(.8, 1.2) + out * .6
				_bit("chaff", at, v, dice.randf_range(1.6, 2.4), .05, 2.5)
		"glass":
			for _k in 4:
				var v: Vector3 = fx.scatter(1.2, 1.0) + out * .9
				_bit("glint", at, v, dice.randf_range(3.0, 5.0), .028, 9.0)
		"rubber":
			_puff(at, out, .07, .4, "smoke")


func _bit(kind: String, at: Vector3, v: Vector3, life: float, size: float, gravity: float) -> void:
	var fx := _fx()
	if fx != null:
		fx.spawn(kind, at, v, life, size, gravity)


## A puff of dust off what was struck, rolling out a little and hanging.
func _puff(at: Vector3, out: Vector3, size: float, life: float, kind := "dust") -> void:
	var fx := _fx()
	if fx == null:
		return
	var puff: WeaponFx.Bit = fx.spawn(
		kind, at + out * .04, out * .5 + Vector3(0, 0, .15), life, size
	)
	puff.grow = size * 3.0


func _away(dir: Vector3, speed: float, up: float) -> Vector3:
	var a := dice.randf_range(0, TAU)
	var v := dice.randf_range(.3, 1.0) * speed
	return Vector3(cos(a) * v, sin(a) * v, dice.randf_range(.1, 1.0) * up) - dir * .2


func _marks_gun(gun: int) -> bool:
	return (
		gun
		in [
			Weapons.REVOLVER,
			Weapons.RIFLE,
			Weapons.SHOTGUN,
			Weapons.HUNTER,
			Weapons.MOWER,
			Weapons.COUNTY45,
			Weapons.STAR357,
			Weapons.HOGLEG,
			Weapons.RIOT_PUMP,
			Weapons.TOMMY,
			Weapons.GREASE_GUN,
			Weapons.PATROL_BAR,
			Weapons.MARKSMAN,
		]
	)


## A round out the far side of a wall: what it tears out flies on with it, and
## a hole there too.
func _pierced(entry: Vector3, exit: Vector3, _struck: String) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_pierced.bind(entry, exit, _struck), "trace")
		return
	var way := exit - entry
	var flat := Vector2(way.x, way.y).length()
	if flat < .001:
		return
	var dir := way / way.length()
	game.sound_at("pierce_plank", exit.x, exit.y, .6)
	var kind := Materials.struck(game.world, exit.x - dir.x * .04, exit.y - dir.y * .04, exit.z)
	_chips(exit + dir * .04, kind, dir, game.armory.active)
	if not _marks_gun(game.armory.active):
		return
	var ax := way.x / flat
	var ay := way.y / flat
	var slope := way.z / flat
	var back := .35
	var mark: View.WallMark = WallHits.wall_mark(
		game.world,
		exit.x - ax * back,
		exit.y - ay * back,
		exit.z - slope * back,
		ax,
		ay,
		slope,
		back
	)
	if mark != null and mark.tile >= 0:
		kind = Materials.of_tile(game.world, mark.tile)
	if mark != null and Materials.hole(kind) != "":
		mark.image = Materials.hole(kind)
		mark.radius = .07
		game.wall_marks.append(mark)
		_adopt_holes()


# ----------------------------------------------------------------- the marks


## Bullet holes the game made since last time: noted with when they were made.
func _adopt_holes() -> void:
	var marks: Array = game.wall_marks
	for k in range(marks.size() - 1, -1, -1):
		var mark: View.WallMark = marks[k]
		var key: int = mark.get_instance_id()
		if _holes.has(key):
			break
		_holes[key] = [mark.image, game.clock, -1.0]
	if _holes.size() > marks.size() + 24:
		# Some went without us (the game's own safety cap): forget them.
		var live := {}
		for m: View.WallMark in marks:
			var key: int = m.get_instance_id()
			if _holes.has(key):
				live[key] = _holes[key]
		_holes = live


## A pock in the floor where a round went into it.
func _pock(at: Vector3, kind: String) -> void:
	var picture := Materials.hole(kind)
	if kind == "dirt":
		picture = "mark_pock_%d" % dice.randi_range(0, 1)
	if picture == "" or game.world.blocked(at.x, at.y):
		return
	var size := .07 if kind == "dirt" else .05
	var mark := View.GroundMark.new(at.x, at.y, 0.0, dice.randf_range(0, TAU), size, size, picture)
	Tumble.lay(game.world, mark, at.z + .1)
	pocks.append([mark, picture, game.clock, -1.0])


## A marking shot from `from` to `to`, or a blast (from == to), for the 3D
## view to mark the modelled things it met (BULLET MARKS on).
func _thing_hit(from: Vector3, to: Vector3) -> void:
	if not game.bullet_marks:
		return
	thing_serial += 1
	thing_hits.append([thing_serial, from, to])
	if thing_hits.size() > THING_KEEP:
		thing_hits.pop_front()


## A blast against a wall scorches it: the nearest faces round it, up to two.
func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if energy:
		return
	_thing_hit(Vector3(x, y, z), Vector3(x, y, z))
	var world: LevelData = game.world
	# Up the wall from the floor the blast was over (a loft's, not the yard's).
	var floor_z: float = world.floor_under(x, y, z)
	var at_z := floor_z + clampf(z - floor_z, .3, 1.1)
	var found: Array = []
	var turn := dice.randf_range(0, TAU)
	for k in 8:
		var a := turn + k * TAU / 8.0
		var ax := cos(a)
		var ay := sin(a)
		var d := .15
		while d < 1.5:
			if world.blocked(x + ax * d, y + ay * d, .02, at_z):
				found.append([d, ax, ay])
				break
			d += .1
	found.sort_custom(
		func(m: Array, n: Array) -> bool:
			var dm: float = m[0]
			var dn: float = n[0]
			return dm < dn
	)
	for k in mini(2, found.size()):
		var hit: Array = found[k]
		var hit_d: float = hit[0]
		var hit_x: float = hit[1]
		var hit_y: float = hit[2]
		var mark: View.WallMark = WallHits.wall_mark(
			game.world, x, y, at_z, hit_x, hit_y, 0.0, hit_d
		)
		if mark == null:
			continue
		var picture := "fx_scorch_wall_%d" % dice.randi_range(0, 1)
		mark.image = picture
		mark.radius = dice.randf_range(.42, .58) * (1.2 - hit_d * .3)
		mark.z = maxf(at_z, floor_z + mark.radius * .8)
		scorches.append([mark, picture, game.clock, -1.0])


func _tick(_dt: float) -> void:
	_adopt_holes()
	_age_holes()
	_age_list(pocks, int(_cap("pock_cap", 40)), _cap("pock_life", 240.0))
	_age_list(scorches, int(_cap("wall_scorch_cap", 10)), _cap("scorch_life", 900.0))
	_bleed()


## Past the cap or their life, the oldest holes fade out and go.
func _age_holes() -> void:
	var marks: Array = game.wall_marks
	var over := marks.size() - int(_cap("hole_cap", 64))
	var life := _cap("hole_life", 300.0)
	var gone: Array = []
	for k in marks.size():
		var m: View.WallMark = marks[k]
		var found: Variant = _holes.get(m.get_instance_id())
		if found == null:
			continue
		var meta: Array = found
		var fading: float = meta[2]
		var made: float = meta[1]
		if fading < 0.0 and (k < over or game.clock - made > life):
			meta[2] = game.clock
			fading = game.clock
		if fading >= 0.0:
			var keep: float = 1.0 - (game.clock - fading) / FADE
			if keep <= 0.0:
				gone.append(m)
			else:
				m.image = game.art.faded_art(str(meta[0]), keep)
	for m: View.WallMark in gone:
		marks.erase(m)
		_holes.erase(m.get_instance_id())


## The same for a list of [mark, picture, made at, fading since].
func _age_list(list: Array, cap: int, life: float) -> void:
	if list.is_empty():
		return
	var over := list.size() - cap
	var k := 0
	while k < list.size():
		var row: Array = list[k]
		var fading: float = row[3]
		var made: float = row[2]
		if fading < 0.0 and (k < over or game.clock - made > life):
			row[3] = game.clock
			fading = game.clock
		if fading >= 0.0:
			var keep: float = 1.0 - (game.clock - fading) / FADE
			if keep <= 0.0:
				list.remove_at(k)
				over -= 1
				continue
			row[0].image = game.art.faded_art(str(row[1]), keep)
		k += 1


## New splats of blood on the walls start to run; past the cap the oldest
## fade (before gore.gd would drop them all at once).
func _bleed() -> void:
	var walls: Array = game.gore_fx.walls
	var live := {}
	for splat: View.WallMark in walls:
		var key: int = splat.get_instance_id()
		var row: Variant = _splats.get(key)
		if row == null:
			row = [splat, splat.image, game.clock, -1.0, _run_for(splat)]
		live[key] = row
	_splats = live
	var over := walls.size() - int(_cap("splat_keep", 26))
	var gone: Array = []
	for k in walls.size():
		var splat: View.WallMark = walls[k]
		var row: Array = _splats[splat.get_instance_id()]
		var fading: float = row[3]
		if fading < 0.0 and k < over:
			row[3] = game.clock
			fading = game.clock
		var keep := 1.0
		if fading >= 0.0:
			keep = 1.0 - (game.clock - fading) / FADE
			if keep <= 0.0:
				gone.append(splat)
				continue
			splat.image = game.art.faded_art(str(row[1]), keep)
		var run: View.WallMark = row[4]
		if run != null:
			var made: float = row[2]
			var stage := mini(RUN_FRAMES - 1, int((game.clock - made) / RUN_TIME * RUN_FRAMES))
			var acid := str(row[1]).begins_with("fx_acid")
			var picture := "fx_%srun_%d" % ["acid" if acid else "blood", stage]
			run.image = game.art.faded_art(picture, keep) if keep < 1.0 else picture
	for splat: View.WallMark in gone:
		walls.erase(splat)
		_splats.erase(splat.get_instance_id())


## The run of blood below a splat, high enough up a wall to run at all.
func _run_for(splat: View.WallMark) -> View.WallMark:
	var image := splat.image
	if not (image.begins_with("fx_blood") or image.begins_with("fx_acid")):
		return null
	# It runs down as far as the floor under the splat (a deck's, a loft's).
	var floor_z: float = game.world.floor_under(splat.x, splat.y, splat.z)
	var reach: float = minf(splat.radius * 1.15, (splat.z - floor_z) * .5)
	if reach < .1:
		return null
	var run := View.WallMark.new()
	run.x = splat.x
	run.y = splat.y
	run.ux = splat.ux
	run.uy = splat.uy
	run.radius = reach
	run.z = splat.z - reach * .8
	run.material = splat.material
	run.image = "fx_%srun_0" % ("acid" if image.begins_with("fx_acid") else "blood")
	return run


func wall_marks() -> Array:
	_marks_out.clear()
	if game.bullet_marks:
		for row: Array in scorches:
			_marks_out.append(row[0])
	if game.gore:
		for key: int in _splats:
			var run: View.WallMark = _splats[key][4]
			if run != null:
				_marks_out.append(run)
	return _marks_out


func ground_marks() -> Array:
	var out: Array = []
	if not game.bullet_marks:
		return out
	var p := game.player
	for row: Array in pocks:
		var m: View.GroundMark = row[0]
		if (m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y) < 144.0:
			out.append(m)
	return out
