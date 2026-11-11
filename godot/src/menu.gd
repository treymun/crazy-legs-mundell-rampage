## The front end's layout and drawing: the title screen and the settings pages.
##
## Everything a screen shows is described once, as rectangles in the game's own
## 320x200 space, and both the renderer and the pointer hit tests read the same
## description. A row can never be drawn in one place and clicked in another.
##
## main.gd owns the state (which entry or setting is selected, the options
## themselves); this file only turns that state into pixels and back.
class_name Menu
extends RefCounted

# ---- title screen -----------------------------------------------------------
const BOARD := Rect2i(6, 84, 180, 114)
const PRIMARY := Rect2i(12, 97, 168, 17)
const COLUMN_X := [12, 98]
const COLUMN_W := 82
const ROWS_Y := 125
const ROW_H := 11
const PRIMARY_IDS := ["RESUME", "CONTINUE CAMPAIGN"]
## Left column: getting into the game. Right column: everything around it.
const OFFICE_IDS := ["SAVE SLOTS", "SETUP", "CONTROLS", "CREDITS", "QUIT"]
const LABELS := {"SAVE SLOTS": "LOAD / SAVE", "SETUP": "SETTINGS"}

# ---- settings ---------------------------------------------------------------
const SIGN := Rect2i(12, 9, 296, 20)
const TABS_Y := 32
const TAB_H := 13
const LIST := Rect2i(20, 48, 276, 96)
const SET_ROW := 12
const VISIBLE_ROWS := 8
const CONTROL_X := 172
const FOOTER_Y := 147
const BACK := Rect2i(254, 177, 46, 13)
const RESET := Rect2i(20, 177, 78, 13)
const SCROLL_UP := Rect2i(298, 48, 8, 12)
const SCROLL_DOWN := Rect2i(298, 132, 8, 12)
## Settings that only matter from the next run or chapter on.
const NEXT_RUN := {
	"supply_rule": "APPLIES TO YOUR NEXT RUN",
	"classic": "APPLIES WHEN A CHAPTER ENDS",
	"difficulty": "CHANGES THE RUN IN PROGRESS",
}

const PAINT := Color(236 / 255.0, 220 / 255.0, 186 / 255.0)
const FADED := Color(176 / 255.0, 150 / 255.0, 112 / 255.0)
const RUST := Color(150 / 255.0, 66 / 255.0, 30 / 255.0)
const RUST_HOT := Color(196 / 255.0, 96 / 255.0, 40 / 255.0)
const DARK := Color(26 / 255.0, 18 / 255.0, 13 / 255.0)
const TIN_INK := Color(30 / 255.0, 22 / 255.0, 18 / 255.0)

var art: Assets


func _init(p_art: Assets) -> void:
	art = p_art


func _blit(c: Canvas, name: String, x: int, y: int) -> void:
	var sheet := art.art(name)
	c.blit_rgba(sheet["data"], int(sheet["w"]), int(sheet["h"]), x, y, "art|" + name)


# ------------------------------------------------------------------ title


## One dictionary per entry, in the order main.entries() gives them:
## {id, label, rect, primary, column, row}.
static func title_items(entries: PackedStringArray) -> Array:
	var items: Array = []
	var first := String(entries[0]) if entries.size() > 0 else ""
	var primary := first if PRIMARY_IDS.has(first) else "NEW GAME"
	var counts := [0, 0]
	for id: String in entries:
		var item := {"id": id, "label": String(LABELS.get(id, id)), "primary": id == primary}
		if id == primary:
			item["rect"] = PRIMARY
			item["column"] = -1
			item["row"] = -1
		else:
			var column := 1 if OFFICE_IDS.has(id) else 0
			item["column"] = column
			item["row"] = counts[column]
			item["rect"] = Rect2i(
				int(COLUMN_X[column]), ROWS_Y + ROW_H * int(counts[column]), COLUMN_W, ROW_H
			)
			counts[column] += 1
		items.append(item)
	return items


## The entry under a point of the 320x200 picture, or -1.
static func title_hit(entries: PackedStringArray, x: int, y: int) -> int:
	var items := title_items(entries)
	for i in items.size():
		if (items[i]["rect"] as Rect2i).has_point(Vector2i(x, y)):
			return i
	return -1


## Where the cursor goes for an arrow key. Up and down walk the list in order;
## left and right cross between the two columns on the same row.
static func title_move(entries: PackedStringArray, index: int, dx: int, dy: int) -> int:
	var items := title_items(entries)
	if items.is_empty():
		return 0
	index = posmod(index, items.size())
	if dy != 0:
		return posmod(index + dy, items.size())
	var here: Dictionary = items[index]
	# Left only leaves the right column, right only the left one.
	if int(here["column"]) < 0 or int(here["column"]) == (1 if dx > 0 else 0):
		return index
	var best := index
	var gap := 99
	for i in items.size():
		var other: Dictionary = items[i]
		if int(other["column"]) >= 0 and int(other["column"]) != int(here["column"]):
			var distance := absi(int(other["row"]) - int(here["row"]))
			if distance < gap:
				gap = distance
				best = i
	return best


## `clock` drives the saucer and the lamp; `motion` is SCENERY MOTION (2 = still)
## and `steady` is true when flashes or lamp flicker are turned down.
func draw_title(
	c: Canvas,
	entries: PackedStringArray,
	selection: int,
	note: String,
	hint: String,
	clock: float,
	motion: int,
	steady: bool
) -> void:
	_blit(c, "title_backdrop", 0, 0)
	if motion != 2:
		var pace := 5.0 if motion == 0 else 2.0
		var sx := int(fposmod(clock * pace + 250.0, 380.0)) - 30
		var sy := 12 + int(roundf(sin(clock * .6) * 2.0))
		_blit(c, "menu_saucer", sx, sy)
	else:
		_blit(c, "menu_saucer", 258, 12)
	_blit(c, "menu_wanted", 278, 96)
	_blit(c, "menu_bessie", 190, 152)
	_blit(c, "menu_board", BOARD.position.x, BOARD.position.y)
	# The yard lamp: steady when flashes or flicker are turned down.
	var lit := true
	if not steady:
		var beat := int(clock * 9.0)
		lit = not (beat % 37 == 0 or beat % 53 == 1)
	if lit:
		_blit(c, "menu_glow", BOARD.position.x - 4, BOARD.position.y - 4)
	_blit(c, "title_logo", 6, 2)
	HUD.text(c, "THE HICKSTON INCIDENT", 14, 88, "body", HUD.AMBER, false, true)
	var items := title_items(entries)
	selection = posmod(selection, maxi(1, items.size()))
	HUD.text(c, "HIT THE ROAD", int(COLUMN_X[0]) + 2, 117, "mini", FADED, false, false)
	HUD.text(c, "COUNTY OFFICE", int(COLUMN_X[1]) + 2, 117, "mini", FADED, false, false)
	c.line(12, 123, 179, 123, Color(52 / 255.0, 36 / 255.0, 24 / 255.0))
	for i in items.size():
		var item: Dictionary = items[i]
		var rect: Rect2i = item["rect"]
		var active := i == selection
		if bool(item["primary"]):
			_plate(c, rect, active)
			var label := String(item["label"])
			var style := (
				"heading" if PixelType.text_width(label, "heading") < rect.size.x - 16 else "menu"
			)
			var top := rect.position.y + (2 if style == "heading" else 4)
			HUD.text(
				c,
				label,
				rect.position.x + rect.size.x / 2,
				top,
				style,
				HUD.INK if active else PAINT,
				true
			)
		else:
			if active:
				c.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y - 1, RUST)
				c.line(
					rect.position.x,
					rect.position.y,
					rect.position.x + rect.size.x - 1,
					rect.position.y,
					RUST_HOT
				)
				HUD.text(c, ">", rect.position.x + 2, rect.position.y + 2, "body", HUD.AMBER)
			HUD.text(
				c,
				String(item["label"]),
				rect.position.x + 9,
				rect.position.y + 2,
				"body",
				HUD.INK if active else PAINT
			)
	var footer := note if note != "" else hint
	c.line(12, 183, 179, 183, Color(52 / 255.0, 36 / 255.0, 24 / 255.0))
	var lines := PixelType.wrap(footer, 164, "mini")
	for i in mini(2, lines.size()):
		HUD.text(
			c, lines[i], 96, 186 + i * 6, "mini", HUD.AMBER if note != "" else PAINT, true, false
		)


## The big painted plate the main action sits on.
func _plate(c: Canvas, rect: Rect2i, active: bool) -> void:
	var face := RUST_HOT if active else RUST
	c.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, DARK)
	c.fill_rect(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, rect.size.y - 2, face)
	c.line(
		rect.position.x + 1,
		rect.position.y + 1,
		rect.position.x + rect.size.x - 2,
		rect.position.y + 1,
		Color(232 / 255.0, 150 / 255.0, 84 / 255.0)
	)
	c.line(
		rect.position.x + 1,
		rect.position.y + rect.size.y - 2,
		rect.position.x + rect.size.x - 2,
		rect.position.y + rect.size.y - 2,
		Color(92 / 255.0, 38 / 255.0, 18 / 255.0)
	)
	if active:
		HUD.text(c, ">", rect.position.x + 5, rect.position.y + 5, "body", HUD.INK)
		HUD.text(c, "<", rect.position.x + rect.size.x - 9, rect.position.y + 5, "body", HUD.INK)


# ------------------------------------------------------------- sub-screens


## The frame every sub-screen shares: dimmed yard, timber, rusted header.
func draw_sheet(c: Canvas, heading: String) -> void:
	_blit(c, "menu_sheet", 0, 0)
	_blit(c, "menu_sign", SIGN.position.x, SIGN.position.y)
	HUD.text(c, heading, 160, SIGN.position.y + 4, "heading", TIN_INK, true, false)


static func plate_button(c: Canvas, rect: Rect2i, label: String, hot := false) -> void:
	c.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, DARK)
	c.fill_rect(
		rect.position.x + 1,
		rect.position.y + 1,
		rect.size.x - 2,
		rect.size.y - 2,
		RUST_HOT if hot else Color(88 / 255.0, 56 / 255.0, 34 / 255.0)
	)
	HUD.text(c, label, rect.position.x + rect.size.x / 2, rect.position.y + 3, "body", PAINT, true)


# --------------------------------------------------------------- settings


static func tab_rect(index: int, count: int) -> Rect2i:
	var width := LIST.size.x / maxi(1, count)
	return Rect2i(LIST.position.x + width * index, TABS_Y, width - 2, TAB_H)


## The row a setting occupies while the list is scrolled to `scroll`, or an
## empty rectangle when it is off screen.
static func row_rect(slot: int, scroll: int) -> Rect2i:
	var shown := slot - scroll
	if shown < 0 or shown >= VISIBLE_ROWS:
		return Rect2i()
	return Rect2i(LIST.position.x, LIST.position.y + shown * SET_ROW, LIST.size.x, SET_ROW)


## Keep the selected row inside the window.
static func scroll_for(slot: int, scroll: int, count: int) -> int:
	scroll = clampi(scroll, maxi(0, slot - VISIBLE_ROWS + 1), slot)
	return clampi(scroll, 0, maxi(0, count - VISIBLE_ROWS))


## What a point on the settings screen means:
## {kind: "tab"|"row"|"back"|"reset"|"up"|"down"|"", index, direction}.
## `direction` is -1 or +1 on a row's control, 0 on its label.
static func setup_hit(x: int, y: int, pages: int, count: int, scroll: int) -> Dictionary:
	var point := Vector2i(x, y)
	for i in pages:
		if tab_rect(i, pages).has_point(point):
			return {"kind": "tab", "index": i, "direction": 0}
	if BACK.has_point(point):
		return {"kind": "back", "index": 0, "direction": 0}
	if RESET.has_point(point):
		return {"kind": "reset", "index": 0, "direction": 0}
	if count > VISIBLE_ROWS:
		if SCROLL_UP.has_point(point):
			return {"kind": "up", "index": 0, "direction": 0}
		if SCROLL_DOWN.has_point(point):
			return {"kind": "down", "index": 0, "direction": 0}
	if LIST.has_point(point):
		var slot := scroll + (y - LIST.position.y) / SET_ROW
		if slot < count:
			var direction := 0
			if x >= CONTROL_X:
				direction = -1 if x < CONTROL_X + (LIST.end.x - CONTROL_X) / 2 else 1
			return {"kind": "row", "index": slot, "direction": direction}
	return {"kind": "", "index": 0, "direction": 0}


static func is_toggle(item: SessionStore.Setting) -> bool:
	return item.choices.size() == 2 and String(item.choices[0]) == "OFF"


func draw_setup(
	c: Canvas,
	pages: Array,
	page: int,
	slot: int,
	scroll: int,
	options: Dictionary,
	note: String,
	guide: String,
	confirm: String
) -> void:
	draw_sheet(c, "SETTINGS")
	for j in pages.size():
		var tab := tab_rect(j, pages.size())
		var on := j == page
		c.fill_rect(
			tab.position.x,
			tab.position.y,
			tab.size.x,
			tab.size.y,
			RUST if on else Color(48 / 255.0, 34 / 255.0, 26 / 255.0)
		)
		c.line(
			tab.position.x,
			tab.position.y,
			tab.position.x + tab.size.x - 1,
			tab.position.y,
			RUST_HOT if on else Color(92 / 255.0, 66 / 255.0, 48 / 255.0)
		)
		HUD.text(
			c,
			String(pages[j][0]),
			tab.position.x + tab.size.x / 2,
			tab.position.y + 3,
			"body",
			HUD.INK if on else FADED,
			true
		)
	var items: Array = pages[page][1]
	c.fill_rect(
		LIST.position.x,
		LIST.position.y,
		LIST.size.x,
		LIST.size.y,
		Color(22 / 255.0, 15 / 255.0, 12 / 255.0)
	)
	for j in items.size():
		var row := row_rect(j, scroll)
		if row.size.y == 0:
			continue
		var item: SessionStore.Setting = items[j]
		var on := j == slot
		var face := (
			Color(34 / 255.0, 24 / 255.0, 19 / 255.0)
			if j % 2 == 0
			else Color(41 / 255.0, 29 / 255.0, 23 / 255.0)
		)
		if on:
			face = Color(96 / 255.0, 52 / 255.0, 28 / 255.0)
		c.fill_rect(row.position.x, row.position.y, row.size.x, row.size.y, face)
		if on:
			c.line(row.position.x, row.position.y, row.end.x - 1, row.position.y, RUST_HOT)
			HUD.text(c, ">", row.position.x + 2, row.position.y + 3, "body", HUD.AMBER)
		HUD.text(
			c, item.label, row.position.x + 10, row.position.y + 3, "body", HUD.INK if on else PAINT
		)
		_control(c, item, int(options[item.key]), row, on)
	if items.size() > VISIBLE_ROWS:
		_scrollbar(c, scroll, items.size())
	# Footer: what the selected setting does, when it applies, how to drive it.
	c.line(
		LIST.position.x,
		FOOTER_Y - 2,
		LIST.end.x - 1,
		FOOTER_Y - 2,
		Color(113 / 255.0, 80 / 255.0, 54 / 255.0)
	)
	var current: SessionStore.Setting = items[slot]
	var lines := PixelType.wrap(note if note != "" else current.hint, LIST.size.x - 4)
	for i in mini(2, lines.size()):
		HUD.text(
			c, lines[i], 160, FOOTER_Y + 1 + i * 9, "body", HUD.AMBER if note != "" else PAINT, true
		)
	HUD.text(
		c,
		String(NEXT_RUN.get(current.key, "CHANGES RIGHT AWAY")),
		160,
		FOOTER_Y + 20,
		"mini",
		FADED,
		true,
		false
	)
	plate_button(c, RESET, "RESET PAGE")
	plate_button(c, BACK, "BACK")
	HUD.text(c, guide, (RESET.end.x + BACK.position.x) / 2, 181, "mini", PAINT, true, false)
	if confirm != "":
		c.fill_rect(46, 78, 228, 44, DARK)
		c.fill_rect(47, 79, 226, 42, Color(70 / 255.0, 40 / 255.0, 24 / 255.0))
		c.rect_outline(47, 79, 226, 42, RUST_HOT)
		HUD.text(c, "KEEP THIS DISPLAY?", 160, 85, "menu", HUD.INK, true)
		HUD.text(c, confirm, 160, 103, "body", HUD.AMBER, true)


## The right-hand side of a row: a bar for a level, a switch for on/off, a
## bracketed word for a choice.
func _control(c: Canvas, item: SessionStore.Setting, value: int, row: Rect2i, on: bool) -> void:
	var ink := HUD.INK if on else PAINT
	var y := row.position.y
	if item is SessionStore.KeySetting:
		var middle_key := (CONTROL_X + row.end.x) / 2
		HUD.text(c, item.format_value(value), middle_key, y + 3, "body", ink, true)
	elif item.choices.is_empty():
		var x := CONTROL_X + 6
		var width := 78
		c.fill_rect(x, y + 3, width, 6, DARK)
		var share := float(value - item.low) / float(maxi(1, item.high - item.low))
		c.fill_rect(x + 1, y + 4, int(roundf((width - 2) * share)), 4, HUD.AMBER if on else FADED)
		HUD.text(c, item.format_value(value), row.end.x - 4, y + 3, "body", ink, false, true, true)
		if on:
			HUD.text(c, "<", CONTROL_X - 1, y + 3, "body", HUD.AMBER)
	elif is_toggle(item):
		var x2 := CONTROL_X + 34
		c.fill_rect(x2, y + 2, 24, 8, DARK)
		var knob := x2 + 13 if value != item.low else x2 + 1
		c.fill_rect(
			knob,
			y + 3,
			10,
			6,
			Color(120 / 255.0, 190 / 255.0, 90 / 255.0) if value != item.low else FADED
		)
		HUD.text(c, item.format_value(value), x2 + 30, y + 3, "body", ink)
	else:
		var middle := (CONTROL_X + row.end.x) / 2
		HUD.text(c, item.format_value(value), middle, y + 3, "body", ink, true)
		if on:
			HUD.text(c, "<", CONTROL_X - 1, y + 3, "body", HUD.AMBER)
			HUD.text(c, ">", row.end.x - 8, y + 3, "body", HUD.AMBER)


func _scrollbar(c: Canvas, scroll: int, count: int) -> void:
	plate_button(c, SCROLL_UP, "", scroll > 0)
	plate_button(c, SCROLL_DOWN, "", scroll + VISIBLE_ROWS < count)
	var track := Rect2i(
		SCROLL_UP.position.x + 2,
		SCROLL_UP.end.y + 1,
		4,
		SCROLL_DOWN.position.y - SCROLL_UP.end.y - 2
	)
	c.fill_rect(track.position.x, track.position.y, track.size.x, track.size.y, DARK)
	var thumb := maxi(8, track.size.y * VISIBLE_ROWS / count)
	var travel := track.size.y - thumb
	var at := track.position.y + travel * scroll / maxi(1, count - VISIBLE_ROWS)
	c.fill_rect(track.position.x, at, track.size.x, thumb, HUD.AMBER)
	for dx in 3:  # little arrowheads
		c.line(
			SCROLL_UP.position.x + 4 - dx,
			SCROLL_UP.position.y + 4 + dx,
			SCROLL_UP.position.x + 4 + dx,
			SCROLL_UP.position.y + 4 + dx,
			PAINT
		)
		c.line(
			SCROLL_DOWN.position.x + 4 - dx,
			SCROLL_DOWN.position.y + 8 - dx,
			SCROLL_DOWN.position.x + 4 + dx,
			SCROLL_DOWN.position.y + 8 - dx,
			PAINT
		)
