## How the start of each chapter plays for a plain player: a bot that walks
## the way the objective pin points (Game.route) and turns to shoot at any
## enemy that is after it, in real game ticks, no cheats. Prints when the
## first enemy notices it, the first hit it lands and takes, and its kills and
## health after one, two and five minutes; FIRST MINUTES OK when the first
## fight of every chapter starts within FIRST_FIGHT seconds.
##
##   godot --headless --path godot --script res://tools/first_minutes.gd
##       [-- <level>] [old-ai] [whole]
##
## old-ai: enemies that lose sight of the player do not hunt for them.
## whole: the bot cannot be hurt and never runs dry, and plays on until the
##   chapter is won (or WHOLE_LIMIT seconds): the way through can be walked,
##   every door, key and set piece on it working. Prints how long it took.
## hitches: also times every tick and prints the slowest (a stutter in the
##   game's own work, apart from drawing) with what happened in it.
##
## It is a yardstick for pacing, not a judge of fun: it never dodges, so its
## health says more about how hard enemies press than about the difficulty.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")

const STEP := 1.0 / 60.0
const MARKS := [60.0, 120.0, 300.0]
const FIRST_FIGHT := 20.0
const WHOLE_LIMIT := 1500.0

var sound: Sound
var whole := false
var hitches := false
## What the game announced during the tick being timed.
var _events: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("old-ai"):
		Enemy.hunting = false
		args.erase("old-ai")
	if args.has("whole"):
		whole = true
		args.erase("whole")
	if args.has("hitches"):
		hitches = true
		args.erase("hitches")
	var ids := (
		["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
		if args.is_empty()
		else [args[0]]
	)
	var art := Assets.new()
	var hud := HUD.new(art)
	sound = Sound.new(art)
	root.add_child(sound)
	var slow := false
	for id: String in ids:
		var first := _play(art, hud, id)
		slow = slow or first < 0.0 or first > FIRST_FIGHT
	print("FIRST MINUTES OK" if not slow else "FIRST MINUTES SLOW")
	quit()


## Plays one chapter's opening and returns when its first fight began.
func _play(art: Assets, hud: HUD, id: String) -> float:
	var game := Game.new(art, hud, sound, id)
	game.configure({"hints": 1})
	game.cheats.god = whole
	var seen := -1.0
	var landed := -1.0
	var taken := -1.0
	var health_was := game.player.health
	var kills_was := 0
	var lines: Array[String] = []
	var mark := 0
	var pilot := Pilot.new()
	pilot.whole = whole
	var p := game.player
	var times := PackedFloat64Array()
	var slowest: Array = []
	if hitches:
		for event in ["enemy_killed", "player_hurt", "pickup_taken", "station_done", "exploded"]:
			game.connect(
				event, func(_a = null, _b = null, _c = null, _d = null): _events.append(event)
			)
	while (
		(mark < MARKS.size() or (whole and game.clock < WHOLE_LIMIT))
		and game.player.health > 0
		and not game.won
	):
		var controls := pilot.steer(game)
		var foe := pilot.foe
		if foe != null and seen < 0.0:
			seen = game.clock
		var t0 := Time.get_ticks_usec()
		_events.clear()
		game.tick(STEP, controls)
		if hitches:
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			times.append(ms)
			if ms > 4.0:
				slowest.append([ms, game.clock, ",".join(_events)])
		pilot.moved(game)
		if landed < 0.0 and game.kills > kills_was:
			landed = game.clock
		if landed < 0.0 and game.hit_mark_until > game.clock:
			landed = game.clock
		if taken < 0.0 and p.health < health_was:
			taken = game.clock
		if mark < MARKS.size() and game.clock >= MARKS[mark]:
			var goal = game.objective_target()
			var left := -1
			if goal != null:
				left = int(game.objective_route(goal)[1])
			(
				lines
				. append(
					(
						"    at %3.0f s: %2d kills, health %3d, at (%.1f, %.1f), %d steps to the objective"
						% [MARKS[mark], game.kills, p.health, p.x, p.y, left]
					)
				)
			)
			mark += 1
	print(
		(
			"%-9s first noticed %s   first hit landed %s   first hit taken %s"
			% [id, _when(seen), _when(landed), _when(taken)]
		)
	)
	for line in lines:
		print(line)
	if hitches and not times.is_empty():
		var sorted := times.duplicate()
		sorted.sort()
		slowest.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		print(
			(
				"    ticks %d: median %.2f ms, p99 %.2f, p99.9 %.2f, max %.2f; over 4 ms: %d"
				% [
					sorted.size(),
					sorted[sorted.size() / 2],
					sorted[int(sorted.size() * .99)],
					sorted[int(sorted.size() * .999)],
					sorted[-1],
					slowest.size()
				]
			)
		)
		for row in slowest.slice(0, 10):
			print("      %.2f ms at %.1f s %s" % [row[0], row[1], row[2]])
	if game.player.health <= 0:
		print("    went down at %.0f s with %d kills" % [game.clock, game.kills])
	elif game.won:
		print("    finished at %.0f s with %d kills" % [game.clock, game.kills])
	elif whole:
		var goal = game.objective_target()
		print(
			(
				"    NOT FINISHED by %.0f s: at (%.1f, %.1f), %s, %d steps to the objective"
				% [
					game.clock,
					game.player.x,
					game.player.y,
					game.objective(),
					int(game.objective_route(goal)[1]) if goal != null else -1
				]
			)
		)
		for e: Enemy in game.wave:
			if e.alive:
				print("      still up: %s at (%.1f, %.1f)" % [e.kind, e.x, e.y])
		return -1.0
	return seen


func _when(t: float) -> String:
	return "never" if t < 0.0 else "%5.1f s" % t
