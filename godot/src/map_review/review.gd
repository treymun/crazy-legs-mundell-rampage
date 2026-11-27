## The design review of a level (pass 16, T2): what a player would trip over,
## in plain words, found from the level alone (data/<id>.json, a map source
## built in memory, later a MAP SHED map). `MapReview.review(lv, opts)` runs
## every check and leaves `findings` (MapReviewLines' shape) and `numbers`.
## Nothing here plays the level: the bot run and the routes are the map
## tools' (tools/map/map_check_cli.gd), which add their own findings.
##
## The checks (numbers and lines in data/tuning/map_review.json):
## - reach: every station, key and exit, in the order the map opens them
##   (keys picked up, stations done, the doors they open); unreached with every
##   door open is "unreached", reached only through a door it opens itself is
##   "out_of_order" (both MUST FIX);
## - the way: from the start through each stop (route_map.gd's order), walked
##   with every door open; fights (MapFights) along it: rounds, cover;
## - sightlines: a hand that sees the start, the longest open look;
## - dead ends: pockets off a single cell (a cut vertex of the open floor)
##   deeper than dead_end_deep with nothing in them; secrets;
## - pacing: the longest quiet stretch walked for the first time (as
##   tools/pacing_check.gd counts it) and how far the first hand is;
## - height, looks (district names, bare ground, dark rooms), cost (pieces,
##   wall rows, the first nav build's time);
## - a level with no objective and no exit is a versus arena: its loot.
class_name MapReview
extends RefCounted

const L := preload("res://src/map_review/review_lines.gd")
const RESCUE_KEYS: Array[String] = ["key_brass", "key_steel"]
const RESCUE_KINDS: Array[String] = ["boss", "jerry", "bessie"]
const HEALS: Array[String] = ["rinds", "beer", "whiskey", "moonshine"]
const ROUND_PICKUPS: Array[String] = ["shells", "bullets", "rifle_ammo", "dynamite"]
const DIRS: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(.7071, .7071),
	Vector2(0, 1),
	Vector2(-.7071, .7071),
	Vector2(-1, 0),
	Vector2(-.7071, -.7071),
	Vector2(0, -1),
	Vector2(.7071, -.7071)
]

var lv: LevelData
var level_id := ""
## gun or item name -> rounds or count the player starts with.
var kit := {}
var findings: Array = []
var numbers := {}
var spawn := Vector3.ZERO
## The way's stops in order: [name, Vector3 place, what ("station", "key",
## "exit", "boss")], and the step each is reached at.
var stops: Array = []
var stop_steps: Array[int] = []
## The way through, cell by cell; whether each step is walked the first
## time; the stop each step leads to.
var steps: Array[Vector2i] = []
var step_first := PackedByteArray()
var step_leg := PackedStringArray()
## The hostile hands: {id, kind, at: Vector3, hp, boss, drop, drop_chance}.
var hands: Array[Dictionary] = []
## MapFights.find's fights.
var fights: Array[Dictionary] = []
var arena := false


static func review(level: LevelData, opts := {}) -> MapReview:
	var r := MapReview.new()
	r.lv = level
	r.level_id = str(opts.get("id", level.id))
	r.kit = L.kit()
	var given: Dictionary = opts.get("kit", {})
	r.kit.merge(given, true)
	r.run()
	return r


func run() -> void:
	var sx: float = lv.spawn[0]
	var sy: float = lv.spawn[1]
	var sz: float = lv.spawn[3] if lv.spawn.size() > 3 else 0.0
	spawn = Vector3(sx, sy, lv.floor_under(sx, sy, sz + .05))
	_hands()
	_cost()
	stops = _stops()
	arena = stops.is_empty()
	numbers["hands"] = hands.size()
	numbers["pickups"] = lv.pickups.size()
	numbers["stations"] = lv.stations.size()
	if arena:
		_add("way", "no_way", [spawn.x, spawn.y], {})
		_arena()
	else:
		_reach()
		_way()
		fights = MapFights.find(self)
		numbers["fights"] = fights.size()
		MapFights.ammo(self)
		MapFights.cover(self)
		_pacing()
	_spawn_seen()
	_alleys()
	_dead_ends()
	_secrets()
	_height()
	_looks()
	findings.sort_custom(_before)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ra := L.LEVELS.find(str(a["level"]))
	var rb := L.LEVELS.find(str(b["level"]))
	return ra < rb


func _add(check: String, code: String, at: Array, fields: Dictionary) -> Dictionary:
	var f := L.finding(check, code, at, fields)
	findings.append(f)
	return f


static func cfg(path: String) -> ConfigFile:
	return Tuning.file(path)


## A kind's value from enemies.cfg, through its `brain` kind when it has none.
static func kind_value(kind: String, key: String, fallback: Variant) -> Variant:
	var c := cfg(Tuning.ENEMIES)
	if c.has_section_key(kind, key):
		return c.get_value(kind, key)
	var brain: String = str(c.get_value(kind, "brain", ""))
	if brain != "" and brain != kind and c.has_section_key(brain, key):
		return c.get_value(brain, key)
	return fallback


func _hands() -> void:
	for row: Dictionary in lv.enemies:
		var kind: String = str(row.get("kind", ""))
		var hostile: bool = kind_value(kind, "hostile", false)
		if not hostile:
			continue
		var x: float = row["x"]
		var y: float = row["y"]
		var z: float = row.get("z", 0.0)
		var hp: float = kind_value(kind, "hp", 60.0)
		var chance: float = kind_value(kind, "drop_chance", 0.0)
		(
			hands
			. append(
				{
					"id": str(row.get("id", kind)),
					"kind": kind,
					"at": Vector3(x, y, lv.floor_under(x, y, z + .05)),
					"hp": hp,
					"boss": cfg(Tuning.ENEMIES).has_section_key(kind, "title"),
					"drop": str(kind_value(kind, "drop", "")),
					"drop_chance": chance,
				}
			)
		)


## The floor a thing at (x, y), z (NAN: the ground) stands on.
func floor_of(x: float, y: float, z: float) -> float:
	return lv.floor_under(x, y, (0.0 if is_nan(z) else z) + .05)


## The stops of the way through, in order (tools/route_map.gd stops_of, with
## each stop's floor): [name, Vector3, what].
func _stops() -> Array:
	var out: Array = []
	var exit: LevelData.Extraction = lv.extraction
	if exit != null:
		var by_id := {}
		for s: LevelData.Station in lv.stations:
			by_id[s.id] = s
		var shutdown: LevelData.Station = by_id.get(exit.shutdown)
		var pending: Array[LevelData.Station] = []
		if shutdown != null:
			for key: Variant in shutdown.requires:
				if by_id.has(str(key)):
					pending.append(by_id[str(key)])
		var done := {}
		var at := Vector2(spawn.x, spawn.y)
		while not pending.is_empty():
			var pick: LevelData.Station = null
			for s: LevelData.Station in pending:
				var ready := true
				for key: Variant in s.requires:
					if not done.has(str(key)):
						ready = false
				var d := at.distance_to(Vector2(s.x, s.y))
				if ready and (pick == null or d < at.distance_to(Vector2(pick.x, pick.y))):
					pick = s
			if pick == null:
				pick = pending[0]
			pending.erase(pick)
			done[pick.id] = true
			out.append(
				[pick.id, Vector3(pick.x, pick.y, floor_of(pick.x, pick.y, pick.z)), "station"]
			)
			at = Vector2(pick.x, pick.y)
		if shutdown != null:
			var sz := floor_of(shutdown.x, shutdown.y, shutdown.z)
			out.append([shutdown.id, Vector3(shutdown.x, shutdown.y, sz), "station"])
		out.append(["exit", Vector3(exit.x, exit.y, floor_of(exit.x, exit.y, exit.z)), "exit"])
	elif lv.rescue:
		for key in RESCUE_KEYS:
			for p: Array in lv.pickups:
				if str(p[0]) == key:
					out.append([key, _pickup_at(p), "key"])
		for kind in RESCUE_KINDS:
			for h: Dictionary in hands:
				if h["kind"] == kind:
					out.append([kind, h["at"], "boss"])
	else:
		for s: LevelData.Station in lv.stations:
			out.append([s.id, Vector3(s.x, s.y, floor_of(s.x, s.y, s.z)), "station"])
	return out


## A pickup that is a key (flow_probe.gd's test, food first).
static func is_key(name: String) -> bool:
	return not HEALS.has(name) and name.contains("key")


func cell_of(x: float, y: float) -> int:
	if x < 0 or y < 0 or x >= lv.width or y >= lv.height:
		return -1
	return int(y) * lv.width + int(x)


func _pickup_at(p: Array) -> Vector3:
	var x: float = p[1]
	var y: float = p[2]
	var z: float = p[3] if p.size() > 3 and (p[3] is float or p[3] is int) else 0.0
	return Vector3(x, y, lv.floor_under(x, y, z + .05))


## A field measured from the start over the whole level.
func spawn_field(every_door: bool) -> FlowField:
	var f := FlowField.new(lv)
	f.reach = 1 << 20
	f.doors_open = true
	f.every_door = every_door
	measure(f, spawn)
	return f


static func measure(f: FlowField, at: Vector3) -> void:
	f.origin = Vector2i(-1, -1)
	f.next_at = 0.0
	f.update(at.x, at.y, 0.0, at.z)


## Whether `at` is reached on `f` (or a place within use_reach of it on its
## floor: a station stands in its machine or against a wall).
func reached(f: FlowField, at: Vector3) -> bool:
	if f.distance(at.x, at.y, at.z) < FlowField.FAR:
		return true
	var r := L.num("use_reach")
	var k := ceili(r)
	for dy in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var x := floorf(at.x) + dx + .5
			var y := floorf(at.y) + dy + .5
			if Vector2(x - at.x, y - at.y).length() > r:
				continue
			if x < 0 or y < 0 or x >= lv.width or y >= lv.height:
				continue
			if absf(lv.floor_under(x, y, at.z + .05) - at.z) > .3:
				continue
			if f.distance(x, y, at.z) < FlowField.FAR:
				return true
	return false


## Doors a trigger opens ({"open": [x, y]}).
func _trigger_doors() -> Dictionary:
	var out := {}
	for t: Variant in lv.triggers:
		if not (t is Dictionary):
			continue
		var tr: Dictionary = t
		var acts: Variant = tr.get("do", [])
		if not (acts is Array):
			continue
		var list: Array = acts
		for a: Variant in list:
			if not (a is Dictionary):
				continue
			var act: Dictionary = a
			if act.has("open"):
				var p: Array = act["open"]
				var px: float = p[0]
				var py: float = p[1]
				out[Vector2i(int(px), int(py))] = true
	return out


## Every station, key and exit in the order the map opens them.
func _reach() -> void:
	var openers := _trigger_doors()
	var was: Array[bool] = []
	var by_cell := {}
	for d: LevelData.Door in lv.doors:
		was.append(d.opened)
		var at := Vector2i(d.x, d.y)
		by_cell[at] = d
		var held := lv.controlled_doors.has(at) or lv.access_doors.has(at)
		if openers.has(at) or (not held and (d.secret or d.blast_only)):
			d.opened = true
	var goals: Array = []
	for s: LevelData.Station in lv.stations:
		goals.append(["station", s.id, Vector3(s.x, s.y, floor_of(s.x, s.y, s.z)), s])
	for p: Array in lv.pickups:
		if is_key(str(p[0])):
			goals.append(["key", str(p[0]), _pickup_at(p), null])
	if lv.extraction != null:
		var e := lv.extraction
		goals.append(["exit", "exit", Vector3(e.x, e.y, floor_of(e.x, e.y, e.z)), null])
	var f := FlowField.new(lv)
	f.reach = 1 << 20
	f.doors_open = true
	var done := {}
	var got := {}
	var changed := true
	var rounds := 0
	while changed and rounds < goals.size() + 2:
		changed = false
		rounds += 1
		f.keys = got.duplicate()
		measure(f, spawn)
		for g: Array in goals:
			var name: String = g[1]
			if got.has(name) or done.has(name):
				continue
			if g[0] == "station":
				var s: LevelData.Station = g[3]
				var ready := true
				for key: Variant in s.requires:
					if not done.has(str(key)):
						ready = false
				var spot: Vector3 = g[2]
				if not ready or not reached(f, spot):
					continue
				done[name] = true
				changed = true
				for door: LevelData.Door in lv.doors:
					var at := Vector2i(door.x, door.y)
					var need: Variant = lv.access_doors.get(at)
					var all_done := need != null
					if need is Array:
						for key: Variant in need:
							if not done.has(str(key)):
								all_done = false
					if s.opens.has(at) or all_done:
						door.opened = true
				continue
			var place_of: Vector3 = g[2]
			if reached(f, place_of):
				got[name] = true
				done[name] = true
				changed = true
	var missing: Array = []
	for g: Array in goals:
		if not done.has(str(g[1])):
			missing.append(g)
	numbers["objectives"] = goals.size()
	numbers["objectives_reached"] = goals.size() - missing.size()
	if not missing.is_empty():
		var all := spawn_field(true)
		for g: Array in missing:
			_unreached(g, all, by_cell)
	var i := 0
	for d: LevelData.Door in lv.doors:
		d.opened = was[i]
		i += 1


func _unreached(g: Array, all: FlowField, by_cell: Dictionary) -> void:
	var at: Vector3 = g[2]
	var what: String = g[0]
	var name: String = g[1]
	var spot := [at.x, at.y, at.z]
	var words := {"what": what, "name": name, "object": name, "z": snappedf(at.z, .01)}
	if not reached(all, at):
		words["map"] = level_id
		_add("reach", "unreached", spot, words)
		return
	# Reached only with every door open: the first shut door on its way back.
	var path: Array = []
	all.waypoint(at.x, at.y, 100000, path, at.z)
	var through := "a door"
	for cell: Vector2i in path:
		if by_cell.has(cell):
			var d: LevelData.Door = by_cell[cell]
			if not d.opened:
				through = (
					"the door at (%d, %d)%s"
					% [d.x, d.y, "" if d.key == "" else " (needs %s)" % d.key]
				)
				break
	words["through"] = through
	_add("reach", "out_of_order", spot, words)


## The way through, step by step (every door open, as pacing_check walks it).
func _way() -> void:
	var f := FlowField.new(lv)
	f.reach = 1 << 20
	f.doors_open = true
	f.every_door = true
	var walked := {}
	var from := spawn
	for stop: Array in stops:
		var to: Vector3 = stop[1]
		measure(f, to)
		var begin := nearest_reached(f, from)
		var path: Array = []
		f.waypoint(begin.x, begin.y, 100000, path, begin.z)
		for cell: Vector2i in path:
			steps.append(cell)
			step_first.append(0 if walked.has(cell) else 1)
			step_leg.append(str(stop[0]))
			walked[cell] = true
		stop_steps.append(steps.size() - 1)
		from = to
	numbers["way_steps"] = steps.size()


## `point`, or the nearest place round it the field reached (a station
## stands in its machine).
func nearest_reached(f: FlowField, point: Vector3) -> Vector3:
	if f.distance(point.x, point.y, point.z) < FlowField.FAR:
		return point
	var best := point
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := point.x + dx
			var y := point.y + dy
			if x < 0 or y < 0 or x >= lv.width or y >= lv.height:
				continue
			if f.distance(x, y, point.z) < FlowField.FAR and Vector2(dx, dy).length() < best_d:
				best_d = Vector2(dx, dy).length()
				best = Vector3(floorf(x) + .5, floorf(y) + .5, point.z)
	return best


static func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + .5, cell.y + .5)


## The longest stretch walked for the first time with nothing on it.
func _pacing() -> void:
	var looks: Array[Vector2] = []
	for s: LevelData.Station in lv.stations:
		looks.append(Vector2(s.x, s.y))
	for b: LevelData.Billboard in lv.billboards:
		if b.image.contains("sign") or b.image.contains("arrow"):
			looks.append(Vector2(b.x, b.y))
	var loot: Array[Vector2] = []
	for p: Array in lv.pickups:
		var at := _pickup_at(p)
		loot.append(Vector2(at.x, at.y))
	var near_hand := L.num("quiet_hand")
	var run := 0
	var start := 0
	var best := 0
	var best_from := 0
	var best_to := 0
	var first_hand := -1
	for i in steps.size():
		var c := centre(steps[i])
		var hand := false
		for h: Dictionary in hands:
			var at: Vector3 = h["at"]
			if Vector2(at.x, at.y).distance_to(c) <= near_hand:
				hand = true
				break
		if hand and first_hand < 0:
			first_hand = i
		if step_first[i] == 0:
			continue
		var quiet := (
			not hand
			and not _within(loot, c, L.num("quiet_loot"))
			and not _within(looks, c, L.num("quiet_look"))
		)
		if quiet:
			if run == 0:
				start = i
			run += 1
			if run > best:
				best = run
				best_from = start
				best_to = i
		else:
			run = 0
	numbers["quiet_most"] = best
	numbers["first_hand_steps"] = first_hand
	if best > L.whole("quiet_most"):
		var a := centre(steps[best_from])
		var b := centre(steps[best_to])
		var mid := centre(steps[(best_from + best_to) / 2])
		_add(
			"pacing",
			"quiet_stretch",
			[mid.x, mid.y],
			{
				"from": L.place([a.x, a.y]),
				"to": L.place([b.x, b.y]),
				"leg": step_leg[best_to],
				"steps": best,
				"hand": near_hand,
				"loot": L.num("quiet_loot"),
				"look": L.num("quiet_look"),
				"mid": L.place([mid.x, mid.y]),
			}
		)
	var late := L.whole("first_fight_late")
	if first_hand > late or (first_hand < 0 and not hands.is_empty() and steps.size() > late):
		_add(
			"pacing",
			"first_fight_late",
			[spawn.x, spawn.y],
			{"steps": first_hand if first_hand >= 0 else steps.size()}
		)


static func _within(points: Array[Vector2], c: Vector2, reach: float) -> bool:
	for p in points:
		if p.distance_to(c) <= reach:
			return true
	return false


## Hands that see the start from close.
func _spawn_seen() -> void:
	var near := L.num("spawn_seen_near")
	var eye := spawn.z + .95
	var worst: Dictionary = {}
	var worst_d := INF
	for h: Dictionary in hands:
		var boss: bool = h["boss"]
		if boss:
			continue
		var at: Vector3 = h["at"]
		var d := Vector2(at.x, at.y).distance_to(Vector2(spawn.x, spawn.y))
		if d > near or d >= worst_d:
			continue
		if lv.visible(at.x, at.y, spawn.x, spawn.y, at.z + 1.4, eye):
			worst = h
			worst_d = d
	if not worst.is_empty():
		var at: Vector3 = worst["at"]
		_add(
			"sightlines",
			"spawn_seen",
			[at.x, at.y, at.z],
			{
				"name": worst["id"],
				"object": worst["id"],
				"kind": str(worst["kind"]).replace("_", " "),
				"far": snappedf(worst_d, .1)
			}
		)


## The longest open look from the way (or the start, on an arena).
func _alleys() -> void:
	var from: Array[Vector2] = []
	var every := L.whole("alley_every")
	for i in range(0, steps.size(), maxi(1, every)):
		from.append(centre(steps[i]))
	if from.is_empty():
		from.append(Vector2(spawn.x, spawn.y))
	var longest := L.num("alley_long")
	var cap := longest * 2.0
	var best := 0.0
	var best_at := Vector2.ZERO
	var best_to := Vector2.ZERO
	for p in from:
		for d in DIRS:
			var far := _look(p, d, cap)
			if far > best:
				best = far
				best_at = p
				best_to = p + d * far
	numbers["longest_look"] = snappedf(best, .1)
	if best > longest:
		_add(
			"sightlines",
			"alley",
			[best_at.x, best_at.y],
			{"far": roundi(best), "to": L.place([best_to.x, best_to.y])}
		)


## How far a look from p along d stays open (to `cap`).
func _look(p: Vector2, d: Vector2, cap: float) -> float:
	var end := p + d * cap
	end.x = clampf(end.x, .5, lv.width - .5)
	end.y = clampf(end.y, .5, lv.height - .5)
	var most := p.distance_to(end)
	if lv.visible(p.x, p.y, end.x, end.y):
		return most
	var lo := 0.0
	var hi := most
	for _k in 6:
		var mid := (lo + hi) * .5
		var q := p + d * mid
		if lv.visible(p.x, p.y, q.x, q.y):
			lo = mid
		else:
			hi = mid
	return lo


## The open floor's cells as a 4-way grid (doors open).
func _open_grid() -> PackedByteArray:
	var f := FlowField.new(lv)
	var out := PackedByteArray()
	out.resize(lv.width * lv.height)
	for c in out.size():
		out[c] = 1 if f.open[c] > 0 else 0
	return out


## Dead ends: pockets off one cell with nothing in them (MapPockets).
func _dead_ends() -> void:
	var open := _open_grid()
	var start := int(spawn.y) * lv.width + int(spawn.x)
	if start < 0 or start >= open.size() or open[start] == 0:
		return
	var stuff := PackedByteArray()
	stuff.resize(open.size())
	var spots: Array[Vector2] = []
	for p: Array in lv.pickups:
		var px: float = p[1]
		var py: float = p[2]
		spots.append(Vector2(px, py))
	for h: Dictionary in hands:
		var at: Vector3 = h["at"]
		spots.append(Vector2(at.x, at.y))
	for s: LevelData.Station in lv.stations:
		spots.append(Vector2(s.x, s.y))
	for b: LevelData.Billboard in lv.billboards:
		spots.append(Vector2(b.x, b.y))
	if lv.extraction != null:
		spots.append(Vector2(lv.extraction.x, lv.extraction.y))
	for p in spots:
		var c := cell_of(p.x, p.y)
		if c >= 0:
			stuff[c] = 1
	for d: LevelData.Door in lv.doors:
		if d.secret:
			stuff[d.y * lv.width + d.x] = 1
	var pockets := MapPockets.empty_pockets(open, stuff, lv.width, lv.height, start)
	var deep := L.whole("dead_end_deep")
	var found := 0
	for p: Dictionary in pockets:
		var how_deep: int = p["deep"]
		if how_deep < deep:
			continue
		found += 1
		var c: int = p["cut"]
		var x := c % lv.width + .5
		var y := c / lv.width + .5
		_add("loops", "dead_end", [x, y], {"deep": how_deep})
	numbers["dead_ends"] = found


func _secrets() -> void:
	var secret := 0
	for d: LevelData.Door in lv.doors:
		if d.secret:
			secret += 1
	var stash := 0
	var off := L.num("stash_off")
	for p: Array in lv.pickups:
		var at := _pickup_at(p)
		var near := INF
		for cell in steps:
			near = minf(near, centre(cell).distance_to(Vector2(at.x, at.y)))
			if near <= off:
				break
		if near > off and not steps.is_empty():
			stash += 1
	numbers["secret_doors"] = secret
	numbers["stashes"] = stash
	if secret == 0 and stash == 0:
		_add("secrets", "no_secrets", [spawn.x, spawn.y], {"off": roundi(off)})


func _height() -> void:
	var above := 0
	var nodes := 0
	if lv.geo != null:
		var f := FlowField.new(lv)
		if f.graph != null:
			nodes = f.graph.count
			above = f.graph.count - f.graph.cells
	numbers["nodes_up"] = above
	var raised := 0
	for c in lv.ground.size():
		if lv.solid[c] < 0 and lv.ground[c] > .6:
			raised += 1
	if above == 0 and raised == 0:
		_add("height", "flat", [spawn.x, spawn.y], {})
	numbers["nodes"] = nodes


func _looks() -> void:
	var unnamed := 0
	for name in lv.districts:
		if name.strip_edges() == "":
			unnamed += 1
	if lv.districts.is_empty():
		unnamed = 1
	if unnamed > 0:
		_add("looks", "no_districts", [spawn.x, spawn.y], {"count": unnamed})
	_empty_ground()
	_dark_rooms()


## The share of open ground with nothing (a wall, a thing) within empty_reach.
func _empty_ground() -> void:
	var w := lv.width
	var n := w * lv.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 20)
	var queue := PackedInt32Array()
	for c in n:
		if lv.solid[c] >= 0:
			dist[c] = 0
			queue.append(c)
	var spots: Array[Vector2] = []
	for b: LevelData.Billboard in lv.billboards:
		spots.append(Vector2(b.x, b.y))
	for p: Array in lv.pickups:
		var px: float = p[1]
		var py: float = p[2]
		spots.append(Vector2(px, py))
	for h: Dictionary in hands:
		var at: Vector3 = h["at"]
		spots.append(Vector2(at.x, at.y))
	for fx: PackedFloat32Array in lv.fixtures:
		spots.append(Vector2((fx[0] + fx[2]) * .5, (fx[1] + fx[3]) * .5))
	for p in spots:
		var c := cell_of(p.x, p.y)
		if c >= 0 and dist[c] != 0:
			dist[c] = 0
			queue.append(c)
	var reach := L.whole("empty_reach")
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if dist[c] >= reach:
			continue
		var cx := c % w
		var cy := c / w
		for d: Vector2i in FlowField.NEIGHBOURS:
			var x := cx + d.x
			var y := cy + d.y
			if x < 0 or y < 0 or x >= w or y >= lv.height:
				continue
			var m := y * w + x
			if dist[m] > dist[c] + 1:
				dist[m] = dist[c] + 1
				queue.append(m)
	var open := 0
	var bare := 0
	for c in n:
		if lv.solid[c] >= 0 or lv.roof[c] > 0.0:
			continue
		open += 1
		if dist[c] >= reach:
			bare += 1
	var share := float(bare) / maxf(1.0, open)
	numbers["bare_share"] = snappedf(share, .01)
	if share > L.num("empty_share"):
		_add(
			"looks",
			"empty_ground",
			[spawn.x, spawn.y],
			{"share": "%d%%" % roundi(share * 100.0), "reach": reach}
		)


## A roofed district that is very dark.
func _dark_rooms() -> void:
	var sums := {}
	var counts := {}
	var places := {}
	for c in lv.area.size():
		if lv.solid[c] >= 0 or lv.roof[c] <= 0.0:
			continue
		var a := lv.area[c]
		var sum: float = sums.get(a, 0.0)
		var count_was: int = counts.get(a, 0)
		sums[a] = sum + lv.light[c]
		counts[a] = count_was + 1
		if not places.has(a):
			places[a] = c
	for a: int in sums:
		var count: int = counts[a]
		if count < 4:
			continue
		var total: float = sums[a]
		var mean: float = total / count
		if mean >= L.num("dark_light"):
			continue
		var c: int = places[a]
		var name := lv.districts[a] if a >= 0 and a < lv.districts.size() else "?"
		_add(
			"looks",
			"dark_room",
			[c % lv.width + .5, c / lv.width + .5],
			{"name": name, "light": snappedf(mean, .01)}
		)


## Pieces, wall rows and the first nav build's time against the budgets.
func _cost() -> void:
	var pieces := 0
	if lv.geo != null:
		pieces = lv.geo.slabs.size() + lv.geo.segments.size() + lv.geo.ceilings.size()
	numbers["pieces"] = pieces
	numbers["wall_rows"] = lv.wall_count
	var began := Time.get_ticks_usec()
	FlowField.new(lv)
	var ms := (Time.get_ticks_usec() - began) / 1000.0
	numbers["nav_ms"] = snappedf(ms, .1)
	_budget("pieces", "the pieces (slabs, walls, ceilings)", pieces)
	_budget("wall_rows", "the wall rows", lv.wall_count)
	_budget("nav_ms", "the first nav build (ms)", roundi(ms))


func _budget(key: String, what: String, value: int) -> void:
	var most := L.whole(key + "_most")
	var should := L.whole(key + "_should")
	var at := [spawn.x, spawn.y]
	if value > most:
		_add("cost", "cost_most", at, {"what": what, "value": value, "budget": most})
	elif value > should:
		_add("cost", "cost_should", at, {"what": what, "value": value, "budget": should})


## A versus map: something to heal with and rounds lying out.
func _arena() -> void:
	var heals := 0
	var rounds := 0
	for p: Array in lv.pickups:
		var name := str(p[0])
		if HEALS.has(name):
			heals += 1
		if ROUND_PICKUPS.has(name):
			rounds += 1
	numbers["arena_heals"] = heals
	numbers["arena_rounds"] = rounds
	if heals < 2 or rounds < 2:
		_add("arena", "arena_loot", [spawn.x, spawn.y], {"heals": heals, "rounds": rounds})
