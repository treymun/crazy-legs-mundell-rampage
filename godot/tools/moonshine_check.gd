## The Moonshine Run (chapter 7, content pass 8): the chapter in the campaign
## and its gate, its stations, the stock car's MOONSHINE RUN driven through
## both roadblocks (the barricades rammed, the agents woken), the patrol
## cruisers on the blacktop and the radio that stops them, the agents' radio
## call and the gas man's tear gas, the Revenue Man's fight (his burst, his
## axe charge into the rock, his shades, the still blowing and the roof
## coming down), and old saves and unlock files at the Mothership.
##
##   godot --headless --path godot --script res://tools/moonshine_check.gd
##
## Prints MOONSHINE CHECK OK.
extends SceneTree

const STEP := 1.0 / 60.0
const VehiclesScript := preload("res://src/features/vehicles.gd")
const RunsScript := preload("res://src/features/vehicle_runs.gd")
const ArenasScript := preload("res://src/features/boss_arenas.gd")
const ShackScript := preload("res://src/features/trophy_shack.gd")
## The run's way: out of the barn, over the bridge through the barricades on
## its south half, round the church curve, east on the blacktop, up its east
## leg, west on its north leg and up through the checkpoint's barricades.
const WAY := [
	Vector2(33.5, 77.0),
	Vector2(40.5, 78.0),
	Vector2(48.5, 78.2),
	Vector2(60.0, 77.5),
	Vector2(65.5, 73.0),
	Vector2(65.5, 62.0),
	Vector2(69.0, 58.0),
	Vector2(100.0, 58.0),
	Vector2(105.5, 54.0),
	Vector2(105.5, 41.0),
	Vector2(101.0, 37.6),
	Vector2(95.2, 37.6),
	Vector2(95.2, 33.5),
	Vector2(95.2, 28.5),
]

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	print("THE CAMPAIGN")
	_campaign(main)
	print("\nTHE CHAPTER")
	_chapter(main)
	print("\nTHE MOONSHINE RUN")
	_moonshine_run(main)
	print("\nTHE PATROL AND THE RADIO")
	_patrol(main)
	print("\nTHE REVENUE MEN")
	_hands(main)
	print("\nTHE REVENUE MAN")
	_boss(main)
	print("\nOLD SAVES")
	_saves()
	print(
		(
			"\n%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print(
		(
			"MOONSHINE CHECK OK"
			if failures.is_empty()
			else "%d MOONSHINE CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main: Control, alone := false) -> Game:
	var g: Game = main.make_game("moonshine")
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.barks.enabled = false
	if alone:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


func _tick(g: Game, n: int, c := Game.Controls.new()) -> void:
	for t in n:
		g.tick(STEP, c)


func _station(g: Game, id: String) -> LevelData.Station:
	for st: LevelData.Station in g.world.stations:
		if st.id == id:
			return st
	return null


func _use(g: Game, id: String) -> void:
	var st := _station(g, id)
	var p := g.player
	p.x = st.x + .9
	p.y = st.y
	p.angle = PI
	p.eye = g.world.stand(p) + .95
	g.interact()


func _enemy(g: Game, id: String) -> Enemy:
	for i in g.enemies.size():
		if str(g.enemy_ids[i]) == id:
			return g.enemies[i]
	return null


# ------------------------------------------------------------------ campaign


func _campaign(main: Control) -> void:
	var at := Campaign.ORDER.find("moonshine")
	_check(
		at > 0 and Campaign.ORDER[at - 1] == "speedway" and Campaign.ORDER[at + 1] == "mothership",
		"between the speedway and the Mothership"
	)
	_check(Campaign.GATE_LABELS.get("moonshine", "") != "", "its gate has a label")
	_check(Campaign.score_of("moonshine") == "moonshine_score", "its own score")
	_check(Sound.BOSSES.get("moonshine_score", "") == "boss_moonshine", "and boss loop")
	var hub: Game = main.make_game("hub")
	var gate := false
	for g: LevelData.Gate in hub.world.hub_gates:
		gate = gate or g.destination == "moonshine"
	_check(gate, "a gate at the County Crossroads")
	_check(Assets.CHAPTER_KINDS.get("moonshine", []).has("revenue_man"), "its pack has its hands")
	_check(Assets.chapter_of("boss_revenue_man_intro") == "moonshine", "and its boss's lines")
	_check(GunFinder.CHAPTER_GUNS.has("moonshine"), "the gun finder knows its guns")
	_check(BossRematch.BOSSES.has("revenue_man"), "the Revenue Man is in BOSS REMATCH")
	_check(
		(
			ShackScript.PLINTH_KINDS.size() == ShackScript.PLINTHS.size()
			and ShackScript.PLINTH_KINDS.has("revenue_man")
		),
		"and has his plinth in the trophy shack"
	)
	for kind: String in BossRematch.BOSSES:
		_check(ShackScript.PLINTH_KINDS.has(kind), "%s has a plinth" % kind)


# ------------------------------------------------------------------ chapter


func _chapter(main: Control) -> void:
	var g := _game(main)
	for id: String in ["trunk", "radio", "bell", "cave"]:
		_check(_station(g, id) != null, "station " + id)
	_check(_station(g, "cave").requires.size() == 3, "the cave waits on the other three")
	var shut := 0
	for d: LevelData.Door in g.world.doors:
		if d.id.begins_with("barn-door") and d.progress == 0.0:
			shut += 1
	_check(shut == 4, "the barn doors are shut till the shine is loaded")
	_use(g, "trunk")
	_check(g.stations_done.has("trunk"), "the shine loads")
	_tick(g, 90)
	var open := 0
	for d: LevelData.Door in g.world.doors:
		if d.id.begins_with("barn-door") and d.progress >= 1.0:
			open += 1
	_check(open == 4, "and the barn doors open")
	_check(
		str(g.level.vehicle_lines.get("car", "")).contains("GRANNY"),
		"the car's own line in the barn"
	)
	_check(g.finale != null and g.finale.kind == "revenue_man", "the Revenue Man is its boss")


# ---------------------------------------------------------------- the run


func _pilot(g: Game, points: Array, most: int, done: Callable) -> int:
	var k := 0
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	var stuck := 0
	var backing := 0
	for t in most:
		if done.call():
			return t
		var aim: Vector2 = points[k]
		if Vector2(v.x, v.y).distance_to(aim) < maxf(1.6, VehicleDrive.speed(v) * .22):
			k += 1
			if k >= points.size():
				return t
			aim = points[k]
		var p := g.player
		p.angle = atan2(aim.y - v.y, aim.x - v.x)
		var off := absf(wrapf(p.angle - v.h, -PI, PI))
		var c := Game.Controls.new()
		c.forward = 1.0 if off < .6 else .45
		var next_k := mini(k + 1, points.size() - 1)
		var after: Vector2 = points[next_k]
		var bend := absf(wrapf((after - aim).angle() - (aim - Vector2(v.x, v.y)).angle(), -PI, PI))
		var fast := VehicleDrive.speed(v)
		var safe := clampf(13.0 - bend * 9.0, 3.5, 13.0)
		if Vector2(v.x, v.y).distance_to(aim) < fast * .9 and fast > safe:
			c.forward = -.6
		stuck = stuck + 1 if fast < .4 else 0
		if stuck > 40:
			backing = 30
			stuck = 0
		if backing > 0:
			backing -= 1
			p.angle = v.h
			c.forward = -1.0
		if OS.get_environment("PILOT_TRACE") != "" and t % 60 == 0:
			print("    t=%d (%.1f, %.1f) v %.1f hp %.0f wp %d" % [t, v.x, v.y, fast, v.hp, k])
		g.tick(STEP, c)
	return most


func _moonshine_run(main: Control) -> void:
	var g := _game(main)
	var runs: RunsScript = g.features.get("vehicle_runs")
	var rides: VehiclesScript = g.features.get("vehicles")
	_check(runs.defs.size() == 1, "the chapter has its run")
	_use(g, "trunk")
	_tick(g, 90)
	var agents: Array = []
	for i in g.enemies.size():
		if str(g.enemy_ids[i]).begins_with("run-"):
			agents.append(g.enemies[i])
	_check(
		agents.size() == 5 and agents.all(func(e: Enemy) -> bool: return e.dormant),
		"the run's agents wait in the woods (%d)" % agents.size()
	)
	var barricades := _barricades(g)
	_check(barricades == 4, "four barricades stand across the roads (%d)" % barricades)
	_check(rides.seat_in(g.player, 0), "into Granny's runner")
	var running := func() -> bool: return runs.state_of("moonshine_run") == RunsScript.RUNNING
	_pilot(g, WAY.slice(0, 2), 600, running)
	_check(running.call(), "out of the barn doors, the run starts")
	_tick(g, 2)
	_check(agents.all(func(e: Enemy) -> bool: return not e.dormant), "the agents come out")
	var done := func() -> bool: return runs.state_of("moonshine_run") == RunsScript.DONE
	var took := _pilot(g, WAY, 60 * 120, done)
	var v: VehicleDrive.Ride = rides.rides[0]
	_check(
		done.call(),
		(
			"driven through both roadblocks, the run is made (%.1f s of %.0f; at %.1f, %.1f)"
			% [took * STEP, runs.limit[0], v.x, v.y]
		)
	)
	_check(_barricades(g) == 0, "every barricade rammed to kindling (%d left)" % _barricades(g))
	_check(v.hp > 0.0, "the car came through (%.0f of %.0f)" % [v.hp, 320.0])
	var rows := Features.tally_rows(g)
	var shown := false
	for row: Array in rows:
		shown = shown or str(row[0]) == "THE MOONSHINE RUN"
	_check(shown, "the tally shows its time")
	# On foot the checkpoint lets a man by at the gap: the way north is open
	# with the barricades standing (no car).
	var foot := _game(main, true)
	_use(foot, "trunk")
	_use(foot, "radio")
	_use(foot, "bell")
	_tick(foot, 120)
	var target := Vector2(_station(foot, "cave").x, _station(foot, "cave").y)
	var p := foot.player
	p.x = 93.5
	p.y = 37.5
	p.eye = foot.world.stand(p) + .95
	var way: Array = foot.objective_route(target)
	_check(int(way[1]) > 0, "on foot past the barricades to the cave (%d steps)" % int(way[1]))
	p.x = 36.5
	p.y = 77.5
	p.eye = foot.world.stand(p) + .95
	way = foot.objective_route(target)
	_check(int(way[1]) > 0, "and from the bridge (%d steps)" % int(way[1]))


func _barricades(g: Game) -> int:
	var breaks: GameFeature = g.features.get("breakables")
	var standing := 0
	for piece: Variant in breaks.get("pieces"):
		if str(piece.image) == "town_sawhorse" and not piece.broken:
			standing += 1
	return standing


# ------------------------------------------------------------- the patrol


func _patrol(main: Control) -> void:
	var g := _game(main, true)
	var laps: GameFeature = g.features.get("race_laps")
	var cars: Array = laps.get("cars")
	_check(cars.size() == 2, "two cruisers patrol the blacktop")
	var sprites: Array = laps.call("sprites")
	g.player.x = 60.0
	g.player.y = 58.0
	var seen := false
	for k in 600:
		g.tick(STEP, Game.Controls.new())
		for spr: View.Sprite in laps.call("sprites"):
			seen = seen or spr.image == "town_cruiser"
	_check(seen and sprites != null, "drawn as the cruiser")
	var first: Array = laps.call("_at", float(cars[0][0]))
	var near: Vector2 = first[0]
	g.player.x = near.x
	g.player.y = near.y + 3.0
	var colours := {}
	for k in 30:
		g.clock += .05
		for l: Array in laps.call("lights", g.player):
			var c: Color = l[4]
			colours[c.to_html()] = true
	_check(colours.size() >= 2, "their light bars flash red and blue (%d)" % colours.size())
	var p := g.player
	g.cheats.god = false
	p.health = 100
	var hurt := [0.0]
	g.events.player_hurt.connect(func(amount: float, _cause: String): hurt[0] += amount)
	var where: Array = laps.call("_at", float(cars[0][0]) + 4.0)
	var at: Vector2 = where[0]
	p.x = at.x
	p.y = at.y
	_tick(g, 60)
	_check(hurt[0] > 0.0, "one runs down a man on the blacktop")
	_use(g, "radio")
	_check(bool(laps.get("dry")), "the radio cut, they pull over")
	_tick(g, 240)
	var moving := false
	for car: Array in cars:
		moving = moving or float(car[1]) > 0.0
	_check(not moving, "and stop")
	var rides: VehiclesScript = g.features.get("vehicles")
	_check(rides.line.is_empty(), "no lap timer on their beat")


# --------------------------------------------------------------- the hands


func _hands(main: Control) -> void:
	var g := _game(main)
	var agent := _enemy(g, "knob-a")
	agent.attacks = 2
	agent.wake(g, g.player.x, g.player.y)
	var before := 0
	for e: Enemy in g.enemies:
		if e.alerted:
			before += 1
	g.player.x = agent.x + 3.0
	g.player.y = agent.y
	var called := MoonshineHands.attack(agent, g, 0.0, 3.0, 1.0, null)
	var after := 0
	for e: Enemy in g.enemies:
		if e.alerted:
			after += 1
	_check(called and after > before, "an agent radios it in (%d up to %d)" % [before, after])
	_use(g, "radio")
	agent.attacks = 6
	_check(not MoonshineHands.attack(agent, g, 0.0, 3.0, 1.0, null), "not once the radio is cut")
	var gas := _enemy(g, "camp-d")
	var shots := g.shots.size()
	g.player.x = gas.x + 4.0
	g.player.y = gas.y
	g.player.eye = g.world.stand(g.player) + .95
	gas.wake(g, g.player.x, g.player.y)
	EnemyAttacks.attack(gas, g, 0.0, 4.0, g.world.stand(gas) + 1.2, null)
	var lobbed: bool = g.shots.size() > shots and str(g.shots.back().kind) == "tear_gas"
	_check(lobbed, "the gas man lobs tear gas")
	var hazards := g.hazards.size()
	_tick(g, 120)
	_check(g.hazards.size() > hazards, "it leaves a cloud where it lands")
	_check(g.hazard_cause(g.hazards.back()) == "TEAR GAS", "called TEAR GAS")


# ---------------------------------------------------------------- the boss


func _boss(main: Control) -> void:
	var g := _game(main)
	var boss := _enemy(g, "cave-revenue-man")
	_check(boss != null and Enemy.BOSS_TITLES.has("revenue_man"), "the Revenue Man is a boss")
	# His burst: the tommy gun's rounds fly.
	boss.dormant = false
	boss.wake(g, boss.x + 4.0, boss.y)
	g.player.x = boss.x - 4.0
	g.player.y = boss.y
	g.player.eye = g.world.stand(g.player) + .95
	boss.attacks = 1
	var shots := g.shots.size()
	MoonshineHands.attack(boss, g, PI, 4.0, g.world.stand(boss) + 1.3, null)
	_check(boss.volley >= 6, "TOMMY GUN: a burst of %d" % boss.volley)
	for k in 40:
		boss.tick(STEP, g)
	_check(g.shots.size() >= shots + 5, "its rounds fly (%d)" % (g.shots.size() - shots))
	# His axe charge, into the rock.
	boss.attacks = 3
	boss.angle = 0.0
	RevenueManMoves.charge(boss, g, PI * .5)
	_check(boss.has_meta("charge"), "AXE CHARGE: he runs")
	var stuck := false
	for k in 120:
		boss.tick(STEP, g)
		stuck = stuck or boss.has_meta("stuck")
	_check(stuck, "into the rock, and the axe sticks")
	# The shades: front and high counts double, from behind not.
	var moves := BossKit.moves("revenue_man")
	boss.remove_meta("stuck")
	boss.angle = 0.0
	var top := g.world.stand(boss) + boss.height * .9
	var front: float = moves.weak_spot(
		boss, g, Vector3(boss.x + .3, boss.y, top), Vector2(boss.x + 4.0, boss.y), "shotgun"
	)
	var back: float = moves.weak_spot(
		boss, g, Vector3(boss.x - .3, boss.y, top), Vector2(boss.x - 4.0, boss.y), "shotgun"
	)
	_check(
		front > 1.0 and back == 1.0, "his shades are the weak spot (%.1f / %.1f)" % [front, back]
	)
	# Phase 3: the still blows and the roof comes down.
	var arenas: ArenasScript = g.features.get("boss_arenas")
	_check(arenas != null and arenas.boss == boss, "the cave is his arena")
	var blasts := 0
	g.events.exploded.connect(func(_a = null, _b = null, _c = null, _d = null): blasts += 1)
	boss.hp = boss.max_hp * .15
	boss.boss_phase = 3
	moves.phase_changed(boss, g, 3)
	_check(arenas.third(), "the third phase turns the cave")
	g.player.x = 116.5
	g.player.y = 9.5
	g.player.eye = g.world.stand(g.player) + .95
	var rocks := 0
	for k in 60 * 8:
		g.tick(STEP, Game.Controls.new())
		for d: Array in arenas.drops:
			rocks = maxi(rocks, 1 if str(d[0]) == "rock" else 0)
	_check(arenas.rocks_down >= 2, "the roof comes down (%d rocks)" % arenas.rocks_down)
	_check(not arenas.slicks.is_empty() or arenas.burn_next > 0.0, "the shine burns")


# ---------------------------------------------------------------- saves


func _saves() -> void:
	var doc := {
		"version": 8,
		"level": "mothership",
		"campaign":
		{
			"history":
			[
				["hickston", 1, 2, 0, 1, 60],
				["fair", 1, 2, 0, 1, 60],
				["sawmill", 1, 2, 0, 1, 60],
				["quarry", 1, 2, 0, 1, 60],
				["bayou", 1, 2, 0, 1, 60],
				["speedway", 1, 2, 0, 1, 60]
			],
			"replay": false
		}
	}
	var up: Variant = SaveUpgrade.upgrade(doc)
	_check(up is Dictionary and int(up["version"]) == SessionStore.VERSION, "a v8 save comes up")
	var history: Array = up["campaign"]["history"] if up is Dictionary else []
	_check(
		(
			history.size() == Campaign.ORDER.find("mothership")
			and str(history[Campaign.ORDER.find("moonshine")][0]) == "moonshine"
		),
		"at the Mothership, the run is put in its history (%d rows)" % history.size()
	)
	var early := {
		"version": 8,
		"level": "bayou",
		"campaign": {"history": [["hickston", 1, 2, 0, 1, 60]], "replay": false}
	}
	var early_up: Dictionary = SaveUpgrade.upgrade(early)
	_check(early_up["campaign"]["history"].size() == 1, "a save before it is left alone")
	var path := OS.get_cache_dir().path_join("moonshine_unlocks.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(
		JSON.stringify(["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"])
	)
	f.close()
	var opened := SessionStore.unlocks(path)
	_check(
		opened.has("moonshine") and opened.has("mothership"),
		"an old unlocks file with the Mothership open opens the run too"
	)
	DirAccess.remove_absolute(path)
