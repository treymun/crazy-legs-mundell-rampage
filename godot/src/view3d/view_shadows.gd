## SHADOWS (VIEW page, `View.shadows`; off on QUALITY LOW and without LIGHTS
## AND GLOW): what moves throws a chunky shadow on the level's floors and
## walls from the strong lights (lamps, lanterns, fires, muzzle flashes,
## blasts), and the sky lays a soft blob on the floor under it.
##
## Worked out each frame from what the view draws, nothing kept: the actors
## (enemies, other players, bosses; a dead body lies along its heading, its
## ragdoll's length), this machine's player, the props on the move (thrown,
## carried, a boss arena's wreck flung), the vehicles and the nearest wreck
## pieces become bodies: a segment with a radius. The nearest `MOST_BODIES` to
## the eye are kept; each with a strong light near it makes a pair (the
## `MOST_PAIRS` that matter most, by the light's strength there and the
## body's distance from the eye), which `view_light.gdshaderinc` tests each
## floor and wall block against (`shadow_cover`, on a grid of SHADOW_GRID
## blocks a cell, the soft edge dithered). A body never shadows a light it
## stands in or carries (its own muzzle flash, the fire it burns in). Looks
## only.
class_name ViewShadows
extends RefCounted

const Vehicles := preload("res://src/features/vehicles.gd")

## At most this many pairs and blobs (the shaders' arrays).
const MOST_PAIRS := 16
const MOST_BLOBS := 12
## At most this many bodies, the nearest to the eye.
const MOST_BODIES := 12
## Bodies farther from the eye than this throw nothing.
const REACH := 22.0
## A light weaker than this (strength times radius) throws no shadows.
const STRONG := .6
## A light this close to a body's segment (past its radius) is its own.
const OWN_LIGHT := .45
## The wreck pieces counted (the nearest), of the bodies.
const MOST_PIECES := 4

## The pairs and blobs for the shaders (always full size; *_count are used).
var pair_a := PackedVector4Array()
var pair_b := PackedVector4Array()
var blobs := PackedVector4Array()
var pair_count := 0
var blob_count := 0
## This frame's bodies: [a: Vector3, b: Vector3, radius: float, from eye].
var _bodies: Array = []


func _init() -> void:
	pair_a.resize(MOST_PAIRS)
	pair_b.resize(MOST_PAIRS)
	blobs.resize(MOST_BLOBS)


## Gather this frame's bodies (map axes) and their blobs: `acting` the
## actors' sprites, `modelled` the props', `wrecked` the wreck pieces'.
func collect(
	game: Game, acting: Array, modelled: Array, wrecked: Array, eye: Vector3, models: PropModels
) -> void:
	_bodies.clear()
	blob_count = 0
	pair_count = 0
	if not View.shadows or not Effects.enabled:
		return
	var level: LevelData = game.level
	for s: View.Sprite in acting:
		var e := s.who as Enemy
		var h := clampf(s.height, .3, 3.5)
		var at := Vector3(s.x, s.y, s.z)
		if e != null and not e.alive:
			# Lying where it fell, along the way it faces, a little off the floor.
			var r := h * .13
			var along := Vector3(cos(e.angle), sin(e.angle), 0.0) * h * .36
			var low := at + Vector3(0.0, 0.0, r * .8)
			_body(low - along, low + along, r, eye, s.z, true)
		else:
			var r := clampf(h * .19, .12, .7)
			_body(at + Vector3(0, 0, r * .6), at + Vector3(0, 0, h - r), r, eye, s.z, false)
	_player(game, eye)
	_vehicles(game, modelled, eye)
	for s: View.Sprite in modelled:
		if s.who == null and s.track == "":
			continue
		var name := models.name_of(s.image)
		if not models.sizes.has(name):
			continue
		var dims: Array = models.sizes[name]
		var size := models.scale_of(name, s.height)
		var wide: float = dims[0]
		var deep: float = dims[1]
		var tall: float = dims[2]
		var r := clampf(maxf(wide, deep) * size * .4, .08, 1.0)
		var middle := Vector3(s.x, s.y, s.z + tall * size * .5)
		var half := maxf(0.0, tall * size * .5 - r)
		var ground := _floor(level, s.x, s.y, s.z)
		_body(middle - Vector3(0, 0, half), middle + Vector3(0, 0, half), r, eye, ground, false)
	# The nearest MOST_PIECES, nearest first: picked out, not the whole list
	# sorted each frame (pass 13; a busy break draws fifty).
	var near := PackedFloat64Array()
	var near_s: Array[View.Sprite] = []
	for s: View.Sprite in wrecked:
		var d := Vector3(s.x, s.y, s.z).distance_to(eye)
		if d >= REACH:
			continue
		var k := near.size()
		while k > 0 and near[k - 1] > d:
			k -= 1
		if k >= MOST_PIECES:
			continue
		near.insert(k, d)
		near_s.insert(k, s)
		if near.size() > MOST_PIECES:
			near.resize(MOST_PIECES)
			near_s.resize(MOST_PIECES)
	for s: View.Sprite in near_s:
		var at := Vector3(s.x, s.y, s.z)
		_body(at, at, .22, eye, _floor(level, s.x, s.y, s.z), false)
	# Nearest the eye first: sorted by [distance, place] in the engine's own
	# sort, not a script call each comparison (pass 13: thirty-odd County
	# Run hands).
	var keyed: Array = []
	for i in _bodies.size():
		var row: Array = _bodies[i]
		keyed.append([row[3], i])
	keyed.sort()
	var sorted: Array = []
	for key: Array in keyed.slice(0, MOST_BODIES):
		var i: int = key[1]
		sorted.append(_bodies[i])
	_bodies = sorted
	_blobs()


## Sorts rows by their number at `k`, smallest first.
static func nearer(m: Array, n: Array, k: int) -> bool:
	var dm: float = m[k]
	var dn: float = n[k]
	return dm < dn


## This machine's player, unless the eye is not theirs (photo mode draws
## their body as a sprite of its own).
func _player(game: Game, eye: Vector3) -> void:
	var p := game.local_player
	if p == null or not game.eye_override.is_empty() or p.health <= 0:
		return
	var feet := p.floor_z + p.air
	var top := maxf(feet + .5, p.eye + .08)
	_body(Vector3(p.x, p.y, feet + .14), Vector3(p.x, p.y, top - .2), .2, eye, feet, false)


## Each vehicle drawn (its sprite among `modelled`: a body turned by its
## plane) as a body along its heading, its width round.
func _vehicles(game: Game, modelled: Array, eye: Vector3) -> void:
	var feature: Vehicles = game.features.get("vehicles")
	if feature == null or feature.rides.is_empty():
		return
	for item: Variant in feature.rides:
		var v: VehicleDrive.Ride = item
		var drawn := false
		for shown: Variant in modelled:
			var s: View.Sprite = shown
			drawn = drawn or (s.body and absf(s.x - v.x) < .05 and absf(s.y - v.y) < .05)
		if not drawn:
			continue
		var spec := VehicleDrive.spec(v.kind)
		var r := spec.width * .5
		var half := maxf(0.0, spec.length * .5 - r)
		var along := Vector3(cos(v.h), sin(v.h), 0.0) * half
		var middle := Vector3(v.x, v.y, v.z + maxf(r, spec.tall * .5))
		_body(middle - along, middle + along, r, eye, v.z, true)


## A body from a to b, radius r, standing on the floor at `ground`; `long`:
## it lies along a to b (a blob at each end).
func _body(a: Vector3, b: Vector3, r: float, eye: Vector3, ground: float, long: bool) -> void:
	var middle := (a + b) * .5
	var d := middle.distance_to(eye)
	if d > REACH:
		return
	_bodies.append([a, b, r, d, ground, long])


## The floor under a thing in the air (the cell's ground; decks are not sought).
static func _floor(level: LevelData, x: float, y: float, z: float) -> float:
	if level.width <= 0 or level.height <= 0:
		return z
	var c := level.cell(clampf(x, 0.0, level.width - .01), clampf(y, 0.0, level.height - .01))
	return minf(z, level.ground[c])


## The sky's blob under each body, smaller and gone the higher it is.
func _blobs() -> void:
	for body: Array in _bodies:
		var a: Vector3 = body[0]
		var b: Vector3 = body[1]
		var r: float = body[2]
		var ground: float = body[4]
		var long: bool = body[5]
		var low := minf(a.z, b.z) - r
		var lift := clampf((low - ground) / 2.5, 0.0, .8)
		if lift >= .8:
			continue
		var ends: Array = [a, b] if long else [(a + b) * .5]
		for at: Vector3 in ends:
			if blob_count >= MOST_BLOBS:
				return
			var size := r * (1.4 if long else 2.2) * (1.0 - lift)
			blobs[blob_count] = Vector4(at.x, at.y, ground, maxf(size, .06))
			blob_count += 1


## The pairs for this frame's lights (Game.effect_lights(), in the order the
## view hands them to the shaders): each body with a strong light near it.
func pair(found: Array) -> void:
	pair_count = 0
	if _bodies.is_empty():
		return
	var candidates: Array = []
	for i in mini(found.size(), Effects.MAX_LIGHTS):
		var l: Array = found[i]
		var lx: float = l[0]
		var ly: float = l[1]
		var lz: float = l[2]
		var reach: float = l[3]
		var power: float = l[5]
		if power * reach < STRONG:
			continue
		var at := Vector3(lx, ly, lz)
		for body: Array in _bodies:
			var a: Vector3 = body[0]
			var b: Vector3 = body[1]
			var r: float = body[2]
			var d := at.distance_to(Geometry3D.get_closest_point_to_segment(at, a, b))
			if d < r + OWN_LIGHT or d > reach * .9:
				continue
			var eye_d: float = body[3]
			var score := power * (1.0 - d / reach) / (1.0 + eye_d * .08)
			candidates.append([score, i, body])
	candidates.sort_custom(func(m: Array, n: Array) -> bool: return nearer(n, m, 0))
	for c: Array in candidates:
		if pair_count >= MOST_PAIRS:
			break
		var light: int = c[1]
		var body: Array = c[2]
		var a: Vector3 = body[0]
		var b: Vector3 = body[1]
		var r: float = body[2]
		pair_a[pair_count] = Vector4(a.x, a.y, a.z, r)
		pair_b[pair_count] = Vector4(b.x, b.y, b.z, light)
		pair_count += 1
