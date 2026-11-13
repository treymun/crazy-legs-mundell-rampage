## Several bots in one game: each player (1 to 4) driven by its own
## bot_pilot through its own controls (game.tick with a Dictionary by slot),
## every chapter for a while or to the end. Reports each player's kills,
## damage taken, deaths and stuck time, how the enemies spread their hunting
## over the players, and what a tick costs; fails on a script or engine error,
## a position that is not a number, a player stuck inside a wall, or two
## identical runs that part (determinism with N players: a twin game fed the
## same controls, compared snapshot for snapshot).
##
##   godot --headless --path godot --script res://tools/multi_bots.gd
##       [-- players=4] [levels=hickston,fair] [seconds=60] [whole] [diff=1]
##       [mortal] [no-twin] [quick]
##
## players: a count or a list (players=1,2,4 runs each). whole: plays each
## chapter to the end (or WHOLE_LIMIT s). mortal: no god mode (a player who
## goes down stays down; the run ends when all are). quick: the part
## tools/check_fixes.gd runs (run()). Prints MULTI BOTS OK or MULTI BOTS FAILED.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0
const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
const WHOLE_LIMIT := 1500.0
## Snapshots of the two runs compared every this many ticks (and at the end).
const COMPARE_EVERY := 600
## A player whose middle is inside a wall this many ticks running is stuck in it.
const IN_WALL_TICKS := 30
## The quick part: [level, players, seconds].
const QUICK := [["hickston", 4, 12.0], ["bayou", 2, 6.0]]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var args := OS.get_cmdline_user_args()
	var counts: Array = [4]
	var levels: Array = LEVELS.duplicate()
	var opts := {"seconds": 60.0, "whole": false, "diff": 1, "mortal": false, "twin": true}
	for arg: String in args:
		if arg.begins_with("players="):
			counts = Array(arg.substr(8).split(",")).map(func(n): return clampi(int(n), 1, 4))
		elif arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(","))
		elif arg.begins_with("seconds="):
			opts["seconds"] = float(arg.substr(8))
		elif arg.begins_with("diff="):
			opts["diff"] = int(arg.substr(5))
	opts["whole"] = args.has("whole")
	opts["mortal"] = args.has("mortal")
	opts["twin"] = not args.has("no-twin")
	var check := func(ok: bool, text: String) -> void:
		print("  ok   " if ok else "  FAIL ", text)
		if not ok:
			failures.append(text)
	# Any error at all (one that cut a run short too) fails the tool.
	var errors := CrashLog.tally()
	if args.has("quick"):
		run(main, check)
	else:
		for n: int in counts:
			for id: String in levels:
				play(main, check, id, n, opts)
	errors.stop()
	if errors.errors > 0:
		check.call(false, "%d error(s), the first: %s" % [errors.errors, errors.first_errors[0]])
	print("")
	print("MULTI BOTS OK" if failures.is_empty() else "MULTI BOTS FAILED (%d)" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The quick part (tools/check_fixes.gd): QUICK's runs, each with its twin.
static func run(main, check: Callable) -> void:
	for row: Array in QUICK:
		var opts := {"seconds": float(row[2]), "whole": false, "diff": 1, "mortal": false}
		opts["twin"] = true
		play(main, check, String(row[0]), int(row[1]), opts)


## A game of `level` with `count` players: player one at the start, the rest
## on open floor round them, the chapters before it in the history.
static func made(main, level: String, count: int, difficulty := 1) -> Game:
	var g: Game = main.make_game(level)
	g.configure({"difficulty": difficulty})
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(level))):
		g.history.append([done, 1, 2, 0, 1, 60])
	for i in count - 1:
		seat(g)
	return g


## Joins a player on open floor near player one, clear of the others, and
## returns its slot.
static func seat(g: Game) -> int:
	var one: Player = g.players[0]
	var at := Vector2(one.x, one.y)
	for ring: float in [1.0, 1.6, 2.2]:
		for k in 8:
			var there := Vector2(one.x, one.y) + Vector2.from_angle(k * TAU / 8.0) * ring
			var free := not g.world.blocked(there.x, there.y, .3)
			for other: Player in g.players:
				free = free and Vector2(other.x, other.y).distance_to(there) > .7
			if free and g.world.visible(one.x, one.y, there.x, there.y):
				return Players.join(g, there.x, there.y, one.angle).slot
	return Players.join(g, at.x, at.y, one.angle).slot


## One run: `count` bots play `level`; returns false when it failed.
static func play(main, check: Callable, level: String, count: int, opts: Dictionary) -> bool:
	var tally := CrashLog.tally()
	var a := made(main, level, count, int(opts["diff"]))
	var twin := bool(opts.get("twin", true))
	var b: Game = made(main, level, count, int(opts["diff"])) if twin else null
	if b != null and count > 1:
		# The twin is seen from the last player's machine: what only looks or
		# sounds follows the local player and must never change play.
		Players.set_local(b, b.players[count - 1])
	var god := not bool(opts["mortal"])
	for g: Game in [a, b]:
		if g != null:
			g.cheats.god = god
	var pilots: Array = []
	for i in count:
		var pilot := Pilot.new()
		pilot.as_controls = true
		pilots.append(pilot)
	var kills := _zeros(count)
	var hurt := _zeros(count)
	var deaths := _zeros(count)
	var stuck := _zeros(count)
	var longest := _zeros(count)
	var in_wall := _zeros(count)
	var hunted := _zeros(count)
	a.enemy_killed.connect(func(_e: Enemy) -> void: kills[a.player.slot] += 1)
	a.player_hurt.connect(func(amount: float, _c: String) -> void: hurt[a.player.slot] += amount)
	var alive := []
	var last := []
	var still := _zeros(count)
	for p: Player in a.players:
		alive.append(p.health > 0)
		last.append(Vector2(p.x, p.y))
	var limit := WHOLE_LIMIT if bool(opts["whole"]) else float(opts["seconds"])
	var ticks := int(limit * 60.0)
	var times := PackedFloat64Array()
	var split := -1
	var split_at := ""
	var nan_at := ""
	var wall_at := ""
	var played := 0
	for t in ticks:
		if a.won or not Players.anyone_alive(a):
			break
		var given := {}
		for p: Player in a.players:
			if p.health <= 0:
				continue
			# A gun run dry is filled again in both runs alike (bot_pilot's
			# own `whole` refill would touch only the game it steers).
			if god:
				for g: Game in [a, b]:
					if g != null:
						_refill(g.players[p.slot])
			a.focus(p)
			given[p.slot] = pilots[p.slot].steer(a)
		a.focus(a.local_player)
		var t0 := Time.get_ticks_usec()
		a.tick(STEP, given)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		if b != null:
			b.tick(STEP, given)
		played += 1
		for p: Player in a.players:
			var i := p.slot
			a.focus(p)
			pilots[i].moved(a)
			if bool(alive[i]) and p.health <= 0:
				deaths[i] += 1
			alive[i] = p.health > 0
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.eye)):
				if nan_at == "":
					nan_at = "player %d at tick %d" % [i, t]
				continue
			var here := Vector2(p.x, p.y)
			if p.health > 0 and pilots[i].foe == null and here.distance_to(last[i]) < .002:
				still[i] += STEP
				stuck[i] += STEP
				longest[i] = maxf(longest[i], still[i])
			else:
				still[i] = 0.0
			last[i] = here
			in_wall[i] = in_wall[i] + 1 if _in_wall(a, p) else 0
			if in_wall[i] >= IN_WALL_TICKS and wall_at == "":
				wall_at = "player %d inside a wall at (%.2f, %.2f), tick %d" % [i, p.x, p.y, t]
		a.focus(a.local_player)
		for e: Enemy in a.enemies:
			if not (is_finite(e.x) and is_finite(e.y)):
				if nan_at == "":
					nan_at = "%s (uid %d) at tick %d" % [e.kind, e.uid, t]
				continue
			if e.alive and e.hostile and e.alerted:
				var who: int = e.hunted.slot if e.hunted != null else 0
				hunted[who] += 1
		if b != null and split < 0 and ((t + 1) % COMPARE_EVERY == 0):
			split_at = _differ(a, b)
			if split_at != "":
				split = t + 1
	if b != null and split < 0:
		split_at = _differ(a, b)
		split = played if split_at != "" else -1
	tally.stop()
	times.sort()
	var total_hunt := 0
	for n in hunted:
		total_hunt += n
	var tag := "%s, %d player%s" % [level, count, "" if count == 1 else "s"]
	print(
		(
			"  %s: %d ticks (%.0f s%s), %d kills, tick median %.2f ms p99 %.2f max %.2f"
			% [
				tag,
				played,
				played / 60.0,
				", won" if a.won else "",
				a.kills,
				times[times.size() / 2] if not times.is_empty() else 0.0,
				times[int(times.size() * .99)] if not times.is_empty() else 0.0,
				times[-1] if not times.is_empty() else 0.0
			]
		)
	)
	for i in count:
		var p: Player = a.players[i]
		print(
			(
				(
					"    player %d: kills %3d  damage taken %4d  deaths %d  stuck %5.1f s"
					+ " (longest %4.1f)  hunted %3.0f%%  health %d at (%.1f, %.1f)"
				)
				% [
					i,
					kills[i],
					hurt[i],
					deaths[i],
					stuck[i],
					longest[i],
					100.0 * hunted[i] / maxf(1.0, total_hunt),
					p.health,
					p.x,
					p.y
				]
			)
		)
	var ok := [true]
	var said := func(cond: bool, text: String) -> void:
		check.call(cond, text)
		ok[0] = bool(ok[0]) and cond
	said.call(
		tally.errors == 0,
		(
			"%s: no script or engine errors%s"
			% [
				tag,
				"" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]]
			]
		)
	)
	said.call(nan_at == "", "%s: every position is a number%s" % [tag, _but(nan_at)])
	said.call(wall_at == "", "%s: no player stuck inside a wall%s" % [tag, _but(wall_at)])
	if b != null:
		said.call(
			split < 0,
			(
				"%s: two runs fed the same controls stay identical%s"
				% [tag, "" if split < 0 else " (part by tick %d: %s)" % [split, split_at]]
			)
		)
	return bool(ok[0])


static func _zeros(n: int) -> Array:
	var out := []
	out.resize(n)
	out.fill(0)
	return out


static func _but(what: String) -> String:
	return "" if what == "" else " (" + what + ")"


## Out of rounds in the gun held: a full reserve (god runs only).
static func _refill(p: Player) -> void:
	var arms = p.armory
	if arms.loaded[arms.active] == 0 and arms.reserve[arms.active] == 0:
		arms.reserve[arms.active] = Weapons.MAX_RESERVE[arms.active]


## Whether the player's middle is inside a solid cell (or off the map).
static func _in_wall(g: Game, p: Player) -> bool:
	var w := g.world
	var ix := int(floorf(p.x))
	var iy := int(floorf(p.y))
	if ix < 0 or iy < 0 or ix >= w.width or iy >= w.height:
		return true
	return w.solid[iy * w.width + ix] >= 0


## Where two runs' snapshots part ("" when they agree), each taken as the host
## takes it, without what follows the local player (NetSync).
static func _differ(a: Game, b: Game) -> String:
	return GameSnapshot.first_difference(
		NetSync.comparable(NetSync.capture(a)), NetSync.comparable(NetSync.capture(b))
	)
