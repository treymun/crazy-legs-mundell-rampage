## WAYS CHECK (pass 16, T4 WAYS): doors up on a storey and wider than a
## cell, panes in the geometry's walls, via points, the automap by floor, on
## a test level of its own: a two-storey house (an off-grid doorway, a stair,
## a loft door upstairs, a window with glass) and a barn (a double door and a
## barn door). Checks a hand and a bot come in through the off-grid doorway
## (and the bot up the stair to the loft) on the level with the ways, and the
## same doorway is no way on it without; the loft door opened, keyed, barred,
## closed on someone (and not on a body under it), locked and closed by
## triggers, carried to a client; the double door and the barn door; the pane
## shot out, carried to a client and in a save; the nav graph's vias baked and
## read back, built twice the same; the automap's storey; broken ways refused.
##
##   Godot --headless --path <project> --script res://tools/ways_check.gd [-- write=<file>]
##
## write=<file> also writes the test level there with the barn door open (a
## window tour of it, under res://data/<id>.json for the tour's run only).
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const ID := "zz_ways"
const DT := 1.0 / 60.0
## The loft's floor.
const LOFT := 2.6

var failures: Array = []
var write_to := ""


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## The test level (`barn_open`: the barn door slid open, for the pictures).
static func level(barn_open := false) -> Dictionary:
	var b = Builder.new(ID, 40, 26, "hedgerow")
	var yard: int = b.district("WAYS")
	b.yard(1, 1, 38, 24, "dirt", yard)
	Geo.ways(b)
	# The house: walls on the cells' edges, x 4 to 14, y 4 to 12, two storeys.
	var wall := {"thick": .12, "tile": "plaster", "area": yard}
	Geo.wall(b, "h_w", Vector2(4, 4), Vector2(4, 12), 0.0, LOFT, wall)
	Geo.wall(b, "h_n", Vector2(4, 4), Vector2(14, 4), 0.0, LOFT, wall)
	var east := wall.duplicate()
	east["openings"] = [{"at": 3.5, "width": 1.2, "sill": .9, "head": 1.9, "pane": true}]
	Geo.wall(b, "h_e", Vector2(14, 4), Vector2(14, 12), 0.0, LOFT, east)
	# The way in: a doorway .8 wide whose middle is on a cell's corner, so no
	# cell's middle walks through it.
	var south := wall.duplicate()
	south["openings"] = [{"at": 3.0, "width": .8}]
	Geo.wall(b, "h_s", Vector2(4, 12), Vector2(14, 12), 0.0, LOFT, south)
	for side: Array in [["u_w", 4, 4, 4, 12], ["u_n", 4, 4, 14, 4], ["u_e", 14, 4, 14, 12]]:
		Geo.wall(b, side[0], Vector2(side[1], side[2]), Vector2(side[3], side[4]), LOFT, 5.2, wall)
	Geo.wall(b, "u_s", Vector2(4, 12), Vector2(14, 12), LOFT, 5.2, wall)
	# The loft: a floor over the house but the stairwell, the stair up to it
	# running north, a wall across it with the loft door.
	var floor_o := {"thick": .15, "tile": "porch", "area": yard}
	Geo.deck(b, "loft_w", [4, 4, 12, 12], LOFT, floor_o)
	Geo.deck(b, "loft_e", [13, 4, 14, 12], LOFT, floor_o)
	Geo.deck(b, "landing", [12, 4, 13, 5], LOFT, floor_o)
	Geo.deck(b, "over_foot", [12, 11, 13, 12], LOFT, floor_o)
	Geo.stairs(b, "stair", [12, 5, 13, 11], 0.0, LOFT, "n", {"tile": "porch", "area": yard})
	var part := wall.duplicate()
	part["openings"] = [{"at": 4.5, "width": 1.0}]
	Geo.wall(b, "u_mid", Vector2(4, 8.5), Vector2(14, 8.5), LOFT, 5.2, part)
	Geo.door(b, 8, 8, false, {"z": LOFT, "id": "loft_door"})
	Geo.ceiling(b, "roof", [4, 4, 14, 12], 5.2, {"area": yard})
	# The barn: walls along the cells' middles; a pair of doors north, a barn
	# door south.
	var barn := {"thick": .14, "tile": "barn", "area": yard}
	Geo.wall(b, "b_w", Vector2(20.5, 4.5), Vector2(20.5, 12.5), 0.0, 3.0, barn)
	Geo.wall(b, "b_e", Vector2(30.5, 4.5), Vector2(30.5, 12.5), 0.0, 3.0, barn)
	var north := barn.duplicate()
	north["openings"] = [{"at": 7.5, "width": 2.0}]
	Geo.wall(b, "b_n", Vector2(20.5, 4.5), Vector2(30.5, 4.5), 0.0, 3.0, north)
	var back := barn.duplicate()
	back["openings"] = [{"at": 5.0, "width": 3.0}]
	Geo.wall(b, "b_s", Vector2(20.5, 12.5), Vector2(30.5, 12.5), 0.0, 3.0, back)
	Geo.door(b, 27, 4, false, {"span": 2, "id": "barn_pair"})
	Geo.door(
		b, 24, 12, false, {"span": 3, "style": "slide", "id": "barn_door", "opened": barn_open}
	)
	b.enemy("billy", 7.5, 18.5, "yard_billy")
	b.enemy("billy", 6.5, 6.5, "loft_billy")
	return b.finish([2.5, 20.5, 0.0])


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("write="):
			write_to = String(arg).substr(6)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var made := level()
	if write_to != "":
		var f := FileAccess.open(write_to, FileAccess.WRITE)
		f.store_string(JSON.stringify(level(true)))
		f.close()
	LevelData.preview[ID] = made
	_data(made)
	_nav(main, made)
	_hand_and_bot(main)
	_loft_door(main)
	_wide_doors(main)
	_pane(main)
	_automap(main)
	_refused()
	LevelData.preview.erase(ID)
	print("")
	print("WAYS CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main, id := ID) -> Game:
	var g: Game = main.make_game(id)
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 0.0
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


func _place(g: Game, x: float, y: float, z: float, angle := 0.0) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.floor_z = z
	p.air = 0.0
	p.angle = angle
	p.eye = .95 + z


## Walks the player straight at `goal` for at most `seconds`.
func _walk(g: Game, goal: Vector2, seconds: float) -> void:
	var c := Game.Controls.new()
	c.forward = 1.0
	for _k in int(seconds * 60.0):
		var p := g.player
		if Vector2(p.x, p.y).distance_to(goal) < .15:
			break
		p.angle = atan2(goal.y - p.y, goal.x - p.x)
		g.tick(DT, c)
	for _k in 20:
		g.tick(DT, Game.Controls.new())


func _door(g: Game, id: String) -> LevelData.Door:
	for d: LevelData.Door in g.world.doors:
		if d.id == id:
			return d
	return null


func _data(made: Dictionary) -> void:
	print("data")
	var block: Dictionary = made["geometry"]
	_check(block.get("nav_via", false) == true, "Geo.ways writes nav_via")
	var vias: Array = block.get("vias", [])
	# The south doorway (7, 12, 0), the loft door's opening, the barn's two,
	# the stair's foot and head; the window (a pane) is none.
	_check(vias.has([7.0, 12.0, 0.0]), "the off-grid doorway's middle is a via")
	_check(vias.has([12.5, 11.0, 0.0]) and vias.has([12.5, 5.0, LOFT]), "so are the stair's ends")
	_check(vias.has([8.5, 8.5, LOFT]), "the loft door's opening is one on its floor")
	_check(not vias.has([14.0, 7.5, 0.9]), "a window is none")
	var panes: Array = made.get("geo_panes", [])
	_check(
		(
			panes.size() == 1
			and JSON.stringify(panes[0]) == '{"a":[14.0,6.9],"b":[14.0,8.1],"z0":0.9,"z1":1.9}'
		),
		"the window's glass is a geo pane: %s" % [panes]
	)
	var doors: Array = made["doors"]
	var spans := []
	for d: Dictionary in doors:
		spans.append([d.get("z", 0.0), d.get("span", 1)])
	_check(spans == [[LOFT, 1], [0.0, 2], [0.0, 3]], "doors written with z and span: %s" % [spans])
	_check(JSON.stringify(level()) == JSON.stringify(made), "the same level twice, to the byte")
	var plain = Builder.new("zz_plain", 12, 12, "hedgerow")
	plain.yard(1, 1, 10, 10, "dirt", plain.district("P"))
	Geo.wall(plain, "w", Vector2(2, 6), Vector2(10, 6), 0.0, 2.4, {"openings": [{"at": 3.0}]})
	plain.door(5, 2, false)
	var flat: Dictionary = plain.finish([1.5, 1.5, 0.0])
	var fblock: Dictionary = flat["geometry"]
	var fdoor: Dictionary = flat["doors"][0]
	_check(
		not fblock.has("nav_via") and not fblock.has("vias") and not flat.has("geo_panes"),
		"a level without the ways writes none of it"
	)
	_check(not fdoor.has("z") and not fdoor.has("span"), "nor a door's z or span")


func _nav(main, made: Dictionary) -> void:
	print("nav graph")
	var g := _game(main)
	var w := g.world
	_check(w.geo.nav_via and w.geo.vias.size() >= 6, "the level reads %d vias" % w.geo.vias.size())
	var graph := w.geo.nav(w)
	_check(not graph.vias.is_empty(), "%d via edges" % (graph.vias.size() / 2))
	var inside := graph.node_at(6.5, 11.5, w.width, w.height, 0.0)
	var outside := graph.node_at(6.5, 12.5, w.width, w.height, 0.0)
	var bent: Variant = graph.vias.get(inside * graph.count + outside)
	_check(bent != null, "the house's inside and the yard are joined through the doorway")
	_check(
		bent != null and Vector2((bent as Vector3).x, (bent as Vector3).y) == Vector2(7, 12),
		"bent through its middle"
	)
	var again := LevelNav.build_nav(w.geo, w)
	_check(
		again.edges == graph.edges and again.first == graph.first and again.vias == graph.vias,
		"built twice, the same graph"
	)
	var back := LevelBakes.nav_from(LevelBakes.nav_row(graph))
	_check(
		back != null and back.vias == graph.vias and back.edges == graph.edges,
		"baked and read back with its vias"
	)
	var bare := made.duplicate(true)
	(bare["geometry"] as Dictionary).erase("nav_via")
	bare["id"] = ID + "_bare"
	LevelData.preview[ID + "_bare"] = bare
	var h := _game(main, ID + "_bare")
	var hw := h.world
	var hg := hw.geo.nav(hw)
	_check(hg.vias.is_empty(), "without nav_via no via edges")
	var hin := hg.node_at(6.5, 11.5, hw.width, hw.height, 0.0)
	var hout := hg.node_at(6.5, 12.5, hw.width, hw.height, 0.0)
	var joined := false
	for e in range(hg.first[hin], hg.first[hin + 1]):
		joined = joined or hg.edges[e] == hout
	_check(not joined, "and the doorway is no way: it misses every cell's middle")
	_place(h, 8.5, 6.5, 0.0)
	h.player.flow.update(8.5, 6.5, 0.0, 0.0)
	_check(
		h.player.flow.distance(7.5, 18.5, 0.0) == FlowField.FAR,
		"a hand in the yard has no way in to the player"
	)
	LevelData.preview.erase(ID + "_bare")


func _hand_and_bot(main) -> void:
	print("a hand and a bot through the doorway")
	var g := _game(main)
	_place(g, 8.5, 6.5, 0.0)
	g.player.flow.update(8.5, 6.5, 0.0, 0.0)
	var steps := g.player.flow.distance(7.5, 18.5, 0.0)
	_check(steps < FlowField.FAR, "the yard is %d steps from the player inside" % steps)
	var hand: Enemy = g.enemies[0]
	hand.dormant = false
	hand.wake(g, g.player.x, g.player.y)
	var came := false
	for _k in 60 * 25:
		g.tick(DT, Game.Controls.new())
		if hand.y < 11.6 and hand.x > 4.0 and hand.x < 14.0:
			came = true
			break
	_check(came, "the hand came in through it (at %.1f, %.1f)" % [hand.x, hand.y])
	# A bot: the player steered by the 5v5 bots' step field to the loft.
	var b := _game(main)
	_place(b, 7.5, 18.5, 0.0)
	var goal := Vector2(6.5, 6.5)
	var field := TacticalNav.field(b, goal.x, goal.y, LOFT)
	var c := Game.Controls.new()
	c.forward = 1.0
	var got := false
	var through := false
	for _k in 60 * 40:
		var p := b.player
		var feet := b.world.stand(p)
		if Vector2(p.x, p.y).distance_to(goal) < .6 and absf(feet - LOFT) < .1:
			got = true
			break
		var head := field.heading(p.x, p.y, feet)
		p.angle = head if not is_nan(head) else atan2(goal.y - p.y, goal.x - p.x)
		b.tick(DT, c)
		through = through or (p.y < 11.8 and p.x > 6.5 and p.x < 7.5)
	_check(through, "the bot walked in through the doorway")
	_check(
		got,
		(
			"and up the stair to the loft (at %.1f, %.1f, floor %.2f)"
			% [b.player.x, b.player.y, b.world.stand(b.player)]
		)
	)
	_check(
		TacticalNav.floor_of(b, Vector2(b.player.x, b.player.y)) > LOFT - .1,
		"a goal where a player stands up there is on the loft's floor"
	)


func _loft_door(main) -> void:
	print("the loft door")
	var g := _game(main)
	var w := g.world
	var door := _door(g, "loft_door")
	_check(door != null and door.raised() and absf(door.z - LOFT) < .001, "it stands on the loft")
	_check(w.solid[8 * w.width + 8] < 0, "its cell is open floor below")
	# Under it on the ground: no door.
	_place(g, 8.5, 10.5, 0.0, -PI * .5)
	_walk(g, Vector2(8.5, 6.5), 4.0)
	_check(g.player.y < 7.0, "a body walks under it on the ground (to y %.2f)" % g.player.y)
	# Up there, shut: in the way.
	_place(g, 8.5, 10.5, LOFT, -PI * .5)
	_walk(g, Vector2(8.5, 6.5), 3.0)
	_check(g.player.y > 8.6, "shut, it stops a body on the loft (at y %.2f)" % g.player.y)
	var rows := w.active_walls(false).slice(w.active_base(false).size())
	var drawn := false
	for o in range(0, rows.size(), LevelData.WALL_STRIDE):
		if absf(rows[o + 1] - 8.5) < .01 and absf(rows[o] - 8.0) < .01:
			drawn = absf(rows[o + 6] - LOFT) < .01 and absf(rows[o + 7] - LOFT - 1.85) < .01
	_check(drawn, "its leaf is drawn from the loft's floor up")
	# The flow field: the place on its floor is the door's, the ground's is not.
	var f := g.player.flow
	var up := f.door_nodes(door)
	_check(up.size() == 1 and up[0] >= w.width * w.height, "its place is the loft's node")
	_check(f.open[up[0]] == 2 and f.open[8 * w.width + 8] == 1, "the loft's node waits on it")
	_check(not f.passable(up[0]), "shut, no way through it")
	# Opened with USE from its own floor (and not from the ground under it).
	_place(g, 8.5, 9.6, 0.0, -PI * .5)
	_check(g.use_target() == null, "USE does not find it from the ground under it")
	_place(g, 8.5, 9.6, LOFT, -PI * .5)
	var target: Variant = g.use_target()
	_check(target is Array and target[0] == door, "USE finds it on the loft")
	g.interact()
	for _k in 60:
		g.tick(DT, Game.Controls.new())
	_check(door.opened and door.progress >= 1.0, "and opens it")
	_check(f.passable(up[0]), "open, the way is through it")
	_walk(g, Vector2(8.5, 6.5), 3.0)
	_check(g.player.y < 7.0, "and a body walks through (to y %.2f)" % g.player.y)
	# Closed on someone standing in it: it waits; not on a body under it.
	_place(g, 8.5, 8.5, LOFT)
	g.toggle_door(door, false)
	for _k in 60:
		g.tick(DT, Game.Controls.new())
	_check(door.progress > .9, "it does not close on someone in it (%.2f)" % door.progress)
	_place(g, 8.5, 8.5, 0.0)
	for _k in 90:
		g.tick(DT, Game.Controls.new())
	_check(door.progress <= 0.0, "nor wait for a body under it (%.2f)" % door.progress)
	# Keyed: refused without its key, opened with it.
	door.key = "key_brass"
	_place(g, 8.5, 9.6, LOFT, -PI * .5)
	g.interact()
	_check(not door.opened, "keyed, it stays shut without the key")
	g.keys["key_brass"] = true
	g.interact()
	_check(door.opened, "and opens with it")
	door.key = ""
	g.toggle_door(door, false)
	door.progress = 0.0
	# Barred from the north: kicked open only from there.
	door.bar_side = -1
	_place(g, 8.5, 9.6, LOFT, -PI * .5)
	g.interact()
	_check(not door.opened, "barred from the north, not from the south")
	_place(g, 8.5, 7.4, LOFT, PI * .5)
	g.interact()
	for _k in 90:
		g.tick(DT, Game.Controls.new())
	_check(door.opened, "but from the north (the bar kicked loose)")
	door.bar_side = 0
	# Triggers: lock, then open; close.
	Triggers.run(g, {"lock": "loft_door"})
	_check(not door.opened and w.controlled_doors.has(Vector2i(8, 8)), "a trigger locks it")
	_place(g, 8.5, 9.6, LOFT, -PI * .5)
	g.interact()
	_check(not door.opened, "and USE cannot open it then")
	Triggers.run(g, {"open": "loft_door"})
	_check(door.opened and not w.controlled_doors.has(Vector2i(8, 8)), "a trigger's open lets go")
	Triggers.run(g, {"close": [8, 8]})
	_check(not door.opened, "and close shuts it (by its cell)")
	# Carried: a client copy takes the host's door.
	g.toggle_door(door, true)
	for _k in 60:
		g.tick(DT, Game.Controls.new())
	var client := _game(main)
	_check(GameSnapshot.apply(client, GameSnapshot.capture(g)), "a snapshot applies")
	var theirs := _door(client, "loft_door")
	_check(theirs.opened and theirs.progress >= 1.0, "the client's loft door is open too")
	# A hand up there waits on it: shut, no way through.
	var g2 := _game(main)
	_place(g2, 6.5, 10.5, LOFT)
	var f2 := g2.player.flow
	f2.update(6.5, 10.5, 0.0, LOFT)
	_check(
		f2.distance(6.5, 6.5, LOFT) == FlowField.FAR,
		"shut, the loft's far side is out of a hand's reach"
	)
	g2.toggle_door(_door(g2, "loft_door"), true)
	for _k in 60:
		g2.tick(DT, Game.Controls.new())
	f2.origin = Vector2i(-1, -1)
	f2.next_at = 0.0
	f2.update(6.5, 10.5, 1.0, LOFT)
	_check(f2.distance(6.5, 6.5, LOFT) < FlowField.FAR, "open, it is in reach")


func _wide_doors(main) -> void:
	print("a double door and a barn door")
	var g := _game(main)
	var w := g.world
	var pair := _door(g, "barn_pair")
	var barn := _door(g, "barn_door")
	_check(pair.cells() == [Vector2i(27, 4), Vector2i(28, 4)], "the pair stands in two cells")
	_check(w.door_cells.has(4 * w.width + 28), "both its cells are door cells")
	_check(w.blocked(28.0, 4.5, .2) and w.blocked(27.3, 4.5, .2), "shut, it fills its doorway")
	_check(pair.segments().size() == 8, "two leaves")
	pair.progress = 1.0
	pair.opened = true
	_check(not w.blocked(28.0, 4.5, .2), "open, its middle is clear")
	_place(g, 28.0, 2.5, 0.0, PI * .5)
	_walk(g, Vector2(28.0, 6.5), 4.0)
	_check(g.player.y > 6.0, "and a body walks through it (to y %.2f)" % g.player.y)
	_check(barn.cells().size() == 3 and w.blocked(25.5, 12.5, .2), "the barn door fills three")
	barn.progress = 1.0
	barn.opened = true
	var seg := barn.segments()
	_check(
		seg.size() == 4 and absf(seg[0] - 27.0) < .01 and absf(seg[2] - 30.0) < .01,
		"open, it has slid aside along the wall (%s)" % [seg]
	)
	_check(not w.blocked(25.5, 12.5, .2) and not w.blocked(24.3, 12.5, .2), "its doorway clear")
	_place(g, 25.5, 14.5, 0.0, -PI * .5)
	_walk(g, Vector2(25.5, 10.5), 4.0)
	_check(g.player.y < 11.0, "and a body walks through it (to y %.2f)" % g.player.y)
	# USE from either end of it.
	barn.progress = 0.0
	barn.opened = false
	_place(g, 26.6, 13.5, 0.0, -PI * .5)
	var target: Variant = g.use_target()
	_check(target is Array and target[0] == barn, "USE finds the barn door from its end")
	# Boss locks take every cell.
	_check(Vector2i(26, 12) in barn.cells(), "its cells run along its wall")


func _pane(main) -> void:
	print("a pane in a wall")
	var g := _game(main)
	var w := g.world
	_check(w.geo_panes.size() == 1, "one pane read")
	var key := LevelData.pane_key(0)
	_check(w.pane_at(14.0, 7.5, 1.4, .025) == key, "whole, a shot at its height meets it")
	_check(w.pane_at(14.0, 7.5, .5, .025) == null, "not under its sill")
	_check(not w.visible(17.5, 7.5, 13.5, 7.5, 1.4, 1.4), "and it stops a look, as grid panes do")
	_place(g, 17.5, 7.5, 0.0, PI)
	g.player.pitch = 0.0
	var c := Game.Controls.new()
	c.fire = true
	for _k in 40:
		g.tick(DT, c)
		if w.broken_panes.has(key):
			break
	_check(w.broken_panes.has(key), "shot, it breaks")
	_check(w.pane_at(14.0, 7.5, 1.4, .025) == null, "broken, it is out of the way")
	_check(w.visible(17.5, 7.5, 13.5, 7.5, 1.4, 1.4), "and a look goes through")
	var rows := w.active_walls(false)
	var glass := false
	for o in range(0, rows.size(), LevelData.WALL_STRIDE):
		glass = glass or int(rows[o + 4]) == w.tile_id("glazing")
	_check(not glass, "and no glass is drawn")
	var client := _game(main)
	_check(GameSnapshot.apply(client, GameSnapshot.capture(g)), "a snapshot applies")
	_check(client.world.broken_panes.has(key), "the client's pane is broken too")
	_check(client.world.pane_at(14.0, 7.5, 1.4, .025) == null, "and out of its shots' way")
	var doc := SessionStore.snapshot(g)
	var panes: Array = doc.get("panes", [])
	_check(panes.has([key.x, key.y]), "a save keeps it broken (%s)" % [panes])


func _automap(main) -> void:
	print("the automap by floor")
	var g := _game(main)
	var m := GameAutomap.new()
	_place(g, 6.5, 10.5, 0.0)
	_check(m._storey_of(g) == 0.0, "on the ground: the ground's map")
	_place(g, 6.5, 10.5, LOFT)
	var storey := m._storey_of(g)
	_check(absf(storey - 2.5) < .01, "on the loft: its storey (%.1f)" % storey)
	m.built_storey = storey
	m._build_image(g, Rect2i(0, 0, g.world.width, g.world.height), 3.0)
	var cells := m.storey_cells
	_check(cells.has(10 * g.world.width + 6), "the loft's floor is on it")
	_check(not cells.has(18 * g.world.width + 7), "the yard is not")
	_check(not cells.has(8 * g.world.width + 12), "nor the stairwell")


func _refused() -> void:
	print("refused")
	var door := LevelData.Door.new()
	_check(LevelLoad.door_ways(door, {"span": 7}) != "" and door.span == 1, "a span of 7")
	_check(LevelLoad.door_ways(door, {"z": -3}) != "" and not door.raised(), "a z under the ground")
	_check(LevelLoad.door_ways(door, {"z": "up"}) != "", "a z not a number")
	_check(LevelLoad.geo_pane({"a": [1, 1]}) == null, "a pane with one end")
	_check(LevelLoad.geo_pane({"a": [1, 1], "b": [1, 1]}) == null, "a pane with no length")
	_check(
		LevelLoad.geo_pane({"a": [1, 1], "b": [2, 1], "z0": 2.0, "z1": 1.0}) == null,
		"a pane upside down"
	)
	var g := LevelGeometry.new()
	g.width = 10
	g.height = 10
	var errors: Array = []
	LevelNav.read_vias(g, {"nav_via": true, "vias": [[1, 1], "x", [50, 50, 0], [2, 2, 0]]}, errors)
	_check(g.vias.size() == 2 and errors.size() == 2, "a via not a point, or off the map")
	errors.clear()
	LevelNav.read_vias(g, {"vias": {"a": 1}}, errors)
	_check(errors.size() == 1, "vias not a list")
