## The objective, moved out of game_world.gd: what it says (objective()), where
## its pin points (objective_target(), objective_route(), station_goal(),
## shore_near()) and the quest props' lamps (quest_lights()). GameWorld keeps
## objective(), objective_target() and objective_route() handing on to these.
class_name GameObjective
extends RefCounted


static func objective_target(g: Game) -> Variant:
	if g.in_hub or g.revisiting:
		return null
	var run: Variant = _run_goal(g)
	if run != null:
		return run
	if not g.level.rescue:
		var exit: LevelData.Extraction = g.world.extraction
		if exit == null:
			return null
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in g.world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return null
		var primary: Array = []
		for key: Variant in shutdown.requires:
			if not g.world.objective_side_tasks.has(key):
				primary.append(str(key))
		var pending: Array = []
		for key: String in primary:
			if not g.stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in g.world.stations:
				if station.id == pending[0]:
					return station_goal(g, station)
		if not pending.is_empty():
			var options: Array = []
			for station: LevelData.Station in g.world.stations:
				if pending.has(station.id):
					options.append(station)
			if options.is_empty():
				return null
			var near: LevelData.Station = options[0]
			for station: LevelData.Station in options:
				if (
					(
						(station.x - g.player.x) * (station.x - g.player.x)
						+ (station.y - g.player.y) * (station.y - g.player.y)
					)
					< (
						(near.x - g.player.x) * (near.x - g.player.x)
						+ (near.y - g.player.y) * (near.y - g.player.y)
					)
				):
					near = station
			return station_goal(g, near)
		for station: LevelData.Station in g.world.stations:
			if g.world.objective_side_tasks.has(station.id) and not g.stations_done.has(station.id):
				return Vector2(station.x, station.y)
		if not g.stations_done.has(shutdown.id):
			return Vector2(shutdown.x, shutdown.y)
		var threats: Array = []
		for enemy: Enemy in g.wave:
			if enemy.alive:
				threats.append(enemy)
		if not threats.is_empty():
			var near2: Enemy = threats[0]
			for enemy: Enemy in threats:
				if (
					(
						(enemy.x - g.player.x) * (enemy.x - g.player.x)
						+ (enemy.y - g.player.y) * (enemy.y - g.player.y)
					)
					< (
						(near2.x - g.player.x) * (near2.x - g.player.x)
						+ (near2.y - g.player.y) * (near2.y - g.player.y)
					)
				):
					near2 = enemy
			if g.world.deep_at(near2.x, near2.y):
				# Out on deep water (the swamp king): the nearest ground to it.
				return shore_near(g, near2.x, near2.y)
			return Vector2(near2.x, near2.y)
		return Vector2(exit.x, exit.y)
	# Hickston: the same steps objective() names. The pin used to point at the
	# sheriff from the start, through the locked barn, while the words said to
	# fetch the brass key.
	var boss: Enemy = g.boss
	var jerry: Enemy = g.jerry
	var bessie: Enemy = g.bessie
	var boss_up: bool = boss != null and boss.alive
	var jerry_up: bool = jerry != null and jerry.alive
	if not boss_up and not jerry_up:
		return Vector2(bessie.x, bessie.y) if bessie != null and bessie.hp > 0.0 else null
	if jerry_up and not jerry.dormant:
		return Vector2(jerry.x, jerry.y)
	if not g.keys.has("key_steel"):
		var wanted := "key_steel" if g.keys.has("key_brass") else "key_brass"
		for entry: Array in g.pickups:
			if str(entry[0]) == wanted:
				var entry_x: float = entry[1]
				var entry_y: float = entry[2]
				return Vector2(entry_x, entry_y)
	if boss_up:
		return Vector2(boss.x, boss.y)
	return Vector2(jerry.x, jerry.y)


## A vehicle set piece's next gate, or its start for a player at the wheel
## of the vehicle that can run it (features/vehicle_runs.gd); null else.
static func _run_goal(g: Game) -> Variant:
	var runs: GameFeature = g.features.get("vehicle_runs")
	return runs.call("goal", g.player) if runs != null else null


## Where to go for a station: the station, or first the thing it needs carried
## to it (the fair's PA patch lead) while that still lies somewhere.
static func station_goal(g: Game, station: LevelData.Station) -> Vector2:
	if station.held != "" and not g.task_items.has(station.held):
		for entry: Array in g.pickups:
			if str(entry[0]) == station.held:
				var lies_x: float = entry[1]
				var lies_y: float = entry[2]
				return Vector2(lies_x, lies_y)
	return Vector2(station.x, station.y)


## What the objective is done at glows a little, as the lamp on the quest prop
## would: a station still to do warm at its lamp, a done one a small green
## pilot; the exit red until the way is clear, then green; a Crossroads gate
## red while locked, green once open (effects.cfg station_todo, station_done,
## exit_locked, exit_open, gate_locked, gate_open). Steady: the props are
## modelled whole and read without a blink. A hidden station keeps its secret.
static func quest_lights(g: Game) -> Array:
	var p := g.player
	var out: Array = []
	if g.in_hub:
		for gate: LevelData.Gate in g.world.hub_gates:
			if absf(gate.x - p.x) < 14.0 and absf(gate.y - p.y) < 14.0:
				var locked := g.world.locked_gates.has(gate)
				var z := g.world.elevation(gate.x, gate.y + gate.side * .4) + 2.0
				out.append(
					Effects.light(
						"gate_locked" if locked else "gate_open",
						gate.x,
						gate.y + gate.side * .4,
						z,
						1.0,
						g.clock
					)
				)
		return out
	for station: LevelData.Station in g.world.stations:
		if station.hidden or station.reveals_secret:
			continue
		if absf(station.x - p.x) > 12.0 or absf(station.y - p.y) > 12.0:
			continue
		var done := g.stations_done.has(station.id)
		var at: Vector3 = lamp_at(g, station)
		out.append(
			Effects.light(
				"station_done" if done else "station_todo",
				at.x,
				at.y,
				at.z - (.45 if done else 0.0),
				1.0,
				g.clock
			)
		)
	var exit: LevelData.Extraction = g.world.extraction
	if exit != null and absf(exit.x - p.x) < 12.0 and absf(exit.y - p.y) < 12.0:
		var at: Vector3 = lamp_at(g, exit)
		var open := g.exit_ready()
		out.append(
			Effects.light("exit_open" if open else "exit_locked", at.x, at.y, at.z, 1.0, g.clock)
		)
	return out


## Where a device's lamp is: near the top of its quest prop (the last of its
## aim points, the prop's middle), else above its own point.
static func lamp_at(g: Game, device: Variant) -> Vector3:
	var points := GameUse.aim_points(g, device)
	var last: Vector3 = points[points.size() - 1]
	return Vector3(last.x, last.y, last.z + .5)


static func objective(g: Game) -> String:
	if g.in_hub:
		return "FACE A GATE AND PRESS E OR SPACE"
	if g.revisiting:
		return "COMPLETED / RETURN AT THE ROAD GATE"
	var runs: GameFeature = g.features.get("vehicle_runs")
	if runs != null:
		# At the wheel for a vehicle set piece (features/vehicle_runs.gd): its
		# start, or its next gate while it runs.
		var run_line: String = runs.call("objective", g.player)
		if run_line != "":
			return run_line
	if not g.level.rescue:
		var exit: LevelData.Extraction = g.world.extraction
		if exit == null:
			return ""
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in g.world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return ""
		var primary: Array = []
		for key: Variant in shutdown.requires:
			if not g.world.objective_side_tasks.has(key):
				primary.append(str(key))
		var pending: Array = []
		for key: Variant in primary:
			if not g.stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in g.world.stations:
				if station.id == pending[0]:
					if station.held != "" and not g.task_items.has(station.held):
						return "FIND THE PA PATCH LEAD AT THE RAFFLE OFFICE"
					return station.label
		if not pending.is_empty():
			return g.world.control_name
		for station: LevelData.Station in g.world.stations:
			if g.world.objective_side_tasks.has(station.id) and not g.stations_done.has(station.id):
				return station.label
		if not g.stations_done.has(shutdown.id):
			return shutdown.label
		var threats := 0
		for enemy: Enemy in g.wave:
			if enemy.alive:
				threats += 1
		return "CLEAR EXIT THREATS: %d" % threats if threats else exit.label
	if (g.boss == null or not g.boss.alive) and (g.jerry == null or not g.jerry.alive):
		return "RESCUE BESSIE"
	if g.jerry != null and g.jerry.alive and not g.jerry.dormant:
		return "PASTURE / BEAT JERRY"
	if g.keys.has("key_steel"):
		return "PASTURE / FIND BESSIE"
	if g.keys.has("key_brass"):
		return (
			"BARN / STEEL KEY AT THE FEED SCALE"
			if g.legacy_key_route
			else "STEEL KEY / EAST AT THE STOCK REGISTRY"
		)
	return "STANKY'S / BRASS KEY IN DISPATCH"


## The middle of the nearest cell to (x, y) a body can stand in out of deep
## water (rings out to 12 cells), or (x, y) itself when there is none.
static func shore_near(g: Game, x: float, y: float) -> Vector2:
	for r in range(1, 13):
		var best := Vector2.INF
		for cy in range(int(y) - r, int(y) + r + 1):
			for cx in range(int(x) - r, int(x) + r + 1):
				if maxi(absi(cx - int(x)), absi(cy - int(y))) != r:
					continue
				var at := Vector2(cx + .5, cy + .5)
				if cx < 1 or cy < 1 or cx >= g.world.width - 1 or cy >= g.world.height - 1:
					continue
				if g.world.blocked(at.x, at.y, .3) or g.world.deep_at(at.x, at.y):
					continue
				if at.distance_squared_to(Vector2(x, y)) < best.distance_squared_to(Vector2(x, y)):
					best = at
		if best != Vector2.INF:
			return best
	return Vector2(x, y)


## Where the objective pin points: four steps along the walk to `target`, and
## how many steps the whole walk is (-1 when it cannot be walked).
static func objective_route(g: Game, target: Vector2, target_z := NAN) -> Array:
	if g.route == null:
		return [target, -1]
	if is_nan(target_z) and g.world.geo != null:
		target_z = g.world.goal_floor(target)
	var opened := 0
	for door: LevelData.Door in g.world.doors:
		if door.opened:
			opened += 1
	var sig := [g.stations_done.size(), g.keys.size(), opened]
	if sig != g.route_sig:
		# A door opened or a key was found: the way may be different now.
		g.route_sig = sig
		g.route.origin = Vector2i(-1, -1)
		g.route.next_at = 0.0
	g.route.update(target.x, target.y, g.clock, target_z)
	var feet := g.world.stand(g.player)
	var steps := g.route.distance(g.player.x, g.player.y, feet)
	if steps >= FlowField.FAR:
		return [target, -1]
	return [g.route.waypoint(g.player.x, g.player.y, 4, [], feet), steps]
