## The fine stuff a break throws with its real pieces (features/wreckage.gd):
## splinters and chips off wood, straw and flakes off hay, shards and glints
## off glass and clay, bright slivers off tin, crumbs of foam, all small
## hard-edged slabs of the thing's own colours, drawn in one go by the wreck
## layer (view3d/wreck_layer.gd, a MultiMesh) instead of tumbling as real
## pieces. Each is a point with a spin: it falls, bounces off the floor under
## it (asked once where it lands, again only when it has gone half a cell),
## slides to a stop, lies a while and shrinks away. Walls stop it when it
## crosses into a cell (a wall cell sends it back). Straw and foam drift
## down slowly. At most `most` at once (the oldest go first; fewer on a
## phone or the LOW tier: breakables.cfg [pieces] fine_most*).
##
## Looks only: the caller's own dice, nothing carried or saved.
class_name WreckDebris
extends RefCounted

const GRAVITY := 9.4
## Bounce off the floor (light stuff less), friction sliding on it.
const BOUNCE := .3
const SLIDE := 6.0
## Shrinking away at the end of its life (seconds).
const SHRINK := .4
## Asked its floor again once it has gone this far from where it last asked.
const REASK := .5


## One bit.
class Bit:
	var p := Vector3.ZERO
	var v := Vector3.ZERO
	## Its slab: long, wide, thin (cells), and its colour (0..1, the palette's).
	var size := Vector3(.05, .01, .01)
	var colour := Color.WHITE
	## Spinning about `axis` at `spin` radians a second, turned `angle` now;
	## lying, turned `yaw` about up.
	var axis := Vector3(0, 0, 1)
	var spin := 0.0
	var angle := 0.0
	var yaw := 0.0
	var age := 0.0
	var life := 6.0
	## Drag in the air (straw and foam drift), how it bounces.
	var drag := .2
	var bounce := BOUNCE
	var floor_z := -INF
	var asked := Vector2.INF
	var resting := false
	## The cell it was drawn in and its light there (the wreck layer's).
	var cell := -1
	var tone := Color(1, 1, 1, 1)
	## Drawn lying still already (the view need not write it again).
	var drawn := false


var bits: Array = []
var most := 120
## Counts up whenever any bit moved, shrank, came or went (the view draws
## them again only then).
var version := 0
## Counts up whenever a bit came or went (the view writes them all again).
var layout := 0


## Add a bit; past `most` the oldest goes.
func add(bit: Bit) -> void:
	version += 1
	layout += 1
	bits.append(bit)
	if bits.size() > most:
		bits.pop_front()


func moving() -> bool:
	for b: Bit in bits:
		if not b.resting:
			return true
	return false


## Step every bit dt seconds over `world`.
func step(world: LevelData, dt: float) -> void:
	var k := bits.size() - 1
	while k >= 0:
		var b: Bit = bits[k]
		b.age += dt
		if b.age >= b.life + SHRINK:
			bits.remove_at(k)
			version += 1
			layout += 1
			k -= 1
			continue
		if not b.resting:
			_move(world, b, dt)
			version += 1
		elif b.age >= b.life:
			version += 1
		k -= 1


func _move(world: LevelData, b: Bit, dt: float) -> void:
	var was := b.p
	b.v.z -= GRAVITY * dt * (.35 if b.drag > 1.0 else 1.0)
	var keep := maxf(0.0, 1.0 - b.drag * dt)
	b.v.x *= keep
	b.v.y *= keep
	if b.drag > 1.0:
		b.v.z = maxf(b.v.z, -1.2)
	b.p += b.v * dt
	b.angle += b.spin * dt
	if int(b.p.x) != int(was.x) or int(b.p.y) != int(was.y):
		if world.blocked(b.p.x, b.p.y, .01, b.p.z):
			b.p.x = was.x
			b.p.y = was.y
			b.v.x *= -.3
			b.v.y *= -.3
	var here := Vector2(b.p.x, b.p.y)
	if b.asked == Vector2.INF or here.distance_to(b.asked) > REASK:
		b.asked = here
		b.floor_z = Tumble.floor_at(world, b.p.x, b.p.y, maxf(was.z, b.p.z) + .05)
	if b.p.z > b.floor_z:
		return
	b.p.z = b.floor_z
	if b.v.z < -1.0:
		b.v.z = -b.v.z * b.bounce
		b.spin *= .5
		b.v.x *= .7
		b.v.y *= .7
		return
	b.v.z = 0.0
	var slow := maxf(0.0, 1.0 - SLIDE * dt)
	b.v.x *= slow
	b.v.y *= slow
	b.spin *= slow
	if Vector2(b.v.x, b.v.y).length() < .08:
		b.resting = true
		b.yaw = b.angle
		b.v = Vector3.ZERO


## How a bit is drawn: its turn and size (scaled down as it shrinks away),
## in map axes.
static func turn_of(b: Bit) -> Basis:
	var k := clampf((b.life + SHRINK - b.age) / SHRINK, 0.0, 1.0)
	var turn := Basis(Vector3(0, 0, 1), b.yaw) if b.resting else Basis(b.axis, b.angle)
	return turn * Basis.from_scale(b.size * k)
