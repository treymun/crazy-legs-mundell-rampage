## The Moonshine Run's revenue men where they do something the county's others
## do not (enemy_attacks.gd hands them their attack):
##   revenooer     a coot's snub .38, but every few shots, while the revenue
##                 radio on Buzzard Knob still talks, he calls it in instead:
##                 every hand within earshot comes for the player
##   revenue_man   the boss: his tommy gun burst, his axe charge and his tear
##                 gas, by the pattern of his phase (src/bosses/revenue_man.gd)
## The still buster needs nothing here (a lunge, enemies.cfg `lunges`) and the
## gas man is a bottle tosser throwing tear gas (enemies.cfg `shot`).
class_name MoonshineHands
extends RefCounted

## How far an agent's radio call carries, and which of his shots it takes.
const CALL_REACH := 18.0
const CALL_EVERY := 4
## The station that kills the radio (moonshine_plan.gd).
const RADIO := "radio"


## The attack of a kind handled here; false for every other kind.
static func attack(
	e: Enemy, game: Game, direction: float, distance: float, eye: float, aim_z: Variant
) -> bool:
	if e.kind == "revenooer" or e.kind == "tough_hoss":
		if e.attacks % CALL_EVERY == 2 and not game.stations_done.has(RADIO) and _call_in(e, game):
			e.cooldown = 2.2
			return true
		return false
	if e.brain != "revenue_man":
		return false
	var p := game.player
	match RevenueManMoves.pick(e.attacks - 1, e.boss_phase):
		"axe":
			RevenueManMoves.charge(e, game, direction)
		"gas":
			var count := 3 if int(game.difficulty) == 3 else 2
			for k in count:
				var spread := (k - (count - 1) / 2.0) * 1.6
				var side := direction + PI / 2.0
				var mx := p.x + cos(side) * spread
				var my := p.y + sin(side) * spread
				lob(e, game, mx, my, eye)
			game.sound_at("tosser_throw", e.x, e.y, .9)
			e.cooldown = 1.5
		_:
			var target: float = p.eye if aim_z == null else aim_z
			e.volley = RevenueManMoves.BURST[clampi(e.boss_phase - 1, 0, 2)]
			e.volley_timer = .05
			e.volley_angle = direction
			e.volley_slope = (target - eye) * 9.0 / maxf(1.0, distance)
			e.cooldown = 1.7
	return true


## A tear gas canister lobbed from `e` to land at (mx, my).
static func lob(e: Enemy, game: Game, mx: float, my: float, eye: float) -> void:
	var dist := Vector2(mx - e.x, my - e.y).length()
	var toward := atan2(my - e.y, mx - e.x)
	var flight := minf(1.3, maxf(.5, dist / 6.0))
	var speed := maxf(.45, (dist - .3) / flight)
	var sx := e.x + cos(toward) * .4
	var sy := e.y + sin(toward) * .4
	if game.world.blocked(sx, sy, .045, eye):
		return
	var target_z: float = game.world.elevation(mx, my)
	game.launch(
		sx,
		sy,
		eye,
		toward,
		speed,
		"tear_gas",
		(target_z + .06 - eye) / flight + 2.75 * flight,
		true,
		0,
		flight
	)


## One round of the boss's tommy gun burst (enemies.gd volley): fanned across
## the player, every other round heard.
static func tommy_round(e: Enemy, game: Game) -> void:
	var fan: float = RevenueManMoves.BURST_FAN
	var sweep := 1.0 if e.attacks % 2 else -1.0
	var bearing := e.volley_angle + sweep * (e.volley - 3.0) * fan
	var ground_z: float = game.world.stand(e)
	var sx := e.x + cos(bearing) * .5
	var sy := e.y + sin(bearing) * .5
	var sz := ground_z + 1.1
	if not game.world.blocked(sx, sy, .045, sz):
		game.launch(
			sx,
			sy,
			sz,
			bearing,
			9.5,
			"deputy_slug",
			e.volley_slope,
			true,
			RevenueManMoves.BURST_DAMAGE
		)
	if e.volley % 2 == 0:
		game.sound_at("tommy", e.x, e.y, .9)
	game.burst(sx, sy, sz, "spark", 2, .9)


## The radio call: every hand in reach that has not seen the fight comes.
## False when there was nobody left to call.
static func _call_in(e: Enemy, game: Game) -> bool:
	var p := game.player
	var called := 0
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile or other.alerted:
			continue
		if Enemy.BOSS_TITLES.has(other.kind):
			continue
		if sqrt(pow(other.x - e.x, 2) + pow(other.y - e.y, 2)) > CALL_REACH:
			continue
		other.wake(game, p.x, p.y)
		other.hunt_until = maxf(other.hunt_until, game.clock + 12.0)
		called += 1
	if called == 0:
		return false
	game.sound_at("sheriff_spot", e.x, e.y, 1.0)
	game.message("HE'S CALLIN' IT IN ON THE RADIO! (%d)" % called, 2.4)
	return true
