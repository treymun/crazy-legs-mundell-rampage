## Blood on the crowbar and the sling blade. A close hit that draws blood
## (gore.gd spray, the local player swinging) wets the business end; more
## hits wet it further (three stages), and it dries off stage by stage over
## LASTS seconds. Looks only: kept here by gun rack, never in a save or a
## snapshot. weapons.gd draws the wet copy of the cel (`smear`), cached with
## the graded one.
class_name MeleeBlood
extends RefCounted

const GUNS := [Weapons.CROWBAR, Weapons.SLING]
## Seconds from three stages wet to clean.
const LASTS := 36.0
## A hit's share of a stage by its damage (a crowbar swing is about 30).
const PER_DAMAGE := 1.0 / 30.0
const RED := [Color8(120, 14, 10), Color8(78, 6, 6), Color8(150, 30, 20)]
const GREEN := [Color8(92, 168, 54), Color8(50, 104, 34), Color8(130, 196, 80)]

## armory instance id -> {gun: [wet 0..3, when (ms), green]}
static var _wet := {}


## A melee hit drew blood.
static func bloody(armory, gun: int, damage: float, green: bool) -> void:
	if not GUNS.has(gun) or armory == null:
		return
	var id: int = armory.get_instance_id()
	if _wet.size() > 8 and not _wet.has(id):
		_wet.clear()
	var guns: Dictionary = _wet.get(id, {})
	var now := Time.get_ticks_msec()
	var wet := minf(3.0, _left(guns.get(gun, []), now) + maxf(.6, damage * PER_DAMAGE))
	guns[gun] = [wet, now, green]
	_wet[id] = guns


## How wet `gun` is now: 0 (clean) to 3.
static func stage(armory, gun: int) -> int:
	if not GUNS.has(gun):
		return 0
	var guns: Dictionary = _wet.get(armory.get_instance_id(), {})
	return ceili(_left(guns.get(gun, []), Time.get_ticks_msec()))


static func green(armory, gun: int) -> bool:
	var row: Array = _wet.get(armory.get_instance_id(), {}).get(gun, [])
	return row.size() > 2 and bool(row[2])


static func _left(row: Array, now: int) -> float:
	if row.is_empty():
		return 0.0
	return maxf(0.0, float(row[0]) - (now - int(row[1])) / 1000.0 / LASTS * 3.0)


## A copy of the graded cel `image` with the end away from the hand wet:
## thick at the tip, thinning toward the hand, in blotches that stay put from
## frame to frame (a hash of the pixel's place).
static func smear(image: Dictionary, wet: int, is_green: bool) -> Dictionary:
	var w: int = image["w"]
	var h: int = image["h"]
	var data: PackedByteArray = (image["data"] as PackedByteArray).duplicate()
	var colors: Array = GREEN if is_green else RED
	# The cel's opaque box, so the tip is measured on the weapon, not the frame.
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] > 0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return image
	# The grip: the middle of what is in the bottom rows (the views all come up
	# from the bottom of the screen); the tip: the farthest pixel from it.
	var grip := Vector2.ZERO
	var count := 0
	for y in range(maxi(y0, y1 - maxi(2, (y1 - y0) / 7)), y1 + 1):
		for x in range(x0, x1 + 1):
			if data[(y * w + x) * 4 + 3] > 0:
				grip += Vector2(x, y)
				count += 1
	grip /= maxf(1.0, count)
	var span := 1.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if data[(y * w + x) * 4 + 3] > 0:
				span = maxf(span, grip.distance_to(Vector2(x, y)))
	var reach := .25 + .14 * wet
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var o := (y * w + x) * 4
			if data[o + 3] < 128:
				continue
			var t := grip.distance_to(Vector2(x, y)) / span
			if t < 1.0 - reach:
				continue
			var weight := (t - (1.0 - reach)) / reach
			var noise := _hash(x, y)
			# Blotches: noise smoothed over 4-pixel cells.
			var blob := _smooth(x / 4.0, y / 4.0)
			if blob * .75 + noise * .25 > 1.0 - weight * (.45 + .17 * wet):
				var c: Color = colors[mini(2, int(_smooth(x / 3.0 + 40.0, y / 3.0) * 3.0))]
				var keep := .25 if noise > .8 else .1
				data[o] = int(lerpf(c.r8, data[o], keep))
				data[o + 1] = int(lerpf(c.g8, data[o + 1], keep))
				data[o + 2] = int(lerpf(c.b8, data[o + 2], keep))
	var out := image.duplicate()
	out["data"] = data
	return out


static func _hash(x: int, y: int) -> float:
	return (((x * 73856093) ^ (y * 19349663) ^ (x * y * 83492791)) & 0xffff) / 65535.0


## Value noise: the hashes of the four whole points round (fx, fy), blended.
static func _smooth(fx: float, fy: float) -> float:
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := smoothstep(0.0, 1.0, fx - ix)
	var ty := smoothstep(0.0, 1.0, fy - iy)
	var top := lerpf(_hash(ix + 91, iy + 7), _hash(ix + 92, iy + 7), tx)
	var bottom := lerpf(_hash(ix + 91, iy + 8), _hash(ix + 92, iy + 8), tx)
	return lerpf(top, bottom, ty)
