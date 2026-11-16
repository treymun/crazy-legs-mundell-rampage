## How a vehicle looks on the move (features/vehicles.gd keeps one Body per
## ride in its `_looks`, which snapshots skip): its body on springs over the
## wheels or the hull, squatting on the throttle and diving under the brake,
## leaning out of a turn, bouncing over a kerb, a step or a rough field and
## coming down hard off a ledge; the airboat rocking on the water. Worked out
## from how the ride itself moved this tick (plain numbers every machine has,
## the driving untouched) with the vehicles' own dice for the jolts, so it
## never changes play. Numbers per kind in data/tuning/vehicles.cfg (spring,
## damp, lean, squat, rough, rock).
class_name VehicleFeel
extends RefCounted

## The springs' small step (seconds).
const STEP := 1.0 / 120.0
## A rise of the floor under it at least this tall (cells) is a bump the body
## takes on its springs; falling faster than LAND_FROM (cells a second) it
## lands with a thump.
const BUMP_FROM := .015
const LAND_FROM := 1.2
## How fast the forces it feels catch up (a second): the lean and squat come
## on smoothly, not in a snap.
const EASE := 10.0
## The most the body may bob (cells) or turn on its springs (radians).
const HEAVE_MOST := .22
const TURN_MOST := .3


## One vehicle's body on its springs: heave (up, cells), pitch (nose up,
## radians) and roll (its right side down: the side Vector2(-sin h, cos h)
## points to), each with its speed; what it felt this tick (along, across).
class Body:
	var heave := 0.0
	var heave_v := 0.0
	var pitch := 0.0
	var pitch_v := 0.0
	var roll := 0.0
	var roll_v := 0.0
	var acc := 0.0
	var lat := 0.0
	var last_along := 0.0
	var last_h := 0.0
	var last_z := 0.0
	var last_bumps := 0
	var fall := 0.0
	var started := false

	## Settled: nothing moving on the springs to speak of.
	func still() -> bool:
		return (
			absf(heave) + absf(pitch) + absf(roll) < .002
			and absf(heave_v) + absf(pitch_v) + absf(roll_v) < .01
		)


## One tick of `b` for ride `v`: the forces from how it moved, a bump or a
## landing, the jolts of `rough` (cells a second of jolting) on `dice`, the
## rocking at `clock` when it floats. Returns true when it struck a wall
## this tick (v.bumps went up).
static func step(
	b: Body,
	v: VehicleDrive.Ride,
	s: VehicleDrive.Spec,
	dt: float,
	rough: float,
	clock: float,
	dice: RandomNumberGenerator
) -> bool:
	var along := VehicleDrive.along(v)
	if not b.started or dt <= 0.0:
		b.started = true
		b.last_along = along
		b.last_h = v.h
		b.last_z = v.z
		b.last_bumps = v.bumps
		return false
	var acc := clampf((along - b.last_along) / dt, -40.0, 40.0)
	var yaw := wrapf(v.h - b.last_h, -PI, PI) / dt
	var ease := 1.0 - exp(-EASE * dt)
	b.acc = lerpf(b.acc, acc, ease)
	b.lat = lerpf(b.lat, along * yaw, ease)
	var dz := v.z - b.last_z
	if dz > BUMP_FROM:
		# The wheels went up a kerb or a step: the body lags below, nose first.
		b.heave = maxf(-HEAVE_MOST, b.heave - dz)
		b.pitch_v += dz * 6.0 * signf(along)
	if dz < -.0005:
		b.fall = minf(b.fall, dz / dt)
	elif b.fall < -LAND_FROM:
		# Down off a ledge: it lands on its springs, the nose dipping.
		b.heave_v += b.fall * .25
		b.pitch_v += b.fall * .15
		b.fall = 0.0
	else:
		b.fall = 0.0
	var struck := v.bumps != b.last_bumps
	if struck:
		# A wall: the nose kicks up and the body jars.
		var hit := clampf(VehicleDrive.speed(v) + 1.0, 0.0, 8.0)
		b.pitch_v += .09 * hit
		b.heave_v += .05 * hit
		b.roll_v += (dice.randf() - .5) * .12 * hit
	var speed := VehicleDrive.speed(v)
	if rough > 0.0 and speed > .2:
		# A rough field: a jolt every tick or so, bigger the faster it goes.
		var jolt := rough * minf(speed, 6.0) * dt
		b.heave_v += (dice.randf() - .5) * jolt * 6.0
		b.pitch_v += (dice.randf() - .5) * jolt * 5.0
		b.roll_v += (dice.randf() - .5) * jolt * 7.0
	b.last_along = along
	b.last_h = v.h
	b.last_z = v.z
	b.last_bumps = v.bumps
	# Where the springs pull it: out of the turn, back on the throttle.
	var roll_to := clampf(-s.lean * b.lat, -s.lean_most, s.lean_most)
	var pitch_to := clampf(s.squat * b.acc, -s.squat_most, s.squat_most)
	if s.rock > 0.0:
		# On the water it rocks, a slow swell more than a chop, less at speed.
		var calm := 1.0 / (1.0 + speed * .15)
		roll_to += s.rock * calm * (sin(clock * 1.7) * .7 + sin(clock * 2.9 + 1.1) * .3)
		pitch_to += s.rock * calm * .6 * sin(clock * 1.3 + .4)
		var surge := s.rock * .5 * calm * sin(clock * 2.1)
		b.heave_v += (surge - b.heave) * dt * 2.0
	var w := TAU * maxf(.1, s.spring)
	var z := clampf(s.damp, 0.0, 1.5)
	var n := maxi(1, ceili(dt / STEP))
	var h := dt / n
	for _k in n:
		b.heave_v += (-w * w * b.heave - 2.0 * z * w * b.heave_v) * h
		b.heave += b.heave_v * h
		b.pitch_v += (-w * w * (b.pitch - pitch_to) - 2.0 * z * w * b.pitch_v) * h
		b.pitch += b.pitch_v * h
		b.roll_v += (-w * w * (b.roll - roll_to) - 2.0 * z * w * b.roll_v) * h
		b.roll += b.roll_v * h
	b.heave = clampf(b.heave, -HEAVE_MOST, HEAVE_MOST)
	b.pitch = clampf(b.pitch, -TURN_MOST, TURN_MOST)
	b.roll = clampf(b.roll, -TURN_MOST, TURN_MOST)
	return struck


## The body's turn in map axes (x, y on the ground, z up) about its feet:
## heading h, the nose up by its pitch, its right side down by its roll
## (View.Sprite.turn for a prop on the move).
static func turn(b: Body, h: float) -> Basis:
	return (
		Basis(Vector3(0.0, 0.0, 1.0), h)
		* Basis(Vector3(0.0, 1.0, 0.0), -b.pitch)
		* Basis(Vector3(1.0, 0.0, 0.0), -b.roll)
	)


## How high (map z, from its feet) a point of the body `fwd` along it and
## `side` to its right (cells) stands, `up` over its floor: for the checks
## and the marks (which side leans down).
static func height_at(b: Body, h: float, fwd: float, side: float, up: float) -> float:
	var local := Vector3(fwd, side, up)
	return b.heave + (turn(b, h) * local).z
