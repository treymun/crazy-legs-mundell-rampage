## Ladders and ledges, for the player and the county's hands (the level's
## ladders are LevelGeometry.Ladder, from the plan's geometry block).
##
## The player walks into a ladder's foot facing it and is on it: FORWARD
## climbs, BACK goes down (turned away from it, the other way round), at a
## steady pace (a 1997 ladder), JUMP lets go.
## At the top they step off onto the floor beyond; walking off that floor's
## edge at a ladder's top puts them on it going down. JUMP and FORWARD at a
## ledge up to about chest high (MANTLE_MAX over the floor they stand or
## jumped from) pulls them up onto it. Both are a move from one point to
## another over a short time (Player.climb_*), carried online like the rest of
## the body.
##
## A hand after the player takes a ladder where its flow field leads up or
## down one (the nav graph joins a ladder's foot and top: LevelGeometry.nav),
## climbs at its own pace and steps off; one that walks off a roof's or a
## loft's edge falls instead of dropping to the floor below at once, and is
## winded a moment as it lands. No dice.
class_name Climbing
extends RefCounted

static var LADDER_SPEED: float = ModeData.get_value("climbing", "ladder_speed", 1.55)
static var HAND_SPEED: float = ModeData.get_value("climbing", "hand_ladder_speed", 1.25)
static var MANTLE_MAX: float = ModeData.get_value("climbing", "mantle_max", 1.15)
static var MANTLE_TIME: float = ModeData.get_value("climbing", "mantle_time", .28)
static var MANTLE_PER: float = ModeData.get_value("climbing", "mantle_per", .3)
static var TOP_STEP: float = ModeData.get_value("climbing", "top_step", .26)
static var GRAVITY: float = ModeData.get_value("climbing", "fall_gravity", 9.2)
static var LANDING: float = ModeData.get_value("climbing", "landing_stun", .3)
## A hand drops at least this far before it falls rather than steps down.
const DROP := .5
## How near a ladder's foot (or its top's edge) the player gets on it.
const REACH := .5


static func ladders(game: GameWorld) -> Array[LevelGeometry.Ladder]:
	var geo: LevelGeometry = game.world.geo
	if geo == null:
		return []
	return geo.ladders


# ------------------------------------------------------------------ player


## The player's body for a tick while climbing: on a ladder, pulling up onto
## a ledge or stepping on or off a ladder's top, or taking hold of one now.
## True when it moved them (game.gd leaves out the walk, the jump and the fall).
static func player_step(game: GameWorld, p: Player, c: GameState.Controls, dt: float) -> bool:
	if p.climb_time > 0.0:
		_move_on(game, p, dt)
		return true
	if p.ladder >= 0:
		_on_ladder(game, p, c, dt)
		return true
	var list := ladders(game)
	if not list.is_empty() and c.forward > 0.0 and _take_hold(p, list):
		return true
	var fresh := c.jump and not p.jump_held
	if c.forward > 0.0 and not c.crouch and (fresh or (p.air > 0.0 and c.jump)):
		return _mantle(game, p)
	return false


## The move under way: the body from climb_from to climb_to, lifted along a
## curve (quick at first, settling at the end); then on the ladder it was
## going to (climb_then) or stood on the floor at climb_to.
static func _move_on(game: GameWorld, p: Player, dt: float) -> void:
	p.climb_t = minf(p.climb_time, p.climb_t + dt)
	var f := p.climb_t / p.climb_time
	var flat := f * f * (3.0 - 2.0 * f)
	var lift := sqrt(f)
	var a := p.climb_from
	var b := p.climb_to
	p.x = lerpf(a.x, b.x, flat)
	p.y = lerpf(a.y, b.y, flat)
	var z := lerpf(a.z, b.z, lift if b.z >= a.z else flat)
	p.vx = 0.0
	p.vy = 0.0
	p.vertical_speed = 0.0
	p.crouched = false
	if f < 1.0:
		p.floor_z = minf(a.z, b.z)
		p.air = maxf(0.0, z - game.world.stand(p))
		return
	p.climb_time = 0.0
	p.climb_t = 0.0
	if p.climb_then >= 0:
		var lad: LevelGeometry.Ladder = ladders(game)[p.climb_then]
		p.ladder = p.climb_then
		p.climb_then = -1
		p.floor_z = lad.z0
		p.air = maxf(0.0, z - lad.z0)
		return
	p.floor_z = b.z
	p.air = 0.0
	p.floor_z = game.world.stand(p)


## On a ladder: up or down it at a steady pace, held at its foot; JUMP lets
## go; off at the top onto the floor beyond, or at the foot.
static func _on_ladder(game: GameWorld, p: Player, c: GameState.Controls, dt: float) -> void:
	var list := ladders(game)
	if p.ladder >= list.size():
		p.ladder = -1
		return
	var lad: LevelGeometry.Ladder = list[p.ladder]
	var at := lad.foot()
	p.x += (at.x - p.x) * minf(1.0, dt * 14.0)
	p.y += (at.y - p.y) * minf(1.0, dt * 14.0)
	p.vx = 0.0
	p.vy = 0.0
	p.vertical_speed = 0.0
	p.crouched = false
	p.floor_z = lad.z0
	var was := p.air
	if c.jump and not p.jump_held:
		# Let go: off backward, falling from where they are.
		p.ladder = -1
		p.vx = -lad.dx * 1.4
		p.vy = -lad.dy * 1.4
		p.jump_held = true
		return
	# Facing the ladder FORWARD climbs; turned away from it, FORWARD goes down
	# (stepped onto it from the top, say).
	var toward := cos(p.angle) * lad.dx + sin(p.angle) * lad.dy >= -.2
	var way := clampf(c.forward, -1.0, 1.0) * (1.0 if toward else -1.0)
	p.air = clampf(p.air + way * LADDER_SPEED * dt, 0.0, lad.z1 - lad.z0)
	if int(p.air / LevelGeometry.RUNG) != int(was / LevelGeometry.RUNG):
		_rung(game, lad, p.x, p.y)
	if way > 0.0 and p.air >= lad.z1 - lad.z0 - .01:
		# Over the top: step off onto the floor beyond.
		var top := lad.top()
		p.ladder = -1
		_start(p, Vector3(p.x, p.y, lad.z1), Vector3(top.x, top.y, lad.z1), TOP_STEP, -1)
		p.floor_z = lad.z0
		p.air = lad.z1 - lad.z0
	elif way < 0.0 and p.air <= 0.0:
		p.ladder = -1
		p.air = 0.0
		p.floor_z = game.world.stand(p)


## Walking into a ladder's foot facing it, or off the floor at its top
## toward it: on it (from the top by a short step over the edge).
static func _take_hold(p: Player, list: Array[LevelGeometry.Ladder]) -> bool:
	var feet := p.floor_z + p.air
	var fx := cos(p.angle)
	var fy := sin(p.angle)
	for i in list.size():
		var lad := list[i]
		var facing := fx * lad.dx + fy * lad.dy
		if absf(feet - lad.z0) < .3 and facing > .55:
			var at := lad.foot()
			if Vector2(p.x - at.x, p.y - at.y).length() < REACH:
				p.ladder = i
				p.air = maxf(0.0, feet - lad.z0)
				p.floor_z = lad.z0
				return true
		elif absf(feet - lad.z1) < .3 and facing < -.55:
			var off := Vector2(p.x - lad.x, p.y - lad.y)
			var along := absf(off.x * lad.dy - off.y * lad.dx)
			var depth := off.x * lad.dx + off.y * lad.dy
			if along < .3 and depth > -.05 and depth < REACH:
				var at := lad.foot()
				_start(p, Vector3(p.x, p.y, feet), Vector3(at.x, at.y, lad.z1 - .15), TOP_STEP, i)
				return true
	return false


## JUMP and FORWARD at a ledge no higher than MANTLE_MAX over the floor they
## stood on: pulled up onto it, if a body fits there.
static func _mantle(game: GameWorld, p: Player) -> bool:
	var w: LevelData = game.world
	var feet := p.floor_z + p.air
	# The floor stood on, or jumped from (a jump between two stacks).
	var base := maxf(p.floor_z, feet - .45)
	var fx := cos(p.angle)
	var fy := sin(p.angle)
	for reach: float in [.42, .62]:
		var px := p.x + fx * reach
		var py := p.y + fy * reach
		if px < 0.0 or py < 0.0 or px >= w.width or py >= w.height:
			return false
		var top := w.floor_under(px, py, base + MANTLE_MAX)
		if top - base <= LevelGeometry.STEP + .05 or top < feet - .05:
			continue
		if not fits(w, p.x, p.y, px, py, top):
			continue
		var into := Vector3(px + fx * .06, py + fy * .06, top)
		var time := MANTLE_TIME + MANTLE_PER * maxf(0.0, top - feet)
		_start(p, Vector3(p.x, p.y, feet), into, time, -1)
		game.sound_at("step_wood_1", px, py, .5)
		return true
	return false


## Whether a standing body fits at (x, y) with its feet at z, and nothing
## stands between there and (from_x, from_y) at that height.
static func fits(w: LevelData, from_x: float, from_y: float, x: float, y: float, z: float) -> bool:
	if w.geo == null:
		if w.blocked(x, y, .2) or w.blocked((x + from_x) * .5, (y + from_y) * .5, .1):
			return false
		var roof: float = w.roof_over(x, y, z)
		return roof == 0.0 or roof - z >= LevelGeometry.BODY
	var geo: LevelGeometry = w.geo
	if geo.blocked_body(w, x, y, .2, z, LevelGeometry.BODY):
		return false
	if geo.blocked_body(w, (x + from_x) * .5, (y + from_y) * .5, .1, z, LevelGeometry.BODY):
		return false
	var over: float = w.roof_over(x, y, z)
	return over == 0.0 or over - z >= LevelGeometry.BODY


static func _start(p: Player, from: Vector3, to: Vector3, time: float, then: int) -> void:
	p.climb_from = from
	p.climb_to = to
	p.climb_time = maxf(.05, time)
	p.climb_t = 0.0
	p.climb_then = then
	p.vx = 0.0
	p.vy = 0.0
	p.vertical_speed = 0.0


## A footfall on a rung: wood, or the plate of a metal ladder.
static func _rung(game: GameWorld, lad: LevelGeometry.Ladder, x: float, y: float) -> void:
	var names: PackedStringArray = game.world.tile_names
	var kind := (
		Materials.of_name(names[lad.tile]) if lad.tile >= 0 and lad.tile < names.size() else ""
	)
	var metal := kind == "tin" or kind == "steel" or kind == "mesh"
	game.sound_at("step_tile_0" if metal else "step_wood_0", x, y, .42)


# ------------------------------------------------------------------- hands


## Every tick of an enemy (Enemy.tick, before it looks or thinks): on a
## ladder it climbs, falling it falls, and it notices a drop it just walked
## off. True while it does nothing else.
static func enemy_step(e: Enemy, dt: float, game: Game) -> bool:
	if e.ladder >= 0:
		_hand_climb(e, dt, game)
		return true
	if e.climb_z > 0.0:
		e.fall -= GRAVITY * dt
		e.climb_z = maxf(0.0, e.climb_z + e.fall * dt)
		if e.climb_z == 0.0:
			e.fall = 0.0
			e.stun = maxf(e.stun, LANDING)
			var floor_z: float = game.world.stand(e)
			game.burst(e.x, e.y, floor_z + .1, "dust", 6, 1.2)
			game.sound_at("step_gravel_1", e.x, e.y, .7)
		e.last_floor = e.floor_z
		return true
	if e.floor_z < e.last_floor - DROP and e.hostile:
		# Walked off an edge: fall the rest of the way.
		e.climb_z = e.last_floor - e.floor_z
		e.fall = 0.0
		e.last_floor = e.floor_z
		return true
	e.last_floor = e.floor_z
	return false


static func _hand_climb(e: Enemy, dt: float, game: Game) -> void:
	var list := ladders(game)
	if e.ladder >= list.size():
		e.ladder = -1
		e.climb_z = 0.0
		return
	var lad: LevelGeometry.Ladder = list[e.ladder]
	var at := lad.foot()
	e.x += (at.x - e.x) * minf(1.0, dt * 10.0)
	e.y += (at.y - e.y) * minf(1.0, dt * 10.0)
	e.angle = atan2(lad.dy, lad.dx)
	e.floor_z = lad.z0
	var was := e.climb_z
	var rise := lad.z1 - lad.z0
	e.climb_z = clampf(e.climb_z + (HAND_SPEED if e.climb_up else -HAND_SPEED) * dt, 0.0, rise)
	e.gait += absf(e.climb_z - was) * 6.0
	if int(e.climb_z / LevelGeometry.RUNG) != int(was / LevelGeometry.RUNG):
		_rung(game, lad, e.x, e.y)
	if e.climb_up and e.climb_z >= rise:
		var top := lad.top()
		e.x = top.x
		e.y = top.y
		e.floor_z = lad.z1
		e.ladder = -1
		e.climb_z = 0.0
		e.floor_z = game.world.stand(e)
		e.last_floor = e.floor_z
	elif not e.climb_up and e.climb_z <= 0.0:
		e.ladder = -1
		e.floor_z = game.world.stand(e)
		e.last_floor = e.floor_z


## An alerted hand where its flow field leads up or down a ladder (the field
## from the player it is after steps from one end of a ladder to the other):
## it takes hold. True when it did.
static func hand_takes_ladder(e: Enemy, game: Game) -> bool:
	var f: FlowField = game.flow
	var list := ladders(game)
	if list.is_empty() or f == null or f.graph == null or e.ladder >= 0:
		return false
	var g: LevelGeometry.NavGraph = f.graph
	var w: LevelData = game.world
	var here := g.node_at(e.x, e.y, w.width, w.height, e.floor_z)
	if here < 0:
		return false
	for i in mini(list.size(), g.ladder_ends.size()):
		var ends: Vector2i = g.ladder_ends[i]
		if ends.x != here and ends.y != here:
			continue
		var other := ends.y if ends.x == here else ends.x
		if f.downhill_node(here) != other:
			continue
		var lad := list[i]
		var up := ends.x == here
		var at := lad.foot() if up else lad.top()
		if Vector2(e.x - at.x, e.y - at.y).length() > 1.0:
			continue
		e.ladder = i
		e.climb_up = up
		if up:
			e.climb_z = maxf(0.0, e.floor_z - lad.z0)
		else:
			# Over the edge and onto it from the top.
			var foot := lad.foot()
			e.x = foot.x
			e.y = foot.y
			e.floor_z = lad.z0
			e.climb_z = lad.z1 - lad.z0 - .05
			e.last_floor = lad.z0
		e.floor_z = lad.z0
		return true
	return false
