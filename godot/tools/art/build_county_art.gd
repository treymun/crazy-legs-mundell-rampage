## COUNTY RUN's XP (src/modes/county_orbs.gd): a crimped bottle cap with a
## star stamped in it, spinning, in three metals by how much XP the pile is
## worth (county_xp_<tier>_<frame>: 0 copper, 1 silver, 2 gold; frames 0..3
## turn it edge-on and back). Drawn small, hard edged, few colours, so it
## sits with the game's pickups; the game draws it full bright.
##
##   godot --headless --path godot --script res://tools/art/build_county_art.gd [-- out=<dir>]
##
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SIZE := 16
## [light, mid, dark, star] of each metal.
const METALS := [
	[[250, 178, 120], [206, 112, 56], [110, 52, 24], [255, 226, 170]],
	[[240, 244, 248], [170, 180, 192], [86, 92, 104], [255, 255, 255]],
	[[255, 236, 132], [236, 178, 40], [128, 82, 14], [255, 252, 210]],
]
## How wide the cap shows in each frame (a turn about its upright axis).
const TURN := [1.0, .62, .18, .62]


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	for tier in METALS.size():
		for frame in TURN.size():
			_cap(METALS[tier], float(TURN[frame]), frame).save(
				out.path_join("county_xp_%d_%d.png" % [tier, frame])
			)
			count += 1
	print("county art: %d written to %s" % [count, out])
	quit()


static func _c(rgb: Array, k := 1.0) -> Color:
	return Paint.rgb(float(rgb[0]) * k, float(rgb[1]) * k, float(rgb[2]) * k)


## One frame: the cap `wide` of its full width (1 face on, near 0 edge on).
static func _cap(metal: Array, wide: float, frame: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(SIZE, SIZE)
	var mid := SIZE / 2.0
	var r := 7.0
	var half := maxf(1.2, r * wide)
	# The crimped rim: teeth round the edge, darker than the face.
	for k in 21:
		var a := k * TAU / 21.0
		var x := mid + cos(a) * half
		var y := mid + sin(a) * r
		Paint.ellipse(s, x - 1.1, y - 1.1, x + 1.1, y + 1.1, _c(metal[2]))
	Paint.ellipse(s, mid - half, mid - r, mid + half, mid + r, _c(metal[1]))
	if wide > .4:
		# The face, lit from the top left, and the star stamped in it.
		Paint.ellipse(
			s, mid - half + 1.0, mid - r + 1.0, mid + half - 1.5, mid + r - 1.5, _c(metal[0])
		)
		Paint.ellipse(
			s, mid - half + 2.0, mid - r + 2.0, mid + half - 1.0, mid + r - 1.0, _c(metal[1])
		)
		var star := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			var reach := 3.6 if k % 2 == 0 else 1.5
			star.append(Vector2(mid + cos(a) * reach * wide, mid + sin(a) * reach))
		Paint.polygon(s, star, _c(metal[3]))
	else:
		# Edge on: a bright line down the crimp.
		Paint.line2(s, mid, mid - r + 1.0, mid, mid + r - 1.0, _c(metal[0]))
	# A glint that moves as it turns.
	var gx := mid - half * .45 + frame * .6
	Paint.point(s, gx, mid - r * .55, Color(1, 1, 1))
	return s
