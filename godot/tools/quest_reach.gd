## Can every quest prop and item be used from a comfortable spot? For each
## chapter and the Crossroads, this stands the player on every spot around
## each thing the objective needs (stations, the exit, the gates, notes, the
## jukebox and sink, the shooting stand, the dispatch board and road clues)
## from where it can be seen, half a cell to a cell and a bit away, faces it
## and asks the game what USE would act on (the same calls a key, the USE
## touch button and a controller's button end in). Every such spot must work,
## and with the aim a little off most still must; a spot whose only way to the
## thing is a walk around a wall must not. Keys and the patch lead must be
## collected by walking up to them, and the objective pin must arrive where
## the thing can be used.
##
##   godot --headless --path godot --script res://tools/quest_reach.gd
##       [-- <level>] [tour=<views.json>] [verbose]
##
## tour= writes a window-tour list (main.gd --view-tour) standing at each
## thing's best spot, for before-and-after pictures. Prints QUEST REACH OK.
extends SceneTree

const LEVELS := ["hickston", "fair", "sawmill", "quarry", "hub"]
## The ring a player stands in to use something: no nearer, no farther.
const NEAR := .5
const FAR := 1.2
const STEP := .1
## Aim this far off still works from most spots.
const LOOSE := deg_to_rad(22.0)
const LOOSE_SHARE := .9
## A spot nearer than this but a long walk around a wall away must not work.
const WALL_REACH := 1.75
const AROUND := 6

var failures: Array = []
var tour: Array = []
var verbose := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var tour_path := ""
	var ids: Array = []
	for a: String in args:
		if a.begins_with("tour="):
			tour_path = a.substr(5)
		elif a == "verbose":
			verbose = true
		else:
			ids.append(a)
	if ids.is_empty():
		ids = LEVELS
	var art := Assets.new()
	var hud := HUD.new(art)
	var sound := Sound.new(art)
	root.add_child(sound)
	for id: String in ids:
		_level(Game.new(art, hud, sound, id))
	if tour_path != "":
		var file := FileAccess.open(tour_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(tour, " "))
		file.close()
		print("tour of %d views written to %s" % [tour.size(), tour_path])
	if failures.is_empty():
		print("\nQUEST REACH OK")
	else:
		print("\nQUEST REACH FAILURES: ", failures.size())
		for f in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ targets


## Everything to use in the level: [name, what USE returns, use point, the
## picture's middle (Vector3), kind].
func _targets(g: Game) -> Array:
	var out: Array = []
	var w := g.world
	if g.level.id == "hub":
		g.in_hub = true
		var board := g.level.hub_board
		out.append(["dispatch board", "dispatch", board, _at(g, board, 1.25), "clue"])
		for clue in w.hub_clues:
			var p := Vector2(float(clue[1]), float(clue[2]))
			out.append([String(clue[3]), String(clue[0]), p, _at(g, p, .9), "clue"])
		for gate: LevelData.Gate in w.hub_gates:
			var p := Vector2(gate.x, gate.y)
			out.append(["gate " + gate.destination, gate, p, _at(g, p, 1.2), "gate"])
		return out
	for station: LevelData.Station in w.stations:
		var p := Vector2(station.x, station.y)
		out.append(["station " + station.id, station, p, _board_at(g, station.id, p), "use"])
	if w.extraction != null:
		var e: LevelData.Extraction = w.extraction
		var p := Vector2(e.x, e.y)
		out.append(["exit", e, p, _board_at(g, "exit", p), "use"])
	for device: Array in g.level.devices:
		var p := Vector2(float(device[1]), float(device[2]))
		out.append([String(device[0]), String(device[0]), p, _device_at(g, device), "use"])
	for note: LevelData.Note in g.level.notes:
		var p := Vector2(note.x, note.y)
		var v := Vector3(p.x, p.y, w.elevation(p.x, p.y) + 1.01)
		out.append(["note " + note.label, note, p, v, "use"])
	if g.gallery != null:
		var p: Vector2 = GameState.GALLERY_STAND + g.gallery.offset
		out.append(["gallery stand", g.gallery, p, _at(g, p, .9), "use"])
	if w.return_gate != null:
		var gate: LevelData.Gate = w.return_gate
		var p := Vector2(gate.x, gate.y)
		out.append(["road gate", gate, p, _at(g, p, 1.2), "gate"])
	return out


func _at(g: Game, p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, g.world.elevation(p.x, p.y) + z)


## The middle of the board that lights up for `signal_name` nearest `p` (the
## picture a player looks at), or the point itself at panel height.
func _board_at(g: Game, signal_name: String, p: Vector2) -> Vector3:
	var best: LevelData.Billboard = null
	for board: LevelData.Billboard in g.world.billboards:
		if board.signal_name != signal_name:
			continue
		var d := Vector2(board.x, board.y).distance_to(p)
		if d < 3.5 and (best == null or d < Vector2(best.x, best.y).distance_to(p)):
			best = board
	if best == null:
		return _at(g, p, .9)
	var z: float = g.world.elevation(best.x, best.y) + best.z + best.height * .5
	return Vector3(best.x, best.y, z)


func _device_at(g: Game, device: Array) -> Vector3:
	var p := Vector2(float(device[1]), float(device[2]))
	for prop: LevelData.Scenery in g.world.scenery:
		if prop.kind == String(device[0]) and Vector2(prop.x, prop.y).distance_to(p) < 1.5:
			var z: float = g.world.elevation(prop.x, prop.y) + prop.z + prop.height * .5
			return Vector3(prop.x, prop.y, z)
	for spec in g.level.props:
		var q := Vector2(float(spec[1]), float(spec[2]))
		if String(spec[0]) == String(device[0]) and q.distance_to(p) < 1.5:
			var h := float(GameState.PROP_HEIGHTS.get(String(spec[0]), 1.0))
			return Vector3(q.x, q.y, g.world.elevation(q.x, q.y) + h * .5)
	return _at(g, p, .9)


# ---------------------------------------------------------------- the test


## What pressing USE standing at `s` facing `angle` would act on, as interact().
func _used(g: Game, s: Vector2, angle: float) -> Variant:
	var p := g.player
	p.x = s.x
	p.y = s.y
	p.angle = angle
	p.pitch = 0.0
	p.drunk = 0.0
	p.sway = 0.0
	p.drift = 0.0
	p.crouched = false
	p.air = 0.0
	p.eye = g.world.elevation(s.x, s.y) + .95
	var gate = g.portal_target()
	if gate != null:
		return gate
	if g.in_hub:
		var clue = g.hub_clue()
		return null if clue == null else String(clue[0])
	var found = g.use_target()
	return null if found == null else found[0]


func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	return a == b


## Open cells reached from the start through every door, gate and hatch.
func _reachable(g: Game) -> FlowField:
	var field := FlowField.new(g.world)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	field.update(float(g.level.spawn[0]), float(g.level.spawn[1]), 0.0)
	return field


func _fits(g: Game, s: Vector2, field: FlowField) -> bool:
	return (
		not g.world.blocked(s.x, s.y, GameState.PLAYER_RADIUS)
		and field.distance(s.x, s.y) < 1 << 20
	)


## Spots on the grid within `radius` of `c` where the player can stand.
func _spots(g: Game, c: Vector2, radius: float, field: FlowField) -> Array:
	var out: Array = []
	var n := int(ceil(radius / STEP))
	var ox := snappedf(c.x, STEP)
	var oy := snappedf(c.y, STEP)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var s := Vector2(ox + i * STEP, oy + j * STEP)
			if s.distance_to(c) <= radius and _fits(g, s, field):
				out.append(s)
	return out


## Steps a body walks from `from`'s cell to any of `cells` with every door as
## it stands, up to `limit` (limit + 1 when farther or cut off).
func _walk(g: Game, from: Vector2, cells: Dictionary, limit: int) -> int:
	var start := Vector2i(int(from.x), int(from.y))
	if cells.has(start):
		return 0
	var seen := {start: 0}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = seen[c]
		if d >= limit:
			continue
		for k: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + k
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= g.world.width or n.y >= g.world.height:
				continue
			if g.world.blocked(n.x + .5, n.y + .5, FlowField.BODY):
				continue
			if cells.has(n):
				return d + 1
			seen[n] = d + 1
			queue.append(n)
	return limit + 1


func _level(g: Game) -> void:
	print("\n=== ", g.level.id)
	var field := _reachable(g)
	for t: Array in _targets(g):
		_target(g, t, field)
	if g.level.id != "hub":
		_items(g, field)


func _target(g: Game, t: Array, field: FlowField) -> void:
	var name := String(t[0])
	var want = t[1]
	var use: Vector2 = t[2]
	var seen: Vector3 = t[3]
	var middle := Vector2(seen.x, seen.y)
	var good: Array = []
	var cells := {}
	for s: Vector2 in _spots(g, middle, FAR, field):
		var d := s.distance_to(middle)
		if d < NEAR:
			continue
		var eye := g.world.elevation(s.x, s.y) + .95
		var face := middle + (s - middle).normalized() * .12
		if not g.world.visible(s.x, s.y, face.x, face.y, eye, seen.z):
			continue
		if String(t[4]) == "gate":
			# A gate is used from its lane, coming up to it.
			var gate: LevelData.Gate = want
			if absf(s.x - gate.x) > gate.width * .5 - .3 or (s.y - gate.y) * gate.side < .5:
				continue
		good.append(s)
		cells[Vector2i(int(s.x), int(s.y))] = true
	var works := 0
	var loose := 0
	var loose_tries := 0
	var missed: Array = []
	var best := Vector2.INF
	var best_room := -1.0
	for s: Vector2 in good:
		var angle := atan2(middle.y - s.y, middle.x - s.x)
		if _same(_used(g, s, angle), want):
			works += 1
			# The spot for a picture: about a cell off, in the open (in front of
			# a sign on a wall rather than beside it).
			var room := _room(g, s) - absf(s.distance_to(middle) - 1.0)
			if room > best_room:
				best = s
				best_room = room
		elif missed.size() < 3:
			missed.append(s)
		for off: float in [-LOOSE, LOOSE]:
			loose_tries += 1
			if _same(_used(g, s, angle + off), want):
				loose += 1
	# Through a wall: near, but only reached by walking round.
	var leaks := 0
	var leak_at := Vector2.INF
	if not good.is_empty():
		for s: Vector2 in _spots(g, middle, WALL_REACH, field):
			if cells.has(Vector2i(int(s.x), int(s.y))):
				continue
			if _walk(g, s, cells, AROUND) <= AROUND:
				continue
			var angle := atan2(middle.y - s.y, middle.x - s.x)
			if _same(_used(g, s, angle), want):
				leaks += 1
				leak_at = s
	var pin := _pin(g, use, middle, want, field)
	var share := float(loose) / maxf(1.0, float(loose_tries))
	var ok := not good.is_empty() and works == good.size() and leaks == 0 and pin != "MISSES"
	ok = ok and share >= LOOSE_SHARE
	print(
		(
			"  %-4s %-34s spots %3d  works %3d  aim off %3.0f%%  through walls %2d  pin %s"
			% ["ok" if ok else "FAIL", name, good.size(), works, share * 100.0, leaks, pin]
		)
	)
	if verbose or not ok:
		for s: Vector2 in missed:
			print("         misses from (%.2f, %.2f)" % [s.x, s.y])
		if leaks > 0:
			print("         works through a wall from (%.2f, %.2f)" % [leak_at.x, leak_at.y])
		if good.is_empty():
			print(
				(
					"         nowhere to stand within %.1f that sees (%.2f, %.2f)"
					% [FAR, seen.x, seen.y]
				)
			)
	if not ok:
		failures.append("%s %s" % [g.level.id, name])
	if best != Vector2.INF:
		var angle := atan2(middle.y - best.y, middle.x - best.x)
		_used(g, best, angle)
		var eye := g.world.elevation(best.x, best.y) + .95
		var pitch := clampf(
			(seen.z - eye) / maxf(.4, best.distance_to(middle)) * Renderer.base_focal, -40.0, 40.0
		)
		var prompt: String = g.gate_prompt()
		if prompt == "" and not g.in_hub:
			prompt = g.use_prompt()
		if verbose:
			print("         best (%.2f, %.2f): %s" % [best.x, best.y, prompt])
		var back := best + (best - middle).normalized() * .9
		if not _fits(g, back, field) or not g.world.visible(back.x, back.y, best.x, best.y):
			back = best
		tour.append(
			{
				"level": g.level.id,
				"tag": ("%s_%s" % [g.level.id, name]).replace(" ", "_").replace("'", ""),
				"x": snappedf(back.x, .01),
				"y": snappedf(back.y, .01),
				"angle": snappedf(atan2(middle.y - back.y, middle.x - back.x), .0001),
				"pitch": snappedf(pitch * .6, .1),
				"weapon": false,
				"use": name
			}
		)


## How much open ground is round `s`, out to 1.2.
func _room(g: Game, s: Vector2) -> float:
	var r := .25
	while r < 1.2 and not g.world.blocked(s.x, s.y, r):
		r += .1
	return r


## Where the objective pin brings the player for a thing at `use`: "-" when
## nothing points there (the Crossroads), "ok" when USE works on arrival.
func _pin(g: Game, use: Vector2, middle: Vector2, want, field: FlowField) -> String:
	if g.in_hub or want is LevelData.Gate or want is LevelData.Note or want is String:
		return "-"
	if want is GameState.Gallery:
		return "-"
	var route := FlowField.new(g.world)
	route.reach = 100000
	route.doors_open = true
	route.every_door = true
	route.update(use.x, use.y, 0.0)
	var at := Vector2i(int(g.level.spawn[0]), int(g.level.spawn[1]))
	if route.distance(at.x + .5, at.y + .5) >= 1 << 20:
		return "MISSES"
	var guard := 0
	while route.steps[at.y * route.width + at.x] > 1 and guard < 5000:
		guard += 1
		var to := route.downhill(at)
		if to.x < 0:
			break
		at = to
	# Arrived next to it: stand anywhere in that cell, facing it.
	for k in 9:
		var s := Vector2(at.x + .2 + .3 * (k % 3), at.y + .2 + .3 * (k / 3))
		if not _fits(g, s, field):
			continue
		if _same(_used(g, s, atan2(middle.y - s.y, middle.x - s.x)), want):
			return "ok"
	return "MISSES"


# -------------------------------------------------------------------- items


func _items(g: Game, field: FlowField) -> void:
	for entry: Array in g.pickups:
		var item := String(entry[0])
		if not item.begins_with("key_") and not GameState.TASK_ITEMS.has(item):
			continue
		var p := Vector2(float(entry[1]), float(entry[2]))
		var spots := _spots(g, p, .9, field)
		var nearest := INF
		var takes := 0
		for s: Vector2 in spots:
			nearest = minf(nearest, s.distance_to(p))
			var p_ := g.player
			p_.x = s.x
			p_.y = s.y
			p_.eye = g.world.elevation(s.x, s.y) + .95
			var taken: bool
			if g.has_method("reaches_pickup"):
				taken = g.reaches_pickup(entry)
			else:
				taken = s.distance_squared_to(p) < .43 * .43 and g.world.visible(s.x, s.y, p.x, p.y)
			if taken:
				takes += 1
		var inside := false
		for f: PackedFloat32Array in g.world.collision_volumes:
			if f[0] < p.x and p.x < f[2] and f[1] < p.y and p.y < f[3]:
				inside = true
		var ok := takes >= 3 and not inside
		print(
			(
				"  %-4s item %-29s takes from %3d spots  nearest %.2f  %s"
				% ["ok" if ok else "FAIL", item, takes, nearest, "IN FURNITURE" if inside else ""]
			)
		)
		if not ok:
			failures.append("%s item %s" % [g.level.id, item])
		# A picture of it from a couple of cells off, looking down at it.
		var view := Vector2(p.x + 2.3, p.y)
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0) * 2.3
			var eye := g.world.elevation(q.x, q.y) + .95
			if (
				_fits(g, q, field)
				and g.world.visible(q.x, q.y, p.x, p.y, eye, g.world.elevation(p.x, p.y) + .3)
			):
				view = q
				break
		tour.append(
			{
				"level": g.level.id,
				"tag": "%s_item_%s" % [g.level.id, item],
				"x": snappedf(view.x, .01),
				"y": snappedf(view.y, .01),
				"angle": snappedf(atan2(p.y - view.y, p.x - view.x), .0001),
				"pitch": -26.0,
				"weapon": false,
				"use": item
			}
		)
