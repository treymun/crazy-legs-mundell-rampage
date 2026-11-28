## Shared checks for enemies arriving out of view.
class_name EnemySpawn
extends RefCounted


static func hidden(game: GameState, at: Vector2, floor_z: float, height: float) -> bool:
	for p: Player in game.players:
		if p.health <= 0.0:
			continue
		for fraction: float in [.5, .88]:
			if game.world.visible(p.x, p.y, at.x, at.y, p.eye, floor_z + height * fraction):
				return false
	return true


static func clear(game: GameState, at: Vector2, floor_z: float, radius: float) -> bool:
	for p: Player in game.players:
		if p.health > 0.0 and at.distance_squared_to(Vector2(p.x, p.y)) < 16.0:
			return false
	for e: Enemy in game.enemies:
		if not e.alive or e.dormant or absf(e.floor_z - floor_z) > 1.0:
			continue
		var gap := radius + e.radius + .25
		if at.distance_squared_to(Vector2(e.x, e.y)) < gap * gap:
			return false
	return true


static func face_entry(game: GameState, e: Enemy, player: Player = null) -> void:
	var p := player if player != null else game.player
	if p.flow != null:
		var way := p.flow.heading(e.x, e.y, e.floor_z)
		if not is_nan(way):
			e.angle = way
			e.face_left = cos(way) < -.24
