## Port of touch_controls.py: the multi-touch gamepad overlay for Android and
## touchscreen browsers.
##
## The overlay stays invisible for mouse/keyboard play and switches on for
## Android or as soon as the first finger touches the window. A left thumbstick
## drives movement, a right-side drag aims, and the round buttons cover fire,
## use, alt-fire, weapon cycling and the menu, exactly where the reference puts
## them. Every finger is tracked by its index so the player can walk, aim and
## shoot at the same time.
##
## The Godot build adds what the reference overlay never had a button for:
## jump, crouch and the three consumables (rinds, beer, moonshine), plus
## vertical swipe-look. Those sit in the gaps of the original layout.
class_name TouchControls
extends Control

const DEADZONE := 0.16
const TURN_RATE := 0.0060
## Vertical look per dragged pixel. The reference overlay only turned; this
## keeps the mouse's own turn/look ratio (.24 / .0034) at half strength so a
## thumb drag does not throw the view at the sky.
const LOOK_RATE := 0.0060 * (0.24 / 0.0034) * 0.5
const TAP_SLOP := 0.022
const TAP_TIME := 0.45

const LABELS := {
	"fire": "FIRE",
	"use": "USE",
	"alt": "ALT",
	"next": "NEXT",
	"menu": "MENU",
	"jump": "JUMP",
	"crouch": "DUCK",
	"rinds": "RIND",
	"beer": "BEER",
	"shine": "SHINE",
	"map": "MAP",
	"photo": "PHOTO",
	"torch": "LIGHT",
	"whistle": "WHISTLE",
	"talk": "TALK",
	"kick": "KICK",
	"throw": "THROW",
}
## One-shot roles: a press counts once, however long the finger rests there.
const TAPPED := [
	"use",
	"next",
	"menu",
	"rinds",
	"beer",
	"shine",
	"map",
	"photo",
	"torch",
	"whistle",
	"kick",
	"throw",
]
## The pictures on the KICK and THROW buttons (pass 15, tools/art/
## build_touch_glyphs.gd: a boot, a lit stick), given by main.gd; a button
## without one shows its word alone.
var glyphs := {}
## TOUCH BUTTONS: MY LAYOUT puts the stick and buttons where the player
## dragged them (MOVE THEM), kept as parts of the overlay's width and height.
const LAYOUT_FILE := "user://touch-layout.json"

var active := false
var area := Rect2()
var fingers := {}
var stick := Vector2.ZERO
var turn := 0.0
var look := 0.0
var fire := false
var alt := false
var jump := false
var crouch := false
var counts := {}
var tap: Variant = null
var stick_center := Vector2.ZERO
var stick_radius := 1.0
var buttons: Array = []
var font_size := 14
var clock := 0.0
var showing := false
var custom := {}
var use_custom := false
var editing := false
var _moving := {}
## Buttons shown only when they do something (offer): LIGHT while this
## player has a flashlight, WHISTLE while BLUE is along, TALK online with the
## mic on PUSH TO TALK (held, voice_chat.gd). MOVE THEM shows all.
var kept_off := {"torch": true, "whistle": true, "talk": true}
var _done_rect := Rect2()
var _reset_rect := Rect2()


func _init() -> void:
	active = (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	_load_custom()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ---------------------------------------------------------------- layout


## `rect` is the part of the window the overlay may use (the display's safe
## area on a phone, the whole window elsewhere), in window pixels.
func layout(rect: Rect2, again := false) -> void:
	if rect == area and not again:
		return
	area = rect
	var w := rect.size.x
	var h := rect.size.y
	var m := maxf(1.0, minf(w, h))
	stick_radius = m * .18
	stick_center = _place("stick", Vector2(.16, .70))
	var r := m * .125
	var small := m * .072
	# The top row stands 9% of the width apart: on a phone held upright
	# (a browser) its rings would overlap and a tap could take the wrong one.
	var tiny := minf(small * .78, w * .043)
	buttons = [
		["fire", _place("fire", Vector2(.87, .72)), r],
		["use", _place("use", Vector2(.68, .85)), small],
		["alt", _place("alt", Vector2(.73, .55)), small],
		["next", _place("next", Vector2(.91, .50)), small],
		["menu", _place("menu", Vector2(.95, .10)), tiny],
		# Godot additions, placed in the gaps of the reference layout.
		["jump", _place("jump", Vector2(.78, .90)), small],
		["crouch", _place("crouch", Vector2(.82, .38)), small],
		["rinds", _place("rinds", Vector2(.58, .10)), tiny],
		["beer", _place("beer", Vector2(.67, .10)), tiny],
		["shine", _place("shine", Vector2(.76, .10)), tiny],
		["map", _place("map", Vector2(.85, .10)), tiny],
		["photo", _place("photo", Vector2(.49, .10)), tiny],
		# Shown only when they do something (offer), in the top row with
		# the pocket's buttons.
		["torch", _place("torch", Vector2(.40, .10)), tiny],
		["whistle", _place("whistle", Vector2(.31, .10)), tiny],
		["talk", _place("talk", Vector2(.07, .36)), small],
		# KICK and THROW (pass 15): by USE, and right of DUCK.
		["kick", _place("kick", Vector2(.60, .66)), small],
		["throw", _place("throw", Vector2(.94, .43)), small],
	]
	_done_rect = Rect2(rect.position + Vector2(w * .30, h * .40), Vector2(w * .18, h * .12))
	_reset_rect = Rect2(rect.position + Vector2(w * .52, h * .40), Vector2(w * .18, h * .12))
	font_size = maxi(14, roundi(m * .028))
	fingers.clear()
	stick = Vector2.ZERO
	fire = false
	alt = false
	jump = false
	crouch = false
	queue_redraw()


## Where a control sits: the player's place for it with MY LAYOUT, else the
## standard one (both as parts of the overlay's width and height).
func _place(role: String, standard: Vector2) -> Vector2:
	var at: Vector2 = custom.get(role, standard) if use_custom or editing else standard
	return area.position + at * area.size


func _load_custom() -> void:
	custom = {}
	if not FileAccess.file_exists(LAYOUT_FILE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	if not parsed is Dictionary:
		return
	var table: Dictionary = parsed
	for role: Variant in table:
		var pair: Variant = table[role]
		if (role == "stick" or LABELS.has(role)) and pair is Array:
			var two: Array = pair
			if two.size() == 2:
				var px: float = two[0]
				var py: float = two[1]
				custom[str(role)] = Vector2(clampf(px, .03, .97), clampf(py, .03, .97))


func _save_custom() -> void:
	# A tool driving the game (tools/touch_settings_check.gd) keeps the places
	# in memory: it must never write the player's layout.
	if Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null:
		return
	var out := {}
	for role: String in custom:
		var at: Vector2 = custom[role]
		out[role] = [snappedf(at.x, .001), snappedf(at.y, .001)]
	var file := FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out))


## MOVE THEM: show every control over whatever screen is up and let a finger
## drag each one; DONE keeps the places (and MY LAYOUT uses them), RESET puts
## them back where they started.
func start_editing() -> void:
	editing = true
	active = true
	visible = true
	showing = true
	layout(area, true)
	queue_redraw()


func _edit_touch(event: InputEventScreenTouch) -> void:
	var pos := event.position
	if not event.pressed:
		_moving.erase(event.index)
		return
	if _done_rect.has_point(pos):
		editing = false
		use_custom = true
		_moving.clear()
		_save_custom()
		layout(area, true)
		set_showing(false)
		return
	if _reset_rect.has_point(pos):
		custom.clear()
		layout(area, true)
		queue_redraw()
		return
	var role := _hit_button(pos)
	if role == "" and pos.distance_to(stick_center) <= stick_radius:
		role = "stick"
	if role != "":
		_moving[event.index] = role


func _edit_drag(event: InputEventScreenDrag) -> void:
	var role: Variant = _moving.get(event.index)
	if role == null:
		return
	var at := (event.position - area.position) / area.size
	custom[str(role)] = Vector2(clampf(at.x, .03, .97), clampf(at.y, .03, .97))
	layout(area, true)
	queue_redraw()


## The KICK and THROW buttons' pictures from `art` (main.gd, once), each
## blown up four times, nearest, so it stays crisp as its ring scales it.
func take_glyphs(art: Assets) -> void:
	for role: String in ["kick", "throw"]:
		var pic := art.art("touch_" + role)
		var w: int = pic["w"]
		var h: int = pic["h"]
		if w <= 1:
			continue
		var data: PackedByteArray = pic["data"]
		var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		image.resize(w * 4, h * 4, Image.INTERPOLATE_NEAREST)
		glyphs[role] = ImageTexture.create_from_image(image)


## Shows or hides `role`'s button (LIGHT, WHISTLE): main.gd each frame.
func offer(role: String, on: bool) -> void:
	if kept_off.get(role, false) == (not on):
		return
	kept_off[role] = not on
	if not on:
		counts[role] = 0
	queue_redraw()


func _hides(role: String) -> bool:
	return kept_off.get(role, false) and not editing


## The buttons on screen now (the HUD's layout keeps clear of them).
func shown_buttons() -> Array:
	return buttons.filter(func(b: Array) -> bool: return not _hides(str(b[0])))


func _hit_button(pos: Vector2) -> String:
	for button: Array in shown_buttons():
		var center: Vector2 = button[1]
		var radius: float = button[2]
		if pos.distance_to(center) <= radius:
			var name_: String = button[0]
			return name_
	return ""


func _stick(pos: Vector2) -> Vector2:
	var d := (pos - stick_center) / stick_radius
	var length := d.length()
	if length > 1.0:
		d /= length
	if length < DEADZONE:
		return Vector2.ZERO
	var scale_ := minf(1.0, (length - DEADZONE) / (1.0 - DEADZONE))
	return d * scale_


# ---------------------------------------------------------------- events


func touch(event: InputEventScreenTouch) -> void:
	if editing:
		_edit_touch(event)
		return
	var pos := event.position
	if event.pressed:
		active = true
		var role := "tap"
		if pos.distance_to(stick_center) <= stick_radius * 1.35:
			role = "stick"
			stick = _stick(pos)
		else:
			var hit := _hit_button(pos)
			if hit != "":
				role = hit
				if TAPPED.has(hit):
					var had: int = counts.get(hit, 0)
					counts[hit] = had + 1
			elif pos.x > area.position.x + area.size.x * .42:
				role = "drag"
		fingers[event.index] = {"role": role, "start": pos, "last": pos, "time": clock}
	else:
		var found: Variant = fingers.get(event.index)
		fingers.erase(event.index)
		if found != null:
			var state: Dictionary = found
			var last: Vector2 = state["last"]
			var start: Vector2 = state["start"]
			var moved: float = last.distance_to(start)
			var began: float = state["time"]
			if moved <= area.size.x * TAP_SLOP and clock - began <= TAP_TIME:
				tap = state["start"]
			if state["role"] == "stick" and not _held("stick"):
				stick = Vector2.ZERO
	_refresh()


func drag(event: InputEventScreenDrag) -> void:
	if editing:
		_edit_drag(event)
		return
	var found: Variant = fingers.get(event.index)
	if found == null:
		return
	var state: Dictionary = found
	if state["role"] == "stick":
		stick = _stick(event.position)
	elif state["role"] == "drag":
		turn += event.relative.x * TURN_RATE
		look += event.relative.y * LOOK_RATE
	state["last"] = event.position
	queue_redraw()


## Whether a finger rests on `role`'s button (TALK: voice_chat.gd).
func pressing(role: String) -> bool:
	return _held(role) and not _hides(role)


func _held(role: String) -> bool:
	for state: Dictionary in fingers.values():
		if state["role"] == role:
			return true
	return false


func _refresh() -> void:
	fire = _held("fire")
	alt = _held("alt")
	jump = _held("jump")
	crouch = _held("crouch")
	queue_redraw()


## Drop every finger: used when play is left, so nothing stays held.
func release() -> void:
	fingers.clear()
	stick = Vector2.ZERO
	turn = 0.0
	look = 0.0
	counts.clear()
	tap = null
	_refresh()


func tick(dt: float) -> void:
	clock += dt


# ---------------------------------------------------------------- output


func state() -> Dictionary:
	var result := {
		"forward": -stick.y,
		"strafe": stick.x,
		"turn": turn,
		"look": look,
		"fire": fire,
		"alt": alt,
		"jump": jump,
		"crouch": crouch,
		# USE held down (a revive, BLUE got up, a 5v5 plant or defuse): its
		# press is also a tap of USE (consume).
		"hold": _held("use")
	}
	turn = 0.0
	look = 0.0
	return result


func consume(role: String) -> bool:
	var had: int = counts.get(role, 0)
	var value := had > 0
	counts[role] = 0
	return value


func consume_tap() -> Variant:
	var value: Variant = tap
	tap = null
	return value


func set_showing(value: bool) -> void:
	if editing:
		return
	value = value and active
	if value != showing:
		showing = value
		visible = value
		if not value:
			release()
		queue_redraw()


# ------------------------------------------------------------------ draw


func _draw() -> void:
	if not showing:
		return
	var font := ThemeDB.fallback_font
	var pressed := {}
	for state: Dictionary in fingers.values():
		pressed[state["role"]] = true
	for button: Array in shown_buttons():
		var role: String = button[0]
		var center: Vector2 = button[1]
		var radius: float = button[2]
		var hot := pressed.has(role)
		var fill := Color8(232, 182, 96, 148) if hot else Color8(29, 24, 20, 108)
		var edge := Color8(255, 226, 160, 210) if hot else Color8(231, 197, 138, 128)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 48, edge, 2.0, true)
		var label: String = LABELS[role]
		var glyph: Texture2D = glyphs.get(role)
		if glyph != null:
			_draw_glyph(glyph, center, radius, hot)
			center += Vector2(0.0, radius * .56)
		var size := font_size if radius >= font_size * 1.9 else maxi(9, int(radius * .52))
		if glyph != null:
			size = maxi(8, int(size * .7))
		var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		if extent.x > radius * 1.8:
			# A long word (WHISTLE) shrinks to sit inside its ring.
			size = maxi(8, int(size * radius * 1.8 / extent.x))
			extent = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var ink := Color8(255, 242, 214, 230 if hot else 180)
		draw_string(
			font,
			center + Vector2(-extent.x * .5, extent.y * .28),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			ink
		)
	draw_circle(stick_center, stick_radius, Color8(22, 18, 16, 92))
	draw_arc(stick_center, stick_radius, 0.0, TAU, 64, Color8(231, 197, 138, 116), 2.0, true)
	var knob := stick_center + stick * stick_radius * .58
	draw_circle(knob, stick_radius * .42, Color8(238, 217, 178, 132))
	draw_arc(knob, stick_radius * .42, 0.0, TAU, 48, Color8(255, 240, 208, 188), 2.0, true)
	if editing:
		_draw_editing(font)


## A button's picture, crisp (nearest), as big as the ring leaves room for
## above its word.
func _draw_glyph(glyph: Texture2D, center: Vector2, radius: float, hot: bool) -> void:
	var side := radius * 1.05
	var scale_ := side / maxf(1.0, maxf(glyph.get_width(), glyph.get_height()))
	var size := Vector2(glyph.get_width(), glyph.get_height()) * scale_
	var at := center - size * .5 - Vector2(0.0, radius * .16)
	draw_texture_rect(glyph, Rect2(at, size), false, Color(1, 1, 1, .95 if hot else .78))


func _draw_editing(font: Font) -> void:
	var strip := Rect2(area.position, Vector2(area.size.x, area.size.y * .08))
	draw_rect(strip, Color8(20, 15, 12, 200))
	var note := "DRAG THE STICK AND BUTTONS WHERE YOUR THUMBS WANT THEM"
	var wide := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		strip.get_center() + Vector2(-wide.x * .5, wide.y * .28),
		note,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color8(255, 226, 160, 240)
	)
	for pair: Array in [[_done_rect, "DONE"], [_reset_rect, "RESET"]]:
		var box: Rect2 = pair[0]
		draw_rect(box, Color8(64, 42, 28, 220))
		draw_rect(box, Color8(255, 226, 160, 230), false, 2.0)
		var word: String = pair[1]
		var extent := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			font,
			box.get_center() + Vector2(-extent.x * .5, extent.y * .28),
			word,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color8(255, 242, 214, 240)
		)
