## BLUE never stuck (pass 10: src/features/hound.gd, src/hound_legs.gd;
## tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/hound_walk_check.gd [-- <level> ...]
##
## A player walks each campaign chapter's way through (tools/route_map.gd's
## stops, every door open, no hands about) with BLUE along, and the hub and
## the range besides (he does not come along there in play: the walk sets
## him on, to prove the ground), running between the stops and turning round
## at each one so his sights sweep over the dog. Measured every tick: how far
## BLUE is from his player, how long he is stuck (far off and not getting
## anywhere), how long he stays far without catching up, every jump (the
## lost dog turning up) and whether his player could see where he left or
## landed, how long he stands in front of their sights, and how long he
## stands in a hazard (a saw, the chipper, a hot fence, a burning cell, deep
## water). Then the catch-ups: after a load far from his player, after a
## ride in a vehicle, and a new chapter.
##
## Fails when he is stuck longer than STUCK_MAX, far longer than FAR_MAX, a
## jump is seen, he stands in a hazard, or a catch-up takes too long.
## Prints a row a level and HOUND WALK OK.
extends SceneTree

const STEP := 1.0 / 60.0
const RouteMap := preload("res://tools/route_map.gd")
const Hound := preload("res://src/features/hound.gd")
const LEVELS := [
	"hickston",
	"fair",
	"sawmill",
	"quarry",
	"bayou",
	"speedway",
	"moonshine",
	"mothership",
	"hub",
	"range"
]
## How long he may be stuck (far off, not getting anywhere), in seconds.
const STUCK_MAX := 2.0
## How long he may stay further than FAR from his player.
const FAR_MAX := 8.0
const FAR := 10.0
## Further than this from his player and he should be on his way.
const STUCK_FROM := 3.5
## The player's half view, a cosine (the 3D view is about 100 degrees wide).
const VIEW_COS := .62
## How many steps of the way a level walks at most (the check's time).
const MOST_STEPS := 420
## States he stands still in on purpose.
const STILL := [1, 3, 6, 7, 8]
## How long each vehicle is driven about (seconds).
const RIDE := 12

var failures: Array = []
var main
## `-- verbose`: a line for each stuck, far or harm moment as it begins.
var verbose := false
## `-- trace=<from>-<to>`: his place and doings every quarter second then.
var trace := Vector2(-1.0, -1.0)


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	var ids: Array = Array(OS.get_cmdline_user_args())
	verbose = ids.has("verbose")
	ids.erase("verbose")
	for arg: String in ids.duplicate():
		if arg.begins_with("trace="):
			var span := arg.substr(6).split("-")
			trace = Vector2(float(span[0]), float(span[1]))
			verbose = true
			ids.erase(arg)
	print(
		(
			"%-10s %5s %6s %6s %6s %6s %5s %5s %6s %6s %5s"
			% [
				"level",
				"secs",
				"median",
				"p90",
				"most",
				"stuck",
				"far",
				"jumps",
				"seen",
				"sights",
				"harm"
			]
		)
	)
	for id: String in ids if not ids.is_empty() else LEVELS:
		_walk(id)
	if ids.is_empty():
		print("\nCATCH UP")
		_after_load()
		_after_ride()
		_new_chapter()
	print("\n%.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	print("HOUND WALK OK" if failures.is_empty() else "%d HOUND WALK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ helpers


func _game(id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "hound": 1})
	g.cheats.god = true
	g.lessons = false
	g.enemies.clear()
	g.enemy_ids.clear()
	var h: Hound = g.features["hound"]
	# The hub and the range: he does not come along in play; the walk sets
	# him on to prove the ground.
	h.asked = true
	h.on = true
	for door: LevelData.Door in g.world.doors:
		door.opened = true
		door.progress = 1.0
	g.world.locked_gates.clear()
	return g


func _dog(g: Game) -> Hound.Dog:
	var h: Hound = g.features["hound"]
	return null if h.dogs.is_empty() else h.dogs[0]


## The cells of the level's way through: route_map's stops, walked with every
## door open, a pickup tour where a level has fewer than three stops.
func _way(g: Game) -> Array:
	var level: LevelData = g.world
	var stops := RouteMap.stops_of(level)
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	var from := Vector2(float(level.spawn[0]), float(level.spawn[1]))
	if stops.size() < 3:
		# A tour of the far corners: each stop the reachable cell furthest
		# (straight) from every stop before it.
		field.update(from.x, from.y, 0.0)
		var picked: Array[Vector2] = [from]
		for k in 5:
			var best := Vector2.INF
			var best_d := 0.0
			for cy in range(1, level.height - 1, 2):
				for cx in range(1, level.width - 1, 2):
					var at := Vector2(cx + .5, cy + .5)
					if field.distance(at.x, at.y) >= FlowField.FAR:
						continue
					var near := INF
					for q in picked:
						near = minf(near, q.distance_to(at))
					if near > best_d:
						best_d = near
						best = at
			if best == Vector2.INF:
				break
			picked.append(best)
			stops.append(["corner", best])
	var cells: Array = []
	for stop: Array in stops:
		var to: Vector2 = stop[1]
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(to.x, to.y, 0.0)
		var path: Array = []
		var begin := RouteMap.nearest_reached(field, from)
		field.waypoint(begin.x, begin.y, 100000, path)
		cells.append_array(path)
		cells.append(Vector2i(-1, -1))  # a stop: he turns round here
		from = to
	return cells


## Whether (x, y) is where player p could see it: in their view and in sight.
func _seen(g: Game, p: Player, x: float, y: float, z: float) -> bool:
	var to := Vector2(x - p.x, y - p.y)
	if to.length() < .6:
		return true
	if to.normalized().dot(Vector2(cos(p.angle), sin(p.angle))) < VIEW_COS:
		return false
	return to.length() < 40.0 and g.world.visible(p.x, p.y, x, y, p.eye, z + .4)


## What hazard the dog stands in ("" none): a saw, the chipper, a hot
## fence... (BrawlHazards), a burning cell, deep water.
func _harm(g: Game, d: Hound.Dog, spots: Array) -> String:
	if g.world.deep_at(d.x, d.y) and not g.world.over_deep(d.x, d.y):
		return "deep water"
	var fire: GameFeature = g.features.get("fire")
	if fire != null and fire.call("burning_at", d.x, d.y):
		return "fire"
	for spot: Array in spots:
		var kind: String = spot[0]
		if kind == "well" or kind == "guard":
			continue  # walked over without harm
		var reach: float = BrawlHazards.value(kind, "reach", .8)
		var sx: float = spot[1]
		var sy: float = spot[2]
		if Vector2(d.x - sx, d.y - sy).length() < reach + .1:
			return "%s at %.1f,%.1f" % [kind, sx, sy]
	return ""


## One walk's numbers, filled in tick by tick.
class Tally:
	var ticks := 0
	var gaps: Array[float] = []
	var most := 0.0
	var stuck := 0.0
	var stuck_most := 0.0
	var far := 0.0
	var far_most := 0.0
	var jumps := 0
	var seen := 0
	var sights := 0.0
	var harm := 0.0
	var harm_was := ""
	var sights_from := -1.0
	var window: Array[Vector2] = []

	func row(id: String) -> String:
		gaps.sort()
		var median := gaps[gaps.size() / 2] if not gaps.is_empty() else 0.0
		var p90 := gaps[int(gaps.size() * .9)] if not gaps.is_empty() else 0.0
		return (
			"%-10s %5.0f %6.1f %6.1f %6.1f %6.1f %5.1f %5d %6d %6.1f %5.1f"
			% [id, ticks * STEP, median, p90, most, stuck_most, far_most, jumps, seen, sights, harm]
		)


## Measures the dog this tick (before: where he was last tick).
func _measure(g: Game, d: Hound.Dog, before: Vector3, t: Tally, spots: Array, h: Hound) -> void:
	var p := g.player
	t.ticks += 1
	var gap := Vector2(d.x - p.x, d.y - p.y).length()
	if t.ticks % 30 == 0:
		t.gaps.append(gap)
	t.most = maxf(t.most, gap)
	var moved := Vector2(d.x - before.x, d.y - before.y).length()
	if moved > 1.2:
		t.jumps += 1
		if _seen(g, p, before.x, before.y, before.z) or _seen(g, p, d.x, d.y, d.floor_z):
			t.seen += 1
	# Stuck: far off and under .3 cells in the last second, not on purpose.
	t.window.append(Vector2(d.x, d.y))
	if t.window.size() > 60:
		t.window.remove_at(0)
	var went := t.window[0].distance_to(t.window[t.window.size() - 1])
	if gap > STUCK_FROM and went < .3 and t.window.size() >= 60 and not STILL.has(d.state):
		t.stuck += STEP
		t.stuck_most = maxf(t.stuck_most, t.stuck)
		if absf(t.stuck - STUCK_MAX) < STEP * .5:
			_tell(g, d, "stuck")
	else:
		t.stuck = 0.0
	if gap > FAR:
		t.far += STEP
		t.far_most = maxf(t.far_most, t.far)
		if absf(t.far - FAR_MAX) < STEP * .5:
			_tell(g, d, "far")
	else:
		t.far = 0.0
	var look := Vector2(cos(p.angle), sin(p.angle))
	var to := Vector2(d.x - p.x, d.y - p.y)
	if (
		gap > .3
		and gap < h.n("clear_reach")
		and to.normalized().dot(look) > h.n("clear_cone")
		and g.world.visible(p.x, p.y, d.x, d.y, p.eye, d.floor_z + .4)
	):
		if t.sights_from < 0.0:
			t.sights_from = g.clock
		t.sights += STEP
	elif t.sights_from >= 0.0:
		if g.clock - t.sights_from > 1.0:
			_tell(g, d, "in sights %.1f s" % (g.clock - t.sights_from))
		t.sights_from = -1.0
	if g.clock >= trace.x and g.clock <= trace.y and t.ticks % 15 == 0:
		_tell(g, d, "trace %.2f a tick %s" % [moved, str(d.path.slice(0, 3))])
	var aloft := d.state == Hound.RIDE or d.hop != Vector2.INF  # in a seat or leaping
	var why := "" if aloft else _harm(g, d, spots)
	if why != "":
		if t.harm_was == "":
			_tell(g, d, "in harm: " + why)
		t.harm += STEP
	t.harm_was = why


## `-- verbose`: where he and his player are and what he is up to.
func _tell(g: Game, d: Hound.Dog, what: String) -> void:
	if not verbose:
		return
	var p := g.player
	print(
		(
			(
				"    %.1f s %s: dog %.1f,%.1f z%.1f  player %.1f,%.1f z%.1f  state %d job %s mood %s"
				+ " path %d no_way %s stall %.1f lost %.1f"
			)
			% [
				g.clock,
				what,
				d.x,
				d.y,
				d.floor_z,
				p.x,
				p.y,
				g.world.stand(p),
				d.state,
				Hound.JOBS[d.job],
				Hound.MOODS[d.mood],
				d.path.size(),
				d.no_way,
				d.stall,
				d.lost
			]
		)
	)


# ------------------------------------------------------------------ the walks


## The player runs the way through, turning round at each stop.
func _walk(id: String) -> void:
	var g := _game(id)
	g.tick(STEP, Game.Controls.new())
	var d := _dog(g)
	if d == null:
		_check(false, "%s: BLUE comes along" % id)
		return
	var h: Hound = g.features["hound"]
	var spots := BrawlHazards.spots(g.world)
	var cells := _way(g)
	if cells.size() > MOST_STEPS:
		cells.resize(MOST_STEPS)
	var p := g.player
	var t := Tally.new()
	var i := 0
	var turn_left := 0.0
	var no_way := 0.0
	var last_gap := INF
	while i < cells.size():
		var c := Game.Controls.new()
		var cell: Vector2i = cells[i]
		if cell.x < 0:
			# A stop: turn round on the spot once (about four seconds).
			if turn_left <= 0.0:
				turn_left = TAU
			var turn := minf(turn_left, TAU / 4.0 * STEP)
			p.angle += turn
			turn_left -= turn
			if turn_left <= 0.0:
				i += 1
		else:
			var aim := Vector2(cell.x + .5, cell.y + .5)
			# Look a couple of cells ahead along the way.
			for k in range(i + 1, mini(i + 3, cells.size())):
				var ahead: Vector2i = cells[k]
				if ahead.x >= 0:
					aim = Vector2(ahead.x + .5, ahead.y + .5)
			var here := Vector2(cell.x + .5, cell.y + .5)
			var gap := here.distance_to(Vector2(p.x, p.y))
			if gap < .55:
				i += 1
				no_way = 0.0
				last_gap = INF
				continue
			p.angle = atan2(aim.y - p.y, aim.x - p.x)
			c.forward = 1.0
			c.running = true
			if gap < last_gap - .01:
				no_way = 0.0
				last_gap = gap
			else:
				no_way += STEP
			if no_way > 1.0:
				# The walker is caught on something: put it on the cell.
				p.x = here.x
				p.y = here.y
				p.floor_z = g.world.floor_under(here.x, here.y, p.floor_z + 1.0)
				p.eye = p.floor_z + .95
				i += 1
				no_way = 0.0
				last_gap = INF
		var before := Vector3(d.x, d.y, d.floor_z)
		g.tick(STEP, c)
		_measure(g, d, before, t, spots, h)
	# Then a little standing still: he should come back to heel.
	for k in 60 * 4:
		var before := Vector3(d.x, d.y, d.floor_z)
		g.tick(STEP, Game.Controls.new())
		_measure(g, d, before, t, spots, h)
	print(t.row(id))
	var bad := []
	if t.stuck_most > STUCK_MAX:
		bad.append("stuck %.1f s" % t.stuck_most)
	if t.far_most > FAR_MAX:
		bad.append("far %.1f s" % t.far_most)
	if t.seen > 0:
		bad.append("%d jumps seen" % t.seen)
	if t.harm > 0.0:
		bad.append("in harm %.1f s" % t.harm)
	if not bad.is_empty():
		_check(false, "%s: %s" % [id, ", ".join(bad)])


## Loaded far from his player, out of their sight: he is back with them in
## good time, never turning up where they look.
func _after_load() -> void:
	var g := _game("hickston")
	g.tick(STEP, Game.Controls.new())
	var p := g.player
	var saved: Dictionary = g.features["hound"].save()
	var rows: Array = saved["dogs"]
	var row: Array = rows[0]
	# The save puts him far off, behind a wall (a load from an old spot).
	var far := Vector2.INF
	for k in 600:
		var at := Vector2(
			2.5 + (k * 37) % maxi(1, g.world.width - 5),
			2.5 + (k * 53) % maxi(1, g.world.height - 5)
		)
		if (
			at.distance_to(Vector2(p.x, p.y)) > 18.0
			and not g.world.blocked(at.x, at.y, .3)
			and not g.world.deep_at(at.x, at.y)
			and not g.world.visible(p.x, p.y, at.x, at.y, p.eye, g.world.elevation(at.x, at.y) + .4)
		):
			far = at
			break
	row[1] = far.x
	row[2] = far.y
	var g2 := _game("hickston")
	g2.features["hound"].restore(saved)
	g2.tick(STEP, Game.Controls.new())
	var d := _dog(g2)
	var spots := BrawlHazards.spots(g2.world)
	var t := Tally.new()
	var back := -1.0
	for k in 60 * 12:
		var before := Vector3(d.x, d.y, d.floor_z)
		g2.tick(STEP, Game.Controls.new())
		_measure(g2, d, before, t, spots, g2.features["hound"])
		if back < 0.0 and Vector2(d.x - p.x, d.y - p.y).length() < 3.0:
			back = k * STEP
	var p2 := g2.player
	var gap := Vector2(d.x - p2.x, d.y - p2.y).length()
	_check(
		gap < 3.0 and t.seen == 0,
		(
			"loaded %.0f cells off, he is back at heel (%.1f off, after %.1f s, %d jumps seen)"
			% [far.distance_to(Vector2(p2.x, p2.y)), gap, back, t.seen]
		)
	)


## His player drives off in a vehicle and gets out far away: he keeps up or
## catches up after.
func _after_ride() -> void:
	for pair: Array in [["speedway", "car"], ["bayou", "airboat"], ["hickston", "mower"]]:
		_ride(str(pair[0]), str(pair[1]))


## One ride: in at the wheel with BLUE beside, a drive about for RIDE
## seconds steering clear of walls, out again; where he was (riding along,
## or how far behind) and how soon he is back at heel.
func _ride(id: String, kind: String) -> void:
	var g := _game(id)
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	g.tick(STEP, Game.Controls.new())
	var i := -1
	for k in rides.rides.size():
		var each: VehicleDrive.Ride = rides.rides[k]
		if each.kind == kind:
			i = k
	var d := _dog(g)
	var p := g.player
	if i < 0 or not rides.seat_in(p, i):
		_check(false, "%s: the player takes the %s's wheel" % [id, kind])
		return
	var v: VehicleDrive.Ride = rides.rides[i]
	var s := VehicleDrive.spec(v.kind)
	# BLUE stands beside it as his player gets in.
	var side := s.width * .5 + .6
	d.x = v.x + sin(v.h) * side
	d.y = v.y - cos(v.h) * side
	d.floor_z = g.world.floor_under(d.x, d.y, v.z + .5)
	var spots := BrawlHazards.spots(g.world)
	var t := Tally.new()
	var near := 0
	var ticks := 0
	var start := Vector2(v.x, v.y)
	for k in 60 * RIDE:
		var c := Game.Controls.new()
		c.forward = 1.0 if k > 60 else 0.0
		p.angle = _clear_way(g, s, v)
		var before := Vector3(d.x, d.y, d.floor_z)
		g.tick(STEP, c)
		_measure(g, d, before, t, spots, g.features["hound"])
		ticks += 1
		if Vector2(d.x - v.x, d.y - v.y).length() < s.length * .5 + 4.0:
			near += 1
	var went := start.distance_to(Vector2(v.x, v.y))
	# Parked back where it started (the airboat on open water has nowhere to
	# step off), and out.
	v.x = start.x
	v.y = start.y
	v.vx = 0.0
	v.vy = 0.0
	var stop := 0
	while rides.seated(p) and stop < 240:
		var c := Game.Controls.new()
		c.forward = -1.0 if VehicleDrive.speed(v) > .3 else 0.0
		if stop > 90 and stop % 20 == 0:
			rides.use(p)
		g.tick(STEP, c)
		stop += 1
	var back := -1.0
	for k in 60 * 12:
		var before := Vector3(d.x, d.y, d.floor_z)
		g.tick(STEP, Game.Controls.new())
		_measure(g, d, before, t, spots, g.features["hound"])
		if back < 0.0 and Vector2(d.x - p.x, d.y - p.y).length() < 3.0:
			back = k * STEP
	_check(
		back >= 0.0 and t.seen == 0 and not rides.seated(p),
		(
			(
				"%s %s: drove %.0f cells, BLUE with it %d%% of the ride, back at heel %.1f s after"
				+ " getting out (%d jumps seen)"
			)
			% [id, kind, went, roundi(100.0 * near / maxi(1, ticks)), back, t.seen]
		)
	)


## A heading for vehicle v that keeps clear of walls a few cells ahead.
func _clear_way(g: Game, s: VehicleDrive.Spec, v: VehicleDrive.Ride) -> float:
	for turn: float in [0.0, .3, -.3, .6, -.6, .9, -.9, 1.3, -1.3, 1.8, -1.8, 2.6, -2.6]:
		var h := v.h + turn
		var ok := true
		for reach: float in [1.5, 3.0, 4.5]:
			var at := Vector2(v.x + cos(h) * reach, v.y + sin(h) * reach)
			if is_nan(VehicleDrive.fits(g.world, s, at.x, at.y, h, v.z)):
				ok = false
				break
		if ok:
			return h
	return v.h + PI * .5


## A new chapter: he starts at his player's heel.
func _new_chapter() -> void:
	for id: String in Campaign.ORDER:
		var g := _game(id)
		g.tick(STEP, Game.Controls.new())
		var d := _dog(g)
		var p := g.player
		var gap := Vector2(d.x - p.x, d.y - p.y).length() if d != null else INF
		if gap > 2.5:
			_check(false, "%s: he starts at the player's heel (%.1f off)" % [id, gap])
	_check(true, "every chapter: he starts at the player's heel")
