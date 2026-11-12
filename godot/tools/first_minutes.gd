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
##
## It is a yardstick for pacing, not a judge of fun: it never dodges, so its
## health says more about how hard enemies press than about the difficulty.
extends SceneTree

const STEP := 1.0 / 60.0
const MARKS := [60.0, 120.0, 300.0]
const FIRST_FIGHT := 20.0
const WHOLE_LIMIT := 1500.0

var sound: Sound
var whole := false


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
	var ids := (
		["hickston", "fair", "sawmill", "quarry", "bayou", "speedway"]
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
	var stuck := 0.0
	var last := Vector2(game.player.x, game.player.y)
	while (
		(mark < MARKS.size() or (whole and game.clock < WHOLE_LIMIT))
		and game.player.health > 0
		and not game.won
	):
		var controls := Game.Controls.new()
		var foe := _nearest_threat(game)
		var p := game.player
		if foe != null:
			if seen < 0.0:
				seen = game.clock
			var want := atan2(foe.y - p.y, foe.x - p.x)
			var turn := fposmod(want - p.angle + PI, TAU) - PI
			controls.turn = clampf(turn, -.12, .12)
			var target: float = game.world.elevation(foe.x, foe.y) + foe.z + foe.height * .58
			var slope := (target - p.eye) / maxf(.5, Vector2(foe.x - p.x, foe.y - p.y).length())
			controls.look = clampf(slope * Renderer.base_focal - p.pitch, -3.0, 3.0)
			controls.fire = absf(turn) < .08
			controls.forward = .4 if Vector2(foe.x - p.x, foe.y - p.y).length() > 4.0 else 0.0
		else:
			var goal = game.objective_target()
			var door := _door_ahead(game)
			if door != null:
				# A closed door on the way: face it and press use, as a player would.
				var centre := door.center()
				var face := fposmod(atan2(centre.y - p.y, centre.x - p.x) - p.angle + PI, TAU) - PI
				controls.turn = clampf(face, -.12, .12)
				if absf(face) < .3 and fmod(game.clock, .4) < STEP:
					game.interact()
			elif goal != null:
				var way: Array = game.objective_route(goal)
				var aim := atan2(goal.y - p.y, goal.x - p.x)
				if int(way[1]) > 1:
					# One cell at a time, so it never cuts a corner into a wall.
					var next := game.route.heading(p.x, p.y)
					aim = next if not is_nan(next) else aim
				var turn := fposmod(aim - p.angle + PI, TAU) - PI
				controls.turn = clampf(turn, -.12, .12)
				var gap := Vector2(goal.x - p.x, goal.y - p.y).length()
				var struck := _strike_target(game, goal)
				if struck != null and gap < 3.0:
					# A thing to hit rather than use (the mill's belt release): shoot it.
					var want := atan2(struck.y - p.y, struck.x - p.x)
					turn = fposmod(want - p.angle + PI, TAU) - PI
					controls.turn = clampf(turn, -.12, .12)
					var top: float = (
						game.world.elevation(struck.x, struck.y) + struck.z + struck.height * .5
					)
					var reach := maxf(.5, Vector2(struck.x - p.x, struck.y - p.y).length())
					controls.look = clampf(
						(top - p.eye) / reach * Renderer.base_focal - p.pitch, -3.0, 3.0
					)
					controls.fire = absf(turn) < .05
					way = [goal, 0]
					gap = 0.0
				if int(way[1]) > 1 or gap > .3:
					controls.forward = 1.0 if absf(turn) < .9 else .2
					controls.running = gap > 1.5
				if gap < 1.3 and absf(turn) < .3 and fmod(game.clock, .4) < STEP:
					# At the objective: use it (a key is picked up by walking on it).
					game.interact()
			controls.look = clampf(-p.pitch, -2.0, 2.0)
		# Out of rounds and nothing in reach: switch to anything that has some.
		if (
			game.armory.loaded[game.armory.active] == 0
			and game.armory.reserve[game.armory.active] == 0
		):
			if whole:
				game.armory.reserve[game.armory.active] = Weapons.MAX_RESERVE[game.armory.active]
			else:
				game.armory.cycle(1, game)
		# Stuck against a ledge: hop it, as a player would (a jump clears about .6).
		if stuck > .35 and foe == null:
			controls.jump = fmod(game.clock, .6) < .1
			controls.forward = 1.0
		game.tick(STEP, controls)
		if Vector2(p.x, p.y).distance_to(last) < .002 and foe == null:
			stuck += STEP
			if stuck > 2.0:
				p.angle += 1.3
				stuck = 0.0
		else:
			stuck = 0.0
		last = Vector2(p.x, p.y)
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
		return -1.0
	return seen


func _when(t: float) -> String:
	return "never" if t < 0.0 else "%5.1f s" % t


## The nearest hostile that has noticed the player and can be seen.
func _nearest_threat(game: Game) -> Enemy:
	var p := game.player
	var best: Enemy = null
	var near := 14.0
	for e: Enemy in game.enemies:
		if not (e.alive and e.hostile and (e.alerted or e.player_seen)):
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < near and game.world.visible(p.x, p.y, e.x, e.y):
			best = e
			near = d
	return best


## The scenery a strike station at `goal` is struck through, if it is one.
func _strike_target(game: Game, goal: Vector2) -> LevelData.Scenery:
	for station: LevelData.Station in game.world.stations:
		if station.action != "strike" or game.stations_done.has(station.id):
			continue
		if Vector2(station.x, station.y).distance_to(goal) > .5:
			continue
		for prop: LevelData.Scenery in game.world.scenery:
			if prop.station == station.id and not game.scenery_used(prop):
				return prop
	return null


## A closed door within reach that the player can open (no key it lacks, not
## a secret one), or null.
func _door_ahead(game: Game) -> LevelData.Door:
	var p := game.player
	for door: LevelData.Door in game.world.doors:
		if door.opened or door.secret or door.blast_only:
			continue
		if door.key != "" and not game.keys.has(door.key):
			continue
		if game.world.controlled_doors.has(Vector2i(door.x, door.y)):
			continue
		if door.center().distance_to(Vector2(p.x, p.y)) < 1.4:
			return door
	return null
