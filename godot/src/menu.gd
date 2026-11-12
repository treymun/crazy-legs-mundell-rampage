## The front end's layout and drawing: the title screen and the settings pages.
##
## Everything a screen shows is described once, as rectangles in the game's own
## 320x200 space, and both the renderer and the pointer hit tests read the same
## description. A row can never be drawn in one place and clicked in another.
##
## main.gd owns the state (which entry or setting is selected, the options
## themselves); this file only turns that state into pixels and back. Every
## shape is a fill_rect, a set_pixel or a named picture, so it draws the same
## in software and on the Godot 2D canvas.
class_name Menu
extends RefCounted

# ---- title screen -----------------------------------------------------------
const BOARD := Rect2i(6, 84, 180, 114)
const PRIMARY := Rect2i(12, 96, 168, 19)
## The barn lamp's shade, bolted over the board's top right.
const LAMP_X := 158
const COLUMN_X := [12, 98]
const COLUMN_W := 82
const ROWS_Y := 125
const ROW_H := 11
const PRIMARY_IDS := ["RESUME", "CONTINUE CAMPAIGN"]
## Left column: getting into the game. Right column: everything around it.
const OFFICE_IDS := ["SAVE SLOTS", "SETUP", "CONTROLS", "CREDITS", "QUIT"]
const LABELS := {"SAVE SLOTS": "LOAD / SAVE", "SETUP": "SETTINGS"}
## One line under the board for the entry the cursor is on.
const BLURBS := {
	"RESUME": "BACK TO THE MAYHEM. IT WAITED FOR YA.",
	"CONTINUE CAMPAIGN": "BACK TO THE CROSSROADS, GUNS AND ALL.",
	"NEW GAME": "HICKSTON AIN'T GONNA SAVE ITSELF.",
	"QUICKLOAD": "BACK TO YER LAST QUICKSAVE.",
	"COUNTY HUB": "THE CROSSROADS. EVERY ROAD STARTS HERE.",
	"REPLAY LEVEL": "RUN A CHAPTER AGAIN FOR THE HELL OF IT.",
	"FIRING RANGE": "EVERY GUN, ALL THE AMMO. GO LEARN 'EM.",
	"LEAVE RANGE": "BACK TO THE TITLE. THE RANGE KEEPS NO SCORE.",
	"SAVE SLOTS": "FOUR NAMED SAVES, APART FROM QUICKSAVE.",
	"SETUP": "TUNE THE MOUSE, SCREEN, SOUND AND KEYS.",
	"CONTROLS": "WHAT EVERY KEY, BUTTON AND TAP DOES.",
	"CREDITS": "WHO TO BLAME FOR ALL THIS.",
	"QUIT": "BACK TO THE REAL WORLD. IT'S WORSE.",
}
## Fireflies over the yard: where each one loiters.
const FIREFLIES := [[198, 104], [222, 60], [250, 46], [298, 56], [308, 126], [206, 138], [272, 36]]

# ---- settings ---------------------------------------------------------------
const SIGN := Rect2i(12, 9, 296, 20)
const TABS_Y := 31
const TAB_H := 13
## The list's frame, and the lines inside it.
const PANEL := Rect2i(14, 44, 292, 103)
const LIST := Rect2i(16, 46, 280, 99)
const SET_ROW := 12
const HEAD_H := 9
## The value column: arrows at its edges, values centred on VALUE_MID.
const VALUE_X := 172
const VALUE_END := 294
const VALUE_MID := 233
const BAR_X := 180
const BAR_W := 80
const LABEL_X := 32
const FOOTER_Y := 147
const HINT := Rect2i(14, 149, 292, 25)
const BACK := Rect2i(246, 177, 60, 13)
const RESET := Rect2i(14, 177, 80, 13)
const SCROLL_UP := Rect2i(298, 46, 7, 9)
const SCROLL_DOWN := Rect2i(298, 136, 7, 9)
const CONFIRM := Rect2i(40, 76, 240, 50)
const CONFIRM_KEEP := Rect2i(56, 96, 96, 14)
const CONFIRM_UNDO := Rect2i(168, 96, 96, 14)
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
const RUST_DEEP := Color(92 / 255.0, 38 / 255.0, 18 / 255.0)
const DARK := Color(26 / 255.0, 18 / 255.0, 13 / 255.0)
const TIN_INK := Color(30 / 255.0, 22 / 255.0, 18 / 255.0)
const BRIGHT := Color(255 / 255.0, 244 / 255.0, 214 / 255.0)
const BRASS := Color(204 / 255.0, 164 / 255.0, 88 / 255.0)
const BRASS_HI := Color(246 / 255.0, 216 / 255.0, 142 / 255.0)
const BRASS_LO := Color(118 / 255.0, 86 / 255.0, 44 / 255.0)
const WOOD_A := Color(34 / 255.0, 24 / 255.0, 19 / 255.0)
const WOOD_B := Color(41 / 255.0, 29 / 255.0, 23 / 255.0)
const WELL := Color(17 / 255.0, 12 / 255.0, 9 / 255.0)
const DIM := Color(108 / 255.0, 80 / 255.0, 58 / 255.0)
const LAMP_ON := Color(150 / 255.0, 226 / 255.0, 96 / 255.0)
const LAMP_ON_HI := Color(228 / 255.0, 255 / 255.0, 196 / 255.0)
const LAMP_OFF := Color(112 / 255.0, 36 / 255.0, 28 / 255.0)
const LAMP_OFF_HI := Color(164 / 255.0, 74 / 255.0, 60 / 255.0)
const HULL := Color(178 / 255.0, 38 / 255.0, 30 / 255.0)
const HULL_HI := Color(232 / 255.0, 96 / 255.0, 72 / 255.0)
const HULL_LO := Color(108 / 255.0, 22 / 255.0, 18 / 255.0)
const BULB_ON := Color(255 / 255.0, 226 / 255.0, 140 / 255.0)
const BULB_OFF := Color(112 / 255.0, 60 / 255.0, 28 / 255.0)
## The county-fair string of lights over every sub-screen.
const FESTOON_POSTS := [10, 85, 160, 235, 310]
const FESTOON_COLOURS := [
	Color(232 / 255.0, 72 / 255.0, 52 / 255.0),
	Color(255 / 255.0, 194 / 255.0, 84 / 255.0),
	Color(124 / 255.0, 212 / 255.0, 92 / 255.0),
	Color(96 / 255.0, 154 / 255.0, 232 / 255.0),
	Color(250 / 255.0, 240 / 255.0, 210 / 255.0),
]

var art: Assets
## The front end's clock and the comfort settings the little motions obey,
## set by main_state.gd before each frame: SCENERY MOTION (0 full, 1 reduced,
## 2 still) and `steady` (SCREEN FLASH or LAMP FLICKER turned down: nothing
## blinks).
var clock := 0.0
var motion := 0
var steady := false

static var _line_cache := {}


func _init(p_art: Assets) -> void:
	art = p_art


func _blit(c: Canvas, name: String, x: int, y: int) -> void:
	var sheet := art.art(name)
	c.blit_rgba(sheet["data"], int(sheet["w"]), int(sheet["h"]), x, y, "art|" + name)


static func _hline(c: Canvas, x: int, y: int, w: int, colour: Color) -> void:
	c.fill_rect(x, y, w, 1, colour)


static func _vline(c: Canvas, x: int, y: int, h: int, colour: Color) -> void:
	c.fill_rect(x, y, 1, h, colour)


## A shotgun shell, the menus' cursor: brass head, red hull, crimped end, in a
## dark outline so it reads on any plank. 11 x 7 with the outline; `left`
## turns it to point left.
static func shell(c: Canvas, x: int, y: int, left := false) -> void:
	c.fill_rect(x - 1, y - 1, 11, 7, DARK)
	var head := x + 6 if left else x
	var hull := x + 1 if left else x + 3
	c.fill_rect(head + (2 if left else 0), y, 1, 5, BRASS_LO)
	c.fill_rect(head + (0 if left else 1), y, 2, 5, BRASS)
	c.fill_rect(head + (0 if left else 1), y, 2, 1, BRASS_HI)
	c.fill_rect(hull, y, 5, 5, HULL)
	c.fill_rect(hull, y, 5, 1, HULL_HI)
	c.fill_rect(hull, y + 4, 5, 1, HULL_LO)
	c.fill_rect(x if left else x + 8, y + 1, 1, 3, HULL_LO)


## A round panel lamp in a brass bezel: green and lit for on, dull red for off.
static func lamp(c: Canvas, cx: int, cy: int, lit: bool) -> void:
	c.circle(cx, cy, 4, BRASS_LO)
	c.circle(cx, cy, 3, DARK)
	c.circle(cx, cy, 2, LAMP_ON if lit else LAMP_OFF)
	c.fill_rect(cx - 1, cy - 1, 1, 1, LAMP_ON_HI if lit else LAMP_OFF_HI)


## Brass rivet heads in a plate's corners.
static func rivets(c: Canvas, rect: Rect2i, inset := 2) -> void:
	for corner: Vector2i in [
		Vector2i(rect.position.x + inset, rect.position.y + inset),
		Vector2i(rect.end.x - 1 - inset, rect.position.y + inset),
		Vector2i(rect.position.x + inset, rect.end.y - 1 - inset),
		Vector2i(rect.end.x - 1 - inset, rect.end.y - 1 - inset),
	]:
		c.fill_rect(corner.x, corner.y, 1, 1, BRASS)


## How far the cursor shell bobs this moment (0 or 1; still on STATIC).
func _nudge() -> int:
	if motion == 2:
		return 0
	return 1 if fposmod(clock * (2.2 if motion == 0 else 1.0), 1.0) < .5 else 0


## Which beat a string of lights is on, or -1 for all of them steadily lit.
func _chase() -> int:
	if motion == 2 or steady:
		return -1
	return int(clock * (6.0 if motion == 0 else 2.0))


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


## `p_clock` drives the saucer, the lamp, the lights and the fireflies;
## `p_motion` is SCENERY MOTION (2 = still) and `p_steady` is true when flashes
## or lamp flicker are turned down.
func draw_title(
	c: Canvas,
	entries: PackedStringArray,
	selection: int,
	note: String,
	hint: String,
	p_clock: float,
	p_motion: int,
	p_steady: bool
) -> void:
	clock = p_clock
	motion = p_motion
	steady = p_steady
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
	_fireflies(c)
	_blit(c, "menu_board", BOARD.position.x, BOARD.position.y)
	# The barn lamp on the board: steady when flashes or flicker are turned down.
	var lit := true
	if not steady:
		var beat := int(clock * 9.0)
		lit = not (beat % 37 == 0 or beat % 53 == 1)
	if lit:
		_blit(c, "menu_glow", LAMP_X - 104, BOARD.position.y - 2)
	rivets(c, BOARD, 1)
	_blit(c, "title_logo", 6, 2)
	_barn_lamp(c, LAMP_X, lit)
	HUD.text(c, "THE HICKSTON INCIDENT", 14, 88, "body", HUD.AMBER, false, true)
	var items := title_items(entries)
	selection = posmod(selection, maxi(1, items.size()))
	HUD.text(c, "HIT THE ROAD", int(COLUMN_X[0]) + 2, 117, "mini", FADED, false, false)
	HUD.text(c, "COUNTY OFFICE", int(COLUMN_X[1]) + 2, 117, "mini", FADED, false, false)
	_hline(c, 12, 123, 168, Color(52 / 255.0, 36 / 255.0, 24 / 255.0))
	_hline(c, 12, 124, 168, Color(120 / 255.0, 88 / 255.0, 58 / 255.0))
	var selected_id := ""
	for i in items.size():
		var item: Dictionary = items[i]
		var rect: Rect2i = item["rect"]
		var active := i == selection
		if active:
			selected_id = String(item["id"])
		if bool(item["primary"]):
			_plate(c, rect, active)
			var label := String(item["label"])
			var style := (
				"heading" if PixelType.text_width(label, "heading") < rect.size.x - 24 else "menu"
			)
			var top := rect.position.y + (2 if style == "heading" else 4)
			HUD.text(
				c,
				label,
				rect.position.x + rect.size.x / 2,
				top,
				style,
				BRIGHT if active else PAINT,
				true
			)
		else:
			if active:
				c.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y - 1, RUST)
				_hline(c, rect.position.x, rect.position.y, rect.size.x, RUST_HOT)
				_hline(c, rect.position.x, rect.end.y - 2, rect.size.x, RUST_DEEP)
				shell(c, rect.position.x + 1 + _nudge(), rect.position.y + 3)
			HUD.text(
				c,
				String(item["label"]),
				rect.position.x + 14,
				rect.position.y + 2,
				"body",
				BRIGHT if active else PAINT
			)
	# Under the board: what the entry is for, then how to drive the menu.
	_hline(c, 12, 181, 168, Color(52 / 255.0, 36 / 255.0, 24 / 255.0))
	_hline(c, 12, 182, 168, Color(120 / 255.0, 88 / 255.0, 58 / 255.0))
	var first := note if note != "" else String(BLURBS.get(selected_id, ""))
	HUD.text(c, first, 96, 184, "mini", HUD.AMBER if note != "" else BRIGHT, true, true)
	HUD.text(c, hint, 96, 191, "mini", FADED, true, false)
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	if version != "":
		HUD.text(c, "V" + version.to_upper(), 317, 193, "mini", FADED, false, true, true)


## The big painted plate the main action sits on, ringed with marquee bulbs
## that chase while it is the one picked.
func _plate(c: Canvas, rect: Rect2i, active: bool) -> void:
	var face := RUST_HOT if active else RUST
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	c.fill_rect(x, y, w, h, DARK)
	c.fill_rect(x + 2, y + 2, w - 4, h - 4, face)
	_hline(c, x + 2, y + 2, w - 4, face.lightened(.25))
	_hline(c, x + 2, y + h - 3, w - 4, RUST_DEEP)
	var beat := _chase() if active else -1
	var n := 0
	var spots: Array = []
	for bx in range(x + 1, x + w - 2, 4):
		spots.append(Vector2i(bx, y))
	for by in range(y + 4, y + h - 4, 4):
		spots.append(Vector2i(x + w - 2, by))
	for bx in range(x + w - 3 - (w - 4) % 4, x, -4):
		spots.append(Vector2i(bx, y + h - 2))
	for by in range(y + h - 6, y + 2, -4):
		spots.append(Vector2i(x, by))
	for spot: Vector2i in spots:
		# Round the ring in order, so the chase runs round the plate.
		var on := (n + (beat if beat >= 0 else 0)) % 3 != 0 if active else n % 2 == 0
		if active and beat < 0:
			on = true
		c.fill_rect(spot.x, spot.y, 2, 2, BULB_ON if on else BULB_OFF)
		if on:
			c.fill_rect(spot.x, spot.y, 1, 1, BRIGHT)
		n += 1
	if active:
		shell(c, x + 7 + _nudge(), y + 7)
		shell(c, x + w - 16 - _nudge(), y + 7, true)


## A green enamel barn light on a gooseneck, bolted to the board's top edge.
func _barn_lamp(c: Canvas, x: int, lit: bool) -> void:
	var top := BOARD.position.y + 1
	var iron := Color(24 / 255.0, 20 / 255.0, 18 / 255.0)
	var iron_hi := Color(96 / 255.0, 86 / 255.0, 76 / 255.0)
	# The gooseneck: up from the bracket, over, and down to the shade.
	c.fill_rect(x + 15, top - 4, 2, 6, iron)
	c.fill_rect(x, top - 4, 17, 2, iron)
	c.fill_rect(x, top - 2, 2, 2, iron)
	_hline(c, x, top - 4, 17, iron_hi)
	c.fill_rect(x + 13, top + 1, 6, 4, iron)  # the bracket on the board
	c.fill_rect(x + 14, top + 2, 1, 1, BRASS)
	c.fill_rect(x + 17, top + 3, 1, 1, BRASS)
	top += 2
	var enamel := Color(52 / 255.0, 92 / 255.0, 64 / 255.0)
	var shine := Color(128 / 255.0, 176 / 255.0, 130 / 255.0)
	var rim := Color(24 / 255.0, 40 / 255.0, 30 / 255.0)
	var inside := Color(244 / 255.0, 236 / 255.0, 206 / 255.0) if lit else Color(.42, .41, .37)
	c.fill_rect(x - 2, top - 3, 6, 1, enamel)
	c.fill_rect(x - 4, top - 2, 10, 1, enamel)
	c.fill_rect(x - 6, top - 1, 14, 1, enamel)
	c.fill_rect(x - 8, top, 18, 1, enamel)
	c.fill_rect(x - 9, top + 1, 20, 1, rim)
	c.fill_rect(x - 8, top + 2, 18, 1, inside)
	c.fill_rect(x - 1, top - 3, 2, 1, shine)
	c.fill_rect(x - 3, top - 2, 3, 1, shine)
	c.fill_rect(x - 5, top - 1, 3, 1, shine)
	c.fill_rect(x - 7, top, 3, 1, shine)
	c.fill_rect(x - 1, top + 3, 4, 2, BULB_ON if lit else Color(.38, .33, .25))
	if lit:
		c.fill_rect(x, top + 3, 2, 1, BRIGHT)


## Fireflies loitering over the yard: none on STATIC, glowing steadily
## instead of blinking when flashes or flicker are turned down.
func _fireflies(c: Canvas) -> void:
	if motion == 2:
		return
	var pace := 1.0 if motion == 0 else .4
	for i in FIREFLIES.size():
		var spot: Array = FIREFLIES[i]
		var t := clock * pace + i * 1.7
		var x := int(spot[0]) + int(roundf(sin(t * .7 + i) * 9.0))
		var y := int(spot[1]) + int(roundf(sin(t * 1.1 + i * 2.3) * 5.0))
		var glow := .7 if steady else clampf(sin(t * 1.9 + i) * 1.6, 0.0, 1.0)
		if glow < .08:
			continue
		var core := Color(.55, .62, .25).lerp(Color(.92, 1.0, .55), glow)
		c.fill_rect(x, y, 1, 1, core)
		if glow > .55:
			var halo := Color(.30, .38, .14).lerp(Color(.50, .62, .22), glow)
			c.fill_rect(x - 1, y, 1, 1, halo)
			c.fill_rect(x + 1, y, 1, 1, halo)
			c.fill_rect(x, y - 1, 1, 1, halo)
			c.fill_rect(x, y + 1, 1, 1, halo)


# ------------------------------------------------------------- sub-screens


## The frame every sub-screen shares: dimmed yard, timber, the fair lights
## strung along the top, rusted header.
func draw_sheet(c: Canvas, heading: String) -> void:
	_blit(c, "menu_sheet", 0, 0)
	_blit(c, "menu_sign", SIGN.position.x, SIGN.position.y)
	HUD.text(c, heading, 160, SIGN.position.y + 4, "heading", TIN_INK, true, false)
	_festoon(c)


## A string of coloured bulbs on a sagging wire, nailed along the frame.
func _festoon(c: Canvas) -> void:
	var wire := Color(16 / 255.0, 11 / 255.0, 8 / 255.0)
	for s in FESTOON_POSTS.size() - 1:
		var x0 := int(FESTOON_POSTS[s])
		var x1 := int(FESTOON_POSTS[s + 1])
		var run_start := x0
		var run_y := _sag(x0, x0, x1)
		for x in range(x0 + 1, x1 + 1):
			var yy := _sag(x, x0, x1)
			if yy != run_y:
				_hline(c, run_start, run_y, x - run_start, wire)
				run_start = x
				run_y = yy
		_hline(c, run_start, run_y, x1 + 1 - run_start, wire)
	for post: int in FESTOON_POSTS:
		c.fill_rect(post, 1, 1, 1, BRASS)
	var beat := _chase()
	var i := 0
	for x in range(18, 304, 15):
		var s := clampi((x - 10) / 75, 0, FESTOON_POSTS.size() - 2)
		var wy := _sag(x, int(FESTOON_POSTS[s]), int(FESTOON_POSTS[s + 1]))
		var colour: Color = FESTOON_COLOURS[i % FESTOON_COLOURS.size()]
		var on := beat < 0 or (i + beat) % 4 != 0
		var face := colour if on else colour.darkened(.62)
		c.fill_rect(x, wy + 1, 1, 1, Color(40 / 255.0, 34 / 255.0, 30 / 255.0))
		c.fill_rect(x - 1, wy + 2, 3, 2, face)
		c.fill_rect(x, wy + 4, 1, 1, face)
		if on:
			c.fill_rect(x - 1, wy + 2, 1, 1, colour.lightened(.55))
		i += 1


static func _sag(x: int, x0: int, x1: int) -> int:
	var t := float(x - x0) / float(maxi(1, x1 - x0)) * 2.0 - 1.0
	return 1 + int(roundf(3.0 * (1.0 - t * t)))


## A wooden plaque with brass nails; `hot` lights it (picked or pointed at).
static func plate_button(c: Canvas, rect: Rect2i, label: String, hot := false) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	c.fill_rect(x, y, w, h, DARK)
	var face := RUST_HOT if hot else Color(88 / 255.0, 56 / 255.0, 34 / 255.0)
	c.fill_rect(x + 1, y + 1, w - 2, h - 2, face)
	_hline(c, x + 1, y + 1, w - 2, face.lightened(.22))
	_hline(c, x + 1, y + h - 2, w - 2, face.darkened(.35))
	if w > 30:
		c.fill_rect(x + 3, y + h / 2, 1, 1, BRASS)
		c.fill_rect(x + w - 4, y + h / 2, 1, 1, BRASS)
	if label != "":
		HUD.text(c, label, x + w / 2, y + (h - 7) / 2, "body", BRIGHT if hot else PAINT, true)


# --------------------------------------------------------------- settings


## Each tab is as wide as its name plus an even share of what is left over.
static func tab_rect(index: int, count: int) -> Rect2i:
	var pages := SessionStore.setup_pages()
	var widths: Array = []
	var total := 0
	for i in count:
		var name := String(pages[i][0]) if count == pages.size() else ""
		var w := PixelType.text_width(name) + 8
		widths.append(w)
		total += w
	var spare := maxi(0, PANEL.size.x - total - (count - 1) * 2)
	var x := PANEL.position.x
	for i in count:
		var w := int(widths[i]) + spare / count + (1 if i < spare % count else 0)
		if i == index:
			return Rect2i(x, TABS_Y, w, TAB_H)
		x += w + 2
	return Rect2i()


## The page's lines in order: ["head", text] for a heading, ["row", slot] for
## a setting.
static func lines(page: int) -> Array:
	if _line_cache.has(page):
		return _line_cache[page]
	var pages := SessionStore.setup_pages()
	var out: Array = []
	if page >= 0 and page < pages.size():
		var heads: Dictionary = SetupPages.HEADERS.get(String(pages[page][0]), {})
		var items: Array = pages[page][1]
		for slot in items.size():
			var key := (items[slot] as SessionStore.Setting).key
			if heads.has(key):
				out.append(["head", String(heads[key])])
			out.append(["row", slot])
	_line_cache[page] = out
	return out


static func line_height(line: Array) -> int:
	return HEAD_H if String(line[0]) == "head" else SET_ROW


static func line_of(page: int, slot: int) -> int:
	var all := lines(page)
	for i in all.size():
		if String(all[i][0]) == "row" and int(all[i][1]) == slot:
			return i
	return 0


## The first line below the window when it starts at line `scroll`. A heading
## whose first row would not fit is left for the next window.
static func shown_end(page: int, scroll: int) -> int:
	var all := lines(page)
	var room := LIST.size.y
	var i := maxi(0, scroll)
	while i < all.size():
		room -= line_height(all[i])
		if room < 0:
			break
		i += 1
	if i < all.size() and i - 1 > scroll and String(all[i - 1][0]) == "head":
		i -= 1
	return i


## The furthest the window scrolls: its last line is the page's last.
static func max_scroll(page: int) -> int:
	var count := lines(page).size()
	for s in count:
		if shown_end(page, s) >= count:
			return s
	return 0


## Keep the selected row (and the heading it sits under) inside the window.
static func scroll_for(page: int, slot: int, scroll: int) -> int:
	var all := lines(page)
	var at := line_of(page, slot)
	var top := at - 1 if at > 0 and String(all[at - 1][0]) == "head" else at
	scroll = mini(scroll, top)
	while at >= shown_end(page, scroll) and scroll < at:
		scroll += 1
	return clampi(scroll, 0, max_scroll(page))


## After the window moved (wheel, drag, groove): the picked row if it is still
## shown, else the nearest one that is, so the window stays where it was put.
## A row whose heading is above the window would pull the window back up, so
## it does not count as shown.
static func slot_in_view(page: int, slot: int, scroll: int) -> int:
	var all := lines(page)
	var rows: Array = []
	for i in range(scroll, shown_end(page, scroll)):
		if String(all[i][0]) != "row":
			continue
		if i == scroll and i > 0 and String(all[i - 1][0]) == "head":
			continue
		rows.append(int(all[i][1]))
	if rows.is_empty() or rows.has(slot):
		return slot
	return int(rows[0]) if slot < int(rows[0]) else int(rows[rows.size() - 1])


## The rows shown while the window starts at `scroll`: [slot, y] pairs.
static func shown_rows(page: int, scroll: int) -> Array:
	var all := lines(page)
	var out: Array = []
	var y := LIST.position.y
	for i in range(maxi(0, scroll), shown_end(page, scroll)):
		if String(all[i][0]) == "row":
			out.append([int(all[i][1]), y])
		y += line_height(all[i])
	return out


## The row a setting occupies while the list is scrolled to `scroll`, or an
## empty rectangle when it is off screen.
static func row_rect(page: int, slot: int, scroll: int) -> Rect2i:
	for pair: Array in shown_rows(page, scroll):
		if int(pair[0]) == slot:
			return Rect2i(LIST.position.x, int(pair[1]), LIST.size.x, SET_ROW)
	return Rect2i()


## The scroll bar's groove between its two buttons.
static func track_rect() -> Rect2i:
	return Rect2i(
		SCROLL_UP.position.x + 1,
		SCROLL_UP.end.y + 1,
		SCROLL_UP.size.x - 2,
		SCROLL_DOWN.position.y - SCROLL_UP.end.y - 2
	)


## The thumb: as long as the window is against the page, where the window is.
static func thumb_rect(page: int, scroll: int) -> Rect2i:
	var all := lines(page)
	var total := 0
	var before := 0
	var furthest := 0
	var last := max_scroll(page)
	for i in all.size():
		var h := line_height(all[i])
		total += h
		if i < scroll:
			before += h
		if i < last:
			furthest += h
	var track := track_rect()
	var thumb := clampi(track.size.y * LIST.size.y / maxi(1, total), 6, track.size.y)
	var y := track.position.y + (track.size.y - thumb) * before / maxi(1, furthest)
	return Rect2i(track.position.x, y, track.size.x, thumb)


## The line to scroll to for a point on the groove (`share` 0 top, 1 bottom).
static func scroll_at(page: int, share: float) -> int:
	return clampi(roundi(share * max_scroll(page)), 0, max_scroll(page))


## A level setting's bar: [left x, segment width, segments].
static func bar_shape(item: SessionStore.Setting) -> Array:
	var steps := maxi(1, (item.high - item.low) / maxi(1, item.step))
	var seg := maxi(1, (BAR_W - (steps - 1)) / steps)
	var span := steps * seg + steps - 1
	return [BAR_X + (BAR_W - span) / 2, seg, steps]


## The value a click at x on a level setting's bar asks for.
static func bar_value(item: SessionStore.Setting, x: int) -> int:
	var shape := bar_shape(item)
	var span := int(shape[2]) * (int(shape[1]) + 1) - 1
	var share := clampf((x - int(shape[0]) + .5) / float(span), 0.0, 1.0)
	return item.low + roundi(share * int(shape[2])) * item.step


static func is_bar(item: SessionStore.Setting) -> bool:
	return item.choices.is_empty() and not item is SessionStore.KeySetting


## What a point on the settings screen means:
## {kind: "tab"|"row"|"back"|"reset"|"up"|"down"|"track"|"", index,
## direction, bar, share}. `direction` is -1 or +1 on a row's value, 0 on its
## label; `bar` is true on a level setting's bar; `share` is where on the
## scroll groove.
static func setup_hit(x: int, y: int, page: int, scroll: int) -> Dictionary:
	var point := Vector2i(x, y)
	var hit := {"kind": "", "index": 0, "direction": 0, "bar": false, "share": 0.0}
	var pages := SessionStore.setup_pages()
	for i in pages.size():
		if tab_rect(i, pages.size()).grow_individual(0, 0, 0, 1).has_point(point):
			hit["kind"] = "tab"
			hit["index"] = i
			return hit
	if BACK.has_point(point):
		hit["kind"] = "back"
		return hit
	if RESET.has_point(point):
		hit["kind"] = "reset"
		return hit
	if max_scroll(page) > 0:
		if SCROLL_UP.grow(1).has_point(point):
			hit["kind"] = "up"
			return hit
		if SCROLL_DOWN.grow(1).has_point(point):
			hit["kind"] = "down"
			return hit
		var track := track_rect().grow_individual(1, 0, 1, 0)
		if track.has_point(point):
			hit["kind"] = "track"
			hit["share"] = clampf(
				float(y - track.position.y) / float(maxi(1, track.size.y - 1)), 0.0, 1.0
			)
			return hit
	if not LIST.has_point(point) or page < 0 or page >= pages.size():
		return hit
	var items: Array = pages[page][1]
	for pair: Array in shown_rows(page, scroll):
		if y < int(pair[1]) or y >= int(pair[1]) + SET_ROW:
			continue
		var item: SessionStore.Setting = items[int(pair[0])]
		hit["kind"] = "row"
		hit["index"] = int(pair[0])
		if x >= VALUE_X - 2:
			hit["direction"] = -1 if x < VALUE_MID else 1
			if is_bar(item):
				var shape := bar_shape(item)
				var left := int(shape[0]) - 1
				var right := left + int(shape[2]) * (int(shape[1]) + 1) + 1
				if x < left:
					hit["direction"] = -1
				elif x > right:
					hit["direction"] = 1
				else:
					hit["bar"] = true
		return hit
	return hit


static func is_toggle(item: SessionStore.Setting) -> bool:
	return item.choices.size() == 2 and String(item.choices[0]) == "OFF"


## The settings screen. `hover` names what the pointer is over ("back",
## "reset", "up", "down", "tab3"); `binding` is the KEYS page action waiting
## for a key.
func draw_setup(
	c: Canvas,
	pages: Array,
	page: int,
	slot: int,
	scroll: int,
	options: Dictionary,
	note: String,
	guide: String,
	confirm: String,
	hover := "",
	binding := ""
) -> void:
	draw_sheet(c, "SETTINGS")
	var items: Array = pages[page][1]
	# The list's frame: a brass-edged well the tabs sit on.
	c.fill_rect(PANEL.position.x, PANEL.position.y, PANEL.size.x, PANEL.size.y, DARK)
	c.fill_rect(
		PANEL.position.x + 1, PANEL.position.y + 1, PANEL.size.x - 2, PANEL.size.y - 2, WELL
	)
	_hline(c, PANEL.position.x, PANEL.position.y, PANEL.size.x, BRASS_LO)
	_tabs(c, pages, page, hover)
	var all := lines(page)
	var y := LIST.position.y
	for i in range(scroll, shown_end(page, scroll)):
		var line: Array = all[i]
		if String(line[0]) == "head":
			_heading(c, String(line[1]), y)
		else:
			var index := int(line[1])
			_row(c, items[index], index, y, index == slot, options, binding)
		y += line_height(line)
	if shown_end(page, scroll) < all.size() and LIST.end.y - y >= 7:
		# Room left under the last row: say there is more below.
		var mid := LIST.position.x + LIST.size.x / 2
		var top := y + (LIST.end.y - y - 5) / 2
		HUD.text(c, "MORE", mid, top, "mini", DIM, true, false)
		for side: int in [-1, 1]:
			var ax := mid + side * 16
			_hline(c, ax - 2, top + 1, 5, DIM)
			_hline(c, ax - 1, top + 2, 3, DIM)
			c.fill_rect(ax, top + 3, 1, 1, DIM)
	if max_scroll(page) > 0:
		_scrollbar(c, page, scroll, hover)
	var current: SessionStore.Setting = items[slot]
	_hint(c, current, note, slot, items.size())
	plate_button(c, RESET, "RESET PAGE", hover == "reset")
	plate_button(c, BACK, "BACK", hover == "back")
	HUD.text(c, guide, (RESET.end.x + BACK.position.x) / 2, 181, "mini", FADED, true, false)
	if confirm != "":
		_confirm(c, confirm, hover)


func _tabs(c: Canvas, pages: Array, page: int, hover: String) -> void:
	for j in pages.size():
		var tab := tab_rect(j, pages.size())
		var on := j == page
		var hot := hover == "tab%d" % j
		var x := tab.position.x
		var w := tab.size.x
		if on:
			# The picked tab stands a little taller and runs into the frame.
			c.fill_rect(x, TABS_Y - 1, w, TAB_H + 2, DARK)
			c.fill_rect(x + 1, TABS_Y, w - 2, TAB_H + 1, RUST)
			_hline(c, x + 1, TABS_Y, w - 2, RUST_HOT)
			c.fill_rect(x + 2, TABS_Y + 2, 1, 1, BRASS)
			c.fill_rect(x + w - 3, TABS_Y + 2, 1, 1, BRASS)
		else:
			var face := (
				Color(70 / 255.0, 48 / 255.0, 34 / 255.0)
				if hot
				else Color(46 / 255.0, 33 / 255.0, 25 / 255.0)
			)
			c.fill_rect(x, TABS_Y + 1, w, TAB_H - 1, DARK)
			c.fill_rect(x + 1, TABS_Y + 2, w - 2, TAB_H - 3, face)
			_hline(c, x + 1, TABS_Y + 2, w - 2, face.lightened(.18))
		HUD.text(
			c,
			String(pages[j][0]),
			x + w / 2,
			TABS_Y + (3 if on else 4),
			"body",
			BRIGHT if on else (PAINT if hot else FADED),
			true
		)


func _heading(c: Canvas, text: String, y: int) -> void:
	c.fill_rect(LIST.position.x, y, LIST.size.x, HEAD_H, WELL)
	var width := PixelType.text_width(text, "mini")
	_hline(c, LIST.position.x + 2, y + 4, 3, BRASS_LO)
	HUD.text(c, text, LIST.position.x + 7, y + 2, "mini", BRASS, false, false)
	var after := LIST.position.x + 10 + width
	_hline(c, after, y + 4, LIST.end.x - 3 - after, BRASS_LO)


func _row(
	c: Canvas,
	item: SessionStore.Setting,
	slot: int,
	y: int,
	on: bool,
	options: Dictionary,
	binding: String
) -> void:
	var x := LIST.position.x
	var w := LIST.size.x
	var face := WOOD_A if slot % 2 == 0 else WOOD_B
	if on:
		face = RUST
	c.fill_rect(x, y, w, SET_ROW, face)
	if on:
		_hline(c, x, y, w, RUST_HOT)
		_hline(c, x, y + SET_ROW - 1, w, RUST_DEEP)
		shell(c, x + 3 + _nudge(), y + 3)
	HUD.text(c, item.label, x + LABEL_X - LIST.position.x, y + 2, "body", BRIGHT if on else PAINT)
	_control(c, item, int(options.get(item.key, item.default_value)), y, on, binding)


## The right-hand side of a row: a segmented bar for a level, a lamp for on
## and off, a keycap for a key, a word between arrows for a choice.
func _control(
	c: Canvas, item: SessionStore.Setting, value: int, y: int, on: bool, binding: String
) -> void:
	var ink := BRIGHT if on else PAINT
	if item is SessionStore.KeySetting:
		var waiting := binding != "" and (item as SessionStore.KeySetting).action == binding
		var label := "PRESS A KEY" if waiting else item.format_value(value)
		var kw := PixelType.text_width(label) + 10
		var kx := VALUE_MID - kw / 2
		var cap := Color(78 / 255.0, 60 / 255.0, 44 / 255.0)
		if waiting:
			var pulse := steady or fposmod(clock * 2.0, 1.0) < .6
			cap = HUD.AMBER if pulse else RUST_HOT
		c.fill_rect(kx, y + 1, kw, 10, DARK)
		c.fill_rect(kx + 1, y + 1, kw - 2, 9, cap)
		_hline(c, kx + 1, y + 1, kw - 2, cap.lightened(.3))
		_hline(c, kx + 1, y + 9, kw - 2, cap.darkened(.4))
		HUD.text(c, label, VALUE_MID, y + 2, "body", TIN_INK if waiting else ink, true, false)
	elif is_bar(item):
		var shape := bar_shape(item)
		var bx := int(shape[0])
		var seg := int(shape[1])
		var steps := int(shape[2])
		var filled := (value - item.low) / maxi(1, item.step)
		c.fill_rect(bx - 1, y + 2, steps * (seg + 1) + 1, 7, DARK)
		for k in steps:
			var sx := bx + k * (seg + 1)
			if k < filled:
				var lit := HUD.AMBER.lerp(RUST_HOT, float(k) / float(maxi(1, steps - 1)))
				if not on:
					lit = lit.darkened(.22)
				c.fill_rect(sx, y + 3, seg, 5, lit)
				_hline(c, sx, y + 3, seg, lit.lightened(.35))
			else:
				c.fill_rect(sx, y + 3, seg, 5, Color(52 / 255.0, 38 / 255.0, 29 / 255.0))
		HUD.text(c, item.format_value(value), VALUE_END, y + 2, "body", ink, false, true, true)
		if on:
			HUD.text(c, "<", VALUE_X, y + 2, "body", HUD.AMBER)
			HUD.text(c, ">", bx + steps * (seg + 1) + 2, y + 2, "body", HUD.AMBER)
	elif is_toggle(item):
		var lit := value != item.low
		lamp(c, VALUE_MID - 9, y + 5, lit)
		HUD.text(c, item.format_value(value), VALUE_MID - 2, y + 2, "body", ink)
	else:
		HUD.text(c, item.format_value(value), VALUE_MID, y + 2, "body", ink, true)
		var arrow := HUD.AMBER if on else DIM
		HUD.text(c, "<", VALUE_X, y + 2, "body", arrow, false, on)
		HUD.text(c, ">", VALUE_END - 4, y + 2, "body", arrow, false, on)
		if on:
			# One pip per choice along the plank's edge, the picked one lit: how
			# many there are and which this is.
			var count := item.choices.size()
			var left := VALUE_MID - (count * 5 - 2) / 2
			for k in count:
				var pip := BRIGHT if k == value - item.low else RUST_HOT
				c.fill_rect(left + k * 5, y + SET_ROW - 1, 3, 1, pip)


func _scrollbar(c: Canvas, page: int, scroll: int, hover: String) -> void:
	var top := scroll > 0
	var bottom := scroll < max_scroll(page)
	for pair: Array in [[SCROLL_UP, top, "up"], [SCROLL_DOWN, bottom, "down"]]:
		var rect: Rect2i = pair[0]
		var hot := hover == String(pair[2]) and bool(pair[1])
		c.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, DARK)
		c.fill_rect(
			rect.position.x + 1,
			rect.position.y + 1,
			rect.size.x - 2,
			rect.size.y - 2,
			RUST_HOT if hot else Color(70 / 255.0, 46 / 255.0, 30 / 255.0)
		)
		var ink := BRIGHT if bool(pair[1]) else DIM
		var mid := rect.position.x + rect.size.x / 2
		for d in 3:
			var row := (
				rect.position.y + 3 + d
				if String(pair[2]) == "up"
				else rect.position.y + rect.size.y - 4 - d
			)
			_hline(c, mid - d, row, d * 2 + 1, ink)
	var track := track_rect()
	c.fill_rect(track.position.x, track.position.y, track.size.x, track.size.y, DARK)
	var thumb := thumb_rect(page, scroll)
	c.fill_rect(thumb.position.x, thumb.position.y, thumb.size.x, thumb.size.y, BRASS)
	_hline(c, thumb.position.x, thumb.position.y, thumb.size.x, BRASS_HI)
	_hline(c, thumb.position.x, thumb.end.y - 1, thumb.size.x, BRASS_LO)
	var grip := thumb.position.y + thumb.size.y / 2 - 2
	for g in 3:
		_hline(c, thumb.position.x + 1, grip + g * 2, thumb.size.x - 2, BRASS_LO)


## Under the list: what the picked setting does, when it takes effect, its
## default and where on the page it is.
func _hint(c: Canvas, item: SessionStore.Setting, note: String, slot: int, count: int) -> void:
	var r := HINT
	c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, DARK)
	c.fill_rect(
		r.position.x + 1,
		r.position.y + 1,
		r.size.x - 2,
		r.size.y - 2,
		Color(30 / 255.0, 21 / 255.0, 16 / 255.0)
	)
	_hline(
		c,
		r.position.x + 1,
		r.position.y + 1,
		r.size.x - 2,
		Color(64 / 255.0, 46 / 255.0, 34 / 255.0)
	)
	rivets(c, r)
	var wrapped := PixelType.wrap(note if note != "" else item.hint, r.size.x - 14)
	for i in mini(2, wrapped.size()):
		HUD.text(
			c,
			wrapped[i],
			160,
			r.position.y + 2 + i * 8,
			"body",
			HUD.AMBER if note != "" else PAINT,
			true
		)
	var bottom := r.end.y - 6
	var applies := String(NEXT_RUN.get(item.key, "CHANGES RIGHT AWAY"))
	if item is SessionStore.KeySetting:
		applies = "ENTER OR CLICK, THEN THE NEW KEY"
	HUD.text(
		c,
		applies,
		r.position.x + 9,
		bottom,
		"mini",
		HUD.AMBER if NEXT_RUN.has(item.key) else FADED,
		false,
		false
	)
	var where := "DEFAULT %s   %d/%d" % [item.format_value(item.default_value), slot + 1, count]
	HUD.text(c, where, r.end.x - 9, bottom, "mini", FADED, false, false, true)


## Keep or undo a display change: a tin plaque with a button for each.
func _confirm(c: Canvas, confirm: String, hover: String) -> void:
	var r := CONFIRM
	c.fill_rect(
		r.position.x + 2,
		r.position.y + 3,
		r.size.x,
		r.size.y,
		Color(8 / 255.0, 5 / 255.0, 4 / 255.0)
	)
	c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, DARK)
	c.fill_rect(
		r.position.x + 1,
		r.position.y + 1,
		r.size.x - 2,
		r.size.y - 2,
		Color(70 / 255.0, 40 / 255.0, 24 / 255.0)
	)
	c.rect_outline(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2, RUST_HOT)
	rivets(c, r, 3)
	HUD.text(c, "KEEP THIS DISPLAY?", 160, r.position.y + 5, "menu", BRIGHT, true)
	plate_button(c, CONFIRM_KEEP, "KEEP", hover != "undo")
	plate_button(c, CONFIRM_UNDO, "UNDO", hover == "undo")
	HUD.text(c, confirm, 160, r.position.y + 40, "mini", HUD.AMBER, true, false)
