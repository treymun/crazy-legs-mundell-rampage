## What the 5v5 round modes draw (tactical_mode.gd), all for this machine's
## player: the hostages and the shine bomb in the world, the score and the
## clock, the cash, the kill feed, teammates' tags, the sites, the plant and
## fuse bars, the round's banner, the buy menu and the screen of a player who
## is out (watching a teammate, or the scoreboard).
##
## The buy menu is this machine's alone (`open`, `cursor`): B opens and shuts
## it, the number keys (1-9, 0, -, =, then , and .) or the arrows and ENTER buy, ESC shuts it
## (main_input.gd hands the keys here first in a 5v5 game).
class_name TacticalScreens
extends RefCounted

const OUTLAW_TINT := [1.3, .82, .66]
const DEPUTY_TINT := [.7, .92, 1.3]
const OUTLAW_INK := Color8(240, 120, 84)
const DEPUTY_INK := Color8(120, 176, 255)
const GREEN := Color8(120, 210, 90)
const PLATE := Color8(30, 21, 17)
const GREY := Color8(120, 104, 88)
const SHOP_KEYS := [
	KEY_1,
	KEY_2,
	KEY_3,
	KEY_4,
	KEY_5,
	KEY_6,
	KEY_7,
	KEY_8,
	KEY_9,
	KEY_0,
	KEY_MINUS,
	KEY_EQUAL,
	KEY_COMMA,
	KEY_PERIOD,
]
const SHOP_NAMES := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "<", ">"]

## The title's 5V5 SHOWDOWN picker: its rows (mode, map, match, START), the
## match lengths (rounds to win), and what each map and mode is.
const PICKER_ROWS := 4
const MATCH_LENGTHS := [4, 7]
const MAP_TITLES := {
	"grainyard": "PUCKETT GRAIN CO-OP",
	"holler": "HOLLER DISTILLERY",
	"salvage": "MUNDELL'S SALVAGE",
}
const MAP_LINES := {
	"grainyard":
	["THREE LANES, BOXCARS IN THE RAIL YARD.", "A: THE DUMP PIT   B: THE SEED WAREHOUSE"],
	"holler":
	["A CREEK ACROSS THE MIDDLE, ONE BRIDGE.", "A: THE STILL HOUSE   B: THE BOTTLING YARD"],
	"salvage": ["TIGHT JUNK CANYONS, CORNERS EVERYWHERE.", "A: THE CRUSHER PIT   B: THE TIRE BARN"],
}
const MODE_LINES := {
	Modes.BOMB: "OUTLAWS PLANT THE SHINE BOMB. DEPUTIES CUT THE FUSE.",
	Modes.HOSTAGE: "DEPUTIES WALK A HOSTAGE OUT. OUTLAWS HOLD 'EM.",
}

## The buy menu (this machine's): open, the row the cursor is on, the last
## word it had (NOT ENOUGH CASH...) and until when.
static var open := false
static var cursor := 0
## The store's page: 0 the guns, 1 gear and throwables (LEFT and RIGHT).
static var page := 0
static var note := ""
static var note_until := 0.0
## The slot this machine's own player plays (the one the keys and mouse
## drive); the view may be on a teammate's while they are out.
static var human := 0


static func reset() -> void:
	open = false
	cursor = 0
	page = 0
	note = ""
	note_until = 0.0


static func ink_for(st, p: Player) -> Color:
	return OUTLAW_INK if TacticalMode.side_of(st, p) == 0 else DEPUTY_INK


## The tint of a player's pictures: by the side they play this half.
static func tint_for(game, p: Player) -> Array:
	var st = Modes.feature(game)
	if st == null:
		return Modes.TINTS[p.slot % Modes.TINTS.size()]
	return OUTLAW_TINT if TacticalMode.side_of(st, p) == 0 else DEPUTY_TINT


# ----------------------------------------------------------------- world


## The hostages and the shine bomb (pooled sprites).
static func sprites(game, st) -> Array:
	var out: Array = []
	var art: Assets = game.art
	if String(st.mode) == Modes.HOSTAGE:
		for hostage: Array in st.hostages:
			if String(hostage[2]) == "rescued":
				continue
			var x := float(hostage[0])
			var y := float(hostage[1])
			if not game.in_view(x, y, 1.0):
				continue
			var image := "coot_0" if art.art_index.has("coot_0") else "player_front_0"
			image = art.tinted_art(image, [1.25, 1.2, .85])
			var spr = game.pooled(x, y, image, .98, game.world.elevation(x, y))
			spr.body = true
			out.append(spr)
	elif String(st.mode) == Modes.BOMB and st.bomb is Dictionary and not st.bomb.is_empty():
		var state := String(st.bomb["state"])
		if state in ["dropped", "planted", "defused"]:
			var x := float(st.bomb["x"])
			var y := float(st.bomb["y"])
			if game.in_view(x, y, 1.0) and art.art_index.has("town_tnt_crate"):
				var high := .42 if state != "dropped" else .32
				out.append(game.pooled(x, y, "town_tnt_crate", high, game.world.elevation(x, y)))
	return out


# ------------------------------------------------------------------ HUD


## Over the view, under the gun.
static func draw_view(c: Canvas, game, st) -> void:
	var me: Player = game.local_player
	var rules := Modes.rules(game) as TacticalMode
	for q: Player in game.players:
		if q != me and q.team == me.team:
			_mate_tag(c, game, st, me, q)
	_objective_tags(c, game, st, me)
	_top_strip(c, game, st, rules, me)
	_feed(c, game, st)
	_bars(c, game, st, me)
	if me.slot != human:
		HUD.text(c, "WATCHING " + Modes.tag(me), 160, 22, "body", HUD.AMBER, true)
	if String(st.phase) == "post":
		_round_banner(c, game, st)
	elif String(st.phase) == "freeze":
		var left := maxi(1, int(ceil(float(st.phase_until) - game.clock)))
		HUD.text(c, str(left), 160, 50, "heading", HUD.AMBER, true)
		if not open:
			HUD.text(c, "B  BUY MENU", 160, 66, "body", HUD.INK, true)
	if open:
		draw_shop(c, game, st)


## The score, the clock, the alive pips and the cash across the top.
static func _top_strip(c: Canvas, game, st, rules: TacticalMode, me: Player) -> void:
	var w: Array = st.wins
	var left := int(ceil(rules.clock_left(game, st)))
	var planted: bool = (
		String(st.mode) == Modes.BOMB and String(st.bomb.get("state", "")) == "planted"
	)
	c.fill_rect(86, 0, 148, 9, PLATE)
	var my_team := me.team
	var foe_team := 1 - my_team
	var mine_ink := ink_for(st, me)
	var foe_ink := DEPUTY_INK if TacticalMode.side_of(st, me) == 0 else OUTLAW_INK
	HUD.text(c, str(int(w[my_team])), 94, 1, "mini", mine_ink, true)
	HUD.text(c, str(int(w[foe_team])), 226, 1, "mini", foe_ink, true)
	var clock_ink := Color8(255, 90, 60) if planted else HUD.INK
	var clock := "%d:%02d" % [left / 60, left % 60]
	if planted:
		clock = "BOMB " + clock
	HUD.text(c, clock, 160, 1, "mini", clock_ink, true)
	_pips(c, game, my_team, 120, mine_ink, false)
	_pips(c, game, foe_team, 200, foe_ink, true)
	HUD.text(c, "CASH %d" % int(st.money[me.slot]), 4, 1, "body", GREEN)
	var side := TacticalMode.side_name(st, me)
	var vest := int(round(float(st.armor[me.slot])))
	var gear := side
	if vest > 0:
		gear += "  VEST %d%s" % [vest, "+HAT" if bool(st.helmet[me.slot]) else ""]
	if bool(st.snips[me.slot]):
		gear += "  SNIPS"
	HUD.text(c, gear, 4, 11, "mini", mine_ink)
	HUD.text(
		c, "ROUND %d/%d" % [int(st.round_no), TacticalMode.max_rounds(st)], 4, 18, "mini", HUD.DIM
	)


## A team's five pips: lit for each one up.
static func _pips(c: Canvas, game, team: int, x: int, ink: Color, rightward: bool) -> void:
	var k := 0
	for p: Player in game.players:
		if p.team != team:
			continue
		var px := x + (k * 4 if rightward else -k * 4)
		c.fill_rect(px, 3, 3, 3, ink if p.health > 0 else GREY)
		k += 1


static func _feed(c: Canvas, _game, st) -> void:
	var y := 2
	for row: Array in st.feed:
		var team := int(row[2])
		var ink := OUTLAW_INK if team == int(st.outlaws) else DEPUTY_INK
		HUD.text(c, String(row[0]), 316, y, "mini", ink, false, true, true)
		y += 7


## A teammate's tag over their head (through walls), or at the view's edge.
static func _mate_tag(c: Canvas, game, st, _me: Player, q: Player) -> void:
	if q.health <= 0:
		return
	var head: float = game.world.elevation(q.x, q.y) + q.air + 1.14
	var at: Vector3 = game.to_canvas(q.x, q.y, head)
	if at.z <= 0.0 or at.x < 6.0 or at.x > Renderer.WIDTH - 6.0 or at.y < 10.0:
		return
	if at.y > Renderer.VIEW - 6.0:
		return
	var label := Modes.tag(q)
	var bomb = st.bomb if String(st.mode) == Modes.BOMB else {}
	if bomb is Dictionary and String(bomb.get("state", "")) == "carried":
		if int(bomb["slot"]) == q.slot:
			label += " BOMB"
	HUD.text(c, label, int(at.x), int(at.y) - 10, "mini", ink_for(st, q), true)


## The sites' letters, the planted bomb and the hostages, where they are.
static func _objective_tags(c: Canvas, game, st, me: Player) -> void:
	var sites = game.world.tactical.get("sites", {})
	if String(st.mode) == Modes.BOMB and sites is Dictionary:
		for name: String in sites:
			var centre := TacticalMode.box_centre(sites[name])
			_tag_at(c, game, me, centre.x, centre.y, 1.6, name, HUD.AMBER, false)
		var bomb: Dictionary = st.bomb
		var state := String(bomb.get("state", ""))
		var x := float(bomb.get("x", 0.0))
		var y := float(bomb.get("y", 0.0))
		if state == "planted":
			var beat := int(game.clock * 4.0) % 2 == 0
			var ink := Color8(255, 80, 50) if beat else HUD.AMBER
			_tag_at(c, game, me, x, y, .7, "SHINE BOMB", ink, false)
		elif state == "dropped" and TacticalMode.attacks(game, st, me):
			_tag_at(c, game, me, x, y, .6, "BOMB HERE", HUD.AMBER, false)
	elif String(st.mode) == Modes.HOSTAGE:
		for hostage: Array in st.hostages:
			var state := String(hostage[2])
			if state == "rescued":
				continue
			var ink := GREEN if state == "free" else HUD.AMBER
			var word := "HOSTAGE" if state == "free" else "CARRIED"
			_tag_at(c, game, me, float(hostage[0]), float(hostage[1]), 1.15, word, ink, true)
		var box := HostageMode.rescue_box(game)
		if not box.is_empty() and TacticalMode.attacks(game, st, me):
			var centre := TacticalMode.box_centre(box)
			_tag_at(c, game, me, centre.x, centre.y, 1.2, "RESCUE", GREEN, false)


static func _tag_at(
	c: Canvas, game, me: Player, x: float, y: float, z: float, word: String, ink: Color, sight: bool
) -> void:
	var top: float = game.world.elevation(x, y) + z
	var at: Vector3 = game.to_canvas(x, y, top)
	if at.z <= 0.0 or at.x < 8.0 or at.x > Renderer.WIDTH - 8.0 or at.y < 10.0:
		return
	if at.y > Renderer.VIEW - 8.0:
		return
	if sight and not game.world.visible(me.x, me.y, x, y, me.eye, top - .3):
		return
	HUD.text(c, word, int(at.x), int(at.y) - 6, "mini", ink, true)


## The plant and fuse bars, for this machine's player or anyone they watch.
static func _bars(c: Canvas, _game, st, me: Player) -> void:
	if String(st.mode) != Modes.BOMB or me.health <= 0:
		return
	var bomb: Dictionary = st.bomb
	if bomb.is_empty():
		return
	var state := String(bomb["state"])
	if state == "carried" and int(bomb["slot"]) == me.slot and float(bomb["plant"]) > 0.0:
		HUD.text(c, "PLANTING", 160, 102, "body", HUD.AMBER, true)
		_bar(c, 110, 112, 100, float(bomb["plant"]) / BombMode.PLANT_TIME, HUD.AMBER)
	elif state == "planted" and int(bomb["defuser"]) == me.slot and float(bomb["defuse"]) > 0.0:
		var whole := BombMode.defuse_time(st, me)
		HUD.text(c, "CUTTING THE FUSE", 160, 102, "body", GREEN, true)
		_bar(c, 110, 112, 100, float(bomb["defuse"]) / whole, GREEN)


static func _bar(c: Canvas, x: int, y: int, w: int, part: float, tone: Color) -> void:
	c.fill_rect(x - 1, y - 1, w + 2, 5, PLATE)
	var filled := clampi(roundi(w * clampf(part, 0.0, 1.0)), 0, w)
	if filled > 0:
		c.fill_rect(x, y, filled, 3, tone)


## Who took the round, in the post-round seconds.
static func _round_banner(c: Canvas, _game, st) -> void:
	var team := int(st.round_winner)
	if team < 0:
		return
	var side := 0 if team == int(st.outlaws) else 1
	var ink := OUTLAW_INK if side == 0 else DEPUTY_INK
	HUD.panel(c, 60, 40, 200, 34, PLATE)
	var line := "%s TAKE THE ROUND" % TacticalMode.SIDE_NAMES[side]
	HUD.text(c, line, 160, 45, "heading", ink, true)
	var w: Array = st.wins
	var score := (
		"%s %d  -  %d %s"
		% [TacticalMode.TEAM_NAMES[0], int(w[0]), int(w[1]), TacticalMode.TEAM_NAMES[1]]
	)
	HUD.text(c, score, 160, 62, "body", HUD.INK, true)


# -------------------------------------------------------------- the shop


## The buy menu: every item with its key, price and whether it can be had.
static func draw_shop(c: Canvas, game, st) -> void:
	var me: Player = game.local_player
	HUD.panel(c, 4, 22, 164, 132, PLATE)
	var left := int(ceil(TacticalMode.buy_left(game, st)))
	HUD.text(c, "GENERAL STORE", 10, 25, "body", HUD.AMBER)
	HUD.text(c, "%d" % int(st.money[me.slot]), 162, 25, "body", GREEN, false, true, true)
	# The two pages' tabs: the one shown lit.
	for k in 2:
		var tab_x := 10 + k * 60
		var on := k == page
		c.fill_rect(tab_x, 35, 56, 8, Canvas.rgb(82, 49, 31) if on else Canvas.rgb(44, 30, 24))
		HUD.text(
			c,
			["GUNS", "GEAR + THROWN"][k],
			tab_x + 28,
			36,
			"mini",
			HUD.AMBER if on else HUD.DIM,
			true
		)
	HUD.text(c, "< >", 162, 36, "mini", HUD.DIM, false, false, true)
	var rows := TacticalShop.page_rows(game, st, me, page)
	for i in rows.size():
		var row: Array = rows[i]
		var y := 47 + i * 7
		var allowed := TacticalShop.allowed(game, st, me, row)
		var price := TacticalShop.price_for(st, me, row)
		var have := TacticalShop.owned_fully(st, me, row)
		var cash := int(st.money[me.slot]) >= price
		var ink := HUD.INK if allowed and cash and not have else GREY
		if i == cursor:
			c.fill_rect(7, y - 1, 158, 7, Canvas.rgb(82, 49, 31))
		HUD.text(c, SHOP_NAMES[i], 10, y, "mini", HUD.AMBER)
		HUD.text(c, String(row[1]), 19, y, "mini", ink)
		HUD.text(c, String(row[6]), 132, y, "mini", HUD.DIM, false, false, true)
		var tail := "GOT" if have else "%d" % price
		HUD.text(c, tail, 162, y, "mini", ink, false, false, true)
	var foot := "BUY TIME %d" % left if left > 0 else "BUY TIME'S OVER"
	if note_until > game.clock:
		foot = note
	HUD.text(c, foot, 86, 145, "mini", HUD.AMBER, true)


## A key while the game is a 5v5 one: true when it was the shop's.
static func key(game, code: int) -> bool:
	var st = Modes.feature(game)
	if st == null or not Modes.TACTICAL.has(String(st.mode)):
		return false
	var me: Player = game.local_player
	if code == KEY_B:
		if open:
			open = false
		elif me.slot == human and TacticalMode.can_buy(game, st, me):
			open = true
			page = 0
			cursor = 0
		else:
			_say(game, "BUY TIME'S OVER" if me.health > 0 else "YOU'RE OUT")
			open = false
			Modes.say(game, "NO SHOPPING NOW.", 1.2)
		return true
	if not open:
		return _slot_key(game, me, code)
	if code == KEY_ESCAPE:
		open = false
		return true
	if not TacticalMode.can_buy(game, st, me) or me.slot != human:
		open = false
		return code != KEY_ESCAPE
	var rows := TacticalShop.page_rows(game, st, me, page)
	if code == KEY_LEFT or code == KEY_RIGHT:
		page = 1 - page
		cursor = 0
		return true
	if code == KEY_UP or code == KEY_DOWN:
		cursor = posmod(cursor + (1 if code == KEY_DOWN else -1), rows.size())
		return true
	var pick := -1
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		pick = cursor
	else:
		pick = SHOP_KEYS.find(code)
	if pick < 0 or pick >= rows.size():
		return false
	cursor = pick
	var said := TacticalShop.buy(game, st, me, String(rows[pick][0]))
	if said == "":
		game.sound.play("weapon_pickup", .7)
		_say(game, "BOUGHT " + String(rows[pick][1]))
	else:
		game.sound.play("menu_back", .5)
		_say(game, said)
	return true


## The 5v5 modes' gun keys, as the round shooters have them: 1 the long gun,
## 2 the sidearm (again: the other sidearm), 3 the crowbar, 4 dynamite.
static func _slot_key(game, me: Player, code: int) -> bool:
	if code < KEY_1 or code > KEY_4 or me.slot != human or me.health <= 0:
		return false
	var a: Weapons.Armory = me.armory
	var want := -1
	match code:
		KEY_1:
			for gun: int in TacticalShop.LONG_GUNS:
				if a.owned[gun]:
					want = gun
					break
		KEY_2:
			# The sidearms held, the next one after the one in hand.
			var held: Array = []
			for gun: int in TacticalShop.SIDEARMS:
				if a.owned[gun]:
					held.append(gun)
			if not held.is_empty():
				var at := held.find(a.active)
				want = int(held[(at + 1) % held.size()]) if at >= 0 else int(held[0])
		KEY_3:
			want = Weapons.CROWBAR
		KEY_4:
			# The throwables held, the next one after the one in hand.
			var held: Array = []
			for gun: int in TacticalShop.THROWABLES:
				var pool := Weapons.CROSSBOW if gun == Weapons.DYNAMITE else gun
				if a.owned[gun] and a.reserve[pool] > 0:
					held.append(gun)
			if not held.is_empty():
				var at := held.find(a.active)
				want = int(held[(at + 1) % held.size()]) if at >= 0 else int(held[0])
	if want >= 0 and a.owned[want]:
		a.select(want, game)
	return true


static func _say(game, text: String) -> void:
	note = text
	note_until = game.clock + 1.6


# ------------------------------------------------------------ picker


## The title's 5V5 SHOWDOWN picker: mode, map, match length, START.
static func draw_picker(c: Canvas, menu: Menu, row: int, mode: int, map: int, long: int) -> void:
	menu.draw_sheet(c, "SHOWDOWN")
	var mode_id := String(Modes.TACTICAL[posmod(mode, Modes.TACTICAL.size())])
	var map_id := String(Modes.SHOWDOWN_MAPS[posmod(map, Modes.SHOWDOWN_MAPS.size())])
	var rounds := int(MATCH_LENGTHS[posmod(long, MATCH_LENGTHS.size())])
	var title := "SEARCH & DESTROY" if mode_id == Modes.BOMB else "HOSTAGE RESCUE"
	var rows := [
		["MODE", title],
		["MAP", String(MAP_TITLES.get(map_id, map_id.to_upper()))],
		["MATCH", "FIRST TO %d ROUNDS" % rounds],
		["", "LET 'ER RIP"],
	]
	for i in rows.size():
		var y := 50 + i * 17
		var here := i == posmod(row, PICKER_ROWS)
		if here:
			c.fill_rect(19, y - 2, 282, 14, Canvas.rgb(82, 49, 31))
			Menu.shell(c, 22, y + 2)
		var ink := HUD.AMBER if here else HUD.INK
		if String(rows[i][0]) != "":
			HUD.text(c, String(rows[i][0]), 36, y, "body", Menu.FADED)
			var value := String(rows[i][1])
			HUD.text(c, ("<  %s  >" % value) if here else value, 196, y, "body", ink, true)
		else:
			HUD.text(c, String(rows[i][1]), 160, y, "heading", ink, true)
	var lines: Array = MAP_LINES.get(map_id, ["", ""])
	HUD.text(c, String(MODE_LINES.get(mode_id, "")), 160, 124, "mini", HUD.AMBER, true)
	HUD.text(c, String(lines[0]), 160, 134, "mini", HUD.INK, true)
	HUD.text(c, String(lines[1]), 160, 142, "mini", HUD.INK, true)
	HUD.text(
		c, "YOU AND FOUR BOTS AGAINST FIVE. B BUYS IN THE FREEZE.", 160, 154, "mini", HUD.DIM, true
	)
	HUD.text(c, "ARROWS PICK   ENTER PLAYS   ESC BACK", 124, 181, "mini", HUD.INK, true)


# ------------------------------------------------------------ down


## This machine's player is out and nobody on their team is left to watch:
## the scoreboard.
static func draw_down(c: Canvas, game) -> void:
	var st = Modes.feature(game)
	if st == null:
		return
	draw_board(c, game, st, "YOU'RE OUT", "THE ROUND GOES ON WITHOUT YOU")


## Both teams' players, their frags and deaths, under a heading.
static func draw_board(c: Canvas, game, st, heading: String, line: String) -> void:
	HUD.panel(c, 40, 22, 240, 126, PLATE)
	HUD.text(c, heading, 160, 26, "heading", HUD.INK, true)
	HUD.text(c, line, 160, 42, "mini", HUD.AMBER, true)
	for team in 2:
		var x := 48 + team * 116
		var any: Player = null
		for p: Player in game.players:
			if p.team == team:
				any = p
				break
		var ink := HUD.INK if any == null else ink_for(st, any)
		var side := "" if any == null else " " + TacticalMode.side_name(st, any)
		HUD.text(
			c,
			"%s %d%s" % [TacticalMode.TEAM_NAMES[team], int(st.wins[team]), side],
			x,
			52,
			"mini",
			ink
		)
		var y := 61
		for p: Player in game.players:
			if p.team != team:
				continue
			var name := Modes.tag(p) + (" YOU" if p.slot == human else "")
			HUD.text(c, name, x, y, "mini", HUD.INK if p.health > 0 else GREY)
			HUD.text(c, "%d/%d" % [p.frags, p.deaths], x + 60, y, "mini", HUD.DIM)
			if p.team == game.local_player.team:
				var cash := "%d" % int(st.money[p.slot])
				HUD.text(c, cash, x + 104, y, "mini", GREEN, false, false, true)
			y += 8
