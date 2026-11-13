## The 5v5 store's throwables once they go off (weapons.cfg `thrown`, shots.cfg
## `rolls`; game_combat.gd explode() hands each one here instead of a blast):
##
##   FLASH JAR        a white flash: everyone who can see it is blinded, more
##                    the nearer and the more they face it (FLASH_MOST seconds
##                    at the most), the bots too; a ringing in the ears
##   SMUDGE POT       a cloud of smoke that grows for SMOKE_GROW seconds and
##                    stands SMOKE_LIFE; nobody's sight goes through it (the
##                    bots' is held to that by smoked()), and it puts fire out
##   SHINE COCKTAIL   bursts where it lands into a patch of fire for FIRE_LIFE
##                    seconds that bites everyone in it (FIRE_DAMAGE every
##                    FIRE_BITE seconds, blamed on the thrower); thrown into
##                    smoke it only fizzles
##   FIRECRACKER CAN  rattles off its thrower's gun for DECOY_LIFE seconds,
##                    in bursts; the bots of the other side take it for a foe
##
## What is going on lives in the mode feature (clouds, fires, decoys, blind:
## plain values, carried in snapshots); tick() runs every tick whatever the
## mode (the firing range has the throwables too).
class_name TacticalUtility
extends RefCounted

const KINDS := ["flash_jar", "smudge_pot", "shine_cocktail", "firecracker_can"]
const FLASH_REACH := 16.0
const FLASH_MOST := 4.6
const SMOKE_LIFE := 15.0
const SMOKE_RADIUS := 2.7
const SMOKE_GROW := 1.4
const FIRE_LIFE := 7.0
const FIRE_RADIUS := 2.1
const FIRE_BITE := .25
const FIRE_DAMAGE := 10.0
const DECOY_LIFE := 10.0
## The decoy's rhythm: the gaps between its shots, over and over.
const DECOY_GAPS := [.13, .13, .13, .9, .2, .2, 1.4, .13, .13, .7]


static func burst(game, shot) -> void:
	var st = Modes.feature(game)
	if st == null:
		return
	var x: float = shot.x
	var y: float = shot.y
	var z: float = maxf(.07, shot.z)
	var spec := Shots.blast(String(shot.kind))
	game.sound_at(String(spec.get("cue", "tnt_bounce")), x, y)
	game.wake_nearby(float(spec.get("wake", 8.0)), x, y)
	match String(shot.kind):
		"flash_jar":
			_flash(game, st, x, y, z)
		"smudge_pot":
			st.clouds.append([x, y, game.clock + SMOKE_LIFE, game.clock])
			game.burst(x, y, z, "dust", 16, 1.8)
		"shine_cocktail":
			_firebomb(game, st, shot, x, y, z)
		"firecracker_can":
			st.decoys.append(
				[
					x,
					y,
					game.clock + DECOY_LIFE,
					game.clock + .35,
					int(shot.slot),
					_gun_cue(game, shot.slot),
					0
				]
			)


## Everyone who sees the flash is blinded by how near and how square on.
static func _flash(game, st, x: float, y: float, z: float) -> void:
	game.burst(x, y, z, "spark", 30, 3.2)
	for p: Player in game.players:
		if p.health <= 0:
			continue
		var d := Vector2(p.x - x, p.y - y).length()
		if d >= FLASH_REACH or not game.world.visible(x, y, p.x, p.y, z, p.eye):
			continue
		if smoked(game, x, y, p.x, p.y):
			continue
		var facing := cos(Enemy.angle_delta(atan2(y - p.y, x - p.x), p.view_angle()))
		var k := (1.0 - d / FLASH_REACH) * (.3 + .7 * maxf(0.0, facing))
		if d < 1.6:
			k = maxf(k, .6)  # at your feet it gets you whichever way you look
		var seconds := FLASH_MOST * k
		if seconds < .35:
			continue
		var was: Array = st.blind.get(p.slot, [0.0, 0.0])
		st.blind[p.slot] = [maxf(float(was[0]), game.clock + seconds), maxf(float(was[1]), k)]
		if p == game.local_player:
			game.blast_flash = maxf(game.blast_flash, .5)
			game.sound_at("ear_ring", p.x, p.y, clampf(k * 1.3, .3, 1.0))


static func _firebomb(game, st, shot, x: float, y: float, z: float) -> void:
	game.burst(x, y, z, "glass", 12, 1.6)
	# Against a wall the fire starts a step back from it.
	if game.world.blocked(x, y, .2):
		x -= shot.vx * .06
		y -= shot.vy * .06
	for cloud: Array in st.clouds:
		if Vector2(x - float(cloud[0]), y - float(cloud[1])).length() < SMOKE_RADIUS:
			game.burst(x, y, z, "dust", 10, 1.0)
			return  # thrown into smoke it only fizzles
	game.burst(x, y, z, "spark", 24, 2.2)
	st.fires.append([x, y, game.clock + FIRE_LIFE, game.clock, int(shot.slot)])


## The sound of its thrower's best gun (the decoy's voice).
static func _gun_cue(game, slot: int) -> String:
	if slot < 0 or slot >= game.players.size():
		return "rifle"
	var gun := TacticalShop.best_gun(game.players[slot])
	return String(Weapons.NAMES[gun]) if gun != Weapons.CROWBAR else "revolver"


static func tick(game, st, _dt: float) -> void:
	var now: float = game.clock
	st.clouds = st.clouds.filter(func(c: Array) -> bool: return float(c[2]) > now)
	var fires: Array = []
	for fire: Array in st.fires:
		if float(fire[2]) <= now or _in_smoke(st, now, float(fire[0]), float(fire[1])):
			continue
		fires.append(fire)
		if now >= float(fire[3]):
			fire[3] = now + FIRE_BITE
			_bite(game, fire)
			if int(now * 4.0) % 6 == 0:
				game.sound_at("fire_crackle", float(fire[0]), float(fire[1]), .7)
	st.fires = fires
	var decoys: Array = []
	for decoy: Array in st.decoys:
		if float(decoy[2]) <= now:
			continue
		decoys.append(decoy)
		if now >= float(decoy[3]):
			var k := int(decoy[6])
			decoy[6] = k + 1
			decoy[3] = now + float(DECOY_GAPS[k % DECOY_GAPS.size()])
			game.sound_at(String(decoy[5]), float(decoy[0]), float(decoy[1]))
			game.burst(float(decoy[0]), float(decoy[1]), .1, "spark", 3, .8)
			game.wake_nearby(9.0, float(decoy[0]), float(decoy[1]))
	st.decoys = decoys
	for slot in st.blind.keys():
		if float(st.blind[slot][0]) <= now:
			st.blind.erase(slot)


## Everyone standing in the fire (not over it in a jump) is burned.
static func _bite(game, fire: Array) -> void:
	var x := float(fire[0])
	var y := float(fire[1])
	var slot := int(fire[4])
	var thrower: Player = game.players[slot] if slot >= 0 and slot < game.players.size() else null
	for p: Player in game.players:
		if p.health <= 0 or p.air > .3:
			continue
		if Vector2(p.x - x, p.y - y).length() > FIRE_RADIUS:
			continue
		if not game.world.visible(x, y, p.x, p.y):
			continue
		if thrower != null and Modes.mode_of(game) != Modes.CAMPAIGN:
			var scale: float = Modes.rules(game).hurt_scale(game, thrower, p, true)
			if scale <= 0.0:
				continue
			Modes._blamed(
				game, slot, p, FIRE_DAMAGE * scale / maxf(.05, float(game.incoming)), [x, y], "FIRE"
			)
		else:
			game.damage(FIRE_DAMAGE, [x, y], "FIRE", p)


static func _in_smoke(st, now: float, x: float, y: float) -> bool:
	for cloud: Array in st.clouds:
		if Vector2(x - float(cloud[0]), y - float(cloud[1])).length() < _radius(cloud, now) * .8:
			return true
	return false


static func _radius(cloud: Array, now: float) -> float:
	return SMOKE_RADIUS * clampf((now - float(cloud[3])) / SMOKE_GROW, .25, 1.0)


## Whether smoke stands between (ax, ay) and (bx, by).
static func smoked(game, ax: float, ay: float, bx: float, by: float) -> bool:
	var st = Modes.feature(game)
	if st == null or st.clouds.is_empty():
		return false
	var a := Vector2(ax, ay)
	var b := Vector2(bx, by)
	for cloud: Array in st.clouds:
		var c := Vector2(float(cloud[0]), float(cloud[1]))
		var r := _radius(cloud, game.clock)
		var near := Geometry2D.get_closest_point_to_segment(c, a, b)
		if near.distance_to(c) < r:
			return true
	return false


## How blind `p` is now (0 clear, 1 white).
static func blindness(game, p: Player) -> float:
	var st = Modes.feature(game)
	if st == null or not st.blind.has(p.slot):
		return 0.0
	var row: Array = st.blind[p.slot]
	var left: float = float(row[0]) - game.clock
	return clampf(left / 1.4, 0.0, 1.0) * clampf(float(row[1]) * 1.6, 0.0, 1.0)


# ------------------------------------------------------------------ looks


## The smoke's billows, the fire's flames and a decoy's can (pooled sprites).
static func sprites(game, st) -> Array:
	var out: Array = []
	var now: float = game.clock
	for cloud: Array in st.clouds:
		var cx := float(cloud[0])
		var cy := float(cloud[1])
		if not game.in_view(cx, cy, SMOKE_RADIUS + 1.0):
			continue
		var r := _radius(cloud, now)
		var fade := clampf((float(cloud[2]) - now) / 2.0, 0.0, 1.0)
		var ground: float = game.world.elevation(cx, cy)
		for k in 18:
			var a := k * 2.39996 + float(cloud[3])
			var reach := r * sqrt((k + .5) / 18.0) * .85
			var x := cx + cos(a) * reach + sin(now * .4 + k) * .12
			var y := cy + sin(a) * reach + cos(now * .37 + k) * .12
			if game.world.blocked(x, y, .1):
				continue
			var high := (
				(1.5 + .5 * sin(k * 1.7))
				* clampf(r / SMOKE_RADIUS + .3, .4, 1.0)
				* (.5 + .5 * fade)
			)
			var image := "fx_smokecloud_%d" % (k % 4)
			var lift := ground + (k % 3) * .35 - .15
			out.append(game.pooled(x, y, image, high, lift))
	for fire: Array in st.fires:
		var fx := float(fire[0])
		var fy := float(fire[1])
		if not game.in_view(fx, fy, FIRE_RADIUS + .5):
			continue
		var dying := clampf((float(fire[2]) - now) / 1.2, .3, 1.0)
		for k in 9:
			var a := k * 2.39996
			var reach := FIRE_RADIUS * sqrt((k + .5) / 9.0) * .8
			var x := fx + cos(a) * reach
			var y := fy + sin(a) * reach
			if game.world.blocked(x, y, .05):
				continue
			var frame := (int(now * 12.0) + k) % 4
			var spr = game.pooled(
				x,
				y,
				"fx_flame_%d" % frame,
				(.55 + .25 * ((k * 7) % 3)) * dying,
				game.world.elevation(x, y)
			)
			spr.glow = true
			out.append(spr)
	for decoy: Array in st.decoys:
		var dx := float(decoy[0])
		var dy := float(decoy[1])
		if game.in_view(dx, dy, .5):
			out.append(game.pooled(dx, dy, "fx_firecracker_can", .15, game.world.elevation(dx, dy)))
	return out


## The white-out of a flash, over this machine's player's view.
static func draw_flash(c: Canvas, game) -> void:
	var white := blindness(game, game.local_player)
	if white <= .02:
		return
	var level := clampi(roundi(white * 10.0), 1, 10)
	var w := Renderer.WIDTH
	var h := Renderer.VIEW
	if not _whites.has(level):
		var data := PackedByteArray()
		data.resize(w * h * 4)
		var alpha := mini(255, int(level * 25.5))
		for i in w * h:
			data[i * 4] = 255
			data[i * 4 + 1] = 252
			data[i * 4 + 2] = 236
			data[i * 4 + 3] = alpha
		_whites[level] = data
	c.blit_rgba(_whites[level], w, h, 0, 0, "flash_white_%d" % level)


static var _whites := {}
