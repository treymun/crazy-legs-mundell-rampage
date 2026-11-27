## CUSTOM MAPS (state "maps", from the title): every player map the game can
## see (yours in user://maps, the examples, the ones lobbies, the shelf and
## codes brought), each with a picture of its plan, who made it, and what it
## can host. Up and down pick a map, left and right what to do with it, ENTER
## does it (a click or a tap on either does the same); a mode the map cannot
## host says why on the line underneath. N is a new map in the MAP SHED.
## Above the maps: THE MAP SHELF (the server's, browsed in place of the list)
## and ENTER A CODE (a shelf code or a long code; CTRL+V anywhere pastes
## one); a map's SHARE IT copies its long code, and again puts it on the
## shelf (map_shelf_panel.gd). State is UserMapPlay's.
class_name CustomMapsScreen
extends UiScreen

const LIST := Rect2i(14, 31, 134, 137)
const ROW_H := 17
const SHOWN := 8
const PANEL := Rect2i(151, 31, 155, 137)
const PICTURE := Rect2i(155, 34, 147, 66)
const ACTIONS_Y := 102
const ACTION_H := 8
## Actions shown at once (more scroll with the cursor).
const ACTIONS_SHOWN := 8
const NOTE_Y := 170
const GREEN := Color8(132, 206, 96)
## The list's rows before the maps.
const FIRST := UserMapPlay.ROWS_BEFORE
const SHED_TEXT := [
	"PAINT GROUND, FLOORS AND WALLS. RAISE A BUILDING IN ONE DRAG.",
	"DROP IN HANDS, LOOT, PROPS, YOUR START, THE BIG LEVER AND THE GETAWAY TRUCK.",
	"MARK OUT 5V5 STARTS AND BOMB SITES IF YOU WANT TEAMS ON IT.",
	"TEST IT, THEN SAVE IT.",
]
## A map's own actions past UserMapPlay's, and where each goes.
const SHARE_AFTER := "host"
const SHARE_NAME := "SHARE IT"

var shelf: MapShelfPanel
var _picture: Image = null
var _picture_of := ""
var _holder := {}
var _scroll := 0
var _action_top := 0


func _init() -> void:
	super._init()
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	shelf = MapShelfPanel.new(self)


func open(m: MainInput) -> void:
	super.open(m)
	UserMapPlay.refresh()
	if m.smoke_frames > 0 and m.selection > 0:
		UserMapPlay.row = m.selection  # --smoke-screen=maps:<row>
	_picture_of = ""
	grab_focus.call_deferred()


func close() -> void:
	if shelf.typing != "":
		shelf.stop_typing(false)
	shelf.close_shelf()


func _process(_delta: float) -> void:
	if visible and shelf.busy():
		shelf.poll(Time.get_ticks_msec())


## The list's rows: NEW MAP, THE MAP SHELF, ENTER A CODE, then every map.
func _count() -> int:
	return UserMapPlay.entries.size() + FIRST


## The actions the picked row offers.
func _actions() -> Array:
	match UserMapPlay.row:
		0:
			return ["new"]
		1:
			return ["shelf"]
		2:
			return ["type", "paste"]
	var entry := _entry()
	if entry.is_empty():
		return ["new"]
	var out: Array = []
	if UserMapPlay.has_save(entry) and not entry.has("error"):
		out.append("continue")
	for what: String in UserMapPlay.ACTIONS:
		out.append(what)
		if what == SHARE_AFTER:
			out.append("share")
	return out


func _entry() -> Dictionary:
	var at := UserMapPlay.row - FIRST
	if at < 0 or at >= UserMapPlay.entries.size():
		return {}
	var entry: Dictionary = UserMapPlay.entries[at]
	return entry


## Pick the list's map with `hash` (a map that just came by code or shelf).
func pick_hash(hash: String) -> void:
	for i in UserMapPlay.entries.size():
		var entry: Dictionary = UserMapPlay.entries[i]
		if str(entry.get("hash", "")) == hash:
			UserMapPlay.row = i + FIRST
			UserMapPlay.action = 0
			_action_top = 0
			_scroll = clampi(_scroll, UserMapPlay.row - SHOWN + 1, UserMapPlay.row)
			_picture_of = ""
			return


func back() -> bool:
	if shelf.typing != "":
		shelf.stop_typing(false)
		main.sound.play("menu_back")
		return true
	if shelf.open:
		shelf.close_shelf()
		main.sound.play("menu_back")
		return true
	UserMapPlay.armed = false
	main.state = "title"
	main.sound.play("menu_back")
	return true


func _gui_input(event: InputEvent) -> void:
	if main == null:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if shelf.typing != "":
			shelf.type_key(key)
		elif key.ctrl_pressed and key.keycode == KEY_V:
			shelf.paste_code()
		elif not (shelf.open and shelf.shelf_key(key.keycode)):
			_key(key.keycode)
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_click(Vector2i(button.position))
		elif button.button_index == MOUSE_BUTTON_XBUTTON1:
			back()
		accept_event()
	elif event is InputEventMouseMotion:
		_hover(Vector2i((event as InputEventMouseMotion).position))


func _key(code: int) -> void:
	if shelf.open:
		return  # (ESC is back(), the rest the shelf's)
	match code:
		KEY_UP, KEY_W:
			_pick_row(UserMapPlay.row - 1)
		KEY_DOWN, KEY_S:
			_pick_row(UserMapPlay.row + 1)
		KEY_LEFT, KEY_A:
			_pick_action(UserMapPlay.action - 1)
		KEY_RIGHT, KEY_D:
			_pick_action(UserMapPlay.action + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_do(str(_actions()[clampi(UserMapPlay.action, 0, _actions().size() - 1)]))
		KEY_N:
			_do("new")
		KEY_E:
			_do("edit")
		KEY_ESCAPE, KEY_BACKSPACE:
			back()


func _pick_row(at: int) -> void:
	var was := UserMapPlay.row
	UserMapPlay.row = posmod(at, _count())
	if UserMapPlay.row != was:
		UserMapPlay.armed = false
		shelf.armed = ""
		UserMapPlay.note = ""
		UserMapPlay.action = 0
		_action_top = 0
		main.sound.play("menu_move")
	_scroll = clampi(_scroll, UserMapPlay.row - SHOWN + 1, UserMapPlay.row)


func _pick_action(at: int) -> void:
	var list := _actions()
	var was := UserMapPlay.action
	UserMapPlay.action = posmod(at, list.size())
	if UserMapPlay.action != was:
		UserMapPlay.armed = false
		shelf.armed = ""
		main.sound.play("menu_move")
	_action_top = clampi(_action_top, UserMapPlay.action - ACTIONS_SHOWN + 1, UserMapPlay.action)


## Row `i` of the list (or of the shelf's page, from `top`).
func row_rect(i: int, top: int) -> Rect2i:
	return Rect2i(
		LIST.position.x + 2, LIST.position.y + 2 + (i - top) * ROW_H, LIST.size.x - 4, ROW_H - 1
	)


func _row_rect(i: int) -> Rect2i:
	return row_rect(i, _scroll)


## Action `i` of the panel, as it stands on screen (the shelf's from the top).
func action_rect(i: int) -> Rect2i:
	return Rect2i(PANEL.position.x + 3, ACTIONS_Y + i * ACTION_H, PANEL.size.x - 6, ACTION_H - 1)


func _action_rect(i: int) -> Rect2i:
	return action_rect(i - _action_top)


## THE MAP SHED's plate at the panel's foot (NEW MAP picked).
func _shed_rect() -> Rect2i:
	return plate_rect(1)


## The panel's plates at its foot: 0 the upper, 1 the lower.
func plate_rect(i: int) -> Rect2i:
	var r := action_rect(4)
	r.position.y = PANEL.end.y - 30 + i * 14
	r.size.y += 2
	return r


func _click(at: Vector2i) -> void:
	if Menu.BACK.has_point(at):
		back()
		return
	if shelf.typing != "":
		return  # (ENTER or ESC finish the field; a phone's keyboard has both)
	if shelf.open:
		_shelf_click(at)
		return
	match UserMapPlay.row:
		0:
			if _shed_rect().has_point(at):
				_do("new")  # the plate a finger sees (before pass 14 it took no tap)
				return
		1:
			if plate_rect(1).has_point(at):
				_do("shelf")
				return
		2:
			for i in 2:
				if plate_rect(i).has_point(at):
					UserMapPlay.action = i
					_do(str(_actions()[i]))
					return
	for i in range(_scroll, mini(_count(), _scroll + SHOWN)):
		if _row_rect(i).has_point(at):
			if i == UserMapPlay.row and i < FIRST:
				_do(str(_actions()[0]))
			_pick_row(i)
			return
	if UserMapPlay.row < FIRST:
		return
	var list := _actions()
	for i in range(_action_top, mini(list.size(), _action_top + ACTIONS_SHOWN)):
		if _action_rect(i).has_point(at):
			UserMapPlay.action = i
			_do(str(list[i]))
			return


func _shelf_click(at: Vector2i) -> void:
	for i in shelf.rows.size():
		if row_rect(i, 0).has_point(at):
			if i == shelf.row:
				shelf.shelf_do("take")
			shelf.row = i
			main.sound.play("menu_move")
			return
	for i in MapShelfPanel.ACTIONS.size():
		if action_rect(i).has_point(at):
			shelf.action = i
			shelf.shelf_do(str(MapShelfPanel.ACTIONS[i]))
			return


func _hover(at: Vector2i) -> void:
	if shelf.open or UserMapPlay.row < FIRST:
		return
	var list := _actions()
	for i in range(_action_top, mini(list.size(), _action_top + ACTIONS_SHOWN)):
		if _action_rect(i).has_point(at) and UserMapPlay.action != i:
			_pick_action(i)


func _do(what: String) -> void:
	var entry := _entry()
	var m: MainFlow = main
	var why := ""
	match what:
		"new":
			UserMapPlay.editor = MapEditor.new()
			UserMapPlay.editor.note = "A FRESH PASTURE. PAINT IT, FILL IT, TEST IT."
			main.state = "mapedit"
			main.sound.play("menu_accept")
			return
		"shelf":
			shelf.open_shelf()
			main.sound.play("menu_accept")
			return
		"type":
			shelf.start_typing("code")
			return
		"paste":
			shelf.paste_code()
			return
		"share":
			why = UserMapPlay.why_not(entry, what)
			if why == "":
				why = shelf.share(entry)
			if why == "":
				return
		"edit":
			if entry.is_empty() or entry.has("error"):
				why = str(entry.get("error", "PICK A MAP FIRST."))
			else:
				var start: Dictionary = entry["map"]
				var ed := MapEditor.new(start)
				ed.stem = str(entry["stem"])
				ed.source = str(entry["source"])
				ed.note = (
					"AN EXAMPLE. SAVING MAKES IT YOUR OWN COPY."
					if ed.source != "mine"
					else "BACK IN THE SHED."
				)
				UserMapPlay.editor = ed
				main.state = "mapedit"
				main.sound.play("menu_accept")
				return
		"continue":
			why = UserMapPlay.load_save(m, entry)
		"host":
			why = UserMapPlay.host(m, entry)
		"remove":
			why = UserMapPlay.why_not(entry, "remove")
			if why == "" and not UserMapPlay.armed:
				UserMapPlay.armed = true
				var again := "TAP" if main.input_device == "touch" else "ENTER"
				UserMapPlay.note = (
					"%s AGAIN TO THROW OUT %s. NO TAKING IT BACK."
					% [again, str(entry["map"]["name"])]
				)
				main.sound.play("menu_move")
				return
			if why == "":
				UserMapPlay.armed = false
				if UserMaps.remove(entry):
					UserMapPlay.refresh()
					UserMapPlay.note = "THROWN OUT."
					_picture_of = ""
				else:
					why = "COULDN'T THROW IT OUT."
		_:
			why = UserMapPlay.play(m, entry, what)
	if why != "":
		UserMapPlay.note = why
		main.sound.play("empty")
	elif what != "remove":
		main.sound.play("menu_accept")


# ------------------------------------------------------------------ drawing


func draw_back(c: Canvas) -> void:
	if main == null:
		return
	main.menu.draw_sheet(c, "CUSTOM MAPS")
	LobbyScreens.box(c, LIST, Menu.WELL)
	LobbyScreens.box(c, PANEL, Menu.WELL)
	var entry := _entry()
	if shelf.open:
		shelf.draw_list(c)
		shelf.draw_panel(c)
	else:
		_scroll = clampi(_scroll, maxi(0, UserMapPlay.row - SHOWN + 1), UserMapPlay.row)
		for i in range(_scroll, mini(_count(), _scroll + SHOWN)):
			_draw_row(c, i)
		if _scroll > 0:
			HUD.text(
				c,
				"MORE",
				LIST.end.x - 4,
				LIST.position.y - 1,
				"mini",
				Menu.FADED,
				false,
				true,
				true
			)
		if _scroll + SHOWN < _count():
			HUD.text(
				c, "MORE", LIST.end.x - 4, LIST.end.y - 7, "mini", Menu.FADED, false, true, true
			)
		match UserMapPlay.row:
			0:
				_draw_new(c)
			1:
				shelf.draw_shelf_row(c)
			2:
				shelf.draw_code(c, UserMapPlay.action)
			_:
				if entry.is_empty():
					_draw_new(c)
				else:
					_draw_entry(c, entry)
	var line := UserMapPlay.note
	if line == "":
		line = shelf.state if shelf.open else _hint(entry)
	var lines := PixelType.wrap(line, 292, "mini")
	for k in mini(2, lines.size()):
		HUD.text(
			c,
			lines[k],
			160,
			NOTE_Y + k * 6,
			"mini",
			HUD.AMBER if UserMapPlay.note != "" else Menu.FADED,
			true
		)
	if shelf.open:
		LobbyScreens.footer(
			c, "ARROWS PICK   ENTER GO   PGUP PGDN PAGE   ESC BACK", "TAP A MAP, THEN TAKE IT HOME"
		)
	else:
		LobbyScreens.footer(
			c, "ARROWS PICK   ENTER GO   N NEW   ESC BACK", "TAP A MAP, THEN WHAT TO DO WITH IT"
		)
	LobbyScreens.back_button(c)


func _hint(entry: Dictionary) -> String:
	match UserMapPlay.row:
		1:
			return "BROWSE THE COUNTY SERVER'S SHELF OF PLAYER MAPS."
		2:
			return "A SHELF CODE, OR A LONG CODE A FRIEND SENT. CTRL+V PASTES ONE ANYWHERE HERE."
	if entry.is_empty():
		return "THE MAP SHED: PAINT GROUND AND WALLS, DROP IN HANDS AND LOOT, TEST IT, SAVE IT."
	var list := _actions()
	var what := str(list[clampi(UserMapPlay.action, 0, list.size() - 1)])
	var why := UserMapPlay.why_not(entry, what) if what != "continue" else ""
	if why != "":
		return why
	var map: Dictionary = entry["map"]
	var note := str(map.get("note", ""))
	if note != "" and what in ["solo", "continue", "edit"]:
		return note
	match what:
		"continue":
			return "PICK UP YOUR SAVE ON THIS MAP."
		"solo":
			return "THROW THE BIG LEVER, THEN GET TO THE TRUCK. F6 SAVES, F9 LOADS."
		"bomb":
			return "YOU AND FOUR BOTS AGAINST FIVE. PLANT THE SHINE BOMB OR STOP IT."
		"hostage":
			return "YOU AND FOUR BOTS AGAINST FIVE. CARRY A HOSTAGE OUT."
		"county":
			return "THE HORDE COMES FROM EVERY ROAD. HOW LONG CAN YA LAST?"
		"host":
			return "YOUR OWN LOBBY ON THIS MAP. EVERYBODY WHO JOINS GETS A COPY."
		"share":
			return "COPY ITS CODE FOR A FRIEND; PRESS AGAIN TO PUT IT ON THE SHELF."
		"edit":
			return "OPEN IT IN THE MAP SHED."
		"remove":
			return "THROW YOUR MAP IN THE BURN BARREL."
	return ""


func _draw_row(c: Canvas, i: int) -> void:
	var r := _row_rect(i)
	var here := i == UserMapPlay.row
	if here:
		c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT)
		Menu.shell(c, r.position.x + 2, r.position.y + 5)
	var x := r.position.x + 15
	if i < FIRST:
		var first: Array = [
			["+ NEW MAP", "OPEN THE MAP SHED"],
			["THE MAP SHELF", "OTHER FOLKS' MAPS, ONLINE"],
			["ENTER A CODE", "A SHELF CODE OR A LONG ONE"],
		][i]
		HUD.text(c, str(first[0]), x, r.position.y + 1, "body", HUD.AMBER if here else HUD.INK)
		HUD.text(c, str(first[1]), x, r.position.y + 9, "mini", LobbyScreens.SOFT)
		return
	var entry: Dictionary = UserMapPlay.entries[i - FIRST]
	var source := str(entry["source"])
	if entry.has("error"):
		HUD.text(
			c,
			str(entry["stem"]).to_upper().replace("_", " ").left(18),
			x,
			r.position.y + 1,
			"body",
			HUD.DIM
		)
		HUD.text(c, "WON'T LOAD", x, r.position.y + 9, "mini", LobbyScreens.RED)
		return
	var map: Dictionary = entry["map"]
	var name := str(map["name"])
	while PixelType.text_width(name, "body") > r.size.x - 18 and name.length() > 4:
		name = name.left(name.length() - 1)
	HUD.text(c, name, x, r.position.y + 1, "body", HUD.AMBER if here else HUD.INK)
	var tag := str({"mine": "YOURS", "example": "EXAMPLE", "shared": "SHARED"}.get(source, ""))
	var by := str(map["author"])
	var second := "%s  %dX%d" % [tag, UserMap.width(map), UserMap.height(map)]
	if by != "" and source != "mine":
		second = "BY %s" % by
	HUD.text(
		c, second, x, r.position.y + 9, "mini", Menu.FADED if source != "example" else Menu.BRASS
	)


func _draw_new(c: Canvas) -> void:
	var x := PANEL.position.x + 6
	HUD.text(c, "THE MAP SHED", x, PANEL.position.y + 5, "menu", HUD.AMBER)
	var lines := PixelType.wrap(" ".join(SHED_TEXT), PANEL.size.x - 12, "mini")
	for k in lines.size():
		HUD.text(c, lines[k], x, PANEL.position.y + 20 + k * 7, "mini", LobbyScreens.SOFT)
	var r := _shed_rect()
	c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT)
	Menu.shell(c, r.position.x + 2, r.position.y + 2)
	var go := "TAP: TO THE SHED" if main.input_device == "touch" else "ENTER: TO THE SHED"
	HUD.text(c, go, r.position.x + 15, r.position.y + 1, "body", HUD.AMBER)


func _draw_entry(c: Canvas, entry: Dictionary) -> void:
	if entry.has("error"):
		HUD.text(
			c,
			"THIS ONE WON'T LOAD",
			PANEL.position.x + 6,
			PANEL.position.y + 5,
			"body",
			LobbyScreens.RED
		)
		var lines := PixelType.wrap(str(entry["error"]), PANEL.size.x - 12, "mini")
		for k in lines.size():
			HUD.text(
				c,
				lines[k],
				PANEL.position.x + 6,
				PANEL.position.y + 16 + k * 7,
				"mini",
				LobbyScreens.SOFT
			)
		HUD.text(
			c,
			str(entry["path"]).get_file().to_upper().replace("_", " ").left(28),
			PANEL.position.x + 6,
			PANEL.end.y - 10,
			"mini",
			Menu.FADED
		)
		return
	var map: Dictionary = entry["map"]
	var key := str(entry.get("hash", ""))
	if key != _picture_of:
		var px := maxi(
			1, mini(PICTURE.size.x / UserMap.width(map), PICTURE.size.y / UserMap.height(map))
		)
		_picture = MapPicture.image(main.art, map, px)
		_picture_of = key
		_holder["version"] = key
	var size := _picture.get_size()
	var at := PICTURE.position + (PICTURE.size - size) / 2
	c.fill_rect(at.x - 1, at.y - 1, size.x + 2, size.y + 2, Menu.DARK)
	MapPicture.blit(c, _picture, Rect2i(Vector2i.ZERO, size), at, _holder)
	var px := maxi(1, size.x / UserMap.width(map))
	for v: Variant in map["things"]:
		var t: Array = v
		var tx: int = t[2]
		var ty: int = t[3]
		if str(t[0]) == "mark" or px >= 3:
			var facing: int = t[4]
			MapPicture.icon(
				c,
				str(t[0]),
				str(t[1]),
				at.x + tx * px + px / 2,
				at.y + ty * px + px / 2,
				maxi(3, px),
				facing
			)
	var list := _actions()
	var modes := UserMap.modes(map)
	_action_top = clampi(
		_action_top, maxi(0, UserMapPlay.action - ACTIONS_SHOWN + 1), UserMapPlay.action
	)
	for i in range(_action_top, mini(list.size(), _action_top + ACTIONS_SHOWN)):
		var what := str(list[i])
		var r := _action_rect(i)
		var here := i == UserMapPlay.action
		if here:
			c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT)
		var label := _action_name(what)
		var why := UserMapPlay.why_not(entry, what) if what not in ["continue", "share"] else ""
		var ink := HUD.AMBER if here else (HUD.INK if why == "" else HUD.DIM)
		if what == "remove" and UserMapPlay.armed and here:
			label = "THROW IT OUT? SURE?"
			ink = LobbyScreens.RED
		if what == "share" and shelf.armed == key and here:
			label = "PUT IT ON THE SHELF?"
		HUD.text(c, label, r.position.x + 3, r.position.y + 1, "mini", ink)
		var right := ""
		var right_ink := GREEN
		if modes.has(what) or what == "host":
			right = "READY" if why == "" else "NOT YET"
			right_ink = GREEN if why == "" else Menu.RUST_HOT
		elif what == "share" and shelf.codes.has(key):
			right = ShareCode.shown(str(shelf.codes[key]))
			right_ink = Menu.BRASS
		if right != "":
			HUD.text(c, right, r.end.x - 3, r.position.y + 1, "mini", right_ink, false, true, true)
	var more_x := PANEL.end.x - 4
	if _action_top > 0:
		HUD.text(c, "MORE", more_x, ACTIONS_Y - 7, "mini", Menu.FADED, false, true, true)
	if _action_top + ACTIONS_SHOWN < list.size():
		var low := ACTIONS_Y + (ACTIONS_SHOWN - 1) * ACTION_H + 1
		HUD.text(c, "MORE", more_x, low, "mini", Menu.FADED, false, true, true)


func _action_name(what: String) -> String:
	match what:
		"continue":
			return "CONTINUE YOUR SAVE"
		"share":
			return SHARE_NAME
	return str(UserMapPlay.ACTION_NAMES[what])
