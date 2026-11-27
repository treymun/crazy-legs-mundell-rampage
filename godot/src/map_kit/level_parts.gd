## What the map kit makes, in map coordinates, ready for any level writer:
## cells to open, format-2 geometry (slabs, segments, ceilings, ladders),
## props, glow pools and stations, and per piece what it is (its footprint,
## doorways, floors, roof, test points and cost). KitPiece.build() fills it;
## the level builder (tools/levels/geo_kit.gd kit()) and the map formats copy
## it into a level. Nothing here reads the clock or play's dice: the same
## pieces in the same order give the same parts, byte for byte (hash()).
##
## A piece draws in its own frame (`frame`: local x 0..w, local y 0..d, its
## front on the south side); every call below takes local coordinates and
## writes map ones, snapped to a millimetre, with ids `<piece id>_<part>`.
class_name LevelParts
extends RefCounted

const SNAP := .001
## A doorway's head when nothing says (a door is 1.85 high).
const DOOR_HEAD := 1.85
## A tread rises at most this (LevelGeometry.STEP is .245).
const RISE := .2

## Cells to open: {x0, y0, x1, y1 (cells, both inside), floor ("" keeps the
## map's), light (< 0 keeps), area (< 0 keeps)}.
var cells: Array[Dictionary] = []
var slabs: Array[Dictionary] = []
var segments: Array[Dictionary] = []
var ceilings: Array[Dictionary] = []
var ladders: Array[Dictionary] = []
## {name, x, y, z, signal ("" a town prop; a station id: a quest prop)}.
var props: Array[Dictionary] = []
## {x, y, reach, amount}.
var glows: Array[Dictionary] = []
## {id, x, y, label, message, cue}.
var stations: Array[Dictionary] = []
## One a piece: {id, piece, footprint [x0, y0, x1, y1], doors, floors, roof,
## walk_in, reach, cost, set_piece}.
var pieces: Array[Dictionary] = []
## The map's seed (a source's or player map's hash): looks dice start from it.
var seed := 0
## The map's size in cells (0: unchecked): a piece must stand inside its
## border.
var width := 0
var height := 0

## The piece being drawn.
var frame := KitFrame.new()
var prefix := ""
var area := 0
var _info := {}
var _made := 0


func begin(id: String, kind: String, f: KitFrame, district: int) -> void:
	frame = f
	prefix = id
	area = district
	_made = 0
	var r := f.footprint()
	_info = {
		"id": id,
		"piece": kind,
		"footprint": [_r(r.position.x), _r(r.position.y), _r(r.end.x), _r(r.end.y)],
		"doors": [],
		"floors": [],
		"roof": {},
		"walk_in": [],
		"reach": [],
		"cost": 0,
		"front": f.dir("s"),
	}


func finish() -> Dictionary:
	_info["cost"] = _made
	pieces.append(_info)
	var out := _info
	_info = {}
	return out


## Dice for looks only, the same for the same piece id on the same map.
func dice(salt := "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%d" % [prefix, salt, seed])
	return rng


static func _r(value: float) -> float:
	return snappedf(value, SNAP)


func _id(part: String) -> String:
	return prefix + "_" + part


# ------------------------------------------------------------ what a piece says


## A doorway (local middle `at` on its wall line, facing out `face`, its sill
## z): the review, the automap and the kit check read these. `hung` is false:
## an open doorway (T4 hangs doors in them).
func doorway(
	part: String,
	at: Vector2,
	face: String,
	z: float,
	width: float,
	head: float,
	walk := true,
	reach := 1.1
) -> void:
	var out_dir: Vector2 = KitFrame.DIRS.get(face, Vector2.ZERO)
	var a := frame.p(at)
	var outside := frame.p(at + out_dir * reach)
	var inside := frame.p(at - out_dir * reach)
	var doors: Array = _info["doors"]
	(
		doors
		. append(
			{
				"id": _id(part),
				"at": [_r(a.x), _r(a.y)],
				"face": frame.dir(face),
				"z": _r(z),
				"width": _r(width),
				"head": _r(head),
				"hung": false,
			}
		)
	)
	if not walk:
		return
	var walks: Array = _info["walk_in"]
	(
		walks
		. append(
			{
				"door": _id(part),
				"from": [_r(outside.x), _r(outside.y), _r(z)],
				"to": [_r(inside.x), _r(inside.y), _r(z)],
			}
		)
	)


## A floor a body stands on (local point on it, its height): reach is the kit
## check's "can the yard walk here" (false: a floor not meant to be reached).
func floor_at(part: String, at: Vector2, z: float, reach := true) -> void:
	var q := frame.p(at)
	var floors: Array = _info["floors"]
	floors.append({"id": _id(part), "at": [_r(q.x), _r(q.y)], "z": _r(z)})
	if reach:
		var list: Array = _info["reach"]
		list.append({"id": _id(part), "at": [_r(q.x), _r(q.y), _r(z)]})


## The roof's top (a local point on it): reach true when it is meant to be
## climbed onto.
func roof_at(at: Vector2, z: float, reach: bool, kind: String) -> void:
	var q := frame.p(at)
	_info["roof"] = {"kind": kind, "at": [_r(q.x), _r(q.y)], "z": _r(z), "reach": reach}
	if reach:
		var list: Array = _info["reach"]
		list.append({"id": _id("roof"), "at": [_r(q.x), _r(q.y), _r(z)]})


func note(key: String, value: Variant) -> void:
	_info[key] = value


# ------------------------------------------------------------------- the cells


## Open the local cells [x0, x1) x [y0, y1) (whole numbers): floor "" keeps
## the map's floor, light or district < 0 keep the map's.
func open(local: Rect2, floor_tile := "", light := -1.0, district := -1) -> void:
	var r := frame.rect(local)
	(
		cells
		. append(
			{
				"x0": roundi(r.position.x),
				"y0": roundi(r.position.y),
				"x1": roundi(r.end.x) - 1,
				"y1": roundi(r.end.y) - 1,
				"floor": floor_tile,
				"light": _r(light),
				"area": district,
			}
		)
	)


# ------------------------------------------------------------------ geometry


## A slab over local `local`, its top `top` at the local north-west corner
## rising gx, gy a unit (local); cut by local lines (Vector3 nx, ny, c).
## look: tile, under, edge, light; thick < 0 solid to the ground.
func slab(
	part: String,
	local: Rect2,
	top: float,
	thick: float,
	look: Dictionary,
	slope := Vector2.ZERO,
	cut_lines: Array[Vector3] = [],
	walk := true,
	kind := "deck"
) -> void:
	var r := frame.rect(local)
	var g := frame.v(slope)
	# The plane's height at the map rectangle's north-west corner.
	var p0 := frame.p(local.position)
	var at := top + g.dot(r.position - p0)
	var tile: String = look.get("tile", "porch")
	var under: String = look.get("under", "ceiling")
	var edge: String = look.get("edge", tile)
	var light: float = look.get("light", .85)
	var s := {
		"id": _id(part),
		"kind": kind,
		"x0": _r(r.position.x),
		"y0": _r(r.position.y),
		"x1": _r(r.end.x),
		"y1": _r(r.end.y),
		"top": _r(at),
		"thick": _r(thick),
		"tile": tile,
		"under": under,
		"edge": edge,
		"light": snappedf(light, .0001),
		"area": area,
	}
	if g.x != 0.0:
		s["gx"] = snappedf(g.x, .0001)
	if g.y != 0.0:
		s["gy"] = snappedf(g.y, .0001)
	if not cut_lines.is_empty():
		var list: Array = []
		for c: Vector3 in cut_lines:
			var m := frame.cut(c)
			list.append([snappedf(m.x, .0001), snappedf(m.y, .0001), _r(m.z)])
		s["cuts"] = list
	if not walk:
		s["walk"] = false
	slabs.append(s)
	_made += 1


## A box standing on z0 (solid to the ground when z0 is 0), top `top`: a
## counter, a pew, a bale, a chimney stack, a plinth.
func block(part: String, local: Rect2, z0: float, top: float, side: String, cap: String) -> void:
	var thick := -1.0 if z0 <= 0.0 else top - z0
	slab(
		part,
		local,
		top,
		thick,
		{"tile": cap, "under": side, "edge": side},
		Vector2.ZERO,
		[],
		true,
		"block"
	)


## A ramp from z0 to z1 rising toward local `toward` (n e s w) over `local`.
func ramp(
	part: String,
	local: Rect2,
	z0: float,
	z1: float,
	toward: String,
	look: Dictionary,
	thick := -1.0
) -> void:
	var rise := z1 - z0
	var slope := Vector2.ZERO
	var top := z0
	match toward:
		"e":
			slope.x = rise / local.size.x
		"w":
			slope.x = -rise / local.size.x
			top = z1
		"s":
			slope.y = rise / local.size.y
		_:
			slope.y = -rise / local.size.y
			top = z1
	slab(part, local, top, thick, look, slope, [], true, "ramp")


## Stairs from z0 up to z1 toward local `toward` across `local`: treads RISE
## high at most, solid down to the ground unless thick >= 0. Returns the count.
func stairs(
	part: String,
	local: Rect2,
	z0: float,
	z1: float,
	toward: String,
	look: Dictionary,
	thick := -1.0
) -> int:
	var n := maxi(1, ceili((z1 - z0) / RISE - .001))
	var along_x := toward == "e" or toward == "w"
	var run := local.size.x if along_x else local.size.y
	var x0 := local.position.x
	var y0 := local.position.y
	var x1 := local.end.x
	var y1 := local.end.y
	for k in n:
		var a := run * k / n
		var c := run * (k + 1) / n
		var tread: Rect2
		match toward:
			"e":
				tread = Rect2(x0 + a, y0, c - a, y1 - y0)
			"w":
				tread = Rect2(x1 - c, y0, c - a, y1 - y0)
			"s":
				tread = Rect2(x0, y0 + a, x1 - x0, c - a)
			_:
				tread = Rect2(x0, y1 - c, x1 - x0, c - a)
		var top := z0 + (z1 - z0) * (k + 1) / n
		slab("%s_%d" % [part, k + 1], tread, top, thick, look, Vector2.ZERO, [], true, "stair")
	return n


## A ceiling over `local` at z.
func ceiling(part: String, local: Rect2, z: float, tile: String, light := .8) -> void:
	var r := frame.rect(local)
	(
		ceilings
		. append(
			{
				"id": _id(part),
				"x0": _r(r.position.x),
				"y0": _r(r.position.y),
				"x1": _r(r.end.x),
				"y1": _r(r.end.y),
				"z": _r(z),
				"tile": tile,
				"light": snappedf(light, .0001),
				"area": area,
			}
		)
	)
	_made += 1


## One straight piece of wall from a to b (local), z0 up to z1 (z1b at b when
## raked). look: tile, light, thick, sight, shots.
func segment(
	part: String, a: Vector2, b: Vector2, z0: float, z1: float, look: Dictionary, z1b := NAN
) -> void:
	var p := frame.p(a)
	var q := frame.p(b)
	var tile: String = look.get("tile", "plaster")
	var thick: float = look.get("thick", .12)
	var light: float = look.get("light", .85)
	var s := {
		"id": _id(part),
		"a": [_r(p.x), _r(p.y)],
		"b": [_r(q.x), _r(q.y)],
		"z0": _r(z0),
		"z1": _r(z1),
		"thick": _r(thick),
		"tile": tile,
		"light": snappedf(light, .0001),
		"area": area,
	}
	if not is_nan(z1b) and absf(z1b - z1) > SNAP * .5:
		s["z1b"] = _r(z1b)
	var sight: bool = look.get("sight", true)
	if not sight:
		s["sight"] = false
	if look.has("shots"):
		var shots: bool = look["shots"]
		s["shots"] = shots
	segments.append(s)
	_made += 1


## A post (a short square segment) at local `at`, z0 to z1.
func post(part: String, at: Vector2, z0: float, z1: float, tile: String, size := .16) -> void:
	var half := size * .5
	segment(
		part, at + Vector2(-half, 0), at + Vector2(half, 0), z0, z1, {"tile": tile, "thick": size}
	)


## A wall from a to b (local) from z0 to z1 with openings cut to size: each
## {at (distance from a to its middle), width, sill (0 a doorway), head}.
## Openings over one another (a storey's windows over the one below, a hay
## door over the big door) are cut by columns. Returns the pieces made.
func wall(
	part: String,
	a: Vector2,
	b: Vector2,
	z0: float,
	z1: float,
	look: Dictionary,
	openings: Array[Dictionary] = []
) -> int:
	var length := a.distance_to(b)
	var way := (b - a) / maxf(length, 1e-6)
	var holes: Array[Vector4] = []
	for hole: Dictionary in openings:
		var width: float = hole.get("width", 1.0)
		var mid: float = hole["at"]
		var sill: float = hole.get("sill", z0)
		var head: float = hole.get("head", sill + DOOR_HEAD)
		holes.append(
			Vector4(maxf(0.0, mid - width * .5), minf(length, mid + width * .5), sill, head)
		)
	holes.sort_custom(func(p: Vector4, q: Vector4) -> bool: return p.x < q.x)
	var before := _made
	var k := 0
	# Columns: every opening's ends cut the length; each column solid from z0
	# to z1 but for the openings over it.
	var cuts: Array[float] = [0.0, length]
	for hole in holes:
		cuts.append(hole.x)
		cuts.append(hole.y)
	cuts.sort()
	if holes.is_empty():
		segment(part, a, b, z0, z1, look)
		return 1
	for i in range(cuts.size() - 1):
		var u := cuts[i]
		var w := cuts[i + 1]
		if w - u < SNAP:
			continue
		var gaps: Array[Vector2] = []
		for hole in holes:
			if hole.x <= u + SNAP and hole.y >= w - SNAP:
				gaps.append(Vector2(hole.z, hole.w))
		gaps.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var low := z0
		for gap in gaps:
			if gap.x > low + SNAP:
				segment("%s_%d" % [part, k], a + way * u, a + way * w, low, gap.x, look)
				k += 1
			low = maxf(low, gap.y)
		if z1 > low + SNAP:
			segment("%s_%d" % [part, k], a + way * u, a + way * w, low, z1, look)
			k += 1
	return _made - before


## A ladder leaning on a face whose line is at local (x, y), climbed facing
## local `facing`, from z0 to the floor at z1 beyond the face; moved along
## the face to the middle of its cell.
func ladder(
	part: String, at: Vector2, facing: String, z0: float, z1: float, tile := "porch"
) -> void:
	# Along its face, in the middle of a cell (the nav graph joins cells).
	var spot := at
	if facing == "n" or facing == "s":
		spot.x = floorf(at.x) + .5
	else:
		spot.y = floorf(at.y) + .5
	var q := frame.p(spot)
	(
		ladders
		. append(
			{
				"id": _id(part),
				"x": _r(q.x),
				"y": _r(q.y),
				"dir": frame.dir(facing),
				"z0": _r(z0),
				"z1": _r(z1),
				"tile": tile,
				"light": .85,
				"area": area,
			}
		)
	)
	_made += 1


# --------------------------------------------------------------- what is in it


## A town prop (assets/art/town_props.json) at local `at`, z up; signal: a
## station id makes it a quest prop (town_<name>_off until done).
func prop(name: String, at: Vector2, z := 0.0, signal_name := "") -> void:
	var q := frame.p(at)
	props.append(
		{
			"name": name,
			"x": snappedf(q.x, .01),
			"y": snappedf(q.y, .01),
			"z": _r(z),
			"signal": signal_name
		}
	)
	_made += 1


func glow(at: Vector2, reach: float, amount: float) -> void:
	var q := frame.p(at)
	glows.append(
		{"x": snappedf(q.x, .01), "y": snappedf(q.y, .01), "reach": reach, "amount": amount}
	)


func station(
	part: String, at: Vector2, label: String, message: String, cue := "lever_clunk"
) -> String:
	var q := frame.p(at)
	var sid := _id(part)
	stations.append(
		{
			"id": sid,
			"x": snappedf(q.x, .01),
			"y": snappedf(q.y, .01),
			"label": label,
			"message": message,
			"cue": cue
		}
	)
	return sid


## Where every list stands now (rollback() puts them back: a refused piece
## leaves nothing behind).
func mark() -> Array[int]:
	return [
		cells.size(),
		slabs.size(),
		segments.size(),
		ceilings.size(),
		ladders.size(),
		props.size(),
		glows.size(),
		stations.size(),
		pieces.size()
	]


func rollback(at: Array[int]) -> void:
	cells.resize(at[0])
	slabs.resize(at[1])
	segments.resize(at[2])
	ceilings.resize(at[3])
	ladders.resize(at[4])
	props.resize(at[5])
	glows.resize(at[6])
	stations.resize(at[7])
	pieces.resize(at[8])


# ---------------------------------------------------------------- the result


## The geometry block's lists (a level writer adds its version).
func geometry() -> Dictionary:
	return {"slabs": slabs, "segments": segments, "ceilings": ceilings, "ladders": ladders}


func to_dict() -> Dictionary:
	return {
		"cells": cells,
		"geometry": geometry(),
		"props": props,
		"glows": glows,
		"stations": stations,
		"pieces": pieces,
	}


## Pieces of geometry made (what a map's budget counts).
func cost() -> int:
	return slabs.size() + segments.size() + ceilings.size() + ladders.size() + props.size()


## The same parts give the same text, so the same hash on every machine.
func hash_text() -> String:
	return JSON.stringify(to_dict(), "", true).md5_text()
