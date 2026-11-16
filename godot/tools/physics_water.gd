## physics_check.gd's water part (run from there): things that come down in
## the bayou's water splash (features/water.gd splash(): rings, a crest and
## drops); brass and gibs sink and are gone; a body thrown in splashes,
## floats and drifts slowly on the current (corpses.gd, play: the same twice)
## and never onto the bank; a crate broken over the water throws boards that
## splash and float off on the current, asleep (wreckage.gd).
extends RefCounted

const DT := 1.0 / 60.0
const Water := preload("res://src/features/water.gd")

var check: SceneTree


func _init(owner: SceneTree) -> void:
	check = owner


func _check(ok: bool, text: String) -> void:
	check.call("_check", ok, text)


func _ok(text: String) -> void:
	check.call("_ok", text)


func run(main: Node) -> void:
	var game := _game(main)
	var spot := _open_water(game)
	_check(spot != Vector2.INF, "the bayou has open water")
	if spot == Vector2.INF:
		return
	var water = game.features["water"]
	var world := game.world
	var surface := world.floor_under(spot.x, spot.y, 99.0)
	# Brass dumped over the water splashes and sinks.
	var p := game.player
	p.x = spot.x
	p.y = spot.y
	p.floor_z = surface
	p.eye = surface + .95
	var debris = game.features["debris"]
	debris.bits.clear()
	var before: int = water.splashes
	game.events.gun_reloading.emit(Weapons.REVOLVER)
	var went := 0
	for _t in 120:
		debris._tick(DT)
	for bit in debris.bits:
		went += 1 if bit.kind == "casing" else 0
	_check(water.splashes > before, "brass falling in the water splashes (%d)" % (water.splashes - before))
	_check(went == 0, "the brass sinks and is gone (%d left)" % went)
	_ok("brass falling in the water splashes and sinks (%d splashes)" % (water.splashes - before))
	# A burst over the water: the gibs splash and go under.
	var gore: Gore = game.gore_fx
	gore.gibs.clear()
	var e := _hand(game)
	e.x = spot.x
	e.y = spot.y
	e.floor_z = surface
	before = water.splashes
	gore.burst(e)
	for _t in 240:
		gore.tick(DT)
	var under := 0
	for g: Gore.Gib in gore.gibs:
		if g.sinking and g.z < world.floor_under(g.x, g.y, 99.0) - .1:
			under += 1
	_check(
		water.splashes > before and under > 0,
		"gibs falling in the water splash (%d) and sink (%d of %d)"
		% [water.splashes - before, under, gore.gibs.size()]
	)
	_ok("a burst over the water: %d gibs splash in and sink" % under)
	# A body thrown into the water splashes, floats and drifts on the current.
	var ends: Array = []
	for _k in 2:
		game = _game(main)
		water = game.features["water"]
		e = _hand(game)
		var at := spot - Water.current("bayou").normalized() * .6
		e.x = at.x
		e.y = at.y
		e.floor_z = world.floor_under(at.x, at.y, 99.0)
		var corpses = game.features["corpses"]
		corpses.moving.clear()
		before = water.splashes
		game.player.x = spot.x
		game.player.y = spot.y + 3.0
		e.dormant = false
		game.hit_point = Vector3(e.x, e.y, game.world.stand(e) + .9)
		game.hit_from = Vector2(e.x, e.y) - Water.current("bayou").normalized()
		e.hurt(999.0, game, false, false, null, "shotgun")
		var held := Game.Controls.new()
		for _t in 60 * 5:
			game.tick(DT, held)
			if corpses._floats.has(e):
				break
		var afloat := Vector2(e.x, e.y)
		if not corpses._floats.has(e):
			print(
				(
					"    %s alive %s dormant %s explosive %s moving %d wet %s at %s"
					% [
						e.kind,
						e.alive,
						e.dormant,
						e.explosive,
						corpses.moving.size(),
						BayouBrains.wet_at(game.world, e.x, e.y),
						afloat
					]
				)
			)
		for _t in 60 * 10:
			game.tick(DT, held)
		ends.append(Vector2(e.x, e.y))
		var drifted := Vector2(e.x, e.y).distance_to(afloat)
		_check(water.splashes > before, "a body thrown in the water splashes")
		_check(corpses._floats.has(e), "the body floats")
		_check(
			drifted > .3 and BayouBrains.wet_at(game.world, e.x, e.y),
			"it drifts on the current and stays in the water (%.2f)" % drifted
		)
	_check(ends[0] == ends[1], "the same throw drifts the same (%s, %s)" % [ends[0], ends[1]])
	_ok("a body thrown in the water splashes, floats and drifts on the current, the same twice")
	_crate(main)


## Something broken over the water: its boards splash in and float off on
## the current, asleep.
func _crate(main: Node) -> void:
	var game := _game(main)
	var spot := _open_water(game)
	var wreck = game.features["wreckage"]
	var water = game.features["water"]
	var before: int = water.splashes
	var surface := game.world.floor_under(spot.x, spot.y, 99.0)
	var src := {
		"key": "m:tnt_crate|boards:2",
		"origin": Vector3(spot.x, spot.y, surface + .3),
		"basis": Basis.IDENTITY,
		"size": 1.0,
	}
	wreck._throw(src, Vector3(.5, 0.0, 1.0), 1.0, 99, "debris_settle", [])
	_check(not wreck.wrecks.is_empty(), "a crate broken over the water throws boards")
	var starts := {}
	for _t in 60 * 6:
		wreck._tick(DT)
		game.clock += DT
	for w in wreck.wrecks:
		starts[w] = w.body.p
	for _t in 60 * 6:
		wreck._tick(DT)
		game.clock += DT
	var floating := 0
	var moved := 0
	for w in wreck.wrecks:
		if w.floats == 1:
			floating += 1
			if w.body.p.distance_to(starts[w]) > .1:
				moved += 1
	_check(water.splashes > before, "a crate's boards falling in the water splash")
	_check(floating > 0 and moved > 0, "its boards float (%d) and drift (%d)" % [floating, moved])
	_check(not wreck.physics.moving(), "drifting boards stay asleep")
	_ok("a crate broken over the water: its boards splash, %d float, %d drift off asleep" % [floating, moved])


func _game(main: Node) -> Game:
	var game: Game = main.make_game("bayou")
	game.configure({})
	game.cheats.god = true
	for e: Enemy in game.enemies:
		e.dormant = true
	return game


func _hand(game: Game) -> Enemy:
	for one: Enemy in game.enemies:
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind) and not GoreExtras.metal(one):
			return one
	return game.enemies[0]


## A spot in the bayou's water with water all round it for two cells, no
## deck over it and nothing in the way.
func _open_water(game: Game) -> Vector2:
	var world := game.world
	for cy in range(3, world.height - 3):
		for cx in range(3, world.width - 3):
			var ok := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var x := cx + dx + .5
					var y := cy + dy + .5
					if (
						not BayouBrains.wet_at(world, x, y)
						or world.blocked(x, y, .3)
						or world.floor_under(x, y, 99.0) > world.elevation(x, y) + .01
					):
						ok = false
			if ok:
				return Vector2(cx + .5, cy + .5)
	return Vector2.INF
