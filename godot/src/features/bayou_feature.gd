## Gator Bayou's boss fight, as a feature (the behaviour is bayou_brains.gd):
## the lane an airboat run will take, marked on the water while the engine
## revs, and the punt gun's spread marked where it will land; the king's
## holler for his gators when he goes fightin' mad; his boat going up when he
## falls. Nothing to save: the marks come from the enemies' own state.
extends GameFeature


func id() -> String:
	return "bayou"


func attach() -> void:
	game.boss_enraged.connect(_mad)
	game.enemy_killed.connect(_down)


func _mad(enemy: Enemy) -> void:
	if not BayouBrains.is_king(enemy):
		return
	var woke := BayouBrains.call_gators(game, enemy.x, enemy.y, 28.0)
	game.message("THE KING HOLLERS FOR HIS GATORS!" if woke > 0 else "THE KING OPENS HER UP!", 2.8)


func _down(enemy: Enemy) -> void:
	if not BayouBrains.is_king(enemy):
		return
	# The airboat's tank goes: fire, the cage across the water, the crown gone.
	var z: float = game.world.stand(enemy)
	game.blasts.append(GameState.Blast.new(enemy.x, enemy.y, z + .6, "fire"))
	game.blasts.append(GameState.Blast.new(enemy.x + .5, enemy.y - .3, z + 1.1, "fire"))
	game.burst(enemy.x, enemy.y, z + .8, "splash", 30, 3.0)
	game.blast_flash = maxf(game.blast_flash, .7)
	game.sound_at("explosion", enemy.x, enemy.y, 1.0)
	game.message("LONG LIVE NOBODY. THE KING'S BOAT GOES UP!", 3.5)


func ground_marks() -> Array:
	var out: Array = []
	if game.world.sky != BayouBrains.SKY:
		return out
	for e: Enemy in game.enemies:
		if not BayouBrains.is_king(e) or not e.alive or e.windup <= 0.0 or e.aim_mark == null:
			continue
		var mark: Array = e.aim_mark
		var toward := atan2(float(mark[1]) - e.y, float(mark[0]) - e.x)
		var gap := Vector2(float(mark[0]) - e.x, float(mark[1]) - e.y).length()
		if BayouBrains.runs_on(e, e.attacks + 1, game.world, toward, gap):
			out.append_array(_lane(e, toward))
		else:
			for k in 3:
				var bearing := toward + (k - 1) * .18
				var reach := Vector2(float(mark[0]) - e.x, float(mark[1]) - e.y).length()
				var at := Vector2(e.x + cos(bearing) * reach, e.y + sin(bearing) * reach)
				out.append(
					Renderer.GroundMark.new(
						at.x,
						at.y,
						game.world.elevation(at.x, at.y) + .003,
						0.0,
						.6,
						.6,
						"mark_warning"
					)
				)
	return out


## The run's lane: as far as the boat would go before something stops it.
func _lane(e: Enemy, bearing: float) -> Array:
	var length := BayouBrains.lane(e, game.world, bearing)
	if length < .6:
		return []
	var out: Array = []
	for side: float in [-.42, .42]:
		var ox := -sin(bearing) * side
		var oy := cos(bearing) * side
		out.append(
			Renderer.GroundMark.new(
				e.x + ox + cos(bearing) * length / 2.0,
				e.y + oy + sin(bearing) * length / 2.0,
				game.world.stand(e) + .003,
				bearing,
				length / 2.0,
				.24,
				"mark_lane"
			)
		)
	return out
