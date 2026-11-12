## Port of enemies.py: Hickston's townsfolk, flying pests and the pasture bosses.
##
## Every table mirrors the reference exactly; the AI methods are line-for-line
## ports so the same seeded rng calls happen in the same order.
class_name Enemy
extends RefCounted

## Tuned and defined in data/tuning/enemies.cfg (see tuning.gd and the key
## list at the top of that file), loaded by load_tuning(): DEFS is kind -> its
## section's values, with what its `brain` kind sets filled in under them;
## KINDS is kind -> [hp, speed, radius, height, hostile]; WINDUP holds
## [windup, cue] and LUNGES the lunge numbers and its cue. The rest are the
## kinds with each key, read from DEFS.
static var DEFS := {}
static var KINDS := {}
static var DEATH_TIME: float
static var RECOVERY_TIMES := {}
static var LUNGES := {}
static var REACH := {}
static var WINDUP := {}
static var COMFORT := {}
static var BOSS_TITLES := {}
## Reach, stand-off, windup, recovery, cooldown, warning, release.
static var SIGNATURES := {}
static var TELLS := {}
## Every kind in TURN_CELS also has a four-beat walk (w0..w3) and falling cels (die_0..die_2).
static var TURN_CELS: Array = []
static var FIDGET_CELS: Array = []
## Creatures that tumble for two cels before they lie still.
static var CREATURE_FALLS: Array = []
## Whose voice a kind has when it is hurt or killed; the rest use the material cues.
static var VOICES := {}
static var VOICE_TAKES := {}
## Voices that only have a death cry.
static var DEATH_ONLY: Array = []
static var SHELL_ACTORS: Array = []
static var TOOL_ACTORS: Array = []
static var LOSS_RESPONDERS: Array = []
static var AWAKE := {}
static var RANGED: Array = []
static var PLASMA: Array = []
static var GREEN_GIBS: Array = []
## How likely a common enemy leaves a random food or drink.
static var LUCKY_CHANCE := .07
## Off, enemies that lose sight of the player go back to the old way (straight
## for where they last saw them); tools/first_minutes.gd compares the two.
static var hunting := true
## How each gun moves what it hits (`how` in hurt(): the gun's name for a
## bullet or a swing, the shot's kind for what flies): [shove in cells, stun
## seconds, flinch seconds]. Champions take a quarter. The sawed-off's shove
## is per pellet, so a full load at close range throws a body back.
const REACTIONS := {
	"shotgun": [.075, 0.0, 0.0],
	"revolver": [.12, .16, 0.0],
	"rifle": [.04, .1, 0.0],
	"riveter": [.08, .38, .3],
	"pressure_gun": [.32, 0.0, .35],
	"crowbar": [.28, .3, 0.0],
	"slingblade": [.42, .4, 0.0],
	"bowling": [.9, .9, .4],
	"blade": [.15, .2, 0.0],
	"ripsaw": [.06, .12, 0.0],
	"energy": [.05, .3, .25],
}


static func _static_init() -> void:
	load_tuning()


## Read the tuned values and definitions; Tuning.watch() calls it again after a change.
static func load_tuning() -> void:
	var path := Tuning.ENEMIES
	var cfg := Tuning.file(path)
	DEATH_TIME = Tuning.value(path, "death_time")
	VOICE_TAKES = Tuning.value(path, "voice_takes")
	DEATH_ONLY = Tuning.value(path, "death_only_voices")
	LUCKY_CHANCE = float(Tuning.value(path, "lucky_chance"))
	DEFS = {}
	for kind in Tuning.sections(path):
		DEFS[kind] = _definition(cfg, kind, 0)
	KINDS = {}
	RECOVERY_TIMES = {}
	LUNGES = {}
	REACH = {}
	WINDUP = {}
	COMFORT = {}
	BOSS_TITLES = {}
	SIGNATURES = {}
	TELLS = {}
	VOICES = {}
	AWAKE = {}
	TURN_CELS = []
	FIDGET_CELS = []
	CREATURE_FALLS = []
	SHELL_ACTORS = []
	TOOL_ACTORS = []
	LOSS_RESPONDERS = []
	RANGED = []
	PLASMA = []
	GREEN_GIBS = []
	var keyed := {
		"recovery_times": RECOVERY_TIMES,
		"lunges": LUNGES,
		"reach": REACH,
		"windup": WINDUP,
		"comfort": COMFORT,
		"title": BOSS_TITLES,
		"signature": SIGNATURES,
		"tell": TELLS,
		"voice": VOICES,
		"alert": AWAKE,
	}
	for kind: String in DEFS:
		var d: Dictionary = DEFS[kind]
		KINDS[kind] = [d["hp"], d["speed"], d["radius"], d["height"], d["hostile"]]
		for key: String in keyed:
			if d.has(key):
				keyed[key][kind] = d[key]
		var cels := String(d.get("cels", ""))
		if cels == "turn":
			TURN_CELS.append(kind)
		elif cels == "tumble":
			CREATURE_FALLS.append(kind)
		if d.get("fidget", false):
			FIDGET_CELS.append(kind)
		if d.get("struck", "") == "shell":
			SHELL_ACTORS.append(kind)
		elif d.get("struck", "") == "tool":
			TOOL_ACTORS.append(kind)
		if d.get("answers_losses", false):
			LOSS_RESPONDERS.append(kind)
		if d.get("ranged", false):
			RANGED.append(kind)
		if d.get("blood", "") == "plasma":
			PLASMA.append(kind)
		if d.get("green_gibs", false):
			GREEN_GIBS.append(kind)


## A section's values over those of the kind it names as its brain.
static func _definition(cfg: ConfigFile, kind: String, depth: int) -> Dictionary:
	var d := {}
	if cfg.has_section_key(kind, "brain") and depth < 4:
		var brain_kind := String(cfg.get_value(kind, "brain"))
		if cfg.has_section(brain_kind) and brain_kind != kind:
			d = _definition(cfg, brain_kind, depth + 1)
			d["brain"] = String(d.get("brain", brain_kind))
	for key in cfg.get_section_keys(kind):
		if key != "brain":
			d[key] = cfg.get_value(kind, key)
	return d


var kind := ""
## The kind whose behaviour this one has (its own kind unless enemies.cfg
## gives it a brain).
var brain := ""
var x := 0.0
var y := 0.0
var timer := 0.0
var pose := 0.0
var stun := 0.0
var alerted := false:
	set(value):
		if value != alerted:
			alerted = value
			Enemy.alert_changes += 1
## Counts every change of any enemy's `alerted`, so game_world.gd
## player_sheltered() asks all of them again only when one has changed.
static var alert_changes := 0
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
## How long the pain cel shows: a hard hit reads longer than the stun it
## causes, which is what the fight itself feels.
var flinch := 0.0
## Until when it hunts the player on the flow field after losing sight of them,
## and which side it swings out to when it closes in (game.gd sets it).
var hunt_until := 0.0
var flank := 0.0
var fled := false
var variant := 1.0
var died_at := -1.0
var struck_at := -1.0
var struck_sum := 0.0
## Tactics (the county's hands only, not bugs, saucers, animals or bosses):
## a spot out of the player's sight it is ducking to [x, y, until], and when
## it may duck again; a friend it ran to for help while badly hurt; another
## of the county's it is brawling after a stray shot or swing caught it; the
## side it is swinging out to so it does not come in on a friend's heels.
var cover = null
var cover_ready := 0.0
var fetching: Enemy = null
var fetch_until := 0.0
var grudge: Enemy = null
var grudge_until := 0.0
var spread := 0.0
var spread_next := 0.0
## Soaked by the teat gun (0 to 1): it slows them and they may slip and fall.
var soak := 0.0
## A boss past half its health: fightin' mad (faster, a harder pattern), and
## when it got that way.
var enraged := false
var enraged_at := -10.0
## A boss's fight (boss_kit.gd): its phase (1, 2 under half its health, 3
## under a fifth: from its health, so not saved), when it can next be staggered and
## when it last was, and when it went plum desperate.
var boss_phase := 1
var stagger_ready := 0.0
var staggered_at := -10.0
var desperate_at := -10.0
## Gator Bayou (bayou_brains.gd): it swims (deep water is no wall to it), and
## how far it is sunk in the water this moment (wading, lurking, a gator low).
var swims := false
var sunk := 0.0
## How it was killed (hurt()'s `how`) and from where, and how high its body
## is thrown this moment (features/corpses.gd moves the body after).
var killed_by := ""
var killed_from := Vector2.ZERO
var toss := 0.0

## Mirror of the reference's read-only properties.
var alive: bool:
	get:
		return hp > 0.0 and not dormant

var z: float:
	get:
		if sunk > 0.0:
			return -sunk
		if brain == "saucer":
			return .76 + .10 * sin(pose * 2.4)
		if brain == "skeeter":
			return (.61 if (windup > 0.0 or recovery > 0.0) else .84) + .13 * sin(pose * 6.5)
		if brain == "lantern":
			return .13 + .09 * sin(pose * 4.3)
		return 0.0


func _init(p_kind := "", px := 0.0, py := 0.0, p_angle := 0.0) -> void:
	kind = p_kind
	brain = String(DEFS[kind].get("brain", kind))
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
	swims = bool(DEFS[kind].get("swims", false))
	variant = 1.0 if BOSS_TITLES.has(kind) else .94 + fmod(x * 13.1 + y * 7.7, 1.0) * .11


## The county's own hands, who duck, fetch help and brawl.
func tactical() -> bool:
	return (
		hostile
		and not BOSS_TITLES.has(kind)
		and brain != "skeeter"
		and brain != "saucer"
		and brain != "crawler"
	)


## The nearest spot a step or three away the player cannot see, or null.
## Of the hidden spots on the nearest ring that has one, the one least toward
## the player (the first in heading order of those as little toward them). The
## headings are tried in that order and the first hidden one is taken: the same
## spot as testing all twelve, without the sight lines to the rest (a search of
## the whole four rings was about 6 ms).
func find_cover(game) -> Variant:
	var p = game.player
	var away := atan2(y - p.y, x - p.x)
	var order: Array = []
	for k in 12:
		order.append([absf(angle_delta(k * TAU / 12.0, away)), k])
	order.sort_custom(
		func(m: Array, n: Array) -> bool:
			return float(m[0]) < float(n[0]) or (m[0] == n[0] and int(m[1]) < int(n[1]))
	)
	for ring: float in [1.2, 2.0, 2.8, 3.6]:
		for pair: Array in order:
			var a := int(pair[1]) * TAU / 12.0
			var cx := x + cos(a) * ring
			var cy := y + sin(a) * ring
			if game.world.blocked(cx, cy, radius) or not game.world.visible(x, y, cx, cy):
				continue
			var head: float = game.world.elevation(cx, cy) + minf(.92, height * .72)
			if game.world.visible(p.x, p.y, cx, cy, p.eye, head):
				continue
			return Vector2(cx, cy)
	return null


## Duck out of sight for a breath, if there is anywhere to duck.
func take_cover(game) -> void:
	if game.clock < cover_ready or fetching != null or grudge != null:
		return
	var spot = find_cover(game)
	if spot != null:
		cover = [spot.x, spot.y, game.clock + game.rng.uniform(1.3, 2.4)]
		cover_ready = game.clock + game.rng.uniform(5.0, 8.0)


## Badly hurt: run for a friend who has not seen the fight yet and bring
## them back; with nobody near, just back off as before.
func fetch_help(game) -> bool:
	var best: Enemy = null
	var near := 12.0
	for other: Enemy in game.enemies:
		if (
			other != self
			and other.alive
			and other.tactical()
			and not other.alerted
			and not other.dormant
		):
			var d := sqrt(pow(other.x - x, 2) + pow(other.y - y, 2))
			if d < near:
				near = d
				best = other
	if best == null:
		return false
	fetching = best
	fetch_until = game.clock + 7.0
	cover = null
	return true


static func angle_delta(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


func wake(game, px: float, py: float) -> void:
	if dormant:
		return
	target = [px, py]
	heard = null
	if hostile and not BOSS_TITLES.has(kind):
		hunt_until = maxf(hunt_until, game.clock + 6.0)
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
		if brain == "boss":
			game.message("THE COUNTY SHAKEDOWN / ALIEN SHERIFF", 3.5)
			game.sound.sting("shakedown_intro")


## `by`: another of the county's (a stray shot, a brawl); null is the player.
func hurt(
	amount: float, game, explosive_hit := false, pressure := false, by: Enemy = null, how := ""
) -> void:
	if not alive or brain == "bessie":
		return
	amount = ShipAliens.soak(self, amount, game, how, explosive_hit, pressure, by)
	var champion := BOSS_TITLES.has(kind)
	if champion and by == null:
		# A boss's weak spot (or armour) where the player's hit struck.
		amount *= BossKit.weak(self, game, how)
	game.hit_point = Vector3.INF
	var from_x: float = game.player.x if by == null else by.x
	var from_y: float = game.player.y if by == null else by.y
	var was_stunned := stun > 0.0
	hp = maxf(0.0, hp - amount)
	# Pellets and blast fragments land as separate hits in the same instant.
	if game.clock - struck_at > .06:
		struck_sum = 0.0
	struck_at = game.clock
	struck_sum += amount
	hit_flash = minf(.18, hit_flash + .075 + minf(.06, amount * .0016))
	flinch = maxf(flinch, .08 if champion else .14 + minf(.16, amount * .004))
	if hp > 0.0 and hostile and not champion and amount >= 20.0:
		var away := atan2(y - from_y, x - from_x)
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
		and by == null
		and game.rng.random() < .55
	):
		fled = true
		if not (tactical() and fetch_help(game)):
			retreat_from(game, game.player.x, game.player.y)
	elif (
		hp > 0.0
		and by == null
		and tactical()
		and hp < max_hp * .75
		and cover == null
		and game.rng.random() < .45
	):
		take_cover(game)
	var interrupt := pressure and not champion and pressure_guard == 0.0 and windup > 0.0
	if interrupt:
		pressure_guard = 1.75
		stun = .36
		game.sound_at("pressure_interrupt", x, y, .76)
	elif not pressure:
		stun = .065 if champion else .13
	if by == null and hp > 0.0 and hostile:
		_react(how, champion, game, from_x, from_y)
		if champion:
			BossKit.stagger(self, game, from_x, from_y)
	if champion and hp > 0.0:
		if not enraged and hp < max_hp * .5:
			_enrage(game)
		BossKit.phase_check(self, game)
	if hostile and by != null:
		# Caught by one of its own: it turns on them for a while.
		if tactical() and by.alive and by != self and alive:
			grudge = by
			grudge_until = game.clock + 7.0
			cover = null
			fetching = null
	elif hostile:
		grudge = null
		wake(game, game.player.x, game.player.y)
	if hostile:
		if (
			windup > 0.0
			and not champion
			and (
				interrupt
				or (not pressure and (amount >= 26.0 or brain == "skeeter" or brain == "crawler"))
			)
		):
			windup = 0.0
			aim_mark = null
			cooldown = .65 if interrupt else .32
	var floor_z: float = game.world.elevation(x, y)
	var burst_kind := "plasma" if PLASMA.has(kind) else "gore"
	game.burst(x, y, floor_z + z + .56 * height, burst_kind, 4, .9)
	if hostile:
		var from := atan2(y - from_y, x - from_x)
		game.gore_fx.spray(
			x, y, floor_z + z + .56 * height, cos(from), sin(from), amount, burst_kind == "plasma"
		)
	var material := (
		"shell" if SHELL_ACTORS.has(kind) else "tool" if TOOL_ACTORS.has(kind) else "cloth"
	)
	if by == null:
		game.struck(amount, hostile and not alive, champion)
	if alive:
		if hostile and amount >= 14.0 and not was_stunned and not interrupt:
			game.sound_at(voice_cue("pain", material), x, y, .47)
		return
	explosive = explosive_hit
	died_at = game.clock
	killed_by = "blast" if explosive_hit else how
	killed_from = Vector2(from_x, from_y)
	# Overkill: far more than the body had left, all at once, takes it apart.
	if (
		game.gore
		and hostile
		and not BOSS_TITLES.has(kind)
		and kind != "skeeter"
		and kind != "saucer"
		and (
			explosive_hit
			or struck_sum >= maxf(48.0, max_hp * .7)
			or how == "blade"
			or how == "ripsaw"
		)
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
		var cue := "skeeter_pop" if brain == "skeeter" else voice_cue("down", material)
		game.sound_at(cue, x, y, .83)
		if champion:
			_boss_falls(game, floor_z)
		game.enemy_down(self)
		if brain == "nitro_huffer":
			SpeedwayHands.huffer_down(self, game)
	else:
		game.sound_at("chicken" if brain == "chicken" else "pig", x, y, .9)
		game.burst(
			x,
			y,
			floor_z + height * .6,
			"feather" if brain == "chicken" else "gore",
			27 if explosive_hit else 9,
			2.8 if explosive_hit else 1.4
		)


func advance(dt: float, game, direction: float, pace := 1.0) -> float:
	var ox := x
	var oy := y
	if soak > 0.0:
		pace *= 1.0 - .35 * soak
		if soak > .35 and stun == 0.0 and game.rng.random() < dt * 1.2 * soak:
			# Down they go in the milk.
			stun = .6
			flinch = .35
			soak = maxf(0.0, soak - .25)
			game.sound_at("enemy_slip", x, y, .8)
			return 0.0
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
		patrol_pause = .5 if (brain == "skeeter" or brain == "saucer") else 1.3
		return
	follow(
		dt, game, atan2(float(point[1]) - y, float(point[0]) - x), .45 if brain == "coot" else .55
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
	if not alive or brain == "bessie":
		return
	pose += dt
	stun = maxf(0.0, stun - dt)
	recovery = maxf(0.0, recovery - dt)
	pressure_guard = maxf(0.0, pressure_guard - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	flinch = maxf(0.0, flinch - dt)
	soak = maxf(0.0, soak - dt / 6.0)
	if BOSS_TITLES.has(kind) and BossKit.tick(self, dt, game):
		# Its own moves (src/bosses/) took this tick.
		return
	if brain == "derby_champ":
		DerbyChamp.tick(self, dt, game)
		return
	if BayouBrains.tick(self, dt, game):
		return
	if volley:
		volley_timer -= dt
		if volley_timer <= 0.0:
			var deputy := brain == "yard_deputy"
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
		var shy := 2.2 if brain == "chicken" else 1.35
		if distance < shy:
			angle = direction + PI
		elif brain == "pig" and timer > 1.05:
			return
		if advance(dt, game, angle, 1.42 if distance < shy else .72) < .0003:
			angle += PI * .71
		return

	cooldown -= dt * float(game.sharpness)
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
	aggro_range += (float(game.sharpness) - 1.0) * 8.0
	if brain == "skeeter" or brain == "saucer":
		aggro_range += .9
	var watching := absf(angle_delta(direction, angle)) < 1.55 or distance < 2.65
	if can_see and (alerted or (distance < aggro_range and watching)):
		wake(game, p.x, p.y)
		if not BOSS_TITLES.has(kind):
			hunt_until = game.clock + 9.0
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
				or brain == "boilerback"
				or brain == "chalk_spitter"
			)
			if (
				stun == 0.0
				and (lunge != null or committed or (can_see and distance < attack_range + .90))
			):
				attack(game, aimed, sqrt(pow(tx - x, 2) + pow(ty - y, 2)), eye, tz)
				recovery = recovery_time(brain == "baron" and game.relief_open())
				if RANGED.has(kind) and tactical() and game.rng.random() < .3:
					# A shot off, then down behind something before the reply.
					take_cover(game)
			else:
				cooldown = .43
			aim_mark = null
		return
	if stun > 0.0:
		return
	if recovery > .17 and (BOSS_TITLES.has(kind) or SIGNATURES.has(kind) or brain == "boilerback"):
		return
	if grudge != null and _brawl(dt, game):
		return
	if fetching != null and _fetch(dt, game, p):
		return
	if cover != null and _hold_cover(dt, game, can_see, direction):
		return
	if retreat != null:
		var rx: float = retreat[0]
		var ry: float = retreat[1]
		if game.clock < float(retreat[2]):
			follow(dt, game, atan2(y - ry, x - rx), .88)
			return
		retreat = null
	if not BOSS_TITLES.has(kind):
		# Lit dynamite on the ground: get clear of it.
		for danger: Vector3 in game.dangers:
			if (
				(danger.x - x) * (danger.x - x) + (danger.y - y) * (danger.y - y)
				< danger.z * danger.z
			):
				retreat = [danger.x, danger.y, game.clock + .9]
				return
	if can_see and distance <= attack_range and cooldown <= 0.0:
		var spec: Array = WINDUP[kind]
		windup = float(spec[0])
		var cue := String(spec[1])
		if brain == "boss" and hp < max_hp / 2.0:
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
	if hunting and not can_see and game.clock < hunt_until and game.flow != null:
		# Out of sight: come round by the open floor, not straight at the wall.
		var lead: float = game.flow.heading(x, y)
		if not is_nan(lead):
			follow(dt, game, lead, .92)
			return
	if not can_see or distance > goal:
		if sqrt(pow(tx2 - x, 2) + pow(ty2 - y, 2)) > .36:
			var pace := 1.21 if brain == "boss" and hp < 145.0 else 1.25 if enraged else 1.0
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
				and (
					brain == "skeeter"
					or brain == "saucer"
					or brain == "billy"
					or brain == "crawler"
				)
				and cooldown > .32
			):
				approach += strafe * (.39 if (brain == "skeeter" or brain == "crawler") else .23)
			elif can_see and not BOSS_TITLES.has(kind):
				# Swing out to one side while still far off, so a group closes from
				# more than one direction, and away from a friend close by.
				approach += flank * clampf((distance - 2.5) / 5.0, 0.0, 1.0)
				if tactical() and distance > 2.0:
					approach += _spread(game) * clampf((distance - 2.0) / 3.0, 0.0, 1.0)
			follow(dt, game, approach, pace)
	elif (
		(brain == "coot" or brain == "skeeter" or brain == "chalk_spitter")
		and distance < float({"coot": 3., "skeeter": 1.18, "chalk_spitter": 3.3}[kind])
	):
		sidestep(dt, game, direction + PI + strafe * .26, .80 if brain == "coot" else 1.16, false)
	elif RANGED.has(kind) or (brain == "clone" and cooldown > .55):
		var pace2: float = {"saucer": 1.24, "alien": .62, "boss": .70, "jerry": .78}.get(kind, .42)
		sidestep(dt, game, direction + strafe, pace2)
		if TURN_CELS.has(kind):
			angle = direction + strafe * .29


## Half its health gone: a roar, a stagger, then a harder fight.
func _enrage(game) -> void:
	enraged = true
	enraged_at = game.clock
	stun = maxf(stun, .9)
	windup = 0.0
	aim_mark = null
	cooldown = maxf(cooldown, .9)
	game.message(String(BOSS_TITLES[kind]) + " IS FIGHTIN' MAD!", 2.6)
	game.sound_at(("sheriff" if kind == "boss" else kind) + "_rage", x, y, 1.0)
	game.shake = minf(1.0, game.shake + .6)
	var floor_z: float = game.world.elevation(x, y)
	game.burst(x, y, floor_z + height * .7, "spark", 16, 2.2)
	game.boss_enraged.emit(self)


## A boss going down: the world holds its breath, the ground shakes, it hollers.
func _boss_falls(game, floor_z: float) -> void:
	game.hitstop = maxf(game.hitstop, .38)
	game.shake = minf(1.0, game.shake + .9)
	game.blast_flash = maxf(game.blast_flash, .55)
	game.sound_at(("sheriff" if kind == "boss" else kind) + "_death", x, y, 1.0)
	game.burst(x, y, floor_z + height * .6, "spark", 30, 3.2)
	game.burst(x, y, floor_z + height * .5, "plasma" if PLASMA.has(kind) else "gore", 26, 2.6)
	if brain == "derby_champ":
		DerbyChamp.falls(self, game)
	if game.barks.enabled:
		game.callout = "BOSS DOWN!"
		game.callout_until = game.clock + 2.2


## How the gun that hit it moves it (REACTIONS), and the teat gun's soaking.
func _react(how: String, champion: bool, game, from_x: float, from_y: float) -> void:
	if how == "teat_gun":
		soak = minf(1.0, soak + (.04 if champion else .14))
		return
	var r: Array = REACTIONS.get(how, [])
	if r.is_empty():
		return
	var scale := .25 if champion else 1.0
	var shove: float = float(r[0]) * scale
	if shove > 0.0:
		var away := atan2(y - from_y, x - from_x)
		game.move_actor(self, cos(away) * shove, sin(away) * shove, radius)
	var held: float = float(r[1]) * scale
	if how == "shotgun" and struck_sum >= 36.0:
		held = .32 * scale
	stun = maxf(stun, minf(held, .1) if champion else held)
	flinch = maxf(flinch, float(r[2]) * scale)


## A brawl with one of its own: close in and swing until one drops or it cools off.
func _brawl(dt: float, game) -> bool:
	if not grudge.alive or game.clock > grudge_until:
		grudge = null
		return false
	var gap := sqrt(pow(grudge.x - x, 2) + pow(grudge.y - y, 2))
	var heading := atan2(grudge.y - y, grudge.x - x)
	if gap > radius + grudge.radius + .25:
		follow(dt, game, heading, 1.08)
		return true
	angle = heading
	face_left = cos(heading) < 0.0
	if cooldown <= 0.0:
		cooldown = game.rng.uniform(.75, 1.15)
		game.sound_at("brawl_punch", x, y, .8)
		grudge.hurt(game.rng.uniform(8.0, 13.0), game, false, false, self)
	return true


## Running for a friend: once close, it hollers and both come back for the player.
func _fetch(dt: float, game, p) -> bool:
	if not fetching.alive or fetching.alerted or game.clock > fetch_until:
		fetching = null
		return false
	var gap := sqrt(pow(fetching.x - x, 2) + pow(fetching.y - y, 2))
	if gap < 2.4 or game.world.visible(x, y, fetching.x, fetching.y) and gap < 4.0:
		var friend := fetching
		fetching = null
		friend.wake(game, p.x, p.y)
		game.sound_at(String(AWAKE.get(kind, "billy_alert")), x, y, .85)
		hunt_until = game.clock + 9.0
		return false
	follow(dt, game, atan2(fetching.y - y, fetching.x - x), 1.12)
	return true


## Ducked out of sight: get there, keep low a moment, then come back out.
func _hold_cover(dt: float, game, can_see: bool, direction: float) -> bool:
	if game.clock > float(cover[2]):
		cover = null
		return false
	var cx: float = cover[0]
	var cy: float = cover[1]
	var gap := sqrt(pow(cx - x, 2) + pow(cy - y, 2))
	if gap > .25:
		follow(dt, game, atan2(cy - y, cx - x), 1.1)
		return true
	if can_see:
		# The player came round: no use hiding here.
		cover = null
		return false
	angle = direction
	return true


## Which way to swing out so as not to close in on a friend's heels: toward
## the side away from the nearest friend also coming in (0: no one close).
func _spread(game) -> float:
	if game.clock < spread_next:
		return spread
	spread_next = game.clock + .3
	spread = 0.0
	var p = game.player
	var best := 2.2
	for other: Enemy in game.enemies:
		if other == self or not other.alive or not other.alerted or not other.hostile:
			continue
		var d := sqrt(pow(other.x - x, 2) + pow(other.y - y, 2))
		if d < best:
			best = d
			var ax: float = x - p.x
			var ay: float = y - p.y
			var bx: float = other.x - p.x
			var by: float = other.y - p.y
			spread = .55 if ax * by - ay * bx > 0.0 else -.55
	return spread


func attack(game, direction: float, distance: float, eye: float, aim_z = null) -> void:
	attacks += 1
	if SpeedwayHands.attack(self, game, direction, distance, eye, aim_z):
		return
	if BayouBrains.attack(self, game, direction, distance, eye):
		return
	if ShipAliens.attack(self, game, direction, distance, eye, aim_z):
		return
	if SIGNATURES.has(kind):
		signature_attack(game, direction, distance, eye, aim_z)
		return
	if brain == "boilerback" or brain == "chalk_spitter" or TELLS.has(kind):
		special_attack(game, direction, distance, eye, aim_z)
		return
	if LUNGES.has(kind):
		var lunge: Array = LUNGES[kind]
		var p = game.player
		var aim := atan2(p.y - y, p.x - x)
		var swing := brain == "skeeter" or absf(angle_delta(aim, direction)) < .61
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
	if brain == "billy":
		chance = maxf(.24, .88 - distance * .104)
		damage = 14 if distance < 2.4 else 8
		cue = "enemy_scatter"
		delay = 1.45
	elif brain == "coot":
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
	var fan := .23 if brain == "billy" else .11 if brain == "coot" else .15
	# One of their own between them and the player takes it instead.
	var in_way: Enemy = null
	var nearest := distance
	for other: Enemy in game.enemies:
		if other == self or not other.alive or not other.hostile:
			continue
		var ox: float = other.x - x
		var oy: float = other.y - y
		var along := ox * cos(direction) + oy * sin(direction)
		if along > .3 and along < nearest:
			if absf(ox * sin(direction) - oy * cos(direction)) < other.radius + .06:
				nearest = along
				in_way = other
	if in_way != null:
		if game.rng.random() < maxf(.35, chance):
			in_way.hurt(float(damage), game, false, false, self)
		return
	chance *= (.79 if p2.crouched else 1.0) * maxf(0.0, 1.0 - miss / fan * .60)
	chance = minf(.97, chance * float(game.sharpness))
	if miss < fan and game.rng.random() < chance:
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
	if brain == "yard_deputy":
		var aim_target: float = p.eye if aim_z == null else float(aim_z)
		var slope := (aim_target - eye) * 8.4 / maxf(distance - .34, .6)
		game.launch(sx, sy, eye, direction - .023, 8.4, "deputy_slug", slope, true, 8, 1.08)
		volley = 1
		volley_timer = .23
		volley_angle = direction
		volley_slope = slope
	elif brain == "bottle_tosser":
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
			String(DEFS[kind].get("shot", "fair_bottle")),
			(target_z + .06 - eye) / flight + 2.75 * flight,
			true,
			0,
			flight
		)
	elif brain == "chain_hand":
		for swing: float in [-.19, 0.0, .19]:
			game.launch(sx, sy, eye - .12, direction + swing, 8.0, "chain_hook", 0.0, true, 7, .44)
	else:
		var ground_z: float = game.world.elevation(x, y)
		var slug := String(DEFS[kind].get("shot", "valve_slug"))
		game.launch(sx, sy, ground_z + .31, direction, 6.3, slug, 0.0, true, 12, 1.17)


func special_attack(game, direction: float, distance: float, eye: float, aim_z) -> void:
	var p = game.player
	if brain == "chalk_spitter":
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
	elif brain == "rudy":
		volley = 8 if enraged else 5
		volley_timer = .02
		volley_angle = direction if attacks % 2 else direction + .095
		var aim_target: float = p.eye if aim_z == null else float(aim_z)
		volley_slope = (aim_target - eye) * 6.8 / maxf(1.0, distance)
		cooldown = (1.42 if attacks % 2 else 1.73) * (.8 if enraged else 1.0)
		game.sound_at("rudy_horn", x, y)
	elif brain == "foreman":
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
		cooldown = 1.69 * (.85 if enraged else 1.0)
		game.sound_at("foreman_cut", x, y)
	elif brain == "baron" and (attacks % 2 == 1 or enraged):
		var ports = game.pressure_ports(attacks - 1)
		var relieved: bool = game.relief_open()
		# pressure_ports() hands back the level's Vector2 points, not [x, y] pairs.
		for point: Vector2 in ports:
			game.add_hazard("steam", point.x, point.y, .94, .69, 1.08 if relieved else 1.35, 15)
			game.sound_at("pressure_vent", point.x, point.y, .76)
		cooldown = (1.95 if relieved else 1.58) * (.8 if enraged else 1.0)
	else:
		var rad := 4.45 if brain == "boilerback" else 5.45
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
			game.damage(15 if brain == "boilerback" else 18, [x, y], "STEAM")
		cooldown = 1.60
		game.sound_at("boiler_release", x, y)


## Saw lanes as [x, y, bearing] triples.
func saw_lanes(direction: float, attack = null) -> Array:
	var side_x := -sin(direction)
	var side_y := cos(direction)
	var index := attacks if attack == null else int(attack)
	var nudges: Array = [-.85, .85] if index % 2 == 0 else [-.70, 0.0, .70]
	if enraged:
		# Fightin' mad: the gap closes and the outside lanes come in.
		nudges = [-1.4, -.70, 0.0, .70, 1.4] if index % 2 else [-1.25, -.42, .42, 1.25]
	var out: Array = []
	for nudge: float in nudges:
		out.append([x + side_x * nudge, y + side_y * nudge, direction])
	return out


func fire_projectiles(game, direction: float, distance: float, eye: float, aim_z) -> void:
	var football := brain == "jerry"
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
	elif brain == "boss":
		count = 3 if hp < max_hp / 2.0 else 1
		speed2 = 5.7
		damage = 13
		cooldown = 1.28
	elif brain == "saucer":
		count = 2
		speed2 = 3.7
		damage = 8
		cooldown = 1.74
	elif brain == "barker":
		count = 3
		speed2 = 4.7
		damage = 8
		spread = .27
		cooldown = 1.70
		kind_name = "barker_bolt"
	elif brain == "lantern":
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
		game.launch(
			x + dx,
			y + dy,
			eye,
			theta,
			speed2,
			kind_name,
			lift,
			true,
			damage,
			-1.0,
			get_instance_id()
		)
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
	if brain == "baron" and relieved:
		return 1.23
	if brain == "boss" and hp < max_hp / 2.0:
		return .51
	return float(RECOVERY_TIMES.get(kind, .095))


func sprite(observer = null, relieved := false, now := -1.0):
	if dormant:
		return null
	if not alive:
		if explosive or brain == "saucer" or brain == "skeeter":
			return null
		var fallen := now - died_at
		var cels := 5 if TURN_CELS.has(kind) else 2 if CREATURE_FALLS.has(kind) else 0
		var span := DEATH_TIME if cels == 5 else DEATH_TIME * .5
		if cels > 0 and died_at >= 0.0 and now >= died_at and fallen < span:
			var cel := "%s_die_%d" % [kind, mini(cels - 1, int(fallen / span * cels))]
			var falling := Renderer.Sprite.new(x, y, cel, height * variant, z + toss)
			falling.flip = face_left
			return falling
		var lying := height * (.45 if brain == "derby_champ" else .25)
		var down := Renderer.Sprite.new(x, y, "%s_down" % kind, lying, toss - .07)
		down.flip = face_left
		return down
	var recover := recovery_time(relieved) if recovery > 0.0 else 0.0
	var release := minf(.14, recover * .53)
	var frame = 0
	if hostile and (stun > 0.0 or (flinch > 0.0 and windup <= 0.0)):
		frame = "pain"
	elif recover > 0.0 and recovery > recover - release:
		frame = "fire"
	elif windup > 0.0:
		frame = "aim"
	elif recover > 0.0 and TURN_CELS.has(kind):
		frame = "recover"
	elif brain == "saucer" or brain == "skeeter" or brain == "lantern":
		frame = int(pose * (16 if brain == "skeeter" else 5)) % 3 - 1
	elif stun > 0.0 or brain == "bessie" or pose - last_stride > .18:
		frame = 0
	elif TURN_CELS.has(kind):
		# Four-beat walk: contact, passing, contact, passing.
		frame = "w%d" % posmod(int(floor(gait / (PI * .5))), 4)
	else:
		frame = int(round(sin(gait)))
	var stem: String = kind + ShipAliens.skin(self)
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
	if windup > 0.0 and BOSS_TITLES.has(kind):
		# A boss winding up glows in a quickening beat (boss_kit.gd).
		out.hurt = maxf(hit_flash, BossKit.pulse(self))
	return out
