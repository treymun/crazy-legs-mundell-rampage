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
}
## One-shot roles: a press counts once, however long the finger rests there.
const TAPPED := ["use", "next", "menu", "rinds", "beer", "shine"]

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
var tap = null
var stick_center := Vector2.ZERO
var stick_radius := 1.0
var buttons: Array = []
var font_size := 14
var clock := 0.0
var showing := false


func _init() -> void:
	active = (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ---------------------------------------------------------------- layout


## `rect` is the part of the window the overlay may use (the display's safe
## area on a phone, the whole window elsewhere), in window pixels.
func layout(rect: Rect2) -> void:
	if rect == area:
		return
	area = rect
	var w := rect.size.x
	var h := rect.size.y
	var m := maxf(1.0, minf(w, h))
	stick_radius = m * .18
	stick_center = rect.position + Vector2(w * .16, h * .70)
	var r := m * .125
	var small := m * .072
	var tiny := small * .78
	buttons = [
		["fire", rect.position + Vector2(w * .87, h * .72), r],
		["use", rect.position + Vector2(w * .68, h * .85), small],
		["alt", rect.position + Vector2(w * .73, h * .55), small],
		["next", rect.position + Vector2(w * .91, h * .50), small],
		["menu", rect.position + Vector2(w * .95, h * .10), tiny],
		# Godot additions, placed in the gaps of the reference layout.
		["jump", rect.position + Vector2(w * .78, h * .90), small],
		["crouch", rect.position + Vector2(w * .82, h * .38), small],
		["rinds", rect.position + Vector2(w * .58, h * .10), tiny],
		["beer", rect.position + Vector2(w * .67, h * .10), tiny],
		["shine", rect.position + Vector2(w * .76, h * .10), tiny],
	]
	font_size = maxi(14, roundi(m * .028))
	fingers.clear()
	stick = Vector2.ZERO
	fire = false
	alt = false
	jump = false
	crouch = false
	queue_redraw()


func _hit_button(pos: Vector2) -> String:
	for button: Array in buttons:
		if pos.distance_to(button[1]) <= float(button[2]):
			return String(button[0])
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
					counts[hit] = int(counts.get(hit, 0)) + 1
			elif pos.x > area.position.x + area.size.x * .42:
				role = "drag"
		fingers[event.index] = {"role": role, "start": pos, "last": pos, "time": clock}
	else:
		var state = fingers.get(event.index)
		fingers.erase(event.index)
		if state != null:
			var moved: float = (state["last"] as Vector2).distance_to(state["start"])
			if moved <= area.size.x * TAP_SLOP and clock - float(state["time"]) <= TAP_TIME:
				tap = state["start"]
			if state["role"] == "stick" and not _held("stick"):
				stick = Vector2.ZERO
	_refresh()


func drag(event: InputEventScreenDrag) -> void:
	var state = fingers.get(event.index)
	if state == null:
		return
	if state["role"] == "stick":
		stick = _stick(event.position)
	elif state["role"] == "drag":
		turn += event.relative.x * TURN_RATE
		look += event.relative.y * LOOK_RATE
	state["last"] = event.position
	queue_redraw()


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
		"crouch": crouch
	}
	turn = 0.0
	look = 0.0
	return result


func consume(role: String) -> bool:
	var value := int(counts.get(role, 0)) > 0
	counts[role] = 0
	return value


func consume_tap():
	var value = tap
	tap = null
	return value


func set_showing(value: bool) -> void:
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
	for button: Array in buttons:
		var role := String(button[0])
		var center: Vector2 = button[1]
		var radius := float(button[2])
		var hot := pressed.has(role)
		var fill := Color8(232, 182, 96, 148) if hot else Color8(29, 24, 20, 108)
		var edge := Color8(255, 226, 160, 210) if hot else Color8(231, 197, 138, 128)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 48, edge, 2.0, true)
		var label := String(LABELS[role])
		var size := font_size if radius >= font_size * 1.9 else maxi(9, int(radius * .52))
		var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
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
