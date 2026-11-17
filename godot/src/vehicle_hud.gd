## The driving plate: a small tin plate in the view's top left corner while
## this machine's player rides a vehicle (features/vehicles.gd draw_view),
## in the status bar's colours and lettering: the speed (big rust numerals,
## or a dial with STATUS PANEL's dials), the rig's health as a row of lamps
## and what state it is in (SMOKIN', ON FIRE, BURNT OUT), the throttle as a
## bar up its right edge (reverse runs down it, red), and a line for the
## kind: the car's gear, the airboat's fan on its tach, the mower's blade on
## or off. HUD MINIMAL keeps only the speed and the rig's health, in two
## lines of text, in the same corner. Looks only.
class_name VehicleHud
extends RefCounted

const W := 84
const H := 37
## The plate's corner as wanted: the view's top left, under the objective
## pin's arrow, clear of the hands on the controls at the bottom of the view
## and of the touch buttons' move stick (the HUD's layout moves it down past
## a long notice: ui/hud/hud_layout.gd).
const AT := Vector2i(HudLayout.EDGE, 36)
## MPH for each cell a second.
const MPH := 3.4
const LAMPS := 10
const FACE := Color8(40, 29, 23)
const EDGE := Color8(141, 102, 65)
const WELL := Color8(22, 17, 14)
const GREEN := Color8(109, 150, 68)
const YELLOW := Color8(196, 160, 60)
const RED := Color8(206, 66, 44)
const DIAL := Color8(189, 172, 132)
const NEEDLE := Color8(68, 45, 34)


## The plate for ride `v` (`driving`: this player has the wheel).
## What the plate inks (HUD MINIMAL's two lines when `minimal`).
static func size(minimal: bool) -> Vector2i:
	if minimal:
		var mini_h: int = PixelType.style_of("mini")[1]
		return Vector2i(66, 10 + mini_h + 3)
	return HudLayout.panel_rect(0, 0, W, H).size


static func draw(
	c: Canvas, game: Game, v: VehicleDrive.Ride, s: VehicleDrive.Spec, driving: bool, at := AT
) -> void:
	var mph := roundi(VehicleDrive.speed(v) * MPH)
	var share := clampf(v.hp / maxf(1.0, s.hp), 0.0, 1.0)
	var health := roundi(100.0 * share)
	var state := condition(v, share)
	var hot := share <= .25 and int(game.clock * 3.0) % 2 == 0
	if game.hud.minimal:
		HUD.text(c, "%d MPH" % mph, at.x + 1, at.y + 1, "body", HUD.INK, false, true)
		var line := "RIG %d%%" % health if state == "" else state
		HUD.text(
			c, line, at.x + 1, at.y + 10, "mini", HUD.LOW if share <= .5 else HUD.INK, false, true
		)
		return
	var x := at.x
	var y := at.y
	c.panel(x, y, W, H, FACE, EDGE)
	# The speed: big numerals, or STATUS PANEL's dial with them small.
	var pace := clampf(VehicleDrive.speed(v) / maxf(1.0, s.top), 0.0, 1.0)
	if game.hud_style:
		_dial(c, x + 15, y + 15, pace)
		HUD.text(c, str(mph), x + 15, y + 17, "mini", HUD.INK, true, false)
		HUD.text(c, "MPH", x + 31, y + 4, "mini", HUD.DIM, false, false)
	else:
		HUD.number(c, str(mph), x + 18, y + 2, false)
		HUD.text(c, "MPH", x + 35, y + 8, "mini", HUD.DIM, false, false)
	# The rig's health: a row of lamps, and how it is if it is bad.
	HUD.text(c, "RIG", x + 4, y + 21, "mini", HUD.INK, false, false)
	_lamps(c, x + 20, y + 21, share)
	if state != "":
		HUD.text(c, state, x + 48, y + 4, "mini", HUD.LOW_HOT if hot else HUD.AMBER, false, false)
	# The kind's own line.
	var label := ""
	var lit := false
	match v.kind:
		"car":
			var g := VehicleCab.gear(v, s)
			var gear := int(g.x)
			label = "GEAR " + ("R" if gear < 0 else "N" if gear == 0 else str(gear))
			_bar(c, x + 44, y + 30, 22, g.y, true)
		"airboat":
			label = "FAN"
			_bar(c, x + 22, y + 30, 44, VehicleCab.rpm(v, s), true)
		"mower":
			lit = VehicleCab.blade_on(v, s)
			label = "BLADE"
			c.circle(x + 31, y + 32, 2, GREEN if lit else WELL)
			HUD.text(
				c,
				"ON" if lit else "OFF",
				x + 36,
				y + 30,
				"mini",
				GREEN if lit else HUD.DIM,
				false,
				false
			)
	HUD.text(c, label, x + 4, y + 30, "mini", HUD.INK, false, false)
	# The throttle up the right edge (only the driver's hand is on it).
	_throttle(c, x + W - 8, y + 4, H - 9, v.gas if driving else 0.0)


## What shape the rig is in, when it is bad ("" when it runs well).
static func condition(v: VehicleDrive.Ride, share: float) -> String:
	if v.wreck >= 0.0:
		return "BURNT OUT"
	if share <= .25:
		return "ON FIRE"
	if share <= .5:
		return "SMOKIN'"
	return ""


## LAMPS lamps for `share`: green, then yellow, the last red.
static func _lamps(c: Canvas, x: int, y: int, share: float) -> void:
	c.fill_rect(x - 1, y - 1, LAMPS * 5 + 1, 7, WELL)
	var on := ceili(share * LAMPS - .001)
	for k in LAMPS:
		var col := GREEN if k >= 6 else YELLOW if k >= 3 else RED
		c.fill_rect(x + k * 5, y, 4, 5, col if k < on else col.darkened(.7))
		if k < on:
			c.line(x + k * 5, y, x + k * 5 + 3, y, col.lightened(.25))


## A tach's bar `w` wide at `value` (0..1), its last fifth red.
static func _bar(c: Canvas, x: int, y: int, w: int, value: float, redline: bool) -> void:
	c.fill_rect(x - 1, y - 1, w + 2, 6, WELL)
	var fill := roundi(clampf(value, 0.0, 1.0) * w)
	for k in fill:
		var hot := redline and k >= w * 4 / 5
		c.line(x + k, y, x + k, y + 3, RED if hot else YELLOW if k >= w / 2 else GREEN)


## The throttle up a bar `h` tall: forward fills up from the middle, reverse
## down from it, red.
static func _throttle(c: Canvas, x: int, y: int, h: int, gas: float) -> void:
	c.fill_rect(x - 1, y - 1, 5, h + 2, WELL)
	var mid := y + h / 2
	c.line(x - 2, mid, x + 4, mid, EDGE)
	var reach := roundi(clampf(absf(gas), 0.0, 1.0) * (h / 2))
	if gas > 0.0:
		c.fill_rect(x, mid - reach, 3, reach, YELLOW if gas < .99 else GREEN)
	elif gas < 0.0:
		c.fill_rect(x, mid + 1, 3, reach, RED)


## STATUS PANEL's speed dial: a half round face, the needle at `pace`.
static func _dial(c: Canvas, cx: int, cy: int, pace: float) -> void:
	c.circle(cx, cy, 12, EDGE)
	c.circle(cx, cy, 11, DIAL)
	c.fill_rect(cx - 12, cy + 3, 25, 10, FACE)
	for k in 7:
		var a := PI * (1.0 + float(k) / 6.0)
		c.set_pixel(
			cx + roundi(cos(a) * 9.0), cy + roundi(sin(a) * 9.0), NEEDLE.r8, NEEDLE.g8, NEEDLE.b8
		)
	var a2 := PI * (1.0 + pace)
	c.line(cx, cy, cx + roundi(cos(a2) * 10.0), cy + roundi(sin(a2) * 10.0), NEEDLE)
	c.circle(cx, cy, 1, NEEDLE)
