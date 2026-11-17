## Draw the small pictures of the county events (content pass 8,
## src/features/county_events.gd):
##
##   event_lantern     a hurricane lantern as a hand carries it in a blackout
##                     (src/event_dark.gd): a tin font and cap, a wire guard
##                     round a smoky glass globe, the flame burning inside, a
##                     bail handle over the top
##
##   godot --headless --path godot --script res://tools/art/build_event_art.gd [-- out=<dir>]
##
## Writes them to assets/art, drawn four times over and shrunk, committed to
## the palette (paint.gd digitize). Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SS := 4


func _init() -> void:
	var art := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(art)
	var made := lantern()
	made.save(art + "/event_lantern.png")
	print("event art: event_lantern")
	quit()


## A filled ellipse on sheet s (centre, radii), colour c.
func _oval(s: Paint.Sheet, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + .5 - cx) / rx
			var dy := (y + .5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				s.put(x, y, c)


func _rect(s: Paint.Sheet, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	for y in range(int(y0), int(y1)):
		for x in range(int(x0), int(x1)):
			s.put(x, y, c)


func lantern() -> Paint.Sheet:
	var w := 14 * SS
	var h := 22 * SS
	var s := Paint.Sheet.new(w, h)
	var mid := w * .5
	var tin := Color(.42, .30, .2)
	var tin_hi := Color(.62, .46, .3)
	var tin_lo := Color(.22, .15, .1)
	var wire := Color(.16, .12, .1)
	# the bail handle over the top
	for a in range(0, 181, 2):
		var t := deg_to_rad(float(a))
		_oval(s, mid + cos(t) * 5.0 * SS, 4.0 * SS - sin(t) * 3.2 * SS, .5 * SS, .5 * SS, wire)
	# the cap: a tin cone with its vent
	for y in range(int(4.0 * SS), int(7.0 * SS)):
		var k := (y - 4.0 * SS) / (3.0 * SS)
		var half := (1.6 + 3.2 * k) * SS
		_rect(s, mid - half, y, mid + half, y + 1, tin.lerp(tin_hi, .3 * (1.0 - k)))
	_rect(s, mid - 1.2 * SS, 3.0 * SS, mid + 1.2 * SS, 4.2 * SS, tin_lo)
	# the globe: smoky glass, the light strongest round the flame
	_oval(s, mid, 11.5 * SS, 4.0 * SS, 4.6 * SS, Color(.86, .62, .3))
	_oval(s, mid, 12.0 * SS, 3.0 * SS, 3.6 * SS, Color(.98, .78, .42))
	# the flame
	_oval(s, mid, 12.6 * SS, 1.2 * SS, 2.2 * SS, Color(1.0, .92, .62))
	_oval(s, mid, 13.2 * SS, .7 * SS, 1.2 * SS, Color(1.0, 1.0, .86))
	# soot at the globe's top, a glint down its side
	_oval(s, mid, 8.0 * SS, 3.0 * SS, 1.0 * SS, Color(.44, .3, .18))
	_rect(s, mid - 2.6 * SS, 10.0 * SS, mid - 1.9 * SS, 13.5 * SS, Color(1.0, .95, .8))
	# the wire guard: three uprights and a band
	for x: float in [-3.6, 0.0, 3.6]:
		_rect(s, mid + x * SS - .4 * SS, 7.0 * SS, mid + x * SS + .4 * SS, 16.4 * SS, wire)
	_rect(s, mid - 4.2 * SS, 11.2 * SS, mid + 4.2 * SS, 11.9 * SS, wire)
	# the font: a squat tin drum, the wick's knob
	_rect(s, mid - 4.6 * SS, 16.0 * SS, mid + 4.6 * SS, 21.0 * SS, tin)
	_rect(s, mid - 4.6 * SS, 16.0 * SS, mid + 4.6 * SS, 16.8 * SS, tin_hi)
	_rect(s, mid - 4.6 * SS, 20.2 * SS, mid + 4.6 * SS, 21.0 * SS, tin_lo)
	_rect(s, mid + 4.4 * SS, 17.4 * SS, mid + 5.8 * SS, 18.6 * SS, tin_lo)
	var small := s.resized(14, 22)
	return Paint.digitize(small, 6.0)
