## The barred doors (pass 15's loops: a door with "bar_side" in a level, the
## short way back opened from the far end; docs/dev/levels.md, gameplay.md;
## tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/bar_door_check.gd
##
## Every chapter's barred doors: hung in a wall with open floor both sides,
## LevelLoad reads the side; from the wrong side USE says BARRED, a running
## boot does not open it, the hands do not kick it, the bots go round, and the
## pin's way (a doors-open walk) never goes through it that way; from the
## bar's side USE boots it open (the boot lands, the bar busts) and it stays
## open (no USE to close it), the way through both ways after. Every station,
## key and the exit is reached from the start with every barred door left
## shut (they are never the only way), and two runs the same.
extends SceneTree

const STEP := 1.0 / 60.0
const Pilot := preload("res://tools/bot_pilot.gd")
## The chapters that have one (tools/levels/*_plan.gd loops).
const WANT := {"hickston": ["rodeo-back-gate"]}

var failures: Array = []
var passes := 0
var main


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	DirectorData.ON = false
	HoundLead.ON = false
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("LEVEL LOADING")
	_check(LevelLoad.bar_side("n", false) == -1 and LevelLoad.bar_side("s", false) == 1, "n and s")
	_check(LevelLoad.bar_side("w", true) == -1 and LevelLoad.bar_side("e", true) == 1, "w and e")
	_check(LevelLoad.bar_side("e", false) == 0 and LevelLoad.bar_side("", true) == 0, "no side")
	for id: String in Campaign.ORDER:
		var g := _game(id)
		var bars := _bars(g)
		var want: Array = WANT.get(id, [])
		var names: Array = []
		for door: LevelData.Door in bars:
			names.append(door.id)
		names.sort()
		_check(names == want, "%s: barred doors %s" % [id, names])
		for door: LevelData.Door in bars:
			print("\n%s %s" % [id.to_upper(), door.id])
			_door(id, door.id)
		if not bars.is_empty():
			_needed(id)
	print("\n%d checks" % (passes + failures.size()))
	print(
		(
			"BAR DOOR CHECK OK"
			if failures.is_empty()
			else "%d BAR DOOR CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "hound": 0})
	g.cheats.god = true
	g.lessons = false
	for e: Enemy in g.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			e.dormant = true
	g.tick(STEP, Game.Controls.new())
	return g


func _bars(g: Game) -> Array:
	var out: Array = []
	for door: LevelData.Door in g.world.doors:
		if door.bar_side != 0:
			out.append(door)
	return out


func _find(g: Game, name: String) -> LevelData.Door:
	for door: LevelData.Door in g.world.doors:
		if door.id == name:
			return door
	return null


## The open cell beside `door` on side `side` (1: its bar's side, -1 not).
func _beside(door: LevelData.Door, side: int) -> Vector2:
	var s := door.bar_side * side
	if door.vertical:
		return Vector2(door.x + .5 + s, door.y + .5)
	return Vector2(door.x + .5, door.y + .5 + s)


## Stands the player at `at` facing the door.
func _face(g: Game, door: LevelData.Door, at: Vector2) -> void:
	var c := door.center()
	Modes.place(g, g.player, at.x, at.y, atan2(c.y - at.y, c.x - at.x))


func _door(id: String, name: String) -> void:
	var g := _game(id)
	var door := _find(g, name)
	var w := g.world
	var inner := _beside(door, 1)
	var outer := _beside(door, -1)
	var jamb_a := Vector2i(door.x, door.y - 1) if door.vertical else Vector2i(door.x - 1, door.y)
	var jamb_b := Vector2i(door.x, door.y + 1) if door.vertical else Vector2i(door.x + 1, door.y)
	_check(
		(
			w.solid[jamb_a.y * w.width + jamb_a.x] >= 0
			and w.solid[jamb_b.y * w.width + jamb_b.x] >= 0
			and not w.blocked(inner.x, inner.y, .2)
			and not w.blocked(outer.x, outer.y, .2)
		),
		"hung in a wall, open floor both sides"
	)
	_check(
		door.barred_from(outer.x, outer.y) and not door.barred_from(inner.x, inner.y), "its sides"
	)
	# The pin's way: through it only from the bar's side.
	_check(_way(g, inner, outer) == 2, "a walk to the far side from the bar's side goes through it")
	_check(
		_way(g, outer, inner) > 2,
		"a walk from the other side never does (%d)" % _way(g, outer, inner)
	)
	# The wrong side: USE, a running boot, a hand, a bot.
	_face(g, door, outer)
	_check(g.use_prompt() == "BARRED FROM THE OTHER SIDE", "the prompt from the wrong side")
	g.interact()
	var said: String = g.notice
	_ticks(g, 1.0)
	_check(not door.opened, "USE from the wrong side leaves it shut")
	_check(said.begins_with("BARRED FROM THE OTHER SIDE"), "and says so (%s)" % said)
	var brawl: Game.BrawlScript = g.features.get("brawl")
	g.player.vx = cos(g.player.angle) * 4.0
	g.player.vy = sin(g.player.angle) * 4.0
	_check(brawl._door_ahead(g.player) < 0, "a running boot from the wrong side does not take it")
	_check(Pilot.door_ahead(g) != door, "the bot does not try it from the wrong side")
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.hostile and e.tactical() and not Enemy.BOSS_TITLES.has(e.kind):
			hand = e
			break
	hand.dormant = false
	hand.x = outer.x
	hand.y = outer.y
	hand.target = [inner.x, inner.y]
	_check(HandTactics._door_ahead(hand, g) != door, "a hand does not kick it")
	hand.dormant = true
	# The bar's side: USE boots it open; it stays open.
	_face(g, door, inner)
	_check(g.use_prompt() == "E  KICK THE BAR LOOSE", "the prompt from the bar's side")
	g.interact()
	_ticks(g, 1.0)
	_check(door.opened and door.progress >= 1.0, "USE from the bar's side boots it open")
	var target: Variant = g.use_target()
	_check(target == null or target[0] != door, "busted open, it stays open (nothing to close)")
	_check(_way(g, outer, inner) == 2, "the way goes through it both ways once open")
	# The same twice.
	var a := _game(id)
	var b := _game(id)
	for game: Game in [a, b]:
		var d2 := _find(game, name)
		_face(game, d2, _beside(d2, 1))
		game.interact()
		_ticks(game, 2.0)
	_check(GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)), "two runs the same")


func _ticks(g: Game, secs: float) -> void:
	for t in int(secs / STEP):
		g.tick(STEP, Game.Controls.new())


## Steps from `from` to `to` by the pin's kind of walk (doors as a player can
## open them, barred ones one way): walked from `to` as the pin walks from the
## objective.
func _way(g: Game, from: Vector2, to: Vector2) -> int:
	var f := FlowField.new(g.world, g.flow)
	f.reach = 100000
	f.doors_open = true
	f.keys = g.keys
	f.update(to.x, to.y, 0.0, g.world.elevation(to.x, to.y))
	return f.distance(from.x, from.y, g.world.elevation(from.x, from.y))


## Every station, key and the exit reached from the start with every barred
## door shut both ways (and every other door open): they are only shortcuts.
func _needed(id: String) -> void:
	var g := _game(id)
	var f := FlowField.new(g.world)
	f.reach = 100000
	f.doors_open = true
	f.every_door = true
	for door: LevelData.Door in _bars(g):
		f.open[door.y * g.world.width + door.x] = 0
	var s := Vector2(float(g.level.spawn[0]), float(g.level.spawn[1]))
	f.update(s.x, s.y, 0.0, g.world.elevation(s.x, s.y))
	var places: Array = []
	for st: LevelData.Station in g.world.stations:
		places.append([st.id, GameObjective.station_goal(g, st)])
	for entry: Array in g.pickups:
		if str(entry[0]).begins_with("key_"):
			places.append([str(entry[0]), Vector2(float(entry[1]), float(entry[2]))])
	if g.world.extraction != null:
		places.append(["exit", Vector2(g.world.extraction.x, g.world.extraction.y)])
	var cut: Array = []
	for row: Array in places:
		var at: Vector2 = row[1]
		if f.distance(at.x, at.y, g.world.goal_floor(at)) >= FlowField.FAR:
			cut.append(row[0])
	_check(cut.is_empty(), "%s: every objective reached with the bars shut %s" % [id, cut])
