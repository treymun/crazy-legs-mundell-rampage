## COUNTY RUN's screens (CLAUDE.md "County Run"): the map picker (state
## "county"), the run's HUD (XP bar, level, clock, the three slots and the
## abilities), the reward cards over a held world (a milestone's in their own
## colours), the swap a full set of slots asks for, the build screen and the
## end of the run. Each draw notes where a tap lands (LobbyScreens.zones,
## cleared every render), and county_input.gd turns taps, clicks and keys
## into the same actions, so they work by touch, mouse and keys alike.
class_name CountyScreens
extends RefCounted

const VIEW := Renderer.VIEW
const CARD_Y := 28
const CARD_W := 102
const CARD_H := 113
const CARD_GAP := 4
const WOOD := Color(30 / 255.0, 21 / 255.0, 16 / 255.0)
const WOOD_HI := Color(46 / 255.0, 32 / 255.0, 24 / 255.0)
const RIBBON := Color(150 / 255.0, 34 / 255.0, 26 / 255.0)
const GOLD := Color(246 / 255.0, 206 / 255.0, 96 / 255.0)
const GOLD_LO := Color(122 / 255.0, 86 / 255.0, 30 / 255.0)
const XP_FILL := Color(120 / 255.0, 220 / 255.0, 120 / 255.0)
const XP_BACK := Color(22 / 255.0, 30 / 255.0, 18 / 255.0)
## A card's top strip by what it is.
const STRIPS := {
	"upgrade": Color(176 / 255.0, 120 / 255.0, 50 / 255.0),
	"weapon": Color(70 / 255.0, 132 / 255.0, 64 / 255.0),
	"perk": Color(70 / 255.0, 98 / 255.0, 138 / 255.0),
	"milestone": Color(186 / 255.0, 44 / 255.0, 30 / 255.0),
}
## Seconds a new set of cards waits before a key or a tap takes one (a shot
## still held from the fight is not a pick).
const ARM := .4

## The map picker's row, the card under the cursor, the card whose weapon
## waits for a slot (-1: none) and the slot picked for it, the build screen,
## the end screen's button, and when the cards on screen came up.
static var map_row := 0
static var card_row := 0
static var swapping := -1
static var swap_slot := -1
static var build_open := false
static var over_row := 0
static var _shown := ""
static var _shown_at := 0
## The picker's DAILY RUN switch, and the board heard from the server.
static var daily := false
static var board: CountyBoard = null


## True while the run puts something over the view that takes taps (cards,
## the swap, the build screen, the end).
static func covering(game) -> bool:
	var f = CountyMode.run(game)
	return f != null and (not f.pending.is_empty() or build_open or f.over)


## The pointer should be free (a desktop): something to click on is up.
static func wants_pointer(game) -> bool:
	return covering(game)


## Keys and taps on the cards wait ARM seconds after they come up.
static func armed() -> bool:
	return Time.get_ticks_msec() - _shown_at >= int(ARM * 1000.0)


static func reset() -> void:
	card_row = 0
	swapping = -1
	swap_slot = -1
	build_open = false
	over_row = 0
	_shown = ""


## The picker (state "county"); false for any other state.
static func draw_screen(main) -> bool:
	if String(main.state) != "county":
		return false
	draw_maps(main.canvas, main.menu)
	return true


## Everything COUNTY RUN draws over the game (main_state.gd render()).
static func draw_over(c: Canvas, game) -> void:
	var f = CountyMode.run(game)
	if f == null:
		return
	if f.over:
		draw_end(c, game, f)
		return
	var key := "%d:%d:%s" % [f.level, f.pending.size(), str(f.offer)]
	if key != _shown:
		_shown = key
		_shown_at = Time.get_ticks_msec()
		card_row = clampi(card_row, 0, maxi(0, f.offer.size() - 1))
		swapping = -1
		swap_slot = -1
	if build_open:
		draw_build(c, game, f)
	elif not f.pending.is_empty() and not f.offer.is_empty():
		if swapping >= 0:
			draw_swap(c, game, f)
		else:
			draw_cards(c, game, f)
	else:
		draw_hud(c, game, f)


# ------------------------------------------------------------------ picker


static func draw_maps(c: Canvas, menu: Menu) -> void:
	menu.draw_sheet(c, "COUNTY RUN")
	# The DAILY RUN switch (T, or a tap): the day's dice, the same for everyone.
	var switch := Rect2i(14, 30, 292, 10)
	LobbyScreens.box(c, switch, LobbyScreens.LIT if daily else LobbyScreens.PLAIN)
	var line := (
		"DAILY RUN %s: TODAY'S DICE, SAME FOR EVERYONE (T)" % CountyBoard.today()
		if daily
		else "SURVIVE AS LONG AS YOU CAN.  T: DAILY RUN, ONE BOARD FOR EVERYONE"
	)
	HUD.text(c, line, 160, 32, "mini", GOLD if daily else LobbyScreens.SOFT, true)
	LobbyScreens.zone(switch, "daily", 0)
	var maps := CountyData.maps()
	for i in maps.size():
		var m: Dictionary = maps[i]
		var y := 41 + i * 43
		var r := Rect2i(14, y, 292, 40)
		var here: bool = i == posmod(map_row, maps.size())
		LobbyScreens.box(c, r, LobbyScreens.LIT if here else LobbyScreens.PLAIN)
		if here:
			Menu.shell(c, 19, y + 6)
		HUD.text(c, String(m.get("title", "")), 33, y + 3, "menu", HUD.AMBER if here else HUD.INK)
		HUD.text(c, String(m.get("tag", "")), 300, y + 4, "mini", Menu.FADED, false, true, true)
		var lines := PixelType.wrap(String(m.get("blurb", "")), 268, "mini")
		for k in mini(2, lines.size()):
			HUD.text(c, lines[k], 33, y + 15 + k * 7, "mini", LobbyScreens.SOFT)
		if daily:
			_daily_line(c, String(m.get("id", "")), y + 30)
			LobbyScreens.zone(r, "map", i)
			continue
		var best := CountyRecords.best(String(m.get("id", "")))
		var record := "NO RUNS YET"
		if not best.is_empty():
			record = (
				"BEST %s  LEVEL %d  KILLS %d  RUNS %d"
				% [
					CountyRecords.clock_text(float(best.get("time", 0.0))),
					int(best.get("level", 1)),
					int(best.get("kills", 0)),
					int(best.get("runs", 0))
				]
			)
		HUD.text(
			c, record, 33, y + 30, "mini", LobbyScreens.GREEN if not best.is_empty() else Menu.FADED
		)
		LobbyScreens.zone(r, "map", i)
	LobbyScreens.footer(c, "ARROWS PICK   ENTER GO   ESC BACK")
	LobbyScreens.back_button(c)


# ------------------------------------------------------------------ the HUD


static func draw_hud(c: Canvas, game, f) -> void:
	if game.player.health <= 0 or game.map:
		return
	_elite_tags(c, game, f)
	var need := CountyData.xp_to_next(f.level)
	var fill := clampi(roundi(320.0 * float(f.xp) / maxf(1.0, float(need))), 0, 320)
	c.fill_rect(0, VIEW - 3, 320, 3, XP_BACK)
	c.fill_rect(0, VIEW - 3, fill, 3, XP_FILL)
	c.fill_rect(0, VIEW - 3, 320, 1, Color(0, 0, 0))
	# The gun slots, armor and level are on the status bar (hud.gd).
	var right := CountyRecords.clock_text(f.run_time)
	HUD.text(c, right, 317, VIEW - 13, "body", HUD.INK, false, true, true)
	var bits: Array = []
	if CountyBuild.has(f, "mudslide"):
		var wait: float = f.dash_ready - game.clock
		bits.append("SLIDE READY" if wait <= 0.0 else "SLIDE %.0fS" % ceilf(wait))
	if CountyBuild.has(f, "second_wind"):
		bits.append("2ND WIND USED" if f.second_wind_used else "2ND WIND")
	if game.clock < f.guard_until:
		bits.append("LAST STAND")
	if game.clock < f.burst_until:
		bits.append("BREAKAWAY")
	if f.six_ready:
		bits.append("CHARGED")
	elif f.streak >= 2:
		bits.append("STREAK %d" % f.streak)
	if f.run_time < f.lull_until:
		bits.append("LULL %ds" % ceili(f.lull_until - f.run_time))
	elif f.next_elite - f.run_time < 5.0:
		bits.append("ELITE COMIN'")
	if not bits.is_empty():
		HUD.text(c, "  ".join(bits), 317, VIEW - 21, "mini", GOLD, false, true, true)


# ------------------------------------------------------------------ cards


## A gold ELITE and a health bar over each elite in sight.
static func _elite_tags(c: Canvas, game, f) -> void:
	if f.elite_ids.is_empty():
		return
	var p: Player = game.player
	for e: Enemy in game.enemies:
		if not e.alive or not f.elite_ids.has(e.get_instance_id()):
			continue
		if Vector2(e.x - p.x, e.y - p.y).length() > 24.0:
			continue
		var top: float = game.world.stand(e) + e.z + e.height + .25
		if not game.world.visible(p.x, p.y, e.x, e.y, p.eye, top - .3):
			continue
		var at: Vector3 = game.to_canvas(e.x, e.y, top)
		if at.z <= 0.0 or at.x < 10 or at.x > 310 or at.y < 6 or at.y > VIEW - 20:
			continue
		var x := int(at.x)
		var y := int(at.y)
		HUD.text(c, "ELITE", x, y - 9, "mini", GOLD, true)
		var w := 20
		var share := clampf(e.hp / maxf(1.0, e.max_hp), 0.0, 1.0)
		c.fill_rect(x - w / 2 - 1, y - 2, w + 2, 4, Color(0, 0, 0))
		c.fill_rect(x - w / 2, y - 1, roundi(w * share), 2, HUD.LOW_HOT)


static func _backdrop(c: Canvas, big: bool) -> void:
	c.fill_rect(0, 0, 320, VIEW, RIBBON.darkened(.55) if big else WOOD)
	for y in range(0, VIEW, 13):
		c.fill_rect(0, y, 320, 1, GOLD_LO if big else WOOD_HI)


static func draw_cards(c: Canvas, game, f) -> void:
	var entry: Array = f.pending[0]
	var big := bool(entry[1])
	_backdrop(c, big)
	# The heading drops in as the cards come up; a milestone's ribbon flashes.
	var age := (Time.get_ticks_msec() - _shown_at) / 1000.0
	var drop := roundi(maxf(0.0, 1.0 - age / .22) * -24.0)
	if big:
		var flash := age < .6 and int(age * 10.0) % 2 == 0
		c.fill_rect(0, 3 + drop, 320, 22, GOLD_LO if flash else RIBBON)
		c.fill_rect(0, 3 + drop, 320, 1, GOLD)
		c.fill_rect(0, 24 + drop, 320, 1, GOLD)
		HUD.text(c, "MILESTONE! LEVEL %d" % int(entry[0]), 160, 5 + drop, "heading", GOLD, true)
	else:
		HUD.text(c, "LEVEL %d!" % int(entry[0]), 160, 4 + drop, "heading", HUD.AMBER, true)
	var note := "PICK A BIG ONE." if big else "PICK ONE. THE CLOCK IS STOPPED."
	if f.pending.size() > 1:
		note = "PICK ONE (%d MORE AFTER THIS)." % (f.pending.size() - 1)
	if f.tips and not big:
		var tips: Array = CountyData.all().get("tips", [])
		if not tips.is_empty():
			note = "TIP: " + String(tips[f.level % tips.size()])
	HUD.text(
		c,
		note,
		160,
		21 if not big else 26,
		"mini",
		GOLD if note.begins_with("TIP") else LobbyScreens.SOFT,
		true
	)
	for i in f.offer.size():
		_card(
			c,
			game,
			f,
			i,
			Rect2i(
				5 + i * (CARD_W + CARD_GAP),
				CARD_Y + (4 if big else 0),
				CARD_W,
				CARD_H - (4 if big else 0)
			),
			big
		)
	LobbyScreens.button(c, Rect2i(5, 143, 52, 11), "BUILD", false, "build")
	# The card under the cursor in full, beside BUILD.
	var here: int = clampi(card_row, 0, f.offer.size() - 1)
	var d := CountyBuild.describe(game, f, f.offer[here])
	var lines := PixelType.wrap(String(d.get("detail", "")), 254, "mini")
	for k in mini(2, lines.size()):
		HUD.text(c, lines[k], 62, 142 + k * 7, "mini", HUD.INK)


static func _card(c: Canvas, game, f, i: int, r: Rect2i, big: bool) -> void:
	var card: Dictionary = f.offer[i]
	var here: bool = i == card_row
	var face := LobbyScreens.LIT if here else LobbyScreens.PLAIN
	var edge := GOLD if here else (GOLD_LO if big else LobbyScreens.EDGE)
	LobbyScreens.box(c, r, face, edge)
	if here:
		LobbyScreens.box(c, r.grow(1), face, GOLD)
		LobbyScreens.box(c, r, face, GOLD)
	var d := CountyBuild.describe(game, f, card)
	var strip: Color = STRIPS.get(String(card["type"]), STRIPS["upgrade"])
	c.fill_rect(r.position.x + 1, r.position.y + 1, r.size.x - 2, 9, strip)
	HUD.text(c, "%d" % (i + 1), r.position.x + 3, r.position.y + 3, "mini", GOLD)
	HUD.text(c, String(d.get("badge", "")), r.position.x + 10, r.position.y + 3, "mini", HUD.INK)
	var x := r.position.x + 4
	var y := r.position.y + 13
	var width := r.size.x - 8
	for line in PixelType.wrap(String(d["title"]), width, "body").slice(0, 2):
		HUD.text(c, line, x, y, "body", GOLD if big else HUD.AMBER)
		y += 9
	# Rank pips: held gold, this one green, the rest empty.
	var pips: Array = d.get("pips", [0, 0])
	if int(pips[1]) > 0:
		for k in int(pips[1]):
			var px := x + k * 9
			var ink := (
				GOLD
				if k < int(pips[0])
				else (LobbyScreens.GREEN if k == int(pips[0]) else Menu.DIM)
			)
			c.fill_rect(px, y + 1, 7, 5, Color(0, 0, 0))
			if k <= int(pips[0]):
				c.fill_rect(px + 1, y + 2, 5, 3, ink)
			else:
				c.fill_rect(px + 1, y + 2, 5, 3, LobbyScreens.PLAIN)
		y += 9
	y += 2
	# What changes, in big letters.
	for line in PixelType.wrap(String(d.get("big", "")), width, "body").slice(0, 5):
		HUD.text(c, line, x, y, "body", HUD.INK)
		y += 9
	if String(card["type"]) == "weapon":
		HUD.text(
			c, String(d["lines"][1]).replace("COMES WITH ", "AMMO "), x, y + 1, "mini", Menu.FADED
		)
		y += 8
	var trade := String(d.get("small_trade", ""))
	if trade != "":
		for line in PixelType.wrap(trade, width, "mini").slice(0, 2):
			HUD.text(c, line, x, y + 2, "mini", HUD.LOW_HOT)
			y += 7
	HUD.text(c, String(d.get("tag", "")), x, r.end.y - 10, "mini", LobbyScreens.GREEN)
	LobbyScreens.zone(r, "card", i)


## A full set of slots: which weapon goes for the new one (and what it takes
## with it), then CONFIRM, or CANCEL back to the same cards.
static func draw_swap(c: Canvas, game, f) -> void:
	var card: Dictionary = f.offer[swapping]
	var gun := int(card["gun"])
	_backdrop(c, false)
	HUD.text(c, "SWAP OUT WHICH?", 160, 4, "heading", HUD.AMBER, true)
	HUD.text(
		c,
		"TAKING: " + CountyData.gun_name(gun) + ". " + CountyData.ammo_text(gun) + ".",
		160,
		21,
		"mini",
		LobbyScreens.SOFT,
		true
	)
	for i in f.slots.size():
		var old := int(f.slots[i])
		var r := Rect2i(10, 30 + i * 29, 300, 27)
		var here: bool = i == swap_slot
		LobbyScreens.box(
			c,
			r,
			LobbyScreens.LIT if here else LobbyScreens.PLAIN,
			GOLD if here else LobbyScreens.EDGE
		)
		var name := CountyData.gun_name(old)
		if old == game.armory.active:
			name += "  (IN HAND)"
		HUD.text(
			c,
			"%d  %s" % [i + 1, name],
			r.position.x + 4,
			r.position.y + 3,
			"body",
			HUD.AMBER if here else HUD.INK
		)
		var lost := CountyBuild.upgrades_on(f, old)
		var words := "NO UPGRADES ON IT."
		if not lost.is_empty():
			var bits: Array = []
			for u: Array in lost:
				bits.append("%s %d/%d" % [u[0], u[1], u[2]])
			words = "LOSES: " + ", ".join(bits)
		var lines := PixelType.wrap(words, 290, "mini")
		for k in mini(2, lines.size()):
			HUD.text(
				c,
				lines[k],
				r.position.x + 4,
				r.position.y + 12 + k * 7,
				"mini",
				HUD.LOW_HOT if not lost.is_empty() else Menu.FADED
			)
		LobbyScreens.zone(r, "slot", i)
	HUD.text(c, "PERKS AND MILESTONES STAY WITH YOU.", 160, 120, "mini", LobbyScreens.GREEN, true)
	if swap_slot >= 0:
		var old_gun := int(f.slots[swap_slot])
		HUD.text(
			c,
			"SWAP %s FOR %s?" % [CountyData.gun_name(old_gun), CountyData.gun_name(gun)],
			160,
			129,
			"mini",
			HUD.INK,
			true
		)
		LobbyScreens.button(c, Rect2i(60, 139, 90, 14), "CONFIRM", true, "confirm")
	LobbyScreens.button(c, Rect2i(170, 139, 90, 14), "CANCEL", swap_slot < 0, "cancel")


# ------------------------------------------------------------------ build


static func draw_build(c: Canvas, game, f) -> void:
	_backdrop(c, false)
	HUD.text(c, "YOUR BUILD", 160, 4, "heading", HUD.AMBER, true)
	HUD.text(
		c,
		"LEVEL %d   %s   %d KILLS" % [f.level, CountyRecords.clock_text(f.run_time), game.kills],
		160,
		21,
		"mini",
		LobbyScreens.SOFT,
		true
	)
	var y := _build_lines(c, f, 30, 148)
	if y < 120 and not f.picks.is_empty():
		HUD.text(c, "TAKEN, NEWEST FIRST:", 10, y + 2, "mini", Menu.FADED)
		y += 10
		var shown: Array = []
		for k in range(f.picks.size() - 1, -1, -1):
			shown.append("%d %s" % [int(f.picks[k][0]), String(f.picks[k][1])])
		for line in PixelType.wrap("   ".join(shown), 300, "mini"):
			if y > 136:
				break
			HUD.text(c, line, 10, y, "mini", LobbyScreens.SOFT)
			y += 7
	LobbyScreens.button(c, Rect2i(130, 141, 60, 13), "CLOSE", true, "close")


## The build's lines from y down to `bottom`: returns where it stopped.
static func _build_lines(c: Canvas, f, y: int, bottom: int) -> int:
	for row: Array in CountyBuild.summary(f):
		if y > bottom - 14:
			break
		HUD.text(c, String(row[0]), 10, y, "body", HUD.AMBER)
		y += 8
		for line in PixelType.wrap(String(row[1]), 296, "mini"):
			if y > bottom - 8:
				break
			HUD.text(c, line, 16, y, "mini", HUD.INK)
			y += 7
		y += 1
	return y


# ------------------------------------------------------------------ the end


static func draw_end(c: Canvas, game, f) -> void:
	var r: Dictionary = f.result
	c.fill_rect(0, 0, 320, VIEW, WOOD)
	c.fill_rect(0, 3, 320, 20, RIBBON)
	c.fill_rect(0, 3, 320, 1, GOLD)
	c.fill_rect(0, 22, 320, 1, GOLD)
	var title := String(CountyData.map(String(r.get("map", ""))).get("title", "COUNTY RUN"))
	HUD.text(c, "RUN OVER: " + title, 160, 6, "heading", GOLD, true)
	var time := float(r.get("time", 0.0))
	var best: Dictionary = r.get("best_before", {})
	var before := float(best.get("time", 0.0))
	HUD.text(c, "SURVIVED " + CountyRecords.clock_text(time), 160, 27, "menu", HUD.INK, true)
	if time > before:
		HUD.text(
			c,
			(
				"NEW PERSONAL BEST!"
				if before > 0.0
				else "FIRST RUN ON THIS MAP. THAT'S THE BEST TO BEAT."
			),
			160,
			38,
			"mini",
			LobbyScreens.GREEN,
			true
		)
	else:
		HUD.text(
			c, "PERSONAL BEST " + CountyRecords.clock_text(before), 160, 38, "mini", HUD.AMBER, true
		)
	HUD.text(
		c,
		"HIGHEST LEVEL %d     KILLS %d" % [int(r.get("level", 1)), int(r.get("kills", 0))],
		160,
		46,
		"body",
		HUD.AMBER,
		true
	)
	HUD.text(
		c,
		(
			"ELITES %d   XP %d   DAMAGE TAKEN %d   BEST STREAK %d"
			% [
				int(r.get("elites", 0)),
				int(r.get("xp", 0)),
				int(r.get("hurt", 0)),
				int(r.get("streak", 0))
			]
		),
		160,
		56,
		"mini",
		LobbyScreens.SOFT,
		true
	)
	HUD.text(c, "FINAL BUILD", 10, 65, "mini", Menu.FADED)
	var y := 72
	for row: Array in r.get("build", []):
		if y > 128:
			break
		var line := "%s: %s" % [row[0], row[1]]
		for part in PixelType.wrap(line, 200 if String(f.daily) != "" else 300, "mini"):
			if y > 128:
				break
			HUD.text(c, part, 10, y, "mini", HUD.INK)
			y += 7
	if String(game.features["county"].daily) != "":
		_daily_end(c, r)
	var labels := ["RETRY", "MAPS", "TITLE"]
	var ids := ["retry", "maps", "title"]
	for i in 3:
		LobbyScreens.button(c, Rect2i(18 + i * 100, 137, 84, 15), labels[i], i == over_row, ids[i])
	HUD.text(c, "ENTER RETRY   M MAPS   ESC TITLE", 160, 130, "mini", Menu.FADED, true)


# ------------------------------------------------------------------ daily run


static func toggle_daily() -> void:
	daily = not daily
	if daily:
		for map_id: String in CountyData.MAP_IDS:
			_board().fetch(map_id)


static func _board() -> CountyBoard:
	if board == null:
		board = CountyBoard.new()
	return board


## Every frame (main.gd): the board's knocks, and a finished daily run posted
## once (never from a tool, which must not knock on the real server).
static func board_frame(main) -> void:
	if board != null and board.busy():
		board.poll(Time.get_ticks_msec())
	var f = CountyMode.run(main.game) if main.game != null else null
	if f == null or not f.over or String(f.daily) == "" or f.result.has("posted"):
		return
	f.result["posted"] = true
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null and not CountyBoard.local:
		return
	var name := String(NetPlay.remembered().get("name", main.options.get("player_name", "MUNDELL")))
	f.result["name"] = name
	_board().post(name, f.result, String(f.daily))


## A map's row on the picker with DAILY RUN on: the day's best three.
static func _daily_line(c: Canvas, map_id: String, y: int) -> void:
	var rows: Array = _board().boards.get(map_id, [])
	var text := "ASKING THE SERVER..." if _board().busy() else "NOBODY HAS RUN IT TODAY. BE FIRST."
	if not rows.is_empty():
		var parts: Array = []
		for i in mini(3, rows.size()):
			parts.append(
				"%d %s %s" % [i + 1, rows[i][0], CountyRecords.clock_text(float(rows[i][1]))]
			)
		text = "TODAY: " + "   ".join(PackedStringArray(parts))
	HUD.text(c, text, 33, y, "mini", GOLD if not rows.is_empty() else Menu.FADED)


## The end of a daily run: the day's board for the map, this run marked.
static func _daily_end(c: Canvas, r: Dictionary) -> void:
	var map_id := String(r.get("map", ""))
	var rows: Array = _board().boards.get(map_id, [])
	var x := 214
	HUD.text(c, "TODAY'S BOARD", x, 65, "mini", GOLD)
	if rows.is_empty():
		HUD.text(c, "SENDING..." if _board().busy() else "NO ANSWER", x, 73, "mini", Menu.FADED)
		return
	var mine := _board().rank_of(map_id, String(r.get("name", "")), float(r.get("time", 0.0)))
	for i in rows.size():
		var row: Array = rows[i]
		var ink := GOLD if i + 1 == mine else HUD.INK
		HUD.text(c, "%d %s" % [i + 1, String(row[0]).substr(0, 10)], x, 73 + i * 8, "mini", ink)
		HUD.text(
			c,
			CountyRecords.clock_text(float(row[1])),
			312,
			73 + i * 8,
			"mini",
			ink,
			false,
			true,
			true
		)
