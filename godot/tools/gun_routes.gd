## Where the guns lie against the way through each chapter (feature pass 7,
## src/gun_finder.gd): the objective route (tools/route_map.gd's legs), each
## gun pickup's walk off it, whether it is in sight of it, and whether a
## secret door stands between. tools/gun_find_check.gd holds the guns to it;
## `gun_find_check.gd -- audit` prints the table.
extends RefCounted

const CHAPTERS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]
## A chapter's guns are new to a player who arrives with only what the
## chapters before it lay out (and the crowbar and .38 every game starts with).
const START := ["crowbar", "revolver"]


## The stops the objective goes through in order (route_map.gd's legs).
static func stops(level: LevelData) -> Array:
	var exit: LevelData.Extraction = level.extraction
	var out: Array = []
	if exit != null:
		var by_id := {}
		for station: LevelData.Station in level.stations:
			by_id[station.id] = station
		var shutdown: LevelData.Station = by_id.get(exit.shutdown)
		var pending: Array = []
		if shutdown != null:
			for key in shutdown.requires:
				if by_id.has(String(key)):
					pending.append(by_id[String(key)])
		var done := {}
		var at := Vector2(float(level.spawn[0]), float(level.spawn[1]))
		while not pending.is_empty():
			var pick: LevelData.Station = null
			for station: LevelData.Station in pending:
				var ready := true
				for key in station.requires:
					if not done.has(String(key)):
						ready = false
				var here := Vector2(station.x, station.y)
				if (
					ready
					and (
						pick == null
						or at.distance_to(here) < at.distance_to(Vector2(pick.x, pick.y))
					)
				):
					pick = station
			if pick == null:
				pick = pending[0]
			pending.erase(pick)
			done[pick.id] = true
			out.append(Vector2(pick.x, pick.y))
			at = Vector2(pick.x, pick.y)
		if shutdown != null:
			out.append(Vector2(shutdown.x, shutdown.y))
		out.append(Vector2(exit.x, exit.y))
	elif level.rescue:
		for key in ["key_brass", "key_steel"]:
			for pickup in level.pickups:
				if String(pickup[0]) == key:
					out.append(Vector2(float(pickup[1]), float(pickup[2])))
		for kind in ["boss", "jerry", "bessie"]:
			for enemy in level.enemies:
				if String(enemy["kind"]) == kind:
					out.append(Vector2(float(enemy["x"]), float(enemy["y"])))
	else:
		for station: LevelData.Station in level.stations:
			out.append(Vector2(station.x, station.y))
	return out


## Every cell the objective route walks (doors open, as a player who has done
## what opens them), keyed Vector2i.
static func route_cells(level: LevelData) -> Dictionary:
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	var walked := {}
	var from := Vector2(float(level.spawn[0]), float(level.spawn[1]))
	walked[Vector2i(int(from.x), int(from.y))] = true
	for to: Vector2 in stops(level):
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(to.x, to.y, 0.0)
		var path: Array = []
		var begin := _nearest_reached(field, from)
		field.waypoint(begin.x, begin.y, 100000, path)
		for cell: Variant in path:
			if cell is Vector2i:
				walked[cell] = true
			elif cell is Vector2:
				var c: Vector2 = cell
				walked[Vector2i(int(c.x), int(c.y))] = true
		from = to
	return walked


## The guns laid out in each chapter, in campaign order: chapter -> [gun, ...]
## (as a campaign game has them: GunFinder.guns_of).
static func guns_by_chapter(art: Assets) -> Dictionary:
	var out := {}
	for id: String in CHAPTERS:
		var level := LevelData.load_level(id, art)
		var guns: Array = []
		for row: Variant in level.pickups:
			for gun: String in gun_names(str(row[0])):
				if not guns.has(gun):
					guns.append(gun)
		out[id] = guns
	return out


## The gun a pickup gives (none for ammo or food).
static func gun_names(item: String) -> Array:
	return GunFinder.guns_of(item)


## The guns new to a player arriving at `id` in campaign order.
static func new_guns(id: String, by_chapter: Dictionary) -> Array:
	var had := {}
	for gun: String in START:
		had[gun] = true
	for chapter: String in CHAPTERS:
		if chapter == id:
			break
		for gun: String in by_chapter.get(chapter, []):
			had[gun] = true
	var out: Array = []
	for gun: String in by_chapter.get(id, []):
		if not had.has(gun):
			out.append(gun)
	return out


## One row for each gun pickup in `level`: {gun, x, y, off (steps off the
## route), branch (the route's cell nearest it, walked), seen (in sight of a
## route cell within `sight`), secret (only reached through a secret door),
## new (first time in campaign order)}.
static func audit(level: LevelData, route: Dictionary, fresh: Array, sight := 14.0) -> Array:
	var rows: Array = []
	var walk := FlowField.new(level)
	walk.reach = 100000
	walk.doors_open = true
	walk.every_door = true
	var plain := FlowField.new(level)
	plain.reach = 100000
	plain.doors_open = true
	plain.keys = {"key_brass": true, "key_steel": true}
	# Every door a player opens by doing what the chapter asks; secrets stay shut.
	var opened := {}
	for door: LevelData.Door in level.doors:
		opened[door] = door.opened
		if not door.secret:
			door.opened = true
	for row: Variant in level.pickups:
		var guns := gun_names(str(row[0]))
		if guns.is_empty():
			continue
		var item: String = guns[0]
		var x := float(row[1])
		var y := float(row[2])
		walk.origin = Vector2i(-1, -1)
		walk.next_at = 0.0
		walk.update(x, y, 0.0)
		var off := FlowField.FAR
		var branch := Vector2i(-1, -1)
		for cell: Vector2i in route:
			var d := walk.distance(cell.x + .5, cell.y + .5)
			if d < off:
				off = d
				branch = cell
		plain.origin = Vector2i(-1, -1)
		plain.next_at = 0.0
		plain.update(x, y, 0.0)
		var spawn := Vector2(float(level.spawn[0]), float(level.spawn[1]))
		var secret := plain.distance(spawn.x, spawn.y) >= FlowField.FAR
		var seen := false
		for cell: Vector2i in route:
			var c := Vector2(cell.x + .5, cell.y + .5)
			if c.distance_to(Vector2(x, y)) <= sight and level.visible(c.x, c.y, x, y):
				seen = true
				break
		var is_new := false
		for gun: String in guns:
			if fresh.has(gun):
				is_new = true
		(
			rows
			. append(
				{
					"gun": item,
					"x": x,
					"y": y,
					"off": off,
					"branch": branch,
					"seen": seen,
					"secret": secret,
					"new": is_new,
				}
			)
		)
	for door: LevelData.Door in level.doors:
		door.opened = opened[door]
	return rows


static func _nearest_reached(field: FlowField, point: Vector2) -> Vector2:
	if field.distance(point.x, point.y) < FlowField.FAR:
		return point
	var best := point
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := point.x + dx
			var y := point.y + dy
			if field.distance(x, y) < FlowField.FAR and Vector2(dx, dy).length() < best_d:
				best_d = Vector2(dx, dy).length()
				best = Vector2(floorf(x) + .5, floorf(y) + .5)
	return best
