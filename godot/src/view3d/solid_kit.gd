## The 3D view's newer solid bodies (SolidLayer3D draws them like the bowling
## pins): the firing range's midway games (a horseshoe and its stake, the
## skee-ball cabinet and its balls, milk bottles and a softball, the dunk
## tank, its seat and bullseye), the fair gallery's tin cans, rails, shelves
## and prizes (a straw hat, a beer), and the trophy shack's plinths and
## plaques. Each is built here from code the first time it is seen, in cells
## and Godot's axes (y up, z the map's y), from the same numbers the play
## uses (range_games_shape.gd).
##
## Their faces carry their own colour, not one of solid.gdshader's PAINT
## materials: UV.x is MATTE or SHINY (below zero) and UV.y the colour packed
## as r * 65536 + g * 256 + b, which a float holds exactly.
class_name SolidKit
extends RefCounted

const S := preload("res://src/range_games_shape.gd")
## UV.x of a face coloured by its own UV.y (solid.gdshader).
const MATTE := -1.0
const SHINY := -2.0

## The kinds made here.
const KINDS := [
	"horseshoe",
	"stake",
	"softball",
	"skee_ball",
	"skee_lane",
	"bottle",
	"beer",
	"hat",
	"tin_can",
	"rail",
	"shelf",
	"plinth",
	"plaque",
	"dunk_tank",
	"dunk_seat",
	"dunk_target",
	"bell",
]

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()


## The mesh of `kind`, or null when it is none of these.
static func mesh_of(kind: String) -> ArrayMesh:
	if not KINDS.has(kind):
		return null
	var k := SolidKit.new()
	k.call("_" + kind)
	return k.mesh()


## A colour packed for UV.y.
static func rgb(r: int, g: int, b: int) -> float:
	return float(r * 65536 + g * 256 + b)


func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# ------------------------------------------------------------------ pieces


## One triangle facing `n` (wound clockwise seen from that side, Godot's front,
## whatever order it is given in), with
## a normal at each corner.
func tri(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	na: Vector3,
	nb: Vector3,
	nc: Vector3,
	col: float,
	shiny := false
) -> void:
	var n := na + nb + nc
	var uv := Vector2(SHINY if shiny else MATTE, col)
	if (b - a).cross(c - a).dot(n) > 0.0:
		verts.append_array(PackedVector3Array([a, c, b]))
		normals.append_array(PackedVector3Array([na, nc, nb]))
	else:
		verts.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([na, nb, nc]))
	uvs.append_array(PackedVector2Array([uv, uv, uv]))


## A flat four-cornered face (corners in order round it) facing `n`.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: float) -> void:
	tri(a, b, c, n, n, n, col)
	tri(a, c, d, n, n, n, col)


## A box: its middle, half its size, its colour, turned by `turn` about its
## middle; `top` colours its top face apart.
func box(mid: Vector3, half: Vector3, col: float, turn := Basis.IDENTITY, top := -1.0) -> void:
	var ax := turn.x * half.x
	var ay := turn.y * half.y
	var az := turn.z * half.z
	for f: Array in [
		[ax, ay, az], [-ax, ay, az], [ay, az, ax], [-ay, az, ax], [az, ax, ay], [-az, ax, ay]
	]:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var face := col if top < 0.0 or not n.is_equal_approx(ay) else top
		var c := mid + n
		quad(c - u - v, c + u - v, c + u + v, c - u + v, n.normalized(), face)


## A round bar from `a` to `b`, `r` thick, with flat ends.
func bar(a: Vector3, b: Vector3, r: float, col: float, sides := 8, shiny := false) -> void:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	var other := along.cross(side)
	for k in sides:
		var a0 := k * TAU / sides
		var a1 := (k + 1) * TAU / sides
		var n0 := side * cos(a0) + other * sin(a0)
		var n1 := side * cos(a1) + other * sin(a1)
		tri(a + n0 * r, b + n0 * r, b + n1 * r, n0, n0, n1, col, shiny)
		tri(a + n0 * r, b + n1 * r, a + n1 * r, n0, n1, n1, col, shiny)
		tri(a, a + n0 * r, a + n1 * r, -along, -along, -along, col, shiny)
		tri(b, b + n1 * r, b + n0 * r, along, along, along, col, shiny)


## A profile turned round the y axis from `base`: [height, radius, colour]
## rings, each band the colour of the ring under it; smooth round and along.
func lathe(profile: Array, sides: int, base := Vector3.ZERO, shiny := false) -> void:
	for i in profile.size() - 1:
		var lo: Array = profile[i]
		var hi: Array = profile[i + 1]
		var y0: float = lo[0]
		var r0: float = lo[1]
		var y1: float = hi[0]
		var r1: float = hi[1]
		var col: float = lo[2]
		var n0 := _ring_normal(profile, i)
		var n1 := _ring_normal(profile, i + 1)
		for k in sides:
			var a0 := k * TAU / sides
			var a1 := (k + 1) * TAU / sides
			var c0 := Vector3(cos(a0), 0.0, sin(a0))
			var c1 := Vector3(cos(a1), 0.0, sin(a1))
			var p00 := base + c0 * r0 + Vector3(0, y0, 0)
			var p01 := base + c1 * r0 + Vector3(0, y0, 0)
			var p10 := base + c0 * r1 + Vector3(0, y1, 0)
			var p11 := base + c1 * r1 + Vector3(0, y1, 0)
			var q00 := c0 * n0.x + Vector3(0, n0.y, 0)
			var q01 := c1 * n0.x + Vector3(0, n0.y, 0)
			var q10 := c0 * n1.x + Vector3(0, n1.y, 0)
			var q11 := c1 * n1.x + Vector3(0, n1.y, 0)
			if r0 > 1e-5 or r1 > 1e-5:
				tri(p00, p10, p11, q00, q10, q11, col, shiny)
				tri(p00, p11, p01, q00, q11, q01, col, shiny)


## The outward normal of a lathe's side at ring `i` (x out, y up).
static func _ring_normal(profile: Array, i: int) -> Vector2:
	var prev: Array = profile[maxi(0, i - 1)]
	var next: Array = profile[mini(profile.size() - 1, i + 1)]
	var dy: float = next[0] - prev[0]
	var dr: float = next[1] - prev[1]
	var n := Vector2(dy, -dr)
	if n.length_squared() < 1e-10:
		return Vector2(0.0, 1.0)
	return n.normalized()


## A ball at `mid`; `paint` gives each facet's colour from its direction
## (a Callable taking a Vector3, giving a float), or `col` for one colour.
func ball(
	mid: Vector3, r: float, col: float, paint := Callable(), slices := 16, stacks := 10
) -> void:
	for j in stacks:
		var t0 := PI * j / stacks
		var t1 := PI * (j + 1) / stacks
		for k in slices:
			var a0 := TAU * k / slices
			var a1 := TAU * (k + 1) / slices
			var n00 := _on_ball(t0, a0)
			var n01 := _on_ball(t0, a1)
			var n10 := _on_ball(t1, a0)
			var n11 := _on_ball(t1, a1)
			var face := col
			if paint.is_valid():
				face = paint.call((n00 + n01 + n10 + n11).normalized())
			tri(mid + n00 * r, mid + n01 * r, mid + n11 * r, n00, n01, n11, face, true)
			tri(mid + n00 * r, mid + n11 * r, mid + n10 * r, n00, n11, n10, face, true)


static func _on_ball(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))


## A flat ring (a disc when r0 is 0) round `mid` facing `n`, `u` one way
## across it.
func ring(
	mid: Vector3, n: Vector3, u: Vector3, r0: float, r1: float, col: float, sides := 24
) -> void:
	var v := n.cross(u)
	for k in sides:
		var a0 := k * TAU / sides
		var a1 := (k + 1) * TAU / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		if r0 <= 0.0:
			tri(mid, mid + d0 * r1, mid + d1 * r1, n, n, n, col)
		else:
			quad(mid + d0 * r0, mid + d0 * r1, mid + d1 * r1, mid + d1 * r0, n, col)


## A shape in the (z, y) plane pushed out along x from x0 to x1: `points`
## (Vector2 z, y) go round a convex outline.
func slab_x(points: Array, x0: float, x1: float, col: float) -> void:
	var count := points.size()
	for i in range(1, count - 1):
		var p0: Vector2 = points[0]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var left := Vector3(-1, 0, 0)
		tri(
			Vector3(x0, p0.y, p0.x),
			Vector3(x0, p1.y, p1.x),
			Vector3(x0, p2.y, p2.x),
			left,
			left,
			left,
			col
		)
		tri(
			Vector3(x1, p0.y, p0.x),
			Vector3(x1, p1.y, p1.x),
			Vector3(x1, p2.y, p2.x),
			-left,
			-left,
			-left,
			col
		)
	var middle := Vector2.ZERO
	for p: Vector2 in points:
		middle += p / count
	for i in count:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		var edge := b - a
		var out := Vector2(edge.y, -edge.x).normalized()
		if out.dot((a + b) * .5 - middle) < 0.0:
			out = -out
		var n := Vector3(0, out.y, out.x)
		quad(
			Vector3(x0, a.y, a.x),
			Vector3(x1, a.y, a.x),
			Vector3(x1, b.y, b.x),
			Vector3(x0, b.y, b.x),
			n,
			col
		)


# ------------------------------------------------------------------ horseshoes


## A horseshoe lying flat, its middle at the origin, heel toward +x and its
## mouth toward -x: a flat iron bar bent round, worn bright on top, rust in
## the nail holes and on its toes.
func _horseshoe() -> void:
	var iron := rgb(92, 86, 80)
	var worn := rgb(132, 126, 118)
	var rust := rgb(134, 78, 44)
	var w := .017
	var h := .009
	var segs := 22
	var sides := 8
	var arc := S.SHOE_ARC
	for i in segs:
		var a0 := -arc + 2.0 * arc * i / segs
		var a1 := -arc + 2.0 * arc * (i + 1) / segs
		var r0 := Vector3(cos(a0), 0.0, sin(a0))
		var r1 := Vector3(cos(a1), 0.0, sin(a1))
		var c0 := r0 * S.SHOE_R
		var c1 := r1 * S.SHOE_R
		# Rust toward the toes and in a nail hole every so often.
		var toe := absf(a0) > arc - .7
		var hole := (i % 4 == 2) and not toe
		for k in sides:
			var b0 := k * TAU / sides
			var b1 := (k + 1) * TAU / sides
			var col := iron
			if sin(b0 + .4) > .55:
				col = rust if hole or toe else worn
			var p00 := c0 + r0 * w * cos(b0) + Vector3.UP * h * sin(b0)
			var p01 := c0 + r0 * w * cos(b1) + Vector3.UP * h * sin(b1)
			var p10 := c1 + r1 * w * cos(b0) + Vector3.UP * h * sin(b0)
			var p11 := c1 + r1 * w * cos(b1) + Vector3.UP * h * sin(b1)
			var n00 := (r0 * cos(b0) / w + Vector3.UP * sin(b0) / h).normalized()
			var n01 := (r0 * cos(b1) / w + Vector3.UP * sin(b1) / h).normalized()
			var n10 := (r1 * cos(b0) / w + Vector3.UP * sin(b0) / h).normalized()
			var n11 := (r1 * cos(b1) / w + Vector3.UP * sin(b1) / h).normalized()
			tri(p00, p10, p11, n00, n10, n11, col, true)
			tri(p00, p11, p01, n00, n11, n01, col, true)
	# The ends, and a calk at each toe and at the heel.
	for a: float in [-arc, arc]:
		var r := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a)) * signf(a)
		ring(r * S.SHOE_R, tangent, r, 0.0, w, rust, 8)
		box(r * S.SHOE_R + Vector3(0, h * .9, 0), Vector3(.011, .006, .011), rust)
	box(Vector3(S.SHOE_R, h * .9, 0), Vector3(.008, .006, .022), worn)


## The stake: an iron pin battered flat on top, rust down its sides.
func _stake() -> void:
	var rust := rgb(118, 76, 52)
	lathe(
		[
			[0.0, S.STAKE_R * 1.2, rgb(96, 72, 54)],
			[.04, S.STAKE_R, rust],
			[S.STAKE_TOP - .03, S.STAKE_R, rgb(140, 100, 72)],
			[S.STAKE_TOP, S.STAKE_R * 1.25, rgb(168, 150, 132)],
			[S.STAKE_TOP + .004, 0.0, rgb(168, 150, 132)],
		],
		10
	)


# ------------------------------------------------------------------ balls


func _softball() -> void:
	var white := rgb(238, 232, 212)
	var red := rgb(206, 40, 34)
	var seam := func(n: Vector3) -> float:
		var s := n.x * n.x - n.z * n.z + .55 * n.y
		return red if absf(s) < .1 else white
	ball(Vector3.ZERO, S.SOFTBALL_R, white, seam, 14, 10)


func _skee_ball() -> void:
	var maple := rgb(206, 152, 88)
	var grain := rgb(150, 98, 52)
	var band := func(n: Vector3) -> float: return grain if absf(n.y) < .14 else maple
	ball(Vector3.ZERO, S.SKEE_BALL_R, maple, band, 14, 10)


# ------------------------------------------------------------------ skee-ball


## The skee-ball cabinet, its foot at the origin and the lane up +z: a maple
## bed between red sides, the rubber hump, the gutter, the ring board
## (the 10 field blue, then 20, 30, 40 and the 50 in the middle, the two
## 100 cups in its top corners), and the red back with its row of bulbs.
func _skee_lane() -> void:
	var half := S.SKEE_W * .5
	var maple := rgb(206, 166, 108)
	var stripe := rgb(168, 124, 76)
	var red := rgb(178, 40, 34)
	var dark := rgb(34, 30, 36)
	var rubber := rgb(58, 56, 60)
	var bed_at := func(s: float) -> float: return S.SKEE_FOOT + S.SKEE_RISE * s
	# The bed, in three strips across, and its hump.
	var steps := 8
	for i in steps:
		var s0 := S.SKEE_LANE * i / steps
		var s1 := S.SKEE_LANE * (i + 1) / steps
		var y0: float = bed_at.call(s0)
		var y1: float = bed_at.call(s1)
		var n := Vector3(0, 1, -S.SKEE_RISE).normalized()
		for strip: Array in [[-half, -.06, maple], [-.06, .06, stripe], [.06, half, maple]]:
			var u0: float = strip[0]
			var u1: float = strip[1]
			var col: float = strip[2]
			quad(
				Vector3(u0, y0, s0),
				Vector3(u1, y0, s0),
				Vector3(u1, y1, s1),
				Vector3(u0, y1, s1),
				n,
				col
			)
	var top: float = bed_at.call(S.SKEE_LANE)
	for i in 4:
		var t0 := float(i) / 4.0
		var t1 := float(i + 1) / 4.0
		var s0 := S.SKEE_LANE + S.SKEE_HUMP * t0
		var s1 := S.SKEE_LANE + S.SKEE_HUMP * t1
		var y0 := top + S.SKEE_HUMP_UP * sin(t0 * PI * .5)
		var y1 := top + S.SKEE_HUMP_UP * sin(t1 * PI * .5)
		var n := Vector3(0, s1 - s0, -(y1 - y0)).normalized()
		quad(
			Vector3(-half, y0, s0),
			Vector3(half, y0, s0),
			Vector3(half, y1, s1),
			Vector3(-half, y1, s1),
			n,
			rubber
		)
	# The gutter under the board's foot, where a short ball drops for 10.
	var lip := S.SKEE_LANE + S.SKEE_HUMP
	quad(
		Vector3(-half, S.SKEE_BOARD_Z - .16, lip),
		Vector3(half, S.SKEE_BOARD_Z - .16, lip),
		Vector3(half, S.SKEE_BOARD_Z - .16, S.SKEE_BOARD_S),
		Vector3(-half, S.SKEE_BOARD_Z - .16, S.SKEE_BOARD_S),
		Vector3.UP,
		dark
	)
	quad(
		Vector3(-half, top + S.SKEE_HUMP_UP, lip),
		Vector3(half, top + S.SKEE_HUMP_UP, lip),
		Vector3(half, S.SKEE_BOARD_Z - .16, lip),
		Vector3(-half, S.SKEE_BOARD_Z - .16, lip),
		Vector3(0, 0, 1),
		rubber
	)
	_skee_board()
	# The sides, the front under the foot, the back and its bulbs.
	var wall := .06
	var foot_top: float = bed_at.call(-.12) + .16
	var mid_top: float = bed_at.call(S.SKEE_BOARD_S - .3) + .16
	var back_top := S.SKEE_BOARD_Z + S.SKEE_BOARD_LEN * sin(S.SKEE_TILT) + .14
	for side: float in [-1.0, 1.0]:
		var x0 := side * half
		var x1 := side * (half + wall * 2.0)
		var lo := minf(x0, x1)
		var hi := maxf(x0, x1)
		slab_x(
			[
				Vector2(-.12, 0.0),
				Vector2(S.SKEE_BOARD_S - .3, 0.0),
				Vector2(S.SKEE_BOARD_S - .3, mid_top),
				Vector2(-.12, foot_top)
			],
			lo,
			hi,
			red
		)
		slab_x(
			[
				Vector2(S.SKEE_BOARD_S - .3, 0.0),
				Vector2(S.SKEE_BACK_S, 0.0),
				Vector2(S.SKEE_BACK_S, back_top),
				Vector2(S.SKEE_BOARD_S - .3, mid_top)
			],
			lo,
			hi,
			red
		)
		# A gold stripe down the outside and a dark kick plate at the foot.
		var out_x := side * (half + wall * 2.0)
		var o0 := minf(out_x, out_x + side * .006)
		var o1 := maxf(out_x, out_x + side * .006)
		slab_x(
			[
				Vector2(-.12, foot_top - .1),
				Vector2(S.SKEE_BOARD_S - .3, mid_top - .1),
				Vector2(S.SKEE_BOARD_S - .3, mid_top - .05),
				Vector2(-.12, foot_top - .05)
			],
			o0,
			o1,
			rgb(236, 196, 58)
		)
		slab_x(
			[
				Vector2(-.12, 0.0),
				Vector2(S.SKEE_BACK_S, 0.0),
				Vector2(S.SKEE_BACK_S, .1),
				Vector2(-.12, .1)
			],
			o0,
			o1,
			rgb(70, 24, 20)
		)
		# The cage's uprights over the board.
		for k in 4:
			var s := S.SKEE_BOARD_S - .3 + (k + 1) * (S.SKEE_BACK_S - S.SKEE_BOARD_S + .3) / 5.0
			var t := (s - S.SKEE_BOARD_S + .3) / (S.SKEE_BACK_S - S.SKEE_BOARD_S + .3)
			var up := lerpf(mid_top, S.SKEE_BACK_TOP - .3, t)
			bar(
				Vector3(side * (half + wall), lerpf(mid_top, back_top, t), s),
				Vector3(side * (half + wall), up, s),
				.01,
				rgb(170, 170, 176),
				4,
				true
			)
		bar(
			Vector3(side * (half + wall), foot_top + .02, -.12),
			Vector3(side * (half + wall), mid_top + .02, S.SKEE_BOARD_S - .3),
			.025,
			rgb(200, 190, 170),
			6,
			true
		)
	box(
		Vector3(0, (S.SKEE_FOOT - .02) * .5, -.07),
		Vector3(half + wall * 2.0, (S.SKEE_FOOT - .02) * .5, .05),
		red,
		Basis.IDENTITY,
		rgb(140, 30, 26)
	)
	# The ball return at the foot: a trough the balls come back to.
	box(Vector3(0, S.SKEE_FOOT - .1, -.26), Vector3(half * .8, .03, .14), dark)
	box(Vector3(0, S.SKEE_FOOT - .2, -.26), Vector3(half * .8, .1, .12), red)
	var back := S.SKEE_BACK_S + .05
	box(
		Vector3(0, S.SKEE_BACK_TOP * .5, back),
		Vector3(half + wall * 2.0, S.SKEE_BACK_TOP * .5, .05),
		red,
		Basis.IDENTITY,
		rgb(120, 26, 22)
	)
	box(
		Vector3(0, S.SKEE_BACK_TOP - .22, back - .06),
		Vector3(half + wall * 2.0 - .04, .14, .012),
		rgb(236, 196, 58)
	)
	for k in 7:
		var x := -half + (k + .5) * S.SKEE_W / 7.0
		ball(
			Vector3(x, S.SKEE_BACK_TOP - .22, back - .08), .03, rgb(255, 240, 170), Callable(), 6, 4
		)
	# The cage over the board: a bar along each side to the back's top.
	for side: float in [-1.0, 1.0]:
		bar(
			Vector3(side * (half + wall), mid_top + .02, S.SKEE_BOARD_S - .3),
			Vector3(side * (half + wall), S.SKEE_BACK_TOP - .3, S.SKEE_BACK_S),
			.016,
			rgb(170, 170, 176),
			6,
			true
		)


## The ring board: its plane from its bottom edge up its slope.
func _skee_board() -> void:
	var half := S.SKEE_W * .5
	var o := Vector3(0, S.SKEE_BOARD_Z, S.SKEE_BOARD_S)
	var up := Vector3(0, sin(S.SKEE_TILT), cos(S.SKEE_TILT))
	var n := Vector3(0, cos(S.SKEE_TILT), -sin(S.SKEE_TILT))
	var across := Vector3(1, 0, 0)
	var length := S.SKEE_BOARD_LEN
	quad(
		o - across * half,
		o + across * half,
		o + across * half + up * length,
		o - across * half + up * length,
		n,
		rgb(30, 50, 118)
	)
	var mid := o + up * S.SKEE_RING_AT
	var colours := [rgb(242, 178, 36), rgb(232, 232, 220), rgb(204, 48, 40), rgb(236, 200, 60)]
	var inner := 0.0
	var lift := .004
	for i in S.SKEE_RINGS.size():
		var row: Array = S.SKEE_RINGS[i]
		var outer: float = row[0]
		var col: float = colours[i]
		ring(mid + n * (lift * (5 - i)), n, across, inner, outer, col, 28)
		# A raised lip round each ring.
		ring(mid + n * (lift * (5 - i) + .002), n, across, outer - .01, outer, rgb(30, 22, 22), 28)
		inner = outer
	# Each ring's drain at its foot, the 50's in the middle.
	var inner2 := 0.0
	for i in S.SKEE_RINGS.size():
		var row2: Array = S.SKEE_RINGS[i]
		var outer2: float = row2[0]
		var at := mid if i == 0 else mid - up * (inner2 + outer2) * .5
		ring(at + n * .03, n, across, 0.0, .035, rgb(6, 6, 10), 12)
		inner2 = outer2
	var cup: Array = S.SKEE_HUNDRED
	var cup_up: float = cup[0]
	var cup_across: float = cup[1]
	var cup_r: float = cup[2]
	for side: float in [-1.0, 1.0]:
		var at := o + up * cup_up + across * side * cup_across + n * .006
		ring(at, n, across, 0.0, cup_r, rgb(6, 6, 10), 16)
		ring(at + n * .002, n, across, cup_r, cup_r + .014, rgb(220, 50, 40), 16)


# ------------------------------------------------------------------ bottles


## A milk bottle standing on its foot: white, a red label, a red cap.
func _bottle() -> void:
	var white := rgb(240, 238, 228)
	var red := rgb(200, 44, 38)
	lathe(
		[
			[0.0, 0.0, white],
			[0.0, .038, white],
			[.008, .044, white],
			[.06, .046, red],
			[.12, .046, white],
			[.16, .042, white],
			[.2, .03, white],
			[.225, .022, white],
			[.245, .023, red],
			[S.BOTTLE_LEN, .021, red],
			[S.BOTTLE_LEN + .002, 0.0, red],
		],
		12,
		Vector3.ZERO,
		true
	)


## A longneck: brown glass, a gold label, a crown cap.
func _beer() -> void:
	var glass := rgb(104, 56, 22)
	var gold := rgb(220, 176, 64)
	var cap := rgb(196, 196, 186)
	lathe(
		[
			[0.0, 0.0, glass],
			[0.0, .03, glass],
			[.035, .032, gold],
			[.085, .032, glass],
			[.11, .03, glass],
			[.14, .014, gold],
			[.16, .012, glass],
			[.19, .012, cap],
			[.2, .013, cap],
			[.202, 0.0, cap],
		],
		10,
		Vector3.ZERO,
		true
	)


## A straw hat with a red band, its brim on the origin.
func _hat() -> void:
	var straw := rgb(214, 178, 106)
	var shade := rgb(176, 140, 78)
	var band := rgb(176, 40, 32)
	lathe(
		[
			[0.0, 0.0, shade],
			[0.0, .16, shade],
			[.014, .165, straw],
			[.02, .085, straw],
			[.03, .079, band],
			[.055, .078, straw],
			[.11, .07, straw],
			[.12, .045, straw],
			[.112, 0.0, straw],
		],
		16
	)


## A tin can, its middle at the origin: a red label round a white band,
## silver rims and ends.
func _tin_can() -> void:
	var tin := rgb(186, 190, 196)
	var red := rgb(198, 50, 40)
	var band := rgb(234, 228, 210)
	var h := S.CAN_H * .5
	var r := S.CAN_R
	lathe(
		[
			[-h, 0.0, tin],
			[-h, r * .96, tin],
			[-h + .008, r, red],
			[-.02, r, band],
			[.02, r, red],
			[h - .008, r, tin],
			[h, r * .96, tin],
			[h, 0.0, tin],
		],
		12,
		Vector3.ZERO,
		true
	)


# ------------------------------------------------------------------ the fair


## A gallery rail one cell long along +x (stretched by its sprite's turn).
func _rail() -> void:
	bar(Vector3(0, 0, 0), Vector3(1, 0, 0), .022, rgb(170, 160, 140), 6, true)
	box(Vector3(.5, -.03, 0), Vector3(.5, .008, .03), rgb(80, 66, 52))


## A shelf plank one cell long along +x, its top on the origin.
func _shelf() -> void:
	box(
		Vector3(.5, -.025, 0),
		Vector3(.5, .025, .16),
		rgb(150, 98, 56),
		Basis.IDENTITY,
		rgb(176, 120, 70)
	)
	box(Vector3(.5, -.07, .14), Vector3(.5, .02, .02), rgb(120, 74, 40))


## The gallery's start bell, hanging from its hanger (the origin): brass,
## dark in its mouth, a red bracket over it.
func _bell() -> void:
	var brass := rgb(222, 178, 66)
	var dark := rgb(120, 84, 30)
	lathe(
		[
			[-.2, 0.0, rgb(40, 30, 16)],
			[-.2, .088, dark],
			[-.188, .095, brass],
			[-.15, .08, brass],
			[-.1, .066, brass],
			[-.045, .056, brass],
			[-.012, .042, brass],
			[0.0, 0.0, brass],
		],
		14,
		Vector3.ZERO,
		true
	)
	bar(Vector3(0, 0, 0), Vector3(0, .09, 0), .012, rgb(70, 66, 62), 6, true)
	box(Vector3(0, .1, -.1), Vector3(.025, .015, .14), rgb(170, 40, 34))


# ------------------------------------------------------------------ trophies


## A turned walnut plinth with a brass band, its top at .25.
func _plinth() -> void:
	var walnut := rgb(96, 58, 36)
	var light := rgb(128, 80, 46)
	var brass := rgb(212, 170, 72)
	lathe(
		[
			[0.0, 0.0, walnut],
			[0.0, .2, walnut],
			[.04, .2, walnut],
			[.05, .17, light],
			[.15, .15, brass],
			[.19, .15, light],
			[.21, .17, walnut],
			[.25, .17, walnut],
			[.25, 0.0, light],
		],
		14,
		Vector3.ZERO,
		true
	)


## A shield-shaped walnut plaque facing +z, its back on the origin, with a
## brass plate low on it.
func _plaque() -> void:
	var walnut := rgb(92, 56, 34)
	var edge := rgb(128, 82, 48)
	var brass := rgb(220, 178, 78)
	box(Vector3(0, .02, .02), Vector3(.24, .26, .02), walnut, Basis.IDENTITY, edge)
	box(Vector3(0, -.29, .02), Vector3(.17, .04, .02), walnut)
	box(Vector3(0, -.34, .02), Vector3(.08, .03, .02), walnut)
	box(Vector3(0, .02, .045), Vector3(.2, .22, .006), edge)
	box(Vector3(0, -.16, .055), Vector3(.12, .035, .005), brass)


# ------------------------------------------------------------------ dunk tank


## The dunk tank, its middle on the origin, its front toward -z: a red base,
## steel sides and a glass front onto the water, the water itself, a red
## rim, the cage posts and its sign, and the arm the bullseye hangs from.
func _dunk_tank() -> void:
	var steel := rgb(150, 158, 170)
	var red := rgb(176, 42, 34)
	var glass := rgb(70, 136, 170)
	var water := rgb(50, 108, 168)
	var hx := S.TANK.x
	var hz := S.TANK.y
	var base := .12
	box(Vector3(0, base * .5, 0), Vector3(hx + .08, base * .5, hz + .08), red)
	var wall_h := (S.TANK_TOP - base) * .5
	var mid_y := base + wall_h
	box(Vector3(-hx, mid_y, 0), Vector3(.03, wall_h, hz), steel)
	box(Vector3(hx, mid_y, 0), Vector3(.03, wall_h, hz), steel)
	box(Vector3(0, mid_y, hz), Vector3(hx, wall_h, .03), steel)
	box(Vector3(0, mid_y, -hz), Vector3(hx, wall_h, .03), glass)
	# Bubbles and the waterline seen through the glass.
	box(Vector3(0, S.WATER - .01, -hz - .032), Vector3(hx - .02, .012, .002), rgb(170, 214, 236))
	quad(
		Vector3(-hx + .03, S.WATER, -hz + .03),
		Vector3(hx - .03, S.WATER, -hz + .03),
		Vector3(hx - .03, S.WATER, hz - .03),
		Vector3(-hx + .03, S.WATER, hz - .03),
		Vector3.UP,
		water
	)
	for z: float in [-hz, hz]:
		box(Vector3(0, S.TANK_TOP, z), Vector3(hx + .04, .025, .045), red)
	for x: float in [-hx, hx]:
		box(Vector3(x, S.TANK_TOP, 0), Vector3(.045, .025, hz + .04), red)
	# Steel straps round the tank, and a ladder up its back.
	for y: float in [base + .16, S.TANK_TOP - .14]:
		box(Vector3(0, y, -hz - .035), Vector3(hx + .01, .025, .006), steel)
		box(Vector3(0, y, hz + .035), Vector3(hx + .01, .025, .006), steel)
	for x: float in [-.22, .22]:
		bar(Vector3(x, 0, hz + .12), Vector3(x, S.TANK_TOP + .3, hz + .12), .016, steel, 6, true)
	for k in 6:
		var rung := .2 + k * .2
		bar(Vector3(-.22, rung, hz + .12), Vector3(.22, rung, hz + .12), .012, steel, 6, true)
	# The cage: four posts, a frame over the top, a sign.
	var cage := 2.65
	for x: float in [-hx, hx]:
		for z: float in [-hz, hz]:
			bar(Vector3(x, S.TANK_TOP, z), Vector3(x, cage, z), .025, steel, 6, true)
	for z: float in [-hz, hz]:
		bar(Vector3(-hx, cage, z), Vector3(hx, cage, z), .022, steel, 6, true)
	for x: float in [-hx, hx]:
		bar(Vector3(x, cage, -hz), Vector3(x, cage, hz), .022, steel, 6, true)
	box(Vector3(0, cage + .2, -hz), Vector3(hx - .05, .17, .02), rgb(236, 200, 58))
	box(Vector3(0, cage + .2, -hz - .022), Vector3(hx - .12, .11, .003), red)
	for k in 5:
		box(
			Vector3(-hx + .3 + k * (hx * 2.0 - .6) / 4.0, cage + .2, -hz - .026),
			Vector3(.04, .06, .002),
			rgb(250, 240, 210)
		)
	# The seat's hinge rail across the back.
	bar(
		Vector3(-hx, S.SEAT_Z - .03, hz - .1),
		Vector3(hx, S.SEAT_Z - .03, hz - .1),
		.02,
		steel,
		6,
		true
	)
	# The arm out of the east side the bullseye hangs from, and its brace.
	var pivot := Vector3(S.TARGET_AT.x, S.TARGET_AT.z + .3, S.TARGET_AT.y)
	bar(Vector3(hx, pivot.y, pivot.z), pivot + Vector3(.04, 0, 0), .022, steel, 6, true)
	bar(Vector3(hx, pivot.y - .45, pivot.z), pivot - Vector3(.3, 0, 0), .016, steel, 6, true)


## The seat, its hinge on the origin and its plank out toward -z.
func _dunk_seat() -> void:
	var plank := rgb(170, 118, 66)
	box(
		Vector3(0, .02, -S.SEAT_DEEP * .5),
		Vector3(.62, .025, S.SEAT_DEEP * .5),
		plank,
		Basis.IDENTITY,
		rgb(196, 142, 82)
	)
	box(Vector3(0, -.01, -S.SEAT_DEEP + .03), Vector3(.62, .02, .03), rgb(120, 80, 44))


## The bullseye hanging from its pivot (the origin) on a rod, facing -z: red
## and white rings, a gold middle.
func _dunk_target() -> void:
	var steel := rgb(150, 158, 170)
	var red := rgb(212, 40, 34)
	var white := rgb(244, 240, 228)
	var r := S.TARGET_R
	bar(Vector3(0, 0, 0), Vector3(0, -.3 + r, 0), .014, steel, 6, true)
	var mid := Vector3(0, -.3, 0)
	ring(mid + Vector3(0, 0, .016), Vector3(0, 0, 1), Vector3.RIGHT, 0.0, r, white, 24)
	var front := Vector3(0, 0, -1)
	var bands := [
		[0.0, .2, rgb(250, 200, 50)],
		[.2, .4, red],
		[.4, .6, white],
		[.6, .8, red],
		[.8, 1.0, white]
	]
	for band: Array in bands:
		var r0: float = band[0]
		var r1: float = band[1]
		var col: float = band[2]
		ring(mid - Vector3(0, 0, .016), front, Vector3.RIGHT, r0 * r, r1 * r, col, 24)
	for k in 24:
		var a0 := k * TAU / 24.0
		var a1 := (k + 1) * TAU / 24.0
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		quad(
			mid + d0 * r - Vector3(0, 0, .016),
			mid + d1 * r - Vector3(0, 0, .016),
			mid + d1 * r + Vector3(0, 0, .016),
			mid + d0 * r + Vector3(0, 0, .016),
			(d0 + d1).normalized(),
			red
		)
