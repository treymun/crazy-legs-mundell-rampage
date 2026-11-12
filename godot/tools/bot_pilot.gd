## The plain player first_minutes.gd plays with, on its own so a real window
## can be played by it too (main.gd --play-bench): walks the way the objective
## pin points (Game.route), opens doors on the way, uses the objective, shoots
## a struck station, turns to shoot any enemy after it and hops a ledge it is
## stuck on. No cheats of its own; `whole` refills the gun it holds.
extends RefCounted

const STEP := 1.0 / 60.0

var whole := false
var stuck := 0.0
var last := Vector2.INF
## The enemy it was after this tick (null: none).
var foe: Enemy = null


## This tick's controls for `game`.
func steer(game: Game) -> Game.Controls:
	var controls := Game.Controls.new()
	foe = nearest_threat(game)
	var p := game.player
	if last == Vector2.INF:
		last = Vector2(p.x, p.y)
	if foe != null:
		var want := atan2(foe.y - p.y, foe.x - p.x)
		var turn := fposmod(want - p.angle + PI, TAU) - PI
		controls.turn = clampf(turn, -.12, .12)
		var target: float = game.world.elevation(foe.x, foe.y) + foe.z + foe.height * .58
		var slope := (target - p.eye) / maxf(.5, Vector2(foe.x - p.x, foe.y - p.y).length())
		controls.look = clampf(slope * Renderer.base_focal - p.pitch, -3.0, 3.0)
		controls.fire = absf(turn) < .08
		var gap := Vector2(foe.x - p.x, foe.y - p.y).length()
		controls.forward = .4 if gap > 4.0 else 0.0
		# Something at its feet (a gator under the gun): step back to get a shot.
		if gap < 1.2:
			controls.forward = -.8
	else:
		var goal = game.objective_target()
		var door := door_ahead(game)
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
			var struck := strike_target(game, goal)
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
	if game.armory.loaded[game.armory.active] == 0 and game.armory.reserve[game.armory.active] == 0:
		if whole:
			game.armory.reserve[game.armory.active] = Weapons.MAX_RESERVE[game.armory.active]
		else:
			game.armory.cycle(1, game)
	# Stuck against a ledge: hop it, as a player would (a jump clears about .6).
	if stuck > .35 and foe == null:
		controls.jump = fmod(game.clock, .6) < .1
		controls.forward = 1.0
	return controls


## After the tick: notice being stuck, and turn away when it lasts.
func moved(game: Game) -> void:
	var p := game.player
	if Vector2(p.x, p.y).distance_to(last) < .002 and foe == null:
		stuck += STEP
		if stuck > 2.0:
			p.angle += 1.3
			stuck = 0.0
	else:
		stuck = 0.0
	last = Vector2(p.x, p.y)


## The nearest hostile that has noticed the player and can be seen.
static func nearest_threat(game: Game) -> Enemy:
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
static func strike_target(game: Game, goal: Vector2) -> LevelData.Scenery:
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
static func door_ahead(game: Game) -> LevelData.Door:
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
