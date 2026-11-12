## Checks for the impacts, the marks that stay and the gun's feel
## (tools/check_fixes.gd runs them; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/feel_check.gd
##
## The ranch rifle goes through a plank baffle on the firing range and hits
## who is behind it for less, the same every time; the .38 does not, and
## nothing goes through logs. The gun's sway and kick spring back and settle;
## landing dips the view and a blow turns it away from where it came from;
## VIEW BOB and SCREEN SHAKE off leave none of it. Bullet holes keep to their
## cap, the oldest fading out first; a blast scorches the wall beside it and
## blood runs down a wall.
extends SceneTree

const DT := 1.0 / 60.0

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
	print("FEEL OK" if failures.is_empty() else "%d FEEL CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func run(main, check: Callable) -> void:
	print("\nPENETRATION (a strong round through a thin wall, by the game's rules)")
	_penetration(main, check)
	print("\nGUN AND VIEW ON SPRINGS")
	_springs(main, check)
	print("\nMARKS THAT STAY")
	_marks(main, check)


## A game on the range, a hand standing at `at`, the player at `from` facing
## `angle` with `gun` in hand.
static func _setup(main, gun: int, from: Vector2, angle: float, at: Vector2) -> Array:
	var game: Game = main.make_game("range")
	game.configure({})
	game.enemies.clear()
	var hand := Enemy.new("billy", at.x, at.y)
	hand.dormant = false
	game.enemies.append(hand)
	var p := game.player
	p.x = from.x
	p.y = from.y
	p.angle = angle
	p.pitch = 0.0
	p.eye = .95 + game.world.elevation(p.x, p.y)
	game.armory.owned[gun] = true
	game.armory.active = gun
	return [game, hand]


static func _shoot(game: Game) -> bool:
	var how: Dictionary = Weapons.FIRING[game.armory.active]
	return game.hitscan(
		game.player.view_angle(),
		0.0,
		Weapons.DAMAGE.get(game.armory.active, 0),
		float(how["range"]),
		float(how["width"])
	)


static func _penetration(main, check: Callable) -> void:
	# The rifle lane's west baffle is a cell of planks at x 20; the pellet lane
	# is behind it.
	var from := Vector2(24.5, 45.5)
	var behind := Vector2(17.5, 45.5)
	var made := _setup(main, Weapons.RIFLE, from, PI, behind)
	var game: Game = made[0]
	var hand: Enemy = made[1]
	check.call(
		Materials.of_tile(game.world, game.world.solid[45 * game.world.width + 20]) == "wood",
		"the range's baffle is planks"
	)
	var before := hand.hp
	var pierced: Array = []
	game.pierced.connect(func(_a, _b, struck): pierced.append(struck))
	var hit := _shoot(game)
	var lost := before - hand.hp
	# The same round straight into a hand this side of the baffle.
	var open := _setup(main, Weapons.RIFLE, from, PI, Vector2(22.5, 45.5))
	var near: Enemy = open[1]
	var whole_hp := near.hp
	_shoot(open[0])
	var full := float(whole_hp - near.hp)
	var part := float(Weapons.FIRING[Weapons.RIFLE].get("penetrate_damage", 1.0))
	check.call(
		hit and full > 0.0 and absf(lost - full * part) < .51,
		"a rifle round goes through the planks and hits behind for %.0f of %.0f" % [lost, full]
	)
	check.call(pierced == ["enemy"], "it says so (pierced)")
	var again: Game = _setup(main, Weapons.RIFLE, from, PI, behind)[0]
	var twin: Enemy = again.enemies[0]
	_shoot(again)
	check.call(is_equal_approx(twin.hp, hand.hp), "the same shot does the same thing again")
	made = _setup(main, Weapons.REVOLVER, from, PI, behind)
	var still: Enemy = made[1]
	var whole := still.hp
	_shoot(made[0])
	check.call(is_equal_approx(still.hp, whole), "the .38 stops in the planks")
	# The cans lane's mouth is a wall of logs at y 17.
	made = _setup(main, Weapons.RIFLE, Vector2(5.5, 19.5), -PI / 2.0, Vector2(5.5, 15.5))
	var log_hand: Enemy = made[1]
	var logged := log_hand.hp
	_shoot(made[0])
	check.call(
		(
			(
				Materials.of_tile(made[0].world, made[0].world.solid[17 * made[0].world.width + 5])
				== "timber"
			)
			and is_equal_approx(log_hand.hp, logged)
		),
		"nothing goes through logs"
	)
	check.call(
		Materials.resist("brick") == INF and Materials.resist("steel") == INF,
		"brick and steel stop every round"
	)
	check.call(
		(
			Materials.of_name("tin_lit") == "tin"
			and Materials.of_name("brick_win") == "brick"
			and Materials.of_name("window") == "glass"
			and Materials.of_name("corn") == "brush"
		),
		"tiles map to what they are made of"
	)


static func _ticks(game: Game, count: int) -> void:
	for _k in count:
		game.clock += DT
		game.ticked.emit(DT)


static func _springs(main, check: Callable) -> void:
	var game: Game = main.make_game("range")
	game.configure({})
	var p := game.player
	var feel = game.features["feel"]
	# Turn for a while, then stop: the gun trails, then settles home.
	var most := 0.0
	for _k in 20:
		game.feel_turn = .05
		_ticks(game, 1)
		most = maxf(most, absf(p.weapon_lag.x))
	game.feel_turn = 0.0
	var crossed := false
	var sign_then := signf(p.weapon_lag.x)
	for _k in 120:
		_ticks(game, 1)
		if signf(p.weapon_lag.x) == -sign_then:
			crossed = true
	check.call(most > 2.0, "the gun trails a turn (%.1f px)" % most)
	check.call(crossed, "and swings a little past home on a spring")
	check.call(p.weapon_lag.length() < .05, "then settles (%.3f px)" % p.weapon_lag.length())
	# A shot: the kick, springing back past home and settling.
	game.armory.active = Weapons.REVOLVER
	_ticks(game, 1)
	game.armory.recoil = float(Weapons.RECOIL[Weapons.REVOLVER])
	game.armory.shot_age = 0.0
	_ticks(game, 1)
	var kicked: float = feel.kick
	var low := 0.0
	for _k in 60:
		game.armory.shot_age += DT
		_ticks(game, 1)
		low = minf(low, feel.kick)
	check.call(kicked > .3, "a shot kicks the gun back (%.2f of its recoil)" % kicked)
	check.call(low < 0.0 and absf(feel.kick) < .01, "the kick overshoots and settles")
	# Landing and blows.
	p.vertical_speed = -3.0
	_ticks(game, 1)
	game.feel_landed = true
	_ticks(game, 1)
	game.feel_landed = false
	var drop := 0.0
	for _k in 10:
		_ticks(game, 1)
		drop = maxf(drop, game.view_kick.z)
	check.call(drop > .01, "landing dips the view (%.3f)" % drop)
	_ticks(game, 120)
	check.call(game.view_kick.length() < .002, "and it settles")
	var left := _blow_turn(game, PI / 2.0)
	var right := _blow_turn(game, -PI / 2.0)
	check.call(
		left * right < 0.0, "a blow turns the view away from its side (%.3f, %.3f)" % [left, right]
	)
	# VIEW BOB and SCREEN SHAKE off: none of it.
	game.configure({"bob": 0, "shake": 0})
	_ticks(game, 240)
	var calm := 0.0
	for _k in 20:
		game.feel_turn = .05
		_ticks(game, 1)
		calm = maxf(calm, p.weapon_lag.length() + game.view_kick.length())
	game.feel_turn = 0.0
	p.vertical_speed = -3.0
	_ticks(game, 1)
	game.feel_landed = true
	_ticks(game, 1)
	game.feel_landed = false
	_blow_turn(game, PI / 2.0)
	for _k in 30:
		_ticks(game, 1)
		calm = maxf(calm, p.weapon_lag.length() + game.view_kick.length())
	check.call(calm < .0001, "with VIEW BOB and SCREEN SHAKE off the view and gun stay still")


## Hit from `side` (radians off where the player looks): the view's turn soon after.
static func _blow_turn(game: Game, side: float) -> float:
	var p := game.player
	_ticks(game, 120)
	var a := p.view_angle() + side
	p.health = 100
	game.damage(12, [p.x + cos(a) * 3.0, p.y + sin(a) * 3.0], "HIT")
	var most := 0.0
	for _k in 8:
		_ticks(game, 1)
		if absf(game.view_kick.x) > absf(most):
			most = game.view_kick.x
	return most


static func _marks(main, check: Callable) -> void:
	var game: Game = main.make_game("range")
	game.configure({})
	var impacts = game.features["impacts"]
	var cap := int(Effects.DEBRIS.get("hole_cap", 64))
	for k in cap + 20:
		var m := Renderer.WallMark.new()
		m.x = 20.0
		m.y = 40.0 + k * .02
		m.z = 1.0
		m.ux = 0.0
		m.uy = 1.0
		m.image = "fx_hole_wood"
		game.wall_marks.append(m)
	_ticks(game, 20)
	var fading := 0
	for m in game.wall_marks:
		if String(m.image).contains("~"):
			fading += 1
	check.call(
		fading >= 18 and not String(game.wall_marks.back().image).contains("~"),
		"past the cap the oldest holes fade first (%d fading)" % fading
	)
	_ticks(game, 120)
	check.call(
		game.wall_marks.size() == cap, "then go, leaving the cap (%d)" % game.wall_marks.size()
	)
	game.clock += float(Effects.DEBRIS.get("hole_life", 300.0)) + 1.0
	_ticks(game, 120)
	check.call(game.wall_marks.is_empty(), "and in time every hole fades away")
	# A blast by the baffle scorches it; blood thrown at it runs down.
	game.exploded.emit(19.4, 45.5, .4, false)
	check.call(not impacts.scorches.is_empty(), "a blast beside a wall scorches it")
	game.gore_fx.spray(18.8, 45.5, 1.2, 1.0, 0.0, 40.0, false)
	_ticks(game, 1)
	var runs: Array = impacts.wall_marks().filter(
		func(m): return String(m.image).begins_with("fx_bloodrun")
	)
	check.call(not runs.is_empty(), "blood on the wall starts to run")
	_ticks(game, 240)
	check.call(
		not runs.is_empty() and String(runs[0].image) == "fx_bloodrun_5",
		"and has run its length a few seconds on"
	)
	game.configure({"bullet_marks": 0})
	check.call(impacts.ground_marks().is_empty(), "BULLET MARKS off: no pocks or scorches drawn")
	game.configure({})
	for k in 60:
		game.exploded.emit(19.4, 30.0 + k * .3, .4, false)
	_ticks(game, 200)
	check.call(
		impacts.scorches.size() <= int(Effects.DEBRIS.get("wall_scorch_cap", 10)),
		"wall scorches keep to their cap (%d)" % impacts.scorches.size()
	)
	var debris = game.features["debris"]
	check.call(
		debris.scorches.size() <= int(Effects.DEBRIS.get("scorch_cap", 24)),
		"ground scorches keep to theirs (%d)" % debris.scorches.size()
	)
