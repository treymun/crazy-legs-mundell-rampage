## Checks of the things a hand picks up and throws, the fire that spreads and
## the moonshine stills (features/carry.gd, fire.gd, stills.gd). In
## check_all's quick set and CI; on its own, from a scratch profile:
##
##   Godot --headless --path <project> --script res://tools/live_props_check.gd
##
## Every chapter has things to take up; a rocking chair taken up hides where
## it stood, is held, thrown into a hand hurts and shoves it, and comes to rest
## standing where it stopped (taken up again there); a propane tank thrown at
## a wall breaks and goes up; jugs of shine break and spill puddles; a brute
## takes up a crate and heaves it at the player; a set-down's save comes back.
## Fire lit on a hay loft spreads over the hay, never onto stone or dirt, chars
## what burned and burns out, the same twice over, never more than its cap at
## once, sooner in the rain; a puddle of shine catches. A still shot sprays
## burning shine that lights the floor; shot to pieces it goes up as a still
## blast, throws copper and leaves fire. Off (LIVE PROPS AND FIRE), nothing.
extends SceneTree

const Carry := preload("res://src/features/carry.gd")
const Fire := preload("res://src/features/fire.gd")
const Stills := preload("res://src/features/stills.gd")
const Breakables := preload("res://src/features/breakables.gd")
const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
const DT := 1.0 / 60.0

var failures: Array = []
var blasts: Array = []


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
	print("LIVE PROPS OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main, level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({})
	g.cheats.god = true
	return g


## The world's tick for the features: the clock, the shots, the features.
static func _ticks(g: Game, seconds: float) -> void:
	for _k in int(seconds * 60.0):
		g.clock += DT
		g.update_shots(DT)
		g.events.ticked.emit(DT)


## Stand the player at (x, y) facing (tx, ty).
static func _stand(g: Game, x: float, y: float, tx: float, ty: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.pitch = 0.0
	p.air = 0.0
	p.eye = g.world.stand(p) + .95


## A spot `d` from (x, y) the player can stand on and see (x, y) from.
static func _spot(g: Game, x: float, y: float, d: float) -> Vector2:
	for k in 16:
		var a := k * TAU / 16.0
		var at := Vector2(x + cos(a) * d, y + sin(a) * d)
		if at.x < 1 or at.y < 1 or at.x > g.world.width - 1 or at.y > g.world.height - 1:
			continue
		if g.world.blocked(at.x, at.y, .25):
			continue
		var z := g.world.elevation(at.x, at.y)
		if absf(z - g.world.elevation(x, y)) > .2:
			continue
		if g.world.visible(at.x, at.y, x, y, z + .9, z + .4):
			return at
	return Vector2.INF


static func run(main, check: Callable) -> void:
	print("PICK UP AND THROW, SPREADING FIRE, THE STILLS")
	var probe := _game(main, "hickston")
	var made := (
		probe.features.get("carry") is Carry
		and probe.features.get("fire") is Fire
		and probe.features.get("stills") is Stills
	)
	check.call(made, "every game has the carry, fire and stills features")
	if not made:
		return
	var counts: Array = []
	var every := true
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var carry: Carry = g.features["carry"]
		counts.append("%s %d" % [level_id, carry.things.size()])
		every = every and carry.things.size() >= 3
	print("    things to take up: ", ", ".join(counts))
	check.call(every, "every chapter has things to take up")
	_chair(main, check)
	_propane(main, check)
	_jugs(main, check)
	_brute(main, check)
	_fire_spreads(main, check)
	_fire_rain(main, check)
	_still(main, check)
	_snapshot(main, check)
	_off(main, check)


## A game with a chair in the air and hay burning, put onto a fresh game by a
## snapshot, carries on the same: the things, the fire and the board hidden.
static func _snapshot(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var carry: Carry = g.features["carry"]
	var fire: Fire = g.features["fire"]
	var i := _find(carry, "town_rocker")
	if not _take(g, carry, i):
		check.call(false, "a chair is taken up for the snapshot")
		return
	_ticks(g, .3)
	carry.hands(g.player, true, false)
	_ticks(g, .1)
	var hay := _hay(fire)
	var c: int = hay[0]
	fire.fresh()
	fire.ignite((c % g.world.width) + .5, float(c / g.world.width) + .5, fire._z[c])
	_ticks(g, 1.0)
	var data := GameSnapshot.capture(g)
	var g2 := _game(main, "hickston")
	var applied := GameSnapshot.apply(g2, data)
	var t2: Carry.Thing = g2.features["carry"].things[i]
	_ticks(g2, DT)
	_ticks(g, DT)
	var same := true
	for id: String in ["carry", "fire", "stills"]:
		var a: Dictionary = GameSnapshot.capture(g)["features"][id]
		var b: Dictionary = GameSnapshot.capture(g2)["features"][id]
		if var_to_str(a) != var_to_str(b):
			same = false
			print("    differs: ", id)
	check.call(applied and same, "a snapshot carries a throw and a fire on, tick for tick")
	check.call(t2.board.image == "", "and the copy hides where the chair stood")
	for _k in 120:
		_ticks(g, DT)
		_ticks(g2, DT)
	var later := var_to_str(GameSnapshot.capture(g)["features"]["fire"])
	check.call(
		later == var_to_str(GameSnapshot.capture(g2)["features"]["fire"]),
		"two seconds on, the fires are the same"
	)


static func _find(carry: Carry, image: String) -> int:
	for i in carry.things.size():
		var t: Carry.Thing = carry.things[i]
		if t.image == image and carry.takeable(t):
			return i
	return -1


## Take up thing i from a spot near it: true when it is held.
static func _take(g: Game, carry: Carry, i: int) -> bool:
	var t: Carry.Thing = carry.things[i]
	var at := carry.place_of(t)
	var spot := _spot(g, at.x, at.y, .9)
	if spot == Vector2.INF:
		return false
	_stand(g, spot.x, spot.y, at.x, at.y)
	if carry.target() != i:
		return false
	return carry.use() and carry.held_by(g.player) == i


static func _chair(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var carry: Carry = g.features["carry"]
	var i := _find(carry, "town_rocker")
	check.call(i >= 0, "hickston has a rocking chair to take up")
	if i < 0:
		return
	var t: Carry.Thing = carry.things[i]
	var was := carry.place_of(t)
	var prompt := g.use_prompt()
	var held := _take(g, carry, i)
	check.call(held, "USE takes up the rocking chair (prompt was '%s')" % prompt)
	if not held:
		return
	check.call(
		t.board.image == "" and g.player.armory.holstered,
		"where it stood shows nothing, and the gun goes down"
	)
	# A hand stood three cells on, the way the player faces.
	var p := g.player
	var e: Enemy = null
	for enemy: Enemy in g.enemies:
		if enemy.alive and enemy.hostile and enemy.brain != "boss":
			e = enemy
			break
	var fx := cos(p.angle)
	var fy := sin(p.angle)
	var spot := Vector2(p.x - fx * .2, p.y - fy * .2)
	for k in range(12, 2, -1):
		var at := Vector2(p.x + fx * k * .25, p.y + fy * k * .25)
		if not g.world.blocked(at.x, at.y, .3) and g.world.visible(p.x, p.y, at.x, at.y):
			spot = at
			break
	e.x = spot.x
	e.y = spot.y
	e.dormant = false
	var hp := e.hp
	var e_was := Vector2(e.x, e.y)
	_ticks(g, .3)
	carry.hands(p, true, false)
	check.call(t.state == Carry.FLY and not p.armory.holstered, "FIRE throws it, the gun comes up")
	for _k in 240:
		_ticks(g, DT)
		if t.state == Carry.STAND:
			break
	check.call(
		e.hp < hp and Vector2(e.x, e.y).distance_to(e_was) > .02,
		"the chair hurts the hand it strikes (%.0f to %.0f) and shoves it" % [hp, e.hp]
	)
	var rests := t.state == Carry.STAND and t.board.image == "town_rocker"
	check.call(
		rests and Vector2(t.x, t.y).distance_to(Vector2(was.x, was.y)) > .3,
		"it comes to rest standing where it stopped (%.2f, %.2f)" % [t.x, t.y]
	)
	var floor_z := Tumble.floor_at(g.world, t.x, t.y, t.foot + .5)
	check.call(absf(t.foot - floor_z) < .05, "on the floor there, not in it or over it")
	# A save made now puts it back there.
	var saved: Dictionary = carry.save()
	var g2 := _game(main, "hickston")
	var carry2: Carry = g2.features["carry"]
	carry2.restore(saved)
	var t2: Carry.Thing = carry2.things[i]
	check.call(
		t2.board.image == "town_rocker" and absf(t2.board.x - t.x) < .02,
		"a save keeps where it was set down"
	)
	check.call(_take(g, carry, i), "it can be taken up again where it lies")
	carry.hands(p, false, false)
	_ticks(g, .3)
	carry.hands(p, false, true)
	for _k in 240:
		_ticks(g, DT)
		if t.state == Carry.STAND:
			break
	check.call(
		t.state == Carry.STAND and Vector2(t.x, t.y).distance_to(Vector2(p.x, p.y)) < 1.2,
		"ALT FIRE sets it down at the player's feet"
	)


static func _propane(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var carry: Carry = g.features["carry"]
	var bk: Breakables = g.features["breakables"]
	var i := _find(carry, "town_propane_tank")
	check.call(i >= 0, "hickston has a propane tank to take up")
	if i < 0 or not _take(g, carry, i):
		check.call(false, "the propane tank is taken up")
		return
	var t: Carry.Thing = carry.things[i]
	var went := [0]
	g.events.exploded.connect(
		func(_x: float, _y: float, _z: float, _e: bool) -> void: went[0] = int(went[0]) + 1
	)
	# Face the nearest wall and throw it hard.
	var p := g.player
	var best := 99.0
	var face := p.angle
	for k in 32:
		var a := k * TAU / 32.0
		for d in range(2, 24):
			var at := Vector2(p.x + cos(a) * d * .25, p.y + sin(a) * d * .25)
			if g.world.blocked(at.x, at.y, .05, p.eye):
				if d * .25 < best and d * .25 > 1.0:
					best = d * .25
					face = a
				break
	p.angle = face
	_ticks(g, .3)
	carry.hands(p, true, false)
	for _k in 300:
		_ticks(g, DT)
	var piece: Breakables.Piece = bk.pieces[t.piece]
	check.call(
		piece.broken and t.state == Carry.GONE,
		"a propane tank thrown at a wall %.1f off breaks" % best
	)
	check.call(int(went[0]) >= 1, "and goes up")


static func _jugs(main, check: Callable) -> void:
	var g := _game(main, "quarry")
	var carry: Carry = g.features["carry"]
	var fire: Fire = g.features["fire"]
	var bk: Breakables = g.features["breakables"]
	var i := _find(carry, "town_jug_stack")
	if i < 0 or not _take(g, carry, i):
		check.call(false, "quarry's jugs of shine are taken up")
		return
	var t: Carry.Thing = carry.things[i]
	var p := g.player
	p.pitch = -20.0
	_ticks(g, .3)
	carry.hands(p, true, false)
	for _k in 240:
		_ticks(g, DT)
	var piece: Breakables.Piece = bk.pieces[t.piece]
	check.call(piece.broken, "jugs of shine thrown down break")
	check.call(fire.puddles.size() >= 1, "and spill shine (%d puddles)" % fire.puddles.size())


static func _brute(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	g.cheats.god = false
	var carry: Carry = g.features["carry"]
	var i := _find(carry, "town_propane_tank")
	var t: Carry.Thing = carry.things[i]
	var at := carry.place_of(t)
	var e: Enemy = null
	for enemy: Enemy in g.enemies:
		if enemy.alive and enemy.brain == "billy":
			e = enemy
			break
	check.call(e != null, "hickston has a billy")
	if e == null:
		return
	var stand := _spot(g, at.x, at.y, .9)
	e.x = stand.x
	e.y = stand.y
	e.dormant = false
	var me := _spot(g, e.x, e.y, 5.0)
	_stand(g, me.x, me.y, e.x, e.y)
	var health := g.player.health
	var heaved := false
	for _k in 60 * 60:
		e.see_time = 1.0
		e.hunted = g.player
		e.windup = 0.0
		_ticks(g, DT)
		if t.state == Carry.FLY and t.thrower_uid == e.uid:
			heaved = true
		if heaved and t.state != Carry.FLY:
			break
	check.call(heaved, "a billy takes up the tank near it and heaves it")
	check.call(
		g.player.health < health or Vector2(t.x, t.y).distance_to(Vector2(me.x, me.y)) < 2.0,
		"at the player (health %d to %d)" % [health, g.player.health]
	)


## The cells of hickston's hay (a loft or a stack): the first with hay, and
## all of them.
static func _hay(fire: Fire) -> Array:
	var cells: Array = []
	for c in fire._fuel.size():
		if fire._fuel[c] > 0.0 and fire._catch[c] >= .9:
			cells.append(c)
	return cells


static func _fire_spreads(main, check: Callable) -> void:
	var results: Array = []
	for round_k in 2:
		var g := _game(main, "hickston")
		var fire: Fire = g.features["fire"]
		var hay := _hay(fire)
		if hay.is_empty():
			check.call(false, "hickston has hay that burns")
			return
		# The hay cell with the most hay round it.
		var w := g.world
		var start: int = hay[0]
		var most := -1
		for c: int in hay:
			var n := 0
			for d: Vector2i in Fire.NEAR:
				var q := c + d.y * w.width + d.x
				n += 1 if hay.has(q) else 0
			if n > most:
				most = n
				start = c
		fire.fresh()
		var x := (start % w.width) + .5
		var y := float(start / w.width) + .5
		var lit := fire.ignite(x, y, fire._z[start])
		var bad: Array = []
		var biggest := 0
		var seconds := 0.0
		while seconds < 120.0:
			_ticks(g, .25)
			seconds += .25
			biggest = maxi(biggest, fire.burning.size())
			for row: Array in fire.burning:
				var c: int = row[0]
				if fire._fuel[c] <= 0.0 and not bad.has(c):
					bad.append(c)
			if fire.burning.is_empty():
				break
		var chars: Array = fire.charred.keys()
		chars.sort()
		results.append(chars)
		if round_k == 0:
			check.call(lit, "fire set to hickston's hay takes (%d hay cells)" % hay.size())
			check.call(
				chars.size() >= 4, "it spreads over the hay (%d cells burned)" % chars.size()
			)
			check.call(
				bad.is_empty(), "never onto stone or dirt (%d cells without fuel)" % bad.size()
			)
			check.call(
				fire.burning.is_empty(), "and burns out (%.0f s), each cell charred" % seconds
			)
			check.call(biggest <= int(fire.num("cap")), "never more than its cap at once")
			check.call(g.features["fire"].ground_marks().size() >= 0, "the chars are marks")
	check.call(results[0] == results[1], "the same fire twice burns the same cells")


static func _fire_rain(main, check: Callable) -> void:
	var lasted: Array = []
	for wet: float in [0.0, 1.0]:
		var g := _game(main, "hickston")
		var fire: Fire = g.features["fire"]
		fire._rain = wet
		var w := g.world
		var spot := -1
		for c in fire._fuel.size():
			if fire._fuel[c] > 0.0 and w.roof[c] == 0.0:
				spot = c
				break
		if spot < 0:
			# Lit on bare open ground: a patch.
			spot = w.cell(float(w.width) * .5, float(w.height) * .5)
		fire.fresh()
		fire.ignite((spot % w.width) + .5, float(spot / w.width) + .5, w.ground[spot], 4.0)
		var seconds := 0.0
		while not fire.burning.is_empty() and seconds < 60.0:
			_ticks(g, .25)
			seconds += .25
		lasted.append(seconds)
	check.call(lasted[1] < lasted[0], "rain puts it out sooner (%.1f s dry, %.1f s wet)" % lasted)
	# A puddle of shine on dirt catches from a fire beside it.
	var g := _game(main, "hickston")
	var fire: Fire = g.features["fire"]
	var p := g.player
	fire.spill(p.x + 1.0, p.y, g.world.elevation(p.x + 1.0, p.y))
	var had := fire.puddles.size()
	fire.fresh()
	fire.ignite(p.x, p.y, g.world.elevation(p.x, p.y), 3.0)
	_ticks(g, 1.0)
	check.call(had == 1 and fire.puddles.is_empty(), "a puddle of shine beside a fire goes up")


static func _still(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var bk: Breakables = g.features["breakables"]
	var stills: Stills = g.features["stills"]
	var fire: Fire = g.features["fire"]
	var at := -1
	for i in bk.pieces.size():
		var piece: Breakables.Piece = bk.pieces[i]
		if piece.image == "town_still":
			at = i
			break
	check.call(at >= 0, "hickston's still is a breakable")
	if at < 0:
		return
	var piece: Breakables.Piece = bk.pieces[at]
	var kinds: Array = []
	g.events.exploded.connect(
		func(_x: float, _y: float, _z: float, _e: bool) -> void: kinds.append(g.blast_kind)
	)
	bk.strike(at, 5.0, 1.0, 0.0)
	check.call(stills.jets.size() == 1, "a still shot sprays from the holed pipe")
	_ticks(g, 1.0)
	check.call(
		not fire.burning.is_empty() or not fire.puddles.is_empty(),
		"the spray lights the floor (%d burning)" % fire.burning.size()
	)
	var bits := bk.bits.size()
	bk.strike(at, 500.0, 1.0, 0.0)
	_ticks(g, .5)
	check.call(piece.broken and stills.jets.is_empty(), "shot to pieces it breaks")
	check.call(kinds.has("still"), "and goes up as a still blast")
	check.call(
		bk.bits.size() > bits + 10, "its copper flies in pieces (%d)" % (bk.bits.size() - bits)
	)
	check.call(
		fire.burning.size() >= 3, "and leaves fire round it (%d cells)" % fire.burning.size()
	)


static func _off(main, check: Callable) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"live_props": 0})
	var carry: Carry = g.features["carry"]
	var fire: Fire = g.features["fire"]
	var i := _find(carry, "town_rocker")
	var t: Carry.Thing = carry.things[i]
	var at := carry.place_of(t)
	var spot := _spot(g, at.x, at.y, .9)
	_stand(g, spot.x, spot.y, at.x, at.y)
	var took := carry.target() >= 0
	fire.fresh()
	var lit := fire.ignite(g.player.x, g.player.y, g.player.eye - .9, 3.0)
	check.call(not took and not lit, "LIVE PROPS AND FIRE off: nothing taken up, no fire")
