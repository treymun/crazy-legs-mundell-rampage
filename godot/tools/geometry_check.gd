## Checks of level format 2's geometry (src/level_geometry.gd) on a small
## level built here and never written (LevelData.preview):
##
##   Godot --headless --path <project> --script res://tools/geometry_check.gd [-- out=<dir>]
##
## A deck with a passage under it, stairs up to it, a ramp, a thin wall with
## a doorway and a window cut to size, a rail, an angled wall, a low
## crawlspace. It checks what stands where, what blocks a body, a look and a
## shot, that a player walks under the deck, climbs the stairs and the ramp,
## falls off an open edge, keeps out of the wall but through its doorway; that
## a shot from the deck reaches the ground past its edge but not through it;
## that the nav graph tells the deck from the floor under it and leads up the
## stairs; that both views draw it; that a save keeps the floor a body is on.
## out=<dir> saves the pictures.
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const DT := 1.0 / 60.0
const ID := "_geometry_check"
const DECK := 1.6

var failures: Array = []
static var out_dir := ""


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## The test level: a 24 x 16 yard walled round.
static func level() -> Dictionary:
	var b = Builder.new(ID, 24, 16, "hedgerow")
	var yard: int = b.district("TEST YARD")
	b.yard(1, 1, 22, 14, "dirt", yard)
	# A deck 1.6 up over x 8..14, y 4..8: the passage under it runs east-west.
	Geo.deck(b, "deck", [8, 4, 14, 8], DECK, {"tile": "porch", "edge": "barn"})
	# Stairs up its west side from x 4 to 8 (y 4..5.2): 8 treads of .2.
	Geo.stairs(b, "stairs", [4, 4, 8, 5.2], 0.0, DECK, "e")
	# A ramp up to it from the south: x 12..13.4, y 8..12, rising north.
	Geo.ramp(b, "ramp", [12, 8, 13.4, 12], 0.0, DECK, "n", {"tile": "porch"})
	# A rail along its north edge, its east edge open.
	Geo.rail(b, "rail", Vector2(8, 4.06), Vector2(14, 4.06), DECK)
	# A thin wall at x 18, y 1..14, with a doorway at y 3 and a window at y 10.
	(
		Geo
		. wall(
			b,
			"wall",
			Vector2(18, 1),
			Vector2(18, 15),
			0.0,
			2.2,
			{
				"openings":
				[
					{"at": 2.5, "width": 1.0},
					{"at": 9.5, "width": 1.2, "sill": .9, "head": 1.7},
				]
			}
		)
	)
	# An angled wall in the yard's south-west.
	Geo.wall(b, "angled", Vector2(2, 10), Vector2(6, 14), 0.0, 2.0, {"tile": "brick"})
	# A crawlspace too low to walk: a slab .7 up over x 20..22, y 10..12.
	Geo.deck(b, "crawl", [20, 10, 22, 12], .8, {"thick": .1})
	b.enemy("billy", 11.0, 6.0, "ground_billy")
	var spawn := [2.5, 6.5, 0.0]
	var out: Dictionary = b.finish(spawn)
	return out


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out_dir = String(arg).substr(4)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(main, _check)
	preload("res://tools/map_check.gd").run(main, _check)
	print("")
	print("GEOMETRY CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The checks, for tools/check_fixes.gd too.
static func run(main, check: Callable) -> void:
	print("LEVEL FORMAT 2: DECKS, STAIRS, RAMPS, THIN WALLS, NAV BETWEEN FLOORS")
	LevelData.preview[ID] = level()
	_queries(main, check)
	_walking(main, check)
	_shooting(main, check)
	_nav(main, check)
	_views(main, check)
	_saves(main, check)
	LevelData.preview.erase(ID)


static func _game(main) -> Game:
	var g: Game = main.make_game(ID)
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 0.0
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


static func _queries(main, check: Callable) -> void:
	print("queries")
	var g := _game(main)
	var w: LevelData = g.world
	check.call(w.format == 2 and w.geo != null, "the level is format 2 with geometry")
	check.call(
		is_equal_approx(w.floor_under(11, 6, .5), 0.0), "under the deck the floor is the ground"
	)
	check.call(
		is_equal_approx(w.floor_under(11, 6, 2.0), DECK), "on the deck the floor is the deck"
	)
	check.call(
		is_equal_approx(w.roof_over(11, 6, 0.0), DECK - .15),
		"under the deck its underside is overhead"
	)
	check.call(w.roof_over(11, 6, DECK) == 0.0, "on the deck the sky is overhead")
	check.call(w.blocked(18.0, 8.0, .2), "the thin wall stops a body")
	check.call(not w.blocked(18.0, 3.5, .2), "its doorway does not")
	check.call(not w.visible(16.5, 8.0, 19.5, 8.0, .95, .95), "the wall stops a look")
	check.call(w.visible(16.5, 3.5, 19.5, 3.5, .95, .95), "a look through the doorway")
	check.call(w.visible(16.5, 10.5, 19.5, 10.5, 1.3, 1.3), "a look through the window")
	check.call(not w.visible(16.5, 10.5, 19.5, 10.5, .5, .5), "not under its sill")
	check.call(w.visible(11, 3.0, 11, 5.0, DECK + .95, DECK + .95), "a look over the rail")
	check.call(not w.visible(11, 2.0, 11, 6.0, 1.5, 1.5), "not through the deck's edge")
	check.call(w.visible(11, 2.0, 11, 6.0, 1.0, 1.0), "but under it")
	check.call(w.visible(9.0, 6.0, 13.0, 6.0, .95, .95), "a look along the passage under the deck")
	check.call(not w.visible(11, 6.0, 11, 6.2, 1.2, 2.0), "not up through the deck")
	check.call(w.blocked(4.0, 12.0, .2), "the angled wall stops a body")
	check.call(
		is_equal_approx(w.floor_under(12.7, 10.0, 2.0), DECK * .5), "half way up the ramp is .8 up"
	)


## Walk the player with forward held toward `goal` for up to `seconds`.
static func _walk(g: Game, goal: Vector2, seconds: float, crouch := false) -> void:
	var c := Game.Controls.new()
	c.forward = 1.0
	c.crouch = crouch
	for _k in int(seconds * 60.0):
		var p := g.player
		if Vector2(p.x, p.y).distance_to(goal) < .15:
			break
		p.angle = atan2(goal.y - p.y, goal.x - p.x)
		g.tick(DT, c)
	g.tick(DT, Game.Controls.new())


static func _settle(g: Game, seconds: float) -> void:
	for _k in int(seconds * 60.0):
		g.tick(DT, Game.Controls.new())


static func _walking(main, check: Callable) -> void:
	print("walking")
	var g := _game(main)
	var p := g.player
	p.x = 6.5
	p.y = 6.5
	_walk(g, Vector2(16.0, 6.5), 6.0)
	check.call(p.x > 15.5, "walked east under the deck (x %.2f)" % p.x)
	check.call(absf(g.world.stand(p)) < .01, "and stayed on the ground (%.2f)" % g.world.stand(p))
	# Up the stairs: from their foot at x 3.5 along y 4.6 onto the deck.
	p.x = 3.0
	p.y = 4.6
	p.floor_z = 0.0
	_walk(g, Vector2(10.0, 4.8), 6.0)
	_settle(g, .5)
	check.call(
		absf(g.world.stand(p) - DECK) < .01,
		"climbed the stairs onto the deck (%.2f)" % g.world.stand(p)
	)
	check.call(absf(p.eye - (DECK + .95)) < .06, "the eye is over the deck (%.2f)" % p.eye)
	# Off the open east edge: falls to the ground.
	_walk(g, Vector2(15.5, 6.0), 4.0)
	_settle(g, 1.5)
	check.call(p.x > 14.2, "walked off the deck's east edge (x %.2f)" % p.x)
	check.call(absf(g.world.stand(p)) < .01 and p.air < .01, "and fell to the ground")
	# Not north past the rail: from the deck toward y 2.
	p.x = 11.0
	p.y = 5.0
	p.floor_z = DECK
	p.air = 0.0
	_walk(g, Vector2(11.0, 2.0), 2.0)
	check.call(p.y > 4.0 and absf(g.world.stand(p) - DECK) < .01, "the rail held (y %.2f)" % p.y)
	# Up the ramp from the south.
	p.x = 12.7
	p.y = 13.0
	p.floor_z = 0.0
	_walk(g, Vector2(12.7, 6.0), 6.0)
	check.call(
		absf(g.world.stand(p) - DECK) < .01,
		"walked up the ramp onto the deck (%.2f)" % g.world.stand(p)
	)
	# The thin wall: not through it, through its doorway.
	p.x = 16.5
	p.y = 8.0
	p.floor_z = 0.0
	_walk(g, Vector2(20.0, 8.0), 3.0)
	check.call(p.x < 18.0, "kept out of the thin wall (x %.2f)" % p.x)
	p.x = 16.5
	p.y = 3.5
	_walk(g, Vector2(20.0, 3.5), 3.0)
	check.call(p.x > 19.5, "through its doorway (x %.2f)" % p.x)
	# The crawlspace (.7 of headroom): not walked into standing.
	p.x = 19.0
	p.y = 11.0
	_walk(g, Vector2(21.5, 11.0), 3.0)
	check.call(p.x < 20.0, "too low to walk under (x %.2f)" % p.x)


static func _shooting(main, check: Callable) -> void:
	print("shooting")
	var g := _game(main)
	var p := g.player
	var e: Enemy = g.enemies[0]
	e.dormant = false
	# The hand stands on the ground east of the deck; the player on the deck.
	e.x = 15.5
	e.y = 6.0
	e.floor_z = 0.0
	p.x = 13.0
	p.y = 6.0
	p.floor_z = DECK
	p.eye = DECK + .95
	var hp := e.hp
	var d := e.x - p.x
	var slope := (g.world.stand(e) + e.height * .5 - p.eye) / d
	g.hitscan(0.0, slope, 20.0, 30.0, 0.0)
	check.call(e.hp < hp, "a shot from the deck past its edge hits a hand on the ground")
	# Now under the deck: a shot straight down does not reach it.
	e.x = 11.0
	e.y = 6.0
	p.x = 9.5
	hp = e.hp
	d = e.x - p.x
	slope = (g.world.stand(e) + e.height * .5 - p.eye) / d
	g.hitscan(0.0, slope, 20.0, 30.0, 0.0)
	check.call(is_equal_approx(e.hp, hp), "the deck stops a shot down at a hand under it")
	check.call(
		absf(g.world.stand(e)) < .01 and absf(g.world.stand(p) - DECK) < .01,
		"each stands on their own floor"
	)


static func _nav(main, check: Callable) -> void:
	print("nav")
	var g := _game(main)
	var w: LevelData = g.world
	var f := FlowField.new(w)
	check.call(
		f.graph != null and f.graph.count > w.width * w.height, "the nav graph has deck nodes"
	)
	var under := f.graph.node_at(11.5, 6.5, w.width, w.height, 0.0)
	var on := f.graph.node_at(11.5, 6.5, w.width, w.height, DECK)
	check.call(
		under != on and under == 6 * w.width + 11, "the deck and the floor under it are apart"
	)
	f.reach = 100000
	f.update(11.5, 6.5, 0.0, DECK)
	var from_ground := f.distance(10.5, 12.5, 0.0)
	check.call(from_ground < FlowField.FAR, "the ground reaches the deck (%d steps)" % from_ground)
	var below := f.distance(11.5, 6.5, 0.0)
	check.call(below > 4 and below < FlowField.FAR, "the spot under it is a walk away (%d)" % below)
	var lead := f.heading(11.5, 6.5, 0.0)
	check.call(not is_nan(lead), "and the way leads off")
	# Walk a hand from under the deck to the player on it.
	var e: Enemy = g.enemies[0]
	e.x = 10.5
	e.y = 6.5
	e.floor_z = 0.0
	var p := g.player
	p.x = 10.5
	p.y = 5.5
	p.floor_z = DECK
	p.eye = DECK + .95
	var path: Array = []
	f.update(p.x, p.y, 1.0, DECK)
	var at := Vector2(e.x, e.y)
	var z := 0.0
	for _i in 60:
		var n := f.graph.node_at(at.x, at.y, w.width, w.height, z)
		var m := f.downhill_node(n)
		if m < 0:
			break
		at = Vector2(f.graph.cell[m] % w.width + .5, f.graph.cell[m] / w.width + .5)
		z = f.graph.z[m]
		path.append(at)
	check.call(not path.is_empty() and absf(z - DECK) < .05, "the steps lead up onto the deck")
	var by_stairs := false
	for q: Vector2 in path:
		if q.x < 8.0 or q.y > 8.0:
			by_stairs = true
	check.call(by_stairs, "by the stairs or the ramp, not straight up")


static func _views(main, check: Callable) -> void:
	print("views")
	var g := _game(main)
	var p := g.player
	for view: Array in [
		["under", 6.5, 6.5, 0.0, 0.0, 0.0],
		["deck", 9.0, 6.0, 0.0, DECK, 0.0],
		["stairs", 2.5, 7.5, -.6, 0.0, 0.0],
		["ramp", 12.7, 14.0, -PI * .5, 0.0, 0.0],
		["wall", 15.0, 9.0, 0.0, 0.0, 0.0],
	]:
		p.x = view[1]
		p.y = view[2]
		p.angle = view[3]
		p.floor_z = view[4]
		p.air = 0.0
		p.eye = .95 + g.world.stand(p)
		p.pitch = view[5]
		g.armory.holstered = true
		g.armory.lower = 1.0
		g.message_until = 0.0
		g.district_until = 0.0
		var canvas := Canvas.new()
		canvas.clear(0, 0, 0)
		g.draw(canvas, 1, false)
		var image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)
		var lit := 0
		for y in range(0, 150, 5):
			for x in range(0, 320, 5):
				if image.get_pixel(x, y).get_luminance() > .02:
					lit += 1
		check.call(lit > 400, "the software view draws %s (%d lit samples)" % [view[0], lit])
		if out_dir != "":
			DirAccess.make_dir_recursive_absolute(out_dir)
			image.save_png("%s/geometry_%s.png" % [out_dir, view[0]])


static func _saves(main, check: Callable) -> void:
	print("saves")
	var g := _game(main)
	var p := g.player
	p.x = 11.0
	p.y = 6.0
	p.floor_z = DECK
	p.eye = DECK + .95
	var e: Enemy = g.enemies[0]
	e.x = 10.0
	e.y = 6.5
	e.floor_z = DECK
	# Not a campaign chapter: saved as a replay (no chapters before it).
	g.replay = true
	var doc: Dictionary = SessionStore.snapshot(g)
	var h: Game = SessionStore.restore_onto(doc, main.make_game(ID))
	var ok := h != null
	check.call(ok, "a save of the level loads (%s)" % SessionStore.last_error)
	if ok:
		check.call(absf(h.world.stand(h.player) - DECK) < .01, "the player is on the deck again")
		check.call(absf(h.world.stand(h.enemies[0]) - DECK) < .01, "and so is the hand")
