## The plain player first_minutes.gd plays with, on its own so a real window
## can be played by it too (main.gd --play-bench): walks the way the objective
## pin points (Game.route), opens doors on the way, uses the objective, shoots
## a struck station, turns to shoot any enemy after it and hops a ledge it is
## stuck on. No cheats of its own; `whole` refills the gun it holds.
extends RefCounted

const STEP := 1.0 / 60.0

var whole := false
## Asks for USE and the next gun through the controls it hands back instead
## of calling the game (a game run in lockstep with another, or a player who
## is not the local one: tools/net_check.gd).
var as_controls := false
## The turn away from a wall it was stuck on, for the next controls (as_controls).
var turn_away := 0.0
var stuck := 0.0
var last := Vector2.INF
## The enemy it was after this tick (null: none).
var foe: Enemy = null
var close_for := 0.0
var back_until := 0.0
## A way round something solid on the route (detour()): cell centres left
## to walk, and when it is given up.
var around: Array[Vector2] = []
var around_until := 0.0

## How far round a detour looks, in cells.
const AROUND_REACH := 6


func _use(game: Game, controls: Game.Controls) -> void:
	if as_controls:
		controls.use = true
	else:
		game.interact()


## The heading to the nearest neighbouring cell the route covers, or `aim`.
func _back_on_route(game: Game, aim: float) -> float:
	var p := game.player
	var best := INF
	for n: Vector2i in FlowField.NEIGHBOURS:
		var at := Vector2(int(p.x) + n.x + .5, int(p.y) + n.y + .5)
		if game.route.distance(at.x, at.y) >= FlowField.FAR:
			continue
		var d := at.distance_to(Vector2(p.x, p.y))
		if d < best:
			best = d
			aim = atan2(at.y - p.y, at.x - p.x)
	return aim


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
		var gap := Vector2(foe.x - p.x, foe.y - p.y).length()
		var pitch := _aim_pitch(game, foe, gap)
		controls.look = clampf(pitch - p.pitch, -3.0, 3.0)
		var tilt := clampf(p.pitch + controls.look, -53.0, 53.0) + p.sway
		var z := p.eye + gap * tilt / View.base_focal
		var feet := game.world.stand(foe) + foe.z
		controls.fire = (
			absf(angle_difference(want, p.view_angle() + controls.turn)) < .08
			and z > feet
			and z < feet + foe.height
			and game.world.visible(p.x, p.y, foe.x, foe.y, p.eye, z)
		)
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
				_use(game, controls)
		elif goal != null:
			var way: Array = game.objective_route(goal)
			var aim := atan2(goal.y - p.y, goal.x - p.x)
			if int(way[1]) > 1:
				# One cell at a time, so it never cuts a corner into a wall.
				var next := game.route.heading(p.x, p.y, game.world.stand(p))
				aim = next if not is_nan(next) else aim
				# Stopped by a solid prop the route walks through (a one-cell
				# searchlight, vat or floodlight): walk round it instead.
				if around.is_empty() and stuck > .25 and _solid_ahead(game, aim):
					around = detour(game)
					around_until = game.clock + 4.0
				if not around.is_empty():
					aim = _follow_around(game, aim)
			elif int(way[1]) < 0:
				# Pressed into a nook the route does not cover (beside a station
				# after a fight there): back to the nearest cell it does.
				aim = _back_on_route(game, aim)
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
				controls.look = clampf((top - p.eye) / reach * View.base_focal - p.pitch, -3.0, 3.0)
				controls.fire = absf(turn) < .05
				way = [goal, 0]
				gap = 0.0
			if int(way[1]) > 1 or gap > .3:
				controls.forward = 1.0 if absf(turn) < .9 else .2
				controls.running = gap > 1.5
			# Up against the objective a while with nothing to use or shoot (a
			# last threat wedged where it cannot be seen): back off and come again.
			close_for = close_for + STEP if gap < 1.6 else 0.0
			if close_for > 4.0:
				close_for = 0.0
				back_until = game.clock + 2.5
			if game.clock < back_until:
				controls.turn = clampf(fposmod(aim + PI - p.angle + PI, TAU) - PI, -.12, .12)
				controls.forward = 1.0
			if gap < 1.3 and absf(turn) < .3 and fmod(game.clock, .4) < STEP:
				# At the objective: use it (a key is picked up by walking on it).
				_use(game, controls)
		controls.look = clampf(-p.pitch, -2.0, 2.0)
	# Out of rounds and nothing in reach: switch to anything that has some.
	if game.armory.loaded[game.armory.active] == 0 and game.armory.reserve[game.armory.active] == 0:
		if whole:
			game.armory.reserve[game.armory.active] = Weapons.MAX_RESERVE[game.armory.active]
		elif as_controls:
			controls.cycle = 1
		else:
			game.armory.cycle(1, game)
	# Stuck against a ledge: hop it, as a player would (a jump clears about .6).
	if stuck > .35 and foe == null:
		controls.jump = fmod(game.clock, .6) < .1
		controls.forward = 1.0
	controls.turn += turn_away
	turn_away = 0.0
	return controls


## After the tick: notice being stuck, and turn away when it lasts.
func moved(game: Game) -> void:
	var p := game.player
	if Vector2(p.x, p.y).distance_to(last) < .002 and foe == null:
		stuck += STEP
		if stuck > 2.0:
			if as_controls:
				turn_away = 1.3
			else:
				p.angle += 1.3
			stuck = 0.0
	else:
		stuck = 0.0
	last = Vector2(p.x, p.y)


## True when a step of the player's width toward `aim` runs into something
## solid where it stands now is clear.
func _solid_ahead(game: Game, aim: float) -> bool:
	var p := game.player
	var z := p.floor_z + .35
	var r := GameState.PLAYER_RADIUS
	if game.world.blocked(p.x, p.y, r, z):
		return false
	return game.world.blocked(p.x + cos(aim) * .12, p.y + sin(aim) * .12, r, z)


## The cell centres of the shortest walk (within AROUND_REACH cells) from the
## player's cell to one nearer the objective, round whatever is solid at the
## player's height; empty when there is none.
func detour(game: Game) -> Array[Vector2]:
	var p := game.player
	var w := game.world
	var z := p.floor_z + .35
	var r := GameState.PLAYER_RADIUS + .06
	var start := Vector2i(int(p.x), int(p.y))
	var here := game.route.distance(p.x, p.y, game.world.stand(p))
	if here >= FlowField.FAR:
		return []
	var span := AROUND_REACH * 2 + 1
	var free := {}
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var open := func(c: Vector2i) -> bool:
		if absi(c.x - start.x) > AROUND_REACH or absi(c.y - start.y) > AROUND_REACH:
			return false
		if not free.has(c):
			free[c] = (
				game.route.distance(c.x + .5, c.y + .5) < FlowField.FAR
				and not w.blocked(c.x + .5, c.y + .5, r, z)
			)
		return free[c]
	while head < queue.size() and head < span * span:
		var c: Vector2i = queue[head]
		head += 1
		if c != start and game.route.distance(c.x + .5, c.y + .5) < here:
			var path: Array[Vector2] = []
			while c != start:
				path.push_front(Vector2(c.x + .5, c.y + .5))
				c = came[c]
			return path
		for n: Vector2i in FlowField.NEIGHBOURS:
			var to := c + n
			if came.has(to) or not open.call(to):
				continue
			if n.x != 0 and n.y != 0:
				if not (open.call(Vector2i(to.x, c.y)) and open.call(Vector2i(c.x, to.y))):
					continue
			# The step itself clear too (from where the player stands, at first).
			var from := Vector2(p.x, p.y) if c == start else Vector2(c.x + .5, c.y + .5)
			if not _clear_walk(w, from, Vector2(to.x + .5, to.y + .5), r, z):
				continue
			came[to] = c
			queue.append(to)
	return []


## True when nothing solid at height z stands on the straight walk from a to b.
static func _clear_walk(w: LevelData, a: Vector2, b: Vector2, r: float, z: float) -> bool:
	var steps := ceili(a.distance_to(b) / .15)
	for i in range(1, steps + 1):
		var at := a.lerp(b, float(i) / steps)
		if w.blocked(at.x, at.y, r, z):
			return false
	return true


## The heading to the next cell centre of the detour, dropping the ones
## reached; back to `aim` once it is walked or given up.
func _follow_around(game: Game, aim: float) -> float:
	var p := game.player
	while not around.is_empty() and Vector2(p.x, p.y).distance_to(around[0]) < .3:
		around.pop_front()
	if around.is_empty() or game.clock > around_until:
		around.clear()
		return aim
	return atan2(around[0].y - p.y, around[0].x - p.x)


## The nearest hostile that has noticed the player and can be seen.
static func nearest_threat(game: Game) -> Enemy:
	var p := game.player
	var best: Enemy = null
	var near := 14.0
	for e: Enemy in game.enemies:
		if not (e.alive and e.hostile and (e.alerted or e.player_seen)):
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < near and not is_nan(_aim_pitch(game, e, d)):
			best = e
			near = d
	return best


## Aim at an exposed part of the actor within the game's vertical look range.
static func _aim_pitch(game: Game, e: Enemy, distance: float) -> float:
	var p: Player = game.player
	var feet := game.world.stand(e) + e.z
	for part: float in [.58, .88, .27]:
		var z := feet + e.height * part
		var pitch := (z - p.eye) * View.base_focal / maxf(.01, distance) - p.sway
		if absf(pitch) <= 53.0 and game.world.visible(p.x, p.y, e.x, e.y, p.eye, z):
			return pitch
	return NAN


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
		if door.opened or door.secret or door.blast_only or door.barred_from(p.x, p.y):
			continue
		if door.key != "" and not game.keys.has(door.key):
			continue
		if game.world.controlled_doors.has(Vector2i(door.x, door.y)):
			continue
		if door.center().distance_to(Vector2(p.x, p.y)) < 1.4:
			return door
	return null
