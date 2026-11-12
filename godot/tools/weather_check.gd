## The weather, the water and the shimmer's checks (tools/check_fixes.gd runs
## them; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/weather_check.gd
##
## Rain falls only where effects.cfg says (a storm chapter from its start, a
## showery one in spells), never on the Mothership or at the Crossroads;
## every tile [water], [relief] and [puddles] names exists and the water ones
## are water underfoot; a body wading leaves rings on the water and none on
## dry ground, the swamp king's airboat leaves a wake; the lamps pool their
## light and the stills, burn barrels and the Mothership's core shimmer.
## All of it is looks for the graphics-card view: the pictures themselves are
## checked by eye in a window (CLAUDE.md), not here.
extends SceneTree

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(main, func(ok: bool, text: String) -> void: _check(ok, text))
	print("")
	print("WEATHER OK" if failures.is_empty() else "%d WEATHER CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## A few seconds of the game's clock, as far as the looks are concerned.
static func _pass(g: Game, seconds: float) -> void:
	for i in int(seconds * 60.0):
		g.clock += 1.0 / 60.0
		g.ticked.emit(1.0 / 60.0)


static func run(main, check: Callable) -> void:
	print("WEATHER (rain only where effects.cfg says, water rings, pools, shimmer)")
	var was := Effects.enabled
	Effects.enabled = true
	var levels: Array = Campaign.ORDER.duplicate()
	levels.append_array(["hub", "range"])
	var rainy: Array = []
	for id: String in levels:
		var g: Game = main.make_game(id)
		g.configure({})
		var weather = g.features["weather"]
		var hard := float(Effects.mood(id, "rain", 0.0))
		var share := float(Effects.mood(id, "showers", 0.0))
		_pass(g, 2.0)
		if hard <= 0.0 or g.in_hub:
			check.call(
				weather.rain == 0.0 and weather.wet == 0.0, "%s: no rain, the ground dry" % id
			)
			continue
		rainy.append(id)
		if share <= 0.0:
			check.call(
				weather.rain > hard * .9 and weather.wet > hard * .9,
				"%s: a storm from the start, the ground already soaked" % id
			)
		else:
			check.call(weather.rain == 0.0, "%s: the showers start dry" % id)
			_pass(g, weather.spell_until - g.clock + 6.0)
			check.call(weather.rain > 0.0, "%s: then a spell of rain comes" % id)
			_pass(g, weather.spell_until - g.clock + .1)
			var soaked: float = weather.wet
			_pass(g, 12.0)
			check.call(
				weather.rain < hard * .5 and weather.wet < soaked,
				"%s: and lets up, the ground drying" % id
			)
	check.call(
		rainy.has("hickston") and rainy.has("sawmill") and rainy.has("bayou"),
		"rain over Hickston, the mill and the bayou (%s)" % ", ".join(rainy)
	)
	check.call(
		not rainy.has("mothership") and Effects.mood("mothership", "rain", 0.0) == 0.0,
		"never rain in the Mothership: it is all indoors"
	)
	_tiles(main, check)
	_rings(main, check)
	_lights(main, check)
	Effects.enabled = was


## Every tile effects.cfg names is a tile; [water] tiles are water underfoot.
static func _tiles(main, check: Callable) -> void:
	var g: Game = main.make_game("bayou")
	var missing: Array = []
	for table: Dictionary in [Effects.WATER, Effects.RELIEF, Effects.PUDDLES]:
		for name: String in table:
			if not g.world.tile_index.has(name):
				missing.append(name)
	check.call(missing.is_empty(), "every tile effects.cfg names exists %s" % str(missing))
	var dry: Array = []
	for name: String in Effects.WATER:
		if String(LevelData.SURFACE_SOUNDS.get(name, "")) != "water":
			dry.append(name)
	check.call(dry.is_empty(), "every [water] tile is water underfoot %s" % str(dry))


## Wading rings on the water, none on dry ground; the airboat's wake.
static func _rings(main, check: Callable) -> void:
	var g: Game = main.make_game("bayou")
	g.configure({})
	var water = g.features["water"]
	var p := g.player
	var wet_cell := _find(g, "bayou_water")
	var dry_cell := _find(g, "bayou_planks")
	check.call(wet_cell.x > 0.0 and dry_cell.x > 0.0, "the bayou has water and planks to try")
	p.x = dry_cell.x
	p.y = dry_cell.y
	_pass(g, .1)
	water.rings.clear()
	for i in 30:
		p.x += .03
		_pass(g, 1.0 / 60.0)
	check.call(water.rings.is_empty(), "walking the planks leaves no rings")
	p.x = wet_cell.x
	p.y = wet_cell.y
	_pass(g, .1)
	water.rings.clear()
	for i in 40:
		p.x += .03
		_pass(g, 1.0 / 60.0)
	check.call(water.rings.size() >= 2, "wading leaves rings (%d)" % water.rings.size())
	check.call(not water.shown(p.x, p.y).is_empty(), "and the shader is handed the nearest of them")
	var king: Enemy = null
	for e: Enemy in g.enemies:
		if e.brain == "swamp_king":
			king = e
	check.call(king != null, "the bayou has its swamp king")
	if king == null:
		return
	# Along open water, as on a run.
	king.x = wet_cell.x - 1.0
	king.y = wet_cell.y
	king.angle = 0.0
	# Out on the water and awake (he is held back, dormant, until the last
	# station is done).
	king.dormant = false
	p.x = king.x
	p.y = king.y + 3.0
	_pass(g, .1)
	water.rings.clear()
	for i in 40:
		king.x += .05
		_pass(g, 1.0 / 60.0)
	check.call(water.rings.size() >= 3, "the airboat leaves a wake (%d rings)" % water.rings.size())
	water.rings.clear()
	g.exploded.emit(wet_cell.x, wet_cell.y, .2, false)
	check.call(water.rings.size() >= 1, "a blast in the water rings it")


## The middle of an open cell floored with `name`, whose neighbours across
## are floored with it too.
static func _find(g: Game, name: String) -> Vector2:
	var world: LevelData = g.world
	var tile := world.tile_id(name)
	for i in range(world.width, world.floor_tile.size() - world.width):
		var row := [i - 1, i, i + 1, i + 2]
		var all := true
		for k: int in row:
			all = all and k < world.floor_tile.size() and int(world.floor_tile[k]) == tile
			all = all and world.solid[k] < 0
		if all:
			return Vector2(i % world.width + .5, i / world.width + .5)
	return Vector2(-1, -1)


## The lamps pool their light; the stills, burn barrels and the core shimmer.
static func _lights(main, check: Callable) -> void:
	var lamp = Effects.light("lamp", 0.0, 0.0, 1.0)
	check.call(
		lamp != null and (int(lamp[6]) & Effects.POOL) != 0, "a lamp pools its light on the ground"
	)
	var still = Effects.light("still", 0.0, 0.0, .4)
	check.call(
		still != null and (int(still[6]) & Effects.HOT) != 0 and float(still[7]) > 0.0,
		"a still's fire shimmers"
	)
	var g: Game = main.make_game("hickston")
	g.configure({})
	g.player.x = 11.5
	g.player.y = 18.0
	var hot := ViewLights.heat_sources(g, 4)
	var near_still := false
	for s: Array in hot:
		if absf(float(s[0]) - 11.5) < .1 and absf(float(s[1]) - 15.5) < .1:
			near_still = true
	check.call(near_still, "Hickston's still is among the hot things in sight")
	var lit := false
	for l: Array in g.effect_lights():
		lit = lit or (absf(float(l[0]) - 11.5) < .1 and absf(float(l[1]) - 15.5) < .1)
	check.call(lit, "and its fire box lights the yard")
	var ship: Game = main.make_game("mothership")
	ship.configure({})
	ship.player.x = 60.0
	ship.player.y = 50.0
	var core := false
	for s: Array in ViewLights.heat_sources(ship, 4):
		core = core or (absf(float(s[0]) - 64.0) < .1 and absf(float(s[1]) - 50.0) < .1)
	check.call(core, "the Mothership's core shimmers")
	var engine_off = Effects.light("generator", 0.0, 0.0, 1.0)
	check.call(
		engine_off != null and float(engine_off[5]) == 0.0 and float(engine_off[7]) > 0.0,
		"a generator only shimmers: no light of its own"
	)
