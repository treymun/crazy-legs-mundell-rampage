## MAW GLORB, the Mothership's queen and the last boss: her own three phases,
## the rolling pin, the hair dryer, stomps, the loose beam and her pod crew
## (features/mothership.gd, enemies.cfg [maw]). Her boss_phase follows hers.
##
## Kind `maw`. Her fight in the core (mothership_plan.gd, from her throne):
##   phase 3      out of the housecoat: HOT CURLERS (features/mothership.gd),
##                five red-hot curlers onto marked spots round the player, each a
##                green pop; and the core goes critical (features/boss_arenas.gd):
##                the beam column throbs and its pulses roll out across the deck,
##                to be jumped, burning her as they pass.
##   weak spot    her curlers, the top of her head: double, from anywhere; out of
##                the housecoat the girdle of power cells round her middle too.
##   HOG WILD     DOUBLE PIN: the rolling pin comes down a second time where the
##                player stood when it first landed (features/mothership.gd).
extends BossMoves

const BossArenasFeature := preload("res://src/features/boss_arenas.gd")
const BossFightFeature := preload("res://src/features/boss_fight.gd")

static var CURLERS: float = BossData.get_value("maw", "curlers")
static var GIRDLE: float = BossData.get_value("maw", "girdle")


func phase_changed(e: Enemy, game: Game, phase: int) -> void:
	if phase == 3:
		var arenas: BossArenasFeature = game.features.get("boss_arenas")
		if arenas != null:
			arenas.turn(e)


## The curlers piled on top of her head, and in her last phase the power cells
## round her middle: height on her, not a pixel of her picture.
func weak_spot(e: Enemy, game: Game, hit: Vector3, _from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy":
		return 1.0
	var up: float = (hit.z - game.world.stand(e)) / maxf(.5, e.height * e.variant)
	if up > .84:
		return CURLERS
	if e.boss_phase >= 3 and up > .38 and up < .62:
		return GIRDLE
	return 1.0


## Her curlers glowing hot; the power cells round her middle sparking once the
## housecoat is gone.
func looks(e: Enemy, game: Game) -> Array:
	var out: Array = []
	var p: Player = game.player
	var floor_z: float = game.world.stand(e)
	var tall := e.height * e.variant
	var toward := atan2(p.y - e.y, p.x - e.x)
	var frame := int(game.clock * 10.0)
	for k in 3:
		var a := toward + (k - 1) * .5
		var glint := View.Sprite.new(
			e.x + cos(a) * e.radius * .35,
			e.y + sin(a) * e.radius * .35,
			"fx_sparks_%d" % ((frame + k) % 3),
			.32,
			floor_z + tall * (.88 + .03 * k)
		)
		glint.glow = true
		out.append(glint)
	if e.boss_phase >= 3:
		for k in 4:
			var a := toward + (k - 1.5) * .45 + sin(game.clock * 3.0) * .1
			var cell := View.Sprite.new(
				e.x + cos(a) * (e.radius + .05),
				e.y + sin(a) * (e.radius + .05),
				"fx_energy_%d" % ((frame + k) % 4),
				.45,
				floor_z + tall * .45
			)
			cell.glow = true
			out.append(cell)
	return out


## Her curlers pop off as she goes down.
func dying(e: Enemy, game: Game) -> void:
	var top: float = game.world.stand(e) + e.height * e.variant * .9
	for k in 3:
		var a := k * TAU / 3.0
		game.blasts.append(
			GameState.Blast.new(e.x + cos(a) * .6, e.y + sin(a) * .6, top + k * .2, "energy")
		)
	var fight: BossFightFeature = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(e.x, e.y, top, "plasma", 24, 3.0)
