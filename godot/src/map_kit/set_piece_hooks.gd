## Set-piece hooks (pass 16, LOOKS): a map may stand the chapters' big breaks
## (features/set_pieces.gd: a pole barn that comes down, a water tower that
## goes over and floods, a fuel line that leaks and burns), as data only: the
## spec joins the level's "set_pieces" list and the game builds and plays it
## as it does the chapters' (sizes and numbers in data/tuning/set_pieces.cfg).
##
##   {"type": "set_piece", "kind": "barn", "id": "hay_shed", "at": [30.5, 12.6],
##    "turn": 2, "falls": [0, 1]}
##   {"type": "set_piece", "kind": "tower", "id": "tank", "at": [44.5, 20.5], "falls": [0, 3]}
##   {"type": "set_piece", "kind": "fuel", "id": "line", "points": [[10, 30], [18, 30]],
##    "pumps": [[10.6, 29.4]]}
##
## `falls` are the ways it may go over (0 east, 1 south, 2 west, 3 north):
## away from walls and the way. Its footprint must be open floor clear of the
## start, the doors and the objectives; a fall that would land on a wall says
## set_piece_fall. Breaking things needs no hook: a wall in a _win tile has
## windows that shatter, plank and fence tiles break as the chapters' do, and
## a prop whose picture breakables.cfg lists (barrels, coolers, crates...)
## breaks wherever it stands, a vignette's included. tools/set_piece_check.gd
## -- <level> brings a map's set pieces down every way and walks it again.
class_name MapSetPieces
extends RefCounted

const KINDS := ["barn", "tower", "fuel"]
## How far past its footprint a fall reaches (cells), by kind.
const REACH := {"barn": 2.5, "tower": 6.5}
## Keys a spec may carry on to the game as they are.
const PASSED := ["w", "d", "eave", "wall_tile", "roof_tile", "sign", "sign_face", "walls"]


## Add one set piece. Returns {"problems": [[code, line]...]}; a piece with a
## MUST problem (set_piece_kind, set_piece_spot) is not added.
static func add(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var problems: Array = []
	var kind := str(spec.get("kind", ""))
	var id := str(spec.get("id", "set_piece%d" % _count(grid.level)))
	if not KINDS.has(kind):
		problems.append(["set_piece_kind", "%s: kind must be barn, tower or fuel" % id])
		return {"problems": problems}
	var out := {"kind": kind, "id": id}
	var falls: Array = []
	for f: Variant in spec.get("falls", [0, 1, 2, 3]):
		var way := int(MapLooksGrid.f(f))
		if way >= 0 and way <= 3 and not falls.has(way):
			falls.append(way)
	if kind == "fuel":
		var points: Array = spec.get("points", []) if spec.get("points") is Array else []
		var pumps: Array = spec.get("pumps", []) if spec.get("pumps") is Array else []
		if points.size() < 2:
			problems.append(["set_piece_spot", "%s: a fuel line wants two points or more" % id])
			return {"problems": problems}
		var clean: Array = []
		for item: Variant in points:
			var pair: Array = item if item is Array else [0, 0]
			var p := Vector2(MapLooksGrid.f(pair[0]), MapLooksGrid.f(pair[1]))
			if not _open(grid, p):
				problems.append(
					["set_piece_spot", "%s: the line runs through a wall at %s" % [id, p]]
				)
				return {"problems": problems}
			clean.append([snappedf(p.x, .01), snappedf(p.y, .01)])
		var pump_list: Array = []
		for item: Variant in pumps:
			var pair: Array = item if item is Array else [0, 0]
			pump_list.append(
				[snappedf(MapLooksGrid.f(pair[0]), .01), snappedf(MapLooksGrid.f(pair[1]), .01)]
			)
		out["x"] = clean[0][0]
		out["y"] = clean[0][1]
		out["points"] = clean
		out["pumps"] = pump_list
	else:
		var at: Array = spec.get("at", []) if spec.get("at") is Array else []
		if at.size() < 2:
			problems.append(["set_piece_spot", "%s: wants at [x, y]" % id])
			return {"problems": problems}
		var p := Vector2(MapLooksGrid.f(at[0]), MapLooksGrid.f(at[1]))
		var turn := posmod(int(MapLooksGrid.f(spec.get("turn", 0))), 4)
		var foot := footprint(kind, p, turn, spec)
		for y in range(floori(foot.position.y), ceili(foot.end.y)):
			for x in range(floori(foot.position.x), ceili(foot.end.x)):
				var c := y * grid.w + x
				if not grid.inside(x, y) or not grid.is_open(c) or grid.roof[c] > 0.0:
					problems.append(
						[
							"set_piece_spot",
							"%s: its footprint is not all open ground under the sky" % id
						]
					)
					return {"problems": problems}
				if grid.kept(x + .5, y + .5, -.5):
					problems.append(
						[
							"set_piece_spot",
							"%s: its footprint covers the start, a door or an objective" % id
						]
					)
					return {"problems": problems}
		var reach: float = REACH[kind]
		for way: int in falls:
			if _fall_hits_wall(grid, foot, way, reach):
				problems.append(
					[
						"set_piece_fall",
						(
							"%s: falling %s it lands on a wall; leave that way out of falls"
							% [id, ["east", "south", "west", "north"][way]]
						)
					]
				)
		out["x"] = snappedf(p.x, .01)
		out["y"] = snappedf(p.y, .01)
		out["turn"] = turn
		for key: String in PASSED:
			if spec.has(key):
				out[key] = spec[key]
	out["falls"] = falls
	var list: Array = grid.level.get("set_pieces", [])
	list.append(out)
	grid.level["set_pieces"] = list
	grid.keep(MapLooksGrid.f(out["x"]), MapLooksGrid.f(out["y"]), 2.0)
	return {"problems": problems}


## The ground a barn or tower stands on (map units).
static func footprint(kind: String, p: Vector2, turn: int, spec: Dictionary) -> Rect2:
	if kind == "barn":
		var bw := MapLooksGrid.f(spec.get("w", SetPieceShape.num("barn", "w", 8.0)))
		var bd := MapLooksGrid.f(spec.get("d", SetPieceShape.num("barn", "d", 5.0)))
		var half := Vector2(bw, bd) * .5 if turn % 2 == 0 else Vector2(bd, bw) * .5
		return Rect2(p - half, half * 2.0)
	var spread := SetPieceShape.num("tower", "spread", 1.15) + .3
	return Rect2(p - Vector2(spread, spread), Vector2(spread, spread) * 2.0)


static func _open(grid: MapLooksGrid, p: Vector2) -> bool:
	return grid.inside(int(p.x), int(p.y)) and grid.is_open(grid.cell(p.x, p.y))


static func _fall_hits_wall(grid: MapLooksGrid, foot: Rect2, way: int, reach: float) -> bool:
	var land := foot
	match way:
		0:
			land = Rect2(foot.end.x, foot.position.y, reach, foot.size.y)
		1:
			land = Rect2(foot.position.x, foot.end.y, foot.size.x, reach)
		2:
			land = Rect2(foot.position.x - reach, foot.position.y, reach, foot.size.y)
		3:
			land = Rect2(foot.position.x, foot.position.y - reach, foot.size.x, reach)
	for y in range(floori(land.position.y), ceili(land.end.y)):
		for x in range(floori(land.position.x), ceili(land.end.x)):
			if not grid.inside(x, y) or not grid.is_open(y * grid.w + x):
				return true
	return false


static func _count(lv: Dictionary) -> int:
	var list: Array = lv.get("set_pieces", [])
	return list.size()
