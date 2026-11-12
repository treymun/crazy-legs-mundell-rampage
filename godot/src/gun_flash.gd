## The gun's muzzle flash on the view, painted under the gun by
## Weapons.Armory.draw. The software view (and the shader view without LIGHTS
## AND GLOW) gets the soft star it always had. The shader view with them
## (Effects.rich) gets each gun's own flash, weapons.cfg `flash_art` (a style
## of tools/art/build_gun_fx_art.gd's fx_mf_<style>_<v>_<f>): three hard-edged
## frames, two shapes taken shot by shot, over a glow that adds its light to
## the view, `flash_size` times the old flash's size.
class_name GunFlash
extends RefCounted


## `at` is where the gun is held (Armory._hold), `style` its muzzle_style,
## `count` its rounds left (which shape this shot shows).
static func draw(
	frame: PackedByteArray,
	assets: Assets,
	i: int,
	anchor: Vector3i,
	s: float,
	at: Vector2,
	shot_age: float,
	last_spent: int,
	style: Array,
	flashes: float,
	count: int
) -> void:
	var x := at.x
	var y := at.y
	var prefix := String(style[0])
	var aspect := float(style[1])
	if Effects.rich and Weapons.painter != null and Weapons.FLASH_ART.has(i):
		_rich(frame, assets, i, anchor, s, at, shot_age, last_spent, aspect, flashes, count)
		return
	var index := mini(3, int(shot_age * 48))
	var size := int(round((float(anchor.z) * 1.4 + (10.0 if last_spent == 2 else 0.0)) * s))
	var flash_name := "fx_%s_%d" % [prefix, index]
	var flash_art := assets.art(flash_name)
	var fw := size
	var fh := int(round(size * aspect))
	var front := Weapons.view_point(x, y, float(anchor.x), float(anchor.y), s)
	var fc := Vector2(roundf(front.x - 3.0 * s), roundf(front.y - 2.0 * s))
	# The flash adds its light to the picture instead of covering it.
	Weapons.Armory._blit_glow(
		frame,
		flash_art,
		fw,
		fh,
		int(fc.x) - fw / 2,
		int(fc.y) - fh / 2,
		int(255.0 * minf(1.0, flashes)),
		flash_name
	)
	if prefix in ["fire", "rocket", "forge"] and shot_age < .075:
		# Burning powder thrown ahead of the muzzle.
		var reach := (5.0 + shot_age * 170.0) * s
		for k in 7:
			var ang := -3.2 + k * .33 + float((last_spent * 3 + k * 5) % 7) * .06
			var far := reach * (.62 + .1 * float(k % 4))
			Weapons.Armory._line(
				frame,
				int(fc.x + cos(ang) * far * .55),
				int(fc.y + sin(ang) * far * .55),
				int(fc.x + cos(ang) * far),
				int(fc.y + sin(ang) * far),
				Color8(255, 220, 130) if k % 2 else Color8(255, 150, 60)
			)
	if i == Weapons.SHOTGUN and last_spent == 2:
		var twin_size := int(round(size * .76))
		var twin_name := "fx_%s_%d" % [prefix, mini(3, index + 1)]
		var twin := assets.art(twin_name)
		Weapons.Armory._blit_glow(
			frame,
			twin,
			twin_size,
			twin_size,
			int(fc.x + roundf(6.0 * s)) - twin_size / 2,
			int(fc.y + roundf(1.0 * s)) - twin_size / 2,
			int(255.0 * minf(1.0, flashes)),
			twin_name
		)


static func _rich(
	frame: PackedByteArray,
	assets: Assets,
	i: int,
	anchor: Vector3i,
	s: float,
	at: Vector2,
	shot_age: float,
	last_spent: int,
	aspect: float,
	flashes: float,
	count: int
) -> void:
	var look := String(Weapons.FLASH_ART[i])
	var grow := float(Weapons.FLASH_SIZE.get(i, 1.6))
	var step := mini(2, int(shot_age * 40.0))
	var shape := count % 2
	var base := (float(anchor.z) * 1.4 + (10.0 if last_spent == 2 else 0.0)) * s
	var fw := roundi(base * grow * [1.0, .9, .75][step])
	# The pictures carry their own shape: squashed only a little by the old aspect.
	var fh := roundi(fw * lerpf(1.0, aspect, .4))
	var front := Weapons.view_point(at.x, at.y, float(anchor.x), float(anchor.y), s)
	var fc := Vector2(roundf(front.x - 3.0 * s), roundf(front.y - 2.0 * s))
	var alpha := int(255.0 * minf(1.0, flashes))
	# A glow round it that lights what is behind: the older soft flash, larger.
	var halo_name := "fx_%s_%d" % ["energy" if look == "energy" else "fire", step]
	var hw := roundi(fw * 1.7)
	var hh := roundi(fh * 1.7)
	Weapons.Armory._blit_glow(
		frame,
		assets.art(halo_name),
		hw,
		hh,
		int(fc.x) - hw / 2,
		int(fc.y) - hh / 2,
		alpha * 3 / 4,
		halo_name
	)
	var name := "fx_mf_%s_%d_%d" % [look, shape, step]
	Weapons.Armory._blit_scaled(
		frame, assets.art(name), fw, fh, int(fc.x) - fw / 2, int(fc.y) - fh / 2, alpha, name
	)
	if i == Weapons.SHOTGUN and last_spent == 2:
		# Both barrels: the second flash beside the first, a beat behind.
		var twin := "fx_mf_%s_%d_%d" % [look, 1 - shape, mini(2, step + 1)]
		var tw := roundi(fw * .8)
		var th := roundi(fh * .8)
		Weapons.Armory._blit_scaled(
			frame,
			assets.art(twin),
			tw,
			th,
			int(fc.x + roundf(7.0 * s)) - tw / 2,
			int(fc.y + roundf(1.0 * s)) - th / 2,
			alpha,
			twin
		)
