## Where a kit piece stands: its own frame (local x across 0..w, local y
## across 0..d, its front on the local south side) mirrored, turned and moved
## onto the map. Every point, rectangle, direction, slope and cut line a piece
## makes goes through here, so a turned or mirrored piece is the same piece.
##
## mirror flips local x first; turn is quarter turns clockwise seen from
## above (0: the front faces south, 1 west, 2 north, 3 east); the turned
## footprint's north-west corner lands on (x, y).
class_name KitFrame
extends RefCounted

const DIRS := {
	"n": Vector2(0, -1),
	"e": Vector2(1, 0),
	"s": Vector2(0, 1),
	"w": Vector2(-1, 0),
}
## The side a piece's front faces -> its turn.
const FACES := {"s": 0, "w": 1, "n": 2, "e": 3}

var origin := Vector2.ZERO
var turn := 0
var mirror := false
## The piece's own size (local, before turning).
var w := 1.0
var d := 1.0


static func make(at: Vector2, size: Vector2, quarter: int, flip: bool) -> KitFrame:
	var f := KitFrame.new()
	f.origin = at
	f.w = size.x
	f.d = size.y
	f.turn = posmod(quarter, 4)
	f.mirror = flip
	return f


## The footprint on the map: [x0, y0, x1, y1].
func footprint() -> Rect2:
	var size := Vector2(w, d) if turn % 2 == 0 else Vector2(d, w)
	return Rect2(origin, size)


## A local point on the map.
func p(local: Vector2) -> Vector2:
	var x := w - local.x if mirror else local.x
	var y := local.y
	match turn:
		1:
			return origin + Vector2(d - y, x)
		2:
			return origin + Vector2(w - x, d - y)
		3:
			return origin + Vector2(y, w - x)
	return origin + Vector2(x, y)


## A local direction or slope on the map (no move).
func v(local: Vector2) -> Vector2:
	var x := -local.x if mirror else local.x
	var y := local.y
	match turn:
		1:
			return Vector2(-y, x)
		2:
			return Vector2(-x, -y)
		3:
			return Vector2(y, -x)
	return Vector2(x, y)


## A local rectangle on the map.
func rect(local: Rect2) -> Rect2:
	var a := p(local.position)
	var b := p(local.end)
	return Rect2(a.min(b), (a - b).abs())


## A local compass side (n, e, s, w) on the map.
func dir(local: String) -> String:
	var way: Vector2 = DIRS.get(local, Vector2.ZERO)
	var out := v(way)
	for key: String in DIRS:
		var test: Vector2 = DIRS[key]
		if test.is_equal_approx(out):
			return key
	return local


## A local cut line [nx, ny, c] (inside where nx * x + ny * y <= c) on the map.
func cut(local: Vector3) -> Vector3:
	var n := v(Vector2(local.x, local.y))
	var t := p(Vector2.ZERO)
	return Vector3(n.x, n.y, local.z + n.dot(t))


## A local heading (radians, 0 east, PI / 2 south) on the map.
func angle(local: float) -> float:
	var out := v(Vector2.from_angle(local))
	return out.angle()
