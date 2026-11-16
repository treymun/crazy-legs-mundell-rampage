## THE MAP SHED (state "mapedit"): the player's map editor, on the county's
## own notice board. The plan on the left (each cell its own tile's picture),
## the palette on the right (GROUND, INSIDE, STEPS, WALLS, HANDS, LOOT, PROPS,
## MARKS), what the picked thing is and how to use it underneath, and a row of
## plates: NAME, SKY, SIZE, UNDO, CHECK, TEST, SAVE, BACK. The work itself is
## MapEditor's (UserMapPlay.editor); this screen turns the mouse, a finger,
## keys and a pad (as keys) into its calls:
##   click / drag paints, right click tears out, SHIFT-drag a box (a wall box
##   is a whole building), middle drag moves the plan;
##   arrows or WASD the cursor, SPACE paints, X tears out, B a box, Q/E the
##   item, TAB the tab, R turns, Z/Y undo/redo, +/- zoom, T test (SHIFT: from
##   the cursor), C check, N name, CTRL+S save, H the keys, ESC back.
class_name MapEditorScreen
extends UiScreen

const VIEW := Rect2i(12, 33, 210, 130)
const FRAME := Rect2i(10, 31, 214, 134)
const PALETTE := Rect2i(227, 31, 83, 134)
const ITEMS_Y := 46
const ITEM_H := 8
const HELP_Y := 167
const PLATES_Y := 181
const PLATE_H := 12
const PLATES := ["NAME", "SKY", "SIZE", "UNDO", "CHECK", "TEST", "SAVE", "BACK"]
const FIELDS := ["name", "author", "note"]
const FIELD_NAMES := {"name": "MAP NAME", "author": "MADE BY", "note": "A LINE ABOUT IT"}
const FACINGS := [
	"EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST", "NORTH", "NORTHEAST"
]
const KEYS_TEXT := [
	["CLICK, DRAG", "PAINT OR PLACE"],
	["RIGHT CLICK", "TEAR IT OUT"],
	["SHIFT + DRAG", "A BOX. A WALL BOX IS A BUILDING"],
	["MIDDLE DRAG", "SLIDE THE PLAN"],
	["ARROWS / WASD", "MOVE THE CURSOR"],
	["SPACE  /  X", "PAINT  /  TEAR OUT AT THE CURSOR"],
	["B", "START A BOX, B AGAIN TO FILL IT"],
	["Q  E  /  TAB", "PICK THE THING  /  THE TAB"],
	["R", "TURN YOUR START OR A PROP"],
	["Z  /  Y", "UNDO  /  REDO"],
	["+  /  -", "ZOOM"],
	["T  /  SHIFT+T", "TEST IT  /  FROM THE CURSOR"],
	["C", "CHECK WHAT IT CAN HOST"],
	["N   CTRL+S", "NAME IT   SAVE IT"],
]

var _picture: Image = null
var _picture_version := -1
var _picture_px := 0
var _holder := {}
var _painting := 0
var _last_cell := Vector2i(-1, -1)
var _box_from := Vector2i(-1, -1)
var _panning := false
var _pan_from := Vector2.ZERO
var _pan_view := Vector2i.ZERO
var _hover := Vector2i(-1, -1)
var _field := ""
var _text := ""
var _checking := false
var _keys := false
var _leave_armed := false
var _item_scroll := 0


func _init() -> void:
	super._init()
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(m: MainInput) -> void:
	super.open(m)
	if UserMapPlay.editor == null:
		UserMapPlay.editor = MapEditor.new()
		if main.smoke_frames > 0 and main.selection > 0:
			# --smoke-screen=mapedit:<n>[:1]: the list's n-th map (and its test
			# run), for pictures of the shed.
			UserMapPlay.refresh()
			var entry: Dictionary = UserMapPlay.entries[
				(main.selection - 1) % UserMapPlay.entries.size()
			]
			var start: Dictionary = entry["map"]
			UserMapPlay.editor = MapEditor.new(start)
			if main.showdown_mode >= 1:
				# 2..: from the cursor, turned (n - 2) eighths.
				UserMapPlay.editor.facing = posmod(main.showdown_mode - 2, 8)
				UserMapPlay.test.call_deferred(main, main.showdown_mode >= 2)
	_picture_version = -1
	_field = ""
	_checking = false
	_leave_armed = false
	grab_focus.call_deferred()


func _ed() -> MapEditor:
	return UserMapPlay.editor


func back() -> bool:
	_key(KEY_ESCAPE, false, false)
	return true


# ------------------------------------------------------------------ input


func _gui_input(event: InputEvent) -> void:
	if main == null or _ed() == null:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			if _field != "":
				_type(key)
			else:
				_key(key.keycode, key.shift_pressed, key.ctrl_pressed or key.meta_pressed)
		accept_event()
	elif event is InputEventMouseButton:
		_button(event as InputEventMouseButton)
		accept_event()
	elif event is InputEventMouseMotion:
		_motion(event as InputEventMouseMotion)
		accept_event()


func _key(code: int, shift: bool, ctrl: bool) -> void:
	var ed := _ed()
	if _checking or _keys:
		_checking = false
		_keys = false
		if code == KEY_ESCAPE:
			return
	if code != KEY_ESCAPE:
		_leave_armed = false
	var step := 4 if shift else 1
	match code:
		KEY_UP, KEY_W:
			_cursor_to(ed.cursor + Vector2i(0, -step))
		KEY_DOWN:
			_cursor_to(ed.cursor + Vector2i(0, step))
		KEY_S:
			if ctrl:
				_save()
			else:
				_cursor_to(ed.cursor + Vector2i(0, step))
		KEY_LEFT, KEY_A:
			_cursor_to(ed.cursor + Vector2i(-step, 0))
		KEY_RIGHT, KEY_D:
			_cursor_to(ed.cursor + Vector2i(step, 0))
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			ed.begin()
			if not ed.apply(ed.cursor):
				ed.undo_drop()
			_sound(true)
		KEY_X, KEY_DELETE:
			ed.begin()
			if not ed.erase(ed.cursor):
				ed.undo_drop()
			_sound(true)
		KEY_B:
			if _box_from.x < 0:
				_box_from = ed.cursor
				ed.note = "BOX FROM %d,%d. MOVE, THEN B AGAIN." % [ed.cursor.x, ed.cursor.y]
			else:
				ed.begin()
				if not ed.box(_box_from, ed.cursor):
					ed.undo_drop()
				_box_from = Vector2i(-1, -1)
				_sound(true)
		KEY_Q, KEY_BRACKETLEFT:
			ed.next_item(-1)
			_tick()
		KEY_E, KEY_BRACKETRIGHT:
			ed.next_item(1)
			_tick()
		KEY_TAB, KEY_PAGEDOWN:
			ed.next_tab(-1 if shift else 1)
			_tick()
		KEY_PAGEUP:
			ed.next_tab(-1)
			_tick()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			ed.tab = code - KEY_1
			_tick()
		KEY_R:
			ed.turn(-1 if shift else 1)
			_tick()
		KEY_Z:
			if shift:
				ed.redo()
			else:
				ed.undo()
			_tick()
		KEY_Y:
			ed.redo()
			_tick()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			ed.zoom_by(1)
			ed.follow(VIEW.size)
		KEY_MINUS, KEY_KP_SUBTRACT:
			ed.zoom_by(-1)
			ed.follow(VIEW.size)
		KEY_T:
			_test(shift)
		KEY_C:
			_checking = true
			main.sound.play("menu_accept")
		KEY_N:
			_edit_field("name")
		KEY_M:
			ed.next_mood(-1 if shift else 1)
			_tick()
		KEY_G:
			ed.next_size(-1 if shift else 1)
			_tick()
		KEY_H, KEY_F1:
			_keys = true
		KEY_ESCAPE, KEY_BACKSPACE:
			if _box_from.x >= 0:
				_box_from = Vector2i(-1, -1)
				ed.note = "BOX DROPPED."
			elif ed.changed and not _leave_armed:
				_leave_armed = true
				ed.note = "NOT SAVED. ESC AGAIN LEAVES IT BEHIND, CTRL+S SAVES."
				main.sound.play("menu_move")
			else:
				_leave()


func _cursor_to(c: Vector2i) -> void:
	var ed := _ed()
	var was := ed.cursor
	ed.move_cursor(c - ed.cursor)
	ed.follow(VIEW.size)
	if Input.is_key_pressed(KEY_SPACE) and ed.cursor != was:
		ed.begin()
		if not ed.apply(ed.cursor):
			ed.undo_drop()


func _tick() -> void:
	main.sound.play("menu_move")


func _sound(done: bool) -> void:
	main.sound.play("menu_move" if done else "empty")


## The cell under a point of the picture (-1, -1 off the plan).
func _cell_at(at: Vector2i) -> Vector2i:
	if not VIEW.has_point(at):
		return Vector2i(-1, -1)
	var ed := _ed()
	var px := ed.cells_px()
	var o := _origin(ed)
	if at.x < o.x or at.y < o.y:
		return Vector2i(-1, -1)
	var c := ed.view + (at - o) / px
	return c if ed.inside(c) else Vector2i(-1, -1)


func _button(b: InputEventMouseButton) -> void:
	var ed := _ed()
	var at := Vector2i(b.position)
	if not b.pressed:
		if _painting != 0 and _box_from.x >= 0 and b.button_index == MOUSE_BUTTON_LEFT:
			var c := _cell_at(at)
			if c.x < 0:
				c = _last_cell
			ed.box(_box_from, c)
			_box_from = Vector2i(-1, -1)
		if _painting != 0:
			ed.end_stroke()
		_painting = 0
		_panning = false
		return
	if _field != "":
		_finish_field(true)
		return
	if _checking or _keys:
		_checking = false
		_keys = false
		return
	_leave_armed = false
	if b.button_index == MOUSE_BUTTON_XBUTTON1:
		back()
		return
	if b.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = true
		_pan_from = b.position
		_pan_view = ed.view
		return
	if b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		ed.zoom_by(1 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		ed.clamp_view(VIEW.size)
		return
	var c := _cell_at(at)
	if c.x >= 0:
		ed.cursor = c
		_last_cell = c
		ed.begin()
		if b.button_index == MOUSE_BUTTON_RIGHT:
			_painting = 2
			ed.erase(c)
		elif b.button_index == MOUSE_BUTTON_LEFT:
			_painting = 1
			if b.shift_pressed:
				_box_from = c
			else:
				ed.apply(c)
		return
	if b.button_index != MOUSE_BUTTON_LEFT:
		return
	_palette_click(at)
	for i in PLATES.size():
		if _plate(i).has_point(at):
			_plate_do(str(PLATES[i]))


func _motion(m: InputEventMouseMotion) -> void:
	var ed := _ed()
	var at := Vector2i(m.position)
	if _panning:
		var px := ed.cells_px()
		ed.view = _pan_view - Vector2i((m.position - _pan_from) / px)
		ed.clamp_view(VIEW.size)
		return
	var c := _cell_at(at)
	_hover = c
	if c.x < 0 or c == _last_cell:
		return
	_last_cell = c
	ed.cursor = c
	if _box_from.x >= 0:
		return
	if _painting == 1:
		ed.apply(c)
	elif _painting == 2:
		ed.erase(c)


func _palette_click(at: Vector2i) -> void:
	var ed := _ed()
	if not PALETTE.has_point(at):
		return
	if at.y < ITEMS_Y - 2:
		ed.next_tab(-1 if at.x < PALETTE.position.x + PALETTE.size.x / 2 else 1)
		_tick()
		return
	var i := _item_scroll + (at.y - ITEMS_Y) / ITEM_H
	if i >= 0 and i < MapEditor.items(ed.tab).size():
		ed.pick_item(i)
		_tick()


func _plate(i: int) -> Rect2i:
	var w := 300 / PLATES.size()
	return Rect2i(10 + i * w, PLATES_Y, w - 2, PLATE_H)


func _plate_do(what: String) -> void:
	var ed := _ed()
	match what:
		"NAME":
			_edit_field("name")
		"SKY":
			ed.next_mood()
			_tick()
		"SIZE":
			ed.next_size()
			_tick()
		"UNDO":
			ed.undo()
			_tick()
		"CHECK":
			_checking = true
			main.sound.play("menu_accept")
		"TEST":
			_test(false)
		"SAVE":
			_save()
		"BACK":
			back()


func _test(here: bool) -> void:
	var why := UserMapPlay.test(main, here)
	if why != "":
		_ed().note = why
		main.sound.play("empty")
	else:
		main.sound.play("menu_accept")


func _save() -> void:
	var why := _ed().save()
	main.sound.play("empty" if why != "" else "menu_accept")


func _leave() -> void:
	_leave_armed = false
	UserMapPlay.open_list(main)
	main.sound.play("menu_back")


# ------------------------------------------------------------------ text


func _edit_field(key: String) -> void:
	_field = key
	_text = str(_ed().map.get(key, ""))
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(_text)
	main.sound.play("menu_accept")


func _finish_field(keep: bool) -> void:
	if keep:
		_ed().set_text(_field, _text)
	_field = ""
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


func _type(key: InputEventKey) -> void:
	match key.keycode:
		KEY_ESCAPE:
			_finish_field(false)
		KEY_ENTER, KEY_KP_ENTER:
			_finish_field(true)
		KEY_TAB, KEY_DOWN, KEY_UP:
			var at := FIELDS.find(_field)
			var next := str(
				FIELDS[posmod(
					at + (-1 if key.shift_pressed or key.keycode == KEY_UP else 1), FIELDS.size()
				)]
			)
			_finish_field(true)
			_edit_field(next)
		KEY_BACKSPACE:
			_text = _text.left(_text.length() - 1)
		_:
			var ch := ""
			if key.unicode > 0:
				ch = String.chr(key.unicode).to_upper()
			elif (
				key.keycode >= KEY_A and key.keycode <= KEY_Z
				or key.keycode >= KEY_0 and key.keycode <= KEY_9
			):
				ch = String.chr(key.keycode)
			elif key.keycode == KEY_SPACE:
				ch = " "
			if ch != "" and UserMap.LETTERS.contains(ch) and _text.length() < UserMap.limit(_field):
				_text += ch


# ------------------------------------------------------------------ drawing


func draw_back(c: Canvas) -> void:
	if main == null or _ed() == null:
		return
	var ed := _ed()
	main.menu.draw_sheet(c, "MAP SHED")
	_draw_plan(c, ed)
	_draw_palette(c, ed)
	_draw_help(c, ed)
	for i in PLATES.size():
		var r := _plate(i)
		var label := str(PLATES[i])
		var hot := r.has_point(Vector2i(main.pointer)) if main.input_device == "keys" else false
		LobbyScreens.box(c, r, LobbyScreens.LIT if hot else LobbyScreens.PLAIN)
		var ink := HUD.AMBER if hot else HUD.INK
		if label == "SAVE" and ed.changed:
			ink = Menu.BRASS_HI
		HUD.text(c, label, r.position.x + r.size.x / 2, r.position.y + 3, "mini", ink, true)
	if _checking:
		_draw_check(c, ed)
	elif _keys:
		_draw_keys(c)


func _draw_plan(c: Canvas, ed: MapEditor) -> void:
	LobbyScreens.box(c, FRAME, Menu.WELL)
	var px := ed.cells_px()
	if _picture == null or _picture_version != ed.version or _picture_px != px:
		_picture = MapPicture.image(main.art, ed.map, px)
		_picture_version = ed.version
		_picture_px = px
		_holder["version"] = "%d|%d" % [ed.version, px]
	ed.clamp_view(VIEW.size)
	var src := Rect2i(ed.view * px, VIEW.size)
	var o := _origin(ed)
	MapPicture.blit(c, _picture, src, o, _holder)
	var shown := Vector2i(
		mini(VIEW.size.x, _picture.get_width() - src.position.x),
		mini(VIEW.size.y, _picture.get_height() - src.position.y)
	)
	# Corner dots every cell when zoomed in, every fourth cell otherwise.
	var every := 1 if px >= 8 else 4
	var dot := Color(0, 0, 0, .55)
	for y in range(0, UserMap.height(ed.map) + 1, every):
		var sy := o.y + (y - ed.view.y) * px
		if sy < o.y or sy >= o.y + shown.y:
			continue
		for x in range(0, UserMap.width(ed.map) + 1, every):
			var sx := o.x + (x - ed.view.x) * px
			if sx >= o.x and sx < o.x + shown.x:
				c.fill_rect(sx, sy, 1, 1, dot)
	for v: Variant in ed.map["things"]:
		var t: Array = v
		var tx: int = t[2]
		var ty: int = t[3]
		var sx := o.x + (tx - ed.view.x) * px + px / 2
		var sy := o.y + (ty - ed.view.y) * px + px / 2
		if sx < o.x or sy < o.y or sx >= o.x + shown.x or sy >= o.y + shown.y:
			continue
		var facing: int = t[4]
		MapPicture.icon(c, str(t[0]), str(t[1]), sx, sy, maxi(3, px - 1), facing)
	# The box being dragged, then the cursor.
	var blink := int(main.menu_clock * 3.0) % 2 == 0
	if _box_from.x >= 0:
		var lo := Vector2i(mini(_box_from.x, ed.cursor.x), mini(_box_from.y, ed.cursor.y))
		var hi := Vector2i(maxi(_box_from.x, ed.cursor.x), maxi(_box_from.y, ed.cursor.y))
		var r := _cells_rect(ed, lo, hi)
		c.rect_outline(r.position.x, r.position.y, r.size.x, r.size.y, MapPicture.START)
	var cr := _cells_rect(ed, ed.cursor, ed.cursor)
	c.rect_outline(cr.position.x - 1, cr.position.y - 1, cr.size.x + 2, cr.size.y + 2, Menu.DARK)
	c.rect_outline(
		cr.position.x, cr.position.y, cr.size.x, cr.size.y, HUD.AMBER if blink else Menu.BRIGHT
	)
	# The map's name on the frame's top edge.
	var title := (
		"%s  %dX%d  %s"
		% [
			ed.map["name"],
			UserMap.width(ed.map),
			UserMap.height(ed.map),
			UserMap.mood(str(ed.map["mood"]))["label"]
		]
	)
	var tw := PixelType.text_width(title, "mini") + 6
	c.fill_rect(FRAME.position.x + 4, FRAME.position.y - 3, tw, 7, Menu.DARK)
	HUD.text(c, title, FRAME.position.x + 7, FRAME.position.y - 2, "mini", Menu.BRASS_HI)


## Where the view's top left cell is drawn: the plan's corner, or a map
## smaller than the view centred in it.
func _origin(ed: MapEditor) -> Vector2i:
	var size := Vector2i(UserMap.width(ed.map), UserMap.height(ed.map)) * ed.cells_px()
	return VIEW.position + ((VIEW.size - size) / 2).max(Vector2i.ZERO)


func _cells_rect(ed: MapEditor, lo: Vector2i, hi: Vector2i) -> Rect2i:
	var px := ed.cells_px()
	var a := _origin(ed) + (lo - ed.view) * px
	var b := _origin(ed) + (hi - ed.view + Vector2i.ONE) * px
	a = a.clamp(VIEW.position, VIEW.end)
	b = b.clamp(VIEW.position, VIEW.end)
	return Rect2i(a, b - a)


func _draw_palette(c: Canvas, ed: MapEditor) -> void:
	LobbyScreens.box(c, PALETTE, Menu.WELL)
	var head := Rect2i(PALETTE.position.x + 2, PALETTE.position.y + 2, PALETTE.size.x - 4, 11)
	c.fill_rect(head.position.x, head.position.y, head.size.x, head.size.y, Menu.RUST_DEEP)
	HUD.text(
		c,
		str(MapEditor.TABS[ed.tab][0]),
		head.position.x + head.size.x / 2,
		head.position.y + 2,
		"body",
		Menu.BRIGHT,
		true
	)
	HUD.text(c, "<", head.position.x + 3, head.position.y + 2, "body", Menu.BRASS_HI)
	HUD.text(c, ">", head.end.x - 3, head.position.y + 2, "body", Menu.BRASS_HI, false, true, true)
	var list := MapEditor.items(ed.tab)
	var shown := (PALETTE.end.y - ITEMS_Y - 10) / ITEM_H
	var picked := ed.picks[ed.tab]
	_item_scroll = clampi(_item_scroll, maxi(0, picked - shown + 1), picked)
	_item_scroll = clampi(_item_scroll, 0, maxi(0, list.size() - shown))
	for k in range(_item_scroll, mini(list.size(), _item_scroll + shown)):
		var entry: Dictionary = list[k]
		var y := ITEMS_Y + (k - _item_scroll) * ITEM_H
		var here := k == picked
		if here:
			c.fill_rect(PALETTE.position.x + 2, y - 1, PALETTE.size.x - 4, ITEM_H, LobbyScreens.LIT)
		_swatch(c, entry, PALETTE.position.x + 4, y, 6)
		var label := str(entry["label"])
		while PixelType.text_width(label, "mini") > PALETTE.size.x - 18 and label.length() > 3:
			label = label.left(label.length() - 1)
		HUD.text(
			c,
			label,
			PALETTE.position.x + 13,
			y,
			"mini",
			HUD.AMBER if here else HUD.INK,
			false,
			false
		)
	if _item_scroll > 0:
		HUD.text(c, "^", PALETTE.end.x - 5, ITEMS_Y - 1, "mini", Menu.FADED)
	if _item_scroll + shown < list.size():
		HUD.text(c, "V", PALETTE.end.x - 5, PALETTE.end.y - 17, "mini", Menu.FADED)
	# The foot: what the facing is (for your start and props) or the count.
	var foot := "%d/%d" % [picked + 1, list.size()]
	if not ed.is_cell_tab():
		foot = (
			"FACING %s" % FACINGS[ed.facing] if str(ed.item().get("name", "")) == "start" else foot
		)
	HUD.text(
		c,
		foot,
		PALETTE.position.x + PALETTE.size.x / 2,
		PALETTE.end.y - 9,
		"mini",
		Menu.FADED,
		true
	)


func _swatch(c: Canvas, entry: Dictionary, x: int, y: int, size: int) -> void:
	c.fill_rect(x - 1, y - 1, size + 2, size + 2, Menu.DARK)
	if entry.has("key"):
		var look := ""
		match str(entry["group"]):
			"wall":
				look = "wall"
			"inside":
				look = "inside"
			"rise":
				var lift: float = entry.get("ground", .24)
				look = "rise%d" % clampi(roundi(lift / .24), 1, 3)
		if str(entry["group"]) == "door":
			c.fill_rect(x, y, size, size, MapPicture.DOOR_EDGE)
			c.fill_rect(x + 1, y + 1, size - 2, size - 2, MapPicture.DOOR)
			return
		var img := MapPicture.swatch(main.art, str(entry["tile"]), size, look)
		var holder: Dictionary = _holder.get("sw|" + str(entry["key"]), {})
		if holder.is_empty():
			holder["version"] = "sw"
			_holder["sw|" + str(entry["key"])] = holder
		MapPicture.blit(c, img, Rect2i(0, 0, size, size), Vector2i(x, y), holder)
		return
	MapPicture.icon(
		c, str(entry["kind"]), str(entry["name"]), x + size / 2, y + size / 2, size + 1, 0
	)


func _draw_help(c: Canvas, ed: MapEditor) -> void:
	var spec := ed.item()
	var first := "%s: %s" % [spec["label"], spec["help"]]
	if _field != "":
		var blink := "_" if int(main.menu_clock * 3.0) % 2 == 0 else " "
		first = "%s: %s%s" % [FIELD_NAMES[_field], _text, blink]
	HUD.text(c, first.left(78), 12, HELP_Y, "mini", HUD.AMBER if _field != "" else HUD.INK, false)
	var second := ed.note
	var ink := Menu.BRASS_HI
	if _field != "":
		second = "ENTER KEEPS IT   TAB NEXT LINE   ESC LEAVES IT AS IT WAS"
		ink = Menu.FADED
	elif second == "":
		var c2 := ed.cursor
		var here := UserMap.cell(UserMap.at(ed.map, c2.x, c2.y))
		var held := ed.thing_at(c2)
		second = "%d,%d %s" % [c2.x, c2.y, here.get("label", "")]
		if not held.is_empty():
			second += " + " + str(UserMap.thing(str(held[0]), str(held[1])).get("label", ""))
		second += "    H: KEYS   SHIFT-DRAG: A BOX"
		ink = Menu.FADED
	HUD.text(c, second.left(78), 12, HELP_Y + 7, "mini", ink, false)


func _draw_check(c: Canvas, ed: MapEditor) -> void:
	var r := Rect2i(24, 40, 272, 118)
	LobbyScreens.box(
		c, Rect2i(r.position - Vector2i(2, 2), r.size + Vector2i(4, 4)), Menu.DARK, Menu.BRASS
	)
	LobbyScreens.box(c, r, Menu.WELL)
	HUD.text(c, "WHAT THIS MAP CAN HOST", 160, r.position.y + 4, "body", HUD.AMBER, true)
	var checked := UserMap.parse_text(UserMap.to_text(ed.map))
	var y := r.position.y + 16
	if checked.has("error"):
		HUD.text(c, str(checked["error"]), 160, y, "mini", LobbyScreens.RED, true)
		return
	var good: Dictionary = checked["map"]
	var modes := UserMap.modes(good)
	for mode: String in UserMap.MODE_ORDER:
		var why := str(modes[mode])
		HUD.text(c, str(UserMap.MODE_NAMES[mode]), r.position.x + 8, y, "mini", HUD.INK)
		HUD.text(
			c,
			"READY" if why == "" else why.left(44),
			r.position.x + 102,
			y,
			"mini",
			CustomMapsScreen.GREEN if why == "" else Menu.RUST_HOT
		)
		y += 9
	var warn := UserMap.warnings(ed.map)
	y += 3
	for k in mini(3, warn.size()):
		var w: Array = warn[k]
		HUD.text(
			c, "%d,%d: %s" % [w[0], w[1], str(w[2]).left(52)], r.position.x + 8, y, "mini", HUD.DIM
		)
		y += 8
	if warn.is_empty():
		HUD.text(c, "EVERY DOOR HANGS RIGHT. NO STRAYS.", r.position.x + 8, y, "mini", HUD.DIM)
	var counts := {}
	for v: Variant in ed.map["things"]:
		var t: Array = v
		var seen: int = counts.get(t[0], 0)
		counts[t[0]] = seen + 1
	HUD.text(
		c,
		(
			"%d HANDS   %d LOOT   %d PROPS   %d THINGS OF %d"
			% [
				counts.get("hand", 0),
				counts.get("loot", 0),
				counts.get("prop", 0),
				_count_things(ed),
				UserMap.limit("things")
			]
		),
		160,
		r.end.y - 18,
		"mini",
		Menu.FADED,
		true
	)
	HUD.text(c, "ANY KEY OR CLICK TO GET BACK TO IT", 160, r.end.y - 9, "mini", Menu.FADED, true)


func _count_things(ed: MapEditor) -> int:
	var list: Array = ed.map["things"]
	return list.size()


func _draw_keys(c: Canvas) -> void:
	var r := Rect2i(20, 36, 280, 128)
	LobbyScreens.box(
		c, Rect2i(r.position - Vector2i(2, 2), r.size + Vector2i(4, 4)), Menu.DARK, Menu.BRASS
	)
	LobbyScreens.box(c, r, Menu.WELL)
	HUD.text(c, "THE SHED'S KEYS", 160, r.position.y + 4, "body", HUD.AMBER, true)
	for i in KEYS_TEXT.size():
		var row: Array = KEYS_TEXT[i]
		var y := r.position.y + 16 + i * 8
		HUD.text(c, str(row[0]), r.position.x + 8, y, "mini", Menu.BRASS_HI)
		HUD.text(c, str(row[1]), r.position.x + 92, y, "mini", HUD.INK)
