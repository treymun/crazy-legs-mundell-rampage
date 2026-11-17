## Port of weapons.py: the arsenal stats and the Armory state machine plus its
## low-resolution viewmodel presentation.
##
## Weapon state is identical to the reference (same capacity/reload/fire times,
## same pose selection). The viewmodel is composed straight into the 320x200
## frame: the graded, enlarged cel plus its rim, then muzzle flashes, smoke,
## sparks and the fuse bar.
class_name Weapons
extends RefCounted

const CROWBAR := 0
const REVOLVER := 1
const SHOTGUN := 2
const CROSSBOW := 3
const RIFLE := 4
const RIPSAW := 5
const ARMGUN := 6
const DYNAMITE := 7
const SLING := 8
const ROCKET := 9
const RIVETER := 10
const PRESSURE := 11
const BOWLING := 12
const KEG := 13
const COW := 14
const TEAT := 15
## The scoped deer rifle and the belt-fed machine gun (the 5v5 store's).
const HUNTER := 16
const MOWER := 17
## Each side's own guns in the 5v5 store: the deputies' issue .45, the
## Star .357 magnum, the outlaws' Hogleg .44, the riot pump, the squad car's
## drum-fed submachine gun, the shiners' grease gun, the patrol automatic
## rifle and the county marksman's scoped semi-automatic.
const COUNTY45 := 18
const STAR357 := 19
const HOGLEG := 20
const RIOT_PUMP := 21
const TOMMY := 22
const GREASE_GUN := 23
const PATROL_BAR := 24
const MARKSMAN := 25
## The 5v5 store's throwables (tactical_utility.gd): a flash, smoke, a
## firebomb and a decoy.
const FLASH_JAR := 26
const SMUDGE_POT := 27
const SHINE_COCKTAIL := 28
const FIRECRACKER_CAN := 29
## The 5v5 store's guns that fire bullets (their holes and their strikes
## sound as the .38's and the rifle's do).
const FRESH_BULLETS := [
	COUNTY45, STAR357, HOGLEG, RIOT_PUMP, TOMMY, GREASE_GUN, PATROL_BAR, MARKSMAN
]

## The guns, in weapons.cfg's order (the constants above are the first
## thirty); a section added at the end of the file is a new gun.
static var COUNT := 30
static var NAMES: Array = []
## Each gun's whole section: how it fires (Armory.fire reads it).
static var FIRING: Array = []
const RELOAD_POSES := ["open", "eject", "load", "close"]
const GUN_W := 320
const GUN_H := 120
## The crowbar, revolver and shotgun are photographed plates. Every other
## weapon is rendered through one of those plates' cameras and held by that
## plate's hand, so it draws at that plate's scale and with its nudge.
## Pixels to slide a viewmodel right and down so its muzzle sits under the
## crosshair instead of on it.
const HIP_PISTOL := Vector2(13, 9)
const HIP_LONG := Vector2(15, 11)
const VIEW_PIVOT := Vector2(160.0, 120.0)
## Where on a gun cel (shares of its size) a finisher turns it: the hand.
const TURN_GRIP := Vector2(.72, .92)

## Defined in data/tuning/weapons.cfg (see the key list there), loaded by
## load_tuning(): each gun's name and its reload and open sounds; the guns
## that are hand-loaded (CYCLE_GUNS: fire_time holds the whole cycle), that
## ease back after the kick, that show a muzzle flash.
static var LABELS: Array = []
## Magazine sizes before the pool change: a save written then may still hold
## rounds in `loaded`, which `Armory.tick` folds back into the pool. (Only the
## .38 and the sawed-off have a magazine and a reload now; every other gun
## fires straight from its ammo pool, `reserve`.)
static var SAVED_CAPACITY: Array = []
static var CYCLE_GUNS: Array = []
static var RECOVERY_GUNS: Array = []
static var MUZZLE_GUNS: Array = []
## Held and thrown as the dynamite is (weapons.cfg `thrown`).
static var THROWN_GUNS: Array = []
static var RELOAD_AUDIO := {}
static var OPEN_AUDIO := {}

## Tuned in data/tuning/weapons.cfg (see tuning.gd), loaded by load_tuning().
static var CAPACITY: Array = []
static var RELOAD_TIME: Array = []
static var FIRE_TIME: Array = []
static var MAX_RESERVE: Array = []
static var PICKUP_RESERVE: Array = []
static var RECOIL: Array = []
static var SHOT_NOISE: Array = []
static var KICK_HOLD: Array = []
static var VIEW_RISE: Array = []
static var SETTLE: Array = []
static var RETREAT: Array = []
static var RAISE_DEPTH: Array = []
static var DAMAGE := {}
static var MELEE := {}
static var VIEW_SCALES := {}
static var VIEW_SHIFT := {}
static var MUZZLES := {}
static var MUZZLE_STYLE := {}
## The shader view's own flash for a gun and its size (gun_flash.gd).
static var FLASH_ART := {}
static var FLASH_SIZE := {}
static var RELOAD_BEATS := {}
static var SHAKE := {}
## [all] sway_turn, sway_strafe, sway_limit, land_dip: the gun's weight.
static var SWAY := {}
static var DYNAMITE_FUSE: float
static var SHOTGUN_DAMAGE: int
static var SHOTGUN_PELLETS: int
static var GRIND_DAMAGE: int
static var VIEW_SCALE: float
static var VIEW_SINK: float
static var HOLD_FLOOR: float


static func _static_init() -> void:
	load_tuning()


## Read the tuned values; DevTune (the dev console) calls it again after a change.
static func load_tuning() -> void:
	var path := Tuning.WEAPONS
	NAMES = Array(Tuning.sections(path))
	COUNT = NAMES.size()
	var cfg := Tuning.file(path)
	FIRING = []
	for name: String in NAMES:
		var section := {}
		for key in cfg.get_section_keys(name):
			section[key] = cfg.get_value(name, key)
		FIRING.append(section)
	LABELS = Tuning.table(path, NAMES, "label")
	SAVED_CAPACITY = Tuning.table(path, NAMES, "saved_capacity")
	CYCLE_GUNS = Tuning.entries(path, NAMES, "cycle").keys()
	RECOVERY_GUNS = Tuning.entries(path, NAMES, "recovers").keys()
	MUZZLE_GUNS = Tuning.entries(path, NAMES, "muzzle_flash").keys()
	THROWN_GUNS = Tuning.entries(path, NAMES, "thrown").keys()
	RELOAD_AUDIO = Tuning.entries(path, NAMES, "reload_sounds")
	OPEN_AUDIO = Tuning.entries(path, NAMES, "open_sound")
	CAPACITY = Tuning.table(path, NAMES, "capacity")
	for i in COUNT:
		# A gun added after the ammo pool change has no older magazine to remember.
		if SAVED_CAPACITY[i] == null:
			SAVED_CAPACITY[i] = CAPACITY[i]
	RELOAD_TIME = Tuning.table(path, NAMES, "reload_time")
	FIRE_TIME = Tuning.table(path, NAMES, "fire_time")
	MAX_RESERVE = Tuning.table(path, NAMES, "max_reserve")
	PICKUP_RESERVE = Tuning.table(path, NAMES, "pickup_reserve")
	RECOIL = Tuning.table(path, NAMES, "recoil")
	SHOT_NOISE = Tuning.table(path, NAMES, "shot_noise")
	KICK_HOLD = Tuning.table(path, NAMES, "kick_hold")
	VIEW_RISE = Tuning.table(path, NAMES, "view_rise")
	SETTLE = Tuning.table(path, NAMES, "settle")
	RETREAT = Tuning.table(path, NAMES, "retreat")
	RAISE_DEPTH = Tuning.table(path, NAMES, "raise_depth")
	DAMAGE = Tuning.entries(path, NAMES, "damage")
	MELEE = Tuning.entries(path, NAMES, "melee")
	VIEW_SCALES = Tuning.entries(path, NAMES, "view_scales")
	VIEW_SHIFT = Tuning.entries(path, NAMES, "view_shift")
	MUZZLES = Tuning.entries(path, NAMES, "muzzles")
	MUZZLE_STYLE = Tuning.entries(path, NAMES, "muzzle_style")
	FLASH_ART = Tuning.entries(path, NAMES, "flash_art")
	FLASH_SIZE = Tuning.entries(path, NAMES, "flash_size")
	RELOAD_BEATS = Tuning.entries(path, NAMES, "reload_beats")
	SHAKE = Tuning.entries(path, NAMES, "shake")
	SWAY = {
		"turn": Tuning.value(path, "sway_turn"),
		"strafe": Tuning.value(path, "sway_strafe"),
		"limit": Tuning.value(path, "sway_limit"),
		"land": Tuning.value(path, "land_dip"),
		"hz": Tuning.value(path, "sway_hz"),
		"damp": Tuning.value(path, "sway_damp"),
		"spring_damp": Tuning.value(path, "spring_damp"),
	}
	DYNAMITE_FUSE = Tuning.value(path, "dynamite_fuse")
	SHOTGUN_DAMAGE = Tuning.value(path, "shotgun_damage")
	SHOTGUN_PELLETS = Tuning.value(path, "shotgun_pellets")
	GRIND_DAMAGE = Tuning.value(path, "grind_damage")
	VIEW_SCALE = Tuning.value(path, "view_scale")
	VIEW_SINK = Tuning.value(path, "view_sink")
	HOLD_FLOOR = Tuning.value(path, "hold_floor")
	# A gun drawn at a new size or place must be lit and scaled again.
	Armory.graded.clear()
	Armory.rim_cache.clear()
	Armory.composed.clear()
	Canvas.forget_textures()


static var _anchors: Dictionary = {}
## Set by Armory.draw for its pixel helpers: the canvas layer's coverage map,
## and whether what they paint goes under what is already there (the muzzle
## flash and smoke, painted after the gun on the layer canvas).
static var cover := PackedByteArray()
static var covering := false
static var under := false
## Set by Armory.draw on a Godot 2D canvas: the helpers below issue its
## commands instead of writing pixels.
static var painter: Canvas = null
## Where the gun in hand had its muzzle on the view (320-wide canvas) when last
## drawn firing: weapon_fx.gd starts tracers and the milk there.
static var muzzle_at := Vector2(-1, -1)


## True for a gun that fires from its ammo pool with no magazine.
static func pool_fed(slot: int) -> bool:
	return CAPACITY[slot] == 0 and slot not in [CROWBAR, SLING, DYNAMITE]


## Cached weapon_anchors.json (muzzle/case positions per pose).
static func muzzle_anchors() -> Dictionary:
	if _anchors.is_empty():
		var raw := FileAccess.get_file_as_string("res://assets_gen/weapon_anchors.json")
		var parsed: Variant = JSON.parse_string(raw)
		_anchors = parsed if parsed is Dictionary else {}
	return _anchors


## Map a source-cel coordinate through the viewmodel presentation transform.
static func view_point(x: float, y: float, px: float, py: float, s: float) -> Vector2:
	return Vector2(
		x + VIEW_PIVOT.x * (1.0 - s) + px * s, y + VIEW_PIVOT.y * (1.0 - s) + VIEW_SINK + py * s
	)


class Armory:
	var active := 1
	var owned: Array[bool] = []
	var loaded: Array[int] = []
	var reserve: Array[int] = []
	var cooldown := 0.0
	var reload := 0.0
	var recoil := 0.0
	var flash := 0.0
	var switch := 0.0
	var empty := 0.0
	var shot_age := 1.0
	var last_spent := 0
	var holstered := false
	var lower := 0.0
	var rifle_heat := 0.0
	var grinding := false
	var swing_hit := false
	var fuse := 0.0
	var tnt_latched := false
	var auto_switch := true
	var auto_reload := true
	## The lit, enlarged cels, their rims and their composed rows, by cel and
	## light level. Kept for the whole session, not per level: lighting a cel is
	## the slowest thing a frame ever does (some 15 ms the first time a gun is
	## seen in a given light), and a new level used to pay for all of it again.
	static var graded := {}
	static var rim_cache := {}
	static var composed := {}
	## So the first sight of a pose costs nothing on the frame: when a gun comes
	## out (or the light it is held in changes) a thread lights every pose of it
	## from that light up to the brightest a muzzle flash gives (_warm), and
	## draw() takes the results in when it is done.
	static var _warm_thread: Thread = null
	static var _warm_key := ""
	static var _poses := {}
	var boxes := {}

	func _init(start_slot := 1) -> void:
		for i in Weapons.COUNT:
			owned.append(i == Weapons.CROWBAR or i == Weapons.REVOLVER)
			loaded.append(6 if i == Weapons.REVOLVER else 0)
			reserve.append(30 if i == Weapons.REVOLVER else 0)
		active = start_slot

	func tick(dt: float, game: GameState) -> void:
		for slot in Weapons.COUNT:
			if loaded[slot] > Weapons.CAPACITY[slot]:
				# An older save's magazine: put the rounds back in the pool.
				var extra: int = loaded[slot] - Weapons.CAPACITY[slot]
				loaded[slot] = Weapons.CAPACITY[slot]
				var most: int = Weapons.MAX_RESERVE[slot]
				reserve[slot] = mini(most, reserve[slot] + extra)
		cooldown = maxf(0.0, cooldown - dt)
		recoil = maxf(0.0, recoil - 5.2 * dt)
		flash = maxf(0.0, flash - dt)
		switch = maxf(0.0, switch - dt)
		empty = maxf(0.0, empty - dt)
		var age_before := shot_age
		shot_age += dt
		if active in Weapons.CYCLE_GUNS and reserve[active] > 0 and reload <= 0.0:
			# The hand-loaded cycle after a shot: its three sounds on the beats.
			var span: float = Weapons.FIRE_TIME[active]
			var hold: float = Weapons.KICK_HOLD[active]
			if age_before < span and span > hold:
				var was: float = (age_before - hold) / (span - hold)
				var now: float = (shot_age - hold) / (span - hold)
				var cycle_cues: Array = Weapons.RELOAD_AUDIO[active]
				var cycle_beats: Array = Weapons.RELOAD_BEATS[active]
				for k in 3:
					if was < cycle_beats[k] and now >= cycle_beats[k]:
						game.sound.play(str(cycle_cues[k]), .78)
		if fuse > 0.0:
			fuse -= dt
			if fuse <= 0.0:
				fuse = 0.0
				cooldown = Weapons.FIRE_TIME[Weapons.DYNAMITE]
				shot_age = 0.0
				(game as GameCombat).throw_dynamite(0.0)
		var how: Dictionary = Weapons.FIRING[active]
		if str(how.get("fire", "")) == "melee" and swing_hit and shot_age >= how["swing_at"]:
			swing_hit = false
			var p: Player = game.player
			var table: Array = Weapons.MELEE[active]
			var damage: int = table[1 if game.sprint else 0]
			var melee_range: float = how["melee_range"]
			var melee_width: float = how["melee_width"]
			var reached: bool = (game as GameCombat).hitscan(
				p.view_angle(),
				(p.pitch + p.sway) / View.base_focal,
				damage,
				melee_range,
				melee_width
			)
			if reached:
				game.sound.play(
					"%s_hit" % ("sling" if active == Weapons.SLING else Weapons.NAMES[active])
				)
		rifle_heat = maxf(0.0, rifle_heat - dt * 1.8)
		lower = maxf(0.0, minf(1.0, lower + dt * (5.5 if holstered else -5.5)))
		if reload > 0.0:
			var reload_time: float = Weapons.RELOAD_TIME[active]
			var before: float = 1.0 - reload / reload_time
			reload -= dt
			var progress: float = 1.0 - reload / reload_time
			var cues: Array = Weapons.RELOAD_AUDIO.get(active, ["eject", "load", "close"])
			var beats: Array = Weapons.RELOAD_BEATS[active]
			for k in 3:
				if before < beats[k] and progress >= beats[k]:
					game.sound.play(str(cues[k]), .78)
			if reload <= 0.0:
				var i := active
				var cap: int = Weapons.CAPACITY[i]
				var count: int = mini(cap - loaded[i], reserve[i])
				loaded[i] += count
				reserve[i] -= count
				reload = 0.0

	func select(slot: int, game: GameWorld) -> void:
		if slot != active and owned[slot]:
			if fuse > 0.0:
				game.message("THROW THAT STICK FIRST!", .85)
				return
			active = slot
			reload = 0.0
			cooldown = 0.0
			flash = 0.0
			recoil = 0.0
			shot_age = 1.0
			grinding = false
			swing_hit = false
			tnt_latched = false
			holstered = false
			switch = .23
			game.sound.play("equip_" + str(Weapons.NAMES[slot]), .61)
			game.message(str(Weapons.LABELS[slot]), .95)
		elif not owned[slot]:
			game.message("YOU AIN'T GOT THAT ONE.", .85)

	func pickup(slot: int, game: GameWorld) -> bool:
		var fresh := not owned[slot]
		owned[slot] = true
		var amount: int = Weapons.PICKUP_RESERVE[slot]
		add_ammo(slot, amount)
		if fresh:
			loaded[slot] = Weapons.CAPACITY[slot]
			if auto_switch:
				select(slot, game)
			else:
				game.message(str(Weapons.LABELS[slot]), 1.35)
		return fresh

	func add_ammo(slot: int, amount: int) -> bool:
		var old := reserve[slot]
		var most: int = Weapons.MAX_RESERVE[slot]
		reserve[slot] = mini(most, old + amount)
		return reserve[slot] > old

	func cycle(direction: int, game: GameWorld) -> void:
		for offset in range(1, Weapons.COUNT):
			var slot := posmod(active + offset * direction, Weapons.COUNT)
			if owned[slot]:
				select(slot, game)
				return

	func start_reload(game: GameState) -> bool:
		var i := active
		if Weapons.CAPACITY[i] and reload <= 0.0 and reserve[i] and loaded[i] < Weapons.CAPACITY[i]:
			reload = Weapons.RELOAD_TIME[i]
			grinding = false
			game.sound.play(str(Weapons.OPEN_AUDIO[i]), .85)
			game.events.gun_reloading.emit(i)
			return true
		return false

	func fire(game: Game, both := false) -> void:
		var i := active
		if holstered:
			holstered = false
			switch = .20
			return
		if cooldown or reload or switch or game.player.health <= 0:
			return
		if i == Weapons.DYNAMITE:
			if fuse == 0.0 and not tnt_latched:
				if reserve[Weapons.CROSSBOW]:
					reserve[Weapons.CROSSBOW] -= 1
					fuse = Weapons.DYNAMITE_FUSE
					tnt_latched = true
					game.sound.play("match_strike")
					game.set_face("grin_rampage", .35)
				elif empty == 0.0:
					empty = .32
					game.sound.play("dry_tnt")
					game.message("OUT OF STICKS.", .72)
			return
		var grind := i == Weapons.RIPSAW and both
		var pool := Weapons.pool_fed(i)
		if ((Weapons.CAPACITY[i] and not loaded[i]) or (pool and not reserve[i])) and not grind:
			var started: bool = not pool and auto_reload and start_reload(game)
			if not started and empty == 0.0:
				empty = .34
				game.sound.play("dry_" + str(Weapons.NAMES[i]))
				game.message("DRY AS A BONE.", .7)
				game.barks.say(game, "empty")
			return
		var pair: bool = (
			both
			and (
				(i == Weapons.SHOTGUN and loaded[i] == 2)
				or (i == Weapons.RIVETER and reserve[i] >= 2)
			)
		)
		var spent := 0 if (grind or i in [Weapons.CROWBAR, Weapons.SLING]) else (2 if pair else 1)
		if grind:
			cooldown = .135
		elif i == Weapons.SHOTGUN and spent == 1 and loaded[i] == 2:
			cooldown = .26
		else:
			cooldown = Weapons.FIRE_TIME[i] + (.18 if spent == 2 else 0.0)
		recoil = Weapons.RECOIL[i] + (.19 if spent == 2 else 0.0)
		flash = (.10 if spent == 2 else .072) if i in Weapons.MUZZLE_GUNS else 0.0
		grinding = grind
		last_spent = spent
		var shake_by: float = Weapons.SHAKE.get(i, 0.0)
		game.shake = minf(1.0, game.shake + shake_by * maxf(1, spent))
		game.events.shot_fired.emit(i)
		shot_age = 0.0
		if pool:
			reserve[i] -= spent
		else:
			loaded[i] -= spent
		game.set_face("yell_fire" if i >= Weapons.SHOTGUN else "grin_rampage", .29)
		var cue := ""
		if i == Weapons.SHOTGUN and spent == 2:
			cue = "shotgun_both"
		elif i == Weapons.RIVETER and spent == 2:
			cue = "riveter_pair"
		else:
			cue = str(Weapons.NAMES[i])
		if not grind:
			if i in Weapons.MUZZLE_GUNS and i != Weapons.ARMGUN:
				game.report(cue)
			else:
				game.sound.play(cue)
		var player: Player = game.player
		var aim: float = player.view_angle()
		var slope: float = (player.pitch + player.sway) / View.base_focal
		var how: Dictionary = Weapons.FIRING[i]
		if how.get("assist", false):
			var assisted: Array = game.assisted_aim(aim, slope)
			aim = assisted[0]
			slope = assisted[1]
		var noise: float = Weapons.SHOT_NOISE[i]
		game.wake_nearby(noise, player.x, player.y)
		var mode := str(how.get("fire", ""))
		if grind:
			game.hitscan(aim, slope, Weapons.GRIND_DAMAGE, 1.45, .36)
		elif mode == "melee":
			swing_hit = true
		elif mode == "hitscan":
			var tuned := Modes.shot_spread(game, player, i, how, rifle_heat)
			var spread: Vector2 = tuned[0]
			var reach: float = tuned[1]
			var amount: float = Weapons.DAMAGE.get(i, 0)
			var width: float = how["width"]
			var pressure: bool = how.get("pressure", false)
			var offsets: Array = [0.0]
			if spent == 2 and how.has("pair_spread"):
				var pair_spread: float = how["pair_spread"]
				offsets = [-pair_spread, pair_spread]
			for offset: float in offsets:
				var yaw := aim + offset
				var tilt := slope
				if spread.x > 0.0:
					yaw += game.rng.randf_range(-spread.x, spread.x)
				if spread.y > 0.0:
					tilt += game.rng.randf_range(-spread.y, spread.y)
				game.hitscan(yaw, tilt, amount, reach, width, true, pressure)
			if how.has("climb"):
				var climb: float = how["climb"]
				var climb_heat: float = how.get("climb_heat", 0.0)
				var heat_gain: float = how.get("heat_gain", 0.0)
				player.pitch = minf(53.0, player.pitch + climb + rifle_heat * climb_heat)
				rifle_heat = minf(1.0, rifle_heat + heat_gain)
		elif mode == "pellets":
			var tuned := Modes.shot_spread(game, player, i, how, 0.0)
			var spread: Vector2 = tuned[0]
			var sparks: int = how.get("spark_pellets", 0)
			var pellets: int = how.get("pellets", Weapons.SHOTGUN_PELLETS)
			var pellet_damage: int = how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE)
			var reach: float = tuned[1]
			var width: float = how["width"]
			for pellet in pellets * spent:
				var dx: float = game.rng.randf_range(-spread.x, spread.x)
				var dy: float = game.rng.randf_range(-spread.y, spread.y)
				game.hitscan(aim + dx, slope + dy, pellet_damage, reach, width, pellet < sparks)
		elif mode == "projectile":
			var speed: float = how["shot_speed"]
			var reach: float = how.get("shot_reach", .23)
			var base: float = (
				game.world.stand(player)
				if str(how.get("shot_from", "eye")) == "floor"
				else player.eye
			)
			var height: float = how.get("shot_height", 0.0)
			var lift: float = how.get("shot_lift", 0.0)
			var aimed: bool = how.get("shot_aimed", true)
			var damage: int = Weapons.DAMAGE.get(i, 0)
			var life: float = how.get("shot_life", -1.0)
			game.launch(
				player.x + cos(aim) * reach,
				player.y + sin(aim) * reach,
				base + height,
				aim,
				speed,
				str(how["shot"]),
				(slope * speed + lift) if aimed else 0.0,
				false,
				damage,
				life
			)

	func release_dynamite(game: Game) -> void:
		if fuse > 0.0:
			game.throw_dynamite(fuse)
			fuse = 0.0
			cooldown = Weapons.FIRE_TIME[Weapons.DYNAMITE]
			recoil = Weapons.RECOIL[Weapons.DYNAMITE]
			shot_age = 0.0
			game.sound.play("tnt_throw")
			game.set_face("yell_fire", .3)
		tnt_latched = false

	func pose() -> String:
		if reload > 0.0:
			var reload_time: float = Weapons.RELOAD_TIME[active]
			var progress: float = 1.0 - reload / reload_time
			var beats: Array = Weapons.RELOAD_BEATS[active]
			var index := 0
			for beat: float in beats:
				if progress >= beat:
					index += 1
			var pose_name: String = Weapons.RELOAD_POSES[index]
			if (
				active == Weapons.SHOTGUN
				and loaded[Weapons.SHOTGUN] == 1
				and pose_name in ["eject", "load"]
			):
				return pose_name + "_one"
			return pose_name
		if active in [Weapons.CROWBAR, Weapons.SLING]:
			if active == Weapons.SLING and shot_age < .40:
				var k := 0
				if shot_age >= .118:
					k += 1
				if shot_age >= .18:
					k += 1
				if shot_age >= .29:
					k += 1
				return ["wind", "strike", "follow", "recover"][k]
			if active == Weapons.CROWBAR and shot_age < .29:
				var k2 := 0
				if shot_age >= .061:
					k2 += 1
				if shot_age >= .115:
					k2 += 1
				if shot_age >= .198:
					k2 += 1
				return ["wind", "strike", "follow", "recover"][k2]
		elif active == Weapons.DYNAMITE:
			if fuse > 0.0:
				return "lit" if int(fuse * 24) % 2 else "lit_alt"
			if shot_age < .065:
				return "throw"
			if shot_age < .16:
				return "kick"
			return "idle" if reserve[Weapons.CROSSBOW] else "dry"
		elif active in Weapons.THROWN_GUNS:
			if shot_age < .065:
				return "throw"
			if shot_age < .16:
				return "kick"
			return "idle" if reserve[active] else "dry"
		elif active == Weapons.RIPSAW and grinding and shot_age < .19:
			return "grind_hot" if int(shot_age * 40) % 2 else "grind"
		elif (
			shot_age < Weapons.KICK_HOLD[active]
			or (active in [Weapons.CROSSBOW, Weapons.RIPSAW] and not reserve[active])
		):
			return "kick"
		elif active in Weapons.CYCLE_GUNS and shot_age < Weapons.FIRE_TIME[active]:
			if not reserve[active]:
				return "open"
			var hold: float = Weapons.KICK_HOLD[active]
			var fire_time: float = Weapons.FIRE_TIME[active]
			var span := fire_time - hold
			var cycle := (shot_age - hold) / span
			var stage := 0
			for beat: float in Weapons.RELOAD_BEATS[active]:
				if cycle >= beat:
					stage += 1
			return Weapons.RELOAD_POSES[stage]
		elif (
			active in Weapons.RECOVERY_GUNS
			and shot_age < (.103 if active == Weapons.RIFLE else .16)
		):
			return "recover"
		return "idle"

	# ------------------------------------------------------------ rendering

	## Compose one viewmodel frame into `frame` (320x200 RGB8).
	## `light` is the cell light, `bob`/`flashes` the presentation scales and
	## `offset` the vertical nudge used by the weapon-view option.
	## Where the gun in hand is held on the view this frame: walking, the raise,
	## a reload's sway, the lowered view, and (player.weapon_lag, from
	## features/feel.gd's springs) its weight, its kick and its jolts.
	func _hold(player: Player, bob: float, offset: int) -> Vector2:
		var i := active
		var gait: float = player.motion * (0.35 if player.air else 1.0) * bob
		var lift_amt := minf(1.0, switch / .23)
		var depth: float = Weapons.RAISE_DEPTH[i]
		lift_amt = lift_amt * lift_amt * (3.0 - 2.0 * lift_amt) * depth
		var reload_time: float = Weapons.RELOAD_TIME[i]
		var reload_sway := sin(PI * reload / reload_time) if reload else 0.0
		if i in Weapons.CYCLE_GUNS and reserve[i] > 0:
			var cycle_span: float = Weapons.FIRE_TIME[i]
			if shot_age < cycle_span:
				reload_sway = sin(PI * shot_age / cycle_span)
		var x := roundf(
			(
				sin(player.walk_phase) * gait * 6.5
				+ player.sway * .7
				+ reload_sway * (2.0 if i == Weapons.CROSSBOW else 4.0)
				+ player.weapon_lag.x
			)
		)
		var y := (
			float(View.VIEW - Weapons.GUN_H + offset)
			+ roundf(
				(
					(absf(cos(player.walk_phase)) * 5.2 - 2.2) * gait
					+ player.air * 5.0
					+ lift_amt
					+ lower * 88.0
					+ reload_sway * 2.0
					+ player.weapon_lag.y
				)
			)
		)
		y = maxf(y, float(View.VIEW - Weapons.GUN_H - Weapons.HOLD_FLOOR))
		var nudge: Vector2 = Weapons.VIEW_SHIFT.get(i, Vector2.ZERO)
		x += nudge.x
		y += nudge.y
		return Vector2(x, y)

	## Works out where the muzzle of the gun in hand is on the view now, before
	## it is drawn, for what is drawn under it (weapon_fx.gd draw_view).
	func place_muzzle(player: Player, bob: float, offset: int) -> void:
		var i := active
		if not i in Weapons.MUZZLE_GUNS:
			return
		var s: float = Weapons.VIEW_SCALES.get(i, Weapons.VIEW_SCALE)
		var held := _hold(player, bob, offset)
		var anchor: Vector3i = Weapons.MUZZLES[i]
		var table: Dictionary = Weapons.muzzle_anchors().get(str(Weapons.NAMES[i]), {})
		var pose_name := pose()
		if table.has(pose_name):
			var pair: Array = table[pose_name]
			var px: float = pair[0]
			var py: float = pair[1]
			anchor = Vector3i(roundi(px), roundi(py), anchor.z)
		Weapons.muzzle_at = Weapons.view_point(held.x, held.y, float(anchor.x), float(anchor.y), s)

	func draw(
		frame: PackedByteArray,
		assets: Assets,
		player: Player,
		light: float,
		bob: float,
		flashes: float,
		offset: int,
		canvas: Canvas = null
	) -> void:
		# With `canvas` (a layer over a view the display shader composes) every
		# pixel painted here is also marked as painted, and the gun itself is laid
		# in first with whole-row copies instead of pixel by pixel.
		# On a Godot 2D canvas the same drawing becomes canvas commands, in
		# painting order: flashes and smoke, then the gun, then what flies off it.
		var gpu := canvas != null and canvas.gpu
		var lay := canvas != null and canvas.layer and not gpu
		Weapons.covering = lay
		Weapons.under = false
		Weapons.cover = canvas.cover if lay else PackedByteArray()
		Weapons.painter = canvas if gpu else null
		if lower >= 1.0:
			return
		if gpu:
			canvas.gpu_item(Canvas.ITEM_NORMAL_VIEW)
		var i := active
		var pose_name := pose()
		var s: float = Weapons.VIEW_SCALES.get(i, Weapons.VIEW_SCALE)
		var name := "gun_%s_%s" % [Weapons.NAMES[i], pose_name]
		var level := clampi(roundi((.68 + .38 * light + flash * flashes * 1.6) * 16), 11, 18)
		_warm(assets, clampi(roundi((.68 + .38 * light) * 16), 11, 18))
		var key := name + "|" + str(level)
		# Blood on the crowbar or sling blade (melee_blood.gd): its own cached copy.
		var wet := MeleeBlood.stage(self, i)
		if wet > 0:
			key += "|wet%d%s" % [wet, "g" if MeleeBlood.green(self, i) else ""]
		if graded.size() > 220:
			# Every gun in every light would run to hundreds of megabytes.
			graded.clear()
			rim_cache.clear()
			composed.clear()
		var image: Dictionary = graded.get(key, {})
		if image.is_empty():
			image = _grade(assets, name, s, level)
			if wet > 0:
				image = MeleeBlood.smear(image, wet, MeleeBlood.green(self, i))
			graded[key] = image
		var held := _hold(player, bob, offset)
		var x := held.x
		var y := held.y
		var bx := roundi(x + Weapons.VIEW_PIVOT.x * (1.0 - s))
		var by := roundi(y + Weapons.VIEW_PIVOT.y * (1.0 - s) + Weapons.VIEW_SINK)
		var source: String = Weapons.NAMES[i]
		var rim: Dictionary = rim_cache.get(key, {})
		if rim.is_empty():
			rim = WeaponPaint.rim_of(image)
			rim_cache[key] = rim
		if lay:
			var whole: Dictionary = composed.get(key, {})
			if whole.is_empty():
				whole = WeaponPaint.compose(image, rim)
				composed[key] = whole
			WeaponPaint.lay_cel(canvas, whole, bx, by - 1)
			frame = canvas.pixels
			Weapons.cover = canvas.cover
			Weapons.under = true

		if i in Weapons.MUZZLE_GUNS and shot_age < .62 and lower < .2 and reload == 0.0:
			var anchor: Vector3i = Weapons.MUZZLES[i]
			var table: Dictionary = Weapons.muzzle_anchors().get(source, {})
			if table.has(pose_name):
				var pair: Array = table[pose_name]
				var px: float = pair[0]
				var py: float = pair[1]
				anchor = Vector3i(roundi(px), roundi(py), anchor.z)
			var style: Array = Weapons.MUZZLE_STYLE[i]
			var prefix := str(style[0])
			var smoke_scale: float = style[2]
			Weapons.muzzle_at = Weapons.view_point(x, y, float(anchor.x), float(anchor.y), s)
			if flash > 0.0 and flashes > 0.0:
				GunFlash.draw(
					frame,
					assets,
					i,
					anchor,
					s,
					Vector2(x, y),
					shot_age,
					last_spent,
					style,
					flashes,
					reserve[i] + loaded[i]
				)
			elif smoke_scale > 0.0 and shot_age >= .048:
				# Smoke leaves the muzzle, rises, spreads and thins over half a second.
				var drift := shot_age - .048
				var index2 := clampi(int(drift * 9.0), 0, 3)
				var size2 := roundi((20.0 + drift * 60.0) * smoke_scale)
				var cloud_name := "fx_%s_%d" % ["steam" if prefix == "steam" else "smoke", index2]
				var cloud := assets.art(cloud_name)
				var spot := Weapons.view_point(
					x,
					y,
					float(anchor.x) - 3.0 - drift * 16.0,
					float(anchor.y) - 7.0 - drift * 44.0,
					s
				)
				WeaponPaint.blit_scaled(
					frame,
					cloud,
					size2,
					size2,
					int(roundf(spot.x)) - size2 / 2,
					int(roundf(spot.y)) - size2 / 2,
					int(clampf(1.15 - drift * 2.0, 0.0, 1.0) * 235.0),
					cloud_name
				)

		Weapons.under = false
		if gpu:
			# Rim first, one pixel high, then the cel: two cached textures.
			var rim_w: int = rim["w"]
			var rim_h: int = rim["h"]
			var rim_data: PackedByteArray = rim["data"]
			if player.weapon_turn == 0.0:
				canvas.gpu_texture(
					Canvas.texture("gunrim|" + key, rim_data, rim_w, rim_h),
					bx,
					by - 1,
					rim_w,
					rim_h
				)
			var cel_w: int = image["w"]
			var cel_h: int = image["h"]
			var cel_data: PackedByteArray = image["data"]
			var made := Canvas.texture("gun|" + key, cel_data, cel_w, cel_h)
			if player.weapon_turn != 0.0:
				# A finisher's swing (brawl_looks.gd): turned about the grip.
				var grip := Vector2(cel_w * Weapons.TURN_GRIP.x, cel_h * Weapons.TURN_GRIP.y)
				canvas.gpu_texture_turned(made, bx, by, cel_w, cel_h, player.weapon_turn, grip)
			else:
				canvas.gpu_texture(made, bx, by, cel_w, cel_h)
		elif not lay:
			# Rim first, one pixel high, then the cel.
			WeaponPaint.blit_rgba(frame, rim, bx, by - 1)
			WeaponPaint.blit_rgba(frame, image, bx, by)

		if i == Weapons.RIPSAW and grinding and flashes > 0.0 and shot_age < .135 and lower < .2:
			var anchors: Dictionary = Weapons.muzzle_anchors().get(source, {})
			var centre: Array = anchors.get(pose_name, [155.0, 79.0])
			var ax: float = centre[0]
			var ay: float = centre[1]
			var origin := Weapons.view_point(x, y, ax, ay, s)
			for spark in 6:
				var spread := (spark - 2.5) * 4.0
				var rise := 5.0 + int(shot_age * 56.0) + spark % 3 * 2.0
				var color := Color8(224, 160, 83) if spark % 2 else Color8(247, 209, 134)
				WeaponPaint.draw_line(
					frame,
					int(roundf(origin.x + spread * .42 * s)),
					int(roundf(origin.y - 2.0 * s)),
					int(roundf(origin.x + spread * s)),
					int(roundf(origin.y - rise * s)),
					color
				)
		if i == Weapons.DYNAMITE and fuse > 0.0 and lower < .25:
			var spot2 := Weapons.view_point(x, y, 144.0, 137.0, s)
			var width := maxi(1, roundi(32.0 * fuse / Weapons.DYNAMITE_FUSE * s))
			WeaponPaint.fill_rect(
				frame,
				int(roundf(spot2.x)),
				int(roundf(spot2.y)),
				int(roundf(33.0 * s)),
				int(roundf(4.0 * s)),
				Color8(62, 37, 25)
			)
			WeaponPaint.fill_rect(
				frame,
				int(roundf(spot2.x)),
				int(roundf(spot2.y + s)),
				width,
				int(roundf(2.0 * s)),
				Color8(215, 130, 58) if fuse > .75 else Color8(220, 69, 40)
			)
		if (
			i == Weapons.RIFLE
			and .016 < shot_age
			and shot_age < .123
			and reload == 0.0
			and lower < .2
		):
			var t := shot_age - .016
			var table2: Dictionary = Weapons.muzzle_anchors().get("rifle", {})
			var origin_pair: Array = table2.get("case", [208.0, 97.0])
			var case_x: float = origin_pair[0]
			var case_y: float = origin_pair[1]
			var origin2 := Weapons.view_point(x, y, case_x, case_y, s)
			var ccx := origin2.x + t * 337.0 * s
			var ccy := origin2.y - t * 244.0 * s + 980.0 * s * t * t
			var angle := t * 61.0 - .6
			var tip := Vector2(roundf(ccx + cos(angle) * 3.0), roundf(ccy + sin(angle) * 3.0))
			var tail := Vector2(roundf(ccx - cos(angle) * 3.0), roundf(ccy - sin(angle) * 3.0))
			WeaponPaint.draw_line(
				frame, int(tail.x), int(tail.y), int(tip.x), int(tip.y), Color8(119, 86, 46), 3
			)
			WeaponPaint.draw_line(
				frame, int(tail.x), int(tail.y), int(tip.x), int(tip.y), Color8(216, 170, 83)
			)
			WeaponPaint.set_pixel(frame, int(tip.x), int(tip.y), Color8(233, 193, 112))

	# ------------------------------------------------------------ warming

	## Take in what the warming thread lit, and start it for the gun in hand
	## when that gun or its light is new (see _warm_thread).
	func _warm(assets: Assets, base_level: int) -> void:
		if _warm_thread != null:
			if _warm_thread.is_alive():
				return
			var done: Dictionary = _warm_thread.wait_to_finish()
			_warm_thread = null
			for key: String in done:
				if not graded.has(key):
					var entry: Array = done[key]
					graded[key] = entry[0]
					rim_cache[key] = entry[1]
					composed[key] = entry[2]
		var gun: String = Weapons.NAMES[active]
		var want := "%s|%d" % [gun, base_level]
		if want == _warm_key:
			return
		_warm_key = want
		if not _poses.has(gun):
			var names: Array = []
			for name: String in assets.art_index:
				if name.begins_with("gun_%s_" % gun):
					names.append(name)
			_poses[gun] = names
		var jobs: Array = []
		for name: String in _poses[gun]:
			for level in range(base_level, 19):
				var key := name + "|" + str(level)
				if not graded.has(key):
					jobs.append([name, assets.art(name), level, key])
		if jobs.is_empty():
			return
		if graded.size() + jobs.size() > 220:
			graded.clear()
			rim_cache.clear()
			composed.clear()
		var s: float = Weapons.VIEW_SCALES.get(active, Weapons.VIEW_SCALE)
		_warm_thread = Thread.new()
		# A static function of the class, not this armory's: a new game can free
		# this armory while the thread still runs, and a call bound to a freed
		# instance loses every function it calls.
		_warm_thread.start(Callable(Armory, "_warm_jobs").bind(jobs, s), Thread.PRIORITY_LOW)

	## Wait for a warming thread still at work (the program is closing: its
	## scripts must outlive it).
	static func settle() -> void:
		if _warm_thread != null:
			_warm_thread.wait_to_finish()
			_warm_thread = null

	## On the warming thread: only its own arguments and static functions.
	static func _warm_jobs(jobs: Array, s: float) -> Dictionary:
		var out := {}
		var own_boxes := {}
		for job: Array in jobs:
			var art: Dictionary = job[1]
			var name: String = job[0]
			var level: int = job[2]
			var image := WeaponPaint.grade_cel(own_boxes, art, name, s, level)
			var rim := WeaponPaint.rim_of(image)
			out[job[3]] = [image, rim, WeaponPaint.compose(image, rim)]
		return out

	## Light and scale one cel. A cel is mostly empty air, so only the box that
	## holds the weapon is graded and scaled, then seated in the full frame:
	## doing the whole 320x120 was a visible hitch the first time a pose showed.
	func _grade(assets: Assets, name: String, s: float, level: int) -> Dictionary:
		return WeaponPaint.grade_cel(boxes, assets.art(name), name, s, level)
