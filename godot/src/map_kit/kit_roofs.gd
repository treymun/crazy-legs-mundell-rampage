## Roofs of sloped slabs over a rectangle of wall lines (local, a piece's
## frame): gable, hip, shed (lean-to), gambrel, quonset, cone and flat with a
## parapet. A roof's underside sits on the walls at `eave`; a slope up to 1 in
## 1 is walked on, a steeper face (a gambrel's lower slope, a steeple) is a
## face nobody stands on (geometry version 2). The end walls under a roof
## (gables) are raked segments up under it. Each returns {top (its highest
## top), at (a local point on a part walked on), walk (bool)}.
class_name KitRoofs
extends RefCounted

const KINDS := ["gable", "hip", "shed", "gambrel", "quonset", "cone", "flat"]
## A cone's or a round roof's facets.
const FACETS := 16


## The "roof" bit: a roof of o.kind over the piece's whole footprint.
static func piece(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var kind: String = o["kind"]
	var eave: float = o["eave"]
	var pitch: float = o["pitch"]
	var ends: bool = o["ends"]
	var r := Rect2(0, 0, w, d)
	var made := over(parts, "roof", kind, r, eave, pitch, look, {"ends": ends})
	var at: Vector2 = made["at"]
	var top: float = made["top"]
	var walk: bool = made["walk"]
	parts.roof_at(at, _top_at(made, at), walk and eave <= .1, kind)
	parts.note("ridge", top)


## A roof of `kind` over local `r` (the wall lines): o.overhang, o.rake,
## o.ends (end walls, true), o.thick, o.along ("u" the ridge along local x,
## "v" along y; default the longer side).
static func over(
	parts: LevelParts,
	part: String,
	kind: String,
	r: Rect2,
	eave: float,
	pitch: float,
	look: Dictionary,
	o := {}
) -> Dictionary:
	match kind:
		"hip":
			return hip(parts, part, r, eave, pitch, look, o)
		"shed":
			return shed(parts, part, r, eave, pitch, look, o)
		"gambrel":
			return gambrel(parts, part, r, eave, look, o)
		"quonset":
			return quonset(parts, part, r, eave, pitch, look, o)
		"cone":
			var c := r.get_center()
			var radius := minf(r.size.x, r.size.y) * .5
			return cone(parts, part, c, radius, eave, pitch, look, o)
		"flat":
			return flat(parts, part, r, eave, look, o)
	return gable(parts, part, r, eave, pitch, look, o)


static func _along_x(r: Rect2, o: Dictionary) -> bool:
	var along: String = o.get("along", "")
	if along == "u":
		return true
	if along == "v":
		return false
	return r.size.x >= r.size.y


## The roof's look: its top, underside and edge.
static func _skin(look: Dictionary) -> Dictionary:
	var roof: String = look.get("roof", "tin")
	var under: String = look.get("under", "joists")
	var trim: String = look.get("trim", roof)
	return {"tile": roof, "under": under, "edge": trim, "light": .85}


## (u, v) -> local: u runs along the ridge, v across it.
static func _p(along_x: bool, u: float, v: float) -> Vector2:
	return Vector2(u, v) if along_x else Vector2(v, u)


static func _rect(along_x: bool, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var a := _p(along_x, u0, v0)
	var b := _p(along_x, u1, v1)
	return Rect2(a.min(b), (b - a).abs())


static func _cut(along_x: bool, nu: float, nv: float, c: float) -> Vector3:
	return Vector3(nu, nv, c) if along_x else Vector3(nv, nu, c)


static func _top_at(made: Dictionary, _at: Vector2) -> float:
	var walk_top: float = made.get("walk_top", made["top"])
	return walk_top


## Two slopes meeting at a ridge, the gable ends raked up under them.
static func gable(
	parts: LevelParts, part: String, r: Rect2, eave: float, pitch: float, look: Dictionary, o := {}
) -> Dictionary:
	var ax := _along_x(r, o)
	var u0 := r.position.x if ax else r.position.y
	var u1 := r.end.x if ax else r.end.y
	var v0 := r.position.y if ax else r.position.x
	var v1 := r.end.y if ax else r.end.x
	var hang: float = o.get("overhang", KitPiece.num("overhang"))
	var rake: float = o.get("rake", 0.0)
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var skin := _skin(look)
	var mid := (v0 + v1) * .5
	var at_wall := eave + thick
	var ridge := at_wall + (mid - v0) * pitch
	var low := at_wall - hang * pitch
	var walk := pitch <= 1.0
	parts.slab(
		part + "_a",
		_rect(ax, u0 - rake, v0 - hang, u1 + rake, mid),
		low,
		thick,
		skin,
		_p(ax, 0, pitch),
		[],
		walk
	)
	parts.slab(
		part + "_b",
		_rect(ax, u0 - rake, mid, u1 + rake, v1 + hang),
		ridge,
		thick,
		skin,
		_p(ax, 0, -pitch),
		[],
		walk
	)
	var ends: bool = o.get("ends", true)
	if ends:
		var inset := KitPiece.num("wall") * .5
		var wl := {"tile": look.get("wall", "barn"), "thick": KitPiece.num("wall")}
		for side in 2:
			var u := u0 + inset if side == 0 else u1 - inset
			parts.segment(
				"%s_end%d_a" % [part, side],
				_p(ax, u, v0),
				_p(ax, u, mid),
				eave,
				eave,
				wl,
				ridge - thick
			)
			parts.segment(
				"%s_end%d_b" % [part, side],
				_p(ax, u, v1),
				_p(ax, u, mid),
				eave,
				eave,
				wl,
				ridge - thick
			)
	var at := _p(ax, (u0 + u1) * .5, mid)
	return {"top": ridge, "at": at, "walk": walk, "walk_top": ridge}


## Four slopes: two long ones to a ridge, two hip ends (a square: a pyramid).
static func hip(
	parts: LevelParts, part: String, r: Rect2, eave: float, pitch: float, look: Dictionary, o := {}
) -> Dictionary:
	var ax := _along_x(r, o)
	var u0 := r.position.x if ax else r.position.y
	var u1 := r.end.x if ax else r.end.y
	var v0 := r.position.y if ax else r.position.x
	var v1 := r.end.y if ax else r.end.x
	var hang: float = o.get("overhang", KitPiece.num("overhang"))
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var skin := _skin(look)
	var half := (v1 - v0) * .5
	var mid := v0 + half
	var at_wall := eave + thick
	var ridge := at_wall + half * pitch
	var low := at_wall - hang * pitch
	var walk := pitch <= 1.0
	var n_cuts: Array[Vector3] = [_cut(ax, -1, 1, v0 - u0), _cut(ax, 1, 1, u1 + v0)]
	var s_cuts: Array[Vector3] = [_cut(ax, -1, -1, -u0 - v1), _cut(ax, 1, -1, u1 - v1)]
	var w_cuts: Array[Vector3] = [_cut(ax, 1, -1, u0 - v0), _cut(ax, 1, 1, u0 + v1)]
	var e_cuts: Array[Vector3] = [_cut(ax, -1, -1, -u1 - v0), _cut(ax, -1, 1, v1 - u1)]
	parts.slab(
		part + "_a",
		_rect(ax, u0 - hang, v0 - hang, u1 + hang, mid),
		low,
		thick,
		skin,
		_p(ax, 0, pitch),
		n_cuts,
		walk
	)
	parts.slab(
		part + "_b",
		_rect(ax, u0 - hang, mid, u1 + hang, v1 + hang),
		ridge,
		thick,
		skin,
		_p(ax, 0, -pitch),
		s_cuts,
		walk
	)
	parts.slab(
		part + "_c",
		_rect(ax, u0 - hang, v0 - hang, u0 + half, v1 + hang),
		low,
		thick,
		skin,
		_p(ax, pitch, 0),
		w_cuts,
		walk
	)
	parts.slab(
		part + "_d",
		_rect(ax, u1 - half, v0 - hang, u1 + hang, v1 + hang),
		ridge,
		thick,
		skin,
		_p(ax, -pitch, 0),
		e_cuts,
		walk
	)
	var at := _p(ax, (u0 + u1) * .5, mid - .2)
	return {"top": ridge, "at": at, "walk": walk, "walk_top": ridge - .2 * pitch}


## One slope, high at the local north (the back) wall line, low at the south:
## the side walls raked under it, the back wall built up to it.
static func shed(
	parts: LevelParts, part: String, r: Rect2, eave: float, pitch: float, look: Dictionary, o := {}
) -> Dictionary:
	var hang: float = o.get("overhang", KitPiece.num("overhang"))
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var skin := _skin(look)
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	var span := y1 - y0
	var at_low := eave + thick
	var high := at_low + span * pitch
	var walk := pitch <= 1.0
	parts.slab(
		part + "_a",
		Rect2(x0 - hang, y0 - hang, x1 - x0 + hang * 2, span + hang * 2),
		high + hang * pitch,
		thick,
		skin,
		Vector2(0, -pitch),
		[],
		walk
	)
	var ends: bool = o.get("ends", true)
	if ends:
		var inset := KitPiece.num("wall") * .5
		var wl := {"tile": look.get("wall", "barn"), "thick": KitPiece.num("wall")}
		parts.segment(
			part + "_end_w",
			Vector2(x0 + inset, y1),
			Vector2(x0 + inset, y0),
			eave,
			eave,
			wl,
			high - thick
		)
		parts.segment(
			part + "_end_e",
			Vector2(x1 - inset, y1),
			Vector2(x1 - inset, y0),
			eave,
			eave,
			wl,
			high - thick
		)
		parts.segment(
			part + "_end_n",
			Vector2(x0, y0 + inset),
			Vector2(x1, y0 + inset),
			eave,
			high - thick,
			wl
		)
	return {
		"top": high,
		"at": Vector2((x0 + x1) * .5, (y0 + y1) * .5),
		"walk": walk,
		"walk_top": at_low + span * .5 * pitch
	}


## A barn's roof: a steep lower slope (not walked on) to a knee each side, a
## shallow upper one to the ridge; the gable ends follow it in four rakes.
static func gambrel(
	parts: LevelParts, part: String, r: Rect2, eave: float, look: Dictionary, o := {}
) -> Dictionary:
	var ax := _along_x(r, o)
	var u0 := r.position.x if ax else r.position.y
	var u1 := r.end.x if ax else r.end.y
	var v0 := r.position.y if ax else r.position.x
	var v1 := r.end.y if ax else r.end.x
	var hang: float = o.get("overhang", KitPiece.num("overhang"))
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var steep: float = o.get("steep", 1.9)
	var shallow: float = o.get("shallow", .55)
	var skin := _skin(look)
	var half := (v1 - v0) * .5
	var mid := v0 + half
	var knee := half * .32
	var at_wall := eave + thick
	var knee_top := at_wall + knee * steep
	var ridge := knee_top + (half - knee) * shallow
	var low := at_wall - hang * steep
	parts.slab(
		part + "_a",
		_rect(ax, u0, v0 - hang, u1, v0 + knee),
		low,
		thick,
		skin,
		_p(ax, 0, steep),
		[],
		false
	)
	parts.slab(
		part + "_b",
		_rect(ax, u0, v0 + knee, u1, mid),
		knee_top,
		thick,
		skin,
		_p(ax, 0, shallow),
		[],
		true
	)
	parts.slab(
		part + "_c",
		_rect(ax, u0, mid, u1, v1 - knee),
		ridge,
		thick,
		skin,
		_p(ax, 0, -shallow),
		[],
		true
	)
	parts.slab(
		part + "_d",
		_rect(ax, u0, v1 - knee, u1, v1 + hang),
		knee_top,
		thick,
		skin,
		_p(ax, 0, -steep),
		[],
		false
	)
	var ends: bool = o.get("ends", true)
	if ends:
		var inset := KitPiece.num("wall") * .5
		var wl := {"tile": look.get("wall", "barn"), "thick": KitPiece.num("wall")}
		for side in 2:
			var u := u0 + inset if side == 0 else u1 - inset
			var k := "%s_end%d" % [part, side]
			parts.segment(
				k + "_a", _p(ax, u, v0), _p(ax, u, v0 + knee), eave, eave, wl, knee_top - thick
			)
			parts.segment(
				k + "_b",
				_p(ax, u, v0 + knee),
				_p(ax, u, mid),
				knee_top - thick,
				knee_top - thick,
				wl,
				ridge - thick
			)
			parts.segment(
				k + "_c", _p(ax, u, v1), _p(ax, u, v1 - knee), eave, eave, wl, knee_top - thick
			)
			parts.segment(
				k + "_d",
				_p(ax, u, v1 - knee),
				_p(ax, u, mid),
				knee_top - thick,
				knee_top - thick,
				wl,
				ridge - thick
			)
			# The block under the upper rakes, from the eave to the knee.
			parts.segment(
				k + "_e", _p(ax, u, v0 + knee), _p(ax, u, v1 - knee), eave, knee_top - thick, wl
			)
	return {"top": ridge, "at": _p(ax, (u0 + u1) * .5, mid), "walk": true, "walk_top": ridge}


## A round-topped roof (a quonset hut's) in facets across the span; the end
## walls follow it.
static func quonset(
	parts: LevelParts, part: String, r: Rect2, eave: float, pitch: float, look: Dictionary, o := {}
) -> Dictionary:
	var ax := _along_x(r, o)
	var u0 := r.position.x if ax else r.position.y
	var u1 := r.end.x if ax else r.end.y
	var v0 := r.position.y if ax else r.position.x
	var v1 := r.end.y if ax else r.end.x
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var skin := _skin(look)
	var half := (v1 - v0) * .5
	var mid := v0 + half
	var rise := half * clampf(pitch * 1.6, .3, 1.0)
	var n := 6
	var ends: bool = o.get("ends", true)
	var inset := KitPiece.num("wall") * .5
	var wl := {"tile": look.get("wall", "barn"), "thick": KitPiece.num("wall")}
	for k in n:
		var a0 := PI * k / n
		var a1 := PI * (k + 1) / n
		var va := mid - half * cos(a0)
		var vb := mid - half * cos(a1)
		var za := eave + thick + rise * sin(a0)
		var zb := eave + thick + rise * sin(a1)
		var slope := clampf((zb - za) / (vb - va), -4.0, 4.0)
		parts.slab(
			"%s_%d" % [part, k],
			_rect(ax, u0, va, u1, vb),
			za,
			thick,
			skin,
			_p(ax, 0, slope),
			[],
			absf(slope) <= 1.0
		)
		if ends:
			for side in 2:
				var u := u0 + inset if side == 0 else u1 - inset
				parts.segment(
					"%s_end%d_%d" % [part, side, k],
					_p(ax, u, va),
					_p(ax, u, vb),
					eave,
					maxf(eave, za - thick),
					wl,
					maxf(eave, zb - thick)
				)
	return {
		"top": eave + thick + rise,
		"at": _p(ax, (u0 + u1) * .5, mid),
		"walk": true,
		"walk_top": eave + thick + rise
	}


## A cone of FACETS faces over a circle (a silo's, a bin's, a steeple's
## round): `pitch` up a unit in, from the wall line at `eave`.
static func cone(
	parts: LevelParts,
	part: String,
	c: Vector2,
	radius: float,
	eave: float,
	pitch: float,
	look: Dictionary,
	o := {}
) -> Dictionary:
	var hang: float = o.get("overhang", .15)
	var thick: float = o.get("thick", KitPiece.num("roof_thick"))
	var facets: int = o.get("facets", FACETS)
	var skin := _skin(look)
	var half_angle := PI / facets
	var apothem := radius * cos(half_angle)
	var apex := eave + thick + pitch * apothem
	var reach := radius + hang
	var walk := pitch <= 1.0
	for k in facets:
		var t0 := TAU * k / facets
		var t1 := TAU * (k + 1) / facets
		var tm := (t0 + t1) * .5
		var um := Vector2.from_angle(tm)
		var p0 := c + Vector2.from_angle(t0) * reach
		var p1 := c + Vector2.from_angle(t1) * reach
		var lo := c.min(p0).min(p1)
		var hi := c.max(p0).max(p1)
		var box := Rect2(lo, hi - lo)
		if box.size.x < .01 or box.size.y < .01:
			box = box.grow(.01)
		var cuts: Array[Vector3] = []
		for t: float in [t0, t1]:
			var e := Vector2.from_angle(t)
			var nrm := Vector2(-e.y, e.x)
			if nrm.dot(um) > 0.0:
				nrm = -nrm
			cuts.append(Vector3(nrm.x, nrm.y, nrm.dot(c)))
		cuts.append(Vector3(um.x, um.y, um.dot(c) + reach * cos(half_angle)))
		var grad := -um * pitch
		var top := apex + grad.dot(box.position - c)
		parts.slab("%s_%d" % [part, k], box, top, thick, skin, grad, cuts, walk)
	return {
		"top": apex,
		"at": c + Vector2(radius * .5, 0),
		"walk": walk,
		"walk_top": apex - pitch * radius * .5
	}


## A flat deck over the walls with a low parapet round it (o.ends: the
## parapet; o.open: sides left without one, "nesw" letters).
static func flat(
	parts: LevelParts, part: String, r: Rect2, eave: float, look: Dictionary, o := {}
) -> Dictionary:
	var thick: float = o.get("thick", .2)
	var skin := _skin(look)
	skin["tile"] = look.get("flat", "tin")
	var top := eave + thick
	parts.slab(part + "_a", r, top, thick, skin)
	var ends: bool = o.get("ends", true)
	if ends:
		var open: String = o.get("open", "")
		var high: float = o.get("parapet", .6)
		var inset := KitPiece.num("wall") * .5
		var wl := {"tile": look.get("wall", "barn"), "thick": KitPiece.num("wall")}
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		var sides := {
			"n": [Vector2(x0, y0 + inset), Vector2(x1, y0 + inset)],
			"e": [Vector2(x1 - inset, y0), Vector2(x1 - inset, y1)],
			"s": [Vector2(x0, y1 - inset), Vector2(x1, y1 - inset)],
			"w": [Vector2(x0 + inset, y0), Vector2(x0 + inset, y1)],
		}
		for side: String in ["n", "e", "s", "w"]:
			if open.contains(side):
				continue
			var ends_at: Array = sides[side]
			var a: Vector2 = ends_at[0]
			var b: Vector2 = ends_at[1]
			parts.segment("%s_parapet_%s" % [part, side], a, b, top, top + high, wl)
	return {"top": top, "at": r.get_center(), "walk": true, "walk_top": top}
