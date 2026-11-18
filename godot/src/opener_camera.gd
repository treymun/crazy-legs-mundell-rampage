## The chapter openers' camera (opener.gd, data/tuning/openers.json): each
## shot's path and the point it watches are smooth curves through the shot's
## keys (centripetal Catmull-Rom), flown at an even speed along their length
## that eases in and out at the shot's ends; the gaze runs a little ahead of
## the flight, the camera leans gently into its turns, and it is lifted
## smoothly over any ground or wall top it would skim. After the last shot it
## drifts to a stop while the boss is shown, and at the end it comes down
## behind the player and into his eyes, so play starts from the same picture.
##
## Looks only: it reads the level and the player and changes nothing.
## clear_at() is the rule tools/opener_check.gd holds every sample of every
## path to: never in a wall, a roof, a prop or the ground, nor skimming them.
class_name OpenerCamera
extends RefCounted

## How near the camera may come (cells): over the ground or a floor, over a
## wall's top, to a roof from above or below, to a wall's face, to a prop's
## middle (under its top).
const CLEAR_FLOOR := .55
const CLEAR_WALL := .4
const CLEAR_ROOF := .4
const NEAR_WALL := .3
const NEAR_PROP := .45
## Pictures standing on the ground too low to fly into (grass, puddles): a
## prop is one taller than this.
const PROP_LOW := .45
## A door's top (LevelData's door walls).
const DOOR_TOP := 1.85
## The lean into a turn: radians of roll per radian a second of turning, and
## the most (about 2.3 degrees: more makes a stair of the horizon at 320x200).
const BANK := .06
const BANK_MAX := .04
## How far ahead of the flight the gaze runs (a share of the shot's middle).
const LEAD := .35
## A shot's speed at its start and end, as a share of its cruise, and the
## share of the shot each ease takes. The first shot starts from nearly still.
const EASE_IN := .55
const EASE_OUT := .55
const EASE_FIRST := .2
const RAMP := .35
## Seconds the drift after the last shot takes to settle; the landing.
const DRIFT := 1.8
const LAND := 1.5
## Curve samples per key-to-key span (arc length), timing samples a shot,
## lift samples a shot.
const SAMPLES := 48
const TIMING := 256
const LIFTS := 96
## The pitch's limits (horizon pixels at the base focal), as the old camera's.
const PITCH_LOW := -120.0
const PITCH_HIGH := 90.0


## A smooth curve through its keys, sampled by length.
class Spline:
	extends RefCounted
	var keys := PackedVector3Array()
	var lengths := PackedFloat32Array()
	var params := PackedFloat32Array()
	var total := 0.0

	func _init(points: PackedVector3Array) -> void:
		keys = points
		var spans := maxi(1, keys.size() - 1)
		var prev := point(0.0)
		lengths.append(0.0)
		params.append(0.0)
		for k in range(1, spans * SAMPLES + 1):
			var tau := float(k) / SAMPLES
			var p := point(tau)
			total += p.distance_to(prev)
			prev = p
			lengths.append(total)
			params.append(tau)

	## The point at `tau` (0 at the first key, 1 at the next, and so on).
	func point(tau: float) -> Vector3:
		var n := keys.size()
		if n == 1:
			return keys[0]
		var i := clampi(floori(tau), 0, n - 2)
		var u := clampf(tau - i, 0.0, 1.0)
		var p1 := keys[i]
		var p2 := keys[i + 1]
		var p0 := keys[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := keys[i + 2] if i + 2 < n else p2 * 2.0 - p1
		return OpenerCamera.centripetal(p0, p1, p2, p3, u)

	## The point a share `s` (0 to 1) of the way along it by length.
	func at(s: float) -> Vector3:
		if total <= 1e-5:
			return keys[0]
		var want := clampf(s, 0.0, 1.0) * total
		var lo := 0
		var hi := lengths.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if lengths[mid] <= want:
				lo = mid
			else:
				hi = mid
		var span := lengths[hi] - lengths[lo]
		var k := (want - lengths[lo]) / span if span > 1e-9 else 0.0
		return point(lerpf(params[lo], params[hi], k))


## One shot: its time, its two curves, its timing and its lift.
class Shot:
	extends RefCounted
	var start := 0.0
	var secs := 3.0
	var path: Spline
	var look: Spline
	var lead := LEAD
	## The share of the path flown at each of TIMING + 1 even moments.
	var timing := PackedFloat32Array()
	## How far the path is lifted at each of LIFTS + 1 even shares of its length.
	var lift := PackedFloat32Array()

	## The share of the path flown a share `u` of the way through the shot.
	func flown(u: float) -> float:
		var k := clampf(u, 0.0, 1.0) * TIMING
		var i := mini(floori(k), TIMING - 1)
		return lerpf(timing[i], timing[i + 1], k - i)

	func lifted(s: float) -> float:
		var k := clampf(s, 0.0, 1.0) * LIFTS
		var i := mini(floori(k), LIFTS - 1)
		return lerpf(lift[i], lift[i + 1], k - i)

	## Where the camera is and what it watches, `u` of the way through.
	func place(u: float) -> Array[Vector3]:
		var s := flown(u)
		var pos := path.at(s)
		pos.z += lifted(s)
		var ahead := s + lead * s * (1.0 - s)
		return [pos, look.at(ahead)]


var shots: Array[Shot] = []
var shots_end := 0.0
## The landing: when it starts, where from, and the player's eye it ends in.
var land_at := INF
var land_from := Vector3.ZERO
var land_eye: Dictionary = {}


## The shots of an opener entry laid end to end, lifted clear of `world`
## (its props and pictures standing, `props` and `art` for their size).
func build(entries: Array, world: LevelData, props: Array, art: Assets) -> void:
	prepare(world, props, art)
	shots.clear()
	var t := 0.0
	for n in entries.size():
		var e: Dictionary = entries[n]
		var shot := Shot.new()
		shot.start = t
		var secs: float = e.get("secs", 3.0)
		shot.secs = maxf(.2, secs)
		shot.path = Spline.new(keys_of(e, "path", "from", "to"))
		shot.look = Spline.new(keys_of(e, "look", "look", "look_to"))
		shot.lead = e.get("lead", LEAD)
		var ease: Array = e.get("ease", [EASE_FIRST if n == 0 else EASE_IN, EASE_OUT])
		var ease_in: float = ease[0]
		var ease_out: float = ease[1]
		shot.timing = timing_of(ease_in, ease_out)
		shot.lift = _lift_of(shot.path, world)
		shots.append(shot)
		t += shot.secs
	shots_end = t
	land_at = INF


## A shot's keys: its list `key` ([[x, y, z], ...]), or the older pair `one`, `two`.
static func keys_of(e: Dictionary, key: String, one: String, two: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var listed: Variant = e.get(key, [])
	var many: Array = listed if listed is Array else []
	if not many.is_empty() and many[0] is Array:
		for v: Variant in many:
			out.append(ChapterOpener.v3(v))
		return out
	var first: Variant = e.get(one, [0, 0, 2])
	out.append(ChapterOpener.v3(first))
	out.append(ChapterOpener.v3(e.get(two, first)))
	return out


## The share of the path flown at TIMING + 1 even moments, for a speed that
## eases from `a` (a share of the cruise) up and back down to `b`.
static func timing_of(a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	var sum := 0.0
	var prev := _speed(0.0, a, b)
	for k in range(1, TIMING + 1):
		var v := _speed(float(k) / TIMING, a, b)
		sum += (prev + v) * .5
		prev = v
		out.append(sum)
	for k in out.size():
		out[k] /= maxf(sum, 1e-6)
	return out


static func _speed(u: float, a: float, b: float) -> float:
	var v := 1.0
	if u < RAMP:
		v = lerpf(a, 1.0, smoothstep(0.0, 1.0, u / RAMP))
	if u > 1.0 - RAMP:
		v = minf(v, lerpf(b, 1.0, smoothstep(0.0, 1.0, (1.0 - u) / RAMP)))
	return v


## How far to lift the path at each share of its length to keep it over the
## ground and the wall tops, widened and smoothed so the rise is gentle.
static func _lift_of(path: Spline, world: LevelData) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for k in LIFTS + 1:
		var p := path.at(float(k) / LIFTS)
		raw.append(maxf(0.0, lowest(world, p.x, p.y, p.z) - p.z))
	var wide := PackedFloat32Array()
	for k in raw.size():
		var most := 0.0
		for j in range(maxi(0, k - 9), mini(raw.size(), k + 10)):
			most = maxf(most, raw[j])
		wide.append(most)
	for _pass in 8:
		var soft := wide.duplicate()
		for k in range(1, wide.size() - 1):
			soft[k] = (wide[k - 1] + wide[k] * 2.0 + wide[k + 1]) * .25
		wide = soft
	return wide


## The lowest the camera may fly at (x, y) from height z: over the ground or
## the floor under it, and over a wall's top where the cell is wall.
static func lowest(world: LevelData, x: float, y: float, z: float) -> float:
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return z
	var c := world.cell(x, y)
	var low := world.floor_under(x, y, z) + CLEAR_FLOOR
	if world.solid[c] >= 0:
		low = maxf(low, world.wall_height[c] + CLEAR_WALL)
	return low


# ------------------------------------------------------------------ the eye


## The landing: from a little behind and above the player's eye, clear of the
## level, down into it over the opener's last LAND seconds.
func land(at_time: float, world: LevelData, eye: Dictionary) -> void:
	land_at = at_time
	land_eye = eye
	var to := eye_point(eye)
	var angle: float = eye["view_angle"]
	var ahead := Vector3(cos(angle), sin(angle), 0.0)
	var side := Vector3(-sin(angle), cos(angle), 0.0)
	land_from = to + Vector3(0.0, 0.0, .3) - ahead * .5
	for back: float in [2.4, 1.8, 1.2, .8]:
		for up: float in [.9, .6, .35]:
			for aside: float in [0.0, .7, -.7]:
				var from := to - ahead * back + side * aside + Vector3(0.0, 0.0, up)
				if _clear_line(world, from, to):
					land_from = from
					return


## Whether a straight flight from `a` into the eye at `b` keeps clear (the
## last part, the player's own spot, only of walls, roofs and the ground).
static func _clear_line(world: LevelData, a: Vector3, b: Vector3) -> bool:
	for k in 25:
		var s := float(k) / 24.0
		var p := a.lerp(b, s)
		if clear_at(world, p.x, p.y, p.z, s < .8) != "":
			return false
	return true


## An eye's place as a point.
static func eye_point(eye: Dictionary) -> Vector3:
	var x: float = eye["x"]
	var y: float = eye["y"]
	var z: float = eye["eye"]
	return Vector3(x, y, z)


## Where the camera is and what it watches at `t` (no lean).
func place(t: float) -> Array[Vector3]:
	if t >= land_at:
		var u := clampf((t - land_at) / LAND, 0.0, 1.0)
		var to := eye_point(land_eye)
		var angle: float = land_eye["view_angle"]
		var s := _landing(u)
		var pos := land_from.lerp(to, s)
		return [pos, Vector3(to.x + cos(angle) * 8.0, to.y + sin(angle) * 8.0, to.z)]
	if shots.is_empty():
		return [Vector3.ZERO, Vector3(1, 0, 0)]
	var last := shots[shots.size() - 1]
	if t >= shots_end:
		# The boss's part: on along the last path's heading, slowing to a stop.
		var end := last.place(1.0)
		var before := last.place(1.0 - .01 / last.secs)
		var velocity := (end[0] - before[0]) / .01
		var since := minf(t - shots_end, DRIFT)
		var travel := velocity * (since - since * since / (2.0 * DRIFT))
		return [end[0] + travel, end[1] + travel]
	var i := 0
	for k in shots.size():
		if t >= shots[k].start:
			i = k
	var shot := shots[i]
	return shot.place((t - shot.start) / shot.secs)


## The landing's share of the way at `u`: in at the speed it starts with, and
## settled to a stop at the eye.
static func _landing(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u * .25)


## The span of the opener `t` is in, so a turn is never measured across a cut.
func span(t: float) -> Vector2:
	var a := 0.0
	var b := INF
	for shot in shots:
		if shot.start <= t:
			a = shot.start
		elif shot.start < b:
			b = shot.start
	if t >= land_at:
		return Vector2(land_at, INF)
	return Vector2(a, minf(b, land_at))


## The eye the view draws from at `t`: place(), its heading and horizon, and
## a lean into the turn.
func eye(t: float, focal: float) -> Dictionary:
	var at := place(t)
	var pos: Vector3 = at[0]
	var look: Vector3 = at[1]
	var flat := Vector2(look.x - pos.x, look.y - pos.y)
	var reach := maxf(.5, flat.length())
	var pitch := clampf(-focal * (pos.z - look.z) / reach, PITCH_LOW, PITCH_HIGH)
	var heading := atan2(flat.y, flat.x)
	if t >= land_at and not land_eye.is_empty():
		var u := clampf((t - land_at) / LAND, 0.0, 1.0)
		heading = land_eye["view_angle"]
		var final_pitch: float = land_eye["pitch"]
		pitch = lerpf(pitch, final_pitch, smoothstep(.55, 1.0, u))
	var out := {
		"x": pos.x,
		"y": pos.y,
		"eye": pos.z,
		"view_angle": heading,
		"pitch": pitch,
		"bob": 0.0,
		"sway": 0.0,
		"roll": clampf(turn_rate(t) * BANK, -BANK_MAX, BANK_MAX),
	}
	if not land_eye.is_empty():
		# The player is not in the story till the camera comes down behind him,
		# and is left out again as it reaches his eyes.
		var mine := eye_point(land_eye)
		var near := Vector2(pos.x - mine.x, pos.y - mine.y).length()
		out["hide_player"] = t < land_at or near < 1.2
	return out


## How fast the camera turns at `t` (rad/s, + to the right), within its span.
func turn_rate(t: float) -> float:
	var s := span(t)
	var h := 1.0 / 60.0
	var a := maxf(s.x, t - h)
	var b := minf(s.y - .0001, t + h)
	if b <= a:
		return 0.0
	return angle_difference(heading_at(a), heading_at(b)) / (b - a)


func heading_at(t: float) -> float:
	if t >= land_at and not land_eye.is_empty():
		return land_eye["view_angle"]
	var at := place(t)
	var pos: Vector3 = at[0]
	var look: Vector3 = at[1]
	return atan2(look.y - pos.y, look.x - pos.x)


# ------------------------------------------------------------------ the rule


## "" when the camera may be at (x, y, z) in `world`, else what it hits. With
## `near` false only walls' insides, roofs and the ground count (the player's
## own spot at the landing's end).
static func clear_at(world: LevelData, x: float, y: float, z: float, near := true) -> String:
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return "off the map"
	var c := world.cell(x, y)
	if z < world.floor_under(x, y, z) + (CLEAR_FLOOR if near else .3):
		return "at or under the ground"
	if world.solid[c] >= 0 and z < world.wall_height[c] + CLEAR_WALL:
		return "inside a wall"
	var roof := world.roof[c]
	if roof != 0.0 and absf(z - roof) < CLEAR_ROOF:
		return "through a roof"
	if world.geo != null and world.geo.solid_point(x, y, z, .2, false):
		return "inside a deck or a wall"
	if not near:
		return ""
	for door: LevelData.Door in world.near_doors.get(Vector2i(floori(x), floori(y)), []):
		if z < DOOR_TOP + CLEAR_WALL and door.blocks(x, y, NEAR_WALL):
			return "at a door (%d, %d)" % [door.x, door.y]
	var hit := _near_wall(world, x, y, z)
	if hit != "":
		return hit
	return _near_prop(x, y, z)


static var _indexed: LevelData = null
static var _indexed_version := -1
static var _wall_cells := {}
static var _thing_cells := {}


## The walls and the things standing (props and pictures, each as
## [x, y, bottom, top, reach]) by the cells they come near, made once a level.
## A thing's reach is half its picture's width at its height, at least
## NEAR_PROP: a tree's crown, not just its trunk.
static func prepare(world: LevelData, props: Array, art: Assets) -> void:
	if _indexed == world and _indexed_version == world.walls_version:
		return
	_indexed = world
	_indexed_version = world.walls_version
	_wall_cells = {}
	_thing_cells = {}
	var reach := NEAR_WALL + .05
	for i in world.wall_count:
		var k := i * LevelData.WALL_STRIDE
		var x0 := minf(world.walls[k], world.walls[k + 2]) - reach
		var x1 := maxf(world.walls[k], world.walls[k + 2]) + reach
		var y0 := minf(world.walls[k + 1], world.walls[k + 3]) - reach
		var y1 := maxf(world.walls[k + 1], world.walls[k + 3]) + reach
		for cy in range(floori(y0), floori(y1) + 1):
			for cx in range(floori(x0), floori(x1) + 1):
				var key := Vector2i(cx, cy)
				var list: PackedInt32Array = _wall_cells.get(key, PackedInt32Array())
				list.append(i)
				_wall_cells[key] = list
	for b: LevelData.Billboard in world.billboards:
		if not b.hidden and b.height > PROP_LOW and is_nan(b.plane):
			_add_thing(art, b.image, b.x, b.y, b.z, b.height)
	for spr: Variant in props:
		var s: View.Sprite = spr
		if s.height > PROP_LOW and is_nan(s.plane):
			_add_thing(art, s.image, s.x, s.y, s.z, s.height)


static func _add_thing(
	art: Assets, image: String, x: float, y: float, z: float, tall: float
) -> void:
	var wide := tall
	var picture: Variant = art.art_index.get(image) if art != null else null
	if picture is Dictionary:
		var size: Dictionary = picture
		var w: float = size.get("w", 1)
		var h: float = size.get("h", 1)
		wide = tall * w / maxf(1.0, h)
	var reach := maxf(NEAR_PROP, wide * .5)
	var row := PackedFloat32Array([x, y, z, z + tall, reach])
	for cy in range(floori(y - reach), floori(y + reach) + 1):
		for cx in range(floori(x - reach), floori(x + reach) + 1):
			var key := Vector2i(cx, cy)
			var list: Array = _thing_cells.get(key, [])
			list.append(row)
			_thing_cells[key] = list


static func _near_wall(world: LevelData, x: float, y: float, z: float) -> String:
	if _indexed != world:
		prepare(world, [], null)
	var here := Vector2(x, y)
	for i: int in _wall_cells.get(Vector2i(floori(x), floori(y)), PackedInt32Array()):
		var k := i * LevelData.WALL_STRIDE
		var bottom := world.walls[k + 6]
		var top := world.walls[k + 7]
		if z < bottom - CLEAR_WALL or z > top + CLEAR_WALL:
			continue
		var a := Vector2(world.walls[k], world.walls[k + 1])
		var b := Vector2(world.walls[k + 2], world.walls[k + 3])
		if Geometry2D.get_closest_point_to_segment(here, a, b).distance_to(here) < NEAR_WALL:
			return "skims a wall (%.1f, %.1f)" % [a.x, a.y]
	return ""


static func _near_prop(x: float, y: float, z: float) -> String:
	for row: PackedFloat32Array in _thing_cells.get(Vector2i(floori(x), floori(y)), []):
		if z > row[3] + CLEAR_WALL or z < row[2] - CLEAR_WALL:
			continue
		if Vector2(row[0] - x, row[1] - y).length() < row[4]:
			return "inside a prop (%.1f, %.1f)" % [row[0], row[1]]
	return ""


## A point of the centripetal Catmull-Rom curve between p1 and p2 (p0 and
## p3 the keys either side), `u` of the way (Barry and Goldman's form).
static func centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t1 := sqrt(maxf(p0.distance_to(p1), 1e-4))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-4))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-4))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / t1) + p1 * (t / t1)
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / t2) + a2 * (t / t2)
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
