## Checks of the big breaks (features/set_pieces.gd): every chapter's set
## pieces stand where their plans put them, in the way only where they stand;
## a barn shot at its posts creaks, its hands run, and it comes down in its
## pieces that hurt and pin whoever is under them and lie as cover; a wall
## panel shot about shows its boards out and then goes on its own; a truck
## rammed into a post takes it out; a water tower with two legs shot out on
## one side goes over that way, its tank bursts and floods the street,
## putting out the fire there and shoving a hand out of the way; a fuel line
## holed leaks gas along itself and a fire at one end runs its length and
## sets off the propane at the other; a blast among the hay brings a barn
## down; the same breaks twice come out the same; a snapshot carries it to a
## fresh game; a save keeps what came down; nothing is ever shut off: with
## every set piece down every way it may fall, every station, key and the
## exit is still walked to from the start; the idle tick costs nothing; and
## (looks) a barn comes apart in pieces of itself that lie on the ground or
## the pile, the same fall the same, another fall otherwise, and a tower's
## legs snap, its tank tears, its hoops land in bands and its deck splinters.
##
##   godot --headless --path godot --script res://tools/set_piece_check.gd [-- <level>]
##   godot --headless --path godot --script res://tools/set_piece_check.gd -- level=<level.json>
##
## A level not in the chapters' list (a map's, pass 16: src/map_kit/
## set_piece_hooks.gd), by its id or by its built file with level=, has its own
## set pieces checked: each one stands, and with them down every way they
## may fall the start still reaches every station, key and the exit.
##
## Prints SET PIECE CHECK OK.
extends SceneTree

const SetPieces := preload("res://src/features/set_pieces.gd")
const Shape := preload("res://src/set_piece_shape.gd")
const Flow := preload("res://src/set_piece_flow.gd")
const STEP := 1.0 / 60.0
## Each chapter's set pieces, by kind (the plans: set_piece_kit.gd).
const WANT := {
	"hickston": ["barn", "tower", "fuel"],
	"fair": ["barn"],
	"sawmill": ["barn"],
	"speedway": ["tower", "fuel"],
	"moonshine": ["barn", "tower", "fuel"],
}

var failures: Array = []
var main: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		only = a
		if a.begins_with("level="):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.substr(6)))
			var built: Dictionary = parsed if parsed is Dictionary else {}
			only = str(built.get("id", ""))
			LevelData.preview[only] = built
	if only != "" and not WANT.has(only):
		_map(only)
	else:
		_check_all(only)
	print("")
	print("SET PIECE CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _game(level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({"difficulty": 1})
	g.cheats.god = false
	g.spawn_grace = 0.0
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


static func _ticks(g: Game, seconds: float) -> void:
	for i in int(seconds / STEP):
		g.tick(STEP, Game.Controls.new())


static func _sets(g: Game) -> SetPieces:
	var sp: SetPieces = g.features.get("set_pieces")
	return sp


static func _find(sp: SetPieces, kind: String) -> int:
	for i in sp.pieces.size():
		var st: Dictionary = sp.pieces[i]
		if str(st["kind"]) == kind:
			return i
	return -1


## The parts of piece i with `role` (codes).
static func _codes(sp: SetPieces, i: int, role: String) -> Array:
	var out: Array = []
	var made: Array = sp.shapes[i]
	for k in made.size():
		var part: Shape.Part = made[k]
		if part.role == role:
			out.append(i * 1000 + k)
	return out


static func _part(sp: SetPieces, code: int) -> Shape.Part:
	var made: Array = sp.shapes[code / 1000]
	var part: Shape.Part = made[code % 1000]
	return part


func _check_all(only: String) -> void:
	print("SET PIECES (barns, water towers, fuel lines)")
	for level_id: String in WANT:
		if only != "" and level_id != only:
			continue
		_standing(level_id)
	if only == "" or only == "hickston":
		_barn("hickston")
		_wall("hickston")
		_ram("hickston")
		_hay_blast("hickston")
		_tower("hickston")
		_flood("hickston")
		_fuel("hickston")
		_twice("hickston")
		_snapshot("hickston")
		_saved("hickston")
		_idle("hickston")
		_looks("hickston")
		_tower_looks("hickston")
	for level_id: String in WANT:
		if only == "" or only == level_id:
			_no_soft_lock(level_id)


## A map's own set pieces (any level not in WANT): each stands, and nothing
## is ever shut off by them coming down.
func _map(level_id: String) -> void:
	print("SET PIECES of %s" % level_id)
	var g := _game(level_id)
	var listed: Array = g.level.set_pieces
	var sp := _sets(g)
	check(
		not listed.is_empty() and sp.pieces.size() == listed.size(),
		"%s: its %d set piece(s) stand" % [level_id, listed.size()]
	)
	_no_soft_lock(level_id)


## Each kind the plan put there stands, its parts in the way only where they
## stand, and nothing is in a wall.
func _standing(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var kinds: Array = []
	for st: Dictionary in sp.pieces:
		kinds.append(str(st["kind"]))
	var want: Array = WANT[level_id]
	var all := true
	for kind: String in want:
		all = all and kinds.has(kind)
	check(all, "%s: its set pieces stand (%s)" % [level_id, ", ".join(kinds)])


## A barn: two posts shot out, it creaks, the hands run, it comes down and
## its pieces lie as cover; one under it is hurt and pinned.
func _barn(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var posts := _codes(sp, i, "post")
	var volumes := g.world.collision_volumes.size()
	var box: Rect2 = sp._boxes[i]
	var mid := box.get_center()
	# A hand in it.
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.hostile and e.hp > 0.0 and not Enemy.BOSS_TITLES.has(e.kind):
			hand = e
			break
	print("    hand ", hand.kind if hand != null else "none", " of ", g.enemies.size())
	hand.dormant = false
	hand.x = mid.x
	hand.y = mid.y
	var p := g.player
	p.x = mid.x + 1.0
	p.y = mid.y
	sp.strike(posts[0], 200.0, 0.0, 1.0)
	_ticks(g, .1)
	var st: Dictionary = sp.pieces[i]
	check(int(st["stage"]) == SetPieces.STANDING, "a barn with one post out still stands")
	sp.strike(posts[1], 200.0, 0.0, 1.0)
	check(int(st["stage"]) == SetPieces.WARN, "the second post out: it creaks")
	check(hand.retreat != null, "the hand in it runs")
	hand.dormant = true
	hand.x = mid.x
	hand.y = mid.y
	var health := p.health
	_ticks(g, 4.0)
	check(int(st["stage"]) == SetPieces.DOWN, "it comes down and lies still")
	check(p.health < health, "the player under it is hurt (%d to %d)" % [health, p.health])
	check(sp.added.size() >= 3, "its pieces lie as cover (%d volumes)" % sp.added.size())
	print(
		"    volumes %d -> %d, hand hp %.0f" % [volumes, g.world.collision_volumes.size(), hand.hp]
	)


func _tower(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "tower")
	var legs := _codes(sp, i, "leg")
	var north: Array = []
	for code: int in legs:
		if _part(sp, code).side.y < 0.0:
			north.append(code)
	var p := g.player
	p.x = 70.0
	p.y = 64.0
	sp.strike(north[0], 300.0, 0.0, -1.0)
	sp.strike(north[1], 300.0, 0.0, -1.0)
	var st: Dictionary = sp.pieces[i]
	check(int(st["stage"]) == SetPieces.WARN, "a tower with two north legs out creaks")
	_ticks(g, 5.0)
	var lean: Array = st["lean"]
	check(int(st["stage"]) == SetPieces.DOWN, "it goes over and lies still")
	check(Shape.f(lean[1]) < -.9, "it went over north (%s)" % [lean])
	check(not sp.floods.is_empty() or Shape.f(st["burst"]) == -2.0, "its tank burst")
	if not sp.floods.is_empty():
		var f: Dictionary = sp.floods[0]
		var cells: Array = f["cells"]
		print("    flood %d cells" % cells.size())
		check(cells.size() >= 40, "its water floods the street (%d cells)" % cells.size())


func _fuel(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "fuel")
	var pipes := _codes(sp, i, "pipe")
	sp.strike(pipes[1], 100.0, 0.0, 1.0)
	_ticks(g, 6.0)
	var st: Dictionary = sp.pieces[i]
	var cells: Array = sp.trails[i]
	var wet := 0
	for j in cells.size():
		if Flow.gas_at(st, j, g.clock):
			wet += 1
	check(
		wet == cells.size(),
		"a holed pipe leaks gas along the line (%d of %d)" % [wet, cells.size()]
	)
	var fire = g.features["fire"]
	var first: Vector2i = cells[0]
	fire.fresh()
	fire.ignite(first.x + .5, first.y + .5, g.world.elevation(first.x + .5, first.y + .5), 3.0)
	var bk = g.features["breakables"]
	var propane = null
	for piece in bk.pieces:
		if (
			piece.image == "town_propane_tank"
			and Vector2(piece.x - 32.3, piece.y - 53.5).length() < .3
		):
			propane = piece
	_ticks(g, 6.0)
	var lit: Array = st["lit"]
	var burnt := 0
	for t: Variant in lit:
		if Shape.f(t) >= 0.0:
			burnt += 1
	check(burnt == cells.size(), "fire at one end runs the line (%d of %d)" % [burnt, cells.size()])
	for piece in bk.pieces:
		if piece.image == "town_propane_tank":
			print(
				(
					"    propane at %.2f,%.2f broken %s hp %.1f"
					% [piece.x, piece.y, piece.broken, piece.hp]
				)
			)
	print("    burning ", fire.burning.size(), " last cell ", cells[cells.size() - 1])
	check(propane != null and propane.broken, "and the propane at the end goes up")


## A wall panel shot about shows its boards out; shot more it goes over on
## its own and the way through it opens.
func _wall(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var code: int = _codes(sp, i, "wall")[0]
	var part := _part(sp, code)
	var st: Dictionary = sp.pieces[i]
	g.player.x = part.p.x + part.side.x * 8.0
	g.player.y = part.p.y + part.side.y * 8.0
	g.view_cone = PackedFloat64Array()
	sp.strike(code, part.hp * .6, 0.0, 1.0)
	var shown := sp.sprites()
	var cracked := false
	for s: View.Sprite in shown:
		cracked = cracked or s.solid.contains(part.tile + "_hit")
	check(
		cracked or not g.art.tile_index.has(part.tile + "_hit"),
		"a wall panel shot about shows its boards out"
	)
	var blocked := g.world.blocked(part.p.x, part.p.y, .2)
	sp.strike(code, part.hp, part.side.x, part.side.y)
	_ticks(g, 2.0)
	var outs: Array = st["out"]
	check(
		(
			blocked
			and int(outs[code % 1000]) == SetPieces.LYING
			and not g.world.blocked(part.p.x, part.p.y, .2)
		),
		"shot through, it goes over on its own and the way through opens"
	)
	check(int(st["stage"]) == SetPieces.STANDING, "and the barn still stands")


## The hickston mower driven into a post at speed takes it out.
func _ram(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var rides = g.features["vehicles"]
	var i := _find(sp, "barn")
	# A front post (the open side), the mower lined up south of it, heading
	# north at it.
	var code := -1
	for c: int in _codes(sp, i, "post"):
		var at := _part(sp, c).p
		if at.y > 17.0 and at.x > 18.0 and at.x < 21.0:
			code = c
	var post := _part(sp, code)
	var v = rides.rides[0]
	var p := g.player
	v.x = post.p.x
	v.y = post.p.y + 3.6
	v.h = -PI * .5
	v.z = g.world.elevation(v.x, v.y)
	p.x = v.x
	p.y = v.y
	rides.seat_in(p, 0)
	p.angle = -PI * .5
	var outs: Array = sp.pieces[i]["out"]
	var c := Game.Controls.new()
	c.forward = 1.0
	for t in 240:
		g.tick(STEP, c)
		if int(outs[code % 1000]) != SetPieces.UP:
			break
	check(int(outs[code % 1000]) != SetPieces.UP, "the mower rammed into a post takes it out")


## A stick of dynamite among the hay brings the shed down (its frame) and
## the hay bales go to pieces.
func _hay_blast(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var box: Rect2 = sp._boxes[i]
	var mid := box.get_center()
	g.player.x = mid.x
	g.player.y = mid.y + 9.0
	var z := g.world.elevation(mid.x, mid.y) + .3
	var st: Dictionary = sp.pieces[i]
	for n in 2:
		if int(st["stage"]) == SetPieces.STANDING:
			g.explode(Game.Shot.new(mid.x, mid.y, z, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0))
			_ticks(g, .2)
	var stage: int = st["stage"]
	check(stage != SetPieces.STANDING, "dynamite among the hay brings the shed down")


## The flood puts out a fire in its way and shoves a hand along.
func _flood(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "tower")
	var fire = g.features["fire"]
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.hostile and e.hp > 0.0 and not Enemy.BOSS_TITLES.has(e.kind):
			hand = e
			break
	hand.x = 61.5
	hand.y = 61.6
	hand.dormant = false
	hand.stun = 30.0
	g.player.x = 75.0
	g.player.y = 70.0
	fire.fresh()
	var lit: bool = fire.ignite(60.5, 64.5, g.world.elevation(60.5, 64.5), 30.0)
	for code: int in _codes(sp, i, "leg"):
		if _part(sp, code).side.y < 0.0:
			sp.strike(code, 400.0, 0.0, -1.0)
	var was := Vector2(hand.x, hand.y)
	_ticks(g, 5.0)
	check(lit and not fire.burning_at(60.5, 64.5), "the flood puts out the fire in the street")
	var moved := Vector2(hand.x, hand.y).distance_to(was)
	check(moved > .3, "and shoves the hand in its way (%.2f)" % moved)


## The same breaks twice: the same pieces where they lie, the same cover.
func _twice(level_id: String) -> void:
	var a := _break_all(level_id)
	var b := _break_all(level_id)
	check(
		var_to_bytes(a.save()) == var_to_bytes(b.save()),
		"the same breaks twice come out the same (pieces, cover, flood, gas)"
	)


func _break_all(level_id: String) -> SetPieces:
	var g := _game(level_id)
	g.player.x = 75.0
	g.player.y = 70.0
	var sp := _sets(g)
	for i in sp.pieces.size():
		var st: Dictionary = sp.pieces[i]
		match str(st["kind"]):
			"barn":
				for code: int in _codes(sp, i, "post").slice(0, 2):
					sp.strike(code, 300.0, 0.0, 1.0)
			"tower":
				for code: int in _codes(sp, i, "leg").slice(0, 2):
					sp.strike(code, 300.0, 1.0, 0.0)
			"fuel":
				sp.strike(_codes(sp, i, "pump")[0], 100.0, 0.0, 1.0)
	_ticks(g, 6.0)
	return sp


## A host's snapshot of it all down carries onto a fresh game: the pieces,
## the cover in its level.
func _snapshot(level_id: String) -> void:
	var a := _break_all(level_id)
	var data := GameSnapshot.capture(a.game)
	var g := _game(level_id)
	GameSnapshot.apply(g, data)
	var b := _sets(g)
	var same := var_to_bytes(a.save()) == var_to_bytes(b.save())
	var volumes := true
	for row: Array in a.added:
		volumes = volumes and g.world.collision_volumes.has(PackedFloat32Array(row))
	for row: Array in a.dropped:
		volumes = volumes and not g.world.collision_volumes.has(PackedFloat32Array(row))
	check(same and volumes, "a snapshot carries it onto a fresh game, its cover in the level")


## A save keeps what came down, its cover in the way.
func _saved(level_id: String) -> void:
	var a := _break_all(level_id)
	var path := OS.get_cache_dir().path_join("set-piece-check.json")
	SessionStore.save(a.game, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var ok := back != null
	if ok:
		var b := _sets(back)
		for n in a.pieces.size():
			var sa: Dictionary = a.pieces[n]
			var sb: Dictionary = b.pieces[n]
			ok = ok and int(sa["stage"]) == int(sb["stage"]) and str(sa["out"]) == str(sb["out"])
		for row: Array in a.added:
			ok = ok and back.world.collision_volumes.has(PackedFloat32Array(row))
	check(ok, "a save keeps what came down, its cover in the way")


## Every set piece down, every way it may fall: the stations, the keys and
## the exit are still walked to from the start (every door open).
func _no_soft_lock(level_id: String) -> void:
	var want := _reach(_game(level_id))
	var worst := ""
	for way in 4:
		var g := _game(level_id)
		var sp := _sets(g)
		g.player.x = float(g.level.spawn[0])
		g.player.y = float(g.level.spawn[1])
		var dir := Vector2.from_angle(way * PI * .5).round()
		for i in sp.pieces.size():
			var spec: Dictionary = sp.spec_of(i)
			var allowed: Array = spec.get("falls", [0, 1, 2, 3])
			if not allowed.has(way) and not allowed.has(float(way)):
				continue
			var st: Dictionary = sp.pieces[i]
			st["lean"] = [dir.x, dir.y]
			match str(st["kind"]):
				"barn", "tower":
					st["stage"] = SetPieces.WARN
					st["t0"] = g.clock
					sp.wake()
				"fuel":
					sp.strike(_codes(sp, i, "pipe")[0], 100.0, 0.0, 1.0)
		_ticks(g, 6.0)
		var now := _reach(g)
		for key: String in want:
			if not now.has(key):
				worst += " %s (falling %d)" % [key, way]
	check(
		worst == "",
		(
			"%s: with its set pieces down every way they fall, all is still reached%s"
			% [level_id, worst]
		)
	)


## What the chapter needs, reached from the start with every door open: the
## stations, the exit, the keys ({name: true}).
func _reach(g: Game) -> Dictionary:
	for door: LevelData.Door in g.world.doors:
		door.opened = true
		door.progress = 1.0
	var w := g.world
	var start := Vector2i(int(g.level.spawn[0]), int(g.level.spawn[1]))
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for k: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + k
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= w.width or n.y >= w.height:
				continue
			if w.solid[n.y * w.width + n.x] >= 0 or w.blocked(n.x + .5, n.y + .5, .2):
				continue
			seen[n] = true
			queue.append(n)
	var out := {}
	var things: Array = []
	for station: LevelData.Station in w.stations:
		things.append(["station " + station.id, station.x, station.y])
	if w.extraction != null:
		things.append(["exit", w.extraction.x, w.extraction.y])
	for item: Array in g.pickups:
		if str(item[0]).begins_with("key"):
			things.append([str(item[0]), item[1], item[2]])
	for t: Array in things:
		var tx: float = t[1]
		var ty: float = t[2]
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if seen.has(Vector2i(int(tx) + dx, int(ty) + dy)):
					out[str(t[0])] = true
	return out


## Standing, nothing doing: no cost a tick.
func _idle(level_id: String) -> void:
	var g := _game(level_id)
	_ticks(g, 1.0)
	var sp := _sets(g)
	# Asleep is the real test (the tick is not called at all). The time is the
	# quickest of a few batches: on a busy machine one batch can be preempted
	# for milliseconds, which said nothing about the tick (pass 9).
	var us := INF
	for batch in 8:
		var t0 := Time.get_ticks_usec()
		for k in 50:
			sp._tick(STEP)
		us = minf(us, (Time.get_ticks_usec() - t0) / 50.0)
	print(
		"    idle tick %.1f us (quickest of 8 batches), asleep %s" % [us, not g.events.is_awake(sp)]
	)
	check(not g.events.is_awake(sp), "standing, its tick sleeps (nothing calls it)")
	check(us < 40.0, "standing, its tick costs next to nothing (%.1f us)" % us)


# ------------------------------------------------------------------ looks


static func _ruin(g: Game) -> SetPieceWreck:
	var wk: GameFeature = g.features.get("wreckage")
	var ruin: SetPieceWreck = wk.get("ruin")
	return ruin


## The barn brought down `how` ("south": its first two posts shot from the
## south; "north": its last two shot from the north; "blast": dynamite in it),
## `wait` seconds into the game: its ruin once all of it lies still.
func _brought_down(level_id: String, how: String, wait: float) -> SetPieceWreck.Ruin:
	var g := _game(level_id)
	g.player.x = 75.0
	g.player.y = 70.0
	_ticks(g, wait)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var posts := _codes(sp, i, "post")
	var st: Dictionary = sp.pieces[i]
	match how:
		"south":
			sp.strike(posts[0], 300.0, 0.0, 1.0)
			sp.strike(posts[1], 300.0, 0.0, 1.0)
		"north":
			sp.strike(posts[posts.size() - 1], 300.0, 0.0, -1.0)
			sp.strike(posts[posts.size() - 2], 300.0, 0.0, -1.0)
		"blast":
			var mid: Vector2 = sp._boxes[i].get_center()
			var z := g.world.elevation(mid.x, mid.y) + .3
			for n in 3:
				if int(st["stage"]) == SetPieces.STANDING:
					g.explode(Game.Shot.new(mid.x, mid.y, z, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0))
					_ticks(g, .2)
	_ticks(g, 7.0)
	var ruin := _ruin(g)
	var r: SetPieceWreck.Ruin = ruin.ruins.get(i)
	return r


## Where the pieces of a ruin lie: each one's key and index, middle.
static func _layout(r: SetPieceWreck.Ruin) -> Dictionary:
	var out := {}
	for b: SetPieceWreck.Bit in r.bits:
		out["%d:%s#%d" % [b.k, b.key.get_slice("|", 1), b.index]] = b.rest_p
	return out


## How far apart two layouts lie: the share of pieces of `a` that `b` has
## no piece of (by its key) within `near` of.
static func _apart(a: Dictionary, b: Dictionary, near: float) -> float:
	var off := 0
	for key: String in a:
		var pa: Vector3 = a[key]
		var pb: Variant = b.get(key)
		if pb == null:
			off += 1
			continue
		var at: Vector3 = pb
		if pa.distance_to(at) > near:
			off += 1
	return float(off) / maxf(1.0, a.size())


## A barn comes apart in pieces of itself (looks: src/set_piece_wreck.gd):
## more than its few big parts, every post snapped, the pieces lying on the
## ground or the pile (none in the air or under the floor), merged once
## still; the same fall twice lies the same (a client, a save), and brought
## down another way (other posts, from the other side, a blast) or at
## another time it lies otherwise.
func _looks(level_id: String) -> void:
	var a := _brought_down(level_id, "south", 1.0)
	if a == null:
		check(false, "the barn's ruin is made")
		return
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var made: Array = sp.shapes[i]
	var posts := 0
	var snapped := {}
	var low := INF
	var high := -INF
	var floating := 0
	var ground: float = sp._ground[i]
	for b: SetPieceWreck.Bit in a.bits:
		var part: Shape.Part = made[b.k]
		if part.role == "post":
			snapped[b.k] = int(snapped.get(b.k, 0)) + 1
		var basis := Basis(b.rest_q)
		var reach := absf(basis[0].z) * b.half.x + absf(basis[1].z) * b.half.y
		reach += absf(basis[2].z) * b.half.z
		var bottom := b.rest_p.z - reach
		low = minf(low, bottom - ground)
		high = maxf(high, bottom - ground)
		if (not b.stub and bottom - ground > 1.6) or b.state != SetPieceWreck.REST:
			floating += 1
			print(
				(
					"    afloat: %s #%d state %d bottom %.2f"
					% [part.role, b.index, b.state, bottom - ground]
				)
			)
	for k in made.size():
		var part: Shape.Part = made[k]
		if part.role == "post":
			posts += 1
	var whole := 0
	for k: int in snapped:
		if int(snapped[k]) < 2:
			whole += 1
	print(
		(
			"    barn: %d parts in %d pieces, bottoms %.2f to %.2f over the ground, %d posts whole"
			% [made.size(), a.bits.size(), low, high, whole]
		)
	)
	check(a.bits.size() > made.size() * 3, "the barn comes apart in pieces (%d)" % a.bits.size())
	check(a.bits.size() <= 220, "but not past its budget (%d of 220)" % a.bits.size())
	check(whole <= 1, "its posts snap rather than fall whole (%d of %d whole)" % [whole, posts])
	check(low > -.12 and floating == 0, "every piece lies on the ground or the pile, none afloat")
	check(
		a.still and not a.merged.is_empty(),
		"once still its pieces are merged (%d meshes)" % a.merged.size()
	)
	var la := _layout(a)
	# The first fall above waited on a worker for its cuts (a busy CI runner
	# can hand them a tick later); two falls with the cuts already made are
	# what must match, piece for piece.
	var again := _layout(_brought_down(level_id, "south", 1.0))
	var twice := _layout(_brought_down(level_id, "south", 1.0))
	check(_apart(again, twice, .001) == 0.0, "the same fall twice lies the same, piece for piece")
	var north := _apart(la, _layout(_brought_down(level_id, "north", 1.0)), .3)
	var blast := _apart(la, _layout(_brought_down(level_id, "blast", 1.0)), .3)
	var later := _apart(la, _layout(_brought_down(level_id, "south", 3.0)), .3)
	print(
		(
			"    pieces lying otherwise: other posts %.2f, a blast %.2f, later %.2f"
			% [north, blast, later]
		)
	)
	check(north > .6, "brought down by the other posts it breaks otherwise (%.2f)" % north)
	check(blast > .6, "brought down by a blast it breaks otherwise (%.2f)" % blast)
	check(later > .6, "the same posts shot another time it breaks otherwise (%.2f)" % later)
	# A save put back: the pile lies in its pieces at once, none flying.
	var back := _brought_down_saved(level_id)
	check(
		back[0] > made.size() * 3 and back[1], "a save put back shows the pile in its pieces, still"
	)
	# A snapshot put on (a late joiner online): the same, and nothing lands
	# again (no dust, no rumble).
	var joined := _brought_down_snapshot(level_id)
	check(
		joined[0] > made.size() * 3 and joined[1] and joined[2] == 0,
		(
			(
				"a snapshot put on a fresh game shows the pile in its pieces, still,"
				+ " nothing landing (%d pieces, %d puffs)"
			)
			% [joined[0], joined[2]]
		)
	)
	# Put on mid-fall (a copy online put back on the host's snapshot while
	# rubble waits to be shut into the paths): it shuts it when the host
	# does, so both games stay the same through the fall and after.
	var parted := _mid_fall(level_id)
	check(
		parted == "",
		(
			"a snapshot put on mid-fall plays on the same as the game it came from"
			+ ("" if parted == "" else " (" + parted + ")")
		)
	)


## The barn falling with rubble down and waiting to be shut into the paths,
## its snapshot on a fresh game, both played on 4 s: where they first part
## ("" never).
func _mid_fall(level_id: String) -> String:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var posts := _codes(sp, i, "post")
	# Stood near enough that the barn's cells are in the player's paths.
	var box: Rect2 = sp._boxes[i]
	var near := Modes.open_spot_near(g, box.get_center().x, box.end.y + 3.0)
	g.player.x = near.x
	g.player.y = near.y
	g.tick(STEP, Game.Controls.new())
	sp.strike(posts[0], 300.0, 0.0, 1.0)
	sp.strike(posts[1], 300.0, 0.0, 1.0)
	var waited := 0
	while (sp._to_shut.is_empty() or not sp._falling_any()) and waited < 600:
		g.tick(STEP, Game.Controls.new())
		waited += 1
	if sp._to_shut.is_empty():
		return "no rubble waited to be shut"
	var back := _game(level_id)
	GameSnapshot.apply(back, GameSnapshot.capture(g))
	for t in int(4.0 / STEP):
		g.tick(STEP, Game.Controls.new())
		back.tick(STEP, Game.Controls.new())
		var w := GameSnapshot.first_difference(GameSnapshot.capture(g), GameSnapshot.capture(back))
		if w != "":
			return "tick %d: %s" % [t, w.left(120)]
	return ""


## The barn down, its snapshot put on a fresh game: [its pieces, all still,
## dust puffs thrown].
func _brought_down_snapshot(level_id: String) -> Array:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var posts := _codes(sp, i, "post")
	sp.strike(posts[0], 300.0, 0.0, 1.0)
	sp.strike(posts[1], 300.0, 0.0, 1.0)
	_ticks(g, 7.0)
	var back := _game(level_id)
	GameSnapshot.apply(back, GameSnapshot.capture(g))
	_ticks(back, .1)
	var ruin := _ruin(back)
	var r: SetPieceWreck.Ruin = ruin.ruins.get(i)
	if r == null:
		return [0, false, ruin.fx.puffs.size()]
	return [r.bits.size(), r.still, ruin.fx.puffs.size()]


## The barn down, saved and read back: [its pieces, all still].
func _brought_down_saved(level_id: String) -> Array:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "barn")
	var posts := _codes(sp, i, "post")
	sp.strike(posts[0], 300.0, 0.0, 1.0)
	sp.strike(posts[1], 300.0, 0.0, 1.0)
	_ticks(g, 7.0)
	var path := OS.get_cache_dir().path_join("set-piece-looks.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	if back == null:
		return [0, false]
	_ticks(back, .1)
	var r: SetPieceWreck.Ruin = _ruin(back).ruins.get(i)
	if r == null:
		return [0, false]
	return [r.bits.size(), r.still]


## A tower comes apart: its legs snap, its tank tears in the fall, its hoops
## spring off in bands that end on the ground (never in the air), its deck
## splinters.
func _tower_looks(level_id: String) -> void:
	var g := _game(level_id)
	var sp := _sets(g)
	var i := _find(sp, "tower")
	var made: Array = sp.shapes[i]
	for code: int in _codes(sp, i, "leg"):
		if _part(sp, code).side.y < 0.0:
			sp.strike(code, 300.0, 0.0, -1.0)
	_ticks(g, 8.0)
	var r: SetPieceWreck.Ruin = _ruin(g).ruins.get(i)
	if r == null:
		check(false, "the tower's ruin is made")
		return
	var hoops := 0
	var high_hoop := -INF
	var deck := 0
	var torn := 0
	var legs := 0
	for b: SetPieceWreck.Bit in r.bits:
		var part: Shape.Part = made[b.k]
		var ground := g.world.elevation(b.rest_p.x, b.rest_p.y)
		match part.role:
			"hoop":
				hoops += 1
				high_hoop = maxf(high_hoop, b.rest_p.z - ground)
			"deck":
				deck += 1
			"tank":
				torn += 1
			"leg":
				legs += 1
	print(
		(
			(
				"    tower: %d pieces, %d hoop bands (highest %.2f up), %d deck planks,"
				+ " %d staves torn out, %d leg pieces"
			)
			% [r.bits.size(), hoops, high_hoop, deck, torn, legs]
		)
	)
	check(
		hoops >= 6 and high_hoop < 1.3,
		"its hoops spring off in bands that lie on the ground or the pile"
	)
	check(deck >= 6, "its deck splinters (%d planks)" % deck)
	check(torn >= 3, "its tank tore open in the fall (%d staves)" % torn)
	check(legs >= 6, "its legs snap (%d pieces of 4 legs)" % legs)
	check(r.still, "and it all lies still")
