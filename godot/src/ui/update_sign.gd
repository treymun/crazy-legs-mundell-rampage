## The update notice's sign on the title (pass 14, update_notice.gd): a tin
## sign strapped to the yard's light pole, NEW VERSION on its red band, the
## version and GIT IT, which lights up like the title's plate while it is
## picked. On Android its small print says the download installs over the
## old copy with the saves kept.
class_name UpdateSign
extends RefCounted

## The sign (the button's rect); Android's is taller for the small print.
const RECT := Rect2i(224, 6, 92, 43)
const RECT_TALL := Rect2i(224, 6, 92, 63)
## Where the light pole stands behind the sign (its straps).
const POLE_X := 284
## Android's small print, under GIT IT.
const NOTE := ["TAP IT ONCE IT'S DOWN.", "IT GOES OVER THIS ONE,", "YER SAVES KEPT."]
const ENAMEL := Color(226 / 255.0, 208 / 255.0, 166 / 255.0)
const ENAMEL_LO := Color(176 / 255.0, 152 / 255.0, 112 / 255.0)
const RUST_SPOT := Color(132 / 255.0, 70 / 255.0, 36 / 255.0)
const RUST_STREAK := Color(186 / 255.0, 140 / 255.0, 96 / 255.0)
const STRAP := Color(40 / 255.0, 34 / 255.0, 30 / 255.0)
const STRAP_HI := Color(104 / 255.0, 94 / 255.0, 84 / 255.0)
const SHADOW := Color(12 / 255.0, 10 / 255.0, 12 / 255.0)


## The sign's rect: with Android's small print (`android`) or without.
static func rect(android: bool) -> Rect2i:
	return RECT_TALL if android else RECT


## The sign for `version`: lit while `active`; `beat` steps its bulbs.
static func draw(c: Canvas, version: String, android: bool, active: bool, beat: int) -> void:
	var r := rect(android)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	# The straps round the pole, above and below the sign, and its shadow.
	for sy: int in [y - 3, y + h + 1]:
		c.fill_rect(POLE_X - 5, sy, 11, 2, STRAP)
		c.fill_rect(POLE_X - 5, sy, 11, 1, STRAP_HI)
	c.fill_rect(x + 2, y + h, w - 1, 1, SHADOW)
	c.fill_rect(x + w, y + 2, 1, h - 1, SHADOW)
	# The tin: a dark rim, the enamel, a rolled lip, rust bitten into the
	# corners and run down from the bolts.
	c.fill_rect(x, y, w, h, Menu.DARK)
	c.fill_rect(x + 1, y + 1, w - 2, h - 2, Menu.BRASS_HI if active else ENAMEL_LO)
	c.fill_rect(x + 2, y + 2, w - 4, h - 4, ENAMEL)
	c.fill_rect(x + 2, y + h - 3, w - 4, 1, ENAMEL_LO)
	for spot: Vector2i in [
		Vector2i(x + 2, y + 2),
		Vector2i(x + 3, y + 2),
		Vector2i(x + 2, y + 3),
		Vector2i(x + w - 4, y + h - 3),
		Vector2i(x + w - 3, y + h - 4),
		Vector2i(x + w - 3, y + h - 3),
		Vector2i(x + 5, y + h - 3),
		Vector2i(x + w - 3, y + 2),
	]:
		c.fill_rect(spot.x, spot.y, 1, 1, RUST_SPOT)
	# The red band, bolted on, with rust run down under each bolt.
	c.fill_rect(x + 4, y + 3, w - 8, 11, Menu.HULL)
	c.fill_rect(x + 4, y + 3, w - 8, 1, Menu.HULL_HI)
	c.fill_rect(x + 4, y + 13, w - 8, 1, Menu.HULL_LO)
	HUD.text(c, "NEW VERSION", x + w / 2, y + 5, "body", Menu.BRIGHT, true, false)
	for bx: int in [x + 6, x + w - 7]:
		c.fill_rect(bx, y + 8, 1, 1, Menu.BRASS_HI)
		c.fill_rect(bx, y + 14, 1, 3, RUST_STREAK)
	HUD.text(c, version + " OUT", x + w / 2, y + 16, "body", Menu.TIN_INK, true, false)
	# GIT IT: painted on the tin, or on a lit plate while picked.
	var plate := Rect2i(x + 14, y + 25, w - 28, 16)
	if active:
		c.fill_rect(plate.position.x, plate.position.y, plate.size.x, plate.size.y, Menu.DARK)
		c.fill_rect(
			plate.position.x + 1,
			plate.position.y + 1,
			plate.size.x - 2,
			plate.size.y - 2,
			Menu.RUST_HOT
		)
		var n := 0
		for bx in range(plate.position.x + 1, plate.end.x - 1, 4):
			for by: int in [plate.position.y, plate.end.y - 2]:
				var on := (n + beat) % 3 != 0
				c.fill_rect(bx, by, 2, 1, Menu.BULB_ON if on else Menu.RUST_DEEP)
				n += 1
		Menu.shell(c, plate.position.x - 8, plate.position.y + 4)
		Menu.shell(c, plate.end.x + 1, plate.position.y + 4, true)
	HUD.text(
		c,
		"GIT IT",
		x + w / 2,
		plate.position.y + 1,
		"heading",
		Menu.BRIGHT if active else Menu.HULL,
		true,
		active
	)
	if android:
		for i in NOTE.size():
			HUD.text(c, str(NOTE[i]), x + w / 2, y + 43 + i * 6, "mini", Menu.TIN_INK, true, false)
