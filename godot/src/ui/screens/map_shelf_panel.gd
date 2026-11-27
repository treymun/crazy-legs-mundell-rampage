## CUSTOM MAPS' sharing (custom_maps_screen.gd draws and hands keys here):
## THE MAP SHELF (the lobby server's, map_shelf.gd: a page at a time, newest
## or most taken first, or by name; TAKE IT HOME keeps one with the maps
## lobbies sent and picks it on the list, where PLAY and HOST ONLINE are),
## ENTER A CODE (a shelf code typed, or a long code typed or pasted:
## ShareCode), and a map's SHARE IT (its long code copied; again, it goes on
## the shelf and its short code is copied). The shelf's knocks are
## ShelfLink's, polled every frame by the screen.
class_name MapShelfPanel
extends RefCounted

## The shelf's own actions, in the order the buttons show.
const ACTIONS := ["take", "sort", "find", "more", "back"]
const ACTION_NAMES := {
	"take": "TAKE IT HOME",
	"find": "FIND BY NAME",
	"more": "NEXT PAGE",
	"back": "BACK TO YOUR MAPS",
}
## The long code's letters a field takes (as typed: their case is the code's).
const CODE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_:"

var screen: CustomMapsScreen
## The shelf is shown in place of the list.
var open := false
var rows: Array = []
var page := 0
var pages := 1
var count := 0
var sort := "new"
var find := ""
var row := 0
var action := 0
## What the shelf's state line says (asking, not answering, empty).
var state := ""
## The field being typed in ("" none, "code", "find") and what it holds.
var typing := ""
var text := ""
## SHARE IT pressed once on this map's hash: the next press puts it up.
var armed := ""
## Shelf codes this session learned, by map hash (shown on the map's panel).
var codes := {}
var _link: ShelfLink = null
var _asked := ""
## The hash of the map being put up.
var _putting := ""


func _init(owner: CustomMapsScreen) -> void:
	screen = owner


func busy() -> bool:
	return _link != null


func poll(now_ms: float) -> void:
	if _link == null:
		return
	_link.poll(now_ms)
	if _link.busy():
		return
	var link := _link
	_link = null
	if link.state == "failed":
		if _asked == "list":
			state = link.why
			rows = []
		else:
			_say(link.why, false)
		return
	match _asked:
		"list":
			_listed(link.answer)
		"get":
			var got := NetMaps.unpack(link.answer)
			if got.has("error"):
				_say(str(got["error"]), false)
			else:
				var map: Dictionary = got["map"]
				_keep(map, str(link.answer.get("code", "")))
		"put":
			var code := str(link.answer.get("code", ""))
			var fresh: bool = link.answer.get("new", true) == true
			codes[_putting] = code
			armed = ""
			DisplayServer.clipboard_set(ShareCode.shown(code))
			_say(
				(
					"%s ON THE SHELF. ITS CODE IS %s (COPIED): ANYBODY CAN ENTER IT."
					% ["IT'S" if fresh else "IT WAS ALREADY", ShareCode.shown(code)]
				),
				true
			)


func _say(line: String, good: bool) -> void:
	UserMapPlay.note = line
	if screen.main != null:
		screen.main.sound.play("menu_accept" if good else "empty")


# ------------------------------------------------------------------ the shelf


func open_shelf() -> void:
	open = true
	row = 0
	action = 0
	page = 0
	UserMapPlay.note = ""
	ask()


## The shelf asked for the page again (R, a sort, a find, a page turned).
func ask() -> void:
	if _link != null:
		_link.close()
	rows = []
	state = "ASKING THE SHELF..."
	_asked = "list"
	_link = ShelfLink.list(sort, find, page)


func close_shelf() -> void:
	open = false
	typing = ""
	if _link != null and _asked == "list":
		_link.close()
		_link = null


func _listed(answer: Dictionary) -> void:
	var got: Variant = answer.get("rows", [])
	var said: Array = got if got is Array else []
	rows = []
	for v: Variant in said:
		if v is Array:
			var one: Array = v
			if one.size() >= 9:
				rows.append(one)
	page = MapShelf._int(answer, "page", 0)
	pages = maxi(1, MapShelf._int(answer, "pages", 1))
	count = MapShelf._int(answer, "count", rows.size())
	row = clampi(row, 0, maxi(0, rows.size() - 1))
	if rows.is_empty():
		state = "NOTHING BY THAT NAME ON THE SHELF." if find != "" else "NOTHING ON THE SHELF YET."
	else:
		var maps := "%d MAP%s" % [count, "" if count == 1 else "S"]
		state = "PAGE %d OF %d: %s%s" % [page + 1, pages, maps, _sort_said()]
	screen.main.sound.play("menu_move")


func _sort_said() -> String:
	var by := ", NEWEST FIRST" if sort == "new" else ", MOST TAKEN FIRST"
	return by + (", NAMES WITH %s" % find if find != "" else "")


func label(what: String) -> String:
	if what == "sort":
		return "MOST TAKEN FIRST" if sort == "new" else "NEWEST FIRST"
	return str(ACTION_NAMES.get(what, what))


## A shelf action: "" or why not.
func shelf_do(what: String) -> String:
	match what:
		"take":
			if rows.is_empty():
				return "NOTHING PICKED ON THE SHELF."
			var picked: Array = rows[row]
			fetch(str(picked[0]))
		"sort":
			sort = "took" if sort == "new" else "new"
			page = 0
			row = 0
			ask()
		"find":
			start_typing("find")
		"more":
			page = (page + 1) % pages
			row = 0
			ask()
		"back":
			close_shelf()
	return ""


## Keys on the shelf (true: taken).
func shelf_key(code: int) -> bool:
	match code:
		KEY_UP, KEY_W:
			row = posmod(row - 1, maxi(1, rows.size()))
		KEY_DOWN, KEY_S:
			row = posmod(row + 1, maxi(1, rows.size()))
		KEY_LEFT, KEY_A:
			action = posmod(action - 1, ACTIONS.size())
		KEY_RIGHT, KEY_D:
			action = posmod(action + 1, ACTIONS.size())
		KEY_PAGEDOWN:
			shelf_do("more")
			return true
		KEY_PAGEUP:
			page = posmod(page - 1, pages)
			row = 0
			ask()
			return true
		KEY_R:
			ask()
			return true
		KEY_F:
			start_typing("find")
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			var why := shelf_do(str(ACTIONS[action]))
			if why != "":
				_say(why, false)
			return true
		_:
			return false
	screen.main.sound.play("menu_move")
	return true


# ------------------------------------------------------------------ codes


## A shelf code's map asked for.
func fetch(code: String) -> void:
	if _link != null:
		_link.close()
	_asked = "get"
	UserMapPlay.note = "ASKING THE SHELF FOR %s..." % ShareCode.shown(code)
	_link = ShelfLink.fetch(code)


## A typed or pasted code: a long one read here, a short one asked of the shelf.
func take_code(typed: String) -> void:
	var t := typed.strip_edges()
	if t == "":
		_say("TYPE OR PASTE A CODE FIRST.", false)
	elif ShareCode.is_long(t):
		var got := ShareCode.from_long(t)
		if got.has("error"):
			_say(str(got["error"]), false)
		else:
			var map: Dictionary = got["map"]
			_keep(map, "")
	elif ShareCode.clean_short(t) == "":
		_say("THAT AIN'T A CODE: A SHELF CODE IS 8 LETTERS LIKE 7KQ2-M9XD.", false)
	else:
		fetch(ShareCode.clean_short(t))


func paste_code() -> void:
	take_code(DisplayServer.clipboard_get())


## A map that came by code or off the shelf: kept with the ones lobbies sent
## (unless the list has it already) and picked on the list.
func _keep(map: Dictionary, code: String) -> void:
	var hash := UserMap.hash_of(map)
	if code != "":
		codes[hash] = code
	var had := not UserMaps.find(hash).is_empty()
	if not had:
		UserMaps.keep_shared(map)
	UserMapPlay.refresh()
	close_shelf()
	screen.pick_hash(hash)
	_say(
		(
			"%s %s. PLAY IT OR HOST IT RIGHT HERE."
			% [map["name"], "IS ON YOUR LIST ALREADY" if had else "IS ON YOUR LIST NOW"]
		),
		true
	)


## SHARE IT on a list entry: the long code copied; pressed again, the map put
## on the shelf.
func share(entry: Dictionary) -> String:
	var map: Dictionary = entry["map"]
	var hash := UserMap.hash_of(map)
	if armed != hash:
		DisplayServer.clipboard_set(ShareCode.long_of(map))
		armed = hash
		var again := "TAP" if screen.main.input_device == "touch" else "ENTER"
		UserMapPlay.note = (
			"LONG CODE COPIED FOR A FRIEND. %s AGAIN PUTS IT ON THE COUNTY SHELF." % again
		)
		screen.main.sound.play("menu_accept")
		return ""
	var words := ShareCode.words_ok(map)
	if words != "":
		return words
	if UserMap.hosts(map).is_empty():
		return "THE SHELF TAKES MAPS THAT HOST SOMETHING: PUT YOUR START DOWN FIRST."
	if _link != null:
		return "HOLD ON, THE SHELF IS STILL ANSWERING."
	_asked = "put"
	_putting = hash
	UserMapPlay.note = "PUTTING IT ON THE SHELF..."
	_link = ShelfLink.put(map)
	screen.main.sound.play("menu_accept")
	return ""


# ------------------------------------------------------------------ typing


func start_typing(field: String) -> void:
	typing = field
	text = find if field == "find" else ""
	screen.main.sound.play("menu_accept")
	var title := "FIND BY NAME" if field == "find" else "A SHELF CODE OR A LONG CODE"
	if WebTyping.ask(screen.main, title, text, true):
		return  # a phone's browser: its own box, typed in, then ENTER
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(text)


func stop_typing(keep: bool) -> void:
	var field := typing
	typing = ""
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	if not keep:
		return
	if field == "find":
		find = text.strip_edges()
		page = 0
		row = 0
		ask()
	else:
		take_code(text)


## A key while a field is open.
func type_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			stop_typing(true)
			return
		KEY_ESCAPE:
			stop_typing(false)
			return
		KEY_BACKSPACE:
			text = text.left(text.length() - 1)
			return
	if key.ctrl_pressed and key.keycode == KEY_V:
		_add(DisplayServer.clipboard_get())
		return
	var ch := ""
	if key.unicode > 0:
		ch = String.chr(key.unicode)
	elif (
		key.keycode >= KEY_A and key.keycode <= KEY_Z
		or key.keycode >= KEY_0 and key.keycode <= KEY_9
	):
		ch = String.chr(key.keycode)
	elif key.keycode == KEY_SPACE:
		ch = " "
	_add(ch)


## Letters typed or pasted into the field, the ones it takes.
func _add(more: String) -> void:
	var most := (
		ShareCode.number("shelf", "find_most") if typing == "find" else UserMap.limit("bytes") * 2
	)
	for each in more:
		if text.length() >= most:
			return
		var ch := each.to_upper() if typing == "find" else each
		if (UserMap.LETTERS if typing == "find" else CODE_LETTERS).contains(ch):
			text += ch


# ------------------------------------------------------------------ drawing


## The shelf's rows in place of the list.
func draw_list(c: Canvas) -> void:
	var here := Rect2i(CustomMapsScreen.LIST.position + Vector2i(6, 6), Vector2i(120, 8))
	if rows.is_empty():
		var lines := PixelType.wrap(state, CustomMapsScreen.LIST.size.x - 12, "mini")
		for k in lines.size():
			HUD.text(
				c, lines[k], here.position.x, here.position.y + k * 7, "mini", LobbyScreens.SOFT
			)
		return
	for i in rows.size():
		var r := screen.row_rect(i, 0)
		var on := i == row
		if on:
			c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT)
			Menu.shell(c, r.position.x + 2, r.position.y + 5)
		var one: Array = rows[i]
		var name := str(one[1])
		while PixelType.text_width(name, "body") > r.size.x - 18 and name.length() > 4:
			name = name.left(name.length() - 1)
		var x := r.position.x + 15
		HUD.text(c, name, x, r.position.y + 1, "body", HUD.AMBER if on else HUD.INK)
		var by := str(one[2])
		var second := "BY %s" % by if by != "" else "%dX%d" % [_n(one[4]), _n(one[5])]
		HUD.text(c, second, x, r.position.y + 9, "mini", Menu.FADED)


## The picked shelf map's card, and the shelf's own actions.
func draw_panel(c: Canvas) -> void:
	var p := CustomMapsScreen.PANEL
	var x := p.position.x + 6
	HUD.text(c, "THE MAP SHELF", x, p.position.y + 5, "menu", HUD.AMBER)
	var y := p.position.y + 18
	if typing == "find":
		_draw_field(c, "FIND BY NAME", y)
	elif not rows.is_empty():
		var one: Array = rows[row]
		var lines := PackedStringArray()
		var took := _n(one[7])
		lines.append(
			(
				"%dX%d, TAKEN %d TIME%s, PUT UP %s"
				% [_n(one[4]), _n(one[5]), took, "" if took == 1 else "S", one[8]]
			)
		)
		var can := PackedStringArray()
		var hosts: Array = one[6] if one[6] is Array else []
		for mode: Variant in hosts:
			can.append(str(UserMap.MODE_NAMES.get(str(mode), "")))
		lines.append("HOSTS " + ", ".join(can))
		if str(one[3]) != "":
			lines.append(str(one[3]))
		lines.append("CODE " + ShareCode.shown(str(one[0])))
		var at := y
		for line in lines:
			for part in PixelType.wrap(line, p.size.x - 12, "mini"):
				if at < CustomMapsScreen.ACTIONS_Y - 7:
					HUD.text(c, part, x, at, "mini", LobbyScreens.SOFT)
					at += 7
	for i in ACTIONS.size():
		var what := str(ACTIONS[i])
		var r := screen.action_rect(i)
		var on := i == action
		if on:
			c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT)
		var dim := what == "take" and rows.is_empty()
		HUD.text(
			c,
			label(what),
			r.position.x + 3,
			r.position.y + 1,
			"mini",
			HUD.AMBER if on else (HUD.DIM if dim else HUD.INK)
		)


## A field's box with the end of what is typed in it.
func _draw_field(c: Canvas, title: String, y: int) -> void:
	var p := CustomMapsScreen.PANEL
	var x := p.position.x + 6
	HUD.text(c, title, x, y, "mini", LobbyScreens.SOFT)
	var box := Rect2i(x - 2, y + 8, p.size.x - 8, 11)
	LobbyScreens.box(c, box, Menu.DARK)
	var shown := text
	while PixelType.text_width(shown + "_", "body") > box.size.x - 6 and shown.length() > 0:
		shown = shown.substr(1)
	HUD.text(c, shown + "_", x + 1, y + 10, "body", HUD.AMBER)
	var hint := "ENTER TO GO, ESC TO LEAVE IT" if screen.main.input_device != "touch" else ""
	if hint != "":
		HUD.text(c, hint, x, y + 22, "mini", Menu.FADED)


## The ENTER A CODE row's card: what a code is, and the field while typing.
func draw_code(c: Canvas, action_at: int) -> void:
	var p := CustomMapsScreen.PANEL
	var x := p.position.x + 6
	HUD.text(c, "ENTER A CODE", x, p.position.y + 5, "menu", HUD.AMBER)
	if typing == "code":
		_draw_field(c, "THE CODE", p.position.y + 20)
	else:
		var said := (
			"A SHELF CODE IS 8 LETTERS LIKE 7KQ2-M9XD. A LONG CODE STARTS CLMR1: AND"
			+ " HOLDS THE WHOLE MAP: NO SERVER NEEDED. EITHER WAY THE MAP LANDS ON YOUR LIST."
		)
		var lines := PixelType.wrap(said, p.size.x - 12, "mini")
		for k in lines.size():
			HUD.text(c, lines[k], x, p.position.y + 20 + k * 7, "mini", LobbyScreens.SOFT)
	var plates := ["TYPE A CODE", "PASTE A CODE"]
	for i in plates.size():
		_plate(c, screen.plate_rect(i), str(plates[i]), i == action_at)


## The MAP SHELF row's card.
func draw_shelf_row(c: Canvas) -> void:
	var p := CustomMapsScreen.PANEL
	var x := p.position.x + 6
	HUD.text(c, "THE MAP SHELF", x, p.position.y + 5, "menu", HUD.AMBER)
	var said := (
		"OTHER FOLKS' MAPS ON THE COUNTY SERVER, NEWEST OR MOST TAKEN FIRST."
		+ " TAKE ONE HOME, THEN PLAY IT OR HOST IT. SHARE IT ON ONE OF YOURS PUTS IT UP."
	)
	var lines := PixelType.wrap(said, p.size.x - 12, "mini")
	for k in lines.size():
		HUD.text(c, lines[k], x, p.position.y + 20 + k * 7, "mini", LobbyScreens.SOFT)
	var go := "TAP: TO THE SHELF" if screen.main.input_device == "touch" else "ENTER: TO THE SHELF"
	_plate(c, screen.plate_rect(1), go, true)


## A number in a shelf row (0 when it is not one).
static func _n(v: Variant) -> int:
	return MapShelf._int({"v": v}, "v", 0)


func _plate(c: Canvas, r: Rect2i, words: String, on: bool) -> void:
	c.fill_rect(
		r.position.x, r.position.y, r.size.x, r.size.y, LobbyScreens.LIT if on else Menu.DARK
	)
	if on:
		Menu.shell(c, r.position.x + 2, r.position.y + 2)
	HUD.text(c, words, r.position.x + 15, r.position.y + 1, "body", HUD.AMBER if on else HUD.INK)
