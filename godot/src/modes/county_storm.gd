## COUNTY RUN's storm front (CLAUDE.md "County Run"): as the run goes on a
## storm sweeps across the map, a dark wall of rain and wind closing the safe
## ground in stages. Each stage is called on the HUD and the map
## (`warn` seconds ahead), then the wall closes for `close` seconds to a
## smaller circle inside the last; outside it the wind pushes a player round
## and the storm hurts (more each stage), and near its wall it throws boards,
## tin and hay that hurt whoever they hit. The safe ground never shrinks
## below `least`, and the first stage waits long enough that a normal run
## still lasts (county.json "storm").
##
## The state is the county feature's (`storm_*`, plain values, carried); its
## dice are its own, seeded from the run's at the start, so a DAILY RUN's
## storm is everyone's and a party's is the same on every machine. COUNTY
## STORM off (game.storm_on) leaves it out of a run (never a DAILY RUN's).
class_name CountyStorm
extends RefCounted

const CountyRun := preload("res://src/features/county_run.gd")
const Climate := preload("res://src/features/climate.gd")
## The pieces it throws (existing break bits: boards, tin, hay).
const BITS := [
	"fx_brk_wood_0", "fx_brk_wood_1", "fx_brk_tin_0", "fx_brk_redtin_1", "fx_brk_straw_0"
]


static func number(key: String, fallback: float) -> float:
	return CountyData.number("storm", key, fallback)


## The run starts: the storm's dice from the run's, the safe ground the whole
## map (round the middle of the ground the start walks to).
static func begin(game: Game, f: CountyRun) -> void:
	f.storm_on = game.storm_on or f.daily != ""
	f.storm_stage = 0
	f.storm_bits = []
	if not f.storm_on:
		return
	f.storm_dice.seed = hash("%d/%s" % [game.rng.get_state(), f.map_id])
	var spots := CountySpawner.spots(game)
	var middle := Vector2(game.level.spawn[0], game.level.spawn[1])
	if not spots.is_empty():
		var sum := Vector2.ZERO
		for at: Vector2 in spots:
			sum += at
		middle = sum / spots.size()
	var reach := 0.0
	for at: Vector2 in spots:
		reach = maxf(reach, at.distance_to(middle))
	f.storm_at = middle
	f.storm_home = middle
	f.storm_r = reach + 3.0
	f.storm_full = f.storm_r
	f.storm_from = Vector3(middle.x, middle.y, f.storm_r)
	f.storm_to = f.storm_from
	f.storm_moving = Vector2(-1.0, -1.0)
	f.storm_next = number("first", 120.0)
	f.storm_bit_next = 0.0
	f.storm_hurt_next = 0.0


## How far into the storm the run is (0 before the first stage, 1 at the
## last): the climate's rain and wind build with it.
static func strength(f: CountyRun) -> float:
	if not f.storm_on:
		return 0.0
	var most := maxf(1.0, float(_radii().size()))
	var stage := float(f.storm_stage)
	if f.storm_moving.x >= 0.0:
		stage -= 1.0 - _closing(f)
	if stage <= 0.0:
		return .2 if f.storm_warned else 0.0
	return clampf(.3 + .7 * stage / most, 0.0, 1.0)


static func _radii() -> Array:
	var out: Variant = CountyData.section("storm").get("radii", [.72, .52, .38, .28, .2])
	return out if out is Array else []


## How far the wall has closed this stage (0 to 1, eased).
static func _closing(f: CountyRun) -> float:
	var span := maxf(.01, f.storm_moving.y - f.storm_moving.x)
	return smoothstep(0.0, 1.0, clampf((f.run_time - f.storm_moving.x) / span, 0.0, 1.0))


## Seconds until the next stage closes in (-1 when none is called).
static func called_in(f: CountyRun) -> float:
	if not f.storm_on or f.storm_moving.x >= 0.0 or f.storm_stage >= _radii().size():
		return -1.0
	var left := f.storm_next - f.run_time
	return left if left <= number("warn", 30.0) else -1.0


## Whether (x, y) is out in the storm.
static func outside(f: CountyRun, x: float, y: float) -> bool:
	return f.storm_on and f.storm_at.distance_to(Vector2(x, y)) > f.storm_r


## Every tick of a run: the stages, the wall, the hurt and the push, the
## pieces thrown; the climate's rain and wind follow.
static func tick(game: Game, f: CountyRun, dt: float) -> void:
	var climate: Climate = game.features.get("climate")
	if not f.storm_on:
		return
	_stages(game, f)
	if climate != null:
		climate.storm = strength(f)
		climate.storm_angle = f.storm_dice_angle
	if f.storm_stage == 0 and f.storm_moving.x < 0.0:
		return
	_hurt(game, f, dt)
	_throw(game, f)
	_fly(game, f, dt)


static func _stages(game: Game, f: CountyRun) -> void:
	var t := f.run_time
	var radii := _radii()
	if f.storm_moving.x >= 0.0:
		var k := _closing(f)
		var from := Vector2(f.storm_from.x, f.storm_from.y)
		var to := Vector2(f.storm_to.x, f.storm_to.y)
		f.storm_at = from.lerp(to, k)
		f.storm_r = lerpf(f.storm_from.z, f.storm_to.z, k)
		if t >= f.storm_moving.y:
			f.storm_moving = Vector2(-1.0, -1.0)
			f.storm_next = t + number("every", 150.0)
			Modes.say(game, "THE STORM HOLDS. FOR NOW.", 2.4)
		return
	if f.storm_stage >= radii.size():
		return
	var warn := number("warn", 30.0)
	if t >= f.storm_next - warn and not f.storm_warned:
		f.storm_warned = true
		Modes.say(game, "STORM FRONT COMIN'! GET INSIDE THE RING.", 3.0)
		game.sound.play("thunder", .8)
	if t < f.storm_next:
		return
	# The wall starts closing: a new ring inside the last, the dice say where.
	var share: float = radii[f.storm_stage]
	var r := maxf(number("least", 9.0), f.storm_full * share)
	var at := _new_middle(game, f, r)
	f.storm_from = Vector3(f.storm_at.x, f.storm_at.y, f.storm_r)
	f.storm_to = Vector3(at.x, at.y, r)
	f.storm_moving = Vector2(t, t + number("close", 30.0))
	f.storm_stage += 1
	f.storm_warned = false
	f.storm_dice_angle = f.storm_dice.randf() * TAU
	Modes.say(game, "THE STORM IS CLOSIN' IN!", 2.6)


## Where the next ring's middle goes: ground the start walks to, inside the
## last ring so the new one fits in it.
static func _new_middle(game: Game, f: CountyRun, r: float) -> Vector2:
	var spots := CountySpawner.spots(game)
	var room := maxf(0.0, f.storm_r - r)
	for _k in 60:
		if spots.is_empty():
			break
		var at: Vector2 = spots[f.storm_dice.randi_range(0, spots.size() - 1)]
		if at.distance_to(f.storm_at) <= room * .8:
			return at
	return f.storm_at


## Outside the ring the storm hurts and the wind shoves a player round its
## wall (and a little back in): twice a second, harder each stage.
static func _hurt(game: Game, f: CountyRun, dt: float) -> void:
	var push := number("push", .9)
	for p: Player in game.players:
		if p.health <= 0 or not outside(f, p.x, p.y):
			continue
		var out := Vector2(p.x, p.y) - f.storm_at
		var along := Vector2(-out.y, out.x).normalized()
		var shove := (along * .8 - out.normalized() * .45) * push * dt
		game.move_actor(p, shove.x, shove.y, Game.PLAYER_RADIUS)
	if f.run_time < f.storm_hurt_next:
		return
	f.storm_hurt_next = f.run_time + .5
	var hurts: Variant = CountyData.section("storm").get("hurt", [3, 4, 6, 8, 10])
	var list: Array = hurts if hurts is Array else [4]
	var each: float = list[clampi(f.storm_stage - 1, 0, list.size() - 1)]
	for p: Player in game.players:
		if p.health > 0 and outside(f, p.x, p.y):
			game.damage(each * .5, [f.storm_at.x, f.storm_at.y], "STORM", p)


## Now and then a board, a sheet of tin or a hay flake comes off the wall
## near a player, flying with the storm's wind.
static func _throw(game: Game, f: CountyRun) -> void:
	if f.run_time < f.storm_bit_next or f.storm_bits.size() >= int(number("bits_most", 14)):
		return
	var every := number("bit_every", 1.4) / (1.0 + .35 * f.storm_stage)
	f.storm_bit_next = f.run_time + every * f.storm_dice.randf_range(.6, 1.4)
	var p: Player = game.players[f.storm_dice.randi_range(0, game.players.size() - 1)]
	if p.health <= 0:
		return
	var gap := Vector2(p.x, p.y).distance_to(f.storm_at)
	if absf(gap - f.storm_r) > number("bit_reach", 9.0):
		return
	# From the wall, beside the player, toward and past them.
	var off := Vector2(p.x, p.y) - f.storm_at
	var bearing := off.angle() + f.storm_dice.randf_range(-.35, .35)
	var from := f.storm_at + Vector2.from_angle(bearing) * (f.storm_r + 1.5)
	var w: LevelData = game.world
	from = from.clamp(Vector2(1.0, 1.0), Vector2(w.width - 1.5, w.height - 1.5))
	var aim := (
		Vector2(p.x, p.y)
		+ Vector2(f.storm_dice.randf_range(-1.5, 1.5), f.storm_dice.randf_range(-1.5, 1.5))
	)
	var fly := aim - from
	var speed := f.storm_dice.randf_range(5.0, 8.0)
	var v := fly.normalized() * speed
	var picture: String = BITS[f.storm_dice.randi_range(0, BITS.size() - 1)]
	var z: float = game.world.elevation(from.x, from.y) + f.storm_dice.randf_range(1.4, 2.4)
	# [x, y, z, vx, vy, vz, picture, age]
	f.storm_bits.append([from.x, from.y, z, v.x, v.y, 1.0, picture, 0.0])


## The pieces in the air: they fall a little, strike walls and drop, and hurt
## a player they hit (once), then lie a moment and are gone.
static func _fly(game: Game, f: CountyRun, dt: float) -> void:
	if f.storm_bits.is_empty():
		return
	var keep: Array = []
	var damage := number("bit_damage", 9.0)
	for bit: Array in f.storm_bits:
		var age: float = bit[7]
		age += dt
		bit[7] = age
		if age > 4.0:
			continue
		keep.append(bit)
		var vx: float = bit[3]
		var vy: float = bit[4]
		var vz: float = bit[5]
		if vx == 0.0 and vy == 0.0 and vz == 0.0:
			continue
		var x: float = bit[0]
		var y: float = bit[1]
		var z: float = bit[2]
		var nx := x + vx * dt
		var ny := y + vy * dt
		var nz := z + vz * dt
		if nx < .5 or ny < .5 or nx > game.world.width - .5 or ny > game.world.height - .5:
			keep.pop_back()
			continue
		vz -= 4.0 * dt
		var low := game.world.elevation(nx, ny)
		if nz <= low + .05 or game.world.blocked(nx, ny, .05, nz):
			# Down: it lies where it fell.
			bit[3] = 0.0
			bit[4] = 0.0
			bit[5] = 0.0
			bit[2] = maxf(low + .03, minf(z, low + .03))
			game.sound_at("impact_wood", x, y, .5)
			continue
		bit[0] = nx
		bit[1] = ny
		bit[2] = nz
		bit[5] = vz
		for p: Player in game.players:
			if p.health <= 0:
				continue
			var feet := game.world.stand(p)
			if Vector2(p.x - nx, p.y - ny).length() < .45 and nz < p.eye + .2 and nz > feet:
				game.damage(damage, [x, y], "DEBRIS", p)
				game.move_actor(p, vx * .05, vy * .05, Game.PLAYER_RADIUS)
				bit[3] = vx * -.2
				bit[4] = vy * -.2
				break
	f.storm_bits = keep


## The pieces as sprites, tumbling while they fly.
static func sprites(game: Game, f: CountyRun) -> Array:
	var out: Array = []
	for bit: Array in f.storm_bits:
		var x: float = bit[0]
		var y: float = bit[1]
		if not game.in_view(x, y, .6):
			continue
		var z: float = bit[2]
		var s: View.Sprite = game.pooled(x, y, str(bit[6]), .32, z)
		var vx: float = bit[3]
		var age: float = bit[7]
		if vx != 0.0:
			s.spin = age * 9.0
		else:
			s.lying = true
		out.append(s)
	return out


# ------------------------------------------------------------------ on screen

const RING := Color(150 / 255.0, 170 / 255.0, 200 / 255.0)
const STORM_INK := Color(120 / 255.0, 150 / 255.0, 210 / 255.0)
const WALL := Color(70 / 255.0, 76 / 255.0, 96 / 255.0)


## The HUD: the stage called ("STORM FRONT 0:25"), the wall closing, a
## warning when out in it, and the small map of the ring in the corner.
static func draw_hud(c: Canvas, game: Game, f: CountyRun) -> void:
	if not f.storm_on or (f.storm_stage == 0 and not f.storm_warned):
		return
	var p: Player = game.player
	var line := ""
	var ink := STORM_INK
	var left := called_in(f)
	if outside(f, p.x, p.y):
		line = "OUT IN THE STORM! GET IN THE RING!"
		ink = HUD.LOW_HOT if int(game.clock * 4.0) % 2 == 0 else HUD.LOW
	elif f.storm_moving.x >= 0.0:
		line = "THE STORM IS CLOSIN' IN"
	elif left >= 0.0:
		line = "STORM FRONT %d:%02d" % [int(left) / 60, int(left) % 60]
	if line != "":
		HUD.text(c, line, 160, 20, "body", ink, true, true, true)
	_corner(c, game, f)


## The ring in the corner: the whole map's circle dim, the safe ring, the
## ring it is closing to, and the player.
static func _corner(c: Canvas, game: Game, f: CountyRun) -> void:
	var size := 32
	var x0 := 320 - size - 3
	var y0 := 3
	c.fill_rect(x0, y0, size, size, Color(.08, .07, .07))
	c.rect_outline(x0, y0, size, size, WALL)
	var middle := Vector2(x0 + size / 2.0, y0 + size / 2.0)
	var scale := (size / 2.0 - 2.0) / maxf(1.0, f.storm_full)
	var whole := f.storm_home
	var at := middle + (f.storm_at - whole) * scale
	c.circle(int(at.x), int(at.y), maxi(1, roundi(f.storm_r * scale)), RING, false)
	if f.storm_moving.x >= 0.0:
		var to := middle + (Vector2(f.storm_to.x, f.storm_to.y) - whole) * scale
		c.circle(
			int(to.x), int(to.y), maxi(1, roundi(f.storm_to.z * scale)), CountyScreens.GOLD, false
		)
	for q: Player in game.players:
		if q.health <= 0:
			continue
		var dot := middle + (Vector2(q.x, q.y) - whole) * scale
		dot = dot.clamp(Vector2(x0 + 1, y0 + 1), Vector2(x0 + size - 2, y0 + size - 2))
		var mine := q == game.local_player
		c.fill_rect(
			int(dot.x),
			int(dot.y),
			2 if mine else 1,
			2 if mine else 1,
			HUD.INK if mine else HUD.AMBER
		)


## The automap (TAB): the safe ring and, while it closes, where it is going
## (dotted round, only inside the map's window).
static func draw_map(c: Canvas, game: Game) -> void:
	var f := CountyMode.run(game)
	if f == null or not f.storm_on or f.storm_stage == 0 and not f.storm_warned:
		return
	_map_ring(c, game, f.storm_at, f.storm_r, RING)
	if f.storm_moving.x >= 0.0:
		_map_ring(c, game, Vector2(f.storm_to.x, f.storm_to.y), f.storm_to.z, CountyScreens.GOLD)


static func _map_ring(c: Canvas, game: Game, at: Vector2, r: float, ink: Color) -> void:
	var steps := clampi(roundi(r * game.map_view.scale_now * 4.0), 24, 400)
	for k in steps:
		var a := TAU * k / steps
		var dot: Vector2 = game.map_view.point(at.x + cos(a) * r, at.y + sin(a) * r)
		if game.map_view.shows(dot):
			c.fill_rect(int(dot.x), int(dot.y), 1, 1, ink)
