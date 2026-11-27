## Foliage (pass 16, LOOKS): grass tufts, weeds, scrub, trees, pines, cypress,
## snags, corn and reeds scattered over a map's natural ground, opt-in. A
## foliage object names a kind (dressing.json "foliage"), an area, a density
## and a seed:
##
##   {"type": "foliage", "kind": "grass", "area": [4, 4, 30, 20], "density": .6, "seed": 3}
##
## The plants go down by Poisson-disc scatter (no two of a kind nearer than its
## spacing over the density's square root), from the seed: the same object
## gives the same plants on every machine. Only on the kind's ground (natural
## floors: grass, dirt, orchard, mud, bank, marsh; corn on dirt and grass,
## reeds and cypress at the water too), out in the open (no roof, no deck
## overhead), and never within the clear distances of dressing.json of the
## way through, a door, an objective, a spawn, a road, or anything standing.
## Each plant is a camera-facing sprite drawn by the sprite layer (no node of
## its own); the kinds with a trunk (tree, pine, cypress, snag) get a base
## that stops a body. A map holds at most budget.most plants, and at most
## budget.most_block in any budget.block-cell square.
class_name MapFoliage
extends RefCounted

## Tries round each placed plant before it is let go (Bridson's k).
const TRIES := 18
## The least density taken (a spacing is never stretched past this).
const THINNEST := .05


## Every foliage picture, for counting what a level already holds.
static func pictures() -> Dictionary:
	var out := {}
	var kinds: Dictionary = MapLooksGrid.tuning().get("foliage", {})
	for kind: String in kinds:
		var spec: Dictionary = kinds[kind]
		for p: Variant in spec.get("pictures", []):
			out[str(p)] = kind
	return out


## How many plants the level holds now, in all and per budget block.
static func count(grid: MapLooksGrid) -> Dictionary:
	var known := pictures()
	var block := maxi(1, int(MapLooksGrid.num("budget", "block", 6.0)))
	var blocks := {}
	var total := 0
	for b: Variant in grid.level.get("billboards", []):
		var board: Dictionary = b
		if not known.has(str(board.get("image", ""))):
			continue
		total += 1
		var key := Vector2i(
			int(MapLooksGrid.f(board.get("x", 0.0))) / block,
			int(MapLooksGrid.f(board.get("y", 0.0))) / block
		)
		var had: int = blocks.get(key, 0)
		blocks[key] = had + 1
	return {"total": total, "blocks": blocks}


## Scatter one foliage object into the level. Returns {"placed": count,
## "problems": [[code, line]...]}.
static func scatter(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var problems: Array = []
	var kind := str(spec.get("kind", ""))
	var kinds: Dictionary = MapLooksGrid.tuning().get("foliage", {})
	if not kinds.has(kind):
		problems.append(
			["foliage_kind", "no foliage kind %s (%s)" % [kind, ", ".join(kinds.keys())]]
		)
		return {"placed": 0, "problems": problems}
	var info: Dictionary = kinds[kind]
	var rect := _area(grid, spec)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		problems.append(["foliage_area", "%s: the area is not on the map" % kind])
		return {"placed": 0, "problems": problems}
	var density := clampf(MapLooksGrid.f(spec.get("density", 1.0)), 0.0, 1.0)
	if density <= 0.0:
		return {"placed": 0, "problems": problems}
	var spacing := MapLooksGrid.f(info.get("spacing", 1.0)) / sqrt(maxf(density, THINNEST))
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(
		"foliage|%s|%s|%s" % [kind, str(spec.get("seed", 0)), str([rect.position, rect.end])]
	)
	var polygon := _polygon(spec)
	var budget := count(grid)
	var most := int(MapLooksGrid.num("budget", "most", 360.0))
	var most_block := int(MapLooksGrid.num("budget", "most_block", 16.0))
	var block := maxi(1, int(MapLooksGrid.num("budget", "block", 6.0)))
	var fits := func(p: Vector2) -> bool:
		if not rect.has_point(p):
			return false
		if not polygon.is_empty() and not Geometry2D.is_point_in_polygon(p, polygon):
			return false
		return _fits(grid, info, p)
	# The accel grid: cells of spacing / sqrt 2 hold at most one plant.
	var size := spacing / sqrt(2.0)
	var cols := maxi(1, ceili(rect.size.x / size))
	var rows := maxi(1, ceili(rect.size.y / size))
	var slots: Array[int] = []
	slots.resize(cols * rows)
	slots.fill(-1)
	var placed: Array[Vector2] = []
	var active: Array[int] = []
	var full := false
	var take := func(p: Vector2) -> bool:
		var key := Vector2i(int(p.x) / block, int(p.y) / block)
		var blocks: Dictionary = budget["blocks"]
		var in_block: int = blocks.get(key, 0)
		if in_block >= most_block:
			return false
		var sx := clampi(int((p.x - rect.position.x) / size), 0, cols - 1)
		var sy := clampi(int((p.y - rect.position.y) / size), 0, rows - 1)
		for yy in range(maxi(0, sy - 2), mini(rows, sy + 3)):
			for xx in range(maxi(0, sx - 2), mini(cols, sx + 3)):
				var other := slots[yy * cols + xx]
				if other >= 0 and placed[other].distance_to(p) < spacing:
					return false
		slots[sy * cols + sx] = placed.size()
		placed.append(p)
		active.append(placed.size() - 1)
		blocks[key] = in_block + 1
		var so_far: int = budget["total"]
		budget["total"] = so_far + 1
		return true
	var in_rows: bool = spec.get("rows", false)
	if in_rows:
		_rows(rect, spacing, dice, fits, take)
	else:
		# Seeds: the area's cells in order, each one not yet near a plant
		# starts a spread of its own (so every patch of ground in the area
		# gets some, however it is cut up), jittered by the dice.
		for cy in range(int(rect.position.y), ceili(rect.end.y)):
			for cx in range(int(rect.position.x), ceili(rect.end.x)):
				if _total(budget) >= most:
					full = true
					break
				var p := Vector2(cx + dice.randf_range(.15, .85), cy + dice.randf_range(.15, .85))
				if not fits.call(p) or not take.call(p):
					continue
				while not active.is_empty() and _total(budget) < most:
					var pick := dice.randi_range(0, active.size() - 1)
					var from: Vector2 = placed[active[pick]]
					var found := false
					for k in TRIES:
						var angle := dice.randf_range(0.0, TAU)
						var reach := dice.randf_range(spacing, spacing * 2.0)
						var q := from + Vector2(cos(angle), sin(angle)) * reach
						if fits.call(q) and take.call(q):
							found = true
							break
					if not found:
						active.remove_at(pick)
			if full:
				break
	if _total(budget) >= most:
		problems.append(
			["foliage_budget", "%s: the map is at its %d plants; the rest left out" % [kind, most]]
		)
	var pics: Array = info.get("pictures", [])
	var tall: Array = info.get("height", [1.0, 1.0])
	var trunk := MapLooksGrid.f(info.get("block", 0.0))
	for p in placed:
		var picture := str(pics[dice.randi_range(0, pics.size() - 1)])
		var height := dice.randf_range(MapLooksGrid.f(tall[0]), MapLooksGrid.f(tall[1]))
		grid.add_board(picture, p.x, p.y, height)
		if trunk > 0.0:
			grid.add_base(p.x, p.y, trunk)
	if placed.is_empty():
		problems.append(
			[
				"foliage_none",
				(
					(
						"%s: no room for it in the area (natural ground in the open,"
						+ " clear of the way, doors, roads and things)"
					)
					% kind
				)
			]
		)
	return {"placed": placed.size(), "problems": problems}


## Corn and the like in rows: a row every 1.7 spacings, a plant every spacing
## along it, each nudged a little by the dice.
static func _rows(
	rect: Rect2, spacing: float, dice: RandomNumberGenerator, fits: Callable, take: Callable
) -> void:
	var step := spacing * .7
	var across := spacing * 1.7
	var y := rect.position.y + across * .5
	while y < rect.end.y:
		var x := rect.position.x + step * .5
		while x < rect.end.x:
			var p := Vector2(x + dice.randf_range(-.12, .12), y + dice.randf_range(-.12, .12))
			if fits.call(p):
				take.call(p)
			x += step
		y += across


## Whether a plant of `info` may stand at p.
static func _fits(grid: MapLooksGrid, info: Dictionary, p: Vector2) -> bool:
	if p.x < .2 or p.y < .2 or p.x > grid.w - .2 or p.y > grid.h - .2:
		return false
	var c := grid.cell(p.x, p.y)
	if not grid.is_open(c) or grid.walk[c] == 0 or grid.roof[c] > 0.0 or grid.covered[c] != 0:
		return false
	var ground: Array = info.get("ground", MapLooksGrid.tuning().get("natural", []))
	if not ground.has(grid.floor_name(c)):
		return false
	if grid.terrain != null and grid.terrain.cliff_at(p.x, p.y):
		return false
	if grid.kept(p.x, p.y):
		return false
	var clear: Dictionary = MapLooksGrid.tuning().get("clear", {})
	if grid.route_distance(p.x, p.y) < MapLooksGrid.f(clear.get("route", 1.5)):
		return false
	var roads: Array = MapLooksGrid.tuning().get("roads", [])
	var road_reach := MapLooksGrid.f(clear.get("road", 1.5))
	if grid.distance_to_floor(p.x, p.y, roads, road_reach) < road_reach:
		return false
	if grid.distance_to_wall(p.x, p.y) < MapLooksGrid.f(info.get("wall", .3)):
		return false
	var trunk := MapLooksGrid.f(info.get("block", 0.0))
	if grid.in_furniture(p.x, p.y, trunk + .15):
		return false
	if info.has("near_water"):
		var reach := MapLooksGrid.f(info["near_water"])
		var water: Array = MapLooksGrid.tuning().get("water_tiles", [])
		if grid.distance_to_floor(p.x, p.y, water, reach) > reach:
			return false
	return true


## The object's area as a rectangle in map units, cut to the map: "area"
## [x0, y0, x1, y1] (cells, the far edge in), else the polygon's bounds, else
## the whole map.
static func _area(grid: MapLooksGrid, spec: Dictionary) -> Rect2:
	var whole := Rect2(0, 0, grid.w, grid.h)
	var listed: Variant = spec.get("area")
	var a: Array = listed if listed is Array else []
	if a.size() == 4:
		var x0 := minf(MapLooksGrid.f(a[0]), MapLooksGrid.f(a[2]))
		var y0 := minf(MapLooksGrid.f(a[1]), MapLooksGrid.f(a[3]))
		var x1 := maxf(MapLooksGrid.f(a[0]), MapLooksGrid.f(a[2])) + 1.0
		var y1 := maxf(MapLooksGrid.f(a[1]), MapLooksGrid.f(a[3])) + 1.0
		return Rect2(x0, y0, x1 - x0, y1 - y0).intersection(whole)
	var polygon := _polygon(spec)
	if not polygon.is_empty():
		var box := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			box = box.expand(p)
		return box.intersection(whole)
	return whole


static func _polygon(spec: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var listed: Variant = spec.get("polygon")
	if listed is Array:
		for item: Variant in listed:
			var pair: Array = item if item is Array else []
			if pair.size() >= 2:
				out.append(Vector2(MapLooksGrid.f(pair[0]), MapLooksGrid.f(pair[1])))
	return out if out.size() >= 3 else PackedVector2Array()


static func _total(budget: Dictionary) -> int:
	var n: int = budget["total"]
	return n
