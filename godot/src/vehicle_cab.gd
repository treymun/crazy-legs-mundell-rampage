## What a driver sees from the seat (features/vehicles.gd calls it for this
## machine's player; looks only, never play): their own vehicle's front in
## the 3D view (the frame's eye gets a `cab` that view3d/cab_layer.gd draws:
## the airboat's deck, rails, bow, stick and the fan cage behind; the car's
## hood, pillars, dash and wheel; the mower's hood, wheel and deck), riding
## the body's springs (src/vehicle_feel.gd) against the eye, its wheel or
## stick turned with the steering, its needles, prop and blade lever going;
## and how the seat feels: the engine's buzz and the mower's chug in the
## view, the eye dipping at speed and the view widening a little more the
## faster it goes; spray over the airboat's bow. SCREEN SHAKE scales the
## shaking, SCENERY MOTION (EASY ON THE EYES) the shaking, the dip and the
## widening (none when STILL). Numbers per kind in data/tuning/vehicles.cfg
## (cab, cab_drop, cab_tilt, cab_lock, buzz, buzz_hz, chug, seat_dip).
class_name VehicleCab
extends RefCounted

## A driver's view widens to this focal (83 degrees across) when the FIELD
## OF VIEW setting is narrower; the faster, the wider by up to KICK more.
const DRIVE_FOCAL := 180.0
const KICK := .07
## The share of each step of SCENERY MOTION's sway that full motion has
## (vehicles.gd SWAY's first).
const FULL_SWAY := .7
## The body's pitch in view lines a radian (the horizon's shift).
const SWAY_PITCH := 55.0
## The fan's prop and the tach: idling and flat out (radians a second, and
## the share of the dial).
const PROP_IDLE := 5.0
const PROP_FULL := 31.0
const IDLE := .16
## The prop's blades fade into a spinning disc from this much of the engine's
## work, over this much more.
const BLUR_FROM := .3
const BLUR_SPAN := .45
## A gauge's needle sweeps 270 degrees from its rest at the bottom left.
const NEEDLE_REST := deg_to_rad(135.0)
const NEEDLE_SWEEP := deg_to_rad(270.0)
## The mower's blade lever on and off (radians, forward is on).
const LEVER_ON := .38
const LEVER_OFF := -.3
## Spray over the airboat's bow: at most, how long each flies (seconds), how
## fast it falls (cells a second squared); the bow's corners in the cab's own
## axes (ahead, right, up from the eye: vehicle_cabs.py's bow cap).
const DROPS_MOST := 40
const DROP_LIFE := .55
const DROP_FALL := 7.0
const BOW := Vector3(2.9, .62, -.88)
const SPRAY_LIGHT := Color8(214, 226, 230)
const SPRAY_DARK := Color8(150, 172, 182)


## How hard the engine is working (0..1): the throttle, or the speed.
static func rpm(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> float:
	var pace := clampf(VehicleDrive.speed(v) / maxf(1.0, s.top), 0.0, 1.0)
	if v.wreck >= 0.0:
		return 0.0
	return clampf(maxf(IDLE + (1.0 - IDLE) * absf(v.gas), pace), 0.0, 1.0)


## The car's gear for its speed (looks: the HUD and the tach; 0 neutral,
## -1 reverse) and where in that gear's band the engine is (0..1).
static func gear(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> Vector2:
	var along := VehicleDrive.along(v)
	if along < -.3:
		return Vector2(-1.0, clampf(-along / maxf(1.0, s.reverse), 0.0, 1.0))
	var pace := clampf(along / maxf(1.0, s.top), 0.0, 1.0)
	if pace < .02 and absf(v.gas) < .1:
		return Vector2(0.0, IDLE)
	var g := mini(4, 1 + int(pace * 4.0))
	var band := pace * 4.0 - (g - 1)
	return Vector2(g, clampf(.3 + band * .7, 0.0, 1.0))


## Dresses this machine's seated player's eye for the frame: the springs'
## sway (vehicles.gd sway_eye: `calm` of the bob and pitch), the buzz, the
## dip, the widening and, for the driver, the cab to draw. `looks` is the
## feature's looks (the prop's turn); `shake` SCREEN SHAKE's scale; `drawn`
## whether this machine draws a cab (a window and the art).
static func dress(
	eye: Dictionary,
	v: VehicleDrive.Ride,
	s: VehicleDrive.Spec,
	b: VehicleFeel.Body,
	seat: int,
	calm: float,
	shake: float,
	clock: float,
	prop_turn: float,
	drawn: bool
) -> void:
	var lift: float = eye["eye"]
	var pitch: float = eye["pitch"]
	var motion := calm / FULL_SWAY
	var pace := clampf(VehicleDrive.speed(v) / maxf(1.0, s.top), 0.0, 1.0)
	var work := rpm(v, s)
	if calm > 0.0:
		lift += b.heave * calm
		pitch += b.pitch * SWAY_PITCH * calm
		lift += s.seat_dip * pace * pace * motion
	# The engine through the seat: a buzz, and the mower's thump each turn.
	var shaking := shake * motion * (.35 + .65 * work)
	var w := TAU * s.buzz_hz
	var buzz := s.buzz * shaking * (sin(clock * w) * .6 + sin(clock * w * 1.71 + 1.3) * .4)
	var thump := s.chug * shaking * (absf(sin(clock * PI * (5.0 + 4.0 * work))) - .55)
	lift += buzz + thump
	pitch += (buzz * .7 + thump) * 90.0 + s.buzz * shaking * 60.0 * sin(clock * w * 1.3 + .4)
	eye["eye"] = lift
	eye["pitch"] = pitch
	var wide := 1.0
	if is_equal_approx(View.base_focal, View.fov_focal):
		wide = clampf(DRIVE_FOCAL / maxf(1.0, View.fov_focal), .75, 1.0)
	eye["wide"] = wide * (1.0 - KICK * pace * pace * motion)
	if (seat != 0 and not s.window) or not drawn or s.cab == "":
		return
	# The cab: tipped on the body's springs against the eye (which took
	# `calm` of them), the eye sitting `cab_drop` lower in it; a hair of the
	# buzz in the hood too. The car's passenger sees it from their seat,
	# `ride_side` to the right of the wheel.
	var turn := VehicleFeel.turn(b, v.h) * Basis(Vector3(0.0, 1.0, 0.0), -s.cab_tilt)
	var rest := turn * Vector3(0.0, -s.ride_side * seat, s.cab_drop)
	rest.z += b.heave * (1.0 - calm) - (buzz + thump) * .6
	var parts := {}
	var fade := {}
	var steer := clampf(v.steer, -1.0, 1.0)
	if v.wreck >= 0.0:
		steer = 0.0
	match v.kind:
		"airboat":
			parts["stick"] = steer * s.cab_lock
			parts["needle"] = NEEDLE_REST - NEEDLE_SWEEP * work
			parts["prop"] = prop_turn
			parts["blur"] = prop_turn
			# Spinning up, the blades fade into a stippled disc.
			var spin := clampf((work - BLUR_FROM) / BLUR_SPAN, 0.0, 1.0)
			fade["prop"] = 1.0 - spin * .75
			fade["blur"] = spin * .55
		"car":
			parts["steer"] = -steer * s.cab_lock
			parts["speed"] = NEEDLE_REST - NEEDLE_SWEEP * pace
			parts["tach"] = NEEDLE_REST - NEEDLE_SWEEP * gear(v, s).y
		"mower":
			parts["steer"] = -steer * s.cab_lock
			parts["lever"] = LEVER_ON if blade_on(v, s) else LEVER_OFF
	eye["cab"] = {"model": s.cab, "turn": turn, "lift": rest, "parts": parts, "fade": fade}


## The mower's blade is biting (its lever forward): on the throttle or
## rolling (features/vehicles.gd _run_over and _cut).
static func blade_on(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> bool:
	return s.blade > 0.0 and v.wreck < 0.0 and (VehicleDrive.speed(v) > .2 or absf(v.gas) > .1)


## How fast the airboat's prop turns this tick (radians a second).
static func prop_speed(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> float:
	return 0.0 if v.wreck >= 0.0 else lerpf(PROP_IDLE, PROP_FULL, rpm(v, s))


## Spray thrown up over the bow this tick (the feature's `drops`, in the
## cab's own axes from the eye: ahead, right, up, their speeds and when),
## more the faster and the more it slides, on `dice` (the looks' own).
static func spray(
	drops: Array, v: VehicleDrive.Ride, clock: float, dt: float, dice: RandomNumberGenerator
) -> void:
	var speed := VehicleDrive.speed(v)
	var rate := clampf((speed - 2.0) / 5.0, 0.0, 1.0) * 26.0 + clampf(v.slide, 0.0, 2.0) * 10.0
	var count := int(rate * dt + dice.randf())
	for _k in count:
		var side := -1.0 if dice.randf() < .5 else 1.0
		var at := Vector3(BOW.x, BOW.y * side * dice.randf_range(.5, 1.0), BOW.z)
		drops.append(
			[
				at,
				Vector3(
					-dice.randf_range(.6, 1.6) - speed * .12,
					side * dice.randf_range(.1, 1.0),
					dice.randf_range(1.2, 2.6) + speed * .08
				),
				clock
			]
		)
	while drops.size() > DROPS_MOST:
		drops.pop_front()


## Draws the spray over the bow on the view (under the gun): each drop where
## the cab (`cab`, the frame eye's) puts it, seen from `eye`, a pixel or two
## of white water.
static func draw_spray(c: Canvas, drops: Array, eye: Dictionary, clock: float) -> void:
	var cab: Dictionary = eye.get("cab", {})
	if cab.is_empty() or drops.is_empty():
		return
	var turn: Basis = cab["turn"]
	var rest: Vector3 = cab["lift"]
	var angle: float = eye["view_angle"]
	var wide: float = eye.get("wide", 1.0)
	var focal := View.base_focal * wide
	var pitch: float = eye["pitch"]
	var bob: float = eye.get("bob", 0.0)
	var sway: float = eye.get("sway", 0.0)
	var horizon := View.VIEW * .5 + (pitch + bob + sway) * wide
	var ca := cos(angle)
	var sa := sin(angle)
	for d: Array in drops:
		var born: float = d[2]
		var age := clock - born
		if age < 0.0 or age > DROP_LIFE:
			continue
		var at: Vector3 = d[0]
		var speed: Vector3 = d[1]
		var local := at + speed * age
		local.z -= DROP_FALL * age * age * .5
		var p := rest + turn * local
		var ahead := p.x * ca + p.y * sa
		if ahead < .2:
			continue
		var across := -p.x * sa + p.y * ca
		var sx := roundi(View.WIDTH * .5 + focal * across / ahead)
		var sy := roundi(horizon - focal * p.z / ahead)
		if sx < 0 or sx >= View.WIDTH or sy < 0 or sy >= View.VIEW:
			continue
		var big := 2 if ahead < 1.6 else 1
		c.fill_rect(sx, sy, big, big, SPRAY_LIGHT if age < DROP_LIFE * .6 else SPRAY_DARK)
