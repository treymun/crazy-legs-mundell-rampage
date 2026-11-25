## The HUD's layout (src/ui/hud/hud_layout.gd), headless: each crowded moment
## of tools/hud_crowd.gd is drawn on the software canvas with every piece's
## ink measured (HudLayout.measuring), and the check fails when any two
## pieces over the view touch, when one inks past the view's margins, or
## when a piece the moment should show is missing. Also: the status bar's
## meter captions fit their wells, and the layout's own rules (down, up,
## the centred banner narrowing round a corner piece).
##
##   godot --headless --path godot --script res://tools/hud_layout_check.gd [-- png=<dir>]
##
## png=<dir> also writes each moment's 320x200 canvas (x3) with the pieces'
## rects outlined, to look at.
extends SceneTree

const Crowd := preload("res://tools/hud_crowd.gd")

var failures: Array = []
var main
var png := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("png="):
			png = String(arg).substr(4)
	if png != "":
		DirAccess.make_dir_recursive_absolute(png)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	_rules()
	_meters()
	HudLayout.measuring = true
	for moment: Array in Crowd.MOMENTS:
		_moment(str(moment[0]), moment[1])
	HudLayout.measuring = false
	_on_top()
	PixelType.clear_small = false
	main.touch.showing = false
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("HUD LAYOUT OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


## The layout's own rules on an empty view.
func _rules() -> void:
	print("\nTHE LAYOUT'S RULES")
	var lay := HudLayout.new()
	lay.reset()
	var a := lay.down("a", Vector2i(80, 30), 4, 36)
	_check(a == Rect2i(4, 36, 80, 30), "down() takes the wanted spot when it is clear")
	var b := lay.down("b", Vector2i(60, 20), 10, 40)
	_check(b.position.y == a.end.y + 1, "and slides the next one under it, a pixel clear")
	var c := lay.up("c", Vector2i(62, 33), 4)
	_check(c.end.y == HudLayout.BOTTOM, "up() sits a piece on the view's foot")
	var d := lay.up("d", Vector2i(50, 11), 4)
	_check(d.end.y == c.position.y - 1, "and stacks the next over it")
	var wide := "A LINE OF WORDS LONG ENOUGH THAT IT HAS TO WRAP TO FIT ACROSS THE VIEW AT ALL"
	var e := lay.banner("e", wide, HudLayout.BOTTOM - 1, 288, true)
	_check(
		e.size.x > 0 and e.position.x > c.end.x and e.size.x < 288,
		"a banner rising beside the badge narrows to clear it (%s)" % str(e)
	)
	var f := lay.centred("f", Vector2i(400, 10), 5)
	_check(f.size.x == 400 or f == Rect2i(), "a piece wider than the view takes what it asked")
	lay.reset()
	_check(lay.taken.is_empty(), "reset() clears the frame's pieces")


## The status bar's meters: each caption ends before its well begins.
func _meters() -> void:
	print("\nTHE STATUS BAR'S METERS")
	for style_small: bool in [false, true]:
		PixelType.clear_small = style_small
		for caption: String in ["GUT", "DRUNK"]:
			var ends := 4 + PixelType.text_width(caption, "body")
			_check(
				ends <= HUD.METER_WELL - 3,
				"%s fits before its meter's well (%d <= %d)" % [caption, ends, HUD.METER_WELL - 3]
			)
	PixelType.clear_small = false


func _moment(name: String, wants: Array) -> void:
	print("\n", name.to_upper())
	HudLayout.inked.clear()
	var g: Game = Crowd.make(main, name)
	if g == null:
		_check(false, "%s: the moment could not be set up" % name)
		return
	main.render()
	var inked: Dictionary = HudLayout.inked.duplicate()
	var shown := PackedStringArray()
	for key: String in inked:
		shown.append("%s %s" % [key, str(inked[key])])
	print("       ", ", ".join(shown))
	var lay0: HudLayout = main.hud.layout
	var laid := PackedStringArray()
	for i in lay0.taken.size():
		laid.append("%s %s" % [lay0.names[i], str(lay0.taken[i])])
	print("       laid out: ", ", ".join(laid))
	for want: String in wants:
		_check(inked.has(want), "%s shows its %s" % [name, want])
	var keys: Array = inked.keys()
	var touching: Array = []
	for i in keys.size():
		var a: Rect2i = inked[keys[i]]
		for j in range(i + 1, keys.size()):
			var b: Rect2i = inked[keys[j]]
			if a.intersects(b):
				touching.append("%s %s / %s %s" % [keys[i], str(a), keys[j], str(b)])
	# The touch buttons draw on their own Control: what play inks keeps off them.
	var lay: HudLayout = main.hud.layout
	for i in lay.taken.size():
		if not lay.names[i].begins_with("touch_"):
			continue
		for key: String in keys:
			var r: Rect2i = inked[key]
			if r.intersects(lay.taken[i]):
				touching.append("%s %s / %s %s" % [key, str(r), lay.names[i], str(lay.taken[i])])
	_check(touching.is_empty(), "%s: no two pieces overlap %s" % [name, ", ".join(touching)])
	var fixed := ["strip", "cash", "kills", "xp", "frags", "ring", "fps", "ping"]
	var outside: Array = []
	for key: String in keys:
		var r: Rect2i = inked[key]
		if fixed.has(key) or key.begins_with("tag"):
			continue
		if (
			r.position.x < HudLayout.EDGE
			or r.end.x > HudLayout.WIDTH - HudLayout.EDGE
			or r.position.y < HudLayout.TOP
			or r.end.y > HudLayout.BOTTOM
		):
			outside.append("%s %s" % [key, str(r)])
	_check(
		outside.is_empty(),
		"%s: every piece inside the view's margins %s" % [name, ", ".join(outside)]
	)
	if png != "":
		_picture(name, inked)
	main.game = null


## The notice and a new player's tip draw over every mark on the view: a hit
## from in front (its hurt arc, or DANGER ARROWS' chevron, at the view's top) leaves both
## banners' pixels as they are without it (pass 12: it struck them through).
func _on_top() -> void:
	print("")
	print("BANNERS ON TOP")
	var g: Game = Crowd.make(main, "campaign_minimal")
	g.hurt_flash = 0.0
	var kept := {}
	for hit: bool in [true, false]:
		g.damage_feedback = [g.player.view_angle(), "FIRE", g.clock + .5] if hit else null
		# DANGER ARROWS: the blow's chevron at the view's top, under the banners too.
		g.danger_blows = (
			[[g.player.view_angle(), g.clock - 1.0, g.clock + .5, 30.0]] if hit else []
		)
		main.render()
		for piece: String in ["notice", "tip"]:
			var r: Rect2i = main.hud.layout.find(piece)
			var rows := PackedByteArray()
			for y in range(r.position.y, r.end.y):
				var at := (y * 320 + r.position.x) * 3
				rows.append_array(main.canvas.pixels.slice(at, at + r.size.x * 3))
			if hit:
				kept[piece] = rows
			else:
				_check(
					r.size.x > 0 and rows == kept[piece],
					"the %s draws over the hurt arc of a hit from in front" % piece
				)
	main.game = null


## The canvas as drawn, three times over, with each piece's rect outlined.
func _picture(name: String, inked: Dictionary) -> void:
	var c: Canvas = main.canvas
	var img := Image.create_empty(320, 200, false, Image.FORMAT_RGB8)
	for y in 200:
		for x in 320:
			var i := y * 320 + x
			if y < View.VIEW and c.cover[i] == 0:
				var k := 60 + (x + y) % 8
				img.set_pixel(x, y, Color8(k, k - 10, k - 20))
			else:
				img.set_pixel(
					x, y, Color8(c.pixels[i * 3], c.pixels[i * 3 + 1], c.pixels[i * 3 + 2])
				)
	img.resize(960, 600, Image.INTERPOLATE_NEAREST)
	for key: String in inked:
		var r: Rect2i = inked[key]
		var s := Rect2i(r.position * 3, r.size * 3)
		for x in range(s.position.x, s.end.x):
			img.set_pixel(clampi(x, 0, 959), clampi(s.position.y, 0, 599), Color(0, 1, 1))
			img.set_pixel(clampi(x, 0, 959), clampi(s.end.y - 1, 0, 599), Color(0, 1, 1))
		for y in range(s.position.y, s.end.y):
			img.set_pixel(clampi(s.position.x, 0, 959), clampi(y, 0, 599), Color(0, 1, 1))
			img.set_pixel(clampi(s.end.x - 1, 0, 959), clampi(y, 0, 599), Color(0, 1, 1))
	img.save_png(png.path_join(name + ".png"))
