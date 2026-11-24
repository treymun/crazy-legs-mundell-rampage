## The update notice's sign on the title (pass 14, update_notice.gd): a tin
## sign strapped to the yard's light pole, NEW VERSION on its red band, the
## version and GIT IT, which lights up like the title's plate while it is
## picked. On Android its small print says the download installs over the
## old copy with the saves kept. With the in-game update (Android with the
## updater, UpdateNotice.in_game) the same tin is the update's panel: its
## band says what it is doing, a gauge fills while it fetches and checks,
## the plate is the one thing to press (GIT IT, HOLD IT, PUT IT IN,
## SETTIN'S, TRY AGIN) and the small print says the rest (words).
class_name UpdateSign
extends RefCounted

## The sign (the button's rect); Android's is taller for the small print.
const RECT := Rect2i(224, 6, 92, 43)
const RECT_TALL := Rect2i(224, 6, 92, 63)
## Where the light pole stands behind the sign (its straps).
const POLE_X := 284
## Android's small print, under GIT IT.
const NOTE := ["TAP IT ONCE IT'S DOWN.", "IT GOES OVER THIS ONE,", "YER SAVES KEPT."]
## Every stage and aside the panel can show (the checks measure them all).
const STAGES := [
	["", ""],
	["", "held"],
	["asking", ""],
	["fetching", ""],
	["checking", ""],
	["ready", ""],
	["ready", "busy"],
	["ready", "declined"],
	["leave", ""],
	["leave", "nosettings"],
	["handed", ""],
	["full", ""],
	["bad", ""],
	["failed", ""],
	["missing", ""],
	["refused", ""],
]

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


## What the in-game update's panel says in `notice`'s stage: "head" (the
## band), "line" (under it; "" when the gauge shows), "gauge" (whether the
## gauge shows), "action" (the plate) and "notes" (three lines of small
## print).
static func words(notice: UpdateNotice) -> Dictionary:
	var v := notice.found
	var head := "NEW VERSION"
	var line := v + " OUT"
	var action := "GIT IT"
	var gauge := false
	var notes: Array[String] = []
	var fetch := notice.fetcher
	var done := UpdateNotice.megs(fetch.have) if fetch != null else 0
	var whole := UpdateNotice.megs(notice.want_size)
	match notice.stage:
		"":
			if notice.aside == "held":
				notes = ["HELD UP. GIT IT AGIN", "AN' IT PICKS UP", "WHERE IT LEFT OFF."]
			elif notice.want_size > 0:
				notes = [
					"%d MB. FETCHES HERE," % whole, "THEN YER PHONE PUTS", "IT IN. SAVES KEPT."
				]
			else:
				notes = ["FETCHES RIGHT HERE,", "THEN YER PHONE PUTS", "IT IN. SAVES KEPT."]
		"asking":
			head = "FETCHIN'"
			line = v
			action = "HOLD IT"
			notes = ["LOOKIN' IT UP...", "", ""]
		"fetching":
			head = "FETCHIN'"
			gauge = true
			action = "HOLD IT"
			if fetch != null and fetch.phase == "wait":
				notes = [
					"LINE DROPPED. TRYIN'",
					"AGIN IN %d..." % ceili(fetch.wait_left),
					"%d OF %d MB" % [done, whole],
				]
			else:
				notes = ["%d OF %d MB" % [done, whole], "PLAY ON IF YA LIKE,", "IT KEEPS FETCHIN'."]
		"checking":
			head = "CHECKIN' IT"
			gauge = true
			action = "HOLD IT"
			notes = ["MAKIN' SURE IT CAME", "THROUGH CLEAN.", ""]
		"ready":
			head = "ALL FETCHED"
			line = v
			action = "PUT IT IN"
			if notice.aside == "busy":
				notes = ["QUIT YER RUN FIRST:", "PUTTIN' IT IN SHUTS", "THE GAME."]
			elif notice.aside == "declined":
				notes = ["NO HARM DONE. PUT", "IT IN WHEN YER", "READY."]
			else:
				notes = ["YER PHONE ASKS ONCE:", "SAY INSTALL. SAVES", "KEPT."]
		"leave":
			head = "ONE SWITCH"
			line = "FIRST TIME"
			action = "SETTIN'S"
			if notice.aside == "nosettings":
				notes = ["SETTIN'S, APPS, THIS", "GAME, INSTALL UNKNOWN", "APPS: ALLOW."]
			else:
				notes = ["LET THIS GAME PUT IN", "ITS OWN UPDATES: FLIP", "ALLOW, COME BACK."]
		"handed":
			head = "PUTTIN' IN"
			line = v
			action = "PUT IT IN"
			notes = ["SAY INSTALL ON YER", "PHONE'S BOX. THE GAME", "SHUTS A SPELL."]
		"full":
			head = "PLUMB FULL"
			line = "NEEDS %d MB" % UpdateNotice.megs(notice.needed)
			action = "TRY AGIN"
			notes = ["CLEAR SOME ROOM ON", "YER PHONE, THEN", "TRY AGIN."]
		"bad":
			head = "CAME OUT BAD"
			line = v
			action = "TRY AGIN"
			notes = ["IT CAME THROUGH", "MANGLED TWICE. TRY", "AGIN LATER."]
		"failed":
			head = "LINE'S DEAD"
			line = v
			action = "TRY AGIN"
			notes = ["COULDN'T GIT IT.", "CHECK YER SIGNAL,", "THEN TRY AGIN."]
		"missing":
			head = "NOT IN YET"
			line = v
			action = "TRY AGIN"
			notes = ["THE NEW ONE AIN'T", "ON THE SHELF YET.", "TRY AGIN IN A BIT."]
		"refused":
			head = "WON'T TAKE"
			line = v
			action = "TRY AGIN"
			notes = ["YER PHONE WOULDN'T", "TAKE IT. TRY AGIN OR", "GIT IT OFF THE SITE."]
	return {"head": head, "line": line, "gauge": gauge, "action": action, "notes": notes}


## The plate's type: the title's heading when the word fits, else menu type.
static func plate_style(action: String) -> String:
	return "heading" if PixelType.text_width(action, "heading") <= RECT.size.x - 20 else "menu"


## The sign for `version`: lit while `active`; `beat` steps its bulbs. With
## `notice` updating the game itself, its panel (words).
static func draw(
	c: Canvas, version: String, android: bool, active: bool, beat: int, notice: UpdateNotice = null
) -> void:
	var said := {}
	if notice != null and notice.in_game():
		said = words(notice)
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
	var head := str(said.get("head", "NEW VERSION"))
	HUD.text(c, head, x + w / 2, y + 5, "body", Menu.BRIGHT, true, false)
	for bx: int in [x + 6, x + w - 7]:
		c.fill_rect(bx, y + 8, 1, 1, Menu.BRASS_HI)
		c.fill_rect(bx, y + 14, 1, 3, RUST_STREAK)
	var show_gauge: bool = said.get("gauge", false)
	if show_gauge:
		gauge(c, x + 8, y + 16, w - 16, notice.progress(), beat)
	else:
		var line := str(said.get("line", version + " OUT"))
		HUD.text(c, line, x + w / 2, y + 16, "body", Menu.TIN_INK, true, false)
	# GIT IT: painted on the tin, or on a lit plate while picked.
	var action := str(said.get("action", "GIT IT"))
	var style := plate_style(action)
	var inset := 14 if style == "heading" else 8
	var plate := Rect2i(x + inset, y + 25, w - inset * 2, 16)
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
		action,
		x + w / 2,
		plate.position.y + (1 if style == "heading" else 4),
		style,
		Menu.BRIGHT if active else Menu.HULL,
		true,
		active
	)
	if android:
		var notes: Array = said.get("notes", NOTE)
		for i in notes.size():
			HUD.text(c, str(notes[i]), x + w / 2, y + 43 + i * 6, "mini", Menu.TIN_INK, true, false)


## The fuel-gauge bar: `fraction` of `w` lit in two-pixel cells, the lit end
## flickering with `beat`.
static func gauge(c: Canvas, x: int, y: int, w: int, fraction: float, beat: int) -> void:
	c.fill_rect(x, y, w, 7, Menu.DARK)
	c.fill_rect(x + 1, y + 1, w - 2, 5, Menu.RUST_DEEP)
	var cells := (w - 2) / 3
	var lit := clampi(int(fraction * cells), 0, cells)
	for i in cells:
		var on := i < lit or (i == lit and lit < cells and beat % 2 == 0)
		var cell := Menu.BULB_ON if on else ENAMEL_LO
		c.fill_rect(x + 2 + i * 3, y + 2, 2, 3, cell)
