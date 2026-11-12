## Paint the firing range's signs into assets/art: Mundell's Proving Grounds,
## nailed up by the same county that lettered Hickston, in the game's own
## block letters on planks and tin, chipped, faded and shot at.
##
##   godot --headless --path godot --script res://tools/art/build_range_signs.gd [-- out=<dir>]
##
##   range_title          the marquee over the armory doors, bulbs and all
##   range_head_<lane>    each station's header board over its mouth
##   range_rules          the range rules by the armory doors
##   range_hot            RANGE IS HOT, red tin on the firing line
##   range_yd_<n>         the yard markers down the lanes
##   range_plaque_<gun>   the plaque under each gun on the armory walls
##   range_plate_<kind>   the name plate on each release lever
##   range_gallery_back   the shooting gallery's striped backdrop
##   range_bowling_mask   the bowling alley's pin deck board
## Seeded, so a rerun gives the same files. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

## [file, title, subtitle, face colour, ink]
const HEADS := [
	["cans", "TIN CAN ALLEY", ".38  RIFLE  RIVETER", "planks"],
	["pellets", "PELLET PATCH", "SAWED-OFF PATTERNS", "planks"],
	["rifle", "RIFLE RANGE", "HOW FAR EACH GUN REACHES", "planks"],
	["gallery", "DUCK GALLERY", "ANY GUN  30 SECONDS", "tin_red"],
	["bowling", "BOWL-O-RAMA", "ROLL ONE FOR A STRIKE", "tin_blue"],
	["soak", "SOAK TANK", "TEAT GUN TRIALS", "tin_cream"],
	["special", "SPECIAL ORDERS", "ARM GUN  COPPERHEAD  SAW", "tin_green"],
	["pit", "POWDER PIT", "DYNAMITE  KEGS  COWS", "tin_yellow"],
	["yard", "WHUPPIN' YARD", "CROWBAR  SLING BLADE  SAW", "planks"],
	["bullpen", "THE BULLPEN", "PULL A LEVER, MEET THE LOCALS", "planks_red"],
	["corral", "BOSS CORRAL", "ONE AT A TIME, FOR PETE'S SAKE", "planks_red"],
	["armory", "THE ARMORY", "WALK UP TO A GUN, PRESS USE", "planks"],
]
## The guns in weapons.cfg order: [plaque name, key].
const GUNS := [
	["CROWBAR", "1"],
	[".38 SPECIAL", "2"],
	["SAWED-OFF", "3"],
	["DYNAMITE BOW", "4"],
	["RANCH RIFLE", "5"],
	["RIP SAW", "6"],
	["ALIEN ARM GUN", "7"],
	["DYNAMITE", "8"],
	["SLING BLADE", "9"],
	["ROCKET TUBE", "0"],
	["MILL RIVETER", "WHEEL"],
	["COPPERHEAD", "WHEEL"],
	["BOWLING BALL", "-"],
	["POWDER KEG", "="],
	["COW LAUNCHER", "WHEEL"],
	["TEAT GUN", "WHEEL"],
]
## Lever plates: [id, name].
const PLATES := [
	["billy", "BILLY"],
	["coot", "COOT"],
	["skeeter", "SKEETER"],
	["clone", "CLONE"],
	["alien", "GREY ALIEN"],
	["saucer", "SAUCER"],
	["barker", "BARKER"],
	["crawler", "CRAWLER"],
	["bottle_tosser", "BOTTLE TOSSER"],
	["millhand", "MILLHAND"],
	["lantern", "LANTERN"],
	["boilerback", "BOILERBACK"],
	["chalk_spitter", "CHALK SPITTER"],
	["yard_deputy", "YARD DEPUTY"],
	["chain_hand", "CHAIN HAND"],
	["valve_rat", "VALVE RAT"],
	["boss", "ALIEN SHERIFF"],
	["jerry", "JERRY JONES"],
	["rudy", "RUDY RACKET"],
	["foreman", "THE FOREMAN"],
	["baron", "COPPER BARON"],
	["squad", "A WHOLE SQUAD"],
	["clear", "CLEAR THE PEN"],
	["reset", "RESET IT ALL"],
	["fodder", "SEND FODDER"],
	["soak", "TURN OUT HANDS"],
	["alien_one", "WAKE THE GREY"],
	["gallery", "START ROUND"],
	["pins", "RACK THE PINS"],
	["cans", "STAND CANS UP"],
]
const YARDS := [3, 5, 6, 9, 10, 12, 15, 20, 25, 30, 35]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1997
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var made := {"range_title": title_sign(), "range_rules": rules_sign(), "range_hot": hot_sign()}
	for row: Array in HEADS:
		made["range_head_" + String(row[0])] = head(String(row[1]), String(row[2]), String(row[3]))
	for n: int in YARDS:
		made["range_yd_%d" % n] = yard_marker(n)
	for i in GUNS.size():
		var gun: Array = GUNS[i]
		made["range_plaque_%d" % i] = plaque(String(gun[0]), String(gun[1]))
	for row: Array in PLATES:
		made["range_plate_" + String(row[0])] = plate(String(row[1]))
	made["range_display"] = display_board()
	made["range_gallery_back"] = gallery_back()
	made["range_bowling_mask"] = bowling_mask()
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		sheet.save(out.path_join(name + ".png"))
	print("range signs: %d written to %s" % [made.size(), out])
	quit()


# ------------------------------------------------------------------ surfaces


func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		var tone := 1.0 + sin(row * 2.3) * .06
		var seam := y % plank == 0
		for x in width:
			var f := tone + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			f *= 1.0 + (1.0 - float(y) / height) * .08
			if seam:
				f *= .55
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))
	return s


func tin(width: int, height: int, base: Color) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf(b * 1.3 - clampf(edge, 0, 1) * .8 - .1, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			var f := 1.0 + grit[y * width + x] + (sin(x * 1.4) * .04)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	return s


## The face a header is painted on, and the ink that reads on it.
func face(kind: String, width: int, height: int) -> Array:
	match kind:
		"tin_red":
			return [tin(width, height, Color(.66, .16, .12)), Color8(250, 232, 190)]
		"tin_blue":
			return [tin(width, height, Color(.2, .3, .5)), Color8(246, 214, 120)]
		"tin_cream":
			return [tin(width, height, Color(.86, .82, .7)), Color8(40, 30, 24)]
		"tin_green":
			return [tin(width, height, Color(.22, .38, .26)), Color8(240, 230, 200)]
		"tin_yellow":
			return [tin(width, height, Color(.86, .66, .16)), Color8(36, 24, 16)]
		"planks_red":
			return [planks(width, height, Color(.5, .17, .12), 8), Color8(240, 226, 190)]
	return [planks(width, height, Color(.5, .36, .24), 8), Color8(240, 228, 196)]


# ------------------------------------------------------------------ lettering


func text_width(text: String, scale: int) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	return width - scale


## Block letters `scale` times their size, with a drop shadow, centred on x.
func letters(
	s: Paint.Sheet, text: String, x: int, y: int, scale: int, ink: Color, shadow := true
) -> void:
	var left := x - text_width(text, scale) / 2
	for pass_k in [1, 0] if shadow else [0]:
		var off: int = pass_k * maxi(1, scale / 2)
		var colour := Color(.08, .05, .04, .85) if pass_k == 1 else ink
		var at := left
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			var rows: Array = g[0]
			var gw: int = g[1]
			for r in rows.size():
				for bx in gw:
					if int(rows[r]) & (1 << (gw - 1 - bx)):
						for yy in scale:
							for xx in scale:
								_blend(
									s, at + bx * scale + xx + off, y + r * scale + yy + off, colour
								)
			at += (gw + 1) * scale


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var a := c.a
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - a) + c[k] * 255.0 * a)
	s.data[o + 3] = maxi(s.data[o + 3], int(a * 255))


func weather(s: Paint.Sheet, chips: int, holes: int) -> void:
	for _k in chips:
		var x := rng.randi_range(1, s.w - 2)
		var y := rng.randi_range(1, s.h - 2)
		var o := (y * s.w + x) * 4
		for k in 3:
			s.data[o + k] = int(s.data[o + k] * .72)
	for _k in holes:
		var x := rng.randi_range(3, s.w - 4)
		var y := rng.randi_range(3, s.h - 4)
		Paint.point(s, x, y, Color8(14, 10, 8))
		Paint.point(s, x + 1, y, Color8(150, 140, 128))
		Paint.point(s, x, y - 1, Color8(150, 140, 128))


func frame(s: Paint.Sheet, c: Color) -> void:
	Paint.outline(s, 0, 0, s.w - 1, s.h - 1, c)
	Paint.outline(s, 1, 1, s.w - 2, s.h - 2, c.lightened(.25))


func nails(s: Paint.Sheet) -> void:
	for p in [
		Vector2i(2, 2), Vector2i(s.w - 3, 2), Vector2i(2, s.h - 3), Vector2i(s.w - 3, s.h - 3)
	]:
		Paint.point(s, p.x, p.y, Color8(200, 196, 186))


## Marquee bulbs round the edge, most still working.
func bulbs(s: Paint.Sheet, step := 6) -> void:
	for x in range(4, s.w - 3, step):
		for y in [1, s.h - 2]:
			var on := rng.randf() < .8
			Paint.point(s, x, y, Color8(255, 226, 150) if on else Color8(90, 70, 50))
	for y in range(5, s.h - 4, step):
		for x in [1, s.w - 2]:
			var on := rng.randf() < .8
			Paint.point(s, x, y, Color8(255, 226, 150) if on else Color8(90, 70, 50))


# --------------------------------------------------------------------- signs


func title_sign() -> Paint.Sheet:
	var s := tin(200, 62, Color(.86, .8, .66))
	Paint.rect(s, 4, 4, 195, 36, Color8(164, 34, 26))
	letters(s, "MUNDELL'S", 100, 6, 2, Color8(250, 236, 196))
	letters(s, "PROVING GROUNDS", 100, 22, 2, Color8(250, 214, 120))
	letters(s, "SHOOT IT  LEARN IT  CLEAN IT", 100, 41, 1, Color8(40, 30, 24), false)
	letters(s, "OPEN DUSK TILL THE COWS COME HOME", 100, 51, 1, Color8(150, 30, 24), false)
	bulbs(s)
	frame(s, Color8(46, 34, 26))
	weather(s, 110, 7)
	return Paint.digitize(s)


func head(title: String, subtitle: String, kind: String) -> Paint.Sheet:
	var made: Array = face(kind, 176, 46)
	var s: Paint.Sheet = made[0]
	var ink: Color = made[1]
	var scale := 2 if text_width(title, 2) <= 164 else 1
	letters(s, title, 88, 7 if scale == 2 else 11, scale, ink)
	Paint.rect(s, 10, 25, 165, 25, ink.darkened(.15))
	letters(s, subtitle, 88, 30, 1, ink, false)
	frame(s, Color8(40, 28, 20))
	nails(s)
	weather(s, 90, 4)
	return Paint.digitize(s)


func rules_sign() -> Paint.Sheet:
	var s := planks(100, 84, Color(.84, .8, .7), 7)
	letters(s, "RANGE RULES", 50, 4, 1, Color8(150, 30, 24), false)
	Paint.rect(s, 12, 13, 87, 13, Color8(150, 30, 24))
	var lines := [
		"1 POINT IT", "  DOWNRANGE", "2 DON'T FEED", "  THE BULLPEN", "3 NO REFUNDS", "  ON COWS"
	]
	for i in lines.size():
		var text := String(lines[i])
		var x := 8
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			_glyph(s, g, x, 18 + i * 10, Color8(40, 30, 24))
			x += int(g[1]) + 1
	frame(s, Color8(60, 48, 40))
	nails(s)
	weather(s, 70, 5)
	return Paint.digitize(s)


func _glyph(s: Paint.Sheet, g: Array, x: int, y: int, ink: Color) -> void:
	var rows: Array = g[0]
	var gw: int = g[1]
	for r in rows.size():
		for bx in gw:
			if int(rows[r]) & (1 << (gw - 1 - bx)):
				_blend(s, x + bx, y + r, ink)


func hot_sign() -> Paint.Sheet:
	var s := tin(84, 30, Color(.7, .14, .1))
	letters(s, "RANGE IS HOT", 42, 4, 1, Color8(250, 236, 200))
	letters(s, "WHEN THE FLAG", 42, 13, 1, Color8(250, 226, 160), false)
	letters(s, "IS UP", 42, 21, 1, Color8(250, 226, 160), false)
	frame(s, Color8(40, 20, 16))
	weather(s, 50, 6)
	return Paint.digitize(s)


func yard_marker(n: int) -> Paint.Sheet:
	var s := tin(30, 16, Color(.9, .88, .82))
	letters(s, "%d YD" % n, 15, 4, 1, Color8(30, 24, 20), false)
	frame(s, Color8(40, 34, 30))
	weather(s, 12, 1 if n > 10 else 0)
	return Paint.digitize(s)


func plaque(name: String, key: String) -> Paint.Sheet:
	var s := planks(84, 24, Color(.42, .28, .17), 6)
	letters(s, name, 42, 4, 1, Color8(246, 226, 170))
	var hint := "KEY " + key if key != "WHEEL" else "MOUSE WHEEL"
	letters(s, hint, 42, 14, 1, Color8(220, 196, 140), false)
	frame(s, Color8(34, 22, 14))
	nails(s)
	weather(s, 20, 0)
	return Paint.digitize(s)


func plate(name: String) -> Paint.Sheet:
	var s := tin(96, 14, Color(.86, .82, .7))
	letters(s, name, 48, 3, 1, Color8(36, 26, 20), false)
	frame(s, Color8(40, 32, 26))
	weather(s, 14, 0)
	return Paint.digitize(s)


## The board each gun hangs on: pale pine, a red rim, two pegs.
func display_board() -> Paint.Sheet:
	var s := planks(56, 40, Color(.78, .66, .46), 5)
	Paint.outline(s, 2, 2, 53, 37, Color8(150, 34, 26))
	Paint.outline(s, 3, 3, 52, 36, Color8(190, 60, 40))
	for x in [14, 41]:
		Paint.rect(s, x, 26, x + 1, 29, Color8(60, 44, 30))
		Paint.point(s, x, 26, Color8(200, 190, 170))
	frame(s, Color8(46, 32, 22))
	nails(s)
	weather(s, 40, 2)
	return Paint.digitize(s)


func gallery_back() -> Paint.Sheet:
	var s := Paint.Sheet.new(192, 56)
	var grit := Paint.noise(rng.randi(), 192 * 56, .05)
	for y in 56:
		for x in 192:
			var stripe := (x / 12) % 2 == 0
			var c := Color(.7, .16, .12) if stripe else Color(.9, .84, .7)
			c = c.darkened(clampf(float(y) / 56.0 * .35, 0, .35))
			var f := 1.0 + grit[y * 192 + x]
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	Paint.rect(s, 0, 0, 191, 13, Color8(40, 60, 120))
	for k in 12:
		var x := 8 + k * 16
		Paint.point(s, x, 6, Color8(250, 230, 150))
		Paint.point(s, x - 1, 6, Color8(250, 230, 150))
		Paint.point(s, x + 1, 6, Color8(250, 230, 150))
		Paint.point(s, x, 5, Color8(250, 230, 150))
		Paint.point(s, x, 7, Color8(250, 230, 150))
	letters(s, "STEP RIGHT UP", 96, 22, 2, Color8(250, 214, 120))
	letters(s, "EVERY SHOT A WINNER, MOSTLY", 96, 42, 1, Color8(250, 240, 220))
	frame(s, Color8(40, 28, 20))
	weather(s, 60, 9)
	return Paint.digitize(s)


func bowling_mask() -> Paint.Sheet:
	var s := tin(150, 44, Color(.18, .22, .4))
	letters(s, "BOWL-O-RAMA", 75, 4, 2, Color8(250, 214, 120))
	for k in 5:
		var x := 27 + k * 24
		Paint.ellipse(s, x - 3, 24, x + 3, 38, Color8(240, 234, 222))
		Paint.ellipse(s, x - 2, 21, x + 2, 27, Color8(240, 234, 222))
		Paint.rect(s, x - 2, 27, x + 2, 28, Color8(200, 34, 30))
	frame(s, Color8(20, 20, 30))
	weather(s, 40, 3)
	return Paint.digitize(s)
