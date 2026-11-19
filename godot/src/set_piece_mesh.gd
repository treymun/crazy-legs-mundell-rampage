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
##   spsplit:sx,sy,sz,mode,seed,detail
##                       the box of spbox broken up (src/set_piece_wreck.gd,
##                       looks): BOARDS (a plank wall: x across in boards, z
##                       up, each board or run of boards snapped once or twice
##                       on a jagged line), SHEETS (tin: x across in sheets,
##                       y down the slope torn across), STICK (a post, a beam,
##                       a leg, a brace, a pipe: snapped along its length on
##                       splintered ends), PLANKS (a deck: planks along x,
##                       some snapped); `seed` the break's own dice, `detail`
##                       how fine (fewer on a phone). Every piece shows the
##                       very part of the tile it showed in the whole box, so
##                       the pieces read as the box until they come apart
##   sphooparc:r,h,n,k,segs,seed
##                       sphoops' k hoops each sprung into `segs` bent bands
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
## spsplit's ways of breaking a box up.
const BOARDS := 0
const SHEETS := 1
const STICK := 2
const PLANKS := 3


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
		"spsplit":
			return split(
				Vector3(_a(args, 0, 1.0), _a(args, 1, .1), _a(args, 2, 1.0)),
				int(_a(args, 3, 0.0)),
				int(_a(args, 4, 1.0)),
				_a(args, 5, 1.0)
			)
		"sphooparc":
			return _hoop_arcs(
				_a(args, 0, 1.5),
				_a(args, 1, 2.0),
				maxi(6, int(_a(args, 2, 16.0))),
				maxi(1, int(_a(args, 3, 3.0))),
				maxi(1, int(_a(args, 4, 3.0))),
				int(_a(args, 5, 1.0))
			)
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


## The pieces of a "t:<tile>@0,0|<recipe>:<numbers>" key, as WreckCuts cuts
## it (a worker may call it: it touches nothing shared).
static func cut_key(key: String) -> Array:
	var recipe := key.substr(key.find("|") + 1)
	var args := PackedFloat32Array()
	if recipe.contains(":"):
		for item: String in recipe.get_slice(":", 1).split(","):
			args.append(item.to_float())
	return cut(recipe.get_slice(":", 0), args)


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


# ------------------------------------------------------------- broken up


## A box `size` (about its middle) broken up `mode`'s way with the dice
## `seed`: its pieces, each about its own middle (`centre` in the box), each
## face showing the tile where the whole box showed it.
static func split(size: Vector3, mode: int, seed: int, detail: float) -> Array:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed
	var out: Array = []
	var h := size * .5
	detail = clampf(detail, .3, 2.0)
	match mode:
		BOARDS:
			# Boards across x, z up: runs of one to three boards, each snapped.
			var cols := clampi(roundi(size.x / .3 * detail), 2, 12)
			for strip: Vector2 in _runs(dice, -h.x, h.x, cols, 3):
				_snap(dice, out, size, 2, 0, strip, Vector2(-h.y, h.y), -h.z, h.z, .5, .13, detail)
		SHEETS:
			# Tin: whole sheets across x (seams), torn across down the slope.
			var cols := 2 if detail >= .5 and size.x > 1.2 else 1
			for strip: Vector2 in _runs(dice, -h.x, h.x, cols, 1):
				_snap(dice, out, size, 1, 0, strip, Vector2(-h.z, h.z), -h.y, h.y, .9, .16, detail)
		STICK:
			var a := 0 if size.x >= size.y and size.x >= size.z else 1 if size.y >= size.z else 2
			var w := (a + 1) % 3 if size[(a + 1) % 3] >= size[(a + 2) % 3] else (a + 2) % 3
			var t := 3 - a - w
			var jag := minf(.2, minf(size[w], size[t]) * 1.3)
			_snap(
				dice,
				out,
				size,
				a,
				w,
				Vector2(-h[w], h[w]),
				Vector2(-h[t], h[t]),
				-h[a],
				h[a],
				-.45,
				jag,
				detail
			)
		PLANKS:
			var rows := clampi(roundi(size.y / .24 * detail), 2, 12)
			for strip: Vector2 in _runs(dice, -h.y, h.y, rows, 2):
				_snap(dice, out, size, 0, 1, strip, Vector2(-h.z, h.z), -h.x, h.x, .6, .12, detail)
	return out


## `n` even boards from a to b, run together in runs of 1 to `most`: each
## run's [from, to].
static func _runs(dice: RandomNumberGenerator, a: float, b: float, n: int, most: int) -> Array:
	var out: Array = []
	var k := 0
	while k < n:
		var run := mini(n - k, dice.randi_range(1, most))
		out.append(Vector2(a + (b - a) * k / n, a + (b - a) * (k + run) / n))
		k += run
	return out


## One run (`across` along axis w, `thick` along the third) from a0 to a1
## along axis `a`, snapped into one to three pieces on jagged lines; each
## piece added to `out`. `snap` how likely each further break, `jag` how
## ragged a break (metres).
static func _snap(
	dice: RandomNumberGenerator,
	out: Array,
	size: Vector3,
	a: int,
	w: int,
	across: Vector2,
	thick: Vector2,
	a0: float,
	a1: float,
	snap: float,
	jag: float,
	detail: float
) -> void:
	var length := a1 - a0
	var breaks := 0
	# A `snap` below 0: its first break is sure (a post always snaps).
	var sure := snap < 0.0
	snap = absf(snap)
	for n in 2:
		if length / (breaks + 2) > .35 and ((sure and n == 0) or dice.randf() < snap * detail):
			breaks += 1
	var cuts: Array = []
	for n in breaks:
		cuts.append(lerpf(a0, a1, (n + dice.randf_range(.35, .75)) / (breaks + 1)))
	# Each break a jagged line: its height at the run's first edge, its last
	# edge and its middle (x, y, z).
	var lines: Array = [Vector3(a0, a0, a0)]
	for c: float in cuts:
		var j := jag * dice.randf_range(.5, 1.0)
		var line := Vector3(
			dice.randf_range(-j, j), dice.randf_range(-j, j), dice.randf_range(-j, j)
		)
		if dice.randf() < .5:
			# A splinter point (or a notch) in the middle.
			line.z = signf(dice.randf() - .5) * j * 1.3
		lines.append(line + Vector3(c, c, c))
	lines.append(Vector3(a1, a1, a1))
	var wm := lerpf(across.x, across.y, dice.randf_range(.35, .65))
	for n in breaks + 1:
		var lo: Vector3 = lines[n]
		var hi: Vector3 = lines[n + 1]
		out.append(_slab(size, a, w, across, wm, thick, lo, hi))


## A piece: along axis `a` from the line `lo` to the line `hi` (each a height
## at the run's first edge, last edge and middle `wm`: x, y, z), across axis
## w from across.x to across.y, through the third axis from thick.x to thick.y.
static func _slab(
	size: Vector3,
	a: int,
	w: int,
	across: Vector2,
	wm: float,
	thick: Vector2,
	lo: Vector3,
	hi: Vector3
) -> WreckCuts.Part:
	var t := 3 - a - w
	var lo_a := minf(lo.x, minf(lo.y, lo.z))
	var hi_a := maxf(hi.x, maxf(hi.y, hi.z))
	var part := WreckCuts.Part.new()
	var c := Vector3.ZERO
	c[a] = (lo_a + hi_a) * .5
	c[w] = (across.x + across.y) * .5
	c[t] = (thick.x + thick.y) * .5
	part.centre = c
	var half := Vector3.ZERO
	half[a] = maxf(.01, (hi_a - lo_a) * .5)
	half[w] = maxf(.01, (across.y - across.x) * .5)
	half[t] = maxf(.01, (thick.y - thick.x) * .5)
	part.half = half
	var ws: Array[float] = [across.x, wm, across.y]
	var los: Array[float] = [lo.x, lo.z, lo.y]
	var his: Array[float] = [hi.x, hi.z, hi.y]
	for side: float in [thick.x, thick.y]:
		var ring: Array[Vector3] = []
		for k in 3:
			ring.append(_pt(a, w, los[k], ws[k], side))
		for k: int in [2, 1, 0]:
			ring.append(_pt(a, w, his[k], ws[k], side))
		var n := Vector3.ZERO
		n[t] = -1.0 if side < c[t] else 1.0
		_poly(part, ring, n, size, c)
	# The run's two edges.
	for k: int in [0, 2]:
		var n := Vector3.ZERO
		n[w] = -1.0 if k == 0 else 1.0
		var ring: Array[Vector3] = [
			_pt(a, w, los[k], ws[k], thick.x),
			_pt(a, w, los[k], ws[k], thick.y),
			_pt(a, w, his[k], ws[k], thick.y),
			_pt(a, w, his[k], ws[k], thick.x),
		]
		_poly(part, ring, n, size, c)
	# The ends: two faces each, on the jagged line.
	var through := Vector3.ZERO
	through[t] = 1.0
	for end in 2:
		var hs: Array[float] = los if end == 0 else his
		for k in 2:
			var p0 := _pt(a, w, hs[k], ws[k], thick.x)
			var p1 := _pt(a, w, hs[k + 1], ws[k + 1], thick.x)
			var n := (p1 - p0).cross(through).normalized()
			if (n[a] > 0.0) == (end == 0):
				n = -n
			var ring: Array[Vector3] = [
				p0, p1, _pt(a, w, hs[k + 1], ws[k + 1], thick.y), _pt(a, w, hs[k], ws[k], thick.y)
			]
			_poly(part, ring, n, size, c)
	return part


static func _pt(a: int, w: int, along: float, across: float, through: float) -> Vector3:
	var p := Vector3.ZERO
	p[a] = along
	p[w] = across
	p[3 - a - w] = through
	return p


## A flat face (its corners in the whole box's frame, in order round it)
## added to `part` about `centre`, its tile laid on as add_box lays it on the
## whole box's face that way (so a piece shows what the whole showed there):
## the face cut where the box's tile repeats, each cell from its own corner.
static func _poly(
	part: WreckCuts.Part, ring: Array[Vector3], n: Vector3, size: Vector3, centre: Vector3
) -> void:
	var au := 0
	var av := 1
	var unit_v := UNIT_U
	if absf(n.y) >= absf(n.x) and absf(n.y) >= absf(n.z):
		av = 2
		unit_v = UNIT_V
	elif absf(n.x) >= absf(n.z):
		au = 1
		av = 2
		unit_v = UNIT_V
	var ax := 3 - au - av
	var su := size[au]
	var sv := size[av]
	var cell_u := su / maxi(1, ceili(su / UNIT_U - .001))
	var cell_v := sv / maxi(1, ceili(sv / unit_v - .001))
	var flat := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p: Vector3 in ring:
		var q := Vector2(p[au] + su * .5, p[av] + sv * .5)
		flat.append(q)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var p0 := ring[0]
	for iu in range(
		floori(lo.x / cell_u + .001),
		maxi(floori(lo.x / cell_u + .001) + 1, ceili(hi.x / cell_u - .001))
	):
		for iv in range(
			floori(lo.y / cell_v + .001),
			maxi(floori(lo.y / cell_v + .001) + 1, ceili(hi.y / cell_v - .001))
		):
			var cell := Rect2(iu * cell_u, iv * cell_v, cell_u, cell_v)
			var piece := _clip(flat, cell)
			if piece.size() < 3:
				continue
			var tris := Geometry2D.triangulate_polygon(piece)
			if tris.is_empty():
				for k in range(1, piece.size() - 1):
					tris.append_array([0, k, k + 1])
			for idx: int in tris:
				var q := piece[idx]
				var p := Vector3.ZERO
				p[au] = q.x - su * .5
				p[av] = q.y - sv * .5
				p[ax] = p0[ax] - (n[au] * (p[au] - p0[au]) + n[av] * (p[av] - p0[av])) / n[ax]
				part.verts.append(p - centre)
				part.normals.append(n)
				part.uvs.append(
					Vector2(
						clampf((q.x - cell.position.x) / UNIT_U, EDGE, 1.0 - EDGE),
						clampf(1.0 - (q.y - cell.position.y) / unit_v, EDGE, 1.0 - EDGE)
					)
				)


## A polygon clipped to a rectangle (Sutherland-Hodgman, edge by edge).
static func _clip(poly: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var out := poly
	for edge in 4:
		var src := out
		out = PackedVector2Array()
		if src.is_empty():
			break
		for k in src.size():
			var cur := src[k]
			var prev := src[k - 1]
			var cin := _inside(cur, r, edge)
			var pin := _inside(prev, r, edge)
			if cin != pin:
				out.append(_cross(prev, cur, r, edge))
			if cin:
				out.append(cur)
	return out


static func _inside(p: Vector2, r: Rect2, edge: int) -> bool:
	match edge:
		0:
			return p.x >= r.position.x - 1e-5
		1:
			return p.x <= r.end.x + 1e-5
		2:
			return p.y >= r.position.y - 1e-5
	return p.y <= r.end.y + 1e-5


static func _cross(a: Vector2, b: Vector2, r: Rect2, edge: int) -> Vector2:
	var at := 0.0
	match edge:
		0:
			at = (r.position.x - a.x) / (b.x - a.x)
		1:
			at = (r.end.x - a.x) / (b.x - a.x)
		2:
			at = (r.position.y - a.y) / (b.y - a.y)
		_:
			at = (r.end.y - a.y) / (b.y - a.y)
	return a.lerp(b, clampf(at, 0.0, 1.0))


## sphoops' hoops each sprung into `segs` bands bent round (each a piece
## about its own middle: x along the band, y out, z up, as a stave's frame), split at the dice's
## angles.
static func _hoop_arcs(r: float, h: float, n: int, k: int, segs: int, seed: int) -> Array:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed
	var out: Array = []
	var wide := TAU * r / n * 1.06
	for j in k:
		var z := -h * .5 + h * (j + .5) / k
		var start := dice.randf() * TAU
		var cuts: Array[float] = []
		for s in segs:
			cuts.append(start + TAU * (s + dice.randf_range(-.2, .2)) / segs)
		cuts.append(start + TAU)
		for s in segs:
			var a0 := cuts[s]
			var a1 := cuts[s + 1]
			var mid := (a0 + a1) * .5
			var part := WreckCuts.Part.new()
			part.centre = Vector3(cos(mid) * r, sin(mid) * r, z)
			part.basis = Basis(
				Vector3(sin(mid), -cos(mid), 0.0),
				Vector3(cos(mid), sin(mid), 0.0),
				Vector3(0, 0, 1)
			)
			var inv := part.basis.inverse()
			var bands := maxi(2, ceili((a1 - a0) / TAU * n))
			var lo := Vector3(INF, INF, -.045)
			var hi := Vector3(-INF, -INF, .045)
			for b in bands:
				var a := lerpf(a0, a1, (b + .5) / bands)
				var at := inv * (Vector3(cos(a) * r, sin(a) * r, z) - part.centre)
				var turn := (
					inv
					* Basis(
						Vector3(sin(a), -cos(a), 0.0),
						Vector3(cos(a), sin(a), 0.0),
						Vector3(0, 0, 1)
					)
				)
				var span := minf(wide, (a1 - a0) / bands * r * 1.08)
				add_box(part, at, turn, Vector3(span * .5, .02, .045))
				lo = Vector3(minf(lo.x, at.x - span * .5), minf(lo.y, at.y - .03), -.045)
				hi = Vector3(maxf(hi.x, at.x + span * .5), maxf(hi.y, at.y + .03), .045)
			part.half = (hi - lo) * .5
			out.append(part)
	return out
