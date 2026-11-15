## Paint the weather's marks into assets/art: what feet, hooves, claws and
## tyres leave in the mud (features/weather.gd prints, effects.cfg [mud]).
##
##   godot --headless --path godot --script res://tools/art/build_weather_art.gd [-- out=<dir>]
##
##   mark_boot_mud   a boot print pressed into mud: sole and heel, wet and dark
##                    in the hollow, a lighter ridge of squeezed-up mud round it
##   mark_hoof_mud    a cloven hoof (hog, cow, mule)
##   mark_claw_mud    a chicken's three toes and its spur
##   mark_tyre_mud    a stretch of tyre track: two bands of tread lugs
## Drawn at four times their size and shrunk, a hard alpha edge, then
## digitized to the palette. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const U := 4
const HOLLOW := Color8(46, 32, 22)
const WET := Color8(70, 52, 36)
const RIDGE := Color8(150, 116, 74)
const SHINE := Color8(150, 140, 128)


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	_finish(boot(), 24).save(out.path_join("mark_boot_mud.png"))
	_finish(hoof(), 20).save(out.path_join("mark_hoof_mud.png"))
	_finish(claw(), 18).save(out.path_join("mark_claw_mud.png"))
	_finish(tyre(), 40).save(out.path_join("mark_tyre_mud.png"))
	print("weather art: 4 marks in %s" % out)
	quit()


## Shrink a sheet drawn U times over to `size` square, harden its edge,
## commit it to the palette.
func _finish(im: Paint.Sheet, size: int) -> Paint.Sheet:
	var small := im.resized(size, size)
	for i in size * size:
		small.data[i * 4 + 3] = 230 if small.data[i * 4 + 3] >= 110 else 0
	return Paint.digitize(small, 4.0)


## A boot print: the ridge of mud it pushed up, the sole's hollow with its
## tread bars, the heel, a shine of water standing in the toe.
func boot() -> Paint.Sheet:
	var s := float(24 * U)
	var im := Paint.Sheet.new(24 * U, 24 * U)
	Paint.ellipse(im, s * .26, s * .04, s * .74, s * .6, RIDGE)
	Paint.ellipse(im, s * .3, s * .6, s * .7, s * .96, RIDGE)
	Paint.ellipse(im, s * .31, s * .08, s * .69, s * .55, HOLLOW)
	Paint.ellipse(im, s * .35, s * .64, s * .65, s * .92, HOLLOW)
	for k in 5:
		var y := s * (.14 + k * .08)
		Paint.rect(im, s * .33, y, s * .67, y + U * 1.2, WET)
	Paint.ellipse(im, s * .4, s * .1, s * .52, s * .18, SHINE)
	return im


## A cloven hoof: two halves of a rounded print, the cleft between.
func hoof() -> Paint.Sheet:
	var s := float(20 * U)
	var im := Paint.Sheet.new(20 * U, 20 * U)
	Paint.ellipse(im, s * .14, s * .1, s * .86, s * .9, RIDGE)
	Paint.ellipse(im, s * .2, s * .16, s * .48, s * .84, HOLLOW)
	Paint.ellipse(im, s * .52, s * .16, s * .8, s * .84, HOLLOW)
	Paint.ellipse(im, s * .26, s * .22, s * .4, s * .4, WET)
	Paint.ellipse(im, s * .6, s * .22, s * .74, s * .4, WET)
	return im


## A chicken's foot: three toes forward, a spur back.
func claw() -> Paint.Sheet:
	var s := float(18 * U)
	var im := Paint.Sheet.new(18 * U, 18 * U)
	var heel := Vector2(s * .5, s * .66)
	for tip: Vector2 in [Vector2(.5, .06), Vector2(.18, .18), Vector2(.82, .18), Vector2(.5, .94)]:
		Paint.line2(im, heel.x, heel.y, s * tip.x, s * tip.y, RIDGE, U * 3.2)
	for tip: Vector2 in [Vector2(.5, .08), Vector2(.2, .2), Vector2(.8, .2), Vector2(.5, .9)]:
		Paint.line2(im, heel.x, heel.y, s * tip.x, s * tip.y, HOLLOW, U * 1.8)
	Paint.ellipse(im, heel.x - U * 2, heel.y - U * 2, heel.x + U * 2, heel.y + U * 2, HOLLOW)
	return im


## A stretch of tyre track: two ruts of tread lugs, chevrons along them.
func tyre() -> Paint.Sheet:
	var s := float(40 * U)
	var im := Paint.Sheet.new(40 * U, 40 * U)
	for x0: float in [.06, .62]:
		Paint.rect(im, s * x0, 0, s * (x0 + .32), s, RIDGE)
		Paint.rect(im, s * (x0 + .02), 0, s * (x0 + .3), s, HOLLOW)
		for k in 8:
			var y := s * (k / 8.0 + .03)
			Paint.line2(im, s * (x0 + .04), y, s * (x0 + .16), y + s * .05, WET, U * 2.0)
			Paint.line2(im, s * (x0 + .16), y + s * .05, s * (x0 + .28), y, WET, U * 2.0)
	return im
