## Port of enemies.py: Hickston's townsfolk, flying pests and the pasture bosses.
##
## Every table mirrors the reference exactly; the AI methods are line-for-line
## ports so the same seeded rng calls happen in the same order.
class_name Enemy
extends RefCounted

## kind -> [health, speed, radius, height, hostile]
const KINDS := {
	"clone": [60, 1.25, .26, 1.55, true],
	"billy": [70, 1.40, .28, 1.58, true],
	"coot": [53, 1.06, .22, 1.51, true],
	"skeeter": [36, 2.55, .20, .46, true],
	"alien": [91, 1.40, .28, 1.56, true],
	"saucer": [75, 1.55, .32, .45, true],
	"boss": [620, 1.08, .52, 2.24, true],
	"jerry": [720, 1.16, .43, 1.94, true],
	"barker": [80, 1.15, .27, 1.69, true],
	"crawler": [34, 2.01, .21, .58, true],
	"millhand": [98, 1.31, .33, 1.73, true],
	"lantern": [69, 1.20, .28, .78, true],
	"boilerback": [99, .99, .34, 1.77, true],
	"chalk_spitter": [52, 1.43, .24, 1.38, true],
	"yard_deputy": [64, 1.23, .25, 1.63, true],
	"bottle_tosser": [51, 1.31, .23, 1.54, true],
	"chain_hand": [78, 1.03, .29, 1.72, true],
	"valve_rat": [63, 1.20, .26, 1.19, true],
	"rudy": [360, 1.28, .35, 1.85, true],
	"foreman": [420, .91, .42, 1.91, true],
	"baron": [480, .96, .43, 1.96, true],
	"chicken": [11, 1.05, .13, .52, false],
	"pig": [22, .70, .23, .66, false],
	"bessie": [100, 0, .22, .70, false],
}

const BOSS_TITLES := {
	"boss": "ALIEN SHERIFF",
	"jerry": "JERRY JONES",
	"rudy": "RUDY RACKET",
	"foreman": "SPLINTER FOREMAN",
	"baron": "COPPER BARON"
}

## Reach, stand-off, windup, recovery, cooldown, warning, release.
const SIGNATURES := {
	"yard_deputy": [7.3, 4.1, .61, .52, 1.54, "deputy_work", "deputy_shot"],
	"bottle_tosser": [7.8, 5.5, .73, .50, 1.86, "tosser_rattle", "tosser_throw"],
	"chain_hand": [4.15, 2.9, .82, .74, 1.65, "chain_raise", "chain_crack"],
	"valve_rat": [7.4, 4.2, .67, .60, 1.72, "rat_hiss", "rat_blow"],
}

const TELLS := {"rudy": "HORN SWEEP", "foreman": "CLEAR THE SAW LANES", "baron": "PIPE OUTLETS"}

const TURN_CELS := [
	"clone",
	"billy",
	"coot",
	"alien",
	"boss",
	"barker",
	"millhand",
	"boilerback",
	"chalk_spitter",
	"yard_deputy",
	"bottle_tosser",
	"chain_hand",
	"valve_rat",
	"rudy",
	"foreman",
	"baron",
	"jerry"
]
const FIDGET_CELS := ["clone", "billy", "coot"]
## Every kind in TURN_CELS also has a four-beat walk (w0..w3) and falling cels (die_0..die_2).
const DEATH_TIME := .50
## Creatures that tumble for two cels before they lie still.
const CREATURE_FALLS := ["crawler", "lantern"]
## Whose voice a kind has when it is hurt or killed; the rest use the material cues.
const VOICES := {
	"billy": "hick",
	"clone": "hick",
	"barker": "hick",
	"millhand": "hick",
	"boilerback": "hick",
	"yard_deputy": "hick",
	"bottle_tosser": "hick",
	"chain_hand": "hick",
	"valve_rat": "hick",
	"coot": "coot",
	"alien": "grey",
	"boss": "grey",
	"jerry": "jerry",
	"rudy": "rudy",
	"foreman": "foreman",
	"baron": "baron",
	"chalk_spitter": "spitter"
}
const VOICE_TAKES := {"hick": 3}
## Voices that only have a death cry.
const DEATH_ONLY := ["rudy", "foreman", "baron", "spitter"]

const RECOVERY_TIMES := {
	"boilerback": .64,
	"rudy": .75,
	"foreman": .82,
	"baron": .91,
	"boss": .33,
	"jerry": .38,
	"skeeter": .15,
	"crawler": .20,
	"millhand": .20,
	"yard_deputy": .52,
	"bottle_tosser": .50,
	"chain_hand": .74,
	"valve_rat": .60,
}

const SHELL_ACTORS := ["alien", "saucer", "boss", "crawler", "lantern", "skeeter", "valve_rat"]
const TOOL_ACTORS := ["boilerback", "foreman", "baron", "chain_hand", "millhand"]
const LOSS_RESPONDERS := ["coot", "yard_deputy", "bottle_tosser"]

## windup, lunge pace, reach, damage, cue, cooldown
const LUNGES := {
	"skeeter": [.22, 2.32, .93, 10, "skeeter_bite", 1.05],
	"crawler": [.25, 2.75, 1.02, 11, "crawler_click", 1.15],
	"millhand": [.24, 2.48, 1.28, 16, "millhand_hit", 1.46],
}

const AWAKE := {
	"clone": "clone_alert",
	"billy": "billy_alert",
	"coot": "coot_alert",
	"skeeter": "skeeter",
	"alien": "alien_alert",
	"saucer": "saucer_spot",
	"boss": "sheriff_spot",
	"yard_deputy": "deputy_work",
	"bottle_tosser": "tosser_rattle",
	"chain_hand": "chain_raise",
	"valve_rat": "rat_hiss"
}

const REACH := {
	"clone": 5.5,
	"billy": 4.5,
	"coot": 7.3,
	"skeeter": 2.15,
	"alien": 8.4,
	"saucer": 7.6,
	"boss": 10.0,
	"jerry": 9.5,
	"barker": 8.,
	"crawler": 2.25,
	"millhand": 2.15,
	"lantern": 7.4,
	"boilerback": 4.35,
	"chalk_spitter": 8.0,
	"rudy": 10.2,
	"foreman": 10.3,
	"baron": 10.5,
	"yard_deputy": 7.3,
	"bottle_tosser": 7.8,
	"chain_hand": 4.15,
	"valve_rat": 7.4
}

## [windup, cue]
const WINDUP := {
	"clone": [.25, "clone_bolt"],
	"billy": [.34, "enemy_pump"],
	"coot": [.32, "coot_cock"],
	"skeeter": [.37, "skeeter_dive"],
	"alien": [.35, "guard_charge"],
	"saucer": [.56, "saucer_charge"],
	"boss": [.53, "sheriff_siren"],
	"jerry": [.54, "whistle"],
	"barker": [.63, "barker_wind"],
	"crawler": [.36, "crawler_click"],
	"millhand": [.60, "millhand_rev"],
	"lantern": [.48, "lantern_charge"],
	"boilerback": [.78, "boiler_priming"],
	"chalk_spitter": [.64, "chalk_cough"],
	"rudy": [.86, "rudy_warn"],
	"foreman": [.95, "foreman_warn"],
	"baron": [.95, "baron_warn"],
	"yard_deputy": [.61, "deputy_work"],
	"bottle_tosser": [.73, "tosser_rattle"],
	"chain_hand": [.82, "chain_raise"],
	"valve_rat": [.67, "rat_hiss"]
}

const COMFORT := {
	"clone": 3.1,
	"billy": 1.7,
	"coot": 4.8,
	"skeeter": .95,
	"alien": 4.7,
	"saucer": 5.0,
	"boss": 4.45,
	"jerry": 4.0,
	"barker": 4.1,
	"crawler": .80,
	"millhand": 1.30,
	"lantern": 4.2,
	"boilerback": 3.15,
	"chalk_spitter": 5.6,
	"rudy": 6.2,
	"foreman": 6.9,
	"baron": 5.25,
	"yard_deputy": 4.1,
	"bottle_tosser": 5.5,
	"chain_hand": 2.9,
	"valve_rat": 4.2
}

const RANGED := [
	"alien",
	"saucer",
	"barker",
	"lantern",
	"chalk_spitter",
	"yard_deputy",
	"bottle_tosser",
	"chain_hand",
	"valve_rat",
	"boss",
	"jerry",
	"rudy",
	"foreman",
	"baron"
]

var kind := ""
var x := 0.0
var y := 0.0
var timer := 0.0
var pose := 0.0
var stun := 0.0
var alerted := false
var cooldown := .75
var angle := 0.0
var hp := 0.0
var explosive := false
var gait := 0.0
var face_left := false
var dormant := false
var windup := 0.0
var attacks := 0
var target = null

# Derived / bookkeeping (Enemy.__post_init__)
var speed := 0.0
var radius := 0.0
var height := 0.0
var hostile := false
var max_hp := 0.0
var route: Array = []
var route_slot := 0
var patrol_pause := 0.0
var aim_mark = null
var recovery := 0.0
var chase_turn := 0.0
var see_time := 0.0
var player_seen := false
var last_stride := 0.0
var pressure_guard := 0.0
var volley := 0
var volley_timer := 0.0
var volley_angle := 0.0
var volley_slope := 0.0
var heard = null
var retreat = null
var responded := false
var hit_flash := 0.0
var fled := false
var variant := 1.0
var died_at := -1.0
var struck_at := -1.0
var struck_sum := 0.0

## Mirror of the reference's read-only properties.
var alive: bool:
	get:
		return hp > 0.0 and not dormant

var z: float:
	get:
		if kind == "saucer":
			return .76 + .10 * sin(pose * 2.4)
		if kind == "skeeter":
			return (.61 if (windup > 0.0 or recovery > 0.0) else .84) + .13 * sin(pose * 6.5)
		if kind == "lantern":
			return .13 + .09 * sin(pose * 4.3)
		return 0.0


func _init(p_kind := "", px := 0.0, py := 0.0, p_angle := 0.0) -> void:
	kind = p_kind
	x = px
	y = py
	angle = p_angle
	var spec: Array = KINDS[kind]
	hp = float(spec[0])
	speed = float(spec[1])
	radius = float(spec[2])
	height = float(spec[3])
	hostile = bool(spec[4])
	max_hp = hp
	variant = 1.0 if BOSS_TITLES.has(kind) else .94 + fmod(x * 13.1 + y * 7.7, 1.0) * .11


static func angle_delta(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


func wake(game, px: float, py: float) -> void:
	if dormant:
		return
	target = [px, py]
	heard = null
	if not alerted:
		alerted = true
		cooldown = maxf(.65, cooldown)
		if hostile and kind != "boss" and kind != "jerry":
			for ally in game.enemies:
				var other: Enemy = ally
				if (
					other != self
					and other.hostile
					and other.alive
					and not other.alerted
					and not other.dormant
					and sqrt(pow(other.x - x, 2) + pow(other.y - y, 2)) < 4.2
					and game.world.visible(other.x, other.y, x, y)
				):
					other.wake(game, px, py)
		if AWAKE.has(kind):
			game.sound_at(String(AWAKE[kind]), x, y, .9)
		if kind == "boss":
			game.message("THE COUNTY SHAKEDOWN / ALIEN SHERIFF", 3.5)
			game.sound.sting("shakedown_intro")


func hurt(amount: float, game, explosive_hit := false, pressure := false) -> void:
	if not alive or kind == "bessie":
		return
	var was_stunned := stun > 0.0
	hp = maxf(0.0, hp - amount)
	# Pellets and blast fragments land as separate hits in the same instant.
	if game.clock - struck_at > .06:
		struck_sum = 0.0
	struck_at = game.clock
	struck_sum += amount
	hit_flash = minf(.18, hit_flash + .075 + minf(.06, amount * .0016))
	var champion := BOSS_TITLES.has(kind)
	if hp > 0.0 and hostile and not champion and amount >= 20.0:
		var away := atan2(y - game.player.y, x - game.player.x)
		game.move_actor(
			self,
			cos(away) * .10 * minf(3.0, amount / 30.0),
			sin(away) * .10 * minf(3.0, amount / 30.0),
			radius
		)
	if (
		hp > 0.0
		and hostile
		and not champion
		and kind != "skeeter"
		and kind != "saucer"
		and kind != "crawler"
		and hp < max_hp * .22
		and not fled
		and game.rng.random() < .55
	):
		fled = true
		retreat_from(game, game.player.x, game.player.y)
	var interrupt := pressure and not champion and pressure_guard == 0.0 and windup > 0.0
	if interrupt:
		pressure_guard = 1.75
		stun = .36
		game.sound_at("pressure_interrupt", x, y, .76)
	elif not pressure:
		stun = .065 if champion else .13
	if hostile:
		wake(game, game.player.x, game.player.y)
		if (
			windup > 0.0
			and not champion
			and (
				interrupt
				or (not pressure and (amount >= 26.0 or kind == "skeeter" or kind == "crawler"))
			)
		):
			windup = 0.0
			aim_mark = null
			cooldown = .65 if interrupt else .32
	var floor_z: float = game.world.elevation(x, y)
	var burst_kind := (
		"plasma" if kind in ["alien", "saucer", "boss", "crawler", "lantern"] else "gore"
	)
	game.burst(x, y, floor_z + z + .56 * height, burst_kind, 4, .9)
	if hostile:
		var from := atan2(y - game.player.y, x - game.player.x)
		game.gore_fx.spray(
			x, y, floor_z + z + .56 * height, cos(from), sin(from), amount, burst_kind == "plasma"
		)
	var material := (
		"shell" if SHELL_ACTORS.has(kind) else "tool" if TOOL_ACTORS.has(kind) else "cloth"
	)
	if alive:
		if hostile and amount >= 14.0 and not was_stunned and not interrupt:
			game.sound_at(voice_cue("pain", material), x, y, .47)
		return
	explosive = explosive_hit
	died_at = game.clock
	# Overkill: far more than the body had left, all at once, takes it apart.
	if (
		game.gore
		and hostile
		and not BOSS_TITLES.has(kind)
		and kind != "skeeter"
		and kind != "saucer"
		and (explosive_hit or struck_sum >= maxf(48.0, max_hp * .7))
	):
		explosive = true
		game.gore_fx.burst(self)
	elif hostile and not explosive and kind != "skeeter" and kind != "saucer":
		game.gore_fx.bleed_out(self, burst_kind == "plasma")
	game.burst(
		x,
		y,
		floor_z + z + .5 * height,
		burst_kind,
		22 if explosive_hit else 9,
		2.6 if explosive_hit else 1.5
	)
	if hostile:
		var cue := "skeeter_pop" if kind == "skeeter" else voice_cue("down", material)
		game.sound_at(cue, x, y, .83)
		game.enemy_down(self)
	else:
		game.sound_at("chicken" if kind == "chicken" else "pig", x, y, .9)
		game.burst(
			x,
			y,
			floor_z + height * .6,
			"feather" if kind == "chicken" else "gore",
			27 if explosive_hit else 9,
			2.8 if explosive_hit else 1.4
		)


func advance(dt: float, game, direction: float, pace := 1.0) -> float:
	var ox := x
	var oy := y
	game.move_actor(
		self, cos(direction) * speed * dt * pace, sin(direction) * speed * dt * pace, radius
	)
	var moved := sqrt(pow(x - ox, 2) + pow(y - oy, 2))
	if moved > .001:
		gait += moved * 6.0
		last_stride = pose
		angle = direction
		if absf(cos(direction)) > .38:
			face_left = cos(direction) < 0.0
	return moved


func sidestep(dt: float, game, direction: float, pace: float, allow_reverse := true) -> void:
	if advance(dt, game, direction, pace) > dt * .12:
		return
	if allow_reverse:
		advance(dt, game, direction + PI, pace * .8)


func follow(dt: float, game, direction: float, pace: float) -> void:
	if chase_turn == 0.0 and advance(dt, game, direction, pace) > dt * .13:
		return
	var bias := 1 if sin(x * 1.3 + y * .93 + attacks) >= 0.0 else -1
	if chase_turn == 0.0:
		chase_turn = float(bias)
	for amount: float in [.61, 1.15, 1.60, -1.03, -1.58]:
		if advance(dt, game, direction + chase_turn * amount, pace * .83) > dt * .15:
			break
	if not game.world.blocked(x + .46 * cos(direction), y + .46 * sin(direction), radius):
		chase_turn = 0.0


func patrol(dt: float, game) -> void:
	if route.is_empty():
		return
	patrol_pause -= dt
	if patrol_pause > 0.0:
		return
	var point: Array = route[route_slot]
	if sqrt(pow(float(point[0]) - x, 2) + pow(float(point[1]) - y, 2)) < .19:
		route_slot = (route_slot + 1) % route.size()
		patrol_pause = .5 if (kind == "skeeter" or kind == "saucer") else 1.3
		return
	follow(
		dt, game, atan2(float(point[1]) - y, float(point[0]) - x), .45 if kind == "coot" else .55
	)


func noise_step(dt: float, game) -> bool:
	if heard == null:
		return false
	var state: Array = heard
	var hx: float = state[0]
	var hy: float = state[1]
	if game.clock >= float(state[3]):
		heard = null
		return false
	var heading := atan2(hy - y, hx - x)
	if not hostile:
		sidestep(dt, game, heading + PI, 1.55, false)
	else:
		angle = heading
		if game.clock >= float(state[2]) and sqrt(pow(hx - x, 2) + pow(hy - y, 2)) > .48:
			follow(dt, game, heading, .76)
	return true


func retreat_from(game, px: float, py: float) -> void:
	responded = true
	var bearing := atan2(y - py, x - px)
	if target != null:
		var tx: float = target[0]
		var ty: float = target[1]
		for offset: float in [0.0, .58, -.58, 1.08, -1.08]:
			var dx := cos(bearing + offset)
			var dy := sin(bearing + offset)
			var probe_x := x + dx * .96
			var probe_y := y + dy * .96
			if (
				not game.world.blocked(probe_x, probe_y, radius)
				and game.world.visible(x, y, probe_x, probe_y)
				and not game.world.visible(tx, ty, probe_x, probe_y)
			):
				px = x - dx * .42
				py = y - dy * .42
				break
	retreat = [px, py, game.clock + 1.20]


func tick(dt: float, game) -> void:
	if not alive or kind == "bessie":
		return
	pose += dt
	stun = maxf(0.0, stun - dt)
	recovery = maxf(0.0, recovery - dt)
	pressure_guard = maxf(0.0, pressure_guard - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	if volley:
		volley_timer -= dt
		if volley_timer <= 0.0:
			var deputy := kind == "yard_deputy"
			var sweep := 1 if attacks % 2 else -1
			var bearing := volley_angle + (.023 if deputy else sweep * (.153 - volley * .061))
			var ground_z: float = game.world.elevation(x, y)
			var sx := x + cos(bearing) * .42
			var sy := y + sin(bearing) * .42
			var sz := ground_z + (.91 if deputy else 1.30)
			if not game.world.blocked(sx, sy, .045, sz):
				game.launch(
					sx,
					sy,
					sz,
					bearing,
					8.4 if deputy else 6.8,
					"deputy_slug" if deputy else "rudy_horn",
					volley_slope,
					true,
					8
				)
			if deputy:
				game.sound_at("deputy_shot", x, y, .82)
			volley -= 1
			volley_timer += .078
		return
	var p = game.player
	var dx: float = p.x - x
	var dy: float = p.y - y
	var distance := sqrt(dx * dx + dy * dy)
	var direction := atan2(dy, dx)
	if not hostile:
		if noise_step(dt, game):
			return
		timer -= dt
		if timer <= 0.0:
			timer = game.rng.uniform(.7, 2.1)
			angle += game.rng.uniform(-1.9, 1.9)
		var shy := 2.2 if kind == "chicken" else 1.35
		if distance < shy:
			angle = direction + PI
		elif kind == "pig" and timer > 1.05:
			return
		if advance(dt, game, angle, 1.42 if distance < shy else .72) < .0003:
			angle += PI * .71
		return

	cooldown -= dt
	var eye: float = game.world.elevation(x, y) + z + minf(.92, height * .72)
	see_time -= dt
	if see_time <= 0.0 or (0.0 < windup and windup <= dt):
		see_time = .079 + (radius - .2) * .051
		player_seen = distance < 14.0 and game.world.visible(x, y, p.x, p.y, eye, p.eye)
	var can_see := player_seen and distance < 14.0
	if not alerted and (game.spawn_grace > 0.0 or game.player_sheltered()):
		can_see = false
		player_seen = false
	var aggro_range := (5.5 if p.crouched else 8.4) + 2.2 * (1.0 if p.gut >= 66 else 0.0)
	if kind == "skeeter" or kind == "saucer":
		aggro_range += .9
	var watching := absf(angle_delta(direction, angle)) < 1.55 or distance < 2.65
	if can_see and (alerted or (distance < aggro_range and watching)):
		wake(game, p.x, p.y)
	if not alerted:
		if not noise_step(dt, game):
			patrol(dt, game)
		return

	var attack_range: float = REACH[kind]
	if windup > 0.0:
		var mark: Array = aim_mark if aim_mark != null else [p.x, p.y, p.eye]
		var tx: float = mark[0]
		var ty: float = mark[1]
		var tz: float = mark[2]
		var aimed := atan2(ty - y, tx - x)
		var lunge = LUNGES.get(kind)
		if (
			lunge != null
			and windup < float(lunge[0])
			and sqrt(pow(tx - x, 2) + pow(ty - y, 2)) > .36
		):
			advance(dt, game, aimed, float(lunge[1]))
		windup = maxf(0.0, windup - dt)
		if windup == 0.0:
			var committed := (
				TELLS.has(kind)
				or SIGNATURES.has(kind)
				or kind == "boilerback"
				or kind == "chalk_spitter"
			)
			if (
				stun == 0.0
				and (lunge != null or committed or (can_see and distance < attack_range + .90))
			):
				attack(game, aimed, sqrt(pow(tx - x, 2) + pow(ty - y, 2)), eye, tz)
				recovery = recovery_time(kind == "baron" and game.relief_open())
			else:
				cooldown = .43
			aim_mark = null
		return
	if stun > 0.0:
		return
	if recovery > .17 and (BOSS_TITLES.has(kind) or SIGNATURES.has(kind) or kind == "boilerback"):
		return
	if retreat != null:
		var rx: float = retreat[0]
		var ry: float = retreat[1]
		if game.clock < float(retreat[2]):
			follow(dt, game, atan2(y - ry, x - rx), .88)
			return
		retreat = null
	if can_see and distance <= attack_range and cooldown <= 0.0:
		var spec: Array = WINDUP[kind]
		windup = float(spec[0])
		var cue := String(spec[1])
		if kind == "boss" and hp < max_hp / 2.0:
			windup *= .83
		aim_mark = [p.x, p.y, p.eye]
		angle = direction
		face_left = cos(direction) < -.24
		game.sound_at(cue, x, y, .72)
		return

	if target == null:
		return
	var tx2: float = target[0]
	var ty2: float = target[1]
	var goal: float = COMFORT[kind]
	var approach := atan2(ty2 - y, tx2 - x)
	var strafe := PI / 2.0 if (attacks + int(pose / 1.45) + int(y)) % 2 else -PI / 2.0
	if not can_see or distance > goal:
		if sqrt(pow(tx2 - x, 2) + pow(ty2 - y, 2)) > .36:
			var pace := 1.21 if kind == "boss" and hp < 145.0 else 1.0
			var partner = game.partners.get(get_instance_id()) if can_see else null
			if (
				partner != null
				and partner[0].alive
				and partner[0].player_seen
				and partner[0].windup > 0.0
			):
				approach += float(partner[1]) * .48
			elif (
				can_see
				and (kind == "skeeter" or kind == "saucer" or kind == "billy" or kind == "crawler")
				and cooldown > .32
			):
				approach += strafe * (.39 if (kind == "skeeter" or kind == "crawler") else .23)
			follow(dt, game, approach, pace)
	elif (
		(kind == "coot" or kind == "skeeter" or kind == "chalk_spitter")
		and distance < float({"coot": 3., "skeeter": 1.18, "chalk_spitter": 3.3}[kind])
	):
		sidestep(dt, game, direction + PI + strafe * .26, .80 if kind == "coot" else 1.16, false)
	elif RANGED.has(kind) or (kind == "clone" and cooldown > .55):
		var pace2: float = {"saucer": 1.24, "alien": .62, "boss": .70, "jerry": .78}.get(kind, .42)
		sidestep(dt, game, direction + strafe, pace2)
		if TURN_CELS.has(kind):
			angle = direction + strafe * .29


func attack(game, direction: float, distance: float, eye: float, aim_z = null) -> void:
	attacks += 1
	if SIGNATURES.has(kind):
		signature_attack(game, direction, distance, eye, aim_z)
		return
	if kind == "boilerback" or kind == "chalk_spitter" or TELLS.has(kind):
		special_attack(game, direction, distance, eye, aim_z)
		return
	if LUNGES.has(kind):
		var lunge: Array = LUNGES[kind]
		var p = game.player
		var aim := atan2(p.y - y, p.x - x)
		var swing := kind == "skeeter" or absf(angle_delta(aim, direction)) < .61
		if (
			swing
			and sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) < float(lunge[2])
			and game.world.visible(x, y, p.x, p.y, eye, p.eye)
		):
			game.damage(int(lunge[3]), [x, y], "STRIKE")
			game.sound_at(String(lunge[4]), x, y)
		cooldown = float(lunge[5])
		return
	if RANGED.has(kind):
		fire_projectiles(game, direction, distance, eye, aim_z)
		return

	var chance := 0.0
	var damage := 0
	var cue := ""
	var delay := 0.0
	if kind == "billy":
		chance = maxf(.24, .88 - distance * .104)
		damage = 14 if distance < 2.4 else 8
		cue = "enemy_scatter"
		delay = 1.45
	elif kind == "coot":
		chance = maxf(.34, .83 - distance * .060)
		damage = 7
		cue = "enemy_pistol"
		delay = 1.58
	else:
		chance = maxf(.39, 1.0 - distance * .115)
		damage = 7 if distance > 2.0 else 10
		cue = "enemy"
		delay = 1.36 if attacks % 2 else 1.77
	cooldown = delay + game.rng.uniform(.04, .33)
	game.sound_at(cue, x, y, .90)
	game.burst(x + cos(direction) * radius, y + sin(direction) * radius, eye, "spark", 3, 1.2)
	var p2 = game.player
	var miss := absf(angle_delta(atan2(p2.y - y, p2.x - x), direction))
	var spread := .23 if kind == "billy" else .11 if kind == "coot" else .15
	chance *= (.79 if p2.crouched else 1.0) * maxf(0.0, 1.0 - miss / spread * .60)
	if miss < spread and game.rng.random() < chance:
		game.damage(damage, [x, y], "FIRE")


func signature_attack(game, direction: float, distance: float, eye: float, aim_z) -> void:
	var p = game.player
	var spec: Array = SIGNATURES[kind]
	cooldown = float(spec[4])
	game.sound_at(String(spec[6]), x, y, .9)
	var sx := x + cos(direction) * .34
	var sy := y + sin(direction) * .34
	if game.world.blocked(sx, sy, .045, eye):
		return
	if kind == "yard_deputy":
		var aim_target: float = p.eye if aim_z == null else float(aim_z)
		var slope := (aim_target - eye) * 8.4 / maxf(distance - .34, .6)
		game.launch(sx, sy, eye, direction - .023, 8.4, "deputy_slug", slope, true, 8, 1.08)
		volley = 1
		volley_timer = .23
		volley_angle = direction
		volley_slope = slope
	elif kind == "bottle_tosser":
		var flight := minf(1.32, maxf(.48, distance / 6.1))
		var speed2 := maxf(.45, (distance - .34) / flight)
		var mark: Array = aim_mark if aim_mark != null else [p.x, p.y]
		var target_z: float = game.world.elevation(float(mark[0]), float(mark[1]))
		game.launch(
			sx,
			sy,
			eye,
			direction,
			speed2,
			"fair_bottle",
			(target_z + .06 - eye) / flight + 2.75 * flight,
			true,
			0,
			flight
		)
	elif kind == "chain_hand":
		for swing: float in [-.19, 0.0, .19]:
			game.launch(sx, sy, eye - .12, direction + swing, 8.0, "chain_hook", 0.0, true, 7, .44)
	else:
		var ground_z: float = game.world.elevation(x, y)
		game.launch(sx, sy, ground_z + .31, direction, 6.3, "valve_slug", 0.0, true, 12, 1.17)


func special_attack(game, direction: float, distance: float, eye: float, aim_z) -> void:
	var p = game.player
	if kind == "chalk_spitter":
		var flight := minf(1.25, maxf(.51, distance / 6.15))
		var speed2 := maxf(.5, (distance - .18) / flight)
		var mark: Array = aim_mark if aim_mark != null else [p.x, p.y]
		var target_z: float = game.world.elevation(float(mark[0]), float(mark[1]))
		game.launch(
			x,
			y,
			eye,
			direction,
			speed2,
			"chalk_lob",
			(target_z + .07 - eye) / flight + 2.1 * flight,
			true,
			0,
			flight
		)
		cooldown = 1.88
		game.sound_at("chalk_spit", x, y)
	elif kind == "rudy":
		volley = 5
		volley_timer = .02
		volley_angle = direction if attacks % 2 else direction + .095
		var aim_target: float = p.eye if aim_z == null else float(aim_z)
		volley_slope = (aim_target - eye) * 6.8 / maxf(1.0, distance)
		cooldown = 1.42 if attacks % 2 else 1.73
		game.sound_at("rudy_horn", x, y)
	elif kind == "foreman":
		for lane: Array in saw_lanes(direction):
			if not game.world.blocked(float(lane[0]), float(lane[1]), .04):
				game.launch(
					float(lane[0]),
					float(lane[1]),
					game.world.elevation(float(lane[0]), float(lane[1])) + .58,
					float(lane[2]),
					7.6,
					"foreman_cut",
					0.0,
					true,
					13,
					1.38
				)
		cooldown = 1.69
		game.sound_at("foreman_cut", x, y)
	elif kind == "baron" and attacks % 2 == 1:
		var ports = game.pressure_ports(attacks - 1)
		var relieved: bool = game.relief_open()
		# pressure_ports() hands back the level's Vector2 points, not [x, y] pairs.
		for point: Vector2 in ports:
			game.add_hazard("steam", point.x, point.y, .94, .69, 1.08 if relieved else 1.35, 15)
			game.sound_at("pressure_vent", point.x, point.y, .76)
		cooldown = 1.95 if relieved else 1.58
	else:
		var rad := 4.45 if kind == "boilerback" else 5.45
		for spread: float in [-.23, 0.0, .23]:
			var sx := x + cos(direction + spread) * .72
			var sy := y + sin(direction + spread) * .72
			if not game.world.blocked(sx, sy, .04):
				game.burst(sx, sy, eye - .20, "dust", 6, 1.45)
		var aim := atan2(p.y - y, p.x - x)
		if (
			sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) < rad
			and absf(angle_delta(aim, direction)) < .47
			and game.world.visible(x, y, p.x, p.y, eye, p.eye)
		):
			game.damage(15 if kind == "boilerback" else 18, [x, y], "STEAM")
		cooldown = 1.60
		game.sound_at("boiler_release", x, y)


## Saw lanes as [x, y, bearing] triples.
func saw_lanes(direction: float, attack = null) -> Array:
	var side_x := -sin(direction)
	var side_y := cos(direction)
	var index := attacks if attack == null else int(attack)
	var nudges: Array = [-.85, .85] if index % 2 == 0 else [-.70, 0.0, .70]
	var out: Array = []
	for nudge: float in nudges:
		out.append([x + side_x * nudge, y + side_y * nudge, direction])
	return out


func fire_projectiles(game, direction: float, distance: float, eye: float, aim_z) -> void:
	var football := kind == "jerry"
	var kind_name := "football" if football else "plasma"
	var spread := .15
	var count := 1
	var speed2 := 0.0
	var damage := 0
	if football:
		count = 3 if hp < max_hp / 2.0 else 1
		speed2 = 7.1
		damage = 13
		cooldown = 1.02 if count == 3 else 1.32
	elif kind == "boss":
		count = 3 if hp < max_hp / 2.0 else 1
		speed2 = 5.7
		damage = 13
		cooldown = 1.28
	elif kind == "saucer":
		count = 2
		speed2 = 3.7
		damage = 8
		cooldown = 1.74
	elif kind == "barker":
		count = 3
		speed2 = 4.7
		damage = 8
		spread = .27
		cooldown = 1.70
		kind_name = "barker_bolt"
	elif kind == "lantern":
		count = 2
		speed2 = 4.15
		damage = 9
		spread = .12
		cooldown = 1.52
		kind_name = "lantern_bolt"
		aim_z = (game.player.eye if aim_z == null else float(aim_z)) - .37
	else:
		count = 1
		speed2 = 4.4
		damage = 9
		cooldown = .99 if attacks % 2 else 1.84
	for i in count:
		var theta := direction + (i - (count - 1) / 2.0) * spread
		var dx := cos(theta) * (radius + .055)
		var dy := sin(theta) * (radius + .055)
		var t := maxf(.12, distance / speed2)
		var aim_target: float = game.player.eye if aim_z == null else float(aim_z)
		var lift := (aim_target - eye) / t + (1.2 * t if football else 0.0)
		game.launch(x + dx, y + dy, eye, theta, speed2, kind_name, lift, true, damage)
	var cue: String = (
		{
			"jerry": "football_throw",
			"saucer": "saucer_shot",
			"boss": "sheriff_shot",
			"barker": "barker_blast",
			"lantern": "lantern_spit"
		}
		. get(kind, "plasma")
	)
	game.sound_at(cue, x, y)


## The cue for this kind being hurt ("pain") or killed ("down").
func voice_cue(moment: String, material: String) -> String:
	var voice := String(VOICES.get(kind, ""))
	if voice == "" or (moment == "pain" and DEATH_ONLY.has(voice)):
		return "actor_%s_%s" % [material, moment]
	var takes := int(VOICE_TAKES.get(voice, 1))
	if takes == 1:
		return "%s_%s" % [voice, moment]
	# No dice roll here: the take follows the fight so replays sound the same.
	return "%s_%s_%d" % [voice, moment, 1 + posmod(attacks + int(x * 3.0) + int(y * 5.0), takes)]


func recovery_time(relieved := false) -> float:
	if kind == "baron" and relieved:
		return 1.23
	if kind == "boss" and hp < max_hp / 2.0:
		return .51
	return float(RECOVERY_TIMES.get(kind, .095))


func sprite(observer = null, relieved := false, now := -1.0):
	if dormant:
		return null
	if not alive:
		if explosive or kind == "saucer" or kind == "skeeter":
			return null
		var fallen := now - died_at
		var cels := 5 if TURN_CELS.has(kind) else 2 if CREATURE_FALLS.has(kind) else 0
		var span := DEATH_TIME if cels == 5 else DEATH_TIME * .5
		if cels > 0 and died_at >= 0.0 and now >= died_at and fallen < span:
			var cel := "%s_die_%d" % [kind, mini(cels - 1, int(fallen / span * cels))]
			var falling := Renderer.Sprite.new(x, y, cel, height * variant, z)
			falling.flip = face_left
			return falling
		var down := Renderer.Sprite.new(x, y, "%s_down" % kind, height * .25, -.07)
		down.flip = face_left
		return down
	var recover := recovery_time(relieved) if recovery > 0.0 else 0.0
	var release := minf(.14, recover * .53)
	var frame = 0
	if hostile and stun > 0.0:
		frame = "pain"
	elif recover > 0.0 and recovery > recover - release:
		frame = "fire"
	elif windup > 0.0:
		frame = "aim"
	elif recover > 0.0 and TURN_CELS.has(kind):
		frame = "recover"
	elif kind == "saucer" or kind == "skeeter" or kind == "lantern":
		frame = int(pose * (16 if kind == "skeeter" else 5)) % 3 - 1
	elif stun > 0.0 or kind == "bessie" or pose - last_stride > .18:
		frame = 0
	elif TURN_CELS.has(kind):
		# Four-beat walk: contact, passing, contact, passing.
		frame = "w%d" % posmod(int(floor(gait / (PI * .5))), 4)
	else:
		frame = int(round(sin(gait)))
	var stem := kind
	var flip := face_left
	var walking: bool = frame is String and String(frame).begins_with("w")
	var plain: bool = frame is int and frame >= -1 and frame <= 1
	if observer != null and (plain or walking) and TURN_CELS.has(kind):
		var bearing := atan2(float(observer[1]) - y, float(observer[0]) - x)
		var relative := angle_delta(bearing, angle)
		var direction := mini(4, int(absf(relative) / (PI / 4.0) + .5))
		if direction:
			stem += ["", "_quarter", "_side", "_away", "_back"][direction]
		flip = relative < 0.0 and direction < 4
	if (
		frame is int
		and frame == 0
		and stem == kind
		and FIDGET_CELS.has(kind)
		and not alerted
		and fmod(pose + x * .37 + y * .13, 5.2) > 4.68
	):
		frame = "fidget"
	var out := Renderer.Sprite.new(x, y, "%s_%s" % [stem, str(frame)], height * variant, z)
	out.flip = flip
	out.body = hostile
	out.hurt = hit_flash
	return out
