## Vehicles to get in and drive with USE: the bayou's airboat, a stock car at
## the speedway and a riding mower at Hickston (a level's "vehicles" list;
## numbers in data/tuning/vehicles.cfg; the driving sums in
## src/vehicle_drive.gd). game.gd's `_step_body` hands a seated player's
## controls here instead of walking them: the driver throttles, brakes and
## steers, a second seat (the airboat's) rides along. A vehicle bumps off
## walls, runs the county's hands down (thrown like a blast: corpses.gd's
## "roadkill"); the mower's blade cuts what it runs over, grass behind it and
## the small breakables in front; fences and windows it rams take the knock a
## thrown body gives them. The hands step out of its way or stand and shoot
## at its driver. It takes a share of what hurts the people in it and every
## blast near it, smokes, burns, and at 0 blows and throws them out.
##
## Play, the same on every machine: each vehicle is a VehicleDrive.Ride of
## plain numbers (a simulation feature, carried in snapshots and saved), no
## dice; only the marks it leaves and the grass it throws are looks
## (`_looks`, skipped by snapshots). Only the campaign and co-op have them
## (online play, County Run and the 5v5, has none).
##
## How each looks on the move is src/vehicle_feel.gd (looks only, its own
## dice): the body on its springs (squat, dive, lean, bumps, landings, the
## airboat rocking), shown as its model turned on the move and as a little
## sway of the seat's eye (less with EASY ON THE EYES, none when STILL); the
## airboat's spray and wake, the car's tyre marks and sparks off a wall, the
## mower's bounce and clippings; the engine's note rising with the speed.
##
## Finding one (feature pass 7, src/vehicle_finder.gd, looks only): a ready
## vehicle keeps its lamps on and its radio playing, the automap marks it,
## USE's prompt names it from further off and its line is said the first time
## a player comes near. Out of the car's window a one-handed gun shoots
## (`window`, [all] window_guns: the other hand stays on the wheel, steering
## less, the shot strays more, never back through the cage), and its
## passenger rides beside the driver and shoots (the set pieces built round
## them are features/vehicle_runs.gd).
extends GameFeature

## A mower's blade bites what it runs over this often (seconds).
const BLADE_EVERY := .4
## Marks left behind (skids, mown grass) and grass thrown at most; spray and
## sparks in the air at most.
const MARKS_MAX := 240
const CLIPS_MAX := 60
const SPRAY_MAX := 48
const SPARKS_MAX := 64
## A skid's streak: its picture and half its width (cells).
const SKID_MARK := "mark_oil_0"
const SKID_WIDE := .1
## How far the airboat goes between its wake's rings (cells).
const WAKE_EVERY := .55
## How much of the body's bob and pitch the seat's eye takes, for each EASY ON
## THE EYES step (full, reduced, still): src/vehicle_cab.gd sways it.
const SWAY := [.7, .3, 0.0]
## The engine's pitch standing and at top speed.
const ENGINE_LOW := .82
const ENGINE_HIGH := 1.32
## Floors the mower leaves a mown stripe on and throws clippings off.
const GRASS := ["grass", "bayou_marsh", "lawn"]
## Smoke over a hurt or burning vehicle, drawn from the clock.
const PUFFS := 6
## Off the racing line by more than this (cells), a lap does not count.
const LINE_REACH := 6.5
## The eye's rumble at full speed (cells).
const RUMBLE := .012
const INK := Color8(236, 214, 150)

## The vehicles (VehicleDrive.Ride).
var rides: Array = []
## The speedway's racing line and its middle, for the lap timer (from the
## level's lap_cars; empty elsewhere).
var line := PackedVector2Array()
var middle := Vector2.ZERO
## Looks only (snapshots skip it): marks [x, y, z, angle, image, width], grass
## clippings, spray and sparks [x, y, z, vx, vy, vz, at], each ride's body
## on its springs (VehicleFeel.Body, by the ride's place in `rides`) and how
## far each has gone since its wake's last ring.
## The seat view's looks too (src/vehicle_cab.gd): each ride's prop turned
## so far (radians) and the spray over the driver's bow.
var _looks := {
	"marks": [],
	"clips": [],
	"spray": [],
	"sparks": [],
	"bodies": [],
	"wake": [],
	"props": [],
	"drops": [],
	"told": {}
}
## The looks' own dice (snapshots skip it).
var _dice := RandomNumberGenerator.new()


func id() -> String:
	return "vehicles"


func attach() -> void:
	var known := VehicleDrive.kinds()
	for row: Variant in game.level.vehicles:
		var r: Array = row
		var kind := str(r[0])
		if not known.has(kind):
			continue
		var x: float = r[1]
		var y: float = r[2]
		var h: float = r[3] if r.size() > 3 else 0.0
		rides.append(_make(kind, x, y, h))
	if rides.is_empty():
		return
	_dice.seed = 1958
	var bodies: Array = _looks["bodies"]
	var wake: Array = _looks["wake"]
	var props: Array = _looks["props"]
	for _v: VehicleDrive.Ride in rides:
		bodies.append(VehicleFeel.Body.new())
		wake.append(0.0)
		props.append(0.0)
	# A patrol's beat (the Moonshine Run's cruisers, "laps": false) is no
	# racing line: no lap timer there.
	var timed: bool = game.level.lap_cars.get("laps", true)
	for point: Variant in game.level.lap_cars.get("path", []) if timed else []:
		var px: float = point[0]
		var py: float = point[1]
		line.append(Vector2(px, py))
		middle += Vector2(px, py)
	if not line.is_empty():
		middle /= line.size()
		line.append(line[0])
	tick_with(_tick)
	game.events.exploded.connect(_blast)


func _make(kind: String, x: float, y: float, h: float) -> VehicleDrive.Ride:
	var s := VehicleDrive.spec(kind)
	var v := VehicleDrive.Ride.new()
	v.kind = kind
	v.x = x
	v.y = y
	v.h = h
	v.z = game.world.floor_under(x, y, 9.0)
	v.hp = s.hp
	for _k in maxi(1, s.seats):
		v.seats.append(-1)
	v.bump_x = x
	v.bump_y = y
	return v


## Vehicles only in the campaign and co-op.
func active() -> bool:
	var mst := Modes.feature(game)
	return mst == null or mst.mode == Modes.CAMPAIGN or mst.mode == Modes.COOP


## [vehicle index, seat] of `p`, or (-1, -1).
func seat_of(p: Player) -> Vector2i:
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		var k := v.seats.find(p.slot)
		if k >= 0:
			return Vector2i(i, k)
	return Vector2i(-1, -1)


## Whether `p` rides a vehicle (game.gd steps them here instead of walking).
func seated(p: Player) -> bool:
	return not rides.is_empty() and seat_of(p).x >= 0


## Whether `p` sits inside a closed shell, out of sight (the car: hands on
## the wheel); an open seat (the airboat, the mower) shows its rider.
func shut_in(p: Player) -> bool:
	var at := seat_of(p) if not rides.is_empty() else Vector2i(-1, -1)
	if at.x < 0:
		return false
	var v: VehicleDrive.Ride = rides[at.x]
	return VehicleDrive.spec(v.kind).hands == 0


## Where `p`'s body stands in an open seat (its feet, sunk by the kind's `sit`
## so the hips sit on the seat and the legs are in the hull): looks only.
func rider_feet(p: Player) -> float:
	var at := seat_of(p) if not rides.is_empty() else Vector2i(-1, -1)
	if at.x < 0:
		return game.world.stand(p) + p.air
	var v: VehicleDrive.Ride = rides[at.x]
	var b := body(at.x)
	return v.z + VehicleDrive.spec(v.kind).sit + (b.heave if b != null else 0.0)


## Whether `p`'s hands are on a wheel (the car: no shooting from it, but a
## one-handed gun out of the window), or the shot would go back through the
## car's cage (its driver and its passenger both).
func hands_busy(p: Player) -> bool:
	if rides.is_empty():
		return false
	var at := seat_of(p)
	if at.x < 0:
		return false
	var v: VehicleDrive.Ride = rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	if s.window and not window_clear(p, v):
		return true
	if at.y != 0:
		return false
	return s.hands == 0 and not (s.window and one_handed(p))


## Whether `p`'s gun in hand goes one-handed out of a window ([all]
## window_guns).
static func one_handed(p: Player) -> bool:
	var guns: Array = Tuning.file(VehicleDrive.FILE).get_value("all", "window_guns", [])
	return guns.has(str(Weapons.NAMES[p.armory.active]))


## Whether `p` looks out of the front or a side of `v` (within window_arc of
## its nose), not back through the cage.
static func window_clear(p: Player, v: VehicleDrive.Ride) -> bool:
	var arc := deg_to_rad(VehicleDrive.shared("window_arc"))
	return absf(wrapf(p.angle - v.h, -PI, PI)) <= arc


## Takes up the first one-handed gun `p` owns (window_guns' order), getting
## in at the wheel with a gun that needs both hands.
func _window_gun(p: Player) -> void:
	var guns: Array = Tuning.file(VehicleDrive.FILE).get_value("all", "window_guns", [])
	for name: Variant in guns:
		var slot: int = Weapons.NAMES.find(str(name))
		if slot >= 0 and p.armory.owned[slot]:
			game.focus(p)
			p.armory.select(slot, game)
			game.focus(game.local_player)
			return


## How much more a seated player's shot strays (Modes.shot_tuning): out of
## the car's window from the wheel, or riding along; 1 on foot and at the
## airboat's stick or the mower's wheel.
func aim_scale(p: Player) -> float:
	if rides.is_empty():
		return 1.0
	var at := seat_of(p)
	if at.x < 0:
		return 1.0
	var v: VehicleDrive.Ride = rides[at.x]
	if at.y > 0:
		return VehicleDrive.shared("rider_spread")
	return VehicleDrive.shared("window_spread") if VehicleDrive.spec(v.kind).window else 1.0


## The vehicle nearest `p`'s hand within reach (and roughly in front), or -1;
## `wide`: the wider reach, when nothing else is at hand to USE.
func _nearest(p: Player, wide := false) -> int:
	var reach := VehicleDrive.shared("reach_wide" if wide else "reach")
	var best := -1
	var best_gap := INF
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		if absf(v.x - p.x) > 4.0 or absf(v.y - p.y) > 4.0:
			continue
		var g := VehicleDrive.gap(VehicleDrive.spec(v.kind), v, p.x, p.y)
		var to := Vector2(v.x - p.x, v.y - p.y).normalized()
		var facing := to.dot(Vector2(cos(p.angle), sin(p.angle)))
		if g < reach and facing > -.2 and g < best_gap:
			best = i
			best_gap = g
	return best


## What USE does here, for the prompt ("" when no vehicle is at hand);
## `wide`: when nothing else is at hand to USE, from the wider reach, and
## then a ready vehicle looked at from further off is named.
func prompt(p: Player, wide := false) -> String:
	if rides.is_empty() or not active():
		return ""
	var at := seat_of(p)
	if at.x >= 0:
		# Said while it stands (on the move USE still gets out).
		var mine: VehicleDrive.Ride = rides[at.x]
		return "E  GET OUT" if VehicleDrive.speed(mine) < .5 else ""
	var i := _nearest(p, wide)
	if i < 0:
		return VehicleFinder.far_prompt(game, rides, p) if wide else ""
	var v: VehicleDrive.Ride = rides[i]
	if v.wreck >= 0.0:
		return "BURNT OUT"
	var seat0: int = v.seats[0]
	if seat0 < 0:
		return "E  DRIVE THE " + VehicleDrive.spec(v.kind).name
	if v.seats.has(-1):
		return "E  RIDE ALONG"
	return "NO ROOM"


## USE: get out, or in (`wide`: from the wider reach, when nothing else
## answered it). True when it was about a vehicle.
func use(p: Player, wide := false) -> bool:
	if rides.is_empty() or not active():
		return false
	var at := seat_of(p)
	if at.x >= 0:
		var mine: VehicleDrive.Ride = rides[at.x]
		if not _get_out(p, mine, at.y, false):
			_say(p, "NOWHERE TO STEP OFF HERE.")
		return true
	var i := _nearest(p, wide)
	if i < 0:
		return false
	var v: VehicleDrive.Ride = rides[i]
	var s := VehicleDrive.spec(v.kind)
	if v.wreck >= 0.0:
		_say(p, "THAT " + s.name + " IS BURNT OUT.")
		return true
	var k := v.seats.find(-1)
	if k < 0:
		return true
	v.seats[k] = p.slot
	p.vx = 0.0
	p.vy = 0.0
	p.crouched = false
	p.scoped = false
	if k == 0:
		# Settled in facing where it points (the look steers it).
		p.angle = v.h
		if s.hands == 0:
			if s.window and not one_handed(p):
				# A one-handed gun to hand for the window, if one is owned.
				_window_gun(p)
			p.armory.holstered = not (s.window and one_handed(p))
		_lap_reset(v)
		v.engine_at = game.clock + .5
		game.sound_at(s.engine, v.x, v.y, .8)
	_place(p, v, s, k, 0.0)
	return true


## Stands `p` beside ride `i` facing it and gets in as USE does (a view
## tour's viewpoint from the seat, main.gd; the checks). True when `p` sits
## in it (already, or now).
func seat_in(p: Player, i: int) -> bool:
	if i < 0 or i >= rides.size():
		return false
	if seat_of(p).x >= 0:
		return seat_of(p).x == i
	var v: VehicleDrive.Ride = rides[i]
	var side := VehicleDrive.spec(v.kind).width * .5 + .3
	p.x = v.x - sin(v.h) * side
	p.y = v.y + cos(v.h) * side
	p.angle = v.h - PI * .5
	use(p)
	return seat_of(p).x == i


func _say(p: Player, text: String) -> void:
	if p == game.local_player:
		game.message(text, 2.0)


## Off the vehicle beside it: the left side first, then the right, behind,
## in front. `thrown`: out of a wreck, wherever there is room (or where it
## sits). False when there was nowhere to stand.
func _get_out(p: Player, v: VehicleDrive.Ride, k: int, thrown: bool) -> bool:
	var s := VehicleDrive.spec(v.kind)
	var half_w := s.width * .5 + .45
	var half_l := s.length * .5 + .45
	var f := Vector2(cos(v.h), sin(v.h))
	var r := Vector2(-sin(v.h), cos(v.h))
	var spots := [-r * half_w, r * half_w, -f * half_l, f * half_l]
	for far: Vector2 in [-r * (half_w + .5), r * (half_w + .5), -f * (half_l + .5)]:
		spots.append(far)
	var w := game.world
	var found := Vector2.INF
	for off: Vector2 in spots:
		var at := Vector2(v.x, v.y) + off
		if at.x < 1.0 or at.y < 1.0 or at.x > w.width - 1 or at.y > w.height - 1:
			continue
		if w.blocked(at.x, at.y, GameState.PLAYER_RADIUS) or w.deep_at(at.x, at.y):
			continue
		var under := w.floor_under(at.x, at.y, v.z + 1.0)
		if absf(under - v.z) > .8 or _in_any(at.x, at.y):
			continue
		found = at
		break
	if found == Vector2.INF:
		if not thrown:
			return false
		found = Vector2(v.x, v.y) - r * half_w
		if w.blocked(found.x, found.y, GameState.PLAYER_RADIUS):
			found = Vector2(v.x, v.y)
	v.seats[k] = -1
	p.x = found.x
	p.y = found.y
	p.floor_z = w.floor_under(found.x, found.y, v.z + 1.0)
	p.air = 0.0
	p.vertical_speed = 0.0
	p.vx = v.vx * .4
	p.vy = v.vy * .4
	p.eye = p.floor_z + .95
	if k == 0:
		p.armory.holstered = false
	return true


## Whether (x, y) lies in any vehicle's hull.
func _in_any(x: float, y: float) -> bool:
	for v: VehicleDrive.Ride in rides:
		var push := VehicleDrive.out_of(VehicleDrive.spec(v.kind), v, x, y, GameState.PLAYER_RADIUS)
		if push != Vector2.INF:
			return true
	return false


## Sits `p` in seat k (the driver over `seat`, a rider behind or beside:
## `ride_back`, `ride_side`), the eye at the seat's height with the engine's
## rumble.
func _place(p: Player, v: VehicleDrive.Ride, s: VehicleDrive.Spec, k: int, rumble: float) -> void:
	var along := s.seat - s.ride_back * k
	var side := s.ride_side * k
	p.x = v.x + cos(v.h) * along - sin(v.h) * side
	p.y = v.y + sin(v.h) * along + cos(v.h) * side
	p.floor_z = v.z
	p.air = 0.0
	p.vertical_speed = 0.0
	p.vx = v.vx
	p.vy = v.vy
	p.crouched = false
	p.motion = 0.0
	p.bob = 0.0
	p.eye = v.z + s.eye + sin(game.clock * 37.0) * RUMBLE * rumble


## One tick for a seated player, from game.gd `_step_body`: the look turns
## freely; the driver drives (bumps, run-overs, cuts, sounds, the lap timer).
func drive(p: Player, c: GameState.Controls, dt: float) -> void:
	var at := seat_of(p)
	var v: VehicleDrive.Ride = rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	p.angle = fposmod(p.angle + c.turn, TAU)
	p.pitch = clampf(p.pitch + c.look, -53.0, 53.0)
	if at.y == 0 and s.window:
		# The gun out of the window while it is one-handed and points out of
		# the front or the sides; else both hands on the wheel.
		p.armory.holstered = not (one_handed(p) and window_clear(p, v))
	if at.y == 0 and v.wreck < 0.0:
		var h := v.h
		var scale := (
			s.slow if s.slow_floors.has(VehicleDrive.tile_at(game.world, v.x, v.y)) else 1.0
		)
		var hand := 1.0
		if s.window and not p.armory.holstered:
			hand = VehicleDrive.shared("one_hand_turn")
		VehicleDrive.throttle(v, s, c, wrapf(p.angle - h, -PI, PI), dt, scale, hand)
		var struck := VehicleDrive.move(game.world, v, s, dt, h)
		if absf(c.strafe) >= .1:
			# Steered by keys: the eye comes round with it.
			p.angle = fposmod(p.angle + wrapf(v.h - h, -PI, PI), TAU)
		if struck > 0.0:
			_bump(v, s, struck, p)
		_run_over(v, s, p, c, dt)
		_cut(v, s, c)
		_noises(v, s)
		_lap(v, p)
	_place(p, v, s, at.y, VehicleDrive.speed(v) / maxf(1.0, s.top))


## A wall struck at `speed`: it bounces; hard enough, it dents (and a fence or
## window in the way takes the knock, as a thrown body's does).
func _bump(v: VehicleDrive.Ride, s: VehicleDrive.Spec, speed: float, driver: Player) -> void:
	var dir := Vector2(cos(v.h), sin(v.h)) * (1.0 if VehicleDrive.along(v) <= 0.0 else -1.0)
	var breaks: GameFeature = game.features.get("wall_breaks")
	if breaks != null and speed > 1.0:
		breaks.call("crash", v.bump_x, v.bump_y, v.z + .5, -dir.x, -dir.y, speed * 9.0)
	# A barn's post or wall, a tower's leg rammed (features/set_pieces.gd).
	var sets: GameFeature = game.features.get("set_pieces")
	if sets != null and speed >= s.ram_from:
		var hit: int = sets.call(
			"touch", v.bump_x - dir.x * .1, v.bump_y - dir.y * .1, v.z + .5, .3
		)
		if hit >= 0:
			var knock := s.ram * speed * SetPieceShape.num("all", "ram_frame", .6) * 2.0
			sets.call("strike", hit, knock, -dir.x, -dir.y)
	var from := VehicleDrive.shared("bump_from")
	if speed < from:
		return
	_hurt(v, (speed - from) * VehicleDrive.shared("bump_damage"))
	if game.clock >= v.bump_at:
		v.bump_at = game.clock + .35
		game.sound_at(
			"lap_car_hit" if speed > 5.0 else "crunch", v.bump_x, v.bump_y, minf(1.0, speed / 8.0)
		)
	if driver != null and driver == game.local_player:
		game.shake = minf(1.0, game.shake + minf(.7, speed / 12.0) * (.6 if s.hands == 1 else 1.0))


## Bodies in its way: run down when it comes fast enough (thrown, as a blast
## throws them), cut by the mower's blade, else shoved aside; the hands
## ahead of it step out of the way.
func _run_over(
	v: VehicleDrive.Ride, s: VehicleDrive.Spec, driver: Player, c: GameState.Controls, dt: float
) -> void:
	var speed := VehicleDrive.speed(v)
	var reach := s.length * .5 + 7.0
	var gap := VehicleDrive.shared("hit_gap")
	var heading := Vector2(v.vx, v.vy).normalized() if speed > .05 else Vector2(cos(v.h), sin(v.h))
	for e: Enemy in game.enemies:
		if not e.alive or e.dormant or e.z > .6:
			continue
		if absf(e.x - v.x) > reach or absf(e.y - v.y) > reach:
			continue
		var push := VehicleDrive.out_of(s, v, e.x, e.y, e.radius)
		if push == Vector2.INF:
			_dodge(e, v, s, heading, speed, dt)
			continue
		var boss := Enemy.BOSS_TITLES.has(e.kind)
		var next: float = v.hits.get(e.uid, -1.0)
		var ready := game.clock >= next
		if ready and speed >= s.ram_from and e.hostile:
			v.hits[e.uid] = game.clock + gap
			var amount := s.ram * speed * (.3 if boss else 1.0)
			e.blast_at = Vector2(e.x, e.y) - heading
			game.focus(driver)
			e.hurt(amount, game, false, false, null, "roadkill")
			game.focus(game.local_player)
			game.sound_at("lap_car_hit", e.x, e.y, .9)
			_hurt(v, amount * .04)
			var keep := -.3 if boss else .86
			v.vx *= keep
			v.vy *= keep
		elif ready and s.blade > 0.0 and e.hostile and (speed > .2 or absf(c.forward) > .1):
			v.hits[e.uid] = game.clock + BLADE_EVERY
			game.focus(driver)
			e.hurt(s.blade * (.3 if boss else 1.0), game, false, false, null, "mower")
			game.focus(game.local_player)
			game.sound_at("mower", e.x, e.y, .7)
		if e.alive and not boss:
			game.move_actor(e, push.x, push.y, e.radius)
	if v.hits.size() > 24:
		for uid: Variant in v.hits.keys():
			var until: float = v.hits[uid]
			if game.clock >= until:
				v.hits.erase(uid)


## A hand ahead of a fast vehicle steps out of its way (one in `dodge_skip`
## holds its ground: the squads already aim at its driver).
func _dodge(
	e: Enemy, v: VehicleDrive.Ride, s: VehicleDrive.Spec, heading: Vector2, speed: float, dt: float
) -> void:
	if speed < VehicleDrive.shared("dodge_from") or not e.hostile or e.stun > 0.0:
		return
	var skip := maxi(1, roundi(VehicleDrive.shared("dodge_skip")))
	if Enemy.BOSS_TITLES.has(e.kind) or e.uid % skip == 0:
		return
	var rel := Vector2(e.x - v.x, e.y - v.y)
	var ahead := rel.dot(heading)
	var side := rel.dot(Vector2(-heading.y, heading.x))
	if ahead < .5 or ahead > VehicleDrive.shared("dodge_reach") or absf(side) > s.width * .5 + 1.0:
		return
	var away := 1.0 if side > 0.0 or (side == 0.0 and e.uid % 2 == 0) else -1.0
	var step := VehicleDrive.shared("dodge_speed") * dt * away
	game.move_actor(e, -heading.y * step, heading.x * step, e.radius)


## What it runs into in front of it: the small breakables are cut down (the
## mower's blade, or a ram fast enough).
func _cut(v: VehicleDrive.Ride, s: VehicleDrive.Spec, c: GameState.Controls) -> void:
	var speed := VehicleDrive.speed(v)
	var blading := s.blade > 0.0 and absf(c.forward) > .1
	if speed < s.ram_from and not blading:
		return
	var breaks: GameFeature = game.features.get("breakables")
	if breaks == null:
		return
	var dir := 1.0 if VehicleDrive.along(v) >= 0.0 else -1.0
	var ahead := (s.length * .5 + .25) * dir
	var fx := v.x + cos(v.h) * ahead
	var fy := v.y + sin(v.h) * ahead
	var i: int = breaks.call("touch", fx, fy, v.z + .35, s.width * .5)
	if i >= 0:
		var amount := maxf(s.blade, s.ram * speed)
		breaks.call("strike", i, amount, cos(v.h) * dir, sin(v.h) * dir)


## The engine's note, quicker and higher with speed, and the tyres' squeal on
## a slide.
func _noises(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> void:
	var pace := clampf(VehicleDrive.speed(v) / maxf(1.0, s.top), 0.0, 1.0)
	if game.clock >= v.engine_at:
		v.engine_at = game.clock + s.every * (1.7 - .7 * pace)
		game.sound_at(s.engine, v.x, v.y, .3 + .5 * pace, engine_rate(pace))
	if v.slide > s.skid and game.clock >= v.skid_at:
		v.skid_at = game.clock + .3
		game.sound_at("tire_roll", v.x, v.y, .6)


## The lap timer round the speedway's racing line (a car only).
func _lap(v: VehicleDrive.Ride, p: Player) -> void:
	if line.is_empty() or v.kind != "car":
		return
	var ang := atan2(v.y - middle.y, v.x - middle.x)
	var last := v.lap_ang
	v.lap_ang = ang
	if _off_line(Vector2(v.x, v.y)):
		v.lap_turn = 0.0
		v.lap_start = game.clock
		return
	v.lap_turn += wrapf(ang - last, -PI, PI)
	if absf(v.lap_turn) < TAU:
		return
	var took := game.clock - v.lap_start
	if v.lap_best <= 0.0 or took < v.lap_best:
		v.lap_best = took
	v.laps += 1
	v.lap_turn -= signf(v.lap_turn) * TAU
	v.lap_start = game.clock
	_say(p, "LAP %d  %s   BEST %s" % [v.laps, clock_text(took), clock_text(v.lap_best)])


func _lap_reset(v: VehicleDrive.Ride) -> void:
	v.lap_turn = 0.0
	v.lap_start = game.clock
	v.lap_ang = atan2(v.y - middle.y, v.x - middle.x)


func _off_line(at: Vector2) -> bool:
	for i in range(1, line.size()):
		var near := Geometry2D.get_closest_point_to_segment(at, line[i - 1], line[i])
		if near.distance_to(at) < LINE_REACH:
			return false
	return true


## The engine's pitch at `pace` (0..1 of its top speed).
static func engine_rate(pace: float) -> float:
	return lerpf(ENGINE_LOW, ENGINE_HIGH, clampf(pace, 0.0, 1.0))


static func clock_text(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d.%d" % [whole / 60, whole % 60, int((seconds - whole) * 10.0)]


## Ride i's looks for one tick (src/vehicle_feel.gd): its body on its springs,
## then what it leaves and throws.
func _feel(i: int, v: VehicleDrive.Ride, s: VehicleDrive.Spec, dt: float) -> void:
	var bodies: Array = _looks["bodies"]
	if i >= bodies.size():
		return
	var b: VehicleFeel.Body = bodies[i]
	var speed := VehicleDrive.speed(v)
	var props: Array = _looks["props"]
	if i < props.size() and v.seats[0] >= 0:
		# The airboat's prop turning while someone is at the stick.
		var turned: float = props[i]
		props[i] = fposmod(turned + VehicleCab.prop_speed(v, s) * dt, TAU)
	var parked := speed < .02 and v.z == b.last_z and v.bumps == b.last_bumps and b.fall == 0.0
	if parked and b.started and b.still() and s.rock <= 0.0:
		# Parked and settled: nothing to work out (asleep it costs nothing).
		b.last_h = v.h
		b.last_z = v.z
		b.last_along = 0.0
		return
	var tile := VehicleDrive.tile_at(game.world, v.x, v.y)
	var rough := s.rough
	if s.slow_floors.has(tile) or GRASS.has(tile):
		rough += s.rough_off
	var struck := VehicleFeel.step(b, v, s, dt, rough, game.clock, _dice)
	if struck and s.sparks and speed > 1.5:
		_sparks(v, speed)
	if speed < .4:
		return
	_leave_marks(v, s, b, tile)
	if s.spray and s.floors.has(tile):
		_spray(i, v, s, speed, dt)
		if v.seats[0] == game.local_player.slot:
			var drops: Array = _looks["drops"]
			VehicleCab.spray(drops, v, game.clock, dt, _dice)


## Skids and a mown stripe left behind, and the grass the mower throws out of
## its side chute.
func _leave_marks(
	v: VehicleDrive.Ride, s: VehicleDrive.Spec, b: VehicleFeel.Body, tile: String
) -> void:
	var marks: Array = _looks["marks"]
	var step := int(game.clock * 60.0)
	var mowing := s.cuts and GRASS.has(tile)
	var braking := s.brake_skid and b.acc < -s.brake * .55 and VehicleDrive.along(v) > 2.0
	if (v.slide > s.skid or braking) and step % 2 == 0 and not s.floors.has(tile):
		# Two black streaks of rubber off the back wheels, along the way it is
		# going: a tyre's width of near-black smear (the pale wear decal they
		# were drawn with read as nothing on dirt and tarmac at 320 wide).
		var way := atan2(v.vy, v.vx)
		var back := -s.length * .3
		for side: float in [-1.0, 1.0]:
			var off := side * s.width * .38
			marks.append(
				[
					v.x + cos(v.h) * back - sin(v.h) * off,
					v.y + sin(v.h) * back + cos(v.h) * off,
					v.z + .004,
					way,
					SKID_MARK,
					SKID_WIDE
				]
			)
	elif mowing and step % 6 == 0:
		marks.append(
			[v.x - cos(v.h) * .5, v.y - sin(v.h) * .5, v.z + .003, v.h, "detail_wear_silt", .5]
		)
	while marks.size() > MARKS_MAX:
		marks.pop_front()
	if mowing and step % 2 == 0:
		# Out of the chute on its right side, in a spray of bits.
		var clips: Array = _looks["clips"]
		var out := Vector2(-sin(v.h), cos(v.h))
		var fan := _dice.randf_range(-.5, .5)
		var throw := 1.2 + _dice.randf() * 1.1
		clips.append(
			[
				v.x + out.x * s.width * .5,
				v.y + out.y * s.width * .5,
				v.z + .18,
				(out.x + cos(v.h) * fan) * throw + v.vx * .5,
				(out.y + sin(v.h) * fan) * throw + v.vy * .5,
				1.2 + _dice.randf() * 1.0,
				game.clock
			]
		)
		while clips.size() > CLIPS_MAX:
			clips.pop_front()


## Sparks where it scrapes a wall (the car's steel on brick and concrete).
func _sparks(v: VehicleDrive.Ride, speed: float) -> void:
	var sparks: Array = _looks["sparks"]
	var count := clampi(int(speed * 1.3), 6, 14)
	for _k in count:
		var a := _dice.randf() * TAU
		var fly := _dice.randf_range(1.0, 3.2)
		sparks.append(
			[
				v.bump_x,
				v.bump_y,
				v.z + .2 + _dice.randf() * .3,
				cos(a) * fly - v.vx * .25,
				sin(a) * fly - v.vy * .25,
				_dice.randf_range(.8, 2.6),
				game.clock
			]
		)
	while sparks.size() > SPARKS_MAX:
		sparks.pop_front()


## The airboat on the water: spray off the bow (more in a turn, a sheet off
## the outside when it slides) and a wake behind it, two rings at a time.
func _spray(i: int, v: VehicleDrive.Ride, s: VehicleDrive.Spec, speed: float, dt: float) -> void:
	var f := Vector2(cos(v.h), sin(v.h))
	var r := Vector2(-sin(v.h), cos(v.h))
	var spray: Array = _looks["spray"]
	var chance := clampf((speed - 1.5) / 6.0, 0.0, 1.0) + clampf(v.slide * .4, 0.0, .8)
	if _dice.randf() < chance:
		var bow := Vector2(v.x, v.y) + f * s.length * .45
		for side: float in [-1.0, 1.0]:
			var at := bow + r * side * s.width * .45
			var out := r * side * _dice.randf_range(.6, 1.6) + f * speed * .25
			spray.append(
				[at.x, at.y, v.z + .1, out.x, out.y, _dice.randf_range(1.0, 2.2), game.clock]
			)
	while spray.size() > SPRAY_MAX:
		spray.pop_front()
	var wake: Array = _looks["wake"]
	var gone: float = wake[i]
	gone += speed * dt
	if gone >= WAKE_EVERY:
		gone = 0.0
		var water: GameFeature = game.features.get("water")
		if water != null and water.has_method("ring"):
			var stern := Vector2(v.x, v.y) - f * s.length * .55
			for side: float in [-1.0, 1.0]:
				var at := stern + r * side * s.width * .4
				water.call("ring", at.x, at.y, .5 + speed * .06)
	wake[i] = gone


## The seat's eye on the springs (game_view.gd, the local player's view
## only): it rises and falls and tips with the body, a little, and less or
## not at all with EASY ON THE EYES; the engine's buzz, the dip and the
## widening at speed, and the driver's own vehicle from the seat (the cab:
## src/vehicle_cab.gd).
func sway_eye(eye: Dictionary) -> void:
	if rides.is_empty():
		return
	var at := seat_of(game.local_player)
	var bodies: Array = _looks["bodies"]
	if at.x < 0 or at.x >= bodies.size():
		return
	var calm: float = SWAY[clampi(game.view.world_motion, 0, 2)]
	var v: VehicleDrive.Ride = rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	var props: Array = _looks["props"]
	var turned: float = props[at.x] if at.x < props.size() else 0.0
	var b: VehicleFeel.Body = bodies[at.x]
	VehicleCab.dress(eye, v, s, b, at.y, calm, game.shake_scale, game.clock, turned, cab_drawn(s))
	var cab: Dictionary = eye.get("cab", {})
	if not cab.is_empty() and s.window:
		# The car's hands: none at the wheel with nobody there; the right
		# one off it while the driver's gun is out of the window.
		var at_wheel: int = v.seats[0]
		var driver := _player(at_wheel)
		var fade: Dictionary = cab["fade"]
		fade["hand_l"] = 0.0 if driver == null else 1.0
		fade["hand_r"] = 0.0 if driver == null or not driver.armory.holstered else 1.0


## The lamps' lights near `p` (view_lights.gd).
func lights(p: Player) -> Array:
	if rides.is_empty() or not active():
		return []
	return VehicleFinder.lights(rides, p, game.clock)


## The radio left playing in a ready vehicle near `p`: Vector3(x, y, how
## loud), or Vector3.INF (game.gd's surroundings).
func radio(p: Player) -> Vector3:
	if rides.is_empty() or not active():
		return Vector3.INF
	return VehicleFinder.radio(rides, p)


## Whether this machine draws the driver's own vehicle from the seat (a
## window, and the cab's art: a browser build may not have it yet).
func cab_drawn(s: VehicleDrive.Spec) -> bool:
	return game.view.layered and s.cab != "" and game.art.has_art("mesh_" + s.cab)


## The body of ride i on its springs (for the checks and the frames).
func body(i: int) -> VehicleFeel.Body:
	var bodies: Array = _looks["bodies"]
	return bodies[i] if i >= 0 and i < bodies.size() else null


## The marks and bits in the looks (for the checks): "marks", "spray",
## "sparks", "clips".
func looks_count(kind: String) -> int:
	var list: Array = _looks.get(kind, [])
	return list.size()


## Hurts a vehicle; at 0 it is wrecked.
func _hurt(v: VehicleDrive.Ride, amount: float) -> void:
	if v.wreck >= 0.0 or amount <= 0.0:
		return
	v.hp = maxf(0.0, v.hp - amount)
	if v.hp <= 0.0:
		_wreck(v)


## Its tank goes: everyone in it is thrown out and hurt, a blast, a fire.
func _wreck(v: VehicleDrive.Ride) -> void:
	v.wreck = game.clock
	v.vx *= .3
	v.vy *= .3
	var s := VehicleDrive.spec(v.kind)
	for k in v.seats.size():
		var in_seat: int = v.seats[k]
		var q := _player(in_seat)
		if q == null:
			continue
		_get_out(q, v, k, true)
		game.damage(VehicleDrive.shared("eject_damage"), [v.x, v.y], "WRECK", q)
		_say(q, "THE " + s.name + " IS DONE FOR. BAIL OUT!")
	var blast: String = Tuning.file(VehicleDrive.FILE).get_value("all", "wreck_blast", "fuel")
	var shot := Game.Shot.new(v.x, v.y, v.z + .6, 0.0, 0.0, 0.0, blast, 0.0, false, 0)
	shot.owner = -1
	game.explode(shot)


## Hurts that reach a seated player: the vehicle takes its share (`soak`).
## Returns what is left for the player.
func soak(p: Player, amount: float) -> float:
	var at := seat_of(p)
	if at.x < 0:
		return amount
	var v: VehicleDrive.Ride = rides[at.x]
	var share := amount * VehicleDrive.spec(v.kind).soak
	_hurt(v, share)
	return amount - share


## A blast near a vehicle hurts it.
func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	var reach := VehicleDrive.shared("blast_reach")
	for v: VehicleDrive.Ride in rides:
		if absf(v.x - x) > reach + 2.0 or absf(v.y - y) > reach + 2.0:
			continue
		var g := VehicleDrive.gap(VehicleDrive.spec(v.kind), v, x, y)
		if g < reach:
			_hurt(v, VehicleDrive.shared("blast_damage") * (1.0 - g / reach))


## Every tick: riders who are down or gone get out, a vehicle nobody drives
## rolls to a stop (running down what it rolls into), and nobody on foot
## stands inside a hull.
func _tick(dt: float) -> void:
	var on := active()
	if not game.host and on:
		# A vehicle's line, the first time a player comes near it (looks).
		var told: Dictionary = _looks["told"]
		VehicleFinder.spot(game, rides, told)
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		var s := VehicleDrive.spec(v.kind)
		if not game.host and on:
			_feel(i, v, s, dt)
		for k in v.seats.size():
			var slot: int = v.seats[k]
			if slot < 0:
				continue
			var q := _player(slot)
			if q == null or q.health <= 0 or not on:
				v.seats[k] = -1
				if q != null:
					_get_out(q, v, k, true)
		var driver: int = v.seats[0]
		if driver < 0 and VehicleDrive.speed(v) > .02:
			var idle := GameState.Controls.new()
			var h := v.h
			VehicleDrive.throttle(v, s, idle, 0.0, dt, 1.0)
			var struck := VehicleDrive.move(game.world, v, s, dt, h)
			if struck > 0.0:
				_bump(v, s, struck, null)
			var near: Player = Players.nearest(game, v.x, v.y)
			_run_over(v, s, near if near != null else game.players[0], idle, dt)
			for k in range(1, v.seats.size()):
				var rider_slot: int = v.seats[k]
				var rider := _player(rider_slot)
				if rider != null:
					_place(rider, v, s, k, 0.0)
		_clear_hull(v, s)


func _player(slot: int) -> Player:
	if slot < 0:
		return null
	for q: Player in game.players:
		if q.slot == slot:
			return q
	return null


## Players on foot and bodies inside the hull are put out of it.
func _clear_hull(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> void:
	var far := s.length * .5 + 1.0
	for q: Player in game.players:
		if q.health <= 0 or absf(q.x - v.x) > far or absf(q.y - v.y) > far or seated(q):
			continue
		var push := VehicleDrive.out_of(s, v, q.x, q.y, GameState.PLAYER_RADIUS)
		if push != Vector2.INF:
			game.focus(q)
			game.move_actor(q, push.x, push.y, GameState.PLAYER_RADIUS)
			game.focus(game.local_player)
	var vx := v.x
	var vy := v.y
	for e: Enemy in game.enemies:
		# Far first: `alive` is worked out (the same hands pass either way).
		if absf(e.x - vx) > far or absf(e.y - vy) > far or e.dormant or not e.alive:
			continue
		var out := VehicleDrive.out_of(s, v, e.x, e.y, e.radius)
		if out != Vector2.INF and not Enemy.BOSS_TITLES.has(e.kind):
			game.move_actor(e, out.x, out.y, e.radius)


func save() -> Dictionary:
	if rides.is_empty():
		return {}
	var out: Array = []
	for v: VehicleDrive.Ride in rides:
		(
			out
			. append(
				[
					v.kind,
					snappedf(v.x, .001),
					snappedf(v.y, .001),
					snappedf(v.z, .001),
					snappedf(v.h, .0001),
					snappedf(v.hp, .1),
					v.wreck,
					v.seats.duplicate(),
				]
			)
		)
	return {"rides": out}


func restore(state: Dictionary) -> void:
	var saved: Array = state.get("rides", [])
	for i in mini(saved.size(), rides.size()):
		var row: Array = saved[i]
		var v: VehicleDrive.Ride = rides[i]
		if row.size() < 8 or str(row[0]) != v.kind:
			continue
		v.x = row[1]
		v.y = row[2]
		v.z = row[3]
		v.h = row[4]
		v.hp = row[5]
		v.wreck = row[6]
		v.vx = 0.0
		v.vy = 0.0
		# A save file's numbers come back as floats: the seats are slots again,
		# or seat_of never finds its rider and the seat stays taken for good.
		var seats: Array = row[7]
		v.seats = []
		for who: Variant in seats:
			var slot: int = who
			v.seats.append(slot)
		while v.seats.size() < maxi(1, VehicleDrive.spec(v.kind).seats):
			# Saved before it had another seat (the car's passenger).
			v.seats.append(-1)
	# Put down somewhere new: the springs start again from rest.
	var bodies: Array = _looks["bodies"]
	for i in bodies.size():
		bodies[i] = VehicleFeel.Body.new()


# ------------------------------------------------------------------- looks


## Each vehicle as its prop's model turned to its heading, with smoke and
## flames over it when hurt or burning, and the mower's clippings.
func sprites() -> Array:
	var out: Array = []
	if rides.is_empty() or not active():
		return out
	var mine := seat_of(game.local_player)
	VehicleFinder.glows(game, rides, mine.x if mine.y == 0 else -1, out)
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		var s := VehicleDrive.spec(v.kind)
		if not game.in_view(v.x, v.y, s.length):
			continue
		var seat_view := mine.x == i and (mine.y == 0 or (s.window and cab_drawn(s)))
		if seat_view and (s.hands == 0 or cab_drawn(s)) and game.eye_override.is_empty():
			# Its driver sees it from the seat (the cab: src/vehicle_cab.gd),
			# or the car's dash and wheel (draw_view), not its shell around
			# the eye.
			_smoke(out, v, s)
			continue
		if v.wreck >= 0.0:
			# A wreck: its hulk without the parts that came off, on its rims
			# (gun_fx.gd's src/vehicle_wreck_looks.gd; looks only).
			var fx: GameFeature = game.features.get("gun_fx")
			var hulk: Variant = fx.call("hulk", i) if fx != null else null
			if hulk != null:
				out.append(hulk)
				_smoke(out, v, s)
				continue
		# Its model on the move (the 3D view keeps one by its track), turned
		# to its heading and tipped on its springs (src/vehicle_feel.gd).
		var b := body(i)
		var spr := View.Sprite.new(v.x, v.y, s.picture, s.height, v.z)
		spr.body = true
		spr.plane = s.nose
		spr.track = "ride%d" % i
		if b != null:
			spr.z = v.z + b.heave
			spr.turn = VehicleFeel.turn(b, v.h)
		else:
			spr.turn = Basis(Vector3(0.0, 0.0, 1.0), v.h)
		out.append(spr)
		_smoke(out, v, s)
	var clips: Array = _looks["clips"]
	var spray: Array = _looks["spray"]
	var sparks: Array = _looks["sparks"]
	_fly(out, clips, .9, 4.0, "fx_chaff_%d", 2, .12, false)
	_fly(out, spray, .7, 6.0, "fx_spray_%d", 4, .34, false)
	# A scrape's sparks a third of a cell across and over half a second: at
	# 320 wide the smaller, quicker ones were a pixel for a frame or two.
	_fly(out, sparks, .6, 6.0, "fx_sparks_%d", 3, .34, true)
	return out


## Bits in the air ([x, y, z, vx, vy, vz, born]): each `life` seconds,
## falling by `fall`, its picture `name` % frame (of `frames`) by its age.
func _fly(
	out: Array,
	list: Array,
	life: float,
	fall: float,
	name: String,
	frames: int,
	size: float,
	glow: bool
) -> void:
	for c: Array in list:
		var born: float = c[6]
		var age := game.clock - born
		if age > life or age < 0.0:
			continue
		var z0: float = c[2]
		var vz: float = c[5]
		var cz := z0 + vz * age - fall * age * age
		if cz < z0 - .25:
			continue
		var cx: float = c[0]
		var cy: float = c[1]
		var dx: float = c[3]
		var dy: float = c[4]
		# Two frames tumble (the clippings); more play through once.
		var frame := (
			int(age * 9.0) % 2 if frames == 2 else mini(frames - 1, int(age / life * frames))
		)
		var bit := game.pooled(cx + dx * age, cy + dy * age, name % frame, size, cz)
		if glow:
			bit.glow = true
		else:
			bit.translucent = frames > 2
		out.append(bit)


## Smoke from a hurt engine (thick, with flames, under a quarter and while a
## wreck burns), worked out from the clock: nothing kept.
func _smoke(out: Array, v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> void:
	if Effects.rich:
		# With LIGHTS AND GLOW the gun and blast layer smokes and burns it
		# (src/vehicle_wreck_looks.gd).
		return
	var burning := v.wreck >= 0.0 and game.clock - v.wreck < VehicleDrive.shared("burn")
	var share := v.hp / maxf(1.0, s.hp)
	if share > .5 and v.wreck < 0.0:
		return
	var back := s.length * .3
	var ex := v.x - cos(v.h) * back
	var ey := v.y - sin(v.h) * back
	var ez := v.z + s.tall
	var puffs := PUFFS if burning or share < .25 else PUFFS / 2
	for k in puffs:
		var phase := fposmod(game.clock * .45 + float(k) / puffs, 1.0)
		var px := ex + sin(k * 2.3 + phase * 3.0) * .25 + phase * .5
		var py := ey + cos(k * 1.7 + phase * 2.0) * .25
		var name := "fx_smoke_%d" % mini(3, int(phase * 4.0))
		var puff := game.pooled(px, py, name, .5 + phase * .9, ez + phase * 2.2)
		puff.translucent = true
		out.append(puff)
	if burning or (share < .25 and v.wreck < 0.0):
		for k in 3:
			var flick := int(game.clock * 12.0 + k * 5) % 4
			var flame := game.pooled(
				ex + (k - 1) * .3,
				ey + (k - 1) * .2,
				"fx_flame_%d" % flick,
				.55 if burning else .35,
				ez - .3
			)
			flame.glow = true
			out.append(flame)


func ground_marks() -> Array:
	var out: Array = []
	if rides.is_empty():
		return out
	var p := game.player
	for m: Array in _looks["marks"]:
		var mx: float = m[0]
		var my: float = m[1]
		if absf(mx - p.x) > 24.0 or absf(my - p.y) > 24.0:
			continue
		var mz: float = m[2]
		var ma: float = m[3]
		var wide: float = m[5] if m.size() > 5 else .5
		var reach := .55 if wide >= .3 else .32
		out.append(View.GroundMark.new(mx, my, mz, ma, reach, wide, str(m[4])))
	for v: VehicleDrive.Ride in rides:
		if v.wreck >= 0.0:
			out.append(View.GroundMark.new(v.x, v.y, v.z + .005, 0.0, 1.6, 1.6, "mark_scorch_0"))
	return out


## For the local player in a vehicle: the speed and the vehicle's health in
## the view's corner, the car's wheel, and the lap timer at the speedway.
func draw_view(c: Canvas) -> void:
	if rides.is_empty():
		return
	var at := seat_of(game.local_player)
	if at.x < 0 or not game.eye_override.is_empty():
		# PHOTO MODE's free camera sees the car from outside: no dash.
		return
	var v: VehicleDrive.Ride = rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	var drops: Array = _looks["drops"]
	VehicleCab.draw_spray(c, drops, game.view_eye, game.clock)
	if at.y == 0 and s.hands == 0 and not cab_drawn(s):
		# Without the seat view (no window, or its art not here yet): the
		# car's painted dash, riding the springs with the eye a pixel or two.
		var b := body(at.x)
		var calm: float = SWAY[clampi(game.view.world_motion, 0, 2)]
		# Never up off the view's bottom edge: it sits a pixel down to rise.
		var lift := 0
		if b != null and calm > 0.0:
			lift = clampi(1 + roundi(b.heave * 30.0 * calm), 0, 3)
		VehicleLooks.cab(c, v.steer, VehicleDrive.speed(v) / maxf(1.0, s.top), lift)
	var plate := game.hud.layout.find("drive")
	if plate.size.x > 0:
		HudLayout.begin(c, "drive")
		VehicleHud.draw(c, game, v, s, at.y == 0, plate.position)
		HudLayout.end(c)
	var lap := game.hud.layout.find("lap")
	if lap.size.x > 0:
		HudLayout.begin(c, "lap")
		c.label(_lap_text(v), View.WIDTH / 2, lap.position.y + 1, "body", INK, true)
		HudLayout.end(c)


## The plate and the speedway's lap timer go where the HUD's layout has room
## (ui/hud/hud_layout.gd): the plate down the left, the timer across the top.
func hud_flow(layout: HudLayout) -> void:
	if rides.is_empty():
		return
	var at := seat_of(game.local_player)
	if at.x < 0 or not game.eye_override.is_empty():
		return
	var v: VehicleDrive.Ride = rides[at.x]
	layout.down("drive", VehicleHud.size(game.hud.minimal), VehicleHud.AT.x, VehicleHud.AT.y)
	var runs: GameFeature = game.features.get("vehicle_runs")
	if runs != null and runs.call("live"):
		return  # a set piece's own timer is up (features/vehicle_runs.gd)
	if not line.is_empty() and v.kind == "car" and at.y == 0:
		var box := HudLayout.text_rect(_lap_text(v), 0, 0, "body")
		layout.centred("lap", box.size, HudLayout.TOP)


func _lap_text(v: VehicleDrive.Ride) -> String:
	var text := "LAP " + clock_text(game.clock - v.lap_start)
	if v.lap_best > 0.0:
		text += "   BEST " + clock_text(v.lap_best)
	return text
