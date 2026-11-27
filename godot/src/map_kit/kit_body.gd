## A building's body: storeys of thin walls round a rectangle with doorways
## on the sides asked for and windows on every floor (holes to see and shoot
## through), a floor over each storey with a stairwell and inside stairs up
## the local west wall, and a partition with a doorway. Walls are geometry,
## so the cells inside stay open ground and the roof over them is the top
## storey's ceiling. Map units: a cell is 1, a storey 2.4, a door 1 x 1.85.
class_name KitBody
extends RefCounted

## The stairwell's width along the west wall, and the landing's depth.
const WELL := 1.4
const LANDING := 1.2


## Builds the body over local `body` (whole cells). o: storeys (int), storey
## (height), base (the ground floor's z), doors ([{side n/e/s/w, at 0..1
## along it from the west or north, width, head, storey}]), windows (every
## so many cells, 0 none), rooms (1 or 2), win_sill, win_head, win_width
## (over each floor), glass (a tile for the windows' upper part, "" none),
## arch (stepped heads), top (the walls' top, default the eave). Returns
## {eave, floors: [z...]}.
static func box(parts: LevelParts, look: Dictionary, body: Rect2, o: Dictionary) -> Dictionary:
	var storeys: int = o.get("storeys", 1)
	var storey: float = o.get("storey", KitPiece.num("storey"))
	var base: float = o.get("base", 0.0)
	var every: int = o.get("windows", 2)
	var rooms: int = o.get("rooms", 1)
	var thick := KitPiece.num("wall")
	var inset := thick * .5
	var eave := base + storeys * storey
	var top: float = o.get("top", eave)
	var wall_tile: String = look.get("wall", "barn")
	var floor_tile: String = look.get("floor", "porch")
	var under: String = look.get("under", "joists")
	var light := KitPiece.num("inside_light")
	var x0 := body.position.x
	var y0 := body.position.y
	var x1 := body.end.x
	var y1 := body.end.y
	parts.open(body, floor_tile if base <= 0.0 else "", light)
	var doors: Array = o.get("doors", [])
	var decks: bool = o.get("decks", true)
	var stairs := storeys > 1 and decks
	var sides := {
		"n": [Vector2(x0, y0 + inset), Vector2(x1, y0 + inset)],
		"e": [Vector2(x1 - inset, y0), Vector2(x1 - inset, y1)],
		"s": [Vector2(x0, y1 - inset), Vector2(x1, y1 - inset)],
		"w": [Vector2(x0 + inset, y0), Vector2(x0 + inset, y1)],
	}
	var wall_look := {"tile": wall_tile, "thick": thick}
	var first_in := Vector2(INF, INF)
	for side: String in ["n", "e", "s", "w"]:
		var ends: Array = sides[side]
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var length := a.distance_to(b)
		var holes: Array[Dictionary] = []
		var door_spots: Array[Vector3] = []
		for door: Dictionary in doors:
			var door_side: String = door.get("side", "s")
			if door_side != side:
				continue
			var width: float = door.get("width", 1.0)
			var head: float = door.get("head", KitPiece.num("door_head"))
			var at: float = door.get("at", .5)
			var level: int = door.get("storey", 0)
			var z := base + level * storey
			var mid := _door_middle(at * length, width, length)
			if side == "w" and stairs and level == 0:
				# Under the landing, clear of the stairs.
				mid = _door_middle(LANDING * .5 + .1, width, length)
			holes.append({"at": mid, "width": width, "sill": z, "head": z + head})
			door_spots.append(Vector3(mid, width, level))
			var middle := a.lerp(b, mid / length)
			if level == 0 and not first_in.is_finite():
				var into: Vector2 = -KitFrame.DIRS[side]
				first_in = (middle + into * 1.6).floor() + Vector2(.5, .5)
			if level > 0:
				# A threshold across the wall's thickness, floor to floor.
				var across := Vector2(0, thick) if side == "n" or side == "s" else Vector2(thick, 0)
				var along := Vector2(width, 0) if side == "n" or side == "s" else Vector2(0, width)
				var sill_box := Rect2(middle - across * .5 - along * .5, across + along)
				parts.slab(
					"sill_%s%d" % [side, door_spots.size()],
					sill_box,
					z,
					KitPiece.num("deck"),
					{"tile": floor_tile, "under": under}
				)
			var walk: bool = door.get("walk", true)
			parts.doorway(
				"%s_door%d" % [side, door_spots.size()], middle, side, z, width, head, walk
			)
		var cells := roundi(length)
		for s in storeys:
			var floor_z := base + s * storey
			var k := 1
			while every > 0 and k < cells - 1:
				var at := k + .5
				var clear := true
				for spot: Vector3 in door_spots:
					if absf(spot.x - at) < spot.y * .5 + .6 and int(spot.z) == s:
						clear = false
				if clear and (k % every == 1 or every == 1):
					var sill: float = o.get("win_sill", KitPiece.num("window_sill"))
					var head: float = o.get("win_head", KitPiece.num("window_head"))
					var width: float = o.get("win_width", KitPiece.num("window_width"))
					holes.append(
						{"at": at, "width": width, "sill": floor_z + sill, "head": floor_z + head}
					)
					_window_dressing(
						parts,
						look,
						side,
						a.lerp(b, at / length),
						width,
						floor_z + sill,
						floor_z + head,
						o
					)
				k += 1
		parts.wall("wall_" + side, a, b, base, top, wall_look, holes)
	var floors: Array[float] = [base]
	var cx := (x0 + x1) * .5
	var cy := (y0 + y1) * .5
	var mid_x := x0 + floorf((x1 - x0) * .5)
	var room_x := (mid_x + x1) * .5 if rooms > 1 else cx
	var inside := Vector2(floorf(room_x) + .5, floorf(cy) + .5)
	if first_in.is_finite():
		inside = first_in
	parts.floor_at("floor0", inside, base)
	var deck_look := {"tile": floor_tile, "under": under, "edge": floor_tile}
	var deck := KitPiece.num("deck")
	var well := x0 + WELL
	for s in range(1, storeys if decks else 1):
		var z := base + s * storey
		floors.append(z)
		parts.slab(
			"floor%d" % s,
			Rect2(well, y0 + thick, x1 - thick - well, y1 - y0 - thick * 2),
			z,
			deck,
			deck_look
		)
		parts.slab(
			"landing%d" % s,
			Rect2(x0 + thick, y0 + thick, WELL - thick, LANDING - thick),
			z,
			deck,
			deck_look
		)
		var run := Rect2(x0 + thick, y0 + LANDING, WELL - thick, y1 - thick - .8 - y0 - LANDING)
		parts.stairs("stairs%d" % s, run, z - storey, z, "n", deck_look, deck if s > 1 else -1.0)
		parts.floor_at("floor%d" % s, Vector2(floorf(room_x) + .5, floorf(cy) + .5), z)
	if rooms > 1 and x1 - x0 >= 6:
		for s in storeys:
			var z := base + s * storey
			var up := z + storey - (deck if s < storeys - 1 else 0.0)
			if s == storeys - 1:
				up = top
			var hole: Array[Dictionary] = [
				{
					"at": floorf((y1 - y0) * .5) + .5 - thick,
					"width": 1.0,
					"sill": z,
					"head": z + KitPiece.num("door_head")
				}
			]
			parts.wall(
				"part%d" % s,
				Vector2(mid_x, y0 + thick),
				Vector2(mid_x, y1 - thick),
				z,
				up,
				{"tile": wall_tile, "thick": .12},
				hole
			)
	return {"eave": eave, "floors": floors, "top": top}


## A doorway's middle along a wall of `length`, in the middle of a cell for an
## odd width, on a cell line for an even one, clear of the corners.
static func _door_middle(want: float, width: float, length: float) -> float:
	var half := width * .5
	var odd := roundi(width) % 2 == 1
	var at := roundf(want - .5) + .5 if odd else roundf(want)
	while at + half > length - .45 and at > 1.0:
		at -= 1.0
	while at - half < .45 and at < length - 1.0:
		at += 1.0
	return at


## A window's glass (a tile over its upper part) and its stepped arch head.
static func _window_dressing(
	parts: LevelParts,
	look: Dictionary,
	side: String,
	middle: Vector2,
	width: float,
	sill: float,
	head: float,
	o: Dictionary
) -> void:
	var glass: String = o.get("glass", "")
	var arch: bool = o.get("arch", false)
	if glass == "" and not arch:
		return
	var along := Vector2(1, 0) if side == "n" or side == "s" else Vector2(0, 1)
	var half := width * .5
	var a := middle - along * half
	var b := middle + along * half
	var key := "%s_%d_%d" % [side, int(middle.x * 10), int(middle.y * 10)]
	if glass != "":
		var from := lerpf(sill, head, .45)
		parts.segment("glass_" + key, a, b, from, head, {"tile": glass, "thick": .06})
	if arch:
		var wall_tile: String = look.get("wall", "barn")
		var thick := KitPiece.num("wall")
		var steps := [[0.0, .2, .34], [.2, .36, .14]]
		for k in steps.size():
			var step: Array = steps[k]
			var u: float = step[0]
			var w: float = step[1]
			var drop: float = step[2]
			var wl := {"tile": wall_tile, "thick": thick}
			parts.segment(
				"arch_%s_w%d" % [key, k],
				a + along * width * u,
				a + along * width * w,
				head - drop,
				head,
				wl
			)
			parts.segment(
				"arch_%s_e%d" % [key, k],
				b - along * width * w,
				b - along * width * u,
				head - drop,
				head,
				wl
			)
