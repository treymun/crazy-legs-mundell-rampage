## The RAMPAGE meter (pass 15, features/rampage.gd; hits.cfg [rampage]):
##
## - a kill of the player's own fills it by `kill`, one by another hand
##   does not; a head, an overkill, a brawl finisher, a boss and a hazard
##   kill add their share; a chain of kills adds its links;
## - it holds `hold` seconds after a kill, then drains `drain` a second;
## - full, RAMPAGE: his hits do `damage` times as much and he moves `speed`
##   times as far; a kill in it keeps it going `extend` longer (to
##   `rampage_most` in all); over after `rampage_for`, the meter empty again;
## - co-op: each player his own; County Run on; off in deathmatch, team
##   deathmatch, the 5v5, the hub and the range;
## - a snapshot carries it (both games play on alike), a save through its
##   JSON keeps it, an older save holds none;
## - the balance bot with a meter near full plays the same twice (the RAMPAGE
##   in it the same).
##
##   godot --headless --path godot --script res://tools/rampage_check.gd
##
## Prints RAMPAGE CHECK OK (check_all runs it).
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const STEP := 1.0 / 60.0
const NEAR := .0001

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	_fills()
	_drains()
	_boost()
	_speed()
	_coop()
	_where()
	_carried()
	_saved()
	_same()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("RAMPAGE CHECK OK")
	else:
		print("RAMPAGE CHECK FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


func _made(id := "hickston") -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": 0})
	g.lessons = false
	g.cheats.god = true
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	DirectorData.ON = false
	_ticks(g, 2)
	DirectorData.ON = true
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


func _r(g: Game) -> Rampage:
	return g.features.get("rampage")


## A fresh hand of `kind` standing by the player, awake.
func _hand(g: Game, kind := "billy", ahead := 3.0) -> Enemy:
	var p := g.player
	var e := Enemy.new(kind, p.x + ahead, p.y, PI)
	e.uid = g.take_uid()
	e.dormant = false
	e.alerted = true
	e.floor_z = g.world.elevation(e.x, e.y)
	g.enemies.append(e)
	return e


## `p` kills a fresh hand with a plain body hit (the real path: Enemy.hurt),
## a small last blow on a hand nearly gone (no overkill).
func _kill(g: Game, p: Player, kind := "billy") -> Enemy:
	var e := _hand(g, kind)
	e.hp = 5.0
	g.focus(p)
	g.hit_point = Vector3.INF
	e.hurt(10.0, g)
	g.focus(g.local_player)
	return e


func _meter(g: Game, slot := 0) -> float:
	var r := _r(g)
	return float(r.meters[slot]) if slot < r.meters.size() else 0.0


func _fills() -> void:
	print("\nKILLS FILL IT")
	var g := _made()
	var r := _r(g)
	check(r != null and r.on, "it runs in a campaign chapter")
	var p := g.player
	_kill(g, p)
	check(absf(_meter(g) - Rampage.KILL) < NEAR, "a kill fills it by `kill` (%.3f)" % _meter(g))
	# By another hand: no.
	var other := _hand(g, "billy", 5.0)
	var victim := _hand(g)
	victim.hurt(victim.hp + 500.0, g, false, false, other)
	check(
		not victim.alive and absf(_meter(g) - Rampage.KILL) < NEAR,
		"a hand killed by another hand fills nothing"
	)
	# Within chain_for: one link more each.
	_ticks(g, 30)
	_kill(g, p)
	var want := Rampage.KILL * 2.0 + Rampage.CHAIN
	check(absf(_meter(g) - want) < NEAR, "a second kill in the chain adds a link (%.3f)" % want)
	# The extras, through the feature's own path (as hit_landed then enemy_killed).
	var g2 := _made()
	var r2 := _r(g2)
	var cases := [
		["head", Rampage.KILL + Rampage.HEAD],
		["overkill", Rampage.KILL + Rampage.OVERKILL],
		["boss", Rampage.KILL + Rampage.BOSS],
	]
	for row: Array in cases:
		r2.meters = []
		r2.until = []
		r2.last_kill = []
		r2.links = []
		r2.holds = []
		r2.began = []
		r2.count = []
		var boss_kind: String = Enemy.BOSS_TITLES.keys()[0]
		var e := _hand(g2, boss_kind if row[0] == "boss" else "billy")
		e.hp = 0.0
		e.last_zone = "head" if row[0] == "head" else "body"
		e.explosive = row[0] == "overkill"
		g2.events.hit_landed.emit(10.0, true)
		g2.events.enemy_killed.emit(e)
		var wanted: float = row[1]
		check(
			absf(_meter(g2) - wanted) < NEAR, "a %s kill adds its share (%.2f)" % [row[0], wanted]
		)
	# A brawl finisher landing (its move started a wind-up ago).
	r2.meters = [0.0]
	r2.last_kill = [-100.0]
	r2.links = [0]
	var brawl: Object = g2.features.get("brawl")
	var moves: Dictionary = brawl.get("last_moves")
	moves[0] = ["head_off", g2.clock - Rampage.WIND]
	var f := _hand(g2)
	f.hp = 0.0
	g2.events.hit_landed.emit(10.0, true)
	g2.events.enemy_killed.emit(f)
	check(
		absf(_meter(g2) - Rampage.KILL - Rampage.FINISHER) < NEAR,
		"a brawl finisher adds `finisher` (%.2f)" % _meter(g2)
	)
	moves.erase(0)
	# A hazard kill: its bonus on top.
	var before := _meter(g2)
	g2.events.hazard_killed.emit(f, "saw", 0)
	check(
		absf(_meter(g2) - before - Rampage.HAZARD) < NEAR,
		"a hazard kill adds [hazard] bonus_rampage (%.2f)" % Rampage.HAZARD
	)


func _drains() -> void:
	print("\nIT HOLDS, THEN DRAINS")
	var g := _made()
	_kill(g, g.player)
	_kill(g, g.player)
	var full := _meter(g)
	_ticks(g, roundi((Rampage.HOLD - .2) / STEP))
	check(absf(_meter(g) - full) < NEAR, "held for `hold` (%.1f s)" % Rampage.HOLD)
	_ticks(g, roundi(1.2 / STEP))
	var drop := full - _meter(g)
	check(
		drop > Rampage.DRAIN * .8 and drop < Rampage.DRAIN * 1.2,
		"then drains `drain` a second (%.3f in about a second)" % drop
	)
	_ticks(g, roundi(full / Rampage.DRAIN / STEP) + 60)
	check(_meter(g) == 0.0, "down to nothing")


## Kills until the meter is full.
func _fill(g: Game, p: Player) -> int:
	var n := 0
	while not Rampage.raging(g, p) and n < 40:
		_kill(g, p)
		n += 1
	return n


func _boost() -> void:
	print("\nFULL: RAMPAGE")
	var g := _made()
	var p := g.player
	var calm := _hand(g, "big_billy")
	g.focus(p)
	g.hit_point = Vector3.INF
	var hp := calm.hp
	calm.hurt(10.0, g)
	var plain := hp - calm.hp
	var n := _fill(g, p)
	check(Rampage.raging(g, p), "%d kills in a row fill it: RAMPAGE" % n)
	check(_r(g).count[0] == 1, "counted once")
	check(
		Rampage.pace(g, p) == Rampage.SPEED, "he moves `speed` times as fast (%.2f)" % Rampage.SPEED
	)
	var hot := _hand(g, "big_billy")
	g.focus(p)
	g.hit_point = Vector3.INF
	hp = hot.hp
	hot.hurt(10.0, g)
	var raged := hp - hot.hp
	check(
		absf(raged - plain * Rampage.DAMAGE) < .01,
		"his hits do `damage` times as much (%.1f against %.1f)" % [raged, plain]
	)
	var other := _hand(g, "big_billy", 5.0)
	hp = hot.hp
	hot.hurt(10.0, g, false, false, other)
	check(absf(hp - hot.hp - 10.0) < .01, "a hand's blow on a hand is as ever")
	var r := _r(g)
	var end: float = r.until[0]
	_kill(g, p)
	check(absf(float(r.until[0]) - end - Rampage.EXTEND) < NEAR, "a kill in it adds `extend`")
	for i in 40:
		_kill(g, p)
	check(
		float(r.until[0]) <= float(r.began[0]) + Rampage.MOST + NEAR,
		"never past `rampage_most` (%.1f s)" % Rampage.MOST
	)
	var n2 := 0
	while g.clock < float(r.until[0]) + .05 and n2 < 3600:
		_ticks(g, 1)
		n2 += 1
	_ticks(g, 2)
	check(not Rampage.raging(g, p) and _meter(g) == 0.0, "over: the meter is empty again")
	check(Rampage.pace(g, p) == 1.0 and Rampage.might(g, null) == 1.0, "and the boost is gone")


## How far the player runs straight ahead in a second.
func _run_for(raging: bool) -> float:
	var g := _made()
	if raging:
		_fill(g, g.player)
	# Past a finishing shot's slow motion and the hitstop (they hold the world).
	while g.slowmo > 0.0 or g.hitstop > 0.0:
		_ticks(g, 1)
	var p := g.player
	var from := Vector2(p.x, p.y)
	for i in 60:
		var c := Game.Controls.new()
		c.forward = 1.0
		c.running = true
		g.tick(STEP, c)
	return from.distance_to(Vector2(p.x, p.y))


func _speed() -> void:
	print("\nHE MOVES FASTER")
	var plain := _run_for(false)
	var raged := _run_for(true)
	var ratio := raged / maxf(.001, plain)
	check(
		plain > 1.0 and absf(ratio - Rampage.SPEED) < .02,
		"a second's run: %.2f cells against %.2f (x%.3f)" % [raged, plain, ratio]
	)


func _coop() -> void:
	print("\nCO-OP: EACH HIS OWN")
	var g := _made()
	Modes.setup(g, Modes.COOP, 2)
	_ticks(g, 2)
	var two := g.players[1]
	_kill(g, two)
	check(_meter(g, 1) > 0.0 and _meter(g, 0) == 0.0, "player two's kill is his own")
	_fill(g, two)
	check(
		Rampage.raging(g, two) and not Rampage.raging(g, g.players[0]), "his RAMPAGE is his alone"
	)
	check(g.player == g.local_player, "the local player is left acting")


func _where() -> void:
	print("\nWHERE IT RUNS")
	var cases := [
		["hickston", Modes.DEATHMATCH, 2, false],
		["hickston", Modes.TEAM, 2, false],
		["county_hickston", Modes.COUNTY, 1, true],
		["hub", "", 1, false],
		["range", "", 1, false],
	]
	for row: Array in cases:
		var g: Game = main.make_game(str(row[0]))
		g.configure({"difficulty": 1, "events": 0})
		if str(row[1]) != "":
			Modes.setup(g, str(row[1]), int(row[2]))
		# (The front end marks the Crossroads so as it opens it: main_flow.gd.)
		g.in_hub = row[0] == "hub"
		_ticks(g, 3)
		var on := Rampage.of(g) != null
		check(on == bool(row[3]), "%s %s: %s" % [row[0], row[1], "on" if row[3] else "off"])
	var showdown: Game = main.make_game("grainyard")
	showdown.configure({"difficulty": 1, "events": 0})
	Modes.setup(showdown, Modes.BOMB, 2)
	_ticks(showdown, 3)
	check(Rampage.of(showdown) == null, "off in the 5v5")


func _raging_game() -> Game:
	var g := _made()
	_fill(g, g.player)
	_ticks(g, 30)
	return g


func _carried() -> void:
	print("\nCARRIED ONLINE")
	var a := _raging_game()
	var b: Game = main.make_game("hickston")
	b.configure({"difficulty": 1, "events": 0})
	b.lessons = false
	b.cheats.god = true
	var snap := GameSnapshot.capture(a)
	check(GameSnapshot.apply(b, snap), "a snapshot mid-RAMPAGE goes on another game")
	check(Rampage.raging(b, b.player) and _r(b).until == _r(a).until, "the RAMPAGE came with it")
	for i in 120:
		a.tick(STEP, Game.Controls.new())
		b.tick(STEP, Game.Controls.new())
	check(GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)), "both play on alike")


func _saved() -> void:
	print("\nSAVED")
	var g := _raging_game()
	var text := JSON.stringify(SessionStore.snapshot(g))
	var parsed: Variant = JSON.parse_string(text)
	var doc: Dictionary = parsed
	var back: Game = SessionStore.restore(doc.duplicate(true), main.make_game)
	check(back != null, "a save mid-RAMPAGE loads")
	if back != null:
		var r := _r(back)
		var was := _r(g)
		var same := r.meters.size() == was.meters.size()
		for i in mini(r.meters.size(), was.meters.size()):
			same = (
				same
				and absf(float(r.meters[i]) - float(was.meters[i])) < NEAR
				and absf(float(r.until[i]) - float(was.until[i])) < NEAR
				and int(r.count[i]) == int(was.count[i])
			)
		check(same, "the meter and the RAMPAGE come back")
		_ticks(back, 2)
		check(Rampage.raging(back, back.player), "and it runs on")
	var features: Dictionary = doc.get("features", {})
	features.erase("rampage")
	var old: Game = SessionStore.restore(doc, main.make_game)
	check(old != null, "an older save (none in it) loads")
	if old != null:
		_ticks(old, 2)
		check(_meter(old) == 0.0 and not Rampage.raging(old, old.player), "with an empty meter")


## The bot plays a minute with its meter near full from the start.
func _play(seed_value: int) -> Game:
	var g := _made()
	g.rng = GameState.Rng.new(seed_value)
	var r := _r(g)
	r._grow(0)
	r.meters[0] = .9
	r.holds[0] = 1e9
	var pilot := Pilot.new(1, seed_value)
	while g.clock < 60.0 and g.player.health > 0:
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
	return g


func _same() -> void:
	print("\nTHE SAME EVERY TIME")
	var a := _play(11)
	var b := _play(11)
	check(int(_r(a).count[0]) >= 1, "the bot went on a RAMPAGE (%d)" % int(_r(a).count[0]))
	check(
		GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)), "two plays end alike"
	)
