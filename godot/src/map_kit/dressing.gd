## Dressing (pass 16, LOOKS): vignettes, groups of things made by hand that
## belong together (a porch sittin' couch, cooler and bug zapper; a junk
## pile; a church yard's stones), set with their backs to a wall. Never
## things scattered to fill ground (the owner's rule, levels.md "Placing
## things"): each is a whole group out of dressing.json "vignettes", and it
## goes only where a wall runs behind it, out of the way.
##
## Two ways to ask:
##
##   {"type": "dress", "area": [2, 2, 40, 30], "theme": "farm", "count": 3, "seed": 1}
##   {"type": "vignette", "id": "porch_sittin", "at": [12, 7], "wall": "n"}
##
## A dress object picks `count` vignettes of its theme and spots for them
## from its seed (the same object, the same spots), each against a wall in
## the area, clear of the way through, doors, objectives, spawns, roads,
## other vignettes and everything standing, never cutting off any ground
## the start could walk to. place() returns those choices as vignette objects
## (id, at, wall), so a tool can write them into the source or the player map
## for the author to move or delete; stand() puts one in the level.
##
## A vignette's frame: `at` is the cell at its corner against the wall, `wall`
## the side the wall is on (n, e, s, w). It runs size[0] cells along the wall
## (east for a north or south wall, south for a west or east one) and
## size[1] out from it. Its items' `at` is [along, out] from that corner of
## the wall's face.
class_name MapDressing
extends RefCounted

const MESHES := "res://assets3d/props/meshes.json"
const SIDES := ["n", "e", "s", "w"]
## The step from a cell to its neighbour across each side.
const ACROSS := {
	"n": Vector2i(0, -1), "e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0)
}
## How far a by-the-door vignette may stand from its door (cells).
const DOOR_NEAR := 4.0

static var _sizes := {}


## A town prop's model sizes [width, depth, height, texture, picture height].
static func prop_size(prop: String) -> Array:
	if _sizes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MESHES))
		_sizes = parsed if parsed is Dictionary else {}
	var found: Variant = _sizes.get(prop)
	return found if found is Array else []


static func vignettes() -> Dictionary:
	var found: Dictionary = MapLooksGrid.tuning().get("vignettes", {})
	return found


## The vignettes a dress object places, as vignette objects. Returns
## {"placed": [{"id", "at", "wall"}...], "problems": [[code, line]...]}.
static func place(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var problems: Array = []
	var theme := str(spec.get("theme", ""))
	var themes: Array = MapLooksGrid.tuning().get("themes", [])
	if not themes.has(theme):
		problems.append(["dress_theme", "no theme %s (%s)" % [theme, ", ".join(themes)]])
		return {"placed": [], "problems": problems}
	var want := clampi(int(MapLooksGrid.f(spec.get("count", 1))), 1, 12)
	var area := _area(grid, spec)
	var dice := RandomNumberGenerator.new()
	dice.seed = hash("dress|%s|%s|%s" % [theme, str(spec.get("seed", 0)), str(area)])
	var pool: Array[String] = []
	var all := vignettes()
	var ids: Array = all.keys()
	ids.sort()
	for id: Variant in ids:
		var v: Dictionary = all[id]
		var listed: Array = v.get("themes", [])
		if listed.has(theme):
			pool.append(str(id))
	var placed: Array = []
	var spread := MapLooksGrid.num("clear", "vignettes", 4.0)
	var order: Array[String] = []
	while placed.size() < want and not pool.is_empty():
		if order.is_empty():
			order = pool.duplicate()
			_shuffle(order, dice)
		var id: String = order.pop_back()
		var spots := spots_for(grid, id, area)
		var free: Array = []
		for s: Dictionary in spots:
			var mid: Vector2 = s["mid"]
			var near := false
			for p: Dictionary in placed:
				var other: Vector2 = p["mid"]
				near = near or other.distance_to(mid) < spread
			if not near:
				free.append(s)
		if free.is_empty():
			pool.erase(id)
			continue
		var pick: Dictionary = free[dice.randi_range(0, free.size() - 1)]
		var choice := {"id": id, "at": pick["at"], "wall": pick["wall"], "mid": pick["mid"]}
		if not _keeps_reach(grid, choice):
			continue
		stand(grid, choice)
		placed.append(choice)
	var out: Array = []
	for p: Dictionary in placed:
		out.append({"id": p["id"], "at": p["at"], "wall": p["wall"]})
	if out.is_empty():
		problems.append(
			[
				"dress_none",
				(
					(
						"%s: no wall in the area with room for a vignette (out of the way,"
						+ " clear of doors, the way and things)"
					)
					% theme
				)
			]
		)
	elif out.size() < want:
		problems.append(
			["dress_short", "%s: room for %d of the %d vignettes asked" % [theme, out.size(), want]]
		)
	return {"placed": out, "problems": problems}


## Every spot vignette `id` fits in the area: [{"at": [x, y], "wall", "mid"}]
## in the area's cell order.
static func spots_for(grid: MapLooksGrid, id: String, area: Rect2i) -> Array:
	var out: Array = []
	var v: Dictionary = vignettes().get(id, {})
	if v.is_empty():
		return out
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			for side: String in SIDES:
				if fits(grid, v, Vector2i(x, y), side) == "":
					out.append({"at": [x, y], "wall": side, "mid": _mid(v, Vector2i(x, y), side)})
	return out


## Why vignette `v` cannot stand with its corner at cell `at` against a wall
## on side `wall` ("" when it can).
static func fits(grid: MapLooksGrid, v: Dictionary, at: Vector2i, wall: String) -> String:
	if not ACROSS.has(wall):
		return "wall must be n, e, s or w"
	var size: Array = v.get("size", [3, 2])
	var along := int(MapLooksGrid.f(size[0]))
	var out := int(MapLooksGrid.f(size[1]))
	var where := str(v.get("where", "outside"))
	var clear: Dictionary = MapLooksGrid.tuning().get("clear", {})
	var route_r := MapLooksGrid.f(clear.get("route", 1.5))
	var roads: Array = MapLooksGrid.tuning().get("roads", [])
	var water: Array = MapLooksGrid.tuning().get("water_tiles", [])
	var floor_z := -INF
	for i in along:
		for j in out:
			var c := _cell(at, wall, i, j)
			if not grid.inside(c.x, c.y):
				return "off the map"
			var k := c.y * grid.w + c.x
			if not grid.is_open(k) or grid.walk[k] == 0:
				return "a wall or furniture in the way"
			if j == 0 and not _wall_behind(grid, c, wall):
				return "no wall behind it"
			var name := grid.floor_name(k)
			if roads.has(name) or water.has(name):
				return "on a road or in water"
			if grid.terrain != null and grid.terrain.has(c.x + .5, c.y + .5):
				return "on terrain (vignettes want flat ground)"
			var under := grid.roof[k] > 0.0 or grid.covered[k] != 0
			if (where == "outside" and under) or (where == "inside" and not under):
				return "not %s" % where
			if floor_z == -INF:
				floor_z = grid.ground[k]
			elif grid.ground[k] != floor_z:
				return "not on one floor"
			var mid := Vector2(c.x + .5, c.y + .5)
			if grid.kept(mid.x, mid.y):
				return "too near a door, an objective, a spawn or a thing"
			if grid.route_distance(mid.x, mid.y) < route_r:
				return "in the way through"
	var by_door: bool = v.get("by_door", false)
	if by_door:
		var mid := _mid(v, at, wall)
		var near := false
		for d: Variant in grid.level.get("doors", []):
			var door: Dictionary = d
			var spot := Vector2(
				MapLooksGrid.f(door.get("x", 0)) + .5, MapLooksGrid.f(door.get("y", 0)) + .5
			)
			near = near or spot.distance_to(mid) <= DOOR_NEAR
		if not near:
			return "no door near it"
	return ""


## Put vignette object `choice` ({"id", "at", "wall"}) in the level: its props
## as sprites (with a base that blocks where an item is solid) and its
## fixtures. Returns "" or why it could not.
static func stand(grid: MapLooksGrid, choice: Dictionary) -> String:
	var id := str(choice.get("id", ""))
	var v: Dictionary = vignettes().get(id, {})
	if v.is_empty():
		return "no vignette %s" % id
	var listed: Array = choice.get("at", [0, 0]) if choice.get("at") is Array else [0, 0]
	var at := Vector2i(int(MapLooksGrid.f(listed[0])), int(MapLooksGrid.f(listed[1])))
	var wall := str(choice.get("wall", "n"))
	if not ACROSS.has(wall):
		return "%s: wall must be n, e, s or w" % id
	for item: Variant in v.get("items", []):
		var it: Dictionary = item
		var local: Array = it.get("at", [0.5, 0.5])
		var p := _world(at, wall, MapLooksGrid.f(local[0]), MapLooksGrid.f(local[1]))
		if it.has("prop"):
			var prop := str(it["prop"])
			var dims := prop_size(prop)
			var tall := MapLooksGrid.f(dims[4]) if dims.size() > 4 else 1.0
			var scale := MapLooksGrid.f(it.get("scale", 1.0))
			grid.add_board("town_" + prop, p.x, p.y, tall * scale, MapLooksGrid.f(it.get("z", 0.0)))
			var r := MapLooksGrid.f(it.get("solid", 0.0))
			if r > 0.0:
				grid.add_base(p.x, p.y, r)
		elif it.has("box"):
			var half: Array = it["box"]
			var hx := MapLooksGrid.f(half[0])
			var hy := MapLooksGrid.f(half[1])
			if wall == "e" or wall == "w":
				var swap := hx
				hx = hy
				hy = swap
			var box := Rect2(p.x - hx, p.y - hy, hx * 2.0, hy * 2.0)
			grid.add_fixture(
				box,
				MapLooksGrid.f(it.get("top", .45)),
				str(it.get("side", "tin")),
				str(it.get("cap", "counter_top"))
			)
	# Nothing else goes on its ground.
	var size: Array = v.get("size", [3, 2])
	for i in int(MapLooksGrid.f(size[0])):
		for j in int(MapLooksGrid.f(size[1])):
			var c := _cell(at, wall, i, j)
			grid.keep(c.x + .5, c.y + .5, .7)
	return ""


## The cell i along and j out from the vignette's corner cell.
static func _cell(at: Vector2i, wall: String, i: int, j: int) -> Vector2i:
	match wall:
		"n":
			return at + Vector2i(i, j)
		"s":
			return at + Vector2i(i, -j)
		"w":
			return at + Vector2i(j, i)
	return at + Vector2i(-j, i)


## A point `u` along the wall's face and `v` out from it, from the corner.
static func _world(at: Vector2i, wall: String, u: float, v: float) -> Vector2:
	match wall:
		"n":
			return Vector2(at.x + u, at.y + v)
		"s":
			return Vector2(at.x + u, at.y + 1.0 - v)
		"w":
			return Vector2(at.x + v, at.y + u)
	return Vector2(at.x + 1.0 - v, at.y + u)


static func _mid(v: Dictionary, at: Vector2i, wall: String) -> Vector2:
	var size: Array = v.get("size", [3, 2])
	return _world(at, wall, MapLooksGrid.f(size[0]) * .5, MapLooksGrid.f(size[1]) * .5)


## Whether a wall stands on side `wall` of cell c: a solid cell there (not a
## door), or a thin wall along that edge.
static func _wall_behind(grid: MapLooksGrid, c: Vector2i, wall: String) -> bool:
	var step: Vector2i = ACROSS[wall]
	var n := c + step
	if not grid.inside(n.x, n.y):
		return false
	var k := c.y * grid.w + c.x
	var m := n.y * grid.w + n.x
	if grid.solid[m] >= 0:
		for d: Variant in grid.level.get("doors", []):
			var door: Dictionary = d
			if (
				int(MapLooksGrid.f(door.get("x", -1))) == n.x
				and int(MapLooksGrid.f(door.get("y", -1))) == n.y
			):
				return false
		return true
	return grid.closed(k, m)


## Whether standing `choice` leaves every cell the start could walk to still
## walked to (a vignette never shuts a pocket off).
static func _keeps_reach(grid: MapLooksGrid, choice: Dictionary) -> bool:
	var starts := grid.spawns()
	if starts.is_empty():
		return true
	var v: Dictionary = vignettes().get(str(choice["id"]), {})
	var listed: Array = choice["at"]
	var at := Vector2i(int(MapLooksGrid.f(listed[0])), int(MapLooksGrid.f(listed[1])))
	var wall := str(choice["wall"])
	var blocked := {}
	for item: Variant in v.get("items", []):
		var it: Dictionary = item
		if not (it.has("box") or MapLooksGrid.f(it.get("solid", 0.0)) > 0.0):
			continue
		var local: Array = it.get("at", [0.5, 0.5])
		var p := _world(at, wall, MapLooksGrid.f(local[0]), MapLooksGrid.f(local[1]))
		blocked[grid.cell(p.x, p.y)] = true
	if blocked.is_empty():
		return true
	var from := grid.cell(starts[0].x, starts[0].y)
	var before := _reached(grid, from, {})
	var after := _reached(grid, from, blocked)
	return after + blocked.size() >= before


static func _reached(grid: MapLooksGrid, from: int, blocked: Dictionary) -> int:
	var seen := PackedByteArray()
	seen.resize(grid.w * grid.h)
	seen.fill(0)
	var todo: Array[int] = [from]
	seen[from] = 1
	var at := 0
	while at < todo.size():
		var c: int = todo[at]
		at += 1
		var x := c % grid.w
		var y := c / grid.w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not grid.inside(x + d.x, y + d.y):
				continue
			var m := (y + d.y) * grid.w + x + d.x
			if seen[m] != 0 or grid.walk[m] == 0 or blocked.has(m) or grid.closed(c, m):
				continue
			seen[m] = 1
			todo.append(m)
	return todo.size()


static func _area(grid: MapLooksGrid, spec: Dictionary) -> Rect2i:
	var whole := Rect2i(0, 0, grid.w, grid.h)
	var listed: Variant = spec.get("area")
	var a: Array = listed if listed is Array else []
	if a.size() != 4:
		return whole
	var x0 := int(minf(MapLooksGrid.f(a[0]), MapLooksGrid.f(a[2])))
	var y0 := int(minf(MapLooksGrid.f(a[1]), MapLooksGrid.f(a[3])))
	var x1 := int(maxf(MapLooksGrid.f(a[0]), MapLooksGrid.f(a[2])))
	var y1 := int(maxf(MapLooksGrid.f(a[1]), MapLooksGrid.f(a[3])))
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1).intersection(whole)


## A deterministic shuffle by the dice (Fisher-Yates).
static func _shuffle(list: Array[String], dice: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := dice.randi_range(0, i)
		var swap := list[i]
		list[i] = list[j]
		list[j] = swap
