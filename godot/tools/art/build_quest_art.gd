## Paint the things the objective is done at into assets/art (and the locked
## gate's barricade into assets/tiles): every chapter's control boxes, relays,
## the brake, the midway bell, the exit signs, the lettered signs that switch
## when a station is done, the keys and the PA patch lead. The same names the
## levels already use, so every chapter (and any new one) picks them up.
##
##   godot --headless --path godot --script res://tools/art/build_quest_art.gd [-- out=<dir>]
##
## One look for "still to do" and "done" across them all: still to do, a big
## warning lamp lit (the graphics-card view adds its blinking glow from
## effects.cfg), the lever up, the hazard plate bright; done, that lamp dark,
## the green pilot on, the lever thrown and a red LOCKED OUT tag hung on it.
## An exit is chained and padlocked under a red lamp until the way is clear,
## then lit green. Keys and the lead wear a bright cloth tag, so they read on
## the dirt. Each is painted at twice its size, shrunk, given a hard edge and
## committed to the game's palette. Seeded: a rerun writes the same files.
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

const INK := Color(.96, .9, .74)
const SOOT := Color(.07, .05, .04)
const HAZARD := Color(.93, .72, .12)
const LAMP_RED := Color(1.0, .34, .16)
const LAMP_AMBER := Color(1.0, .7, .2)
const PILOT_GREEN := Color(.36, 1.0, .42)

var rng := RandomNumberGenerator.new()


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var tiles := Paint.repo("assets/tiles") if out == Paint.repo("assets/art") else out
	var made := 0
	var mill := Color(.27, .42, .40)
	var fair := Color(.62, .17, .13)
	var boxes := [
		["mill_control", "CONTROL", mill, "lever"],
		["mill_relay", "RELAY", mill, "relay"],
		["fair_control", "POWER", fair, "lever"],
		["fair_relay", "RELAY", fair, "relay"],
	]
	for spec: Array in boxes:
		for done in [false, true]:
			rng.seed = hash(String(spec[0]))
			var s := console(String(spec[1]), spec[2], String(spec[3]), done)
			_save(s, out, String(spec[0]) + ("_on" if done else "_off"))
			made += 1
	for done in [false, true]:
		rng.seed = 77
		_save(brake(done), out, "mill_brake" + ("_on" if done else "_off"))
		rng.seed = 78
		_save(bell(done), out, "fair_bell" + ("_on" if done else "_off"))
		made += 2
	for name in ["mill_exit", "fair_exit"]:
		for open in [false, true]:
			rng.seed = hash(name)
			_save(exit_sign(open, name == "fair_exit"), out, name + ("_on" if open else "_off"))
			made += 1
	# [name, colour, still-to-do words, done words]
	var signs := [
		[
			"wing_town_hatch",
			Color(.38, .36, .22),
			["FEED HATCH", "SLIDE THE BOLT"],
			["FEED HATCH", "BOLT FREE"]
		],
		[
			"wing_town_pen",
			Color(.46, .26, .16),
			["FEED AND BOARD", "BRING YOUR OWN BUCKET"],
			["BESSIE'S HOME", "BACK TO REGULAR RATIONS"]
		],
		[
			"wing_fair_pa",
			Color(.42, .18, .22),
			["BACKSTAGE PA", "PATCH JACK B"],
			["PA OFF AIR", "LAST SHOW CANCELLED"]
		],
		[
			"wing_mill_belt",
			Color(.30, .36, .30),
			["KILN BELT", "HIT THE RELEASE"],
			["BELT CUT", "KILN LOCKED OUT"]
		],
		[
			"wing_quarry_latch",
			Color(.36, .34, .24),
			["WASH CARTS", "LIFT THE LATCH"],
			["WASH CARTS", "WAY OPEN"]
		],
		[
			"wing_quarry_condenser",
			Color(.46, .28, .16),
			["COPPER RECOVERY", "DIVERT BEFORE BOTTLING"],
			["FLOW DIVERTED", "COOLING LINE / NO TAPS"]
		],
	]
	for spec: Array in signs:
		for done in [false, true]:
			rng.seed = hash(String(spec[0]))
			var words: Array = spec[3] if done else spec[2]
			_save(
				status_sign(spec[1], String(words[0]), String(words[1]), done),
				out,
				String(spec[0]) + ("_on" if done else "_off")
			)
			made += 1
	rng.seed = 11
	_save(key_item(Color(.86, .62, .2), Color(.84, .12, .1)), out, "item_key_brass")
	rng.seed = 12
	_save(key_item(Color(.66, .7, .74), Color(.95, .78, .12)), out, "item_key_steel")
	rng.seed = 13
	_save(patch_lead(), out, "item_pa_patch")
	rng.seed = 14
	_save(barricade(), tiles, "route_closed")
	made += 4
	print("quest art: %d pictures written to %s (route_closed to %s)" % [made, out, tiles])
	quit()


func _save(s: Paint.Sheet, folder: String, name: String) -> void:
	s.save(folder.path_join(name + ".png"))


## Twice-size painting -> game size: resampled, a hard edge, the palette.
func finish(big: Paint.Sheet, w: int, h: int, dither := 7.0) -> Paint.Sheet:
	var small := big.resized(w, h)
	for i in w * h:
		small.data[i * 4 + 3] = 255 if small.data[i * 4 + 3] >= 120 else 0
	return Paint.digitize(small, dither)


# ------------------------------------------------------------------ surfaces


## Painted steel: a flat coat gone patchy, darker at the edges, grime running
## down, scratched; `base` its colour.
func steel(s: Paint.Sheet, x0: int, y0: int, x1: int, y1: int, base: Color) -> void:
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), (x1 - x0 + 1) * (y1 - y0 + 1), .045)
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var u := float(x - x0) / bw
			var v := float(y - y0) / bh
			var edge := minf(minf(x - x0, x1 - x), minf(y - y0, y1 - y)) / 10.0
			var b := blot[int(v * 63) * 64 + int(u * 63)]
			var rust := clampf(b * 1.4 - clampf(edge, 0, 1) * .7 - .25 + v * .25, 0, 1)
			var c := base.lerp(Color(.42, .22, .11), rust * .8)
			var f := 1.0 + grit[(y - y0) * bw + (x - x0)] - (1.0 - clampf(edge, 0, 1)) * .18
			f *= 1.06 - v * .16
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	# Grime streaks down from the top.
	for _k in bw / 9:
		var sx := rng.randi_range(x0 + 4, x1 - 4)
		var length := rng.randi_range(bh / 5, bh / 2)
		for t in length:
			var o: int = ((y0 + t) * s.w + sx) * 4
			for k in 3:
				s.data[o + k] = int(s.data[o + k] * (.78 + .22 * float(t) / length))


## Planks laid across, as the town paints them.
func planks(s: Paint.Sheet, x0: int, y0: int, x1: int, y1: int, base: Color, plank := 14) -> void:
	var grain := Paint.noise(rng.randi(), (x1 - x0 + 1) * (y1 - y0 + 1), .05)
	var bw := x1 - x0 + 1
	for y in range(y0, y1 + 1):
		var row := (y - y0) / plank
		var tone := 1.0 + sin(row * 2.3) * .07
		var seam := (y - y0) % plank == 0
		for x in range(x0, x1 + 1):
			var f := tone + grain[(y - y0) * bw + (x - x0)] + sin(x * .11 + row * 1.7) * .035
			if seam:
				f *= .5
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))


## Yellow and black diagonal stripes in the box.
func hazard(s: Paint.Sheet, x0: int, y0: int, x1: int, y1: int, period := 16) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var band := posmod(x + y, period) < period / 2
			var c := HAZARD if band else Color(.12, .1, .08)
			var f := .9 + .1 * sin(x * .7 + y * 1.3)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))


func rivet(s: Paint.Sheet, x: int, y: int) -> void:
	Paint.ellipse(s, x - 2, y - 2, x + 2, y + 2, Color(.16, .14, .12))
	Paint.ellipse(s, x - 2, y - 2, x + 1, y + 1, Color(.74, .7, .6))
	Paint.point(s, x - 1, y - 1, Color(.95, .92, .82))


## A warning lamp: a glass dome in a wire cage on a black base. Lit, a hot
## core and a hard bright ring; dark, smoky glass.
func lamp(s: Paint.Sheet, cx: int, cy: int, r: int, colour: Color, lit: bool) -> void:
	Paint.rect(s, cx - r - 3, cy, cx + r + 3, cy + r / 2 + 3, SOOT)
	Paint.rect(s, cx - r - 3, cy, cx + r + 3, cy + 2, Color(.3, .28, .26))
	var glass := colour if lit else colour.darkened(.72)
	Paint.pieslice(s, cx - r, cy - r, cx + r, cy + r, 180, 360, glass)
	if lit:
		var hot := colour.lerp(Color(1, 1, .86), .65)
		Paint.pieslice(s, cx - r * .55, cy - r * .7, cx + r * .4, cy + r * .2, 180, 360, hot)
		Paint.ellipse(s, cx - r * .45, cy - r * .75, cx - r * .1, cy - r * .45, Color(1, 1, .95))
	else:
		Paint.ellipse(s, cx - r * .5, cy - r * .8, cx - r * .25, cy - r * .55, colour.darkened(.4))
	# The cage: wire hoops over the dome.
	var wire := Color(.1, .09, .08)
	Paint.arc(s, cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, 180, 360, wire, 2)
	for k in [-.5, 0.0, .5]:
		var x := cx + int(k * r)
		var top := cy - int(sqrt(maxf(0.0, 1.0 - k * k)) * r)
		Paint.rect(s, x - 1, top, x, cy, wire)


## Block letters (the game's own), `sx` wide and `sy` tall per glyph pixel,
## with a drop shadow, centred on cx. Returns the width drawn.
func letters(
	s: Paint.Sheet, text: String, cx: int, y: int, sx: int, sy: int, ink: Color, shadow := true
) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * sx
	width -= sx
	var left := cx - width / 2
	for pass_k in [1, 0] if shadow else [0]:
		var off: int = pass_k * maxi(2, sy / 2)
		var colour := Color(.05, .03, .02, .85) if pass_k == 1 else ink
		var at := left
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			var rows: Array = g[0]
			var gw: int = g[1]
			for r in rows.size():
				for bx in gw:
					if int(rows[r]) & (1 << (gw - 1 - bx)):
						for yy in sy:
							for xx in sx:
								_blend(s, at + bx * sx + xx + off, y + r * sy + yy + off, colour)
			at += (gw + 1) * sx
	return width


func text_width(text: String, sx: int) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * sx
	return width - sx


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	if s.data[o + 3] == 0:
		return
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - c.a) + c[k] * 255.0 * c.a)


## Chips where the paint came off and a few bullet holes.
func weather(s: Paint.Sheet, chips: int, holes: int) -> void:
	for _k in chips:
		var x := rng.randi_range(2, s.w - 3)
		var y := rng.randi_range(2, s.h - 3)
		for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var o := ((y + d.y) * s.w + x + d.x) * 4
			if s.data[o + 3] > 0:
				for k in 3:
					s.data[o + k] = int(s.data[o + k] * .7)
	for _k in holes:
		var x := rng.randi_range(8, s.w - 9)
		var y := rng.randi_range(8, s.h - 9)
		if s.alpha_at(x, y) == 0:
			continue
		Paint.ellipse(s, x - 2, y - 2, x + 2, y + 2, Color(.05, .04, .03))
		Paint.arc(s, x - 3, y - 3, x + 3, y + 3, 180, 300, Color(.7, .66, .58))


## The red tag a hand hangs on a thrown switch: LOCKED OUT.
func lockout_tag(s: Paint.Sheet, x: int, y: int) -> void:
	Paint.line2(s, x, y, x + 4, y + 14, Color(.85, .82, .7), 2)
	var top := y + 14
	Paint.polygon(
		s,
		PackedVector2Array(
			[
				Vector2(x - 8, top + 4),
				Vector2(x + 4, top),
				Vector2(x + 16, top + 4),
				Vector2(x + 16, top + 40),
				Vector2(x - 8, top + 40)
			]
		),
		Color(.82, .1, .07)
	)
	Paint.ellipse(s, x + 2, top + 3, x + 6, top + 7, Color(.9, .88, .8))
	Paint.rect(s, x - 6, top + 12, x + 14, top + 13, Color(.98, .92, .8))
	letters(s, "NO", x + 4, top + 16, 2, 2, Color(.98, .94, .84), false)
	letters(s, "GO", x + 4, top + 28, 2, 2, Color(.98, .94, .84), false)


# ------------------------------------------------------------------ the boxes


## A control box on legs: title plate, the warning lamp on its top, the
## mechanism (a knife lever, or the relay's fuse tubes and lever), a hazard
## plate, the pilot lights. 112 x 126.
func console(title: String, body: Color, kind: String, done: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(224, 252)
	var l := 12
	var r := 178
	var t := 44
	var b := 226
	var depth := 22
	var rise := 14
	# Legs and the conduit to the ground.
	Paint.rect(s, l + 10, b, l + 22, 251, Color(.14, .13, .12))
	Paint.rect(s, r - 22, b, r - 10, 251, Color(.14, .13, .12))
	if kind == "relay":
		Paint.line(
			s,
			PackedVector2Array(
				[Vector2(96, b), Vector2(96, 240), Vector2(150, 240), Vector2(150, 251)]
			),
			Color(.35, .22, .12),
			7
		)
	# Side and top faces in shade, the front lit.
	Paint.polygon(
		s,
		PackedVector2Array(
			[
				Vector2(r, t),
				Vector2(r + depth, t - rise),
				Vector2(r + depth, b - rise),
				Vector2(r, b)
			]
		),
		body.darkened(.55)
	)
	Paint.polygon(
		s,
		PackedVector2Array(
			[
				Vector2(l, t),
				Vector2(l + depth, t - rise),
				Vector2(r + depth, t - rise),
				Vector2(r, t)
			]
		),
		body.lightened(.12)
	)
	steel(s, l, t, r, b, body)
	Paint.outline(s, l, t, r, b, SOOT)
	Paint.outline(s, l + 1, t + 1, r - 1, b - 1, body.lightened(.3))
	# The big warning lamp on the top, lit while the job is still to do.
	lamp(s, l + 40, t - 6, 22, LAMP_RED if kind == "lever" else LAMP_AMBER, not done)
	# Title plate.
	Paint.rect(s, l + 12, t + 12, r - 12, t + 46, Color(.08, .07, .06))
	Paint.outline(s, l + 12, t + 12, r - 12, t + 46, body.lightened(.35))
	var sx := (
		5 if text_width(title, 5) < r - l - 34 else 4 if text_width(title, 4) < r - l - 30 else 3
	)
	letters(s, title, (l + r) / 2, t + 15, sx, 4, INK)
	if kind == "lever":
		_lever(s, (l + r) / 2, t + 104, done)
	else:
		_relay(s, l, r, t, done)
	# Hazard plate and the pilot lights under it.
	hazard(s, l + 10, b - 30, r - 10, b - 14)
	Paint.outline(s, l + 10, b - 30, r - 10, b - 14, SOOT)
	_pilot(s, l + 20, b - 6, LAMP_RED, not done)
	_pilot(s, r - 20, b - 6, PILOT_GREEN, done)
	for p in [
		Vector2i(l + 6, t + 6),
		Vector2i(r - 6, t + 6),
		Vector2i(l + 6, b - 38),
		Vector2i(r - 6, b - 38)
	]:
		rivet(s, p.x, p.y)
	weather(s, 120, 3)
	return finish(s, 112, 126)


func _pilot(s: Paint.Sheet, cx: int, cy: int, colour: Color, lit: bool) -> void:
	Paint.ellipse(s, cx - 5, cy - 5, cx + 5, cy + 5, SOOT)
	Paint.ellipse(s, cx - 3, cy - 3, cx + 3, cy + 3, colour if lit else colour.darkened(.75))
	if lit:
		Paint.point(s, cx - 1, cy - 1, Color(1, 1, .9))


## A knife lever in a slot: up (ON, live) or thrown down (OFF) with the tag.
func _lever(s: Paint.Sheet, cx: int, cy: int, done: bool) -> void:
	Paint.rect(s, cx - 34, cy - 44, cx + 34, cy + 44, Color(.1, .09, .08))
	Paint.outline(s, cx - 34, cy - 44, cx + 34, cy + 44, Color(.5, .46, .4))
	letters(s, "ON", cx - 50, cy - 40, 2, 2, INK if not done else INK.darkened(.5), false)
	letters(s, "OFF", cx - 52, cy + 28, 2, 2, INK if done else INK.darkened(.5), false)
	# The slot and the hub.
	Paint.rect(s, cx - 5, cy - 38, cx + 5, cy + 38, Color(.03, .03, .03))
	var tip := Vector2(cx + 6, cy - 36) if not done else Vector2(cx + 6, cy + 36)
	Paint.line2(s, cx, cy, tip.x, tip.y, Color(.62, .6, .56), 9)
	Paint.line2(s, cx - 2, cy, tip.x - 2, tip.y, Color(.85, .84, .8), 3)
	# The grip: hazard yellow and black, a red knob on the end.
	var grip := Vector2(tip.x + (14 if not done else 14), tip.y)
	Paint.line2(s, tip.x - 16, tip.y, grip.x, grip.y, HAZARD, 12)
	for k in 3:
		var x := tip.x - 12 + k * 9
		Paint.rect(s, x, tip.y - 6, x + 3, tip.y + 6, Color(.12, .1, .08))
	Paint.ellipse(s, grip.x - 2, grip.y - 9, grip.x + 16, grip.y + 9, Color(.78, .1, .06))
	Paint.ellipse(s, grip.x + 2, grip.y - 6, grip.x + 8, grip.y - 1, Color(1, .6, .5))
	Paint.ellipse(s, cx - 9, cy - 9, cx + 9, cy + 9, Color(.25, .24, .22))
	rivet(s, cx, cy)
	if done:
		lockout_tag(s, cx + 40, cy - 24)


## The relay: three fuse tubes glowing while it runs, dark once it is shut
## down, and the lever that does it.
func _relay(s: Paint.Sheet, l: int, r: int, t: int, done: bool) -> void:
	for k in 3:
		var x := l + 22 + k * 30
		Paint.rect(s, x, t + 58, x + 18, t + 128, Color(.06, .05, .05))
		Paint.rect(
			s, x + 3, t + 62, x + 15, t + 124, Color(.2, .18, .14) if done else Color(.95, .5, .14)
		)
		if not done:
			Paint.rect(s, x + 7, t + 64, x + 11, t + 122, Color(1, .92, .62))
		Paint.rect(s, x - 2, t + 56, x + 20, t + 60, Color(.7, .6, .4))
		Paint.rect(s, x - 2, t + 122, x + 20, t + 126, Color(.7, .6, .4))
	var cx := r - 30
	var cy := t + 92
	Paint.rect(s, cx - 12, cy - 38, cx + 12, cy + 38, Color(.08, .07, .06))
	var tip := Vector2(cx, cy - 32) if not done else Vector2(cx, cy + 32)
	Paint.line2(s, cx, cy, tip.x, tip.y, Color(.62, .6, .56), 8)
	Paint.line2(s, tip.x - 12, tip.y, tip.x + 12, tip.y, HAZARD, 10)
	Paint.ellipse(s, tip.x + 8, tip.y - 7, tip.x + 20, tip.y + 7, Color(.78, .1, .06))
	rivet(s, cx, cy)
	if done:
		lockout_tag(s, cx - 24, cy - 34)


## The log carriage brake: a long lever on a toothed quadrant in a plank frame.
## Still to do: hauled back, BRAKE ON in red; done: forward, OFF, tagged.
func brake(done: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(204, 236)
	planks(s, 8, 18, 196, 236, Color(.46, .32, .2), 16)
	Paint.outline(s, 8, 18, 196, 235, SOOT)
	Paint.rect(s, 8, 18, 196, 26, Color(.3, .2, .12))
	lamp(s, 46, 16, 20, LAMP_RED, not done)
	# The plate behind the lever.
	steel(s, 30, 40, 174, 196, Color(.3, .36, .34))
	Paint.outline(s, 30, 40, 174, 196, SOOT)
	letters(s, "BRAKE", 102, 48, 4, 4, INK)
	letters(s, "ON" if not done else "OFF", 140, 84, 3, 3, LAMP_RED if not done else PILOT_GREEN)
	# The quadrant: an arc of teeth round the pivot.
	var px := 80
	var py := 176
	Paint.arc(s, px - 70, py - 70, px + 70, py + 70, 200, 340, Color(.55, .52, .46), 7)
	for k in 9:
		var a := deg_to_rad(205.0 + k * 16.0)
		Paint.point(s, px + cos(a) * 74, py + sin(a) * 74, Color(.2, .18, .16))
		Paint.point(s, px + cos(a) * 75, py + sin(a) * 75, Color(.2, .18, .16))
	var ang := deg_to_rad(230.0 if not done else 320.0)
	var tip := Vector2(px + cos(ang) * 96, py + sin(ang) * 96)
	Paint.line2(s, px, py, tip.x, tip.y, Color(.6, .58, .54), 10)
	Paint.line2(s, px - 2, py - 1, tip.x - 2, tip.y - 1, Color(.86, .84, .8), 3)
	Paint.ellipse(s, tip.x - 10, tip.y - 10, tip.x + 10, tip.y + 10, Color(.78, .1, .06))
	Paint.ellipse(s, tip.x - 5, tip.y - 7, tip.x, tip.y - 2, Color(1, .6, .5))
	Paint.ellipse(s, px - 12, py - 12, px + 12, py + 12, Color(.2, .19, .18))
	rivet(s, px, py)
	hazard(s, 30, 204, 174, 222)
	Paint.outline(s, 30, 204, 174, 222, SOOT)
	if done:
		lockout_tag(s, int(tip.x) - 6, int(tip.y) + 6)
	weather(s, 110, 4)
	return finish(s, 102, 118)


## The midway bell on its board, a pull rope with a striped handle. Still to
## ring: the RING ME lamp lit and the bell polished; rung: lamp out, the bell
## swung over, a blue ribbon pinned up.
func bell(done: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(204, 236)
	planks(s, 14, 18, 190, 220, Color(.62, .2, .14), 18)
	Paint.outline(s, 14, 18, 190, 220, SOOT)
	Paint.rect(s, 18, 22, 186, 26, Color(.95, .82, .5))
	lamp(s, 102, 16, 20, LAMP_AMBER, not done)
	Paint.rect(s, 30, 34, 174, 60, Color(.1, .07, .06))
	letters(s, "RING" if not done else "RUNG", 102, 37, 5, 3, Color(.98, .84, .4))
	# The bracket and the bell.
	Paint.rect(s, 60, 70, 144, 76, Color(.2, .18, .16))
	var swing := 0.0 if not done else .35
	var cx := 102.0
	var top := 78.0
	var pts := PackedVector2Array()
	for p in [
		Vector2(-12, 0),
		Vector2(12, 0),
		Vector2(20, 30),
		Vector2(26, 62),
		Vector2(40, 74),
		Vector2(-40, 74),
		Vector2(-26, 62),
		Vector2(-20, 30)
	]:
		pts.append(Vector2(cx, top) + p.rotated(swing))
	var brass := Color(.86, .64, .24) if not done else Color(.64, .46, .2)
	Paint.polygon(s, pts, brass)
	var shine := PackedVector2Array()
	for p in [Vector2(-8, 6), Vector2(-2, 6), Vector2(-4, 60), Vector2(-14, 60)]:
		shine.append(Vector2(cx, top) + p.rotated(swing))
	Paint.polygon(s, shine, brass.lightened(.45))
	var lip := Vector2(cx, top) + Vector2(0, 74).rotated(swing)
	Paint.ellipse(s, lip.x - 40, lip.y - 5, lip.x + 40, lip.y + 5, brass.darkened(.35))
	# The rope down to its handle.
	var clapper := Vector2(cx, top) + Vector2(0, 80).rotated(swing * .5)
	Paint.line2(s, clapper.x, clapper.y, 102, 196, Color(.86, .8, .62), 4)
	Paint.rect(s, 94, 190, 110, 216, Color(.9, .88, .82))
	for k in 3:
		Paint.rect(s, 94, 192 + k * 8, 110, 195 + k * 8, Color(.8, .1, .08))
	if done:
		# A blue ribbon: the bell was rung.
		Paint.ellipse(s, 146, 96, 172, 122, Color(.18, .32, .78))
		Paint.ellipse(s, 152, 102, 166, 116, Color(.95, .84, .4))
		Paint.polygon(
			s,
			PackedVector2Array(
				[Vector2(150, 118), Vector2(158, 118), Vector2(152, 146), Vector2(144, 142)]
			),
			Color(.18, .32, .78)
		)
		Paint.polygon(
			s,
			PackedVector2Array(
				[Vector2(160, 118), Vector2(168, 118), Vector2(174, 142), Vector2(166, 146)]
			),
			Color(.18, .32, .78)
		)
	for p in [Vector2i(20, 30), Vector2i(184, 30), Vector2i(20, 212), Vector2i(184, 212)]:
		rivet(s, p.x, p.y)
	weather(s, 90, 3)
	return finish(s, 102, 118)


# --------------------------------------------------------------------- signs


## The way out. Locked: a dark board, chained and padlocked, the red lamp
## lit, NOT YET. Open: green tin, its bulbs lit, GIT ON OUT and an arrow.
func exit_sign(open: bool, fair: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(352, 134)
	if open:
		steel(s, 4, 4, 347, 129, Color(.16, .46, .24))
	else:
		planks(s, 4, 4, 347, 129, Color(.42, .16, .12) if fair else Color(.38, .2, .14), 18)
	Paint.outline(s, 4, 4, 347, 129, SOOT)
	Paint.outline(s, 8, 8, 343, 125, Color(.86, .78, .56) if open else Color(.52, .38, .28))
	lamp(s, 40, 54, 20, PILOT_GREEN if open else LAMP_RED, true)
	if not open:
		# The chain slung across behind the lettering, link by link.
		for k in 21:
			var x := 72 + k * 13
			var y := 30 + int(absf(k - 10) * -1.6) + 16 + (k % 2) * 2
			var c := Color(.62, .6, .56) if k % 2 == 0 else Color(.42, .4, .38)
			Paint.arc(s, x - 8, y - 5, x + 8, y + 5, 0, 360, c, 3)
	letters(s, "EXIT", 196, 16, 9, 9, INK if open else Color(.86, .8, .7))
	if open:
		letters(s, "GIT ON OUT >", 196, 96, 3, 3, Color(1, .92, .5))
		# A bulb border, all of them lit.
		for x in range(16, 340, 14):
			for y in [12, 121]:
				Paint.ellipse(s, x - 3, y - 3, x + 3, y + 3, Color(1, .9, .55))
	else:
		letters(s, "NOT YET", 196, 96, 3, 3, Color(.95, .7, .5))
		# The padlock hanging off the chain's right end.
		Paint.arc(s, 310, 40, 328, 64, 180, 360, Color(.6, .58, .54), 4)
		Paint.rounded_rect(s, 304, 52, 334, 82, 4, Color(.82, .62, .22))
		Paint.rect(s, 317, 60, 321, 72, Color(.1, .08, .06))
	for p in [Vector2i(14, 14), Vector2i(337, 14), Vector2i(14, 119), Vector2i(337, 119)]:
		rivet(s, p.x, p.y)
	weather(s, 160, 4)
	return finish(s, 176, 67)


## A painted status sign: its words, and a lamp on the left (amber while the
## job is still to do, green once done).
func status_sign(base: Color, title: String, under: String, done: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(352, 134)
	planks(s, 4, 4, 347, 129, base if not done else base.lerp(Color(.22, .34, .22), .45), 16)
	Paint.outline(s, 4, 4, 347, 129, SOOT)
	Paint.outline(s, 8, 8, 343, 125, Color(.82, .72, .5))
	lamp(s, 36, 70, 18, PILOT_GREEN if done else LAMP_AMBER, true)
	var room := 262
	var sx := 4
	while sx > 2 and text_width(title, sx) > room:
		sx -= 1
	letters(s, title, 202, 22, sx, 6, INK)
	var ux := 3 if text_width(under, 3) <= room else 2
	letters(s, under, 202, 84, ux, 3, Color(.98, .86, .5) if not done else Color(.8, .96, .7))
	for p in [Vector2i(14, 14), Vector2i(337, 14), Vector2i(14, 119), Vector2i(337, 119)]:
		rivet(s, p.x, p.y)
	weather(s, 150, 3)
	return finish(s, 176, 67)


# --------------------------------------------------------------------- items


## A big old barn key with a cloth tag knotted to its bow, lying on its side.
func key_item(metal: Color, cloth: Color) -> Paint.Sheet:
	var s := Paint.Sheet.new(96, 96)
	# The tag first, under the bow.
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(6, 30), Vector2(26, 18), Vector2(36, 34), Vector2(14, 48)]),
		cloth
	)
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(8, 32), Vector2(24, 22), Vector2(28, 28), Vector2(12, 38)]),
		cloth.lightened(.3)
	)
	# The bow: a thick ring.
	Paint.ellipse(s, 18, 14, 50, 46, metal.darkened(.45))
	Paint.ellipse(s, 21, 17, 47, 43, metal)
	Paint.ellipse(s, 28, 24, 40, 36, Color(0, 0, 0, 0))
	Paint.arc(s, 21, 17, 47, 43, 190, 260, metal.lightened(.5), 3)
	# The shank down to the bit.
	Paint.line2(s, 42, 40, 82, 80, metal.darkened(.45), 11)
	Paint.line2(s, 42, 40, 82, 80, metal, 7)
	Paint.line2(s, 44, 39, 80, 75, metal.lightened(.45), 2)
	# The bit: two teeth.
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(66, 72), Vector2(76, 62), Vector2(86, 72), Vector2(76, 82)]),
		metal.darkened(.2)
	)
	Paint.rect(s, 68, 78, 74, 90, metal.darkened(.3))
	Paint.rect(s, 76, 80, 82, 92, metal.darkened(.3))
	# A glint.
	for d: Vector2i in [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]:
		Paint.point(s, 30 + d.x, 20 + d.y, Color(1, 1, .92))
	return finish(s, 48, 48, 5.0)


## The PA patch lead: a coil of orange cable, a jack plug at each end and a
## yellow tag marked PA.
func patch_lead() -> Paint.Sheet:
	var s := Paint.Sheet.new(108, 96)
	var cable := Color(.95, .42, .1)
	for k in 3:
		var o: int = k * 5
		Paint.arc(s, 14 + o, 26 + o / 2, 86 - o, 80 - o / 2, 0, 360, cable.darkened(.45), 9)
		Paint.arc(s, 15 + o, 27 + o / 2, 85 - o, 79 - o / 2, 0, 360, cable, 6)
		Paint.arc(s, 16 + o, 28 + o / 2, 84 - o, 78 - o / 2, 200, 280, cable.lightened(.4), 2)
	# The two plugs off the coil.
	for p in [[Vector2(70, 40), Vector2(98, 22)], [Vector2(30, 72), Vector2(8, 88)]]:
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		Paint.line2(s, a.x, a.y, b.x, b.y, cable.darkened(.3), 6)
		var mid := a.lerp(b, .55)
		Paint.line2(s, mid.x, mid.y, b.x, b.y, Color(.12, .11, .1), 9)
		var tip := b + (b - a).normalized() * 8
		Paint.line2(s, b.x, b.y, tip.x, tip.y, Color(.86, .86, .82), 4)
	# The tag.
	Paint.rect(s, 40, 6, 72, 26, Color(.98, .82, .14))
	Paint.outline(s, 40, 6, 72, 26, Color(.2, .14, .06))
	letters(s, "PA", 56, 9, 2, 2, Color(.16, .1, .06), false)
	Paint.line2(s, 56, 26, 56, 34, Color(.9, .88, .8), 2)
	return finish(s, 54, 48, 5.0)


# --------------------------------------------------------------------- tiles


## A locked gate's barricade (route_closed), laid once across the gate: it is
## about three times wider in the world than it is here, so the lettering is
## drawn tall and narrow. Two striped rails, a tin plate CLOSED and the lock.
func barricade() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	planks(s, 0, 0, 127, 127, Color(.3, .22, .15), 12)
	for rail in [[12, 34], [92, 114]]:
		for y in range(int(rail[0]), int(rail[1]) + 1):
			for x in 128:
				var band := posmod(x * 3 + y, 36) < 18
				var c := Color(.88, .84, .76) if band else Color(.74, .1, .07)
				var f := .92 + .08 * sin(x * .9 + y * .4)
				s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
		Paint.rect(s, 0, int(rail[0]) - 1, 127, int(rail[0]), SOOT)
		Paint.rect(s, 0, int(rail[1]), 127, int(rail[1]) + 1, SOOT)
	# The plate in the middle, and the chain and lock hanging off it.
	Paint.rect(s, 30, 40, 98, 86, Color(.9, .86, .74))
	Paint.outline(s, 30, 40, 98, 86, SOOT)
	Paint.outline(s, 32, 42, 96, 84, Color(.74, .1, .07))
	letters(s, "CLOSED", 64, 46, 2, 5, Color(.72, .08, .06), false)
	Paint.line2(s, 58, 86, 52, 100, Color(.55, .53, .5), 2)
	Paint.line2(s, 70, 86, 76, 100, Color(.55, .53, .5), 2)
	Paint.arc(s, 58, 96, 70, 110, 180, 360, Color(.6, .58, .54), 2)
	Paint.rect(s, 55, 103, 73, 118, Color(.82, .62, .22))
	Paint.rect(s, 63, 107, 65, 113, SOOT)
	weather(s, 120, 2)
	return Paint.digitize(s, 6.0)
