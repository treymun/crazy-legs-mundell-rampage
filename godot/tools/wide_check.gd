## ASPECT / SCALING WIDE (pass 14), headless: the picture's columns for
## each screen shape and where it is placed; the 3D view drawn that wide at
## the same focal length (Hor+), the crosshair's column the camera's middle
## and a point off to the side landing where the canvas would draw it; the
## HUD pieces kept to the edges they hug; the status bar's parts at the
## picture's edges with the plate's planks between (and at 320 exactly as
## before); the scope's glass round and across the whole picture; a bar drawn
## across the canvas spanning the picture; the setting's choice.
##
##   godot --headless --path godot --script res://tools/wide_check.gd
##
## The pictures themselves are the tour's wide_* viewpoints
## (picture_views.json `screen`, compare_3d.gd).
extends SceneTree

var failures: Array[String] = []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL ", what)


func _init() -> void:
	_columns()
	_projection()
	_sides()
	_bar()
	_scope()
	_spans()
	_setting()
	View.cols = View.WIDTH
	View.shift = 0
	View.square = false
	Scope.forget()
	if failures.is_empty():
		print("WIDE CHECK OK")
		quit(0)
	else:
		print("WIDE CHECK FAILED: %d" % failures.size())
		quit(1)


func _set_cols(cols: int, square := true) -> void:
	View.cols = cols
	View.shift = (cols - View.WIDTH) / 2
	View.square = square


## Each screen's columns, and the picture placed on it at that shape.
func _columns() -> void:
	var shapes := [
		[1920, 1080, 356, "16:9"],
		[2560, 1440, 356, "16:9 QHD"],
		[1280, 720, 356, "16:9 HD"],
		[2560, 1080, 474, "21:9"],
		[3440, 1440, 478, "21.5:9"],
		[5120, 1440, 712, "32:9"],
		[2532, 1170, 432, "19.5:9 phone"],
		[1280, 800, 320, "8:5"],
		[1024, 768, 320, "4:3"],
		[800, 1280, 320, "upright"],
		[9000, 1000, PictureShape.MOST_COLS, "past 32:9"],
	]
	for shape: Array in shapes:
		var w: int = shape[0]
		var h: int = shape[1]
		var want: int = shape[2]
		var cols := PictureShape.wide_cols(w, h)
		check(cols == want, "%s: %d columns, want %d" % [shape[3], cols, want])
		check(cols % 2 == 0, "%s: an even number of columns" % shape[3])
		var size := PictureShape.size_for(w, h, PictureShape.ASPECT_WIDE)
		check(size[0] <= w and size[1] <= h, "%s: the picture fits the screen" % shape[3])
		var shown := float(size[0]) / size[1]
		check(
			absf(shown - cols / 200.0) * size[1] <= 1.5,
			"%s: the picture is %d by 200 in shape (%dx%d)" % [shape[3], cols, size[0], size[1]]
		)
		if want > View.WIDTH and want < PictureShape.MOST_COLS:
			check(
				size[0] >= w - 2 or size[1] >= h - 2,
				"%s: no bars to speak of (%dx%d)" % [shape[3], size[0], size[1]]
			)
	# The other choices are as they were.
	check(
		PictureShape.size_for(1920, 1080, 0) == PackedInt32Array([1440, 1080]),
		"DOS 4:3 at 1920x1080 is 1440x1080"
	)
	check(
		PictureShape.size_for(1920, 1080, 1) == PackedInt32Array([1728, 1080]),
		"SQUARE 8:5 at 1920x1080 is 1728x1080"
	)


## The 3D view at WIDE: as many more columns, the same focal length (Hor+:
## the vertical view unchanged), and the camera's projection putting a point
## where the canvas (centred on the picture) puts it.
func _projection() -> void:
	var near := .02
	for cols: int in [320, 356, 474, 712]:
		_set_cols(cols)
		var view := View.new(null, null)
		for detail: int in [0, -1, 1]:
			view.set_detail(detail)
			var k := 2.0 if detail < 0 else 1.0 / float(1 << detail)
			check(
				view.vw == roundi(cols * k), "%d cols, detail %d: %d wide" % [cols, detail, view.vw]
			)
			check(
				view.vh == roundi(View.VIEW * k), "%d cols, detail %d: rows kept" % [cols, detail]
			)
			check(
				is_equal_approx(view.focal, View.base_focal * k),
				"%d cols, detail %d: the focal length kept" % [cols, detail]
			)
			# world_view.gd _place_camera: KEEP_HEIGHT, the view's height in focal.
			var size := near * view.vh / view.focal
			var horizon := view.vh * .5 + 9.0 * k
			var lens := Projection.create_frustum_aspect(
				size,
				float(view.vw) / view.vh,
				Vector2(0.0, (horizon - view.vh * .5) * near / view.focal),
				near,
				160.0,
				false
			)
			for side: float in [0.0, 1.7, -3.1]:
				var ahead := 4.0
				var clip := lens * Vector4(side, 0.0, -ahead, 1.0)
				var column := (clip.x / clip.w + 1.0) * .5 * view.vw
				# game_view.gd to_canvas, then the canvas's place on the picture.
				var canvas_x := View.WIDTH / 2.0 + side / ahead * View.base_focal + View.shift
				check(
					absf(column / k - canvas_x) < .01,
					(
						"%d cols, detail %d: a point %.1f aside drawn at %.2f, the canvas says %.2f"
						% [cols, detail, side, column / k, canvas_x]
					)
				)
		view.fit()
		_set_cols(View.WIDTH, false)
		view.fit()
		check(view.vw == View.WIDTH >> 1, "back at 320 the view (LOW) fits again")


## HudLayout.side_of: a piece hugging an edge keeps it, the rest stay centred.
func _sides() -> void:
	var cases := [
		[Rect2i(4, 4, 90, 30), -1, "the kill feed"],
		[Rect2i(8, 100, 70, 20), -1, "a picked-up thing's plate"],
		[Rect2i(193, 5, 123, 12), 1, "the boss bar"],
		[Rect2i(280, 4, 36, 8), 1, "the frame counter"],
		[Rect2i(40, 5, 240, 12), 0, "a banner"],
		[Rect2i(130, 70, 28, 14), 0, "a mark by the crosshair"],
		[Rect2i(4, 4, 312, 30), 0, "a piece across the view"],
		[Rect2i(), 0, "no piece"],
	]
	for row: Array in cases:
		var r: Rect2i = row[0]
		var want: int = row[1]
		check(HudLayout.side_of(r) == want, "%s keeps side %d" % [row[2], want])


## The status bar's Controls: at WIDE the right part at the picture's right
## edge, the planks between; at 320 exactly the old boxes.
func _bar() -> void:
	var hud := HUD.new(Assets.new())
	var layer := HudLayer.new(hud)
	for cols: int in [356, 712, 320]:
		_set_cols(cols, cols > 320)
		layer.fit()
		var across := 2 * View.shift
		check(layer.size.x == cols, "%d cols: the layer as wide as the picture" % cols)
		for part: String in HudLayer.BOXES:
			var r: Rect2i = HudLayer.BOXES[part]
			var box: TextureRect = layer.boxes[part]
			var want := r.position.x + (across if r.position.x >= HudLayer.SPLIT else 0)
			check(int(box.position.x) == want, "%d cols: %s at %d" % [cols, part, want])
			check(Vector2i(box.size) == r.size, "%d cols: %s its own size" % [cols, part])
		var pocket: TextureRect = layer.boxes["pocket"]
		var right_edge := pocket.position.x + pocket.size.x
		check(int(right_edge) == cols, "%d cols: the pocket at the right edge" % cols)
		check(layer.filler.visible == (cols > 320), "%d cols: the planks shown when wide" % cols)
		if cols > 320:
			check(
				(
					int(layer.filler.size.x) == across
					and int(layer.filler.position.x) == HudLayer.SPLIT
				),
				"%d cols: the planks fill the gap" % cols
			)
			check(
				int(layer.plate_right.position.x + layer.plate_right.size.x) == cols,
				"%d cols: the plate's right part at the edge" % cols
			)
		else:
			check(layer.plate.size == Vector2(320, 44), "at 320 the plate is whole")
		check(layer.pin.position.x == View.shift, "%d cols: the pin centred" % cols)
	layer.free()


## The scope's mask: across the whole picture, its glass round when WIDE (the
## pixels square), 1.2 wide on a 4:3 screen as before.
func _scope() -> void:
	for wide: bool in [true, false]:
		_set_cols(356 if wide else 320, wide)
		var c := Canvas.new()
		Scope.mask(c)
		var w := View.cols
		var mask: PackedByteArray = Scope._mask
		check(mask.size() == w * View.VIEW * 4, "the scope's mask is the picture's width")
		var cx := w / 2
		var cy := View.VIEW / 2
		var r := int(Scope.RADIUS)
		var reach := roundi(Scope.RADIUS * (1.0 if wide else Scope.ASPECT))
		# Just inside the glass across and down (off the hairs), and past it.
		var a_in := mask[((cy + 6) * w + cx + reach - 6) * 4 + 3]
		var a_out := mask[((cy + 6) * w + cx + reach + 4) * 4 + 3]
		var d_in := mask[((cy + r - 6) * w + cx + 6) * 4 + 3]
		check(a_in == 0 and d_in == 0, "the glass is clear to its rim (wide %s)" % wide)
		check(a_out == 255, "past the rim is black (wide %s)" % wide)
		check(mask[3] == 255 and mask[(w - 1) * 4 + 3] == 255, "black to the picture's sides")


## A rect across the 320 canvas spans the wide picture; one drawn for the
## picture (the automap's window, the scope's mask) is left as it is.
func _spans() -> void:
	_set_cols(356)
	var c := Canvas.new()
	check(c._spans(0, 320), "a bar across the canvas spans the picture")
	check(c._spans(-1, 322), "a shade a column past each side too")
	check(not c._spans(-16, 352), "the automap's own window is left alone")
	check(not c._spans(-18, 356), "the scope's mask is left alone")
	check(not c._spans(27, 266), "a panel is left alone")


func _setting() -> void:
	var found := false
	for page: Array in SessionStore.setup_pages():
		for item: SessionStore.Setting in page[1]:
			if item.key == "aspect":
				found = true
				check(
					item.format_value(PictureShape.ASPECT_WIDE) == "WIDE",
					"ASPECT / SCALING's choice %d is WIDE" % PictureShape.ASPECT_WIDE
				)
				check(item.default_value == 0, "the default stays DOS 4:3")
	check(found, "the ASPECT / SCALING row")
