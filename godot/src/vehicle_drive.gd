## How a vehicle drives (features/vehicles.gd keeps them; numbers in
## data/tuning/vehicles.cfg): plain arcade arithmetic on a Ride's numbers,
## the same on every machine (no dice). Throttle and brake on FORWARD/BACK,
## steering toward where the driver looks (mouse, pad or touch) or straight
## from STRAFE; a slide across the heading that grip wears away (JUMP is the
## handbrake); the hull an oblong of three circles that walls, furniture,
## closed doors, steps taller than its `step` and floors it does not run on
## stop; a bump bounces it back.
class_name VehicleDrive
extends RefCounted

const FILE := "res://data/tuning/vehicles.cfg"
## Steering toward the look: how much lock a radian off the look gives.
const LOOK_STEER := 2.2
## A bump keeps this much of the speed into the wall, turned back.
const BOUNCE := .25
## Falling off a ledge (cells a second).
const FALL := 5.0

static var _specs := {}


## A kind's numbers (vehicles.cfg says what each is).
class Spec:
	extends RefCounted
	var kind := ""
	var name := ""
	var picture := ""
	var engine := ""
	var height := 1.0
	var nose := 0.0
	var length := 2.0
	var width := 1.0
	var tall := 1.0
	var top := 5.0
	var reverse := 2.0
	var accel := 3.0
	var brake := 5.0
	var coast := 1.0
	var turn := 2.0
	var turn_full := 2.0
	var thrust_turn := 0.0
	var grip := 4.0
	var skid := 2.0
	var handbrake := 1.0
	var step := .12
	var floors := PackedStringArray()
	var slow_floors := PackedStringArray()
	var slow := 1.0
	var hp := 100.0
	var soak := .5
	var seats := 1
	var hands := 1
	var eye := 1.0
	var seat := 0.0
	## A rider's body seen from outside (looks only): how far its feet stand
	## over the floor (below it: sunk so the hips sit on the seat).
	var sit := 0.0
	var ram := 10.0
	var ram_from := 2.5
	var blade := 0.0
	var cuts := false
	var every := 1.0
	## How it looks on the move (src/vehicle_feel.gd, looks only): the
	## springs' pace and damping, the lean in a turn and the squat on the
	## throttle (and their most), the jolts off rough floors, the rocking on
	## water, and what it throws (spray, sparks off a wall, skids braking).
	var spring := 2.0
	var damp := .4
	var lean := .02
	var lean_most := .08
	var squat := .01
	var squat_most := .06
	var rough := 0.0
	var rough_off := 0.0
	var rock := 0.0
	var spray := false
	var sparks := false
	var brake_skid := false
	## The seat view (src/vehicle_cab.gd, view3d/cab_layer.gd; looks only):
	## its model, how much lower the eye sits in it and how far it tips its
	## nose up (to show more of it in the view), the wheel's or stick's lock
	## (radians), the engine's buzz in the view (cells, at its pace a second)
	## and the mower's chug, the eye's dip at top speed, the airboat's slaps
	## on the water and its bow's rise at speed (radians).
	var cab := ""
	var cab_drop := 0.0
	var cab_tilt := 0.0
	var cab_lock := .9
	var buzz := 0.0
	var buzz_hz := 30.0
	var chug := 0.0
	var seat_dip := 0.0
	var slap := 0.0
	var trim := 0.0


## A vehicle in play: plain numbers a snapshot carries and a save keeps.
class Ride:
	extends RefCounted
	var kind := ""
	var x := 0.0
	var y := 0.0
	## The floor under it.
	var z := 0.0
	## Heading (radians) and speed (cells a second).
	var h := 0.0
	var vx := 0.0
	var vy := 0.0
	var hp := 100.0
	## The slot in each seat (-1 empty); seat 0 drives.
	var seats: Array = []
	## When it was wrecked (-1: running).
	var wreck := -1.0
	## Its last bump: when it may sound again, and where it struck.
	var bump_at := -9.0
	var bump_x := 0.0
	var bump_y := 0.0
	## When the engine and the tyres are heard next.
	var engine_at := 0.0
	var skid_at := 0.0
	## The wheel's lock (-1..1) and the slide across the heading this tick;
	## the driver's throttle (-1..1: back is reverse) this tick.
	var steer := 0.0
	var gas := 0.0
	var slide := 0.0
	## Enemy uid -> when this vehicle may hit it again.
	var hits := {}
	## How many times it has struck something (bounced).
	var bumps := 0
	## The lap timer: turned round the track's middle, the lap's start, the
	## best lap, laps done, the last angle from the middle.
	var lap_turn := 0.0
	var lap_start := 0.0
	var lap_best := 0.0
	var laps := 0
	var lap_ang := 0.0


static func spec(kind: String) -> Spec:
	var kept: Spec = _specs.get(kind)
	if kept != null:
		return kept
	var cfg := Tuning.file(FILE)
	var s := Spec.new()
	s.kind = kind
	for prop: Dictionary in s.get_property_list():
		var usage: int = prop["usage"]
		var key := str(prop["name"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or key == "kind":
			continue
		if not cfg.has_section_key(kind, key):
			continue
		var raw: Variant = cfg.get_value(kind, key)
		if raw is Array:
			var names := PackedStringArray()
			var items: Array = raw
			for item: Variant in items:
				names.append(str(item))
			s.set(key, names)
		elif typeof(s.get(key)) == TYPE_FLOAT and raw is int:
			var whole: int = raw
			s.set(key, float(whole))
		elif typeof(s.get(key)) == TYPE_INT and raw is float:
			var part: float = raw
			s.set(key, roundi(part))
		else:
			s.set(key, raw)
	_specs[kind] = s
	return s


## A number of the [all] section.
static func shared(key: String) -> float:
	var raw: Variant = Tuning.file(FILE).get_value("all", key, 0.0)
	if raw is int:
		var whole: int = raw
		return float(whole)
	var part: float = raw
	return part


static func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for section: String in Tuning.file(FILE).get_sections():
		if section != "all":
			out.append(section)
	return out


## The hull's three circles' middles at (x, y) heading h.
static func circles(s: Spec, x: float, y: float, h: float) -> Array:
	var off := maxf(0.0, s.length * .5 - s.width * .5)
	var f := Vector2(cos(h), sin(h))
	return [Vector2(x, y) + f * off, Vector2(x, y), Vector2(x, y) - f * off]


## The floor's tile name under (x, y).
static func tile_at(w: LevelData, x: float, y: float) -> String:
	var t := int(w.floor_tile[w.cell(x, y)])
	return String(w.tile_names[t]) if t >= 0 and t < w.tile_names.size() else ""


## Whether the hull fits at (x, y) heading h with its floor near z: the floor
## it would stand on, or NAN where something stops it.
static func fits(w: LevelData, s: Spec, x: float, y: float, h: float, z: float) -> float:
	var r := s.width * .5
	var best := -INF
	for c: Vector2 in circles(s, x, y, h):
		if c.x - r < 0.0 or c.y - r < 0.0 or c.x + r >= w.width or c.y + r >= w.height:
			return NAN
		if s.floors.is_empty():
			if w.deep_at(c.x, c.y):
				return NAN
		elif not s.floors.has(tile_at(w, c.x, c.y)):
			return NAN
		var cell := w.cell(c.x, c.y)
		var under: float
		if w.geo != null:
			under = w.geo.floor_at(c.x, c.y, z + s.step, w.ground[cell], true)
			var higher := w.geo.floor_at(
				c.x, c.y, z + LevelGeometry.STEP + .01, w.ground[cell], true
			)
			if higher > z + s.step + .001:
				return NAN
			if w.geo.blocked_body(w, c.x, c.y, r * .92, under, s.tall):
				return NAN
		else:
			under = w.elevation(c.x, c.y)
			if under > z + s.step + .001 or w.blocked(c.x, c.y, r * .92):
				return NAN
		best = maxf(best, under)
	return best


## One tick of driving `v` with `c`'s throttle and steering; `look` is how
## far the driver's eye is turned from the heading (radians); `scale` slows
## it on a slow floor. Returns how far the wheel was turned (-1..1).
static func throttle(
	v: Ride, s: Spec, c: GameState.Controls, look: float, dt: float, scale: float
) -> float:
	var f := Vector2(cos(v.h), sin(v.h))
	var r := Vector2(-sin(v.h), cos(v.h))
	var vel := Vector2(v.vx, v.vy)
	var along := vel.dot(f)
	var across := vel.dot(r)
	var top := s.top * scale
	var gas := clampf(c.forward, -1.0, 1.0)
	v.gas = gas
	if gas > 0.0:
		if along < -.3:
			along = minf(0.0, along + s.brake * dt)
		elif along < top:
			along = minf(top, along + s.accel * gas * dt)
	elif gas < 0.0:
		if along > .3:
			along = maxf(0.0, along - s.brake * dt)
		elif along > -s.reverse:
			along = maxf(-s.reverse, along + s.accel * .6 * gas * dt)
	if gas == 0.0 or along > top:
		along = move_toward(along, 0.0, s.coast * dt)
	# Steering: STRAFE turns the wheel; otherwise it comes round to the look
	# (not while firing, so a shot to the side holds the course).
	var steer := clampf(c.strafe, -1.0, 1.0)
	if absf(steer) < .1:
		steer = 0.0 if c.fire else clampf(look * LOOK_STEER, -1.0, 1.0)
	var bite := clampf(along / maxf(.1, s.turn_full), -1.0, 1.0)
	if s.thrust_turn > 0.0:
		# A prop's wash on the rudder: it turns on the throttle, standing still too.
		bite = maxf(absf(bite), absf(gas) * s.thrust_turn) * (1.0 if along >= -.05 else -1.0)
	v.steer = steer
	across *= exp(-(s.handbrake if c.jump else s.grip) * dt)
	v.slide = absf(across)
	vel = f * along + r * across
	v.vx = vel.x
	v.vy = vel.y
	v.h = fposmod(v.h + steer * s.turn * bite * dt, TAU)
	return steer


## Moves `v` by its speed for one tick: a turn that does not fit is taken
## back, then the whole step, else each axis (a slide along the wall); a
## blocked axis bounces back. Returns the speed it struck with (0: nothing)
## and keeps where (`bump_x`, `bump_y`).
static func move(w: LevelData, v: Ride, s: Spec, dt: float, old_h: float) -> float:
	if v.h != old_h and is_nan(fits(w, s, v.x, v.y, v.h, v.z)):
		v.h = old_h
	var x := v.x
	var y := v.y
	var vx := v.vx
	var vy := v.vy
	var struck := 0.0
	var ahead := 1.0 if vx * cos(v.h) + vy * sin(v.h) >= 0.0 else -1.0
	var nx := x + vx * dt
	var ny := y + vy * dt
	var floor_z := fits(w, s, nx, ny, v.h, v.z)
	if is_nan(floor_z) and is_nan(fits(w, s, x, y, v.h, v.z)):
		# Wedged already (set down so, or shoved in by a blast): it may drive
		# out whichever way until it is clear again.
		floor_z = v.z
	elif is_nan(floor_z):
		var only_x := fits(w, s, nx, y, v.h, v.z)
		var only_y := fits(w, s, x, ny, v.h, v.z)
		if not is_nan(only_x) and absf(vx) > .01:
			struck = absf(vy)
			vy = -vy * BOUNCE
			ny = y
			floor_z = only_x
		elif not is_nan(only_y) and absf(vy) > .01:
			struck = absf(vx)
			vx = -vx * BOUNCE
			nx = x
			floor_z = only_y
		else:
			struck = Vector2(vx, vy).length()
			vx = -vx * BOUNCE
			vy = -vy * BOUNCE
			nx = x
			ny = y
			floor_z = fits(w, s, x, y, v.h, v.z)
			if is_nan(floor_z):
				floor_z = v.z
		v.bumps += 1
		v.bump_x = x + cos(v.h) * s.length * .5 * ahead
		v.bump_y = y + sin(v.h) * s.length * .5 * ahead
	v.x = nx
	v.y = ny
	v.vx = vx
	v.vy = vy
	if floor_z < v.z - .03:
		v.z = maxf(floor_z, v.z - FALL * dt)
	else:
		v.z = floor_z
	return struck


## Its speed (cells a second), and the speed along its heading.
static func speed(v: Ride) -> float:
	return Vector2(v.vx, v.vy).length()


static func along(v: Ride) -> float:
	return v.vx * cos(v.h) + v.vy * sin(v.h)


## The way out of the hull (padded by `pad`) for a point inside it, along the
## shorter side; Vector2.INF when the point is outside.
static func out_of(s: Spec, v: Ride, px: float, py: float, pad: float) -> Vector2:
	var dx := px - v.x
	var dy := py - v.y
	var fwd := dx * cos(v.h) + dy * sin(v.h)
	var side := -dx * sin(v.h) + dy * cos(v.h)
	var half_l := s.length * .5 + pad
	var half_w := s.width * .5 + pad
	if absf(fwd) >= half_l or absf(side) >= half_w:
		return Vector2.INF
	var out_l := half_l - absf(fwd)
	var out_w := half_w - absf(side)
	if out_w <= out_l:
		var k := out_w * (1.0 if side >= 0.0 else -1.0)
		return Vector2(-sin(v.h) * k, cos(v.h) * k)
	var k2 := out_l * (1.0 if fwd >= 0.0 else -1.0)
	return Vector2(cos(v.h) * k2, sin(v.h) * k2)


## How far (px, py) is from the hull's edge (0 inside).
static func gap(s: Spec, v: Ride, px: float, py: float) -> float:
	var dx := px - v.x
	var dy := py - v.y
	var fwd := absf(dx * cos(v.h) + dy * sin(v.h)) - s.length * .5
	var side := absf(-dx * sin(v.h) + dy * cos(v.h)) - s.width * .5
	return Vector2(maxf(0.0, fwd), maxf(0.0, side)).length()
