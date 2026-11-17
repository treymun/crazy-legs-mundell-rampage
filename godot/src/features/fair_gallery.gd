## The fair's SHOOTING GALLERY (Possum County Fair, the game court's east
## booth on the north side; the prize booth two along): shoot the bell to
## start a thirty-second round and shoot what rides the rails. Tin ducks
## ride the back rail (2) and go over flat when hit; cans and milk bottles
## ride the middle one, a can (1) leaving its rail spinning to bounce off the
## booth's back and floor (hit again in the air: 2 more), a bottle (3)
## bursting; now and then a wooden hog runs the front rail (5). The house
## pays for the rounds (each shot fired in a round comes back to the gun's
## pocket). At the end the prize booth pays out by the score: a cold beer
## into the pockets, the straw hat, the big bear; the hat and the bear won
## sit on its counter after. Each round's score goes to the range's records
## and, online, its board (range_board.gd).
##
## Nothing here is a station, a door or a wall: the booths are the fair's as
## built (fair_plan.gd), so it never stands in the chapter's way. Its state
## is play (carried in snapshots); the best and the prizes are saved.
extends GameFeature

const S := preload("res://src/range_games_shape.gd")
const Targets := preload("res://src/range_targets.gd")
const GRAVITY := 10.7
## The gallery booth's inside (cells x0, y0 to x1, y1: its back wall's face
## at y0, its counter's inner face at y1), where the shooter stands, the rails
## [y, z above the floor, speed (cells a second, the sign its way), kinds],
## the front rail's y and height (the hog's), the bell.
const BOOTH := Rect2(96.05, 44.05, 4.9, 4.2)
const STAND := Rect2(95.5, 48.75, 6.0, 2.0)
const RAILS := [
	[44.75, 1.5, 1.0, ["duck", "duck", "duck"]],
	[45.85, 1.2, -1.35, ["can", "bottle", "can", "bottle"]],
]
const HOG_Y := 47.0
const HOG_Z := 1.0
const BELL := Vector3(96.4, 47.9, 1.78)
## The prize booth: its shelves' left end, y and heights; its counter's y
## and top.
const SHELF := Vector3(87.15, 44.4, 1.05)
const SHELF_UP := .5
const PRIZE_COUNTER := Vector2(48.5, .95)
## What each target is worth and how big it is to hit: [points key,
## height, radius across, its middle up from the rail].
const KINDS := {
	"duck": ["duck", .34, .14, .17],
	"can": ["can", S.CAN_H, .065, S.CAN_H * .5],
	"bottle": ["bottle", S.BOTTLE_LEN, .055, .13],
}

static var ROUND: float = RangeTuning.get_value("fair_gallery", "round", 30.0)
static var POINTS: Dictionary = {
	"duck": RangeTuning.get_value("fair_gallery", "duck", 2),
	"can": RangeTuning.get_value("fair_gallery", "can", 1),
	"bottle": RangeTuning.get_value("fair_gallery", "bottle", 3),
	"hog": RangeTuning.get_value("fair_gallery", "hog", 5),
	"air_can": RangeTuning.get_value("fair_gallery", "air_can", 2),
}
static var BEER: int = RangeTuning.get_value("fair_gallery", "beer", 15)
static var HAT: int = RangeTuning.get_value("fair_gallery", "hat", 30)
static var BEAR: int = RangeTuning.get_value("fair_gallery", "bear", 45)
static var SPEED: float = RangeTuning.get_value("fair_gallery", "speed", 1.2)
static var SPEED_UP: float = RangeTuning.get_value("fair_gallery", "speed_up", .9)
static var DOWN: float = RangeTuning.get_value("fair_gallery", "down", 1.4)
static var CAN_BOUNCE: float = RangeTuning.get_value("fair_gallery", "can_bounce", .45)
static var CAN_DRAG: float = RangeTuning.get_value("fair_gallery", "can_drag", 2.5)

var on := false
## The round: running, its clock, the score, hits and shots, the best, the
## last round's words.
var round_on := false
var clock := 0.0
var score := 0
var hits := 0
var shots := 0
var best := 0
var last := ""
## What rides the rails: {kind, rail, x, down_until}.
var targets: Array = []
## Cans knocked off their rail: {x, y, z (above the floor), vx, vy, vz,
## turn (radians about `axis`), axis (radians, the line it turns about),
## w (its spin), still (seconds at rest), scored_air}.
var cans: Array = []
## The hog: where it is on the front rail, running or not, when it runs next.
var hog_x := -1.0
var hog_down := 0.0
var hog_next := 3.0
var hog_fast := false
## Who opened the round (their slot): only they must stay at the counter,
## and only their own machine posts the round.
var slot := 0
## The bell's swing (seconds left) and the prizes won.
var bell := 0.0
var won_hat := false
var won_bear := false
var beers := 0


func id() -> String:
	return "fair_gallery"


func attach() -> void:
	on = game.level != null and game.level.id == "fair" and game.level.width >= 102
	if not on:
		return
	_fill()
	tick_with(_tick)
	game.events.traced.connect(_traced)
	game.events.shot_fired.connect(_fired)


func _fill() -> void:
	targets.clear()
	for r in RAILS.size():
		var rail: Array = RAILS[r]
		var kinds: Array = rail[3]
		for k in kinds.size():
			var x := BOOTH.position.x + (k + .5) * BOOTH.size.x / kinds.size()
			targets.append({"kind": str(kinds[k]), "rail": r, "x": x, "down_until": 0.0})


func save() -> Dictionary:
	if not on:
		return {}
	return {"best": best, "hat": won_hat, "bear": won_bear, "beers": beers}


func restore(state: Dictionary) -> void:
	var b: int = state.get("best", 0)
	best = b
	won_hat = state.get("hat", false) == true
	won_bear = state.get("bear", false) == true
	var n: int = state.get("beers", 0)
	beers = n


func _floor() -> float:
	return game.world.elevation(98.5, 46.0)


static func standing_at(p: Player) -> bool:
	return STAND.has_point(Vector2(p.x, p.y))


# ------------------------------------------------------------------ the round


func start(p: Player) -> String:
	if round_on:
		return ""
	if not standing_at(p):
		return "STEP UP TO THE GALLERY COUNTER TO PLAY."
	round_on = true
	slot = p.slot
	clock = 0.0
	score = 0
	hits = 0
	shots = 0
	last = ""
	cans.clear()
	_fill()
	hog_x = -1.0
	hog_next = 2.0
	game.message("SHOOTING GALLERY: 30 SECONDS. DUCKS 2, CANS 1, BOTTLES 3, THE HOG 5.", 2.6)
	return ""


func _finish(words: String) -> void:
	round_on = false
	best = maxi(best, score)
	var aim := roundi(hits * 100.0 / maxf(1.0, shots))
	var prizes := PackedStringArray()
	if score >= BEAR and not won_bear:
		won_bear = true
		prizes.append("THE BIG BEAR")
	if score >= HAT and not won_hat:
		won_hat = true
		prizes.append("THE STRAW HAT")
	if score >= BEER:
		beers += 1
		if not game.collect("beer"):
			game.add_pickup("beer", 98.5, 49.6)
		prizes.append("A COLD BEER")
	last = "%d POINTS, %d%% AIM" % [score, aim]
	var won := (" YOU WIN " + ", ".join(prizes) + ".") if not prizes.is_empty() else ""
	game.message(words + " " + last + "." + won, 3.6)
	if not prizes.is_empty():
		game.callout = "WINNER!"
		game.callout_until = game.clock + 1.6
		game.sound.play("crowd_cheer", .6)
	game.sound.play("range_gallery_buzzer")
	var me: Player = game.local_player
	if not Modes.is_versus(game) and me != null and me.slot == slot:
		RangeBoard.finished("fair_gallery", score)


func _tick(dt: float) -> void:
	bell = maxf(0.0, bell - dt)
	var p := game.player
	for q: Player in game.players:
		if q.slot == slot:
			p = q
	if round_on:
		clock += dt
		if clock >= ROUND:
			_finish("TIME!")
		elif not standing_at(p):
			_finish("LEFT THE COUNTER: ROUND OVER.")
	var pace := (1.0 + clock / ROUND * SPEED_UP) if round_on else .4
	for t: Dictionary in targets:
		var rail: Array = RAILS[t["rail"]]
		var speed: float = rail[2]
		var x: float = t["x"]
		x += speed * SPEED * pace * dt
		if x > BOOTH.end.x:
			x -= BOOTH.size.x
		elif x < BOOTH.position.x:
			x += BOOTH.size.x
		t["x"] = x
	_tick_hog(dt, pace)
	_tick_cans(dt)


func _tick_hog(dt: float, pace: float) -> void:
	if hog_x < 0.0:
		if round_on and clock >= hog_next:
			hog_x = BOOTH.position.x
			hog_fast = false
			hog_down = 0.0
		return
	if hog_down > 0.0:
		hog_down -= dt
		if hog_down <= 0.0:
			hog_x = -1.0
			hog_next = clock + 4.0
		return
	hog_x += (5.0 if hog_fast else 1.7) * pace * dt
	if hog_x > BOOTH.end.x:
		hog_x = -1.0
		hog_next = clock + 3.5


func _tick_cans(dt: float) -> void:
	var kept: Array = []
	for can: Dictionary in cans:
		var x: float = can["x"]
		var y: float = can["y"]
		var z: float = can["z"]
		var vx: float = can["vx"]
		var vy: float = can["vy"]
		var vz: float = can["vz"]
		var w: float = can["w"]
		var still: float = can["still"]
		vz -= GRAVITY * dt
		x += vx * dt
		y += vy * dt
		z += vz * dt
		var turn: float = can["turn"]
		turn += w * dt
		var r := S.CAN_R
		if x < BOOTH.position.x + r or x > BOOTH.end.x - r:
			x = clampf(x, BOOTH.position.x + r, BOOTH.end.x - r)
			vx = -vx * CAN_BOUNCE
			game.sound_at("ricochet_tin", x, y, .35)
		if y < BOOTH.position.y + r or y > BOOTH.end.y - r:
			y = clampf(y, BOOTH.position.y + r, BOOTH.end.y - r)
			vy = -vy * CAN_BOUNCE
			game.sound_at("ricochet_tin", x, y, .35)
		if z <= r:
			z = r
			if absf(vz) > .8:
				game.sound_at("can_kick", x, y, minf(.6, absf(vz) * .12))
			vz = -vz * CAN_BOUNCE if absf(vz) > .6 else 0.0
			var slow := maxf(0.0, 1.0 - CAN_DRAG * dt)
			vx *= slow
			vy *= slow
			w *= slow
		if z <= r + .001 and Vector2(vx, vy).length() < .08 and vz == 0.0:
			still += dt
		can["x"] = x
		can["y"] = y
		can["z"] = z
		can["vx"] = vx
		can["vy"] = vy
		can["vz"] = vz
		can["w"] = w
		can["turn"] = turn
		can["still"] = still
		if still < 2.5:
			kept.append(can)
	cans = kept


# ------------------------------------------------------------------ shots


func _fired(gun: int) -> void:
	if not round_on:
		return
	shots += 1
	# The house pays: the round's shots come back to the gun.
	var a := game.armory
	if gun >= 0 and gun < Weapons.COUNT:
		var most: int = Weapons.MAX_RESERVE[gun]
		var have: int = a.reserve[gun]
		a.reserve[gun] = mini(most, have + 1)


func _traced(end: Vector3, _struck: String) -> void:
	var p := game.player
	if Vector2(p.x - 98.5, p.y - 46.5).length() > 12.0:
		return
	var s := Vector3(p.x, p.y, p.eye)
	var floor_z := _floor()
	var best_t := 9.0
	var hit: Variant = null
	# The bell.
	var b := Targets.crossing(s, end, BELL.x, BELL.y, floor_z + BELL.z - .08, .1, .1)
	if b.x >= 0.0:
		best_t = b.x
		hit = "bell"
	for t: Dictionary in targets:
		var down_until: float = t["down_until"]
		if game.clock < down_until:
			continue
		var rail: Array = RAILS[t["rail"]]
		var spec: Array = KINDS[t["kind"]]
		var rail_z: float = rail[1]
		var high: float = spec[1]
		var reach: float = spec[2]
		var up: float = spec[3]
		var x: float = t["x"]
		var y: float = rail[0]
		var c := Targets.crossing(s, end, x, y, floor_z + rail_z + up, high * .5, reach)
		if c.x >= 0.0 and c.x < best_t:
			best_t = c.x
			hit = t
	for can: Dictionary in cans:
		var cx: float = can["x"]
		var cy: float = can["y"]
		var cz: float = can["z"]
		var c2 := Targets.crossing(s, end, cx, cy, floor_z + cz, .07, .07)
		if c2.x >= 0.0 and c2.x < best_t:
			best_t = c2.x
			hit = can
	if hog_x >= 0.0 and hog_down <= 0.0:
		var c3 := Targets.crossing(s, end, hog_x, HOG_Y, floor_z + HOG_Z + .2, .2, .3)
		if c3.x >= 0.0 and c3.x < best_t:
			best_t = c3.x
			hit = "hog"
	if hit == null:
		return
	var way := Vector2(end.x - s.x, end.y - s.y).normalized()
	if hit is String:
		if hit == "bell":
			bell = 1.2
			game.sound_at("fair_bell", BELL.x, BELL.y, .9)
			var told := start(p)
			if told != "":
				game.message(told, 2.0)
		else:
			_hog_hit()
		return
	var struck: Dictionary = hit
	if struck.has("vz"):
		_can_again(struck, way)
	else:
		_target_hit(struck, way)


func _score(points: int) -> void:
	if round_on:
		score += points
		hits += 1


func _target_hit(t: Dictionary, way: Vector2) -> void:
	var kind := str(t["kind"])
	t["down_until"] = game.clock + DOWN
	var rail: Array = RAILS[t["rail"]]
	var x: float = t["x"]
	var y: float = rail[0]
	var rail_z: float = rail[1]
	var points: int = POINTS[kind]
	_score(points)
	match kind:
		"duck":
			game.sound_at("range_gallery_ding", x, y, .6)
		"bottle":
			game.sound_at("glass_break", x, y, .6)
			game.burst(x, y, _floor() + rail_z + .14, "glass", 10, 1.2)
		"can":
			game.sound_at("ricochet_tin", x, y, .6)
			# Off its rail, spinning, the way the shot went and up.
			(
				cans
				. append(
					{
						"x": x,
						"y": y,
						"z": rail_z + S.CAN_H * .5,
						"vx": way.x * 2.4 + (x - 98.5) * .3,
						"vy": way.y * 2.4,
						"vz": 2.8,
						"turn": 0.0,
						"axis": atan2(way.y, way.x) + PI * .5,
						"w": 14.0,
						"still": 0.0,
						"scored_air": false,
					}
				)
			)


func _can_again(can: Dictionary, way: Vector2) -> void:
	var cx: float = can["x"]
	var cy: float = can["y"]
	var cz: float = can["z"]
	game.sound_at("ricochet_tin", cx, cy, .7)
	var vx: float = can["vx"]
	var vy: float = can["vy"]
	can["vx"] = vx + way.x * 2.0
	can["vy"] = vy + way.y * 2.0
	can["vz"] = 3.0
	can["w"] = 16.0
	can["still"] = 0.0
	if cz > S.CAN_R + .05 and not can["scored_air"]:
		can["scored_air"] = true
		var points: int = POINTS["air_can"]
		_score(points)
		game.callout = "IN THE AIR!"
		game.callout_until = game.clock + 1.0


func _hog_hit() -> void:
	var points: int = POINTS["hog"]
	_score(points)
	game.sound_at("pig", hog_x, HOG_Y, .8)
	game.burst(hog_x, HOG_Y, _floor() + HOG_Z + .1, "dust", 8, 1.0)
	hog_down = .6
	hog_fast = true


# ------------------------------------------------------------------ looks


func sprites() -> Array:
	var out: Array = []
	if not on:
		return out
	var floor_z := _floor()
	if game.in_view(98.5, 46.0, 3.5):
		_gallery_sprites(out, floor_z)
	if game.in_view(89.5, 46.0, 3.5):
		_prize_sprites(out, floor_z)
	return out


static func _solid(
	x: float, y: float, z: float, kind: String, turn := Basis.IDENTITY
) -> View.Sprite:
	var s := View.Sprite.new(x, y, "town_range_pin", .3, z)
	s.solid = kind
	s.turn = turn
	return s


func _gallery_sprites(out: Array, floor_z: float) -> void:
	var sign := View.Sprite.new(
		98.5, BOOTH.position.y + .02, "range_head_fairgallery", .5, floor_z + 1.7
	)
	sign.plane = 0.0
	out.append(sign)
	for rail: Array in RAILS:
		var y: float = rail[0]
		var z: float = rail[1]
		out.append(
			_solid(
				BOOTH.position.x,
				y + .06,
				floor_z + z - .02,
				"rail",
				Basis.from_scale(Vector3(BOOTH.size.x, 1, 1))
			)
		)
	out.append(
		_solid(
			BOOTH.position.x,
			HOG_Y + .1,
			floor_z + HOG_Z - .02,
			"rail",
			Basis.from_scale(Vector3(BOOTH.size.x, 1, 1))
		)
	)
	var calm: float = [1.0, .4, 0.0][clampi(game.view.world_motion, 0, 2)]
	for t: Dictionary in targets:
		var rail: Array = RAILS[t["rail"]]
		var x: float = t["x"]
		var y: float = rail[0]
		var z: float = rail[1]
		var down_until: float = t["down_until"]
		var down := game.clock < down_until
		var kind := str(t["kind"])
		var speed: float = rail[2]
		match kind:
			"duck":
				var duck := View.Sprite.new(x, y, "town_range_duck", .34, floor_z + z)
				duck.plane = 0.0
				duck.flip = speed < 0.0
				duck.tilt = sin(game.clock * 7.0 + x * 3.0) * .06 * calm
				if down:
					var over := minf(game.clock - (down_until - DOWN), down_until - game.clock)
					duck.tilt = PI * .5 * clampf(over / .12, 0.0, 1.0)
				out.append(duck)
			"can":
				if not down:
					out.append(_solid(x, y, floor_z + z + S.CAN_H * .5, "tin_can"))
			"bottle":
				if not down:
					out.append(_solid(x, y, floor_z + z, "bottle"))
	for can: Dictionary in cans:
		var cx: float = can["x"]
		var cy: float = can["y"]
		var cz: float = can["z"]
		var axis_a: float = can["axis"]
		var turn: float = can["turn"]
		var axis := Vector3(cos(axis_a), sin(axis_a), 0.0)
		out.append(_solid(cx, cy, floor_z + cz, "tin_can", Basis(axis, turn)))
	if hog_x >= 0.0:
		var hog := View.Sprite.new(hog_x, HOG_Y, "town_giant_hog", .42, floor_z + HOG_Z)
		hog.plane = PI * .5
		if hog_down > 0.0:
			hog.z += sin(hog_down * 12.0) * .05
		out.append(hog)
	var swing := sin(bell * 14.0) * bell * .4
	out.append(_solid(BELL.x, BELL.y, floor_z + BELL.z, "bell", Basis(Vector3(1, 0, 0), swing)))


func _prize_sprites(out: Array, floor_z: float) -> void:
	var sign := View.Sprite.new(89.5, SHELF.y - .33, "range_head_prizes", .5, floor_z + 2.0)
	sign.plane = 0.0
	out.append(sign)
	for k in 2:
		out.append(
			_solid(
				SHELF.x,
				SHELF.y,
				floor_z + SHELF.z + k * SHELF_UP,
				"shelf",
				Basis.from_scale(Vector3(4.7, 1, 1))
			)
		)
	var top := floor_z + SHELF.z + SHELF_UP
	var counter_y := PRIZE_COUNTER.x
	var counter_z := floor_z + PRIZE_COUNTER.y
	var bear_at := Vector3(88.6, counter_y, counter_z) if won_bear else Vector3(88.4, SHELF.y, top)
	var bear := View.Sprite.new(bear_at.x, bear_at.y, "town_prize_bear", .5, bear_at.z)
	bear.plane = 0.0
	out.append(bear)
	var hat_at := Vector3(90.4, counter_y, counter_z) if won_hat else Vector3(90.6, SHELF.y, top)
	out.append(_solid(hat_at.x, hat_at.y, hat_at.z, "hat", Basis(Vector3(0, 0, 1), .6)))
	for k in 4:
		out.append(
			_solid(88.0 + k * .5, SHELF.y, floor_z + SHELF.z, "beer", Basis(Vector3(0, 0, 1), k))
		)


# ------------------------------------------------------------------ HUD


## The gallery's card goes in the top left where the HUD's layout has room
## (ui/hud/hud_layout.gd).
func hud_flow(layout: HudLayout) -> void:
	var lines := _card_lines()
	if not lines.is_empty():
		var size := HudLayout.panel_rect(0, 0, 150, 14 + lines.size() * 7).size
		layout.down("card", size, HudLayout.EDGE, 18)


func draw_view(c: Canvas) -> void:
	var lines := _card_lines()
	var at := game.hud.layout.find("card")
	if lines.is_empty() or at.size.x <= 0:
		return
	var top := at.position.y
	var left := at.position.x
	HudLayout.begin(c, "card")
	HUD.panel(c, left, top, 150, 14 + lines.size() * 7, Color(34 / 255.0, 24 / 255.0, 19 / 255.0))
	HUD.text(c, "SHOOTING GALLERY", left + 5, top + 3, "body", HUD.AMBER)
	for i in lines.size():
		HUD.text(c, str(lines[i]), left + 5, top + 13 + i * 7, "mini", HUD.INK, false, false)
	HudLayout.end(c)


## The card's lines ([] when it is not up).
func _card_lines() -> Array:
	if not on or game.map or Modes.is_versus(game):
		return []
	var p := game.player
	if not round_on and not standing_at(p):
		return []
	var lines: Array = []
	if round_on:
		lines.append("SCORE %d  TIME %d" % [score, ceili(ROUND - clock)])
		lines.append("DUCK 2  CAN 1  BOTTLE 3  HOG 5")
	else:
		lines.append("SHOOT THE BELL TO START A ROUND")
		lines.append("15 A BEER  30 THE HAT  45 THE BEAR")
		if last != "":
			lines.append("LAST: " + last)
	lines.append("BEST %d" % best)
	return lines
