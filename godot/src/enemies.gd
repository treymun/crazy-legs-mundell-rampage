## Port of enemies.py: Hickston's townsfolk, flying pests and the pasture bosses.
##
## Every table mirrors the reference exactly; the AI methods are line-for-line
## ports so the same seeded rng calls happen in the same order. The attacks
## are in enemy_attacks.gd, the hurt and wind-up cels in enemy_looks.gd, the
## tactics (cover, fetching help, brawls) in hand_tactics.gd and the tuning in
## enemy_tuning.gd.
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
## TURN_CELS, FIDGET_CELS and CREATURE_FALLS as sets (looked up every frame).
static var TURNS := {}
static var FIDGETS := {}
static var FALLS := {}
## Cel names by stem and frame (cel_name()), made once instead of every frame.
static var _cels := {}
const WALK_CELS := ["w0", "w1", "w2", "w3"]
const HEADINGS := ["", "_quarter", "_side", "_away", "_back"]
## How tall a fallen body's cel stands against the living one's.
const DOWN_SHARE := {"derby_champ": .45, "cow": .51, "mule": .38}
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
static var REACTIONS: Dictionary = HitData.section("reaction")


static func _static_init() -> void:
	load_tuning()


## Read the tuned values and definitions; DevTune (the dev console) calls it again after a change.
static func load_tuning() -> void:
	EnemyTuning.load_tuning()


## A section's values over those of the kind it names as its brain.
static func _definition(cfg: ConfigFile, kind: String, depth: int) -> Dictionary:
	return EnemyTuning.definition(cfg, kind, depth)


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
var target: Variant = null

# Derived / bookkeeping (Enemy.__post_init__)
var speed := 0.0
var radius := 0.0
var height := 0.0
var hostile := false
var max_hp := 0.0
var route: Array = []
var route_slot := 0
var patrol_pause := 0.0
var aim_mark: Variant = null
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
var heard: Variant = null
var retreat: Variant = null
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
var cover: Variant = null
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
## COUNTY RUN: an elite, and where it was last seen moving and last saw the
## player ([x, y, moved at, saw at]; county_spawner.gd). On the enemy, not
## keyed by instance id, so a snapshot carries them.
var county_elite := false
var county_watch: Array = []
var sunk := 0.0
## How it was killed (hurt()'s `how`) and from where, and how high its body
## is thrown this moment (features/corpses.gd moves the body after).
var killed_by := ""
var killed_from := Vector2.ZERO
var toss := 0.0
## Hit locations (hit_zones.gd, not saved): where the player's last hit struck
## ("head", "body", "arms", "legs"; "" not known) and from which side, the
## shot whose blast killed it and the blast's middle, how far this instant has
## reeled it, until when it limps, and its dropped weapon: until when it goes
## without, where it lies, when it stoops for it. A hat knocked off stays off.
var last_zone := ""
var last_side := ""
var killed_with := ""
var blast_at := Vector2.INF
var reel := 0
var reel_at := -1.0
var limp_until := -1.0
var disarmed_until := -1.0
var arm_at := Vector2.INF
var arm_roll := -1.0
var pick_at := -1.0
var hatless := false
## A critter's hop off the ground (features/critters.gd: a chicken flapping
## off, a cow bowled up by a blast).
var hop := 0.0
## An animal's own picture for now ("" none: a mule's kick, a tipped cow's
## fall) and its height's share (a cow going over), critters.gd.
var held_cel := ""
var squash := 1.0
## Its floor on a level with geometry (format 2), read by LevelData.stand().
var floor_z := 0.0
## Climbing (src/climbing.gd): the ladder it is on (-1 none) and which way,
## how high over floor_z it is on it or falling off an edge, how fast it
## falls, and the floor it stood on last tick.
var ladder := -1
var climb_up := true
var climb_z := 0.0
var fall := 0.0
var last_floor := 0.0
## A hand's part in the squad and its idle activity (Squad.Mind, src/squad.gd).
var mind: Squad.Mind = null
## Its stable id for snapshots (game.take_uid(); 0 until its first tick ends).
var uid := 0
## The player it is after till when (Players.hunted), and who hurt it till when.
var hunted: Player = null
var hunted_until := 0.0
var spite: Player = null
var spite_until := 0.0
## The clock of the last tick it took while far and calm (EnemyLod; -1: not
## calm), and a cover search left to go on (CoverSearch: [why, next spot,
## fallback x, y, ring]).
var lod_since := -1.0
var cover_hunt: Array = []
## Play a boss's moves, a gator's runs and the arena's fire keep on it, by
## name (plain values: get_note, set_note): carried like any field. Until
## pass 12 they were the object's metas, which no snapshot carries: a copy
## put back on one, or a late joiner's, parted at the next boss move or
## arena fire bite (net_soak_all.gd found it in a co-op boss fight).
var notes := {}

## Mirror of the reference's read-only properties.
var alive: bool:
	get:
		return hp > 0.0 and not dormant

var z: float:
	get:
		if climb_z > 0.0:
			return climb_z
		if hop > 0.0:
			return hop
		if sunk > 0.0:
			return -sunk
		if brain == "saucer":
			return .76 + .10 * sin(pose * 2.4)
		if brain == "skeeter":
			return (.61 if (windup > 0.0 or recovery > 0.0) else .84) + .13 * sin(pose * 6.5)
		if brain == "lantern":
			return .13 + .09 * sin(pose * 4.3)
		return 0.0


## A note kept on it (`fallback` when there is none), as get_meta was.
func get_note(key: String, fallback: Variant = null) -> Variant:
	return notes.get(key, fallback)


## Keeps `value` under `key` (null takes it away, as set_meta did).
func set_note(key: String, value: Variant) -> void:
	if value == null:
		notes.erase(key)
	else:
		notes[key] = value


func has_note(key: String) -> bool:
	return notes.has(key)


func remove_note(key: String) -> void:
	notes.erase(key)


func _init(p_kind := "", px := 0.0, py := 0.0, p_angle := 0.0) -> void:
	kind = p_kind
	var def: Dictionary = DEFS[kind]
	brain = str(def.get("brain", kind))
	x = px
	y = py
	angle = p_angle
	var spec: Array = KINDS[kind]
	hp = spec[0]
	speed = spec[1]
	radius = spec[2]
	height = spec[3]
	hostile = spec[4]
	max_hp = hp
	swims = def.get("swims", false)
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


## The nearest spot a step or three away the player cannot see, or null:
## of the hidden spots on the nearest ring that has one, the one least toward
## the player (CoverSearch, HANDS: CLASSIC's rings), all at once.
func find_cover(game: GameWorld) -> Variant:
	return CoverSearch.whole(self, game, false)


## Duck out of sight for a breath, if there is anywhere to duck.
## (CoverSearch: a few spots a tick; it ducks when the search ends.)
func take_cover(game: GameWorld, why := CoverSearch.DUCK) -> void:
	if game.clock < cover_ready or fetching != null or grudge != null:
		return
	CoverSearch.want(self, game, why)


static func angle_delta(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


func wake(game: GameWorld, px: float, py: float) -> void:
	if dormant:
		return
	target = [px, py]
	heard = null
	if hostile and not BOSS_TITLES.has(kind):
		hunt_until = maxf(hunt_until, game.clock + 6.0)
	if not alerted:
		if mind != null:
			Squad.startled(self, game as Game)
		alerted = true
		cooldown = maxf(.65, cooldown)
		if hostile and kind != "boss" and kind != "jerry":
			for other: Enemy in game.enemies:
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
			game.sound_at(str(AWAKE[kind]), x, y, .9)
		if brain == "boss":
			game.message("THE COUNTY SHAKEDOWN / ALIEN SHERIFF", 3.5)
			game.sound.sting("shakedown_intro")


## `by`: another of the county's (a stray shot, a brawl); null is the player.
func hurt(
	amount: float,
	game: GameWorld,
	explosive_hit := false,
	pressure := false,
	by: Enemy = null,
	how := ""
) -> void:
	if not alive or brain == "bessie":
		return
	amount = ShipAliens.soak(self, amount, game as Game, how, explosive_hit, pressure, by)
	# Head, body, arms or legs, where the player's hit struck (hit_zones.gd).
	amount *= HitZones.strike(self, game as Game, how, by)
	var champion := BOSS_TITLES.has(kind)
	if champion and by == null:
		# A boss's weak spot (or armour) where the player's hit struck.
		amount *= BossKit.weak(self, game as Game, how, amount)
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
		if not (tactical() and HandTactics.fetch_help(self, game)):
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
			BossKit.stagger(self, game as Game, from_x, from_y)
	if champion and hp > 0.0:
		if not enraged and hp < max_hp * .5:
			_enrage(game)
		BossKit.phase_check(self, game as Game)
	if hostile and by != null:
		# Caught by one of its own: it turns on them for a while.
		if tactical() and by.alive and by != self and alive:
			grudge = by
			grudge_until = game.clock + 7.0
			cover = null
			fetching = null
	elif hostile:
		grudge = null
		spite = game.player
		spite_until = game.clock + Players.SPITE
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
	var base: float = game.world.stand(self)
	var burst_kind := "plasma" if PLASMA.has(kind) else "gore"
	HitZones.splash(self, game as Game, x, y, base + z + .56 * height, burst_kind)
	if hostile and not HitZones.metal(self):
		var from := atan2(y - from_y, x - from_x)
		game.events.blood_sprayed.emit(
			x, y, base + z + .56 * height, cos(from), sin(from), amount, burst_kind == "plasma"
		)
	var material := (
		"shell" if SHELL_ACTORS.has(kind) else "tool" if TOOL_ACTORS.has(kind) else "cloth"
	)
	if by == null:
		game.struck(amount, hostile and not alive, champion)
	HitZones.land(self, game as Game, amount, by)
	if alive:
		if hostile and amount >= 14.0 and not was_stunned and not interrupt:
			game.sound_at(voice_cue("pain", material), x, y, .47)
		return
	# A blast that only just finishes one, or the cow launcher, throws it
	# whole (hit_zones.gd); the specks below are thrown as ever.
	var whole := explosive_hit and not HitZones.blast_gibs(self, game as Game)
	explosive = explosive_hit and not whole
	died_at = game.clock
	killed_by = "blast" if explosive_hit else how
	killed_with = game.blast_kind if explosive_hit else how
	killed_from = Vector2(from_x, from_y)
	# Overkill: far more than the body had left, all at once, takes it apart.
	if (
		game.gore
		and hostile
		and not BOSS_TITLES.has(kind)
		and kind != "skeeter"
		and kind != "saucer"
		and not whole
		and (
			explosive_hit
			or HitZones.overkill(self, game as Game, how)
			or how == "blade"
			or how == "ripsaw"
		)
	):
		explosive = true
		game.events.enemy_gibbed.emit(self)
	elif hostile and not explosive and kind != "skeeter" and kind != "saucer":
		game.events.enemy_bled_out.emit(self, burst_kind == "plasma")
	game.burst(
		x,
		y,
		base + z + .5 * height,
		burst_kind,
		22 if explosive_hit else 9,
		2.6 if explosive_hit else 1.5
	)
	if hostile:
		var cue := "skeeter_pop" if brain == "skeeter" else voice_cue("down", material)
		game.sound_at(cue, x, y, .83)
		if champion:
			_boss_falls(game, base)
		game.enemy_down(self)
		if brain == "nitro_huffer":
			SpeedwayHands.huffer_down(self, game as Game)
	else:
		game.sound_at(animal_voice(brain), x, y, .9)
		game.burst(
			x,
			y,
			base + height * .6,
			"feather" if brain == "chicken" else "gore",
			27 if explosive_hit else 9,
			2.8 if explosive_hit else 1.4
		)


func advance(dt: float, game: GameWorld, direction: float, pace := 1.0) -> float:
	var ox := x
	var oy := y
	if limp_until > game.clock:
		pace *= HitZones.LIMP_PACE
	if soak > 0.0:
		pace *= 1.0 - .35 * soak
		if soak > .35 and stun == 0.0 and game.rng.random() < dt * 1.2 * soak:
			# Down they go in the milk.
			stun = .6
			flinch = .35
			soak = maxf(0.0, soak - .25)
			game.sound_at("enemy_slip", x, y, .8)
			return 0.0
	if Variants.STUMBLE.has(kind):
		direction += Variants.wobble(self)
	pace *= Mud.pace(game, x, y)
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


func sidestep(
	dt: float, game: GameWorld, direction: float, pace: float, allow_reverse := true
) -> void:
	if advance(dt, game, direction, pace) > dt * .12:
		return
	if allow_reverse:
		advance(dt, game, direction + PI, pace * .8)


func follow(dt: float, game: GameWorld, direction: float, pace: float) -> void:
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


func patrol(dt: float, game: GameWorld) -> void:
	if route.is_empty():
		return
	patrol_pause -= dt
	if patrol_pause > 0.0:
		return
	var point: Array = route[route_slot]
	var px: float = point[0]
	var py: float = point[1]
	if sqrt(pow(px - x, 2) + pow(py - y, 2)) < .19:
		route_slot = (route_slot + 1) % route.size()
		patrol_pause = .5 if (brain == "skeeter" or brain == "saucer") else 1.3
		return
	follow(dt, game, atan2(py - y, px - x), .45 if brain == "coot" else .55)


func noise_step(dt: float, game: GameWorld) -> bool:
	if heard == null:
		return false
	var state: Array = heard
	var hx: float = state[0]
	var hy: float = state[1]
	var ready_at: float = state[2]
	var until: float = state[3]
	if game.clock >= until:
		heard = null
		return false
	var heading := atan2(hy - y, hx - x)
	if not hostile:
		sidestep(dt, game, heading + PI, 1.55, false)
	else:
		angle = heading
		if game.clock >= ready_at and sqrt(pow(hx - x, 2) + pow(hy - y, 2)) > .48:
			follow(dt, game, heading, .76)
	return true


func retreat_from(game: GameWorld, px: float, py: float) -> void:
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


## EnemyLod.step for this enemy (src/enemy_lod.gd): the step to tick it
## with this tick, 0 while far and calm it waits. Written here, on its own
## fields and in one function, for speed (a tick asks it of every enemy).
func lod_step(lod: EnemyLod, wdt: float, clock: float) -> float:
	if not (hp > 0.0) or dormant or brain == "bessie":
		# (Enemy.tick does nothing for these.)
		return wdt
	# While it waits only what others can change is asked again (`full`
	# false); the rest on the tick after each of its own.
	var full := lod_since < 0.0 or clock - lod_since <= wdt * 1.5
	if not EnemyLod.ON or not _lod_calm(lod, clock, full):
		lod.thought += 1
		if lod_since < 0.0:
			return wdt
		# Engaged again: this tick, with what it saved.
		var owed := clock - lod_since
		lod_since = -1.0
		return owed
	lod.thought += 1
	if lod_since < 0.0:
		# Calm from now: this tick it takes, then it waits.
		lod_since = clock
		return wdt
	# Between .6 and 1 of STEP, by its uid and how long it has lived (its
	# pose, which only moves when it ticks): each wait a little different,
	# so the far ones' turns never fall together for long.
	var since := clock - lod_since
	var turn := EnemyLod.STEP * (.6 + .4 * fposmod(uid * .6180339887 + pose * 3.7, 1.0))
	if since < turn:
		lod.thought -= 1
		lod.waited += 1
		return 0.0
	lod_since = clock
	return since


## Whether it may think less often now (EnemyLod's rules): far from every
## player who is up (`lod` holds this tick's), out of their sight lines'
## way, and nothing going on. `full` false asks only what others change (a
## player's place, an alarm, a shot heard, a hit, a critter's scare, the
## squad's calls): the rest only changes on its own ticks.
func _lod_calm(lod: EnemyLod, clock: float, full: bool) -> bool:
	var eyes := lod.eyes
	var far2 := lod.far2
	var view2 := lod.view2
	var n := eyes.size()
	var k := 0
	while k < n:
		var dx := x - eyes[k]
		var dy := y - eyes[k + 1]
		var d2 := dx * dx + dy * dy
		if d2 < far2:
			return false
		if d2 < view2 and dx * eyes[k + 2] + dy * eyes[k + 3] > EnemyLod.VIEW_COS * sqrt(d2):
			# Out in front of them, near enough to watch it walk.
			return false
		k += 4
	if alerted or heard != null or retreat != null or held_cel != "" or hop > 0.0:
		return false
	if struck_at >= 0.0 and clock - struck_at < EnemyLod.HURT:
		return false
	var m := mind
	if m != null and (m.investigate != null or m.regroup != null or m.flush_at > 0.0):
		return false
	if not full:
		return true
	if (
		windup > 0.0
		or volley != 0
		or stun > 0.0
		or recovery > 0.0
		or hit_flash > 0.0
		or flinch > 0.0
		or soak > 0.0
		or cover != null
		or grudge != null
		or fetching != null
		or ladder >= 0
		or climb_z > 0.0
		or disarmed_until >= 0.0
		or not cover_hunt.is_empty()
		or brain == "derby_champ"
	):
		return false
	return not (BOSS_TITLES.has(kind) or (m != null and (m.search_until > 0.0 or m.kick_at > 0.0)))


func tick(dt: float, game: Game) -> void:
	# (not alive, written out)
	if not (hp > 0.0) or dormant or brain == "bessie":
		return
	pose += dt
	stun = maxf(0.0, stun - dt)
	recovery = maxf(0.0, recovery - dt)
	pressure_guard = maxf(0.0, pressure_guard - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	flinch = maxf(0.0, flinch - dt)
	soak = maxf(0.0, soak - dt / 6.0)
	if mind != null and alerted:
		Squad.watch(self, game)
	if not cover_hunt.is_empty():
		CoverSearch.go_on(self, game)
	if BOSS_TITLES.has(kind) and BossKit.tick(self, dt, game):
		# Its own moves (src/bosses/) took this tick.
		return
	if brain == "derby_champ":
		DerbyChamp.tick(self, dt, game)
		return
	if (swims or game.world.sky == BayouBrains.SKY) and BayouBrains.tick(self, dt, game):
		return
	if disarmed_until >= 0.0 and HitZones.tick(self, dt, game):
		# Gone to fetch the weapon an arm hit made it drop.
		return
	if volley and brain == "revenue_man":
		# The Revenue Man's tommy gun (src/moonshine_hands.gd).
		volley_timer -= dt
		if volley_timer <= 0.0:
			MoonshineHands.tommy_round(self, game as Game)
			volley -= 1
			volley_timer += .07
		return
	if volley:
		volley_timer -= dt
		if volley_timer <= 0.0:
			var deputy := brain == "yard_deputy"
			var sweep := 1 if attacks % 2 else -1
			var bearing := volley_angle + (.023 if deputy else sweep * (.153 - volley * .061))
			var ground_z: float = game.world.stand(self)
			var sx := x + cos(bearing) * .42
			var sy := y + sin(bearing) * .42
			var sz := ground_z + (.91 if deputy else 1.12)
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
	# Climbing.enemy_step's plain case written out (on a ladder, falling or
	# off an edge it takes the tick): on its feet it only notes the floor.
	if ladder >= 0 or climb_z > 0.0 or (floor_z < last_floor - Climbing.DROP and hostile):
		if Climbing.enemy_step(self, dt, game):
			return
	else:
		last_floor = floor_z
	var p: Player = game.player
	var dx: float = p.x - x
	var dy: float = p.y - y
	var distance := sqrt(dx * dx + dy * dy)
	var direction := atan2(dy, dx)
	if not hostile:
		# (critters.gd has no class_name: steer() is called by name.)
		var critters: Object = game.features.get("critters")
		if critters != null and critters.call("steer", self, dt):
			# A hurt hog charging (features/critters.gd).
			return
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
	see_time -= dt
	var looking := see_time <= 0.0 or (0.0 < windup and windup <= dt)
	# The eye: unused by one that neither looks, sees nor is awake this tick.
	var eye := 0.0
	if looking or alerted or (player_seen and distance < 14.0):
		eye = game.world.stand(self) + z + minf(.92, height * .72)
	if looking:
		see_time = .079 + (radius - .2) * .051
		player_seen = distance < 14.0 and game.world.visible(x, y, p.x, p.y, eye, p.eye)
	var can_see := player_seen and distance < 14.0
	if not alerted and player_seen and (game.spawn_grace > 0.0 or game.player_sheltered()):
		can_see = false
		player_seen = false
	if can_see:
		# (How near it notices the player matters only while it sees them.)
		var aggro_range := (5.5 if p.crouched else 8.4) + 2.2 * (1.0 if p.gut >= 66 else 0.0)
		aggro_range += (float(game.sharpness) - 1.0) * 8.0
		if brain == "skeeter" or brain == "saucer":
			aggro_range += .9
		if mind != null and not alerted:
			aggro_range *= IdleLife.notice(self, game)
		var county: Object = game.features.get("events")
		if county != null and not alerted:
			# The dark of a blackout hides a player with no light on.
			var dark: float = county.call("notice", self, p)
			aggro_range *= dark
		var watching := absf(angle_delta(direction, angle)) < 1.55 or distance < 2.65
		if alerted or (distance < aggro_range and watching):
			wake(game, p.x, p.y)
			if not BOSS_TITLES.has(kind):
				hunt_until = game.clock + 9.0
	if not alerted:
		if (
			not (heard != null and noise_step(dt, game))
			and (mind == null or not Squad.calm(self, dt, game))
			and not route.is_empty()
		):
			patrol(dt, game)
		return

	if HandTactics.step(self, dt, game, can_see, distance):
		# A ladder, a door kicked in, a peek out of cover (src/hand_tactics.gd).
		return
	var attack_range: float = REACH[kind]
	if windup > 0.0:
		var mark: Array = aim_mark if aim_mark != null else [p.x, p.y, p.eye]
		var tx: float = mark[0]
		var ty: float = mark[1]
		var tz: float = mark[2]
		var aimed := atan2(ty - y, tx - x)
		var lunge: Array = LUNGES.get(kind, [])
		if (
			not lunge.is_empty()
			and windup < lunge[0]
			and sqrt(pow(tx - x, 2) + pow(ty - y, 2)) > .36
		):
			var lunge_pace: float = lunge[1]
			advance(dt, game, aimed, lunge_pace)
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
				and (
					not lunge.is_empty() or committed or (can_see and distance < attack_range + .90)
				)
			):
				attack(game, aimed, sqrt(pow(tx - x, 2) + pow(ty - y, 2)), eye, tz)
				recovery = recovery_time(brain == "baron" and game.relief_open())
				if RANGED.has(kind) and tactical() and game.rng.random() < HandTactics.duck(game):
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
	if grudge != null:
		# A raider shoots at a hand it feuds with (features/county_events.gd).
		var events: Object = game.features.get("events")
		if events != null and events.call("feud", self, dt):
			return
		if HandTactics.brawl(self, dt, game):
			return
	if fetching != null and HandTactics.fetch(self, dt, game, p):
		return
	if cover != null and HandTactics.hold_cover(self, dt, game, can_see, direction):
		return
	if retreat != null:
		var rx: float = retreat[0]
		var ry: float = retreat[1]
		var until: float = retreat[2]
		if game.clock < until:
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
		windup = spec[0]
		var cue := str(spec[1])
		if brain == "boss" and hp < max_hp / 2.0:
			windup *= .83
		aim_mark = [p.x, p.y, p.eye]
		angle = direction
		face_left = cos(direction) < -.24
		game.sound_at(cue, x, y, .72)
		return
	if mind != null and Squad.move(self, dt, game, can_see, distance):
		return

	if target == null:
		return
	var tx2: float = target[0]
	var ty2: float = target[1]
	var goal: float = COMFORT[kind]
	var approach := atan2(ty2 - y, tx2 - x)
	var strafe := PI / 2.0 if (attacks + int(pose / 1.45) + int(y)) % 2 else -PI / 2.0
	# Deep water on the straight line (deep_steer.gd): go round by the flow field.
	var water := can_see and DeepSteer.across(game, self, p)
	var lost: bool = not can_see or game.world.geo != null and game.world.apart(self, p)
	if (water or hunting and lost and game.clock < hunt_until) and game.flow != null:
		# Out of sight: come round by the open floor, not straight at the wall.
		var lead: float = game.flow.heading(x, y, floor_z)
		if not is_nan(lead):
			follow(dt, game, lead, .92)
			return
	if not can_see or distance > goal:
		if sqrt(pow(tx2 - x, 2) + pow(ty2 - y, 2)) > .36:
			var pace := 1.21 if brain == "boss" and hp < 145.0 else 1.25 if enraged else 1.0
			var partner: Array = game.partners.get(get_instance_id(), []) if can_see else []
			var mate: Enemy = null if partner.is_empty() else partner[0]
			if mate != null and mate.alive and mate.player_seen and mate.windup > 0.0:
				var side: float = partner[1]
				approach += side * .48
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
					approach += (
						HandTactics.spread_side(self, game)
						* clampf((distance - 2.0) / 3.0, 0.0, 1.0)
					)
			follow(dt, game, approach, pace)
	elif (
		(brain == "coot" or brain == "skeeter" or brain == "chalk_spitter")
		and distance < {"coot": 3., "skeeter": 1.18, "chalk_spitter": 3.3}[brain]
	):
		sidestep(dt, game, direction + PI + strafe * .26, .80 if brain == "coot" else 1.16, false)
	elif RANGED.has(kind) or (brain == "clone" and cooldown > .55):
		var pace2: float = {"saucer": 1.24, "alien": .62, "boss": .70, "jerry": .78}.get(brain, .42)
		sidestep(dt, game, direction + strafe, pace2)
		if TURNS.has(kind):
			angle = direction + strafe * .29


## Half its health gone: a roar, a stagger, then a harder fight.
func _enrage(game: GameWorld) -> void:
	enraged = true
	enraged_at = game.clock
	stun = maxf(stun, .9)
	windup = 0.0
	aim_mark = null
	cooldown = maxf(cooldown, .9)
	game.message(str(BOSS_TITLES[kind]) + " IS FIGHTIN' MAD!", 2.6)
	game.sound_at(("sheriff" if kind == "boss" else kind) + "_rage", x, y, 1.0)
	game.shake = minf(1.0, game.shake + .6)
	var base: float = game.world.stand(self)
	game.burst(x, y, base + height * .7, "spark", 16, 2.2)
	game.events.boss_enraged.emit(self)


## A boss going down: the world holds its breath, the ground shakes, it hollers.
func _boss_falls(game: GameWorld, base: float) -> void:
	game.hitstop = maxf(game.hitstop, .38)
	game.shake = minf(1.0, game.shake + .9)
	game.blast_flash = maxf(game.blast_flash, .55)
	game.sound_at(("sheriff" if kind == "boss" else kind) + "_death", x, y, 1.0)
	game.burst(x, y, base + height * .6, "spark", 30, 3.2)
	game.burst(x, y, base + height * .5, "plasma" if PLASMA.has(kind) else "gore", 26, 2.6)
	if brain == "derby_champ":
		DerbyChamp.falls(self, game as Game)
	if game.barks.enabled:
		game.callout = "BOSS DOWN!"
		game.callout_until = game.clock + 2.2


## How the gun that hit it moves it (REACTIONS), and the teat gun's soaking.
func _react(how: String, champion: bool, game: GameWorld, from_x: float, from_y: float) -> void:
	if how == "teat_gun":
		soak = minf(1.0, soak + (.04 if champion else .14))
		return
	var r: Array = REACTIONS.get(how, HitZones.MORE_REACTIONS.get(how, []))
	if r.is_empty():
		return
	var steady: float = Variants.STEADY.get(kind, 1.0)
	var scale := (.25 if champion else 1.0) * steady
	var shove: float = r[0]
	shove *= scale
	if shove > 0.0:
		var away := atan2(y - from_y, x - from_x)
		game.move_actor(self, cos(away) * shove, sin(away) * shove, radius)
	var held: float = r[1]
	held *= scale
	if how == "shotgun" and struck_sum >= 36.0:
		held = .32 * scale
	stun = maxf(stun, minf(held, .1) if champion else held)
	var flinched: float = r[2]
	flinch = maxf(flinch, flinched * scale)


## EnemyAttacks.attack (enemy_attacks.gd).
func attack(
	game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant = null
) -> void:
	EnemyAttacks.attack(self, game, direction, distance, eye, aim_z)


## EnemyAttacks.special_attack (enemy_attacks.gd).
func special_attack(
	game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant
) -> void:
	EnemyAttacks.special_attack(self, game, direction, distance, eye, aim_z)


## Saw lanes as [x, y, bearing] triples.
func saw_lanes(direction: float, attack: Variant = null) -> Array:
	var side_x := -sin(direction)
	var side_y := cos(direction)
	var index: int = attacks if attack == null else attack
	var nudges: Array = [-.85, .85] if index % 2 == 0 else [-.70, 0.0, .70]
	if enraged:
		# Fightin' mad: the gap closes and the outside lanes come in.
		nudges = [-1.4, -.70, 0.0, .70, 1.4] if index % 2 else [-1.25, -.42, .42, 1.25]
	var out: Array = []
	for nudge: float in nudges:
		out.append([x + side_x * nudge, y + side_y * nudge, direction])
	return out


## The cue for this kind being hurt ("pain") or killed ("down").
func voice_cue(moment: String, material: String) -> String:
	var voice := str(VOICES.get(kind, ""))
	if voice == "" or (moment == "pain" and DEATH_ONLY.has(voice)):
		return "actor_%s_%s" % [material, moment]
	var takes: int = VOICE_TAKES.get(voice, 1)
	if takes == 1:
		return "%s_%s" % [voice, moment]
	# No dice roll here: the take follows the fight so replays sound the same.
	return "%s_%s_%d" % [voice, moment, 1 + posmod(attacks + int(x * 3.0) + int(y * 5.0), takes)]


func recovery_time(relieved := false) -> float:
	if brain == "baron" and relieved:
		return 1.23
	if brain == "boss" and hp < max_hp / 2.0:
		return .51
	var time: float = RECOVERY_TIMES.get(kind, .095)
	return time


## What it looks like this frame. `into` (a sprite fresh from Game.pooled(),
## every field at its default) is filled in and handed back instead of a new one.
func sprite(
	observer: Variant = null, relieved := false, now := -1.0, into: View.Sprite = null
) -> View.Sprite:
	if dormant:
		return null
	var out := into if into != null else View.Sprite.new()
	out.x = x
	out.y = y
	out.flip = face_left
	if not alive:
		if explosive or brain == "saucer" or brain == "skeeter":
			return null
		var fallen := now - died_at
		var cels := 5 if TURNS.has(kind) else 2 if FALLS.has(kind) else 0
		var span := DEATH_TIME if cels == 5 else DEATH_TIME * .5
		var worn := Variants.stem(kind)
		if cels > 0 and died_at >= 0.0 and now >= died_at and fallen < span:
			var cel := cel_name(worn + "_die", mini(cels - 1, int(fallen / span * cels)))
			out.image = Variants.look(self, cel)
			out.height = height * variant
			out.z = z + toss
			return out
		out.image = Variants.look(self, cel_name(worn, "down"))
		out.height = height * DOWN_SHARE.get(brain, .25)
		out.z = toss - .07
		return out
	var turns := TURNS.has(kind)
	var recover := recovery_time(relieved) if recovery > 0.0 else 0.0
	var release := minf(.14, recover * .53)
	var frame: Variant = 0
	if hostile and (stun > 0.0 or (flinch > 0.0 and windup <= 0.0)):
		frame = "pain"
	elif recover > 0.0 and recovery > recover - release:
		frame = "fire"
	elif windup > 0.0:
		frame = "aim"
	elif recover > 0.0 and turns:
		frame = "recover"
	elif brain == "saucer" or brain == "skeeter" or brain == "lantern":
		frame = int(pose * (16 if brain == "skeeter" else 5)) % 3 - 1
	elif stun > 0.0 or brain == "bessie" or pose - last_stride > .18:
		frame = 0
	elif turns:
		# Four-beat walk: contact, passing, contact, passing.
		frame = WALK_CELS[posmod(int(floorf(gait / (PI * .5))), 4)]
	else:
		frame = int(roundf(sin(gait)))
	if mind != null and not alerted and frame is int and frame == 0:
		frame = IdleLife.frame(self, observer)
	var worn := Variants.stem(kind)
	var stem: String = worn if kind != "maw" else worn + ShipAliens.skin(self)
	var walking: bool = frame is String and str(frame).begins_with("w")
	var plain: bool = frame is int and frame >= -1 and frame <= 1
	if observer != null and (plain or walking) and turns:
		var seen_x: float = observer[0]
		var seen_y: float = observer[1]
		var bearing := atan2(seen_y - y, seen_x - x)
		var relative := angle_delta(bearing, angle)
		var direction := mini(4, int(absf(relative) / (PI / 4.0) + .5))
		if direction:
			stem += HEADINGS[direction]
		out.flip = relative < 0.0 and direction < 4
	if (
		frame is int
		and frame == 0
		and stem == worn
		and FIDGETS.has(kind)
		and not alerted
		and fmod(pose + x * .37 + y * .13, 5.2) > 4.68
	):
		frame = "fidget"
	var look := cel_name(stem, frame) if held_cel == "" else held_cel
	var boss := BOSS_TITLES.has(kind)
	if boss:
		look = BossLooks.cel(self, look)
	elif hostile:
		look = EnemyLooks.cel(self, look)
	out.image = Variants.look(self, look)
	# A cow going over: her picture squashed by the lean, never below .3.
	out.height = height * variant * maxf(.3, squash)
	out.z = z
	out.body = hostile
	out.hurt = hit_flash
	out.tell = EnemyLooks.tell(self, now)
	if windup > 0.0 and boss:
		# A boss winding up glows in a quickening beat (boss_kit.gd).
		out.hurt = maxf(hit_flash, BossKit.pulse(self))
	return out


## An animal's cry (a chicken, a hog, a cow, the mule).
static func animal_voice(of: String) -> String:
	return {"chicken": "chicken", "cow": "cow_moo", "mule": "mule_bray"}.get(of, "pig")


## "<stem>_<frame>", made once per pair.
static func cel_name(stem: String, frame: Variant) -> String:
	if not _cels.has(stem):
		_cels[stem] = {}
	var row: Dictionary = _cels[stem]
	var name: String = row.get(frame, "")
	if name == "":
		name = "%s_%s" % [stem, str(frame)]
		row[frame] = name
	return name
