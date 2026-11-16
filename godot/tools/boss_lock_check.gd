## Checks of the boss arenas' lock (features/boss_lock.gd, src/boss_fight.gd,
## bosses.cfg [boss_lock]; tools/check_fixes.gd runs them, this also runs on
## its own):
##
##   Godot --headless --path <project> --script res://tools/boss_lock_check.gd [-- <kind> ...]
##
## For each of the eight bosses, in its own chapter with every way in open:
## its room's edge has no way through but its doors and gates; standing
## outside any way in, in the doorway, or hurting it from outside, starts
## nothing; stepping in starts the fight and every way in is shut (the door
## swung to, every cell solid to bodies, shots and sight, a gate drawn where
## there is no door), walking at it goes nowhere; it holds through a door
## forced open, the phases, the wreck and USE; the boss down, the doors that
## stood open open again; the checkpoint's retry puts the player at the door
## with the way open and it shuts again as they walk in. In co-op a partner
## outside, one on a vehicle too, is brought in, and a copy of the game made
## from a snapshot is shut the same.
extends SceneTree

const STEP := 1.0 / 60.0
const KINDS := ["boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "maw"]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var only: Array = []
	for arg: String in OS.get_cmdline_user_args():
		only.append(arg)
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text),
		only
	)
	print("")
	print("BOSS LOCK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable, only: Array = []) -> void:
	print("BOSS LOCK (locked in with the boss, the fight starts inside)")
	for kind: String in KINDS:
		if only.is_empty() or only.has(kind):
			_arena(main, check, kind)
			_retry(main, check, kind)
	if only.is_empty() or only.has("coop"):
		_coop(main, check)


## A chapter's game for `kind`, god mode, the boss awake, its ways in open.
static func _game(main, kind: String) -> Game:
	var sheet: Dictionary = BossData.get_value("boss_lock", kind)
	var level_id := str(sheet["level"])
	var g: Game = main.make_game(level_id)
	g.configure({"difficulty": 1})
	# The chapters before it played (a save of it holds them).
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(level_id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	g.cheats.god = true
	g.spawn_grace = 0.0
	var e := BossFight.of_kind(g, kind)
	e.dormant = false
	e.alerted = true
	for door: LevelData.Door in BossFight.lock_doors(g, kind):
		door.opened = true
		door.progress = 1.0
	# Nothing else about: the boss and the player only.
	for other: Enemy in g.enemies:
		if other != e:
			other.hp = 0.0
			other.alive = false
	return g


static func _ticks(g: Game, n: int, given: Game.Controls = null) -> void:
	for i in n:
		g.tick(STEP, given if given != null else Game.Controls.new())


static func _stand(g: Game, p: Player, at: Vector2, face := 0.0) -> void:
	Modes.place(g, p, at.x, at.y, face)
	p.floor_z = g.world.elevation(at.x, at.y)


static func _lock(g: Game) -> GameFeature:
	return g.features["boss_lock"]


static func _shut(g: Game) -> bool:
	return str(_lock(g).get("kind")) != ""


static func _began(g: Game, kind: String) -> bool:
	var met: Dictionary = g.features["boss_fight"].met
	return met.has(kind)


## A spot 1.6 off a way in's cell, `inside` toward the room or not (Vector2.INF
## when that side has no open floor).
static func _side(g: Game, kind: String, cell: Vector2i, inside: bool) -> Vector2:
	var w := g.world
	var ways := BossFight.entrances(g, kind)
	for e: Array in LevelEdit.EDGES:
		var dx: int = e[0]
		var dy: int = e[1]
		var n := Vector2i(cell.x + dx, cell.y + dy)
		if n.x < 0 or n.y < 0 or n.x >= w.width or n.y >= w.height or ways.has(n):
			continue
		var c := n.y * w.width + n.x
		if w.solid[c] >= 0 and not w.door_cells.has(c):
			continue
		var in_room := BossFight.in_room(g, kind, n.x + .5, n.y + .5)
		if in_room != inside:
			continue
		for reach: float in [2.0, 1.6, 2.4, 1.3]:
			var at := Vector2(cell.x + .5 + dx * reach, cell.y + .5 + dy * reach)
			if ways.has(Vector2i(int(at.x), int(at.y))):
				continue
			if not w.blocked(at.x, at.y, .35) and not w.deep_at(at.x, at.y):
				if BossFight.in_room(g, kind, at.x, at.y) == inside:
					return at
	return Vector2.INF


## The middle of an open cell just outside the room (a doorway, a gap).
static func _just_out(g: Game, kind: String) -> Vector2:
	var w := g.world
	var room := BossFight.room_of(g, kind)
	for c in room.size():
		if room[c] == 0:
			continue
		for step: int in [w.width, -w.width, 1, -1]:
			var n := c + step
			if n < 0 or n >= room.size() or room[n] != 0:
				continue
			var at := Vector2(n % w.width + .5, n / w.width + .5)
			if w.solid[n] < 0 and not w.blocked(at.x, at.y, .3) and not w.deep_at(at.x, at.y):
				return at
	return Vector2.INF


## The cells of the room's edge a body could walk out by that are not its
## ways in.
static func _leaks(g: Game, kind: String) -> Array:
	var w := g.world
	var ways := BossFight.entrances(g, kind)
	var room := BossFight.room_of(g, kind)
	var out: Array = []
	for c in room.size():
		if room[c] == 0:
			continue
		for step: int in [1, -1, w.width, -w.width]:
			var n := c + step
			if n < 0 or n >= room.size() or room[n] != 0:
				continue
			var cell := Vector2i(n % w.width, n / w.width)
			if ways.has(cell) or (w.solid[n] >= 0 and not w.door_cells.has(n)):
				continue
			if w.blocked(cell.x + .5, cell.y + .5, .3):
				continue
			if not out.has(cell):
				out.append(cell)
	return out


static func _arena(main, check: Callable, kind: String) -> void:
	var g := _game(main, kind)
	var w := g.world
	var e := BossFight.of_kind(g, kind)
	var p := g.player
	var ways := BossFight.entrances(g, kind)
	var doors := BossFight.lock_doors(g, kind)
	var sheet := BossFight.lock_of(g, kind)
	var spot_list: Array = sheet["spot"]
	var spot := Vector2(float(spot_list[0]), float(spot_list[1]))
	check.call(
		not ways.is_empty() and doors.size() == Array(sheet.get("doors", [])).size(),
		"%s: its ways in are on the map (%d doors, %d cells)" % [kind, doors.size(), ways.size()]
	)
	check.call(
		BossFight.in_room(g, kind, e.x, e.y) and BossFight.started_at(g, e, spot.x, spot.y),
		"%s: it stands in its room, its spot is where the fight starts" % kind
	)
	if not sheet.get("flood", false):
		var leaks := _leaks(g, kind)
		check.call(
			leaks.is_empty(),
			"%s: no way out of its room but its doors and gates %s" % [kind, leaks]
		)
	# Outside every way in, the doors open, the boss awake and looking: nothing.
	var outside_ok := true
	var outside_seen := 0
	for cell: Vector2i in ways:
		var out := _side(g, kind, cell, false)
		if out == Vector2.INF:
			continue
		outside_seen += 1
		_stand(g, p, out, atan2(e.y - out.y, e.x - out.x))
		e.alerted = true
		_ticks(g, 20)
		if _shut(g) or _began(g, kind) or BossFight.on(g) != null:
			outside_ok = false
			print("    outside ", cell, " at ", out, " started it")
	check.call(
		outside_ok and outside_seen > 0,
		"%s: walking up to any way in (%d) starts nothing" % [kind, outside_seen]
	)
	# It keeps to its room: set out of it (after the player through a door, a
	# charge through a gate), it is back on its floor the next tick.
	var home := Vector2(e.x, e.y)
	var gone := _just_out(g, kind)
	e.x = gone.x
	e.y = gone.y
	_ticks(g, 1)
	check.call(
		BossFight.in_room(g, kind, e.x, e.y) and not _shut(g),
		"%s: stepped out of its room, it is set back in (%.1f, %.1f)" % [kind, e.x, e.y]
	)
	e.x = home.x
	e.y = home.y
	# Hurt from outside (a hand's stick, a drum, a thrown thing): nothing.
	e.hp -= 5.0
	_ticks(g, 10)
	check.call(not _shut(g) and not _began(g, kind), "%s: hurt from outside starts nothing" % kind)
	e.hp = e.max_hp
	# In the doorway, a step inside: nothing yet.
	var doorway_ok := true
	for cell: Vector2i in ways:
		var inn := _side(g, kind, cell, true)
		if inn == Vector2.INF:
			continue
		_stand(g, p, inn, atan2(e.y - inn.y, e.x - inn.x))
		_ticks(g, 6)
		if _shut(g) or _began(g, kind):
			doorway_ok = false
			print("    in the doorway ", cell, " at ", inn, " started it")
	check.call(doorway_ok, "%s: standing in a doorway starts nothing" % kind)
	# Well in: it starts and every way in shuts.
	_stand(g, p, spot, atan2(e.y - spot.y, e.x - spot.x))
	for i in 40:
		_ticks(g, 1)
		if _shut(g):
			break
	check.call(_began(g, kind) and _shut(g), "%s: stepping in starts the fight and shuts it" % kind)
	if not _shut(g):
		return
	_ticks(g, 60)
	_check_shut(g, check, kind, "shut")
	if sheet.get("flood", false):
		# The whole bank its bridges keep, never the chapter's start.
		var start: Array = g.level.spawn
		check.call(
			_lock(g).inside(spot.x, spot.y) and not _lock(g).inside(start[0], start[1]),
			"%s: shut in on its side of the water, the chapter's start outside" % kind
		)
	if kind == "swamp_king":
		# The north bank west of the lagoon (the Mudhole, the gator farm) is
		# gated off: nobody waits the fight out in the juke joint.
		var mudhole := Vector2(59.5, 14.5)
		_stand(g, p, mudhole)
		_ticks(g, 2)
		check.call(
			not _lock(g).inside(mudhole.x, mudhole.y) and _lock(g).inside(p.x, p.y),
			"%s: the Mudhole is outside the shut arena; stood in it, brought in" % kind
		)
		_stand(g, p, spot, atan2(e.y - spot.y, e.x - spot.x))
	var gates := BossFight.gate_cells(g, kind)
	check.call(
		gates.is_empty() == w.lock_walls.is_empty(),
		"%s: a gate is drawn where there is no door (%d rows)" % [kind, w.lock_walls.size() / 9]
	)
	# Walking at each way in from inside goes nowhere.
	var walked_ok := true
	for cell: Vector2i in ways:
		var inn := _side(g, kind, cell, true)
		if inn == Vector2.INF:
			continue
		_stand(g, p, inn, atan2(cell.y + .5 - inn.y, cell.x + .5 - inn.x))
		var push := Game.Controls.new()
		push.forward = 1.0
		push.running = true
		_ticks(g, 70, push)
		if not BossFight.in_room(g, kind, p.x, p.y):
			walked_ok = false
			print("    walked out by ", cell, " to ", Vector2(p.x, p.y))
	check.call(walked_ok, "%s: walking at a shut way in goes nowhere" % kind)
	_stand(g, p, spot, atan2(e.y - spot.y, e.x - spot.x))
	# Forced open (a station, a trigger, a kick, a blast): shut again.
	for door: LevelData.Door in doors:
		g.toggle_door(door, true)
	_ticks(g, 3)
	var held := true
	for door: LevelData.Door in doors:
		if door.opened:
			held = false
	check.call(held, "%s: a door forced open is shut again" % kind)
	var says := (
		doors.is_empty() or BossFight.door_note(w, doors[0], "") == "SHUT TILL THE BOSS IS DOWN"
	)
	check.call(says, "%s: USE on a shut door says why" % kind)
	# Through its phases and its arena's wreck.
	for share: float in [.45, .15]:
		e.hp = e.max_hp * share
		BossKit.phase_check(e, g)
		_ticks(g, 90)
	_check_shut(g, check, kind, "through phases 2 and 3")
	# Down: the ways that stood open open again.
	e.hp = 1.0
	g.cheats.god = true
	e.hurt(e.max_hp * 4.0, g)
	for i in 600:
		_ticks(g, 1)
		if not _shut(g) and g.slowmo <= 0.0:
			break
	_ticks(g, 60)
	var open_ok := not _shut(g) and w.lock_walls.is_empty()
	for cell: Vector2i in ways:
		if w.blocked(cell.x + .5, cell.y + .5, .2) and gates.has(cell):
			open_ok = false
	for door: LevelData.Door in doors:
		var c := door.y * w.width + door.x
		if (
			not door.opened
			or w.solid[c] >= 0
			or w.controlled_doors.get(Vector2i(door.x, door.y)) is String
		):
			open_ok = false
	check.call(open_ok, "%s: down, every way in opens again" % kind)


## Every way in shut: each door swung to, each cell solid, blocking a body,
## a shot and the sight through it.
static func _check_shut(g: Game, check: Callable, kind: String, when: String) -> void:
	var w := g.world
	var bad: Array = []
	for door: LevelData.Door in BossFight.lock_doors(g, kind):
		if door.opened or door.progress > .01:
			bad.append("%s open" % door.id)
	for cell: Vector2i in BossFight.entrances(g, kind):
		var cx := cell.x + .5
		var cy := cell.y + .5
		var c := cell.y * w.width + cell.x
		if w.solid[c] < 0 or not w.blocked(cx, cy, .3):
			bad.append("%s walks" % cell)
		if not w.blocked(cx, cy, .045, w.ground[c] + 1.0):
			bad.append("%s shoots" % cell)
		var inn := _side(g, kind, cell, true)
		var out := _side(g, kind, cell, false)
		if inn != Vector2.INF and out != Vector2.INF and w.visible(inn.x, inn.y, out.x, out.y):
			bad.append("%s sees" % cell)
	check.call(bad.is_empty(), "%s: %s, every way in is shut and solid %s" % [kind, when, bad])


## The checkpoint's retry: back at the door with the way open; in again, shut.
static func _retry(main, check: Callable, kind: String) -> void:
	var g := _game(main, kind)
	var e := BossFight.of_kind(g, kind)
	var p := g.player
	var sheet := BossFight.lock_of(g, kind)
	var spot_list: Array = sheet["spot"]
	var spot := Vector2(float(spot_list[0]), float(spot_list[1]))
	var out := Vector2.INF
	for cell: Vector2i in BossFight.entrances(g, kind):
		out = _side(g, kind, cell, false)
		if out != Vector2.INF:
			break
	_stand(g, p, out, atan2(e.y - out.y, e.x - out.x))
	_ticks(g, 40)
	_stand(g, p, spot, atan2(e.y - spot.y, e.x - spot.x))
	var taken := false
	for i in 300:
		_ticks(g, 1)
		if g.features["boss_checkpoint"].taken.has(kind):
			taken = true
			break
	check.call(taken and _shut(g), "%s: shut in, the checkpoint is taken" % kind)
	if not taken:
		return
	e.hp = e.max_hp * .4
	var back := BossDoor.restore(Callable(main, "make_game"), g)
	check.call(
		back != null,
		"%s: the retry loads %s" % [kind, "" if back != null else SessionStore.last_error]
	)
	if back == null:
		return
	var w := back.world
	var open_ok := not _shut(back) and w.lock_walls.is_empty()
	for door: LevelData.Door in BossFight.lock_doors(back, kind):
		var c := door.y * w.width + door.x
		if not door.opened or w.solid[c] >= 0:
			open_ok = false
	for cell: Vector2i in BossFight.gate_cells(back, kind):
		if w.solid[cell.y * w.width + cell.x] >= 0:
			open_ok = false
	var boss := BossFight.of_kind(back, kind)
	var q := back.player
	check.call(
		(
			open_ok
			and boss != null
			and boss.hp == boss.max_hp
			and not BossFight.in_room(back, kind, q.x, q.y)
		),
		(
			"%s: the retry puts the player at the door (%.1f, %.1f), the way open, the boss whole"
			% [kind, q.x, q.y]
		)
	)
	back.cheats.god = true
	# Its trigger never fired here (the test woke it by hand); in play the
	# save holds that it did.
	boss.dormant = false
	_ticks(back, 20)
	check.call(not _shut(back), "%s: at the door, it stays open" % kind)
	_stand(back, q, spot, 0.0)
	for i in 40:
		_ticks(back, 1)
		if _shut(back):
			break
	check.call(_shut(back), "%s: in again, it shuts again" % kind)
	_ticks(back, 60)
	_check_shut(back, check, kind, "after the retry")


## Co-op: a partner outside, one on the mower, brought in; a copy from a
## snapshot shut the same; the shut saved and loaded.
static func _coop(main, check: Callable) -> void:
	var kind := "boss"
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2, {})
	g.cheats.god = true
	g.spawn_grace = 0.0
	var e := BossFight.of_kind(g, kind)
	e.alerted = true
	for door: LevelData.Door in BossFight.lock_doors(g, kind):
		door.opened = true
		door.progress = 1.0
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var spot := Vector2(131.5, 13.5)
	_stand(g, b, Vector2(130.5, 26.5), 0.0)
	var rides: GameFeature = g.features.get("vehicles")
	var mower = rides.rides[0] if rides != null and not rides.rides.is_empty() else null
	if mower != null:
		mower.x = b.x
		mower.y = b.y
		mower.seats[0] = b.slot
	g.focus(a)
	_stand(g, a, spot, 0.0)
	for i in 40:
		_ticks(g, 1)
		if _shut(g):
			break
	_ticks(g, 2)
	check.call(
		_shut(g) and BossFight.in_room(g, kind, b.x, b.y),
		"co-op: a partner outside is brought in as the arena shuts (%.1f, %.1f)" % [b.x, b.y]
	)
	if mower != null:
		check.call(not rides.seated(b), "co-op: a partner on the mower is set down first")
	# A copy from a snapshot, as a client sees it.
	var copy: Game = main.make_game("hickston")
	copy.configure({"difficulty": 1})
	Modes.setup(copy, Modes.COOP, 2, {})
	var applied := GameSnapshot.apply(copy, GameSnapshot.capture(g))
	var w := copy.world
	var solid_ok := applied and _shut(copy) and not w.lock_walls.is_empty()
	for cell: Vector2i in BossFight.entrances(copy, kind):
		if w.solid[cell.y * w.width + cell.x] < 0:
			solid_ok = false
	check.call(solid_ok, "co-op: a copy from a snapshot is shut the same, gates and all")
	# Saved and loaded mid-fight: still shut.
	var path := OS.get_cache_dir().path_join("clmr-boss-lock-check.json")
	SessionStore.save(g, path)
	var loaded: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var lw := loaded.world if loaded != null else null
	var load_ok := loaded != null and _shut(loaded)
	if load_ok:
		for cell: Vector2i in BossFight.entrances(loaded, kind):
			if lw.solid[cell.y * lw.width + cell.x] < 0:
				load_ok = false
	check.call(load_ok, "a save made shut in loads shut in")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# The copy and the host open together when it falls.
	e.hp = 1.0
	e.hurt(e.max_hp * 4.0, g)
	for i in 400:
		_ticks(g, 1)
	GameSnapshot.apply(copy, GameSnapshot.capture(g))
	var open_ok := not _shut(copy) and copy.world.lock_walls.is_empty()
	for cell: Vector2i in BossFight.gate_cells(copy, kind):
		if copy.world.solid[cell.y * copy.world.width + cell.x] >= 0:
			open_ok = false
	check.call(not _shut(g) and open_ok, "co-op: down, the host and the copy open together")
