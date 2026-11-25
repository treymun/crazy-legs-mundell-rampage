## How pickups lying out catch the eye (pass 15, effects.cfg [pickup_glint]):
## they bob (game_view.gd), and ammo, food and scrap glint now and then, a
## two-frame star in the palette (fx_twinkle_0, _1: small, big, small) at
## the pickup's top, each on its own beat by where it lies. Guns not had yet
## shine their own way (gun_finder.gd), keys and the task items are lit
## (view_lights.gd). Looks only: worked out from the clock and the place each
## frame, nothing kept, no dice; drawn whatever QUALITY (no light needed).
## EASY ON THE EYES calms the bob and makes the glints rarer.
class_name PickupLooks
extends RefCounted

const STARS: Array[String] = ["fx_twinkle_0", "fx_twinkle_1"]

static var _version := -1
static var _every := 2.6
static var _step := .07
static var _size := .22
static var _reach := 16.0
static var _bob: Array = [.05, .018, 0.0]
static var _calm: Array = [1.0, 1.6, 2.4]


static func _read() -> void:
	if _version == Effects.version:
		return
	_version = Effects.version
	_every = Effects.num("pickup_glint", "every", 2.6)
	_step = Effects.num("pickup_glint", "step", .07)
	_size = Effects.num("pickup_glint", "size", .22)
	_reach = Effects.num("pickup_glint", "reach", 16.0)
	_bob = Effects.num("pickup_glint", "bob", [.05, .018, 0.0])
	_calm = Effects.num("pickup_glint", "calm", [1.0, 1.6, 2.4])


## How far a pickup bobs (cells) with EASY ON THE EYES at `motion` (0 full,
## 1 reduced, 2 still).
static func bob(motion: int) -> float:
	_read()
	var k := clampi(motion, 0, _bob.size() - 1)
	var cells: float = _bob[k]
	return cells


## Whether a pickup named `item` glints: ammo, food and scrap.
static func glints(item: String) -> bool:
	return item.begins_with("scrap_") or HUD.ITEMS.has(item) or GameState.AMMO.has(item)


## Where in its beat the glint of a pickup at x, y is at `clock`: 0, 1 or 0
## (the star small, big, small) for its three steps, -1 between glints.
static func frame_at(x: float, y: float, clock: float, motion: int) -> int:
	_read()
	var calm: float = _calm[clampi(motion, 0, _calm.size() - 1)]
	var every := maxf(_every * calm, _step * 4.0)
	# Each its own beat: a hash of where it lies, 0 to 1.
	var h := fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
	var beat := fposmod(clock + h * every, every)
	if beat >= _step * 3.0:
		return -1
	return 1 if beat >= _step and beat < _step * 2.0 else 0


## The glint of pickup `entry` lying at x, y, `top` the height of its top,
## added to `out` while it shows (within `reach` of `p`, the eye).
static func glint(
	g: GameState, entry: Array, x: float, y: float, top: float, p: Player, out: Array
) -> void:
	var frame := frame_at(x, y, g.clock, g.view.world_motion)
	if frame < 0 or absf(x - p.x) > _reach or absf(y - p.y) > _reach:
		return
	if not glints(str(entry[0])):
		return
	# On its upper corner toward the eye's right, a touch nearer the eye.
	var a := p.view_angle()
	var sx := x - sin(a) * .07 - cos(a) * .05
	var sy := y + cos(a) * .07 - sin(a) * .05
	var star := g.pooled(sx, sy, STARS[frame], _size, top - _size * .5)
	star.glow = true
	out.append(star)
