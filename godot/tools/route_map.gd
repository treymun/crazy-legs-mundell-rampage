## The way through each level, objective by objective, and where it doubles
## back: from the start to each station the exit needs (nearest open one next),
## then the exit's own station and the exit. Each leg is walked over open
## floor with every door open, as a player who has done what opens them.
## A leg several times longer than the straight line is a place a shortcut
## door (an `access_doors` entry) would save a long walk back.
##
##   godot --headless --path godot --script res://tools/route_map.gd [-- <out dir>]
##
## Prints each leg's length and writes <out dir>/route_<level>.png: walls dark,
## the route from yellow (walked once) to red (walked three or more times),
## stations white, the start green, the exit blue, long legs magenta.
## Hickston has no exit: its legs are the keys, the sheriff, Jerry and Bessie.
extends SceneTree

const SCALE := 6
const DETOUR := 1.9


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := String(args[0]) if not args.is_empty() else ""
	var art := Assets.new()
	for id in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway"]:
		var level := LevelData.load_level(id, art)
		_route(level, out_dir)
	quit()


func _route(level: LevelData, out_dir: String) -> void:
	var exit: LevelData.Extraction = level.extraction
	var stops: Array = []
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
				if (
					ready
					and (
						pick == null
						or (
							at.distance_to(Vector2(station.x, station.y))
							< at.distance_to(Vector2(pick.x, pick.y))
						)
					)
				):
					pick = station
			if pick == null:
				pick = pending[0]
			pending.erase(pick)
			done[pick.id] = true
			stops.append([pick.id, Vector2(pick.x, pick.y)])
			at = Vector2(pick.x, pick.y)
		if shutdown != null:
			stops.append([shutdown.id, Vector2(shutdown.x, shutdown.y)])
		stops.append(["exit", Vector2(exit.x, exit.y)])
	elif level.rescue:
		# Hickston: the brass key, the steel key, the sheriff, Jerry, Bessie.
		for key in ["key_brass", "key_steel"]:
			for pickup in level.pickups:
				if String(pickup[0]) == key:
					stops.append([key, Vector2(float(pickup[1]), float(pickup[2]))])
		for kind in ["boss", "jerry", "bessie"]:
			for enemy in level.enemies:
				if String(enemy["kind"]) == kind:
					stops.append([kind, Vector2(float(enemy["x"]), float(enemy["y"]))])
	else:
		for station: LevelData.Station in level.stations:
			stops.append([station.id, Vector2(station.x, station.y)])
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	var walked := {}
	var long_cells := {}
	var from := Vector2(float(level.spawn[0]), float(level.spawn[1]))
	var total := 0
	print("%s" % level.id)
	for stop: Array in stops:
		var to: Vector2 = stop[1]
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(to.x, to.y, 0.0)
		var path: Array = []
		var begin := _nearest_reached(field, from)
		field.waypoint(begin.x, begin.y, 100000, path)
		var length := path.size()
		var straight := from.distance_to(to)
		var detour := length / maxf(straight, 1.0)
		var flag := length > 24 and detour > DETOUR
		total += length
		print(
			(
				"  %-14s %4d steps  straight %5.1f  x%.1f%s"
				% [stop[0], length, straight, detour, "   <- long way round" if flag else ""]
			)
		)
		for cell: Vector2i in path:
			walked[cell] = int(walked.get(cell, 0)) + 1
			if flag:
				long_cells[cell] = true
		from = to
	print("  total %d steps" % total)
	if out_dir == "":
		return
	var image := Image.create_empty(
		level.width * SCALE, level.height * SCALE, false, Image.FORMAT_RGB8
	)
	for cy in level.height:
		for cx in level.width:
			var cell := cy * level.width + cx
			var color := Color(.09, .07, .06) if level.solid[cell] >= 0 else Color(.32, .29, .25)
			var count := int(walked.get(Vector2i(cx, cy), 0))
			if count > 0:
				color = Color(1.0, 1.0 - minf(1.0, (count - 1) / 2.0) * .85, .15)
			if long_cells.has(Vector2i(cx, cy)):
				color = color.lerp(Color(.9, .2, .9), .55)
			image.fill_rect(Rect2i(cx * SCALE, cy * SCALE, SCALE, SCALE), color)
	for stop: Array in stops:
		var point: Vector2 = stop[1]
		var mark := Color(.3, .5, 1.0) if stop[0] == "exit" else Color.WHITE
		image.fill_rect(
			Rect2i(int(point.x) * SCALE - 2, int(point.y) * SCALE - 2, SCALE + 4, SCALE + 4), mark
		)
	var start := Vector2i(int(level.spawn[0]), int(level.spawn[1]))
	image.fill_rect(
		Rect2i(start.x * SCALE - 2, start.y * SCALE - 2, SCALE + 4, SCALE + 4), Color(.2, .9, .3)
	)
	image.save_png("%s/route_%s.png" % [out_dir, level.id])


## A station stands against a wall or in its machine: start from the nearest
## cell the walk reached.
func _nearest_reached(field: FlowField, point: Vector2) -> Vector2:
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
