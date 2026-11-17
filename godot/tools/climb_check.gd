## Checks of climbing and the smarter hands (src/climbing.gd,
## src/hand_tactics.gd; check_all runs it, quick too):
##
##   Godot --headless --path <project> --script res://tools/climb_check.gd
##
## Every chapter has ladders, each joining a floor at its foot to the one at
## its top in the nav graph; a ladder takes the player up and back down, a
## pull-up gets them onto a chest-high stack and from it onto the roof, a
## ledge too high is not pulled up onto, a running jump crosses between two
## stacks; a hand after the player on a roof
## comes up the ladder to them, and one up there drops off the edge to get at
## them below; a hand under fire ducks behind something solid, peeks out and
## shoots, and goes back; a hand kicks a door in its way open (not on EASY or
## CLASSIC); the same run twice comes out the same.
extends SceneTree

const STEP := 1.0 / 60.0
const CHAPTERS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("CLIMB CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable) -> void:
	print("\nLADDERS IN EVERY CHAPTER")
	_every_chapter(main, check)
	print("\nCLIMBING")
	_ladder(main, check)
	_mantle(main, check)
	print("\nHANDS AND HEIGHT")
	_hand_climbs(main, check)
	_hand_drops(main, check)
	print("\nSMARTER HANDS")
	_cover(main, check)
	_kick(main, check)
	_same_twice(main, check)


static func _game(main, level_id: String, difficulty := 2, smart := 1) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({"difficulty": difficulty, "smart_hands": smart})
	g.spawn_grace = 0.0
	g.events.ticked.emit(STEP)
	g.enemies.clear()
	# (Triggers name enemies by their place in the level's list.)
	g.level.triggers = []
	return g


static func _ladder_named(g: Game, id: String) -> LevelGeometry.Ladder:
	for lad: LevelGeometry.Ladder in g.world.geo.ladders:
		if lad.id == id:
			return lad
	return null


static func _place(g: Game, at: Vector2, angle: float, z: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = angle
	p.floor_z = z
	p.air = 0.0
	p.vertical_speed = 0.0
	p.floor_z = g.world.stand(p)
	p.eye = p.floor_z + .95


static func _drive(g: Game, c: Game.Controls, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / STEP):
		g.tick(STEP, c)
		if until.is_valid() and until.call():
			return true
	return false


static func _every_chapter(main, check: Callable) -> void:
	var all := true
	var joined := true
	var lines: Array = []
	for level_id: String in CHAPTERS:
		var g: Game = main.make_game(level_id)
		var geo: LevelGeometry = g.world.geo
		var n := 0 if geo == null else geo.ladders.size()
		all = all and n >= 1
		lines.append("%s %d" % [level_id, n])
		if geo == null:
			continue
		var nav := geo.nav(g.world)
		for i in geo.ladders.size():
			var ends: Vector2i = nav.ladder_ends[i]
			if ends.x < 0:
				joined = false
				lines.append("%s's %s joins nothing" % [level_id, geo.ladders[i].id])
	check.call(all, "every chapter has ladders (%s)" % ", ".join(lines))
	check.call(joined, "every ladder joins its foot's floor to its top's in the nav graph")


## Up the registry lookout's ladder and back down it.
static func _ladder(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var lad := _ladder_named(g, "registry_lookout_ladder")
	check.call(lad != null, "hickston has the registry lookout's ladder")
	if lad == null:
		return
	var face := atan2(lad.dy, lad.dx)
	var foot := lad.foot()
	_place(g, foot - Vector2(lad.dx, lad.dy) * .6, face, lad.z0)
	var c := Game.Controls.new()
	c.forward = 1.0
	var p := g.player
	var held := [false]
	var up := _drive(
		g,
		c,
		6.0,
		func() -> bool:
			held[0] = held[0] or p.ladder >= 0
			return p.ladder < 0 and p.climb_time == 0.0 and absf(p.floor_z - lad.z1) < .05
	)
	check.call(
		held[0] and up and p.air == 0.0,
		(
			"walking into the ladder and on up it stands the player on the lookout (floor %.2f)"
			% p.floor_z
		)
	)
	# Turned round, walking off the edge at the ladder takes it down to the yard.
	p.angle = face + PI
	var on := [false]
	var down := _drive(
		g,
		c,
		6.0,
		func() -> bool:
			on[0] = on[0] or p.ladder >= 0
			return on[0] and p.ladder < 0 and p.climb_time == 0.0 and p.floor_z < lad.z0 + .05
	)
	check.call(
		on[0] and down and p.eye < lad.z0 + 1.2,
		"turned round, walking off at the ladder climbs down it (floor %.2f)" % p.floor_z
	)
	# JUMP lets go of a ladder half way up: down they come.
	_place(g, foot - Vector2(lad.dx, lad.dy) * .6, face, lad.z0)
	_drive(g, c, .9)
	var half := p.air
	var jump := Game.Controls.new()
	jump.jump = true
	g.tick(STEP, jump)
	var fell := _drive(g, Game.Controls.new(), 2.0, func() -> bool: return p.air == 0.0)
	check.call(
		half > .4 and p.ladder < 0 and fell,
		"JUMP lets go of the ladder %.2f up and they fall" % half
	)


## Pull-ups in the salvage yard: onto the low stack, from it onto the high one.
static func _mantle(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var p := g.player
	# West of the low stack (x 25.6..26.6, y 41.7..42.9, top 1.0)? It stands
	# against the high stack: come at it from the east.
	_place(g, Vector2(27.05, 42.3), PI, 0.0)
	var c := Game.Controls.new()
	c.forward = 1.0
	c.jump = true
	var onto := _drive(
		g, c, 1.5, func() -> bool: return p.climb_time == 0.0 and absf(p.floor_z - 1.0) < .05
	)
	check.call(onto, "JUMP at a chest-high stack pulls the player up onto it (%.2f)" % p.floor_z)
	var release := Game.Controls.new()
	g.tick(STEP, release)
	var roof := _drive(
		g, c, 1.5, func() -> bool: return p.climb_time == 0.0 and absf(p.floor_z - 1.9) < .05
	)
	check.call(roof, "and from the stack up onto the crushed cars (%.2f)" % p.floor_z)
	# From the ground the high stack is out of reach.
	_place(g, Vector2(24.6, 44.05), -PI / 2, 0.0)
	_drive(g, c, 1.2)
	check.call(
		p.floor_z < .3, "a ledge 1.9 up is not pulled up onto from the ground (%.2f)" % p.floor_z
	)
	# The sawmill's lumber: a running jump from one high stack to the next
	# (x 25.2..27.6 and 28.8..31.0, both 1.8 up).
	var s := _game(main, "sawmill")
	var q := s.player
	_place(s, Vector2(26.2, 52.0), 0.0, 1.8)
	var run := Game.Controls.new()
	run.forward = 1.0
	run.running = true
	_drive(s, run, .3)
	var leap := Game.Controls.new()
	leap.forward = 1.0
	leap.running = true
	leap.jump = true
	s.tick(STEP, leap)
	var landed := _drive(
		s, run, 1.5, func() -> bool: return q.x > 28.9 and q.air == 0.0 and q.climb_time == 0.0
	)
	check.call(
		landed and absf(q.floor_z - 1.8) < .05,
		"a running jump crosses from one lumber stack to the next (floor %.2f)" % q.floor_z
	)


static func _hand(g: Game, kind: String, at: Vector2, z: float) -> Enemy:
	var e := Enemy.new(kind, at.x, at.y)
	e.floor_z = z
	e.floor_z = g.world.stand(e)
	e.last_floor = e.floor_z
	e.mind = Squad.Mind.new()
	e.alerted = true
	e.hunting = true
	e.hunt_until = 1e9
	e.target = [g.player.x, g.player.y]
	g.enemies.append(e)
	return e


## The player up on the lookout: a brawler in the yard comes up its ladder.
static func _hand_climbs(main, check: Callable) -> void:
	var g := _game(main, "hickston", 2)
	var lad := _ladder_named(g, "registry_lookout_ladder")
	var top := lad.top()
	_place(g, top + Vector2(lad.dx, lad.dy) * .8, 0.0, lad.z1)
	g.player.health = 100000
	var e := _hand(g, "billy", lad.foot() + Vector2(-lad.dx, -lad.dy) * 3.0 + Vector2(0, 2), 0.0)
	var climbed := [false]
	var still := Game.Controls.new()
	var there := _drive(
		g,
		still,
		25.0,
		func() -> bool:
			climbed[0] = climbed[0] or e.ladder >= 0
			return absf(e.floor_z - lad.z1) < .05 and e.ladder < 0
	)
	check.call(
		climbed[0] and there,
		"a hand after the player on the lookout comes up its ladder (floor %.2f)" % e.floor_z
	)


## A brawler up on the lookout, the player below close by: it drops off.
static func _hand_drops(main, check: Callable) -> void:
	var g := _game(main, "hickston", 2)
	var lad := _ladder_named(g, "registry_lookout_ladder")
	var top := lad.top()
	g.player.health = 100000
	# The player below, a few steps west of the lookout (x 92..94, y 31..33).
	_place(g, Vector2(89.9, 32.0), 0.0, 0.0)
	var e := _hand(g, "billy", Vector2(92.6, 32.0), lad.z1)
	var fell := [false]
	var down := _drive(
		g,
		Game.Controls.new(),
		10.0,
		func() -> bool:
			fell[0] = fell[0] or e.climb_z > .5
			return e.floor_z < .3 and e.climb_z == 0.0
	)
	check.call(
		fell[0] and down, "a hand up on the lookout drops off the edge to get at the player below"
	)
	check.call(top.x > 0.0 and e.stun >= 0.0, "and lands winded, on the yard's floor")


## A ranged hand hurt in the open ducks behind something solid, then peeks
## out and fires, and goes back behind it.
static func _cover(main, check: Callable) -> void:
	var g := _game(main, "hickston", 2)
	var p := g.player
	p.health = 100000
	# The salvage yard: the player by the hedge, a deputy beside the crushed
	# cars' stack (x 23.6..25.6, y 41.6..43.6).
	_place(g, Vector2(26.4, 47.2), -PI / 2, 0.0)
	var e := _hand(g, "yard_deputy", Vector2(22.4, 44.4), 0.0)
	e.player_seen = true
	e.hp = e.max_hp * .6
	e.cover_ready = 0.0
	e.take_cover(g)
	# (In play a few spots a tick: CoverSearch; here to its end at once.)
	CoverSearch.go_on(e, g, false)
	var found: bool = e.cover != null
	var spot := Vector2.INF
	var solid := false
	if found:
		var c: Array = e.cover
		spot = Vector2(float(c[0]), float(c[1]))
		var to := Vector2(p.x, p.y) - spot
		to = to.normalized()
		solid = g.world.blocked(
			spot.x + to.x * (e.radius + .45), spot.y + to.y * (e.radius + .45), .12
		)
	check.call(
		found and not g.world.visible(p.x, p.y, spot.x, spot.y, p.eye, 1.0),
		(
			"a hand under fire ducks to a spot out of the player's sight %s%s"
			% [spot, " right behind something solid" if solid else ""]
		)
	)
	var reached := _drive(
		g, Game.Controls.new(), 3.0, func() -> bool: return Vector2(e.x, e.y).distance_to(spot) < .3
	)
	check.call(reached, "and gets there")
	var shots := e.attacks
	var out := [false]
	var back := [false]
	_drive(
		g,
		Game.Controls.new(),
		12.0,
		func() -> bool:
			out[0] = out[0] or e.attacks > shots
			back[0] = back[0] or (out[0] and e.cover != null)
			return back[0]
	)
	check.call(out[0], "a hand in cover peeks out and fires (%d shots)" % (e.attacks - shots))
	check.call(back[0], "and goes back into cover after")
	# CLASSIC: the old open-ground spot (Enemy.find_cover), the same as before.
	var g2 := _game(main, "hickston", 2, 0)
	_place(g2, Vector2(26.4, 47.2), -PI / 2, 0.0)
	var old := _hand(g2, "yard_deputy", Vector2(22.4, 44.4), 0.0)
	var want: Variant = old.find_cover(g2)
	var got: Variant = HandTactics.cover(old, g2)
	check.call(want == got, "HANDS: CLASSIC ducks where it always did")


## A brawler with a closed door between it and the player kicks it open.
static func _kick(main, check: Callable) -> void:
	var results := []
	for setting: Array in [[2, 1], [0, 1], [2, 0]]:
		var g := _game(main, "hickston", setting[0], setting[1])
		g.player.health = 100000
		var door: LevelData.Door = null
		for d: LevelData.Door in g.world.doors:
			if d.id == "front":
				door = d
		if door == null:
			results.append(false)
			continue
		door.opened = false
		door.progress = 0.0
		# Stanky's front door (53, 42), hung north-south: the player inside,
		# a brawler come up to it on the street.
		_place(g, Vector2(50.5, 42.5), 0.0, 0.0)
		var e := _hand(g, "billy", Vector2(54.7, 42.5), 0.0)
		e.player_seen = false
		_drive(g, Game.Controls.new(), 8.0, func() -> bool: return door.opened)
		results.append(door.opened)
	check.call(results[0], "a hand kicks a closed door in its way open (HARD)")
	check.call(not results[1] and not results[2], "not on EASY, nor with HANDS: CLASSIC")


## The same fight twice: the same everything after.
static func _same_twice(main, check: Callable) -> void:
	var rows: Array = []
	for k in 2:
		var g := _game(main, "hickston", 3)
		var lad := _ladder_named(g, "registry_lookout_ladder")
		g.player.health = 100000
		_place(g, lad.top() + Vector2(lad.dx, lad.dy) * .8, 0.0, lad.z1)
		var a := _hand(g, "billy", lad.foot() + Vector2(-3.0, 2.0), 0.0)
		var b := _hand(g, "yard_deputy", Vector2(96.5, 36.5), 0.0)
		_drive(g, Game.Controls.new(), 8.0)
		rows.append([a.x, a.y, a.floor_z, a.climb_z, b.x, b.y, b.attacks, g.rng.state])
	check.call(rows[0] == rows[1], "the same climb and fight twice comes out the same")
