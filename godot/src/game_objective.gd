## Moved out of game_world.gd to keep it under the line limit; the originals call these.
class_name GameObjective
extends RefCounted


static func objective_target(g) -> Variant:
	if g.in_hub or g.revisiting:
		return null
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
		for key in shutdown.requires:
			if not g.world.objective_side_tasks.has(key):
				primary.append(String(key))
		var pending: Array = []
		for key in primary:
			if not g.stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in g.world.stations:
				if station.id == pending[0]:
					return g._station_goal(station)
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
			return g._station_goal(near)
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
				return g.shore_near(near2.x, near2.y)
			return Vector2(near2.x, near2.y)
		return Vector2(exit.x, exit.y)
	# Hickston: the same steps objective() names. The pin used to point at the
	# sheriff from the start, through the locked barn, while the words said to
	# fetch the brass key.
	var boss_up: bool = g.boss != null and g.boss.alive
	var jerry_up: bool = g.jerry != null and g.jerry.alive
	if not boss_up and not jerry_up:
		return Vector2(g.bessie.x, g.bessie.y) if g.bessie != null and g.bessie.hp > 0.0 else null
	if jerry_up and not g.jerry.dormant:
		return Vector2(g.jerry.x, g.jerry.y)
	if not g.keys.has("key_steel"):
		var wanted := "key_steel" if g.keys.has("key_brass") else "key_brass"
		for entry: Array in g.pickups:
			if String(entry[0]) == wanted:
				return Vector2(float(entry[1]), float(entry[2]))
	if boss_up:
		return Vector2(g.boss.x, g.boss.y)
	return Vector2(g.jerry.x, g.jerry.y)
