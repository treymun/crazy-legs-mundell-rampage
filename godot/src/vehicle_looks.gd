## What a driver sees of the car in place of the gun: the dash under the
## windscreen (brown vinyl, a speedometer and a tach whose needles follow the
## speed) and the top of a worn steering wheel (taped leather over a steel
## rim, two chrome spokes) turning as it steers. Painted once in code (the
## wheel a turn at a time, seven of them) and drawn as cached pictures
## (Canvas.blit_rgba); the car's own model is left out of its driver's view.
## Since the engine pass after 3.3.0 only without the seat view (no window,
## or the cab's art not here yet: features/vehicles.gd cab_drawn); with it
## the driver sees the car's own dash, wheel and hood in 3D
## (src/vehicle_cab.gd, view3d/cab_layer.gd).
class_name VehicleLooks
extends RefCounted

const W := 132
const H := 34
## The wheel's middle below the picture's bottom edge, its rim's radius and
## the rim's thickness (pixels).
const DROP := 30
const RIM := 60
const THICK := 7
const TURNS := 7
## How far the wheel turns at full lock (radians).
const LOCK := .9
const LEATHER := Color8(70, 44, 28)
const LEATHER_LIT := Color8(126, 86, 52)
const LEATHER_DARK := Color8(34, 22, 15)
const TAPE := Color8(150, 140, 112)
const CHROME := Color8(176, 172, 158)
const CHROME_DARK := Color8(84, 82, 76)

## The dash under the windscreen: its height, the gauges' middles and radius.
const DASH_H := 20
const GAUGES := [Vector2i(96, 10), Vector2i(224, 10)]
const GAUGE_R := 8
const VINYL := Color8(44, 30, 22)
const VINYL_LIT := Color8(82, 58, 40)
const FACE := Color8(222, 206, 160)
const NEEDLE := Color8(200, 40, 24)

static var _turns: Array = []
static var _dash := PackedByteArray()


## The dash across the bottom of the view, its gauges' needles at `pace`
## (0..1 of top speed), then the wheel over it; both `lift` pixels down (the
## body on its springs, vehicle_feel.gd).
static func cab(c: Canvas, steer: float, pace: float, lift := 0) -> void:
	if _dash.is_empty():
		_dash = _paint_dash()
	var top := View.VIEW - DASH_H + lift
	c.blit_rgba(_dash, View.WIDTH, DASH_H, 0, top, "vehicle_dash")
	for k in GAUGES.size():
		var g: Vector2i = GAUGES[k]
		# The speedometer and a tach that runs ahead of it.
		var turn := clampf(pace * (1.0 if k == 0 else 1.3), 0.0, 1.0)
		var a := PI * (1.15 - 1.3 * turn)
		var tip := Vector2(g.x + cos(a) * (GAUGE_R - 2), top + g.y - sin(a) * (GAUGE_R - 2))
		c.line(g.x, top + g.y, int(tip.x), int(tip.y), NEEDLE)
	wheel(c, steer, lift)


static func _paint_dash() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(View.WIDTH * DASH_H * 4)
	for py in DASH_H:
		for px in View.WIDTH:
			# A dash a little higher in the middle (the hood's line), lit on top.
			var mid := absf(px - View.WIDTH * .5) / (View.WIDTH * .5)
			var edge := 3.0 + mid * mid * 5.0
			var col := Color(0, 0, 0, 0)
			if py >= edge:
				col = VINYL_LIT if py < edge + 2.0 else VINYL
				if int(px * 3 + py * 7) % 11 == 0:
					col = col.darkened(.2)
				for g: Vector2i in GAUGES:
					var d := Vector2(px + .5 - g.x, py + .5 - g.y).length()
					if d <= GAUGE_R:
						col = FACE if d < GAUGE_R - 1.5 else CHROME
						var a := atan2(-(py + .5 - g.y), px + .5 - g.x)
						# Ticks round the face.
						var tick := absf(fposmod(a * 6.0 / PI + .5, 1.0) - .5) < .12
						if d > GAUGE_R - 3.5 and d < GAUGE_R - 1.5 and tick:
							col = LEATHER_DARK
			var at := (py * View.WIDTH + px) * 4
			data[at] = int(col.r * 255.0)
			data[at + 1] = int(col.g * 255.0)
			data[at + 2] = int(col.b * 255.0)
			data[at + 3] = int(col.a * 255.0)
	return data


## Draws the wheel turned by `steer` (-1..1) at the bottom of the view,
## `lift` pixels down.
static func wheel(c: Canvas, steer: float, lift := 0) -> void:
	if _turns.is_empty():
		for k in TURNS:
			_turns.append(_paint(LOCK * (float(k) / (TURNS - 1) * 2.0 - 1.0)))
	var k := clampi(roundi((steer + 1.0) * .5 * (TURNS - 1)), 0, TURNS - 1)
	var data: PackedByteArray = _turns[k]
	c.blit_rgba(data, W, H, (View.WIDTH - W) / 2, View.VIEW - H + lift, "vehicle_wheel_%d" % k)


static func _paint(turn: float) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(W * H * 4)
	var cx := W * .5
	var cy := float(H + DROP)
	for py in H:
		for px in W:
			var dx := px + .5 - cx
			var dy := py + .5 - cy
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx) - turn
			var col := Color(0, 0, 0, 0)
			if r <= RIM and r >= RIM - THICK:
				# Leather lit from above, darker on its inner edge; grips of tape.
				var t := (RIM - r) / THICK
				col = LEATHER_LIT if t < .3 else LEATHER if t < .75 else LEATHER_DARK
				var round_a := fposmod(a + PI * .5, TAU)
				if absf(round_a - .55) < .07 or absf(round_a - (TAU - .55)) < .07:
					col = TAPE
				if int(px + py) % 5 == 0 and t > .2 and t < .7:
					col = col.darkened(.15)
			elif r < RIM - THICK:
				# Two spokes out to the rim at ten and two o'clock.
				for spoke: float in [-PI + .5, -.5]:
					var off := absf(wrapf(a - spoke, -PI, PI))
					var across := sin(off) * r
					if off < PI * .5 and across < 3.2:
						col = CHROME if across < 1.6 else CHROME_DARK
			var at := (py * W + px) * 4
			data[at] = int(col.r * 255.0)
			data[at + 1] = int(col.g * 255.0)
			data[at + 2] = int(col.b * 255.0)
			data[at + 3] = int(col.a * 255.0)
	return data
