## The weather you can feel, County Run's storm front and the critters'
## physics (tools/check_fixes.gd runs it; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/climate_check.gd
##
## Puddles gather the longer it rains; mud slows a player and a hand on a
## muddy floor (not with WEATHER OFF, and never on a floor that does not
## muddy); the wind carries a thrown stick of dynamite off its line a little,
## the same every time; the storm front calls a stage, closes the ring to a
## smaller one inside the last, hurts and shoves a player outside it and not
## inside, throws its pieces near the wall, is gone with COUNTY STORM off and
## plays the same for two DAILY RUNs of a day; a chicken flaps and glides
## off, a hog's charge bowls a player over, the mule kicks whoever stands
## behind it (not in front), a cow tips at a USE, lies a while and gets up.
extends SceneTree

const STEP := 1.0 / 60.0

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
	print("CLIMATE OK" if failures.is_empty() else "%d CLIMATE CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func run(main, check: Callable) -> void:
	print("CLIMATE (puddles, mud, wind, the storm front, critters)")
	_puddles(main, check)
	_mud(main, check)
	_wind(main, check)
	_storm(main, check)
	_daily(main, check)
	_critters(main, check)


## The weather's clock alone (no bodies moving), as weather_check does it.
static func _pass(g: Game, seconds: float) -> void:
	for i in int(seconds * 60.0):
		g.clock += STEP
		g.events.ticked.emit(STEP)


static func _puddles(main, check: Callable) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({})
	var climate = g.features["climate"]
	var weather = g.features["weather"]
	var before: float = climate.pool
	_pass(g, 90.0)
	check.call(
		climate.pool > before + .25 and absf(weather.pool - climate.pool) < .001,
		(
			"puddles gather the longer it rains (%.2f to %.2f), the looks follow"
			% [before, climate.pool]
		)
	)
	var dry: Game = main.make_game("fair")
	dry.configure({})
	_pass(dry, 30.0)
	check.call(dry.features["climate"].pool == 0.0, "and none on a dry chapter")


## A walk forward for `seconds` from (x, y): how far it got.
static func _walk(g: Game, x: float, y: float, angle: float, seconds: float) -> float:
	var p: Player = g.player
	p.x = x
	p.y = y
	p.angle = angle
	p.vx = 0.0
	p.vy = 0.0
	var held := Game.Controls.new()
	held.forward = 1.0
	for i in int(seconds * 60.0):
		g.tick(STEP, held)
	return Vector2(p.x - x, p.y - y).length()


static func _mud(main, check: Callable) -> void:
	var walked: Array = []
	var paced: Array = []
	for feel: int in [0, 2]:
		var g: Game = main.make_game("hickston")
		g.configure({"weather": feel})
		g.cheats.god = true
		Modes.clear_enemies(g)
		_pass(g, 60.0)
		# The orchard's grass (hickston_cast.gd), clear for a few cells east.
		walked.append(_walk(g, 10.5, 12.5, 0.0, .8))
		var prints: Array = g.features["weather"].prints
		var drawn := not prints.is_empty()
		for m: View.GroundMark in prints:
			drawn = drawn and g.art.has_art(m.image)
		check.call(drawn, "boots leave prints in the mud, drawn (%d)" % prints.size())
		paced.append(Mud.pace(g, 12.5, 12.5))
		if feel == 0:
			check.call(g.mud > .5, "a long storm leaves the ground muddy (%.2f)" % g.mud)
			check.call(
				Mud.at(g.world, 12.5, 12.5) > 0.0 and Mud.at(g.world, 60.5, 40.5) == 0.0,
				"grass muddies, Main Street's boards do not"
			)
			var e := Enemy.new("billy", 10.5, 16.5)
			var dry := Enemy.new("billy", 10.5, 16.5)
			var wet_step := e.advance(.5, g, 0.0)
			g.mud = 0.0
			var dry_step := dry.advance(.5, g, 0.0)
			check.call(
				wet_step < dry_step * .95 and wet_step > dry_step * .6,
				"a hand wades slower through mud (%.2f against %.2f)" % [wet_step, dry_step]
			)
		else:
			check.call(
				g.mud == 0.0 and g.features["weather"].pool > 0.0,
				"WEATHER OFF: no mud in play, the puddles still show"
			)
	check.call(
		walked[0] < walked[1] * .95 and walked[0] > walked[1] * .6,
		"mud slows the player a little (%.2f against %.2f cells)" % [walked[0], walked[1]]
	)
	check.call(paced[1] == 1.0 and paced[0] < 1.0, "WEATHER OFF walks as before")


## A stick of dynamite thrown on the same line: where it comes to rest.
static func _throw(main, feel: int) -> Vector2:
	var g: Game = main.make_game("hickston")
	g.configure({"weather": feel})
	g.cheats.god = true
	Modes.clear_enemies(g)
	_pass(g, 5.0)
	g.tick(STEP, Game.Controls.new())
	var shot := Game.Shot.new(10.5, 12.5, 1.2, 2.6, 0.0, 2.2, "tnt", 9.0, false, 0, 3)
	g.shots.append(shot)
	for i in 90:
		g.tick(STEP, Game.Controls.new())
	return Vector2(shot.x, shot.y)


static func _wind(main, check: Callable) -> void:
	var calm := _throw(main, 2)
	var blown := _throw(main, 0)
	var again := _throw(main, 0)
	var off := blown.distance_to(calm)
	check.call(
		off > .05 and off < 1.5,
		"the wind carries a thrown stick off its line a little (%.2f cells)" % off
	)
	check.call(blown == again, "the same throw in the same wind lands the same")


## A County Run on hickston's map (its spawner held off), the storm as asked.
static func _run_on(main, options: Dictionary, daily := "") -> Game:
	var g: Game = main.make_game("county_hickston")
	g.configure(options)
	Modes.setup(g, Modes.COUNTY, 1)
	if daily != "":
		g.rng.set_state(CountyBoard.seed_for(daily, "county_hickston"))
		g.features["county"].daily = daily
	g.tick(STEP, Game.Controls.new())
	var f = g.features["county"]
	f.next_spawn = 1e9
	f.next_elite = 1e9
	f.next_lull = 1e9
	Modes.clear_enemies(g)
	g.cheats.god = false
	return g


static func _ticks(g: Game, seconds: float) -> void:
	for i in int(seconds * 60.0):
		g.tick(STEP, Game.Controls.new())


static func _storm(main, check: Callable) -> void:
	var g := _run_on(main, {"difficulty": 1})
	var f = g.features["county"]
	check.call(f.storm_on and f.storm_stage == 0, "a run has the storm front, held off at first")
	var full: float = f.storm_r
	f.storm_next = f.run_time + 31.0
	_ticks(g, 2.0)
	check.call(
		f.storm_warned and CountyStorm.called_in(f) > 0.0,
		"the stage is called ahead (%.0f s)" % CountyStorm.called_in(f)
	)
	var p: Player = g.player
	p.health = 100
	_ticks(g, 31.0 + 31.0)
	var first: float = f.storm_r
	check.call(
		f.storm_stage == 1 and f.storm_moving.x < 0.0 and first < full * .8 and first >= 9.0,
		"the wall closes in to a smaller ring (%.1f of %.1f cells)" % [first, full]
	)
	# Inside, nothing; outside, the storm hurts and shoves.
	p.x = f.storm_at.x
	p.y = f.storm_at.y
	var spot := Vector2.ZERO
	for at: Vector2 in CountySpawner.spots(g):
		if (
			at.distance_to(f.storm_at) > f.storm_r + 2.0
			and at.distance_to(f.storm_at) < f.storm_r + 5.0
		):
			spot = at
			break
	var whole := p.health
	_ticks(g, 2.0)
	check.call(p.health == whole, "inside the ring the storm leaves you be")
	p.x = spot.x
	p.y = spot.y
	var bits_before: int = f.storm_bits.size()
	_ticks(g, 3.0)
	check.call(
		spot != Vector2.ZERO and p.health < whole and Vector2(p.x, p.y).distance_to(spot) > .3,
		(
			"outside it hurts (%d) and shoves you (%.2f cells)"
			% [whole - p.health, Vector2(p.x, p.y).distance_to(spot)]
		)
	)
	check.call(
		f.storm_bits.size() > bits_before or f.storm_bit_next > 0.0,
		"its wall throws boards, tin and hay near you (%d)" % f.storm_bits.size()
	)
	var climate = g.features["climate"]
	check.call(climate.rain > .1 and climate.storm > .3, "the rain and the wind come with it")
	# The next stage closes inside the last.
	var last_at: Vector2 = f.storm_at
	var last_r: float = f.storm_r
	f.storm_next = f.run_time + .1
	_ticks(g, 32.0)
	check.call(
		(
			f.storm_stage == 2
			and f.storm_r < last_r
			and f.storm_at.distance_to(last_at) + f.storm_r <= last_r + .5
		),
		"the next ring is smaller and inside the last (%.1f in %.1f)" % [f.storm_r, last_r]
	)
	var off := _run_on(main, {"difficulty": 1, "county_storm": 0})
	var off_f = off.features["county"]
	off_f.storm_next = 0.0
	_ticks(off, 2.0)
	check.call(not off_f.storm_on and off_f.storm_stage == 0, "COUNTY STORM off: no storm")
	var daily := _run_on(main, {"difficulty": 1, "county_storm": 0}, CountyBoard.today())
	check.call(daily.features["county"].storm_on, "but a DAILY RUN always has it")


static func _daily(main, check: Callable) -> void:
	var plans: Array = []
	for day: String in [CountyBoard.today(), CountyBoard.today(), "2001-01-01"]:
		var g := _run_on(main, {"difficulty": 1}, day)
		var f = g.features["county"]
		g.cheats.god = true
		var plan: Array = []
		for stage in 3:
			f.storm_next = f.run_time + .1
			_ticks(g, 31.0)
			plan.append([f.storm_at.snapped(Vector2(.01, .01)), snappedf(f.storm_r, .01)])
		plans.append(plan)
	check.call(
		plans[0] == plans[1], "two DAILY RUNs of a day get the same storm (%s)" % str(plans[0][0])
	)
	check.call(plans[0] != plans[2], "another day's storm goes elsewhere")


## The hickston orchard's animals, the rest of the level cleared.
static func _farm(main) -> Game:
	var g: Game = main.make_game("hickston")
	g.configure({})
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.spawn_grace = 0.0
	return g


static func _one(g: Game, brain: String) -> Enemy:
	for e: Enemy in g.enemies:
		if e.brain == brain and e.alive:
			return e
	return null


static func _critters(main, check: Callable) -> void:
	# A chicken scared up: it flaps and glides off.
	var g := _farm(main)
	var critters = g.features["critters"]
	var hen := _one(g, "chicken")
	var p: Player = g.player
	p.x = hen.x - 1.2
	p.y = hen.y
	var from := Vector2(hen.x, hen.y)
	critters.scatter(p.x, p.y, 4.0, p)
	check.call(critters.gliding(hen) and hen.hop > 0.0, "a scared chicken flaps up and glides")
	var top := 0.0
	for i in 30:
		g.tick(STEP, Game.Controls.new())
		top = maxf(top, hen.hop)
	check.call(
		Vector2(hen.x, hen.y).distance_to(from) > .3 and top > .15,
		"and sails off (%.2f cells, %.2f up)" % [Vector2(hen.x, hen.y).distance_to(from), top]
	)
	# A hog's charge bowls the player over; the same twice.
	var ends: Array = []
	for k in 2:
		var farm := _farm(main)
		var crit = farm.features["critters"]
		var hog := _one(farm, "pig")
		var q: Player = farm.player
		q.x = hog.x + 2.0
		q.y = hog.y
		if farm.world.blocked(q.x, q.y, .3):
			q.x = hog.x - 2.0
		crit.charge(hog, q)
		var flat := false
		for i in 150:
			farm.tick(STEP, Game.Controls.new())
			flat = flat or q.knocked > 0.0
		check.call(
			flat and crit.knocked() == 1 and q.health < 100,
			"a charging hog knocks the player flat (%d)" % q.health
		)
		ends.append([q.x, q.y, hog.x, hog.y])
	check.call(ends[0] == ends[1], "the same charge plays the same")
	# The mule kicks whoever stands behind it, not in front.
	for behind: bool in [true, false]:
		var farm := _farm(main)
		var crit = farm.features["critters"]
		var mule := _one(farm, "mule")
		var q: Player = farm.player
		mule.angle = 0.0
		mule.heard = null
		var side := -.9 if behind else .9
		q.x = mule.x + side
		q.y = mule.y
		var kicked := false
		for i in 50:
			mule.angle = 0.0
			farm.tick(STEP, Game.Controls.new())
			kicked = kicked or q.knocked > 0.0
			q.x = mule.x + side
			q.y = mule.y
		if behind:
			check.call(
				kicked and q.health < 100, "the mule kicks whoever walks behind it (%d)" % q.health
			)
		else:
			check.call(not kicked and q.health == 100, "but not someone in front of it")
	# A cow tips at a USE beside her, lies a while and gets back up.
	var farm := _farm(main)
	var crit = farm.features["critters"]
	var cow := _one(farm, "cow")
	var q: Player = farm.player
	q.x = cow.x
	q.y = cow.y + .9
	if farm.world.blocked(q.x, q.y, .3):
		q.y = cow.y - .9
	var use := Game.Controls.new()
	use.use = true
	farm.tick(STEP, use)
	check.call(crit.lying(cow), "USE beside a cow tips her")
	for i in 90:
		farm.tick(STEP, Game.Controls.new())
	check.call(
		cow.held_cel == "cow_down" and cow.squash < 1.0, "she goes over and lies on her side"
	)
	var spot := Vector2(cow.x, cow.y)
	for i in int(60 * 9.0):
		farm.tick(STEP, Game.Controls.new())
	check.call(
		(
			not crit.lying(cow)
			and cow.held_cel == ""
			and Vector2(cow.x, cow.y).distance_to(spot) < 1.5
		),
		"then gets back on her feet"
	)
	check.call(crit.tipped() == 1, "one cow tipped")
