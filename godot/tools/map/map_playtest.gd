## Playtests of a map from its source, built in memory and never written
## (LevelData.preview), so an edit can be tried before it is built:
##
## - routes: a bot (the player's own body and controls, god mode) walks from
##   one named place to another on the nav graph: "spawn", an object's id (a
##   station, pickup, spawn point, hand: its place and floor; a deck, ramp,
##   stairs or block: the middle of its top) or [x, y, z]. Each route reports
##   whether it got there, the time, the distance walked, the nav steps and
##   every place it stuck (stood still 1.5 s; it hops and sidesteps, and gives
##   up after 6 s stuck or its time). Doors are opened first (keys too): this
##   tests the geometry, not the order of the quest.
## - enemies: hands woken and set on the player standing at each route's end,
##   on whatever floor that is: how near each got in `seconds`.
## - perf: the software view's frame time from the spawn and every route's
##   ends, and the tick's while the bots walk.
## A scenario is {"routes": [{"id", "from", "to", "seconds"}], "enemies": bool,
## "perf": bool}; with no routes, the spawn to every objective, pickup, spawn
## point and deck. A route fails the playtest; enemies and perf only report.
extends RefCounted

const DT := 1.0 / 60.0


static func _main(tree: SceneTree) -> Control:
	var main: Control = load("res://src/Main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.set_process(false)
	main.state = "title"
	return main


static func _game(main, map_id: String) -> Game:
	var g: Game = main.make_game(map_id)
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.spawn_grace = 0.0
	g.lessons = false
	return g


## Where a named place is: [x, y, z] (z the floor), or [] when it is unknown.
static func place(name, doc: Dictionary, built: Dictionary, lv: LevelData) -> Array:
	if name is Array:
		var z := float(name[2]) if (name as Array).size() > 2 else 0.0
		return [
			float(name[0]), float(name[1]), lv.floor_under(float(name[0]), float(name[1]), z + .05)
		]
	var key := String(name)
	if key == "spawn":
		var s: Array = built["spawn"]
		var z := float(s[3]) if s.size() > 3 else 0.0
		return [s[0], s[1], lv.floor_under(s[0], s[1], z + .05)]
	for o in doc.get("objects", []):
		if not (o is Dictionary) or String(o.get("id", "")) != key:
			continue
		if o.has("at"):
			var at: Array = o["at"]
			var z := float(o.get("z", 0.0))
			return [float(at[0]), float(at[1]), lv.floor_under(float(at[0]), float(at[1]), z + .05)]
		if o.has("rect"):
			var r: Array = o["rect"]
			var mid := Vector2((float(r[0]) + float(r[2])) * .5, (float(r[1]) + float(r[3])) * .5)
			var top := float(o.get("top", o.get("to", 0.0)))
			return [mid.x, mid.y, lv.floor_under(mid.x, mid.y, top + .05)]
	return []


static func default_routes(doc: Dictionary) -> Array:
	var out: Array = []
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var type := String(o.get("type", ""))
		if (
			type
			in ["station", "exit", "pickup", "spawn_point", "deck", "balcony", "bridge", "block"]
		):
			if type == "block" and not bool(o.get("walk", true)):
				continue
			out.append(
				{"id": "spawn_to_" + String(o["id"]), "from": "spawn", "to": String(o["id"])}
			)
	return out


static func run(
	tree: SceneTree, doc: Dictionary, built: Dictionary, scenario: Dictionary, opts: Dictionary
) -> Dictionary:
	var map_id := String(doc["id"])
	LevelData.preview[map_id] = built["level"]
	var main: Control = await _main(tree)
	var lines: Array = []
	var routes: Array = scenario.get("routes", [])
	if routes.is_empty():
		routes = default_routes(doc)
	var results: Array = []
	var passed := true
	var tick_us: Array = []
	for route: Dictionary in routes:
		var g := _game(main, map_id)
		for e: Enemy in g.enemies:
			e.dormant = true
		for d: LevelData.Door in g.world.doors:
			d.opened = true
			d.progress = 1.0
		var a := place(route.get("from", "spawn"), doc, built, g.world)
		var b := place(route.get("to"), doc, built, g.world)
		var name := String(route.get("id", "%s_to_%s" % [route.get("from"), route.get("to")]))
		if a.is_empty() or b.is_empty():
			results.append(
				{
					"id": name,
					"reached": false,
					"error":
					"unknown place %s" % (route.get("from") if a.is_empty() else route.get("to"))
				}
			)
			passed = false
			lines.append("FAIL %s: unknown place" % name)
			continue
		var walk := walk(g, a, b, float(route.get("seconds", 0.0)), tick_us)
		walk["id"] = name
		walk["from"] = a
		walk["to"] = b
		results.append(walk)
		if not bool(walk["reached"]):
			passed = false
		lines.append(
			(
				"%s %s: %s in %.1f s, %.1f walked, %d nav steps%s"
				% [
					"ok  " if walk["reached"] else "FAIL",
					name,
					(
						"reached"
						if walk["reached"]
						else "stopped %.1f short at %s" % [walk["short"], walk["end"]]
					),
					walk["seconds"],
					walk["walked"],
					walk["steps"],
					"" if (walk["stuck"] as Array).is_empty() else ", stuck at %s" % [walk["stuck"]]
				]
			)
		)
	var out := {"passed": passed, "routes": results}
	if bool(scenario.get("enemies", false)) or opts.has("enemies"):
		out["enemies"] = _enemies(
			main, map_id, doc, built, results, float(opts.get("seconds", 20.0)), lines
		)
	if bool(scenario.get("perf", false)) or opts.has("perf"):
		out["perf"] = _perf(main, map_id, results, tick_us, lines)
	lines.append("PLAYTEST %s" % ("OK" if passed else "FAILED"))
	out["lines"] = lines
	LevelData.preview.erase(map_id)
	main.queue_free()
	return out


## Walk the player from a to b ([x, y, floor]): the result's fields as run() says.
static func walk(g: Game, a: Array, b: Array, seconds: float, tick_us: Array) -> Dictionary:
	var w := g.world
	var p := g.player
	p.x = a[0]
	p.y = a[1]
	p.floor_z = a[2]
	p.air = 0.0
	p.eye = .95 + a[2]
	var f := FlowField.new(w)
	f.reach = 1 << 20
	f.doors_open = true
	f.every_door = true
	f.update(b[0], b[1], 0.0, b[2])
	var steps := f.distance(p.x, p.y, a[2])
	var limit := (
		seconds
		if seconds > 0.0
		else 12.0 + Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])) * .9
	)
	var c := Game.Controls.new()
	var stuck: Array = []
	var still := 0.0
	var stuck_total := 0.0
	var mark := Vector2(p.x, p.y)
	var walked := 0.0
	var t := 0.0
	var reached := false
	var wiggle := 0
	while t < limit:
		var here := Vector2(p.x, p.y)
		var feet := w.stand(p)
		if here.distance_to(Vector2(b[0], b[1])) < .45 and absf(feet - b[2]) < .4:
			reached = true
			break
		var heading := f.heading(p.x, p.y, feet)
		if is_nan(heading) or here.distance_to(Vector2(b[0], b[1])) < 1.0:
			heading = atan2(b[1] - p.y, b[0] - p.x)
		p.angle = heading
		c.forward = 1.0
		c.running = true
		c.jump = false
		c.strafe = 0.0
		if wiggle > 0:
			wiggle -= 1
			c.strafe = 1.0 if (int(t * 2.0) % 2) == 0 else -1.0
			c.jump = wiggle == 20
		var began := Time.get_ticks_usec()
		g.tick(DT, c)
		tick_us.append(Time.get_ticks_usec() - began)
		walked += here.distance_to(Vector2(p.x, p.y))
		t += DT
		still += DT
		if Vector2(p.x, p.y).distance_to(mark) > .25:
			mark = Vector2(p.x, p.y)
			still = 0.0
		elif still > 1.5:
			stuck.append([snappedf(p.x, .01), snappedf(p.y, .01), snappedf(w.stand(p), .01)])
			stuck_total += still
			still = 0.0
			wiggle = 40
			if stuck_total > 6.0:
				break
	return {
		"reached": reached,
		"seconds": snappedf(t, .01),
		"walked": snappedf(walked, .01),
		"steps": steps if steps < FlowField.FAR else -1,
		"stuck": stuck,
		"end": [snappedf(p.x, .01), snappedf(p.y, .01), snappedf(w.stand(p), .01)],
		"short": snappedf(Vector2(p.x, p.y).distance_to(Vector2(b[0], b[1])), .01),
	}


static func _enemies(
	main,
	map_id: String,
	_doc: Dictionary,
	_built: Dictionary,
	routes: Array,
	seconds: float,
	lines: Array
) -> Array:
	var out: Array = []
	for r: Dictionary in routes:
		if not r.has("to"):
			continue
		var g := _game(main, map_id)
		var spot: Array = r["to"]
		var p := g.player
		p.x = spot[0]
		p.y = spot[1]
		p.floor_z = spot[2]
		p.eye = .95 + spot[2]
		for d: LevelData.Door in g.world.doors:
			d.opened = true
			d.progress = 1.0
		var nearest := INF
		var arrived: Array = []
		for e: Enemy in g.enemies:
			if not e.hostile:
				continue
			e.dormant = false
			e.alerted = true
			e.hunt_until = 1e9
		var idle := Game.Controls.new()
		for _k in int(seconds / DT):
			g.tick(DT, idle)
			p.health = 100
		for e: Enemy in g.enemies:
			if not e.hostile or not e.alive:
				continue
			var d := Vector2(e.x, e.y).distance_to(Vector2(p.x, p.y))
			nearest = minf(nearest, d)
			if d < 2.5 and absf(g.world.stand(e) - spot[2]) < .5:
				arrived.append(
					(
						String(g.enemy_ids[g.enemies.find(e)])
						if g.enemies.find(e) < g.enemy_ids.size()
						else e.kind
					)
				)
		out.append(
			{"at": r["id"], "floor": spot[2], "nearest": snappedf(nearest, .01), "arrived": arrived}
		)
		lines.append(
			(
				"enemies at %s (floor %.2f): %d came within 2.5 on that floor, nearest %.1f"
				% [r["id"], spot[2], arrived.size(), nearest]
			)
		)
	return out


static func _perf(main, map_id: String, routes: Array, tick_us: Array, lines: Array) -> Dictionary:
	var g := _game(main, map_id)
	var spots: Array = [[g.player.x, g.player.y, g.world.stand(g.player)]]
	for r: Dictionary in routes:
		if r.has("from"):
			spots.append(r["from"])
		if r.has("to"):
			spots.append(r["to"])
	var times: Array = []
	var canvas := Canvas.new()
	for s: Array in spots:
		var p := g.player
		p.x = s[0]
		p.y = s[1]
		p.floor_z = s[2]
		p.eye = .95 + s[2]
		for k in 8:
			p.angle = k * TAU / 8.0
			var began := Time.get_ticks_usec()
			g.draw(canvas, 1, false)
			times.append((Time.get_ticks_usec() - began) / 1000.0)
	times.sort()
	tick_us.sort()
	var out := {
		"frames": times.size(),
		"frame_ms_median": snappedf(times[times.size() / 2], .01) if not times.is_empty() else 0.0,
		"frame_ms_max": snappedf(times[times.size() - 1], .01) if not times.is_empty() else 0.0,
		"tick_ms_median":
		snappedf(tick_us[tick_us.size() / 2] / 1000.0, .001) if not tick_us.is_empty() else 0.0,
		"tick_ms_p99":
		(
			snappedf(tick_us[int(tick_us.size() * .99)] / 1000.0, .001)
			if not tick_us.is_empty()
			else 0.0
		),
	}
	(
		lines
		. append(
			(
				"perf: software view %.1f ms median, %.1f max over %d frames; tick %.3f ms median, %.3f p99"
				% [
					out["frame_ms_median"],
					out["frame_ms_max"],
					out["frames"],
					out["tick_ms_median"],
					out["tick_ms_p99"]
				]
			)
		)
	)
	return out


## The game's own view (the software view with the palette, as the tools draw
## it) from each of `views` ({tag, at: [x, y, z], angle, pitch} in degrees).
static func shots(
	tree: SceneTree, map_id: String, level: Dictionary, views: Array, dir: String
) -> Array:
	LevelData.preview[map_id] = level
	var main: Control = await _main(tree)
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Array = []
	var g := _game(main, map_id)
	for v: Dictionary in views:
		var at: Array = v.get("at", [g.player.x, g.player.y, 0.0])
		var p := g.player
		p.x = float(at[0])
		p.y = float(at[1])
		p.floor_z = g.world.floor_under(p.x, p.y, (float(at[2]) if at.size() > 2 else 0.0) + .05)
		p.air = 0.0
		p.eye = .95 + p.floor_z
		p.angle = deg_to_rad(float(v.get("angle", 0.0)))
		p.pitch = float(v.get("pitch", 0.0))
		p.sway = 0.0
		g.armory.holstered = not bool(v.get("weapon", false))
		g.armory.lower = 1.0 if g.armory.holstered else 0.0
		g.message_until = 0.0
		g.district_until = 0.0
		var canvas := Canvas.new()
		canvas.clear(0, 0, 0)
		g.draw(canvas, 1, false)
		_palette(canvas, g.art.palette)
		var image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)
		var path := dir.path_join("%s.png" % String(v.get("tag", "view%d" % out.size())))
		image.save_png(path)
		out.append(path)
	LevelData.preview.erase(map_id)
	main.queue_free()
	return out


static func _palette(canvas: Canvas, lut: PackedByteArray) -> void:
	var pix := canvas.pixels
	for i in range(0, pix.size(), 3):
		var r5 := (pix[i] * 31 + 127) / 255
		var g5 := (pix[i + 1] * 31 + 127) / 255
		var b5 := (pix[i + 2] * 31 + 127) / 255
		var at := ((r5 << 10) | (g5 << 5) | b5) * 3
		pix[i] = lut[at]
		pix[i + 1] = lut[at + 1]
		pix[i + 2] = lut[at + 2]
	canvas.pixels = pix
