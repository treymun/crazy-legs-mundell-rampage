## The set pieces' own pieces (features/set_pieces.gd, src/set_piece_shape.gd)
## as WreckCuts parts, so the 3D view's wreck layer draws them with a level
## tile's own picture and wreckage.gd can throw them: a key
## "t:<tile>@0,0|<recipe>:<numbers>" (WreckCuts._cut_tile hands any recipe
## starting "sp" here).
##
##   spbox:sx,sy,sz      one solid box (a post, a beam, a plank wall, a tin
##                       sheet, a deck), the tile repeated across every face
##                       by the metre as the level's walls carry it (UNIT_U
##                       along, UNIT_V up), so a wall of barn boards here
##                       shows the same boards as a barn wall of the level
##   sptank:r,h,n        a stave tank: n staves round a ring, each its own
##                       piece (they fly apart when it bursts)
##   sphoops:r,h,n,k     k iron hoops round it, each a ring of n bands
##   spcone:r,rise,n     a tin cap of n sectors over the tank
##   sparc:r,w,h,n       a picture (a "p:" source) painted round a tank of
##                       radius r, w along the curve and h tall, facing -y,
##                       in n strips
##
## Parts are about their own middle in map axes (x, y, z up); `centre` and
## `basis` place them in the whole's frame (WreckCuts.Part).
class_name SetPieceMesh
extends RefCounted

## Texels to a tile and the world size one repeat covers (level_mesh.gd lays a
## wall's tile 128 texels a cell along and 100 a cell up).
const UNIT_U := 1.0
const UNIT_V := 1.28
const EDGE := .5 / 128.0
## A painted band's back: how far inside its face, and the picture's row it
## shows (plain paint above the letters: build_town_signs.gd tower_sign).
const BACK := .04
const PLAIN_V := 2.5 / 22.0


static func cut(recipe: String, args: PackedFloat32Array) -> Array:
	match recipe:
		"spbox":
			var part := box(_a(args, 0, 1.0), _a(args, 1, .1), _a(args, 2, 1.0))
			return [part]
		"sptank":
			return _tank(_a(args, 0, 1.5), _a(args, 1, 2.0), maxi(6, int(_a(args, 2, 16.0))))
		"sphoops":
			return _hoops(
				_a(args, 0, 1.5),
				_a(args, 1, 2.0),
				maxi(6, int(_a(args, 2, 16.0))),
				maxi(1, int(_a(args, 3, 3.0)))
			)
		"spcone":
			return [_cone(_a(args, 0, 1.6), _a(args, 1, .8), maxi(6, int(_a(args, 2, 16.0))))]
		"sparc":
			return [
				_arc(
					_a(args, 0, 1.6),
					_a(args, 1, 2.0),
					_a(args, 2, .4),
					maxi(2, int(_a(args, 3, 8.0)))
				)
			]
	return []


static func _a(args: PackedFloat32Array, i: int, fallback: float) -> float:
	return args[i] if i < args.size() else fallback


## A box sx by sy by sz about its middle, every face the tile by the metre.
static func box(sx: float, sy: float, sz: float) -> WreckCuts.Part:
	var part := WreckCuts.Part.new()
	part.half = Vector3(maxf(sx * .5, .01), maxf(sy * .5, .01), maxf(sz * .5, .01))
	add_box(part, Vector3.ZERO, Basis.IDENTITY, part.half)
	return part


## A box of half sizes `h` at `at` turned by `b` into `part`'s faces.
static func add_box(part: WreckCuts.Part, at: Vector3, b: Basis, h: Vector3) -> void:
	# Each face: its normal axis and the two axes across it (u, v), with
	# v the up one where the face stands (z), else y.
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var hn := absf(n.dot(h))
		var unit_v := UNIT_V if v.z != 0.0 else UNIT_U
		_face(part, at, b, n * hn, u * hu, v * hv, hu * 2.0 / UNIT_U, hv * 2.0 / unit_v, b * n)


## One face: middle `mid`, half spans `u` and `v` (in the part's frame before
## `b`), repeating the tile `ru` by `rv` times (split into quads of at most one
## repeat each, every quad's texture from its own corner).
static func _face(
	part: WreckCuts.Part,
	at: Vector3,
	b: Basis,
	mid: Vector3,
	u: Vector3,
	v: Vector3,
	ru: float,
	rv: float,
	n: Vector3
) -> void:
	var cu := maxi(1, ceili(ru - .001))
	var cv := maxi(1, ceili(rv - .001))
	for j in cv:
		for i in cu:
			var a0 := float(i) / cu
			var a1 := float(i + 1) / cu
			var b0 := float(j) / cv
			var b1 := float(j + 1) / cv
			var pu0 := mid + u * (a0 * 2.0 - 1.0)
			var pu1 := mid + u * (a1 * 2.0 - 1.0)
			var dv0 := v * (b0 * 2.0 - 1.0)
			var dv1 := v * (b1 * 2.0 - 1.0)
			var tu := clampf(ru / cu, .02, 1.0)
			var tv := clampf(rv / cv, .02, 1.0)
			# Texture: u from the left, v from the top (row 0 is the tile's top).
			var uv := [
				Vector2(EDGE, 1.0 - EDGE),
				Vector2(tu - EDGE, 1.0 - EDGE),
				Vector2(tu - EDGE, 1.0 - tv + EDGE),
				Vector2(EDGE, 1.0 - tv + EDGE),
			]
			WreckCuts._quad(
				part,
				at + b * (pu0 + dv0),
				at + b * (pu1 + dv0),
				at + b * (pu1 + dv1),
				at + b * (pu0 + dv1),
				n,
				uv
			)


## A frame whose x is along `along` and z as near `up` as it can be.
static func frame(along: Vector3, up: Vector3) -> Basis:
	var x := along.normalized()
	var y := up.cross(x).normalized()
	if y.length() < .5:
		y = Vector3(0, 1, 0) if absf(x.y) < .9 else Vector3(1, 0, 0)
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## n staves round a ring of radius r, h tall: each its own piece, about its
## own middle, turned to face out.
static func _tank(r: float, h: float, n: int) -> Array:
	var out: Array = []
	var wide := TAU * r / n * 1.04
	for k in n:
		var a := TAU * k / n
		var out_dir := Vector3(cos(a), sin(a), 0.0)
		var part := WreckCuts.Part.new()
		# The stave's own frame: x across it (round the ring), y out, z up.
		var b := Basis(Vector3(sin(a), -cos(a), 0.0), out_dir, Vector3(0, 0, 1))
		part.centre = out_dir * r
		part.basis = b
		part.half = Vector3(wide * .5, .045, h * .5)
		add_box(part, Vector3.ZERO, Basis.IDENTITY, part.half)
		out.append(part)
	return out


## k hoops round a tank of radius r and height h: each a ring of n bands,
## one piece a hoop.
static func _hoops(r: float, h: float, n: int, k: int) -> Array:
	var out: Array = []
	var wide := TAU * r / n * 1.06
	for j in k:
		var z := -h * .5 + h * (j + .5) / k
		var part := WreckCuts.Part.new()
		part.centre = Vector3(0, 0, z)
		part.half = Vector3(r, r, .04)
		for i in n:
			var a := TAU * i / n
			var b := Basis(
				Vector3(sin(a), -cos(a), 0.0), Vector3(cos(a), sin(a), 0.0), Vector3(0, 0, 1)
			)
			add_box(part, Vector3(cos(a), sin(a), 0.0) * r, b, Vector3(wide * .5, .02, .045))
		out.append(part)
	return out


## A cap of n tin sectors rising `rise` to a point over a ring of radius r.
static func _cone(r: float, rise: float, n: int) -> WreckCuts.Part:
	var part := WreckCuts.Part.new()
	part.centre = Vector3(0, 0, rise * .5)
	part.half = Vector3(r, r, rise * .5)
	var top := Vector3(0, 0, rise * .5)
	var slant := Vector2(r, rise).length()
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, -rise * .5)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, -rise * .5)
		var nrm := (p1 - p0).cross(top - p0).normalized()
		if nrm.z < 0.0:
			nrm = -nrm
		var span := (p1 - p0).length() / UNIT_U
		var tall := clampf(slant / UNIT_V, .05, 1.0)
		for corner: Vector3 in [p0, p1, top]:
			part.verts.append(corner)
			part.normals.append(nrm)
		part.uvs.append(Vector2(EDGE, 1.0 - EDGE))
		part.uvs.append(Vector2(clampf(span, .05, 1.0) - EDGE, 1.0 - EDGE))
		part.uvs.append(Vector2(clampf(span, .05, 1.0) * .5, 1.0 - tall + EDGE))
	return part


## A picture round a curve of radius r, w along it and h tall, its middle
## facing -y, in n strips (the whole picture across them).
static func _arc(r: float, w: float, h: float, n: int) -> WreckCuts.Part:
	var part := WreckCuts.Part.new()
	var span := w / r
	part.half = Vector3(r, r, h * .5)
	for i in n:
		var a0 := -PI * .5 - span * .5 + span * i / n
		var a1 := -PI * .5 - span * .5 + span * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0.0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var nrm := Vector3(cos((a0 + a1) * .5), sin((a0 + a1) * .5), 0.0)
		# The picture's left at the curve's far end, so it reads left to
		# right seen from outside.
		var u0 := 1.0 - float(i) / n
		var u1 := 1.0 - float(i + 1) / n
		WreckCuts._quad(
			part,
			p0 + Vector3(0, 0, -h * .5),
			p1 + Vector3(0, 0, -h * .5),
			p1 + Vector3(0, 0, h * .5),
			p0 + Vector3(0, 0, h * .5),
			nrm,
			[Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0)]
		)
		# Its back a hair inside: plain paint (a row of the picture above the
		# letters), so from behind (the band flying, lying face down) no
		# lettering shows through backwards.
		var back := (r - BACK) / r
		WreckCuts._quad(
			part,
			p1 * back + Vector3(0, 0, -h * .5),
			p0 * back + Vector3(0, 0, -h * .5),
			p0 * back + Vector3(0, 0, h * .5),
			p1 * back + Vector3(0, 0, h * .5),
			-nrm,
			[Vector2(u1, PLAIN_V), Vector2(u0, PLAIN_V), Vector2(u0, PLAIN_V), Vector2(u1, PLAIN_V)]
		)
	return part
