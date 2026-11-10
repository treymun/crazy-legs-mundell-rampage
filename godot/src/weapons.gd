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

const COUNT := 16

const NAMES := [
	"crowbar",
	"revolver",
	"shotgun",
	"crossbow",
	"rifle",
	"ripsaw",
	"armgun",
	"tnt",
	"slingblade",
	"bottle_launcher",
	"riveter",
	"pressure_gun",
	"bowling_ball",
	"powder_keg",
	"cow_launcher",
	"teat_gun"
]
const LABELS := [
	"RUSTED CROWBAR",
	".38 SPECIAL",
	"SAWED-OFF",
	"DYNAMITE CROSSBOW",
	"RANCH RIFLE",
	"RIP SAW",
	"ALIEN ARM GUN",
	"DYNAMITE",
	"SLING BLADE [9]",
	"BOTTLE ROCKET LAUNCHER [0]",
	"MILL RIVETER",
	"COPPERHEAD",
	"BOWLING BALL [-]",
	"POWDER KEG [=]",
	"COW LAUNCHER",
	"TEAT GUN"
]
## Only the .38 and the sawed-off have a magazine and a reload. Every other
## gun fires straight from its ammo pool (`reserve`).
const CAPACITY := [0, 6, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
## Magazine sizes before the pool change: a save written then may still hold
## rounds in `loaded`, which `Armory.tick` folds back into the pool.
const SAVED_CAPACITY := [0, 6, 2, 1, 18, 1, 6, 0, 0, 1, 8, 3, 1, 1, 1, 30]
const RELOAD_TIME := [
	0.0, .88, 1.10, .68, 1.30, .58, .88, 0.0, 0.0, .79, .94, 1.18, .72, .95, 1.10, 1.25
]
## Seconds between shots. For the CYCLE_GUNS this is the whole hand-loaded
## cycle: the shot, then the open / eject / load / close poses.
const FIRE_TIME := [
	.33, .30, .55, 1.05, .11, .78, .21, .46, .49, 1.15, .22, .60, 1.10, 1.35, 1.55, .09
]
const MAX_RESERVE := [0, 90, 48, 30, 200, 22, 60, 0, 0, 16, 60, 24, 9, 6, 6, 150]
## One shot, then a visible reload inside the fire delay.
const CYCLE_GUNS := [CROSSBOW, RIPSAW, ROCKET, BOWLING, KEG, COW]
const PICKUP_RESERVE := [0, 12, 15, 8, 20, 5, 8, 0, 0, 6, 16, 6, 3, 2, 2, 30]
const RECOIL := [.60, .70, 1.03, .8, .44, .55, .42, .25, .87, .74, .65, .82, .55, .75, 1.1, .30]
const SHOT_NOISE := [
	2.8, 10.0, 14.0, 4.0, 13.0, 7.0, 8.0, 1.0, 2.9, 8.5, 7.0, 7.5, 4.0, 6.0, 12.0, 6.0
]
const KICK_HOLD := [
	0.0, .073, .095, .11, .052, .09, .075, .14, 0.0, .095, .086, .125, .12, .12, .12, .04
]
const VIEW_RISE := [4, 6, 10, 5, 6, 4, 5, 5, 7, 6, 8, 8, 3, 5, 9, 2]
const SETTLE := [.21, .17, .24, .24, .10, .19, .22, .19, .27, .23, .13, .29, .25, .25, .30, .08]
const RETREAT := [3, 3, 7, 2, 4, 4, 2, 4, 4, 6, 3, 5, 3, 4, 8, 1]
const RAISE_DEPTH := [42, 36, 45, 43, 47, 49, 40, 36, 49, 46, 45, 50, 44, 44, 46, 42]
const DYNAMITE_FUSE := 2.65

## Per-shot damage; the shotgun entry is [per pellet, pellet count].
const DAMAGE := {
	REVOLVER: 34,
	RIFLE: 21,
	RIVETER: 32,
	PRESSURE: 24,
	ARMGUN: 50,
	RIPSAW: 54,
	TEAT: 10,
	BOWLING: 108,
	COW: 150,
	ROCKET: 120
}
const SHOTGUN_DAMAGE := 12
const SHOTGUN_PELLETS := 10
const GRIND_DAMAGE := 21
const MELEE := {CROWBAR: [44, 58], SLING: [58, 72]}
const RECOVERY_GUNS := [
	REVOLVER, SHOTGUN, RIFLE, ARMGUN, ROCKET, RIVETER, PRESSURE, BOWLING, KEG, COW, TEAT
]
const RELOAD_POSES := ["open", "eject", "load", "close"]
const MUZZLE_GUNS := [REVOLVER, SHOTGUN, RIFLE, ARMGUN, ROCKET, RIVETER, PRESSURE, COW, TEAT]
const MUZZLES := {
	REVOLVER: Vector3i(182, 73, 32),
	SHOTGUN: Vector3i(181, 75, 48),
	RIFLE: Vector3i(173, 63, 32),
	ARMGUN: Vector3i(171, 79, 31),
	ROCKET: Vector3i(165, 70, 25),
	RIVETER: Vector3i(174, 75, 23),
	PRESSURE: Vector3i(173, 76, 19),
	COW: Vector3i(163, 69, 26),
	TEAT: Vector3i(280, 82, 18),
}
const GUN_W := 320
const GUN_H := 120
const VIEW_SCALE := 1.22
## The crowbar, revolver and shotgun are photographed plates. Every other
## weapon is rendered through one of those plates' cameras and held by that
## plate's hand, so it draws at that plate's scale and with its nudge.
const VIEW_SCALES := {
	CROWBAR: 1.36,
	SLING: 1.36,
	DYNAMITE: 1.36,
	SHOTGUN: 1.20,
	RIFLE: 1.20,
	CROSSBOW: 1.20,
	ROCKET: 1.20,
	COW: 1.20
}
## Pixels to slide a viewmodel right and down so its muzzle sits under the
## crosshair instead of on it.
const HIP_PISTOL := Vector2(13, 9)
const HIP_LONG := Vector2(15, 11)
const VIEW_SHIFT := {
	REVOLVER: HIP_PISTOL,
	ARMGUN: HIP_PISTOL,
	RIVETER: HIP_PISTOL,
	PRESSURE: HIP_PISTOL,
	TEAT: HIP_PISTOL,
	RIPSAW: HIP_PISTOL,
	SHOTGUN: HIP_LONG,
	RIFLE: HIP_LONG,
	CROSSBOW: HIP_LONG,
	ROCKET: HIP_LONG,
	COW: HIP_LONG
}
const VIEW_PIVOT := Vector2(160.0, 120.0)
const VIEW_SINK := 4.0
const HOLD_FLOOR := 3.0

const MUZZLE_STYLE := {
	REVOLVER: ["fire", .81, 0.76],
	SHOTGUN: ["fire", .91, 1.24],
	RIFLE: ["fire", .65, .69],
	ARMGUN: ["energy", 1.06, 0.0],
	ROCKET: ["rocket", 1.07, 1.14],
	RIVETER: ["forge", .58, .62],
	PRESSURE: ["steam", .86, 1.23],
	COW: ["rocket", 1.07, 1.14],
	TEAT: ["steam", .74, .55],
}
const RELOAD_BEATS := {
	REVOLVER: [.22, .48, .83],
	SHOTGUN: [.23, .46, .80],
	CROSSBOW: [.26, .51, .82],
	RIFLE: [.27, .49, .85],
	RIPSAW: [.22, .47, .80],
	ARMGUN: [.29, .52, .85],
	ROCKET: [.26, .49, .83],
	RIVETER: [.23, .48, .82],
	PRESSURE: [.30, .52, .84],
	BOWLING: [.25, .50, .82],
	KEG: [.25, .50, .82],
	COW: [.26, .50, .83],
	TEAT: [.28, .52, .84],
}
const RELOAD_AUDIO := {
	REVOLVER: ["rev_extract", "rev_cylinder", "rev_lock"],
	SHOTGUN: ["shot_extract", "shot_shell", "shot_lock"],
	CROSSBOW: ["bow_pull", "bow_seat", "bow_latch"],
	RIFLE: ["mag_out", "mag_in", "bolt_rack"],
	RIPSAW: ["saw_latch", "saw_seat", "saw_latch"],
	ARMGUN: ["arm_vent", "arm_cell", "arm_ready"],
	ROCKET: ["rocket_case", "rocket_seat", "rocket_lock"],
	RIVETER: ["rivet_mag", "rivet_strip", "rivet_lock"],
	PRESSURE: ["pressure_vent", "pressure_charge", "pressure_pump"],
	BOWLING: ["eject", "load", "close"],
	KEG: ["shot_hinge", "load", "close"],
	COW: ["rocket_case", "rocket_seat", "rocket_lock"],
	TEAT: ["mag_out", "gulp", "bolt_rack"],
}
const OPEN_AUDIO := {
	REVOLVER: "rev_cylinder",
	SHOTGUN: "shot_hinge",
	CROSSBOW: "bow_hook",
	RIFLE: "reload",
	RIPSAW: "saw_latch",
	ARMGUN: "arm_vent",
	ROCKET: "rocket_breech",
	RIVETER: "rivet_mag",
	PRESSURE: "pressure_seal",
	BOWLING: "load",
	KEG: "shot_hinge",
	COW: "rocket_breech",
	TEAT: "reload",
}

static var _anchors: Dictionary = {}


## True for a gun that fires from its ammo pool with no magazine.
static func pool_fed(slot: int) -> bool:
	return CAPACITY[slot] == 0 and slot not in [CROWBAR, SLING, DYNAMITE]


## Cached weapon_anchors.json (muzzle/case positions per pose).
static func muzzle_anchors() -> Dictionary:
	if _anchors.is_empty():
		var raw := FileAccess.get_file_as_string("res://assets_gen/weapon_anchors.json")
		var parsed = JSON.parse_string(raw)
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
	var graded := {}
	var rim_cache := {}
	var boxes := {}

	func _init(start_slot := 1) -> void:
		for i in Weapons.COUNT:
			owned.append(i == Weapons.CROWBAR or i == Weapons.REVOLVER)
			loaded.append(6 if i == Weapons.REVOLVER else 0)
			reserve.append(30 if i == Weapons.REVOLVER else 0)
		active = start_slot

	func tick(dt: float, game) -> void:
		for slot in Weapons.COUNT:
			if loaded[slot] > Weapons.CAPACITY[slot]:
				# An older save's magazine: put the rounds back in the pool.
				var extra: int = loaded[slot] - Weapons.CAPACITY[slot]
				loaded[slot] = Weapons.CAPACITY[slot]
				reserve[slot] = mini(Weapons.MAX_RESERVE[slot], reserve[slot] + extra)
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
					if was < float(cycle_beats[k]) and now >= float(cycle_beats[k]):
						game.sound.play(String(cycle_cues[k]), .78)
		if fuse > 0.0:
			fuse -= dt
			if fuse <= 0.0:
				fuse = 0.0
				cooldown = Weapons.FIRE_TIME[Weapons.DYNAMITE]
				shot_age = 0.0
				game.throw_dynamite(0.0)
		var swing_at := .118 if active == Weapons.SLING else .061
		if active in [Weapons.CROWBAR, Weapons.SLING] and swing_hit and shot_age >= swing_at:
			swing_hit = false
			var p = game.player
			var sling := active == Weapons.SLING
			var table: Array = Weapons.MELEE[Weapons.SLING if sling else Weapons.CROWBAR]
			var damage: int = table[1 if game.sprint else 0]
			var reached: bool = game.hitscan(
				p.view_angle(),
				(p.pitch + p.sway) / Renderer.FOCAL,
				damage,
				2.15 if sling else 1.65,
				.30 if sling else .34
			)
			if reached:
				game.sound.play("sling_hit" if sling else "crowbar_hit")
		rifle_heat = maxf(0.0, rifle_heat - dt * 1.8)
		lower = maxf(0.0, minf(1.0, lower + dt * (5.5 if holstered else -5.5)))
		if reload > 0.0:
			var before: float = 1.0 - reload / float(Weapons.RELOAD_TIME[active])
			reload -= dt
			var progress: float = 1.0 - reload / float(Weapons.RELOAD_TIME[active])
			var cues: Array = Weapons.RELOAD_AUDIO.get(active, ["eject", "load", "close"])
			var beats: Array = Weapons.RELOAD_BEATS[active]
			for k in 3:
				if before < float(beats[k]) and progress >= float(beats[k]):
					game.sound.play(String(cues[k]), .78)
			if reload <= 0.0:
				var i := active
				var count: int = mini(Weapons.CAPACITY[i] - loaded[i], reserve[i])
				loaded[i] += count
				reserve[i] -= count
				reload = 0.0

	func select(slot: int, game) -> void:
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
			game.sound.play("equip_" + String(Weapons.NAMES[slot]), .61)
			game.message(String(Weapons.LABELS[slot]), .95)
		elif not owned[slot]:
			game.message("YOU AIN'T GOT THAT ONE.", .85)

	func pickup(slot: int, game) -> bool:
		var fresh := not owned[slot]
		owned[slot] = true
		add_ammo(slot, Weapons.PICKUP_RESERVE[slot])
		if fresh:
			loaded[slot] = Weapons.CAPACITY[slot]
			if auto_switch:
				select(slot, game)
			else:
				game.message(String(Weapons.LABELS[slot]), 1.35)
		return fresh

	func add_ammo(slot: int, amount: int) -> bool:
		var old := reserve[slot]
		reserve[slot] = mini(Weapons.MAX_RESERVE[slot], old + amount)
		return reserve[slot] > old

	func cycle(direction: int, game) -> void:
		for offset in range(1, Weapons.COUNT):
			var slot := posmod(active + offset * direction, Weapons.COUNT)
			if owned[slot]:
				select(slot, game)
				return

	func start_reload(game) -> bool:
		var i := active
		if Weapons.CAPACITY[i] and reload <= 0.0 and reserve[i] and loaded[i] < Weapons.CAPACITY[i]:
			reload = Weapons.RELOAD_TIME[i]
			grinding = false
			game.sound.play(String(Weapons.OPEN_AUDIO[i]), .85)
			return true
		return false

	func fire(game, both := false) -> void:
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
				game.sound.play("dry_" + String(Weapons.NAMES[i]))
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
			cue = String(Weapons.NAMES[i])
		if not grind:
			if i in Weapons.MUZZLE_GUNS and i != Weapons.ARMGUN:
				game.report(cue)
			else:
				game.sound.play(cue)
		var player = game.player
		var aim: float = player.view_angle()
		var slope: float = (player.pitch + player.sway) / Renderer.FOCAL
		if i in [Weapons.REVOLVER, Weapons.SHOTGUN, Weapons.RIFLE]:
			var assisted: Array = game.assisted_aim(aim, slope)
			aim = assisted[0]
			slope = assisted[1]
		game.wake_nearby(Weapons.SHOT_NOISE[i], player.x, player.y)
		if i in [Weapons.CROWBAR, Weapons.SLING]:
			swing_hit = true
		elif i == Weapons.REVOLVER:
			game.hitscan(
				aim + game.rng.randf_range(-.009, .009),
				slope,
				Weapons.DAMAGE[Weapons.REVOLVER],
				23.0,
				.055
			)
		elif i == Weapons.SHOTGUN:
			for pellet in Weapons.SHOTGUN_PELLETS * spent:
				var dx: float = game.rng.randf_range(-.135, .135)
				var dy: float = game.rng.randf_range(-.09, .09)
				game.hitscan(aim + dx, slope + dy, Weapons.SHOTGUN_DAMAGE, 11.5, .04, pellet < 4)
		elif i == Weapons.RIFLE:
			var spread := .009 + rifle_heat * .027
			game.hitscan(
				aim + game.rng.randf_range(-spread, spread),
				slope + game.rng.randf_range(-spread, spread),
				Weapons.DAMAGE[Weapons.RIFLE],
				27.0,
				.045
			)
			player.pitch = minf(53.0, player.pitch + .70 + rifle_heat * 1.2)
			rifle_heat = minf(1.0, rifle_heat + .29)
		elif i == Weapons.RIVETER:
			var offsets: Array = [-.031, .031] if spent == 2 else [0.0]
			for offset in offsets:
				game.hitscan(
					aim + float(offset), slope, Weapons.DAMAGE[Weapons.RIVETER], 16.0, .042
				)
		elif i == Weapons.PRESSURE:
			# pressure=True only: a miss still sparks, chips and breaks glass.
			game.hitscan(aim, slope, Weapons.DAMAGE[Weapons.PRESSURE], 8.5, .035, true, true)
		elif i == Weapons.TEAT:
			game.hitscan(
				aim + game.rng.randf_range(-.05, .05),
				slope + game.rng.randf_range(-.04, .04),
				Weapons.DAMAGE[Weapons.TEAT],
				9.0,
				.06
			)
		elif i in [Weapons.BOWLING, Weapons.KEG, Weapons.COW]:
			var kind := ""
			var speed := 0.0
			var damage := 0
			var lift := 0.0
			if i == Weapons.BOWLING:
				kind = "bowling"
				speed = 7.4
				damage = Weapons.DAMAGE[Weapons.BOWLING]
			elif i == Weapons.KEG:
				kind = "keg"
				speed = 6.2
				lift = .55
			else:
				kind = "cow"
				speed = 8.6
				damage = Weapons.DAMAGE[Weapons.COW]
				lift = .30
			var z: float = (
				(game.world.elevation(player.x, player.y) + .22)
				if i == Weapons.BOWLING
				else player.eye - .12
			)
			game.launch(
				player.x + cos(aim) * .25,
				player.y + sin(aim) * .25,
				z,
				aim,
				speed,
				kind,
				(slope * speed + lift) if i != Weapons.BOWLING else 0.0,
				false,
				damage,
				4.5 if i == Weapons.BOWLING else -1.0
			)
		elif grind:
			game.hitscan(aim, slope, Weapons.GRIND_DAMAGE, 1.45, .36)
		else:
			var kind2 := ""
			var speed2 := 0.0
			var damage2 := 0
			match i:
				Weapons.CROSSBOW:
					kind2 = "bolt"
					speed2 = 10.8
				Weapons.RIPSAW:
					kind2 = "blade"
					speed2 = 15.0
					damage2 = Weapons.DAMAGE[Weapons.RIPSAW]
				Weapons.ARMGUN:
					kind2 = "arm_bolt"
					speed2 = 12.2
					damage2 = Weapons.DAMAGE[Weapons.ARMGUN]
				Weapons.ROCKET:
					kind2 = "bottle_rocket"
					speed2 = 9.6
					damage2 = Weapons.DAMAGE[Weapons.ROCKET]
			var lift2 := .34 if i in [Weapons.CROSSBOW, Weapons.ROCKET] else 0.0
			game.launch(
				player.x + cos(aim) * .23,
				player.y + sin(aim) * .23,
				player.eye - .09,
				aim,
				speed2,
				kind2,
				slope * speed2 + lift2,
				false,
				damage2,
				-1.0
			)

	func release_dynamite(game) -> void:
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
			var progress: float = 1.0 - reload / float(Weapons.RELOAD_TIME[active])
			var beats: Array = Weapons.RELOAD_BEATS[active]
			var index := 0
			for beat in beats:
				if progress >= float(beat):
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
		elif active == Weapons.RIPSAW and grinding and shot_age < .19:
			return "grind_hot" if int(shot_age * 40) % 2 else "grind"
		elif (
			shot_age < float(Weapons.KICK_HOLD[active])
			or (active in [Weapons.CROSSBOW, Weapons.RIPSAW] and not reserve[active])
		):
			return "kick"
		elif active in Weapons.CYCLE_GUNS and shot_age < float(Weapons.FIRE_TIME[active]):
			if not reserve[active]:
				return "open"
			var hold := float(Weapons.KICK_HOLD[active])
			var span := float(Weapons.FIRE_TIME[active]) - hold
			var cycle := (shot_age - hold) / span
			var stage := 0
			for beat in Weapons.RELOAD_BEATS[active]:
				if cycle >= float(beat):
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
	func draw(
		frame: PackedByteArray,
		assets: Assets,
		player,
		light: float,
		bob: float,
		flashes: float,
		offset: int
	) -> void:
		if lower >= 1.0:
			return
		var i := active
		var pose_name := pose()
		var s: float = float(Weapons.VIEW_SCALES.get(i, Weapons.VIEW_SCALE))
		var name := "gun_%s_%s" % [Weapons.NAMES[i], pose_name]
		var level := clampi(int(round((.68 + .38 * light + flash * flashes * 1.6) * 16)), 11, 18)
		var key := name + "|" + str(level)
		var image: Dictionary = graded.get(key, {})
		if image.is_empty():
			image = _grade(assets, name, s, level)
			graded[key] = image
		var gait: float = player.motion * (0.35 if player.air else 1.0) * bob
		var progress := minf(1.0, shot_age / float(Weapons.SETTLE[i]))
		var settling := ((1.0 - progress) * (1.0 - progress) - .32 * sin(PI * progress)) * recoil
		var lift_amt := minf(1.0, switch / .23)
		lift_amt = lift_amt * lift_amt * (3.0 - 2.0 * lift_amt) * float(Weapons.RAISE_DEPTH[i])
		var reload_sway := sin(PI * reload / Weapons.RELOAD_TIME[i]) if reload else 0.0
		if i in Weapons.CYCLE_GUNS and reserve[i] > 0:
			var cycle_span: float = Weapons.FIRE_TIME[i]
			if shot_age < cycle_span:
				reload_sway = sin(PI * shot_age / cycle_span)
		var x := roundf(
			(
				sin(player.walk_phase) * gait * 6.5
				+ player.sway * .7
				+ settling * float(Weapons.RETREAT[i])
				+ reload_sway * (2.0 if i == Weapons.CROSSBOW else 4.0)
			)
		)
		var y := (
			float(Renderer.VIEW - Weapons.GUN_H + offset)
			+ roundf(
				(
					(absf(cos(player.walk_phase)) * 5.2 - 2.2) * gait
					+ player.air * 5.0
					- float(Weapons.VIEW_RISE[i]) * settling
					+ lift_amt
					+ lower * 88.0
					+ reload_sway * 2.0
				)
			)
		)
		y = maxf(y, float(Renderer.VIEW - Weapons.GUN_H - Weapons.HOLD_FLOOR))
		var nudge: Vector2 = Weapons.VIEW_SHIFT.get(i, Vector2.ZERO)
		x += nudge.x
		y += nudge.y
		var bx := int(round(x + Weapons.VIEW_PIVOT.x * (1.0 - s)))
		var by := int(round(y + Weapons.VIEW_PIVOT.y * (1.0 - s) + Weapons.VIEW_SINK))
		var source: String = Weapons.NAMES[i]

		if i in Weapons.MUZZLE_GUNS and shot_age < .31 and lower < .2 and reload == 0.0:
			var anchor := Vector3i(Weapons.MUZZLES[i])
			var table: Dictionary = Weapons.muzzle_anchors().get(source, {})
			if table.has(pose_name):
				var pair: Array = table[pose_name]
				anchor = Vector3i(int(round(float(pair[0]))), int(round(float(pair[1]))), anchor.z)
			var style: Array = Weapons.MUZZLE_STYLE[i]
			var prefix := String(style[0])
			var aspect := float(style[1])
			var smoke_scale := float(style[2])
			if flash > 0.0 and flashes > 0.0:
				var index := mini(3, int(shot_age * 48))
				var size := int(round((float(anchor.z) + (8.0 if last_spent == 2 else 0.0)) * s))
				var flash_art := assets.art("fx_%s_%d" % [prefix, index])
				var fw := size
				var fh := int(round(size * aspect))
				var front := Weapons.view_point(x, y, float(anchor.x), float(anchor.y), s)
				var fc := Vector2(roundf(front.x - 3.0 * s), roundf(front.y - 2.0 * s))
				_blit_scaled(
					frame,
					flash_art,
					fw,
					fh,
					int(fc.x) - fw / 2,
					int(fc.y) - fh / 2,
					int(255.0 * minf(1.0, flashes))
				)
				if i == Weapons.SHOTGUN and last_spent == 2:
					var twin_size := int(round(size * .76))
					var twin := assets.art("fx_%s_%d" % [prefix, mini(3, index + 1)])
					_blit_scaled(
						frame,
						twin,
						twin_size,
						twin_size,
						int(fc.x + roundf(6.0 * s)) - twin_size / 2,
						int(fc.y + roundf(1.0 * s)) - twin_size / 2,
						int(255.0 * minf(1.0, flashes))
					)
			elif smoke_scale > 0.0 and shot_age >= .048:
				var index2 := clampi(int((shot_age - .055) * 16.0), 0, 3)
				var size2 := int(round((21.0 + index2 * 6.0) * smoke_scale))
				var cloud := assets.art("fx_smoke_%d" % index2)
				var spot := Weapons.view_point(
					x,
					y,
					float(anchor.x) - 4.0 - index2 * 2.0,
					float(anchor.y) - 9.0 - index2 * 4.0,
					s
				)
				_blit_scaled(
					frame,
					cloud,
					size2,
					size2,
					int(roundf(spot.x)) - size2 / 2,
					int(roundf(spot.y)) - size2 / 2,
					255
				)

		# Rim first, one pixel high, then the cel.
		var rim: Dictionary = rim_cache.get(key, {})
		if rim.is_empty():
			rim = _rim(image)
			rim_cache[key] = rim
		_blit_rgba(frame, rim, bx, by - 1)
		_blit_rgba(frame, image, bx, by)

		if i == Weapons.RIPSAW and grinding and flashes > 0.0 and shot_age < .135 and lower < .2:
			var anchors: Dictionary = Weapons.muzzle_anchors().get(source, {})
			var centre: Array = anchors.get(pose_name, [155.0, 79.0])
			var ax := float(centre[0])
			var ay := float(centre[1])
			var origin := Weapons.view_point(x, y, ax, ay, s)
			for spark in 6:
				var spread := (spark - 2.5) * 4.0
				var rise := 5.0 + int(shot_age * 56.0) + spark % 3 * 2.0
				var color := Color8(224, 160, 83) if spark % 2 else Color8(247, 209, 134)
				_line(
					frame,
					int(roundf(origin.x + spread * .42 * s)),
					int(roundf(origin.y - 2.0 * s)),
					int(roundf(origin.x + spread * s)),
					int(roundf(origin.y - rise * s)),
					color
				)
		if i == Weapons.DYNAMITE and fuse > 0.0 and lower < .25:
			var spot2 := Weapons.view_point(x, y, 144.0, 137.0, s)
			var width := maxi(1, int(round(32.0 * fuse / Weapons.DYNAMITE_FUSE * s)))
			_fill(
				frame,
				int(roundf(spot2.x)),
				int(roundf(spot2.y)),
				int(roundf(33.0 * s)),
				int(roundf(4.0 * s)),
				Color8(62, 37, 25)
			)
			_fill(
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
			var origin2 := Weapons.view_point(x, y, float(origin_pair[0]), float(origin_pair[1]), s)
			var ccx := origin2.x + t * 337.0 * s
			var ccy := origin2.y - t * 244.0 * s + 980.0 * s * t * t
			var angle := t * 61.0 - .6
			var tip := Vector2(roundf(ccx + cos(angle) * 3.0), roundf(ccy + sin(angle) * 3.0))
			var tail := Vector2(roundf(ccx - cos(angle) * 3.0), roundf(ccy - sin(angle) * 3.0))
			_line(frame, int(tail.x), int(tail.y), int(tip.x), int(tip.y), Color8(119, 86, 46), 3)
			_line(frame, int(tail.x), int(tail.y), int(tip.x), int(tip.y), Color8(216, 170, 83))
			_set_pixel(frame, int(tip.x), int(tip.y), Color8(233, 193, 112))

	# ------------------------------------------------------------ helpers

	## Multiply the cel by the graded light, add the warm floor, then smoothscale.
	## Where a cel has anything in it (one pixel of margin), found once per cel.
	func _opaque_box(name: String, data: PackedByteArray, w: int, h: int) -> Rect2i:
		if boxes.has(name):
			return boxes[name]
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for y in h:
			var row := y * w * 4 + 3
			for x in w:
				if data[row + x * 4] != 0:
					if x < x0:
						x0 = x
					if x > x1:
						x1 = x
					if y < y0:
						y0 = y
					y1 = y
		var box := Rect2i(0, 0, 0, 0)
		if x1 >= x0:
			x0 = maxi(0, x0 - 1)
			y0 = maxi(0, y0 - 1)
			box = Rect2i(x0, y0, mini(w - 1, x1 + 1) - x0 + 1, mini(h - 1, y1 + 1) - y0 + 1)
		boxes[name] = box
		return box

	## Light and scale one cel. A cel is mostly empty air, so only the box that
	## holds the weapon is graded and scaled, then seated in the full frame:
	## doing the whole 320x120 was a visible hitch the first time a pose showed.
	func _grade(assets: Assets, name: String, s: float, level: int) -> Dictionary:
		var art := assets.art(name)
		var w: int = art["w"]
		var h: int = art["h"]
		var data: PackedByteArray = art["data"]
		var tw := int(round(Weapons.GUN_W * s))
		var th := int(round(Weapons.GUN_H * s))
		var spans := PackedInt32Array()
		spans.resize(th * 2)
		spans.fill(-1)
		var box := _opaque_box(name, data, w, h)
		var out := PackedByteArray()
		if box.size.x <= 0:
			out.resize(tw * th * 4)
			return {"w": tw, "h": th, "data": out, "spans": spans}
		var cw := box.size.x
		var ch := box.size.y
		var mul_r := mini(255, level * 15 + 11)
		var mul_g := mini(255, level * 15 + 8)
		var mul_b := mini(255, level * 16 + 3)
		var crop := PackedByteArray()
		crop.resize(cw * ch * 4)
		for y in ch:
			var i := ((box.position.y + y) * w + box.position.x) * 4
			var o := y * cw * 4
			for _x in cw:
				var da := data[i + 3]
				if da != 0:
					var dr := data[i]
					var dg := data[i + 1]
					var db := data[i + 2]
					# pygame BLEND_RGBA_MULT: ((d * s) + 255) >> 8, or 0 when either is 0;
					# then BLEND_RGB_ADD: a saturating add that leaves alpha alone.
					crop[o] = mini(255, (((dr * mul_r) + 255) >> 8 if dr else 0) + 11)
					crop[o + 1] = mini(255, (((dg * mul_g) + 255) >> 8 if dg else 0) + 8)
					crop[o + 2] = mini(255, (((db * mul_b) + 255) >> 8 if db else 0) + 4)
					crop[o + 3] = ((da * 255) + 255) >> 8
				else:
					crop[o] = 11
					crop[o + 1] = 8
					crop[o + 2] = 4
				i += 4
				o += 4
		var sw := clampi(int(round(cw * s)), 1, tw)
		var sh := clampi(int(round(ch * s)), 1, th)
		var small := SmoothScale.rgba(crop, cw, ch, sw, sh)
		var ox := clampi(int(round(box.position.x * s)), 0, tw - sw)
		var oy := clampi(int(round(box.position.y * s)), 0, th - sh)
		var left := PackedByteArray()
		left.resize(ox * 4)
		var right := PackedByteArray()
		right.resize((tw - ox - sw) * 4)
		out.resize(oy * tw * 4)
		for y in sh:
			out.append_array(left)
			out.append_array(small.slice(y * sw * 4, (y + 1) * sw * 4))
			out.append_array(right)
			var first := -1
			var last := -1
			var row := y * sw * 4 + 3
			for x in sw:
				if small[row + x * 4] != 0:
					if first < 0:
						first = x
					last = x
			if first >= 0:
				spans[(oy + y) * 2] = ox + first
				spans[(oy + y) * 2 + 1] = ox + last
		out.resize(tw * th * 4)
		return {"w": tw, "h": th, "data": out, "spans": spans}

	## mask.from_surface(image).to_surface((205,168,116,42)) over the scaled cel.
	func _rim(image: Dictionary) -> Dictionary:
		var w: int = image["w"]
		var h: int = image["h"]
		var data: PackedByteArray = image["data"]
		var spans: PackedInt32Array = image["spans"]
		var out := PackedByteArray()
		out.resize(w * h * 4)
		for y in h:
			var first := spans[y * 2]
			if first < 0:
				continue
			for x in range(first, spans[y * 2 + 1] + 1):
				var i := (y * w + x) * 4
				if data[i + 3] >= 128:
					out[i] = 205
					out[i + 1] = 168
					out[i + 2] = 116
					out[i + 3] = 42
		return {"w": w, "h": h, "data": out, "spans": spans}

	## Clip-blit an RGBA image into the view rows of `frame`. Uses the cached
	## per-row opaque span when the image has one.
	static func _blit_rgba(frame: PackedByteArray, image: Dictionary, x: int, y: int) -> void:
		var w: int = image["w"]
		var h: int = image["h"]
		var data: PackedByteArray = image["data"]
		var spans = image.get("spans")
		if spans == null:
			for yy in h:
				var ty := y + yy
				if ty < 0 or ty >= Renderer.VIEW:
					continue
				var row := yy * w * 4
				for xx in w:
					var tx := x + xx
					if tx < 0 or tx >= Renderer.WIDTH:
						continue
					var sp := row + xx * 4
					var a := data[sp + 3]
					if a == 0:
						continue
					var o := (ty * Renderer.WIDTH + tx) * 3
					if a == 255:
						frame[o] = data[sp]
						frame[o + 1] = data[sp + 1]
						frame[o + 2] = data[sp + 2]
					else:
						var k := a
						frame[o] = clampi(
							frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
						)
						frame[o + 1] = clampi(
							(
								frame[o + 1]
								+ (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8)
							),
							0,
							255
						)
						frame[o + 2] = clampi(
							(
								frame[o + 2]
								+ (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8)
							),
							0,
							255
						)
			return
		var ty0 := maxi(y, 0)
		var ty1 := mini(y + h, Renderer.VIEW)
		for yy in range(ty0 - y, ty1 - y):
			var first: int = spans[yy * 2]
			if first < 0:
				continue
			var last: int = spans[yy * 2 + 1]
			var ty := y + yy
			var row := yy * w * 4
			var x0 := maxi(x + first, 0)
			var x1 := mini(x + last, Renderer.WIDTH - 1)
			var o := (ty * Renderer.WIDTH + x0) * 3
			var sp := row + (x0 - x) * 4
			for tx in range(x0, x1 + 1):
				var a := data[sp + 3]
				if a != 0:
					if a == 255:
						frame[o] = data[sp]
						frame[o + 1] = data[sp + 1]
						frame[o + 2] = data[sp + 2]
					else:
						var k := a
						frame[o] = clampi(
							frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
						)
						frame[o + 1] = clampi(
							(
								frame[o + 1]
								+ (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8)
							),
							0,
							255
						)
						frame[o + 2] = clampi(
							(
								frame[o + 2]
								+ (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8)
							),
							0,
							255
						)
				o += 3
				sp += 4

	## Nearest-neighbour scale blit (pygame.transform.scale), alpha scaled.
	static func _blit_scaled(
		frame: PackedByteArray, art: Dictionary, tw: int, th: int, x: int, y: int, alpha: int
	) -> void:
		var w: int = art["w"]
		var h: int = art["h"]
		var data: PackedByteArray = art["data"]
		if tw <= 0 or th <= 0:
			return
		for ty in th:
			var sy := clampi(ty * h / th, 0, h - 1)
			var gy := y + ty
			if gy < 0 or gy >= Renderer.VIEW:
				continue
			for tx in tw:
				var sx := clampi(tx * w / tw, 0, w - 1)
				var gx := x + tx
				if gx < 0 or gx >= Renderer.WIDTH:
					continue
				var sp := (sy * w + sx) * 4
				var a := data[sp + 3]
				if a == 0:
					continue
				if alpha < 255:
					a = a * alpha / 255
				var o := (gy * Renderer.WIDTH + gx) * 3
				if a == 255:
					frame[o] = data[sp]
					frame[o + 1] = data[sp + 1]
					frame[o + 2] = data[sp + 2]
				else:
					frame[o] = clampi(
						frame[o] + (((data[sp] - frame[o]) * a + data[sp]) >> 8), 0, 255
					)
					frame[o + 1] = clampi(
						frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * a + data[sp + 1]) >> 8),
						0,
						255
					)
					frame[o + 2] = clampi(
						frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * a + data[sp + 2]) >> 8),
						0,
						255
					)

	static func _set_pixel(frame: PackedByteArray, x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= Renderer.WIDTH or y >= Renderer.VIEW:
			return
		var o := (y * Renderer.WIDTH + x) * 3
		frame[o] = roundi(c.r * 255.0)
		frame[o + 1] = roundi(c.g * 255.0)
		frame[o + 2] = roundi(c.b * 255.0)

	static func _fill(frame: PackedByteArray, x: int, y: int, w: int, h: int, c: Color) -> void:
		var r := roundi(c.r * 255.0)
		var g := roundi(c.g * 255.0)
		var b := roundi(c.b * 255.0)
		for yy in range(maxi(0, y), mini(Renderer.VIEW, y + h)):
			for xx in range(maxi(0, x), mini(Renderer.WIDTH, x + w)):
				var o := (yy * Renderer.WIDTH + xx) * 3
				frame[o] = r
				frame[o + 1] = g
				frame[o + 2] = b

	## Bresenham line with an optional square width, matching pg.draw.line.
	static func _line(
		frame: PackedByteArray, x0: int, y0: int, x1: int, y1: int, c: Color, width := 1
	) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		var r := roundi(c.r * 255.0)
		var g := roundi(c.g * 255.0)
		var b := roundi(c.b * 255.0)
		while true:
			if width <= 1:
				if x0 >= 0 and y0 >= 0 and x0 < Renderer.WIDTH and y0 < Renderer.VIEW:
					var o := (y0 * Renderer.WIDTH + x0) * 3
					frame[o] = r
					frame[o + 1] = g
					frame[o + 2] = b
			else:
				_fill(frame, x0, y0, width, width, c)
			if x0 == x1 and y0 == y1:
				break
			var e2 := err * 2
			if e2 >= dy:
				err += dy
				x0 += sx
			if e2 <= dx:
				err += dx
				y0 += sy
