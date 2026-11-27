## What a level's geometry block draws (LevelGeometry.render_parts, moved
## here out of level_geometry.gd in pass 16 for its line cap): the wall rows
## of slab edges, segments and ladders, the flat caps over and under, the
## slopes, and the rakes (faces whose top or bottom slopes).
class_name GeoParts
extends RefCounted


## What the renderers draw for it:
##   "walls": wall rows (LevelData.WALL_STRIDE each), slab edges and segments
##   "caps": height -> [x0, y0, x1, y1, tile, cuts...] flat floors seen from above
##   "roof_caps": height -> [...] flat surfaces seen from below
##   "slopes": [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...]
## `ground` gives a cell's floor (an edge or a wedge stops there).
static func render(geo: LevelGeometry, ground: Callable) -> Dictionary:
	var walls := PackedFloat32Array()
	var caps := {}
	var roof_caps := {}
	var slopes: Array = []
	var rakes := PackedFloat32Array()
	var slab_edges := geo.slab_edges
	for s in geo.slabs:
		var poly := LevelGeometry.outline(s.x0, s.y0, s.x1, s.y1, s.cuts)
		if poly.size() < 3:
			continue
		if s.sloped():
			slopes.append(_slope_row(s, s.top, 1.0, s.tile))
			if s.thick >= 0.0:
				slopes.append(_slope_row(s, s.top - s.thick, -1.0, s.under))
			if geo.version >= 2:
				# Its sides as true quads (rakes), not strips.
				_slab_rakes(rakes, slab_edges, s, poly, ground)
				continue
		else:
			_add_cap(caps, s.top, s, s.tile)
			if s.thick >= 0.0:
				_add_cap(roof_caps, s.top - s.thick, s, s.under)
		# The sides: each edge of the outline from the underside (or the ground)
		# up to the top, in strips where the top slopes along it.
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			if length < .001:
				continue
			var strips := 1
			if s.sloped():
				var rise := absf(s.top_at(b.x, b.y) - s.top_at(a.x, a.y))
				strips = clampi(int(ceilf(rise / .1)), 1, 64)
			for k in strips:
				var p := a.lerp(b, float(k) / strips)
				var q := a.lerp(b, float(k + 1) / strips)
				var mid := (p + q) * .5
				var top := s.top_at(mid.x, mid.y)
				if s.sloped():
					top = maxf(s.top_at(p.x, p.y), s.top_at(q.x, q.y))
				var bottom := s.bottom_at(mid.x, mid.y)
				if s.thick < 0.0:
					bottom = ground.call(mid.x, mid.y)
				if top - bottom < .005:
					continue
				walls.append_array(
					PackedFloat32Array([p.x, p.y, q.x, q.y, s.edge, s.light, bottom, top, s.area])
				)
				slab_edges[Vector4(p.x, p.y, q.x, q.y)] = s.edge
	for g in geo.segments:
		var length := Vector2(g.bx - g.ax, g.by - g.ay).length()
		if length < .001:
			continue
		if g.half * 2.0 < .2:
			_face_rows(walls, rakes, g, Vector2(g.ax, g.ay), Vector2(g.bx, g.by), g.z1, g.z1b)
			continue
		# A thick wall: its two faces, its ends and (when low) its top.
		var d := Vector2(g.bx - g.ax, g.by - g.ay) / length
		var n := Vector2(-d.y, d.x) * g.half
		var c: Array[Vector2] = [
			Vector2(g.ax, g.ay) - n,
			Vector2(g.bx, g.by) - n,
			Vector2(g.bx, g.by) + n,
			Vector2(g.ax, g.ay) + n
		]
		# Each face's top at its two ends (a raked wall's faces slope with it).
		var tops: Array[float] = [g.z1, g.z1b, g.z1b, g.z1b, g.z1b, g.z1, g.z1, g.z1]
		for i in 4:
			var p: Vector2 = c[i]
			var q: Vector2 = c[(i + 1) % 4]
			_face_rows(walls, rakes, g, p, q, tops[i * 2], tops[i * 2 + 1])
		if g.z1 < 1.5 and not g.raked():
			var key := snappedf(g.z1, .001)
			if not caps.has(key):
				caps[key] = []
			var x0 := minf(minf(c[0].x, c[1].x), minf(c[2].x, c[3].x))
			var x1 := maxf(maxf(c[0].x, c[1].x), maxf(c[2].x, c[3].x))
			var y0 := minf(minf(c[0].y, c[1].y), minf(c[2].y, c[3].y))
			var y1 := maxf(maxf(c[0].y, c[1].y), maxf(c[2].y, c[3].y))
			var row := [x0, y0, x1, y1, g.tile]
			if d.x != 0.0 and d.y != 0.0:
				# An angled wall's top: its box cut down to the wall's band.
				for sign: float in [1.0, -1.0]:
					var nn := Vector2(-d.y, d.x) * sign
					row.append_array([nn.x, nn.y, nn.dot(Vector2(g.ax, g.ay)) + g.half])
			var at_key: Array = caps[key]
			at_key.append(row)
	for c in geo.ceilings:
		var row := [c.x0, c.y0, c.x1, c.y1, c.tile]
		row.append_array(Array(c.cuts))
		var key := snappedf(c.z, .001)
		if not roof_caps.has(key):
			roof_caps[key] = []
		var at_key: Array = roof_caps[key]
		at_key.append(row)
	for lad in geo.ladders:
		walls.append_array(ladder_rows(lad))
	geo.rakes = rakes
	return {"walls": walls, "caps": caps, "roof_caps": roof_caps, "slopes": slopes, "rakes": rakes}


## A sloped slab's sides as rakes: a thick one's each a band from its sloped
## underside to its top; a solid one's cut where the side crosses a cell line
## (the ground under it may step there), each from that cell's ground up.
static func _slab_rakes(
	rakes: PackedFloat32Array,
	slab_edges: Dictionary,
	s: LevelGeometry.Slab,
	poly: PackedVector2Array,
	ground: Callable
) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if a.distance_to(b) < .001:
			continue
		var cuts: Array[float] = [0.0, 1.0]
		if s.thick < 0.0:
			for axis in 2:
				var from := a[axis]
				var to := b[axis]
				if absf(to - from) < 1e-6:
					continue
				for line in range(floori(minf(from, to)) + 1, ceili(maxf(from, to))):
					cuts.append((line - from) / (to - from))
			cuts.sort()
		for k in cuts.size() - 1:
			if cuts[k + 1] - cuts[k] < 1e-6:
				continue
			var p := a.lerp(b, cuts[k])
			var q := a.lerp(b, cuts[k + 1])
			var tp := s.top_at(p.x, p.y)
			var tq := s.top_at(q.x, q.y)
			var bp := tp - s.thick
			var bq := tq - s.thick
			if s.thick < 0.0:
				var mid := (p + q) * .5
				bp = ground.call(mid.x, mid.y)
				bq = bp
				tp = maxf(tp, bp)
				tq = maxf(tq, bq)
				if maxf(tp, tq) - bp < .005:
					continue
			rakes.append_array(
				PackedFloat32Array([p.x, p.y, q.x, q.y, s.edge, s.light, bp, tp, bq, tq, s.area])
			)
			slab_edges[Vector4(p.x, p.y, q.x, q.y)] = s.edge


## A ladder's pieces as wall rows: two square rails from its floor to a
## hand-hold over the top, and a rung every LevelGeometry.RUNG up to the top.
static func ladder_rows(lad: LevelGeometry.Ladder) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := Vector2(lad.dx, lad.dy)
	var side := Vector2(-d.y, d.x)
	var base := Vector2(lad.x, lad.y) - d * .07
	var half := .025
	for s: float in [-1.0, 1.0]:
		var mid := base + side * (.22 * s)
		var c: Array[Vector2] = [
			mid - d * half - side * half,
			mid + d * half - side * half,
			mid + d * half + side * half,
			mid - d * half + side * half
		]
		for i in 4:
			var p: Vector2 = c[i]
			var q: Vector2 = c[(i + 1) % 4]
			out.append_array(
				PackedFloat32Array(
					[p.x, p.y, q.x, q.y, lad.tile, lad.light, lad.z0, lad.z1 + .8, lad.area]
				)
			)
	var a := base - side * .22
	var b := base + side * .22
	var z := lad.z0 + .26
	while z < lad.z1 + .6:
		for k: float in [-half, half]:
			var pa := a + d * k
			var pb := b + d * k
			out.append_array(
				PackedFloat32Array(
					[pa.x, pa.y, pb.x, pb.y, lad.tile, lad.light * .9, z, z + .045, lad.area]
				)
			)
		z += LevelGeometry.RUNG
	return out


## A segment's face from p (top ta) to q (top tb): a wall row for a level
## top, else a rake (a true quad, its top sloping from ta to tb).
static func _face_rows(
	walls: PackedFloat32Array,
	rakes: PackedFloat32Array,
	g: LevelGeometry.Segment,
	p: Vector2,
	q: Vector2,
	ta: float,
	tb: float
) -> void:
	if ta == tb:
		walls.append_array(
			PackedFloat32Array([p.x, p.y, q.x, q.y, g.tile, g.light, g.z0, ta, g.area])
		)
		return
	rakes.append_array(
		PackedFloat32Array([p.x, p.y, q.x, q.y, g.tile, g.light, g.z0, ta, g.z0, tb, g.area])
	)


static func _add_cap(into: Dictionary, z: float, s: LevelGeometry.Slab, tile: int) -> void:
	var key := snappedf(z, .001)
	if not into.has(key):
		into[key] = []
	var row := [s.x0, s.y0, s.x1, s.y1, tile]
	row.append_array(Array(s.cuts))
	var at_key: Array = into[key]
	at_key.append(row)


static func _slope_row(s: LevelGeometry.Slab, z0: float, side: float, tile: int) -> Array:
	var row := [z0, s.gx, s.gy, side, s.x0, s.y0, s.x1, s.y1, tile, s.light, s.area]
	row.append_array(Array(s.cuts))
	return row
