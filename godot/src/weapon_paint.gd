## Moved out of weapons.gd to keep it under the line limit; the originals call these.
class_name WeaponPaint
extends RefCounted


static func blit_rgba(frame: PackedByteArray, image: Dictionary, x: int, y: int) -> void:
	var w: int = image["w"]
	var h: int = image["h"]
	var data: PackedByteArray = image["data"]
	var spans = image.get("spans")
	var cv := Weapons.covering
	var cover := Weapons.cover
	if spans == null:
		for yy in h:
			var ty := y + yy
			if ty < 0 or ty >= Renderer.VIEW:
				continue
			var row := yy * w * 4
			for xx in w:
				var tx := x + xx
				if tx < 0 or tx >= Renderer.WIDTH:
					continue
				var sp := row + xx * 4
				var a := data[sp + 3]
				if a == 0:
					continue
				var o := (ty * Renderer.WIDTH + tx) * 3
				if cv:
					var p := o / 3
					cover[p] = (255 if a == 255 else cover[p] + (((255 - cover[p]) * a + 255) >> 8))
				if a == 255:
					frame[o] = data[sp]
					frame[o + 1] = data[sp + 1]
					frame[o + 2] = data[sp + 2]
				else:
					var k := a
					frame[o] = clampi(
						frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
					)
					frame[o + 1] = clampi(
						frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8),
						0,
						255
					)
					frame[o + 2] = clampi(
						frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8),
						0,
						255
					)
		return
	var ty0 := maxi(y, 0)
	var ty1 := mini(y + h, Renderer.VIEW)
	for yy in range(ty0 - y, ty1 - y):
		var first: int = spans[yy * 2]
		if first < 0:
			continue
		var last: int = spans[yy * 2 + 1]
		var ty := y + yy
		var row := yy * w * 4
		var x0 := maxi(x + first, 0)
		var x1 := mini(x + last, Renderer.WIDTH - 1)
		var o := (ty * Renderer.WIDTH + x0) * 3
		var sp := row + (x0 - x) * 4
		for tx in range(x0, x1 + 1):
			var a := data[sp + 3]
			if a != 0:
				if cv:
					var p := o / 3
					cover[p] = (255 if a == 255 else cover[p] + (((255 - cover[p]) * a + 255) >> 8))
				if a == 255:
					frame[o] = data[sp]
					frame[o + 1] = data[sp + 1]
					frame[o + 2] = data[sp + 2]
				else:
					var k := a
					frame[o] = clampi(
						frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
					)
					frame[o + 1] = clampi(
						frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8),
						0,
						255
					)
					frame[o + 2] = clampi(
						frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8),
						0,
						255
					)
			o += 3
			sp += 4
