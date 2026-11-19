## THE REVENUE MAN, the Moonshine Run's boss: a federal agent in a black suit
## and mirrored shades who has Granny Hooten's still wired to blow, with a
## tommy gun and a fire axe (enemies.cfg [revenue_man], bosses.cfg
## [revenue_man]).
##
## Kind `revenue_man`. His fight in the still cave (moonshine_plan.gd):
##   attacks      in turn by phase (PATTERN): TOMMY GUN, a burst raked across
##                the player (Enemy.volley, deputy slugs); AXE CHARGE, a run
##                at where the player stood when he wound up, the axe swung at
##                the end of it: in the rock he buries it and stands stuck a
##                moment (hits on him then count STUCK); TEAR GAS, canisters
##                lobbed round the player (moonshine_hands.gd).
##   phase 3      THE STILL BLOWS: Granny's still goes up, the shine spilled
##                round it burns, and the cave's roof comes down a rock at a
##                time on marked spots round the player (features/
##                boss_arenas.gd); the rocks hurt him too.
##   weak spot    his mirrored shades: a hit from in front of him at head
##                height counts WEAK (shot off, boss_gear, his bare eyes
##                count the same; the shades only hide where to aim).
##   HOG WILD     three canisters a volley, and a second rock on every fall.
class_name RevenueManMoves
extends BossMoves

const BossArenasFeature := preload("res://src/features/boss_arenas.gd")
const BossFightFeature := preload("res://src/features/boss_fight.gd")

## What he does, phase by phase, taken in turn by his attack count.
static var PATTERN: Dictionary = BossData.get_value("revenue_man", "pattern")
static var TELLS: Dictionary = BossData.get_value("revenue_man", "tells")
## The tommy gun: rounds a burst by phase, the fan's width, how hard each.
static var BURST: Array = BossData.get_value("revenue_man", "burst")
static var BURST_FAN: float = BossData.get_value("revenue_man", "burst_fan")
static var BURST_DAMAGE: int = BossData.get_value("revenue_man", "burst_damage")
## The axe charge: how fast, how long at most, how near the axe reaches, how
## hard by difficulty (EASY .. HOG WILD), how long stuck in the rock.
static var CHARGE_SPEED: float = BossData.get_value("revenue_man", "charge_speed")
static var CHARGE_TIME: float = BossData.get_value("revenue_man", "charge_time")
static var AXE_REACH: float = BossData.get_value("revenue_man", "axe_reach")
static var AXE_DAMAGE: Array = BossData.get_value("revenue_man", "axe_damage")
static var STUCK: float = BossData.get_value("revenue_man", "stuck")
static var STUCK_WEAK: float = BossData.get_value("revenue_man", "stuck_weak")
## The shades: how far off his facing a shot may come from, how high on him.
static var FRONT: float = BossData.get_value("revenue_man", "front")
static var HEAD: float = BossData.get_value("revenue_man", "head")
static var WEAK: float = BossData.get_value("revenue_man", "weak")
## His cooldown after an attack, by phase, of what the brain gives.
static var COOLDOWN: Array = BossData.get_value("revenue_man", "cooldown")


## What his attack number `n` is, at `phase`.
static func pick(n: int, phase: int) -> String:
	var row: Array = PATTERN.get(clampi(phase, 1, 3), PATTERN[1])
	return str(row[posmod(n, row.size())])


func stagger_hit(_e: Enemy) -> float:
	return 150.0


func stagger_rest(_e: Enemy) -> float:
	return 5.0


func phase_changed(e: Enemy, game: Game, phase: int) -> void:
	if phase == 3:
		var arenas: BossArenasFeature = game.features.get("boss_arenas")
		if arenas != null:
			arenas.turn(e)


func tick(e: Enemy, dt: float, game: Game) -> bool:
	e.set_note("tell", str(TELLS.get(pick(e.attacks, e.boss_phase), "TOMMY GUN")))
	var paced: int = e.get_note("paced", 0)
	if e.attacks != paced:
		e.set_note("paced", e.attacks)
		var cool: float = COOLDOWN[clampi(e.boss_phase - 1, 0, 2)]
		e.cooldown *= cool
	if e.has_note("stuck"):
		var until: float = e.get_note("stuck")
		if game.clock < until and e.alive:
			return true
		e.remove_note("stuck")
	if e.has_note("charge"):
		_charge(e, dt, game)
		return true
	return false


## The axe charge begins: at where the player stands now.
static func charge(e: Enemy, game: Game, direction: float) -> void:
	e.set_note("charge", [direction, game.clock + CHARGE_TIME])
	e.angle = direction
	e.cooldown = 1.5
	game.sound_at("revenue_man_rage", e.x, e.y, .7)


func _charge(e: Enemy, dt: float, game: Game) -> void:
	var row: Array = e.get_note("charge")
	var heading: float = row[0]
	var until: float = row[1]
	var p := game.player
	var moved := e.advance(dt, game, heading, CHARGE_SPEED)
	var near := Vector2(p.x - e.x, p.y - e.y).length()
	if near < AXE_REACH + e.radius and p.air < .6:
		var hurt: int = AXE_DAMAGE[clampi(game.difficulty, 0, 3)]
		game.damage(hurt, [e.x, e.y], "AXE")
		game.sound_at("crowbar_hit", p.x, p.y, 1.0)
		game.shake = minf(1.0, game.shake + .5)
		_end(e)
		e.recovery = .9
		return
	if moved < e.speed * CHARGE_SPEED * dt * .25:
		# Into the rock or a barrel: the axe stays in it a moment.
		e.set_note("stuck", game.clock + STUCK)
		game.sound_at("impact_stone", e.x, e.y, 1.0)
		game.shake = minf(1.0, game.shake + .3)
		var fight: BossFightFeature = game.features.get("boss_fight")
		if fight != null:
			var z: float = game.world.stand(e) + 1.0
			var tip := Vector2(e.x + cos(heading) * .6, e.y + sin(heading) * .6)
			fight.sparks(tip.x, tip.y, z, "spark", 14, 2.4)
			fight.sparks(tip.x, tip.y, z, "dust", 10, 1.4)
		game.message("HE BURIED THE AXE IN THE ROCK! LET HIM HAVE IT!", 1.8)
		_end(e)
		return
	if game.clock >= until:
		_end(e)
		e.recovery = .5


func _end(e: Enemy) -> void:
	e.remove_note("charge")


## His shades: a hit from in front, high on him. Stuck in the rock, anything.
func weak_spot(e: Enemy, game: Game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "fire" or how == "steam" or how == "energy":
		return 1.0
	if e.has_note("stuck"):
		return STUCK_WEAK
	var toward_shooter := atan2(from.y - e.y, from.x - e.x)
	if absf(Enemy.angle_delta(toward_shooter, e.angle)) > FRONT:
		return 1.0
	var up: float = (hit.z - game.world.stand(e)) / maxf(.5, e.height)
	return WEAK if up > HEAD else 1.0


## The axe raised over him as he charges; smoke off the tommy gun's barrel
## once he is mad.
func looks(e: Enemy, game: Game) -> Array:
	var out: Array = []
	if e.boss_phase < 2:
		return out
	var floor_z: float = game.world.stand(e)
	var muzzle := Vector2(e.x + cos(e.angle) * .5, e.y + sin(e.angle) * .5)
	var age := fposmod(game.clock * 1.2, 1.0)
	var s := View.Sprite.new(
		muzzle.x,
		muzzle.y,
		"fx_steam_%d" % mini(3, int(age * 4.0)),
		.25 + age * .3,
		floor_z + e.height * (.6 + age * .4)
	)
	s.translucent = true
	out.append(s)
	return out


func dying(e: Enemy, game: Game) -> void:
	e.remove_note("charge")
	e.remove_note("stuck")
	var floor_z: float = game.world.stand(e)
	var fight: BossFightFeature = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(e.x, e.y, floor_z + 1.2, "dust", 20, 2.2)
	game.message("THE REVENUE MAN'S DOWN! GET OUT BEFORE THE ROOF GOES!", 3.0)
