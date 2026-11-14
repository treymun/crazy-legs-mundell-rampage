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
		(
			targets
			. append(
				{
					"id": String(row[0]),
					"station": String(row[1]),
					"kind": String(row[2]),
					"x": float(row[3]),
					"y": float(row[4]),
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
func trace(game, s: Vector3, e: Vector3, gun: int, damage: float) -> Dictionary:
	var best := {}
	var best_t := 9.0
	var miss := 0.0
	for t: Dictionary in targets:
		var spec: Array = L.TARGET_KINDS[t["kind"]]
		var floor_z: float = game.world.elevation(t["x"], t["y"])
		var hit := crossing(
			s, e, t["x"], t["y"], floor_z + float(spec[3]), float(spec[4]), float(spec[2])
		)
		if hit.x >= 0.0 and hit.x < best_t:
			best_t = hit.x
			best = t
			miss = hit.y
	for m: Dictionary in movers:
		if game.clock < float(m["down_until"]):
			continue
		var row: Array = L.GALLERY_ROWS[m["row"]]
		var size := float(row[3])
		var floor_z2: float = game.world.elevation(m["x"], row[0])
		var hit2 := crossing(
			s, e, m["x"], float(row[0]), floor_z2 + float(row[1]) + size * .5, size * .5, size * .45
		)
		if hit2.x >= 0.0 and hit2.x < best_t:
			best_t = hit2.x
			best = m
	var pin_hit := bowling.shot_at(s, e, crossing)
	if not pin_hit.is_empty() and float(pin_hit["t"]) < best_t:
		best_t = float(pin_hit["t"])
		best = {"pin": pin_hit["pin"]}
	if best.is_empty():
		return {}
	var distance := Vector2(e.x - s.x, e.y - s.y).length() * best_t
	if best.has("row"):
		_gallery_hit(game, best)
		return {"gallery": true}
	if best.has("pin"):
		bowling.shot_knock(game, best["pin"], Vector2(e.x - s.x, e.y - s.y), damage)
		return {"pin": true}
	_struck(game, best, gun, damage, distance, miss)
	return best


func _struck(game, t: Dictionary, gun: int, damage: float, distance: float, miss: float) -> void:
	t["hits"] = int(t["hits"]) + 1
	t["spin"] = .7
	t["last"] = [gun, damage, distance, miss]
	var offsets: Array = t["offsets"]
	offsets.append(miss)
	if offsets.size() > 6:
		offsets.pop_front()
	var dps: Array = t["dps"]
	dps.append([game.clock, damage])
	while not dps.is_empty() and game.clock - float(dps[0][0]) > 3.0:
		dps.pop_front()
	var cue := "range_gong" if String(t["kind"]) == "gong" else "range_board_hit"
	if String(t["kind"]) == "dummy":
		cue = "range_dummy_thwack"
	game.sound_at(cue, t["x"], t["y"], .55)


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
		if now - float(row[0]) <= 3.0:
			total += float(row[1])
	return roundi(total / 3.0)


## A blast at (x, y): every target near it spins, pins within reach fall.
func blast(game, x: float, y: float) -> void:
	for t: Dictionary in targets:
		var d := Vector2(t["x"] - x, t["y"] - y).length()
		if d < 2.6:
			t["spin"] = 1.2
			t["hits"] = int(t["hits"]) + 1
			t["last"] = [game.armory.active, -1.0, d, 0.0]
	bowling.blast(game, x, y)


## Projectiles in flight: a bowling ball takes pins, anything else that
## would burst bursts on a target, a blade sails through it.
func shots(game, dt: float) -> void:
	var burst: Array = []
	for shot in game.shots:
		if shot.enemy:
			continue
		var key: int = shot.get_instance_id()
		if shot.kind == "bowling":
			if shot.uid > last_ball:
				last_ball = shot.uid
				bowling.thrown(shot, turn_rate)
			if shot.uid == bowling.ball_uid:
				bowling.roll_ball(game, shot, dt)
		for t: Dictionary in targets:
			var spec: Array = L.TARGET_KINDS[t["kind"]]
			var floor_z: float = game.world.elevation(t["x"], t["y"])
			if (
				Vector2(t["x"] - shot.x, t["y"] - shot.y).length() < float(spec[2]) + .12
				and absf(shot.z - floor_z - float(spec[3])) < float(spec[4]) + .1
				and not counted.has([key, t["id"]])
			):
				counted[[key, t["id"]]] = true
				var distance := Vector2(t["x"] - game.player.x, t["y"] - game.player.y).length()
				_struck(game, t, game.armory.active, float(shot.damage), distance, 0.0)
				if Shots.explodes(shot.kind) and shot.kind != "tnt":
					burst.append(shot)
		for m: Dictionary in movers:
			if game.clock < float(m["down_until"]):
				continue
			var row: Array = L.GALLERY_ROWS[m["row"]]
			if (
				Vector2(m["x"] - shot.x, float(row[0]) - shot.y).length() < .3
				and absf(shot.z - float(row[1]) - float(row[3]) * .5) < .4
			):
				_gallery_hit(game, m)
	for shot in burst:
		game.finish_shot(shot)
		game.shots.erase(shot)
	if counted.size() > 400:
		counted.clear()


# ------------------------------------------------------------------- gallery


func start_gallery(game) -> void:
	gallery_on = true
	gallery_clock = 0.0
	gallery_score = 0
	gallery_hits = 0
	gallery_shots = 0
	gallery_last = ""
	for m: Dictionary in movers:
		m["down_until"] = 0.0
	game.sound.play("menu_accept")


func _gallery_hit(game, m: Dictionary) -> void:
	m["down_until"] = game.clock + 1.1
	var row: Array = L.GALLERY_ROWS[m["row"]]
	game.sound_at("range_gallery_ding", m["x"], row[0], .5)
	if gallery_on:
		gallery_hits += 1
		gallery_score += int(row[4])


func tick_gallery(game, dt: float) -> void:
	var pace := 1.0 if gallery_on else .35
	if gallery_on:
		gallery_clock += dt
		# The movers speed up as the round goes on.
		pace += gallery_clock / L.GALLERY_TIME * .8
	for m: Dictionary in movers:
		var row: Array = L.GALLERY_ROWS[m["row"]]
		m["x"] = float(m["x"]) + float(m["dir"]) * float(row[5]) * pace * dt
		if float(m["x"]) > L.GALLERY_X[1]:
			m["x"] = L.GALLERY_X[1]
			m["dir"] = -1.0
		elif float(m["x"]) < L.GALLERY_X[0]:
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


func sprites(game) -> Array:
	var out: Array = []
	for t: Dictionary in targets:
		if not game.in_view(t["x"], t["y"], 1.0):
			continue
		var spec: Array = L.TARGET_KINDS[t["kind"]]
		var x := float(t["x"])
		var spin := float(t["spin"])
		var sprite := Renderer.Sprite.new(
			x, t["y"], String(spec[0]), float(spec[1]), game.world.elevation(x, t["y"])
		)
		var kind := String(t["kind"])
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
		if game.clock < float(m["down_until"]) or not game.in_view(m["x"], row[0], .5):
			continue
		var s := Renderer.Sprite.new(m["x"], row[0], String(row[2]), float(row[3]), float(row[1]))
		s.plane = 0.0
		s.flip = float(m["dir"]) < 0.0
		out.append(s)
	return out


func tick(game, dt: float) -> void:
	for t: Dictionary in targets:
		if float(t["spin"]) > 0.0:
			t["spin"] = maxf(0.0, float(t["spin"]) - dt)
	bowling.tick(game, dt)
	tick_gallery(game, dt)
	var turn := wrapf(game.player.angle - last_angle, -PI, PI) / maxf(dt, .001)
	turn_rate += (turn - turn_rate) * minf(1.0, dt * 10.0)
	last_angle = game.player.angle
	shots(game, dt)
