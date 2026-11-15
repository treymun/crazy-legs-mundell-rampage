## The firing range's targets (src/range_layout.gd says where): boards, gongs,
## straw dummies and plywood cows that spin and swing when hit, the bowling
## alley's lane (range_bowling.gd), and the duck gallery's movers. None of them is in the
## level's walls: a bullet is tested against them along its trace (the game's
## `traced` event) and a projectile as it flies, and they keep the score the
## range's cards show. Looks only: its own dice, never the game's.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const Bowling := preload("res://src/range_bowling.gd")
## Inches in a map cell, for groupings (a cell is about a yard).
const INCHES := 36.0

var dice := RandomNumberGenerator.new()
## Each: {id, station, kind, x, y, hits, spin (seconds left), last [gun, damage,
## distance, offset in cells], offsets (the last six), dps: [[clock, damage]]}.
var targets: Array = []
## The Bowl-O-Rama: its pins, ball, pinsetter and score sheet.
var bowling := Bowling.new()
## The newest ball seen thrown (its uid), the thrower's heading a tick ago and
## how fast they have been turning (radians a second, smoothed over a tenth of
## a second): how they turned as they let go is the ball's hook.
var last_ball := 0
var last_angle := 0.0
var turn_rate := 0.0
## The gallery: movers {row, x, dir, down_until}, the round.
var movers: Array = []
var gallery_on := false
var gallery_clock := 0.0
var gallery_score := 0
var gallery_hits := 0
var gallery_shots := 0
var gallery_best := 0
var gallery_last := ""
## Shots already counted against a target: shot instance id -> true.
var counted := {}


func _init() -> void:
	dice.seed = 1997
	for row: Array in L.TARGETS:
		var row_x: float = row[3]
		var row_y: float = row[4]
		(
			targets
			. append(
				{
					"id": str(row[0]),
					"station": str(row[1]),
					"kind": str(row[2]),
					"x": row_x,
					"y": row_y,
					"hits": 0,
					"spin": 0.0,
					"last": [],
					"offsets": [],
					"dps": [],
				}
			)
		)
	for r in L.GALLERY_ROWS.size():
		for k in 3:
			(
				movers
				. append(
					{
						"row": r,
						"x": lerpf(L.GALLERY_X[0], L.GALLERY_X[1], (k + .5 * r) / 3.0),
						"dir": 1.0 if (k + r) % 2 == 0 else -1.0,
						"down_until": 0.0,
					}
				)
			)


## The lever: a fresh rack and a new game.
func rack() -> void:
	bowling.new_game()


func pins_down() -> int:
	return bowling.pins_down()


func reset_targets() -> void:
	for t: Dictionary in targets:
		t["hits"] = 0
		t["spin"] = 0.0
		t["last"] = []
		t["offsets"] = []
		t["dps"] = []


# ------------------------------------------------------------------- hitting


## Where along the segment a body at (x, y) from z0 to z1 up, `radius` across,
## is crossed: the share of the way (0 to 1), or -1 when it is missed. Also
## the miss distance from its middle, in cells.
static func crossing(
	s: Vector3, e: Vector3, x: float, y: float, z_mid: float, half: float, radius: float
) -> Vector2:
	var d := Vector2(e.x - s.x, e.y - s.y)
	var length := d.length_squared()
	if length < 1e-6:
		return Vector2(-1, 0)
	var t := ((x - s.x) * d.x + (y - s.y) * d.y) / length
	if t <= 0.0 or t > 1.04:
		return Vector2(-1, 0)
	var across := Vector2(s.x + d.x * t - x, s.y + d.y * t - y).length()
	var z := s.z + (e.z - s.z) * t
	if across > radius or absf(z - z_mid) > half:
		return Vector2(-1, 0)
	return Vector2(t, Vector2(across, (z - z_mid) * .6).length())


## A bullet, pellet, swing or squirt from `s` that ended at `e`: the nearest
## target it crossed takes it. Returns what was hit ({} for nothing).
func trace(game: Game, s: Vector3, e: Vector3, gun: int, damage: float) -> Dictionary:
	var best := {}
	var best_t := 9.0
	var miss := 0.0
	for t: Dictionary in targets:
		var spec: Array = L.TARGET_KINDS[t["kind"]]
		var tx: float = t["x"]
		var ty: float = t["y"]
		var floor_z: float = game.world.elevation(tx, ty)
		var spec_reach: float = spec[2]
		var spec_lift: float = spec[3]
		var spec_half: float = spec[4]
		var hit := crossing(s, e, tx, ty, floor_z + spec_lift, spec_half, spec_reach)
		if hit.x >= 0.0 and hit.x < best_t:
			best_t = hit.x
			best = t
			miss = hit.y
	for m: Dictionary in movers:
		var down_until: float = m["down_until"]
		if game.clock < down_until:
			continue
		var row: Array = L.GALLERY_ROWS[m["row"]]
		var size: float = row[3]
		var mx: float = m["x"]
		var row_y: float = row[0]
		var row_lift: float = row[1]
		var floor_z2: float = game.world.elevation(mx, row_y)
		var hit2 := crossing(
			s, e, mx, row_y, floor_z2 + row_lift + size * .5, size * .5, size * .45
		)
		if hit2.x >= 0.0 and hit2.x < best_t:
			best_t = hit2.x
			best = m
	var pin_hit := bowling.shot_at(s, e, crossing)
	var pin_t: float = pin_hit.get("t", 0.0)
	if not pin_hit.is_empty() and pin_t < best_t:
		best_t = pin_t
		best = {"pin": pin_hit["pin"]}
	if best.is_empty():
		return {}
	var distance := Vector2(e.x - s.x, e.y - s.y).length() * best_t
	if best.has("row"):
		_gallery_hit(game, best)
		return {"gallery": true}
	if best.has("pin"):
		var pin: Dictionary = best["pin"]
		bowling.shot_knock(game, pin, Vector2(e.x - s.x, e.y - s.y), damage)
		return {"pin": true}
	_struck(game, best, gun, damage, distance, miss)
	return best


func _struck(
	game: Game, t: Dictionary, gun: int, damage: float, distance: float, miss: float
) -> void:
	var hits: int = t["hits"]
	t["hits"] = hits + 1
	t["spin"] = .7
	t["last"] = [gun, damage, distance, miss]
	var offsets: Array = t["offsets"]
	offsets.append(miss)
	if offsets.size() > 6:
		offsets.pop_front()
	var dps: Array = t["dps"]
	dps.append([game.clock, damage])
	while not dps.is_empty():
		var oldest: Array = dps[0]
		var oldest_at: float = oldest[0]
		if not (game.clock - oldest_at > 3.0):
			break
		dps.pop_front()
	var cue := "range_gong" if str(t["kind"]) == "gong" else "range_board_hit"
	if str(t["kind"]) == "dummy":
		cue = "range_dummy_thwack"
	var tx: float = t["x"]
	var ty: float = t["y"]
	game.sound_at(cue, tx, ty, .55)


## The group a target's last shots made: the average miss, in inches.
static func grouping(t: Dictionary) -> int:
	var offsets: Array = t["offsets"]
	if offsets.is_empty():
		return 0
	var sum := 0.0
	for o: float in offsets:
		sum += o
	return roundi(sum / offsets.size() * INCHES)


static func dps(t: Dictionary, now: float) -> int:
	var total := 0.0
	for row: Array in t["dps"]:
		var at: float = row[0]
		if now - at <= 3.0:
			var amount: float = row[1]
			total += amount
	return roundi(total / 3.0)


## A blast at (x, y): every target near it spins, pins within reach fall.
func blast(game: Game, x: float, y: float) -> void:
	for t: Dictionary in targets:
		var tx: float = t["x"]
		var ty: float = t["y"]
		var d := Vector2(tx - x, ty - y).length()
		if d < 2.6:
			t["spin"] = 1.2
			var hits: int = t["hits"]
			t["hits"] = hits + 1
			t["last"] = [game.armory.active, -1.0, d, 0.0]
	bowling.blast(game, x, y)


## Projectiles in flight: a bowling ball takes pins, anything else that
## would burst bursts on a target, a blade sails through it.
func shots(game: Game) -> void:
	var burst: Array = []
	for shot: GameState.Shot in game.shots:
		if shot.enemy:
			continue
		var key: int = shot.get_instance_id()
		if shot.kind == "bowling":
			if shot.uid > last_ball:
				last_ball = shot.uid
				bowling.thrown(shot, turn_rate)
		for t: Dictionary in targets:
			var spec: Array = L.TARGET_KINDS[t["kind"]]
			var tx: float = t["x"]
			var ty: float = t["y"]
			var floor_z: float = game.world.elevation(tx, ty)
			var spec_reach: float = spec[2]
			var spec_lift: float = spec[3]
			var spec_half: float = spec[4]
			if (
				Vector2(tx - shot.x, ty - shot.y).length() < spec_reach + .12
				and absf(shot.z - floor_z - spec_lift) < spec_half + .1
				and not counted.has([key, t["id"]])
			):
				counted[[key, t["id"]]] = true
				var distance := Vector2(tx - game.player.x, ty - game.player.y).length()
				_struck(game, t, game.armory.active, float(shot.damage), distance, 0.0)
				if Shots.explodes(shot.kind) and shot.kind != "tnt":
					burst.append(shot)
		for m: Dictionary in movers:
			var down_until: float = m["down_until"]
			if game.clock < down_until:
				continue
			var row: Array = L.GALLERY_ROWS[m["row"]]
			var mx: float = m["x"]
			var row_y: float = row[0]
			var row_lift: float = row[1]
			var row_size: float = row[3]
			if (
				Vector2(mx - shot.x, row_y - shot.y).length() < .3
				and absf(shot.z - row_lift - row_size * .5) < .4
			):
				_gallery_hit(game, m)
	for shot: GameState.Shot in burst:
		game.finish_shot(shot)
		game.shots.erase(shot)
	if counted.size() > 400:
		counted.clear()


# ------------------------------------------------------------------- gallery


func start_gallery(game: Game) -> void:
	gallery_on = true
	gallery_clock = 0.0
	gallery_score = 0
	gallery_hits = 0
	gallery_shots = 0
	gallery_last = ""
	for m: Dictionary in movers:
		m["down_until"] = 0.0
	game.sound.play("menu_accept")


func _gallery_hit(game: Game, m: Dictionary) -> void:
	m["down_until"] = game.clock + 1.1
	var row: Array = L.GALLERY_ROWS[m["row"]]
	var mx: float = m["x"]
	var row_y: float = row[0]
	game.sound_at("range_gallery_ding", mx, row_y, .5)
	if gallery_on:
		gallery_hits += 1
		var points: int = row[4]
		gallery_score += points


func tick_gallery(game: Game, dt: float) -> void:
	var pace := 1.0 if gallery_on else .35
	if gallery_on:
		gallery_clock += dt
		# The movers speed up as the round goes on.
		pace += gallery_clock / L.GALLERY_TIME * .8
	for m: Dictionary in movers:
		var row: Array = L.GALLERY_ROWS[m["row"]]
		var mx: float = m["x"]
		var dir: float = m["dir"]
		var row_speed: float = row[5]
		m["x"] = mx + dir * row_speed * pace * dt
		var moved: float = m["x"]
		if moved > L.GALLERY_X[1]:
			m["x"] = L.GALLERY_X[1]
			m["dir"] = -1.0
		elif moved < L.GALLERY_X[0]:
			m["x"] = L.GALLERY_X[0]
			m["dir"] = 1.0
	if gallery_on and gallery_clock >= L.GALLERY_TIME:
		gallery_on = false
		var aim := roundi(gallery_hits * 100.0 / maxf(1.0, gallery_shots))
		var ribbon := (
			"BLUE RIBBON"
			if gallery_score >= 24
			else (
				"RED RIBBON"
				if gallery_score >= 14
				else "WHITE RIBBON" if gallery_score >= 7 else "CITY SLICKER"
			)
		)
		gallery_best = maxi(gallery_best, gallery_score)
		gallery_last = "%d POINTS, %d%% AIM: %s" % [gallery_score, aim, ribbon]
		game.message("TIME! " + gallery_last, 4.0)
		game.callout = ribbon
		game.callout_until = game.clock + 1.8
		game.sound.play("range_gallery_buzzer")


# ------------------------------------------------------------------- drawing


func sprites(game: Game) -> Array:
	var out: Array = []
	for t: Dictionary in targets:
		var tx: float = t["x"]
		var ty: float = t["y"]
		if not game.in_view(tx, ty, 1.0):
			continue
		var spec: Array = L.TARGET_KINDS[t["kind"]]
		var x := tx
		var spin: float = t["spin"]
		var spec_height: float = spec[1]
		var sprite := View.Sprite.new(x, ty, str(spec[0]), spec_height, game.world.elevation(x, ty))
		var kind := str(t["kind"])
		if kind == "cow":
			sprite.plane = 0.0
		if spin > 0.0:
			if kind == "board" or kind == "cow":
				# Hit: it spins on its stand, slowing.
				sprite.plane = spin * spin * 14.0
			else:
				# A gong swings, a dummy rocks.
				sprite.x = x + sin(spin * 22.0) * spin * .12
		out.append(sprite)
	var eye: Player = game.local_player
	out.append_array(bowling.sprites(game, Vector2(eye.x, eye.y)))
	for m: Dictionary in movers:
		var row: Array = L.GALLERY_ROWS[m["row"]]
		var down_until: float = m["down_until"]
		var mx: float = m["x"]
		var row_y: float = row[0]
		if game.clock < down_until or not game.in_view(mx, row_y, .5):
			continue
		var row_size: float = row[3]
		var row_lift: float = row[1]
		var s := View.Sprite.new(mx, row_y, str(row[2]), row_size, row_lift)
		s.plane = 0.0
		var dir: float = m["dir"]
		s.flip = dir < 0.0
		out.append(s)
	return out


func tick(game: Game, dt: float) -> void:
	for t: Dictionary in targets:
		var spin: float = t["spin"]
		if spin > 0.0:
			t["spin"] = maxf(0.0, spin - dt)
	bowling.tick(game, dt)
	tick_gallery(game, dt)
	var turn := wrapf(game.player.angle - last_angle, -PI, PI) / maxf(dt, .001)
	turn_rate += (turn - turn_rate) * minf(1.0, dt * 10.0)
	last_angle = game.player.angle
	shots(game)
