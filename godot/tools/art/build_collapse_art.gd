## Paint the big breaks' effects (features/set_pieces.gd, src/set_piece_wreck.gd)
## into assets/art: hard edged, few colours, committed to the VGA palette like
## build_gun_fx_art.gd's smoke.
##
##   godot --headless --path godot --script res://tools/art/build_collapse_art.gd [-- out=<dir>]
##
##   fx_barndust_N (4)   the dust a barn throws coming down: a low, lumpy,
##                       near-solid billow of dry dirt and hay dust that rolls
##                       out along the ground
##   fx_gush_N (4)       a water tower's tank bursting: a fan of water jets
##                       and spray thrown up and out, foam at the crest
##   fx_gasjet_N (3)     gasoline spurting from a holed pipe or pump: a thin
##                       jet arcing over, drops falling off it
## Then run tools/pack_assets.gd. out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const DUST := [
	Color8(86, 74, 60),
	Color8(108, 94, 76),
	Color8(130, 114, 94),
	Color8(152, 136, 114),
	Color8(176, 160, 136),
	Color8(198, 184, 160),
]
const WATER := [
	Color8(58, 92, 118),
	Color8(92, 132, 158),
	Color8(134, 172, 192),
	Color8(182, 210, 220),
	Color8(226, 240, 244),
	Color8(255, 255, 255),
]
const GAS := [
	Color8(128, 98, 44),
	Color8(170, 140, 70),
	Color8(210, 188, 118),
	Color8(238, 226, 170),
	Color8(255, 250, 226),
]

var out := ""
var count := 0


func _init() -> void:
	out = Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	for f in 4:
		_save(barndust(f), "fx_barndust_%d" % f)
		_save(gush(f), "fx_gush_%d" % f)
	for f in 3:
		_save(gasjet(f), "fx_gasjet_%d" % f)
	print("collapse art: %d pictures in %s" % [count, out])
	quit()


func _save(s: Paint.Sheet, name: String) -> void:
	Paint.digitize(s, 7.0).save(out.path_join(name + ".png"))
	count += 1


func _step(ramp: Array, v: float) -> Color:
	return ramp[clampi(int(v * ramp.size()), 0, ramp.size() - 1)]


## A dark rim one pixel round everything drawn: the cartoon edge of a sprite
## of the period.
func _rim(s: Paint.Sheet, c: Color) -> void:
	var edge: Array = []
	for y in s.h:
		for x in s.w:
			if s.alpha_at(x, y) != 0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < s.w and ny < s.h and s.alpha_at(nx, ny) == 255:
					edge.append(Vector2i(x, y))
					break
	for p: Vector2i in edge:
		s.put(p.x, p.y, c)


## A billow of barn dust: wider than tall, flat along its foot where it rolls
## on the ground, lumpy on top, lit from above; variant 3 is thinning out (a
## ragged edge with holes).
func barndust(variant: int) -> Paint.Sheet:
	var w := 64
	var h := 48
	var s := Paint.Sheet.new(w, h)
	var churn := Paint.cloud(64, 7300 + variant * 37, [4, 8, 16])
	var fine := Paint.cloud(64, 7500 + variant * 19, [8, 16, 32])
	var thin := .22 if variant == 3 else 0.0
	for y in h:
		for x in w:
			var dx := (x - (w - 1) / 2.0) / (w * .44)
			# Its middle low: the foot is flat, the top heaped.
			var dy := (y - h * .62) / (h * .5)
			if dy > 0.0:
				dy *= 1.9
			var r := sqrt(dx * dx + dy * dy * 1.25)
			if absf(dx) > 1.0:
				continue
			var i := (y % 64) * 64 + x % 64
			var body := 1.0 - r + (churn[i] - .5) * .6 + (fine[i] - .5) * .2 - thin - dx * dx * .3
			if body < .1:
				continue
			var light := clampf(.6 - dy * .4 + (fine[i] - .5) * .55, 0.0, .999)
			s.put(x, y, _step(DUST, light))
	_rim(s, Color8(92, 80, 66))
	return s


## A tank's water bursting out: jets fanning up and out from the foot, each
## tapering and breaking into drops at its tip, foam heaped where they leave.
func gush(variant: int) -> Paint.Sheet:
	var w := 72
	var h := 56
	var s := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9700 + variant * 13
	var foot := Vector2((w - 1) / 2.0, h - 4.0)
	var jets := 11 + variant
	for j in jets:
		var a := lerpf(-PI * .92, -PI * .08, (j + dice.randf_range(.2, .8)) / jets)
		var reach := dice.randf_range(.55, 1.0) * (h - 6.0) * (1.0 - .35 * absf(cos(a)))
		var thick := dice.randf_range(3.0, 4.6)
		var bend := dice.randf_range(.1, .3)
		var steps := int(reach * 1.4)
		for n in steps:
			var t := float(n) / steps
			var dir := Vector2(cos(a), sin(a))
			# Falling over at the tip.
			var p := foot + dir * reach * t + Vector2(0.0, bend * reach * t * t)
			var r := thick * (1.0 - t * .75)
			var tone := clampf(.95 - t * .45 + (1.0 - absf(cos(a))) * .1, 0.0, .999)
			if t > .8 and n % 3 != 0:
				continue
			for oy in range(-ceili(r), ceili(r) + 1):
				for ox in range(-ceili(r), ceili(r) + 1):
					if ox * ox + oy * oy <= r * r:
						var shade := tone - (.25 if ox > r * .3 else 0.0)
						s.put(int(p.x) + ox, int(p.y) + oy, _step(WATER, shade))
		# Drops off the tip.
		var tip := foot + Vector2(cos(a), sin(a)) * reach * 1.05
		for d in 3:
			var q := (
				tip + Vector2(dice.randf_range(-3.0, 3.0), dice.randf_range(-2.0, 4.0) + d * 2.5)
			)
			s.put(int(q.x), int(q.y), WATER[4])
			s.put(int(q.x) + 1, int(q.y), WATER[3])
	# The foam heaped at the foot.
	var churn := Paint.cloud(64, 9900 + variant * 7, [4, 8])
	for y in range(h - 14, h):
		for x in w:
			var dx := (x - foot.x) / (w * .42)
			var dy := (y - (h - 2.0)) / 9.0
			var body := 1.0 - (dx * dx + dy * dy) + (churn[(y % 64) * 64 + x % 64] - .5) * .7
			var grain: float = churn[((y * 3) % 64) * 64 + (x * 2) % 64]
			if body > .15:
				var lit := clampf(.35 - dy * .35 + (grain - .5) * .9, 0.0, .999)
				s.put(x, y, _step(WATER, lit))
	_rim(s, Color8(48, 76, 98))
	return s


## Gasoline spurting from a hole: a thin jet leaving low on the left, arcing
## up and over to the right, drops falling from it; each frame its own wobble.
func gasjet(frame: int) -> Paint.Sheet:
	var w := 28
	var h := 40
	var s := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 4400 + frame * 11
	var lift := 1.0 + frame * .12
	var steps := 70
	var last := Vector2.ZERO
	for n in steps:
		var t := float(n) / steps
		var x := 3.0 + t * (w - 8.0)
		var y := h - 4.0 - (h - 10.0) * lift * 4.0 * t * (1.0 - t) * .95
		y += sin(t * 9.0 + frame * 2.1) * .8
		var r := 1.6 - t * .9
		if t > .7 and n % 4 >= 2:
			continue
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				if ox * ox + oy * oy <= r * r + .3:
					s.put(int(x) + ox, int(y) + oy, _step(GAS, .85 - t * .4 + oy * .08))
		last = Vector2(x, y)
	for d in 5:
		var q := (
			last + Vector2(dice.randf_range(-3.0, 2.0), 3.0 + d * 2.6 + dice.randf_range(0.0, 1.5))
		)
		if q.y < h - 1:
			s.put(int(q.x), int(q.y), GAS[2])
			s.put(int(q.x), int(q.y) + 1, GAS[1])
	_rim(s, Color8(92, 70, 32))
	return s
