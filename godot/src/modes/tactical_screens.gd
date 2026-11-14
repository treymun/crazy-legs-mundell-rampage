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
const PICKER_ROWS := 5
## The picker's LET 'ER RIP row (the last).
const PICKER_GO := 4
## A 5v5 player's figure, as tall as the hit box (Modes.player_in_line: 1.08).
const PLAYER_HEIGHT := 1.14
const MATCH_LENGTHS := [4, 7]
const MAP_TITLES := {
	"grainyard": "PUCKETT GRAIN CO-OP",
	"holler": "HOLLER DISTILLERY",
	"salvage": "MUNDELL'S SALVAGE",
	"pumpngo": "PUMP & GO",
	"pineacres": "PINE ACRES",
	"landing": "CATFISH LANDING",
}
const MAP_LINES := {
	"grainyard":
	["THREE LANES, BOXCARS IN THE RAIL YARD.", "A: THE DUMP PIT   B: THE SEED WAREHOUSE"],
	"holler":
	["A CREEK ACROSS THE MIDDLE, ONE BRIDGE.", "A: THE STILL HOUSE   B: THE BOTTLING YARD"],
	"salvage": ["TIGHT JUNK CANYONS, CORNERS EVERYWHERE.", "A: THE CRUSHER PIT   B: THE TIRE BARN"],
	"pumpngo": ["A HIGHWAY GAS STATION. LONG LOT OR THE STORE.", "A: THE PUMPS"],
	"pineacres": ["A TRAILER PARK. BACK ROW, GREEN OR DOUBLE-WIDE.", "A: THE CARPORT"],
	"landing": ["A BAIT SHOP ON THE RIVER. BANK OR THE SHOP.", "A: THE DOCK"],
}
const MODE_LINES := {
	Modes.BOMB: "OUTLAWS PLANT THE SHINE BOMB. DEPUTIES CUT THE FUSE.",
	Modes.HOSTAGE: "DEPUTIES RUN A HOSTAGE OUT. OUTLAWS HOLD 'EM.",
	"tagteam": "TWO A SIDE, ONE SITE. PLANT IT OR CUT IT. FIRST TO 9.",
}
## The picker's modes: the two 5v5 modes, then TAG TEAM 2V2 (search and
## destroy two a side on its own maps), and each one's match lengths.
const PICKER_MODES := [Modes.BOMB, Modes.HOSTAGE, "tagteam"]
const TAG_LENGTHS := [5, 9]


static func picker_maps(mode: int) -> Array:
	return Modes.TAGTEAM_MAPS if posmod(mode, PICKER_MODES.size()) == 2 else Modes.SHOWDOWN_MAPS


static func picker_rounds(mode: int, long: int) -> int:
	var lengths: Array = TAG_LENGTHS if posmod(mode, PICKER_MODES.size()) == 2 else MATCH_LENGTHS
	return int(lengths[posmod(long, lengths.size())])


## The buy menu (this machine's): open, the row the cursor is on, the last
## word it had (NOT ENOUGH CASH...) and until when.
static var open := false
## The touch overlay is up (main.gd): a BUY plate to tap in the buy time.
static var touch_on := false
## The pointer is let go for the open store (main.gd), to point and click.
static var mouse_free := false
## Where the BUY plate sits.
const BUY_PLATE := Rect2i(4, 22, 52, 14)
static var cursor := 0
## The store's page: 0 the guns, 1 gear and throwables (LEFT and RIGHT).
static var page := 0
static var note := ""
static var note_until := 0.0
## The slot this machine's own player plays (the one the keys and mouse
## drive); the view may be on a teammate's while they are out.
static var human := 0
## What this machine's player asked for between ticks, to go out as their
## next controls (main.gd hands them to the game, or a networked game's host):
## buys in order, a gun, a reload, USE pressed, a cycle.
static var pending_buys: Array = []
static var pending_weapon := -1
static var pending_reload := false
static var pending_use := false
static var pending_cycle := 0
## Watching a teammate while out: SPACE asks for the next one.
static var watch_next := false
## The results screen's last line (empty online: the lobby's line is there).
static var footer := "ENTER  REMATCH   /   ESC  TITLE"
## The cash shown last frame, and the last gain's amount and until when.
static var _cash_seen := -1
static var _gain := 0
static var _gain_until := 0.0


static func reset() -> void:
	pending_buys = []
	pending_weapon = -1
	pending_reload = false
	pending_use = false
	pending_cycle = 0
	_cash_seen = -1
	open = false
	cursor = 0
	page = 0
	note = ""
	note_until = 0.0


static func ink_for(st, p: Player) -> Color:
	return OUTLAW_INK if TacticalMode.side_of(st, p) == 0 else DEPUTY_INK


## How a 5v5 player looks to `me`: the OUTLAWS as the county's hillbillies,
## the DEPUTIES as its yard deputies (the campaign's own actors, every view
## and walk cel), at the height of a player's hit box (the head drawn where a
## shot counts as the head); aiming and firing face on, hurt cels under half
## health, crouched lower, laid out when down.
static func player_sprite(game, q: Player, me: Player):
	var st = Modes.feature(game)
	var kind := "billy" if st == null or TacticalMode.side_of(st, q) == 0 else "yard_deputy"
	var floor_z: float = game.world.elevation(q.x, q.y)
	if q.health <= 0:
		var down = game.pooled(q.x, q.y, kind + "_down", PLAYER_HEIGHT * .3, floor_z - .07)
		down.body = true
		return down
	var bearing := atan2(me.y - q.y, me.x - q.x)
	var relative := Enemy.angle_delta(bearing, q.angle)
	var direction := mini(4, int(absf(relative) / (PI / 4.0) + .5))
	var hurt := "_hurt" if q.health < 50 else ""
	var moving := Vector2(q.vx, q.vy).length() > .5
	var fired: bool = q.armory != null and q.armory.shot_age < .12
	var image := ""
	if direction == 0 and fired:
		image = kind + hurt + "_fire"
	elif direction == 0 and (q.scoped or (q.armory != null and q.armory.shot_age < .7)):
		image = kind + hurt + "_aim"
	else:
		var frame := "w%d" % (int(q.walk_phase / (PI * .5)) % 4) if moving else "0"
		image = "%s%s%s_%s" % [kind, hurt, Enemy.HEADINGS[direction], frame]
	if not game.art.has_art(image):
		image = "%s%s_%s" % [kind, Enemy.HEADINGS[direction], "0"]
	var tall := PLAYER_HEIGHT * (.78 if q.crouched else 1.0)
	var spr = game.pooled(q.x, q.y, image, tall, floor_z + q.air)
	spr.flip = relative < 0.0 and direction < 4
	spr.body = true
	return spr


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
	if st.money.size() < game.players.size() or String(st.phase) == "":
		return  # not begun (an online copy before the host's first snapshot)
	var rules := Modes.rules(game) as TacticalMode
	if not me.scoped:
		# Through a scope the glass is all there is (tags would float on the mask).
		_mate_tags(c, game, st, me)
		_objective_tags(c, game, st, me)
		_spread_marks(c, game, me)
	_top_strip(c, game, st, rules, me)
	_feed(c, game, st)
	_bars(c, game, st, me)
	_cash_gain(c, game, st, me)
	if me.slot != human:
		HUD.text(c, "WATCHING " + Modes.tag(me), 160, 22, "body", HUD.AMBER, true)
		HUD.text(c, "SPACE  NEXT", 160, 32, "mini", HUD.DIM, true)
		_killed_line(c, st, 112)
	if Input.is_key_pressed(KEY_TAB) and not open:
		draw_board(
			c,
			game,
			st,
			"SCOREBOARD",
			"ROUND %d OF %d" % [int(st.round_no), TacticalMode.max_rounds(st)]
		)
	if String(st.phase) == "post":
		_round_banner(c, game, st)
	elif String(st.phase) == "freeze":
		var left := maxi(1, int(ceil(float(st.phase_until) - game.clock)))
		HUD.text(c, str(left), 160, 50, "heading", HUD.AMBER, true)
		if not open:
			HUD.text(c, "TAP BUY" if touch_on else "B  BUY MENU", 160, 66, "body", HUD.INK, true)
	# (The open store is drawn over everything, gun and HUD too: main_state.gd.)
	if not open and touch_on and me.slot == human and TacticalMode.can_buy(game, st, me):
		LobbyScreens.button(c, BUY_PLATE, "BUY", true, "buy")


## A tap while a 5v5 round is on (main_input.gd _touch_actions): the BUY
## plate, the store's items and X, or outside an open store (closes it).
## True when the tap was the store's.
static func tap(game, at: Vector2i) -> bool:
	var hit := LobbyScreens.zone_at(at)
	var id := String(hit[0]) if not hit.is_empty() else ""
	match id:
		"buy":
			return key(game, KEY_B)
		"item":
			page = int(hit[1]) / 100
			cursor = int(hit[1]) % 100
			return key(game, KEY_ENTER)
		"close":
			open = false
			return true
		"shop":
			return true
	if open:
		open = false
		return true
	return false


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
	HUD.text(
		c, "ROUND %d/%d" % [int(st.round_no), TacticalMode.max_rounds(st)], 4, 11, "mini", HUD.DIM
	)


## What the 5v5 status bar shows of this machine's player (hud.gd draws it
## where the campaign's keys, gut and pockets go): [vest, hard hat, snips,
## carrying the bomb, throwables, side name, its ink, the side's goal]; []
## before the match has begun.
static func bar_state(game) -> Array:
	var st = Modes.feature(game)
	var me: Player = game.local_player
	if st == null or st.money.size() <= me.slot or String(st.phase) == "":
		return []
	var bomb = st.bomb if String(st.mode) == Modes.BOMB else {}
	var carrying: bool = (
		bomb is Dictionary
		and String(bomb.get("state", "")) == "carried"
		and int(bomb.get("slot", -1)) == me.slot
	)
	var rules := Modes.rules(game) as TacticalMode
	return [
		roundi(float(st.armor[me.slot])),
		bool(st.helmet[me.slot]),
		bool(st.snips[me.slot]),
		carrying,
		TacticalShop.thrown_count(me),
		TacticalMode.side_name(st, me),
		ink_for(st, me),
		rules.goal_line(game, st),
	]


## The match's end: the teams' round wins big, who took it, each team's
## players by kills (the match's MVP marked), and a strip of every round in
## the team's colour that took it, lettered by how (Blown, Defused, Wiped
## out, Time, Rescue). `footer` is what ENTER and ESC do (online: the lobby's
## own line goes there instead).
static func results(c: Canvas, game, st) -> void:
	var art: Dictionary = game.art.art("title_backdrop")
	c.blit_rgba(art["data"], art["w"], art["h"], 0, 0, "art|title_backdrop")
	HUD.panel(c, 8, 6, 304, 186)
	var mode_name := "SEARCH & DESTROY" if String(st.mode) == Modes.BOMB else "HOSTAGE RESCUE"
	if Modes.is_tag_team(game):
		mode_name = "TAG TEAM 2V2"
	var place: String = String(MAP_TITLES.get(game.level.id, game.level.id.to_upper()))
	HUD.text(c, "%s  -  %s" % [place, mode_name], 160, 12, "mini", HUD.DIM, true)
	var w: Array = st.wins
	var a := int(w[0])
	var b := int(w[1])
	var team_ink := [Color8(232, 160, 96), Color8(126, 196, 120)]
	HUD.text(c, TacticalMode.TEAM_NAMES[0], 74, 22, "heading", team_ink[0], true)
	HUD.text(c, TacticalMode.TEAM_NAMES[1], 246, 22, "heading", team_ink[1], true)
	HUD.text(c, "%d - %d" % [a, b], 160, 22, "heading", HUD.AMBER, true)
	var said := (
		"A DRAW. NOBODY TAKES THE COUNTY."
		if a == b
		else "THE %s TAKE THE COUNTY." % TacticalMode.TEAM_NAMES[0 if a > b else 1]
	)
	HUD.text(c, said, 160, 42, "body", HUD.INK, true)
	# The MVP: the most kills, the fewest deaths on a tie.
	var mvp: Player = null
	for p: Player in game.players:
		if mvp == null or p.frags > mvp.frags or (p.frags == mvp.frags and p.deaths < mvp.deaths):
			mvp = p
	for t in 2:
		var x0 := 20 + t * 148
		HUD.text(c, "PLAYER", x0, 55, "mini", HUD.DIM)
		HUD.text(c, "K", x0 + 112, 55, "mini", HUD.DIM, false, true, true)
		HUD.text(c, "D", x0 + 128, 55, "mini", HUD.DIM, false, true, true)
		var mine: Array = game.players.filter(func(p: Player) -> bool: return p.team == t)
		mine.sort_custom(
			func(p: Player, q: Player) -> bool:
				return p.frags > q.frags or (p.frags == q.frags and p.deaths < q.deaths)
		)
		# Two a side (TAG TEAM) gets the bigger lettering, spaced out.
		var few := mine.size() <= 2
		var step := 16 if few else 9
		var style := "body" if few else "mini"
		for i in mini(mine.size(), 5):
			var p: Player = mine[i]
			var y := 63 + i * step
			c.fill_rect(x0 - 4, y - 2, 136, step - 1, PLATE)
			var name := Modes.tag(p)
			if p == game.local_player or p.slot == human:
				name += " (YOU)"
			HUD.text(c, name, x0, y, style, team_ink[t])
			if p == mvp and p.frags > 0:
				HUD.text(c, "MVP", x0 + 92, y, style, HUD.AMBER, false, true, true)
			HUD.text(c, str(p.frags), x0 + 112, y, style, HUD.INK, false, true, true)
			HUD.text(c, str(p.deaths), x0 + 128, y, style, HUD.DIM, false, true, true)
	# Every round as it went.
	var rounds: Array = st.history
	HUD.text(c, "ROUND BY ROUND", 160, 113, "mini", HUD.DIM, true)
	var size := 10 if rounds.size() <= 26 else 8
	var x := 160 - rounds.size() * size / 2
	for row: Array in rounds:
		var t := int(row[0])
		var how := String(row[1])
		c.fill_rect(x, 121, size - 1, 11, team_ink[t] if t >= 0 and t < 2 else HUD.DIM)
		var letter := how.substr(0, 1) if how != "" else "?"
		HUD.text(c, letter, x + (size - 1) / 2, 124, "mini", PLATE, true, false)
		x += size
	HUD.text(
		c, "B BLOWN  D DEFUSED  W WIPED OUT  T TIME  R RESCUE", 160, 136, "mini", HUD.DIM, true
	)
	if footer != "":
		HUD.text(c, footer, 160, 180, "body", HUD.INK, true)


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
## Four short ticks round the crosshair as far out as the gun's shots can
## stray now: they open up on the move, in the air and as a spray climbs,
## and close in standing still or crouched (TacticalMode.shot_tuning).
static func _spread_marks(c: Canvas, game, me: Player) -> void:
	if me.slot != human or me.health <= 0:
		return
	var gun: int = me.armory.active
	var how: Dictionary = Weapons.FIRING[gun]
	if not String(how.get("fire", "")) in ["hitscan", "pellets"]:
		return
	var spread: Vector2 = Modes.shot_spread(game, me, gun, how, me.armory.rifle_heat)[0]
	var gap := clampi(roundi(tan(spread.x) * Renderer.base_focal), 2, 40)
	var ink: Color = game.crosshair_tint
	var mid := Renderer.VIEW / 2
	c.fill_rect(160 - gap - 3, mid, 3, 1, ink)
	c.fill_rect(161 + gap, mid, 3, 1, ink)
	c.fill_rect(160, mid - gap - 3, 1, 3, ink)
	c.fill_rect(160, mid + 1 + gap, 1, 3, ink)


## Teammates' names over their heads: the nearest first, each moved up
## clear of the ones already drawn (or left out when there is no room); one
## out of sight and far off is only a mark.
static func _mate_tags(c: Canvas, game, st, me: Player) -> void:
	var mates: Array = []
	for q: Player in game.players:
		if q != me and q.team == me.team and q.health > 0:
			mates.append([Vector2(q.x - me.x, q.y - me.y).length(), q])
	mates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var taken: Array[Rect2i] = []
	var bomb = st.bomb if String(st.mode) == Modes.BOMB else {}
	for entry: Array in mates:
		var q: Player = entry[1]
		var head: float = game.world.elevation(q.x, q.y) + q.air + 1.14
		var at: Vector3 = game.to_canvas(q.x, q.y, head)
		if at.z <= 0.0 or at.x < 6.0 or at.x > Renderer.WIDTH - 6.0 or at.y < 10.0:
			continue
		if at.y > Renderer.VIEW - 6.0:
			continue
		var ink := ink_for(st, q)
		var seen: bool = (
			float(entry[0]) < 12.0 or game.world.visible(me.x, me.y, q.x, q.y, me.eye, head)
		)
		if not seen:
			c.fill_rect(int(at.x) - 1, int(at.y) - 6, 3, 3, ink)
			continue
		var label := Modes.tag(q)
		if bomb is Dictionary and String(bomb.get("state", "")) == "carried":
			if int(bomb["slot"]) == q.slot:
				label += " BOMB"
		var w := PixelType.text_width(label, "mini")
		var y := int(at.y) - 10
		var rect := Rect2i(int(at.x) - w / 2 - 1, y - 1, w + 2, 7)
		var tries := 0
		while tries < 4 and taken.any(func(r: Rect2i) -> bool: return r.intersects(rect)):
			rect.position.y -= 7
			tries += 1
		if tries >= 4 or rect.position.y < 8:
			continue
		taken.append(rect)
		HUD.text(c, label, int(at.x), rect.position.y + 1, "mini", ink, true)


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
		if TacticalMode.attacks(game, st, me):
			for box: Array in HostageMode.rescue_boxes(game):
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


## The buy menu: one big store, the guns on the left and the gear and
## throwables on the right, every item's price and whether it can be had.
## Point and click (the pointer is let go while it is open, main.gd) or tap
## an item to buy it; the keys still work: LEFT and RIGHT pick a side, UP and
## DOWN an item, ENTER or its number buys, B or ESC shuts it.
static func draw_shop(c: Canvas, game, st) -> void:
	var me: Player = game.local_player
	var panel := Rect2i(8, 16, 304, 140)
	HUD.panel(c, panel.position.x, panel.position.y, panel.size.x, panel.size.y, PLATE)
	LobbyScreens.zone(panel, "shop")
	var left := int(ceil(TacticalMode.buy_left(game, st)))
	HUD.text(c, "GENERAL STORE", 14, 20, "body", HUD.AMBER)
	var time := "BUY TIME %d" % left if left > 0 else "BUY TIME'S OVER"
	HUD.text(c, time, 160, 20, "body", HUD.INK, true)
	HUD.text(c, "CASH %d" % int(st.money[me.slot]), 290, 20, "body", GREEN, false, true, true)
	LobbyScreens.button(c, Rect2i(294, 18, 15, 11), "X", false, "close")
	for side in 2:
		var x0 := 12 + side * 150
		var focused := side == page
		HUD.text(
			c,
			["GUNS", "GEAR + THROWN"][side],
			x0 + 3,
			33,
			"body",
			HUD.AMBER if focused else LobbyScreens.SOFT
		)
		c.fill_rect(x0, 41, 146, 1, Canvas.rgb(110, 80, 52))
		var rows := TacticalShop.page_rows(game, st, me, side)
		for i in rows.size():
			var row: Array = rows[i]
			var y := 45 + i * 10
			var allowed := TacticalShop.allowed(game, st, me, row)
			var price := TacticalShop.price_for(st, me, row)
			var have := TacticalShop.owned_fully(st, me, row)
			var cash := int(st.money[me.slot]) >= price
			var ink := HUD.INK if allowed and cash and not have else GREY
			var spot := Rect2i(x0, y - 2, 146, 10)
			if focused and i == cursor:
				c.fill_rect(
					spot.position.x, spot.position.y, spot.size.x, spot.size.y, LobbyScreens.LIT
				)
			if focused and i < SHOP_NAMES.size():
				HUD.text(c, SHOP_NAMES[i], x0 + 2, y + 1, "mini", HUD.AMBER)
			HUD.text(c, String(row[1]), x0 + 10, y, "body", ink)
			var tail := "GOT" if have else "%d" % price
			HUD.text(c, tail, x0 + 144, y, "body", GREEN if have else ink, false, false, true)
			LobbyScreens.zone(spot, "item", side * 100 + i)
	var foot := "CLICK OR TAP TO BUY.  B CLOSES."
	var ink_foot := LobbyScreens.SOFT
	if note_until > game.clock:
		foot = note
		ink_foot = HUD.AMBER
	HUD.text(c, foot, 160, 146, "body", ink_foot, true)


## The store's item under the pointer becomes the picked one.
static func hover(at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if not hit.is_empty() and String(hit[0]) == "item":
		page = int(hit[1]) / 100
		cursor = int(hit[1]) % 100


## The store shuts when the buy time is over or this machine's player is out
## (main.gd, every frame).
static func settle(game) -> void:
	if not open:
		return
	var st = Modes.feature(game)
	var me: Player = game.local_player
	if st == null or me.slot != human or not TacticalMode.can_buy(game, st, me):
		open = false


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
		return _play_key(game, me, code)
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
	var said := TacticalShop.why_not(game, st, me, String(rows[pick][0]))
	if said == "":
		pending_buys.append(TacticalShop.index_of(String(rows[pick][0])))
		game.sound.play("weapon_pickup", .7)
		_say(game, "BOUGHT " + String(rows[pick][1]))
	else:
		game.sound.play("menu_back", .5)
		_say(game, said)
	return true


## The 5v5 modes' gun keys, as the round shooters have them: 1 the long gun,
## 2 the sidearm (again: the other sidearm), 3 the crowbar, 4 dynamite.
static func _slot_key(_game, me: Player, code: int) -> bool:
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
		pending_weapon = want
	return true


static func _say(game, text: String) -> void:
	note = text
	note_until = game.clock + 1.6


# ------------------------------------------------------------ picker


## The title's 5V5 SHOWDOWN picker: mode, map, match length, START.
## PLAY VS BOTS: mode, map, match length, rules and LET 'ER RIP. A value row
## steps with LEFT and RIGHT or a tap on its arrows (a tap on the picked row:
## the next value); the taps are noted in LobbyScreens.zones.
static func draw_picker(
	c: Canvas, menu: Menu, row: int, mode: int, map: int, long: int, rules := 0
) -> void:
	menu.draw_sheet(c, "PLAY VS BOTS")
	var mode_id := String(PICKER_MODES[posmod(mode, PICKER_MODES.size())])
	var maps := picker_maps(mode)
	var map_id := String(maps[posmod(map, maps.size())])
	var rounds := picker_rounds(mode, long)
	var title := (
		"SEARCH & DESTROY"
		if mode_id == Modes.BOMB
		else ("HOSTAGE RESCUE" if mode_id == Modes.HOSTAGE else "TAG TEAM 2V2")
	)
	var rows := [
		["MODE", title],
		["MAP", String(MAP_TITLES.get(map_id, map_id.to_upper()))],
		["MATCH", "FIRST TO %d ROUNDS" % rounds],
		["RULES", String(TacticalShop.RULE_NAMES[posmod(rules, TacticalShop.RULE_NAMES.size())])],
	]
	var picked := posmod(row, PICKER_ROWS)
	for i in rows.size():
		var y := 42 + i * 16
		var here := i == picked
		var ink := HUD.AMBER if here else HUD.INK
		if here:
			c.fill_rect(19, y - 3, 282, 14, LobbyScreens.LIT)
			Menu.shell(c, 22, y + 1)
		HUD.text(c, String(rows[i][0]), 36, y, "body", Menu.FADED)
		HUD.text(c, String(rows[i][1]), 196, y, "body", ink, true)
		HUD.text(c, "<", 112, y, "body", ink if here else Menu.DIM)
		HUD.text(c, ">", 278, y, "body", ink if here else Menu.DIM)
		LobbyScreens.zone(Rect2i(19, y - 3, 282, 14), "row", i)
		LobbyScreens.zone(Rect2i(100, y - 3, 32, 14), "left", i)
		LobbyScreens.zone(Rect2i(264, y - 3, 37, 14), "right", i)
	var go := picked == PICKER_GO
	LobbyScreens.button(c, Rect2i(70, 107, 180, 20), "", go, "go", PICKER_GO)
	HUD.text(c, "LET 'ER RIP", 160, 110, "heading", HUD.AMBER if go else HUD.INK, true)
	var lines: Array = MAP_LINES.get(map_id, ["", ""])
	_fit(c, String(MODE_LINES.get(mode_id, "")), 133, HUD.AMBER)
	_fit(c, String(lines[0]), 143, HUD.INK)
	_fit(c, String(lines[1]), 152, HUD.INK)
	var blurb := (
		"YOU AND A BOT AGAINST TWO." if mode_id == "tagteam" else "YOU AND FOUR BOTS AGAINST FIVE."
	)
	_fit(c, blurb, 163, LobbyScreens.SOFT)
	LobbyScreens.footer(c, "ARROWS PICK   ENTER PLAYS   ESC BACK")
	LobbyScreens.back_button(c)


## A line in the readable font where it fits the sheet, else the small one.
static func _fit(c: Canvas, text: String, y: int, ink: Color) -> void:
	var style := "body" if PixelType.text_width(text, "body") <= 280 else "mini"
	HUD.text(c, text, 160, y, style, ink, true)


# ------------------------------------------------------------ down


## This machine's player is out and nobody on their team is left to watch:
## the scoreboard.
static func draw_down(c: Canvas, game) -> void:
	var st = Modes.feature(game)
	if st == null:
		return
	draw_board(c, game, st, "YOU'RE OUT", "THE ROUND GOES ON WITHOUT YOU")
	_killed_line(c, st, 142)


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


# ------------------------------------------------------------ play keys


## A key in play (the store shut): the gun keys, reload, USE, the scoreboard
## (TAB, held) and the map (M); pocket items are not for a round.
static func _play_key(game, me: Player, code: int) -> bool:
	if code == KEY_TAB:
		return true  # held for the scoreboard (draw_view asks)
	if code == KEY_M:
		game.map = not game.map
		return true
	if me.slot != human:
		if code == KEY_SPACE or code == KEY_E:
			watch_next = true
			return true
		return false
	if me.health <= 0:
		return false
	if code == KEY_R:
		pending_reload = true
		return true
	if code == KEY_E or code == KEY_SPACE:
		pending_use = true
		return true
	if code in [KEY_F, KEY_Q, KEY_C, KEY_V, KEY_X, KEY_ENTER, KEY_KP_ENTER, KEY_H]:
		return true
	if code == KEY_SEMICOLON or code == KEY_APOSTROPHE:
		pending_cycle = -1 if code == KEY_SEMICOLON else 1
		return true
	if (
		(code >= KEY_5 and code <= KEY_9)
		or (
			code
			in [
				KEY_0,
				KEY_MINUS,
				KEY_EQUAL,
				KEY_BACKSLASH,
				KEY_QUOTELEFT,
				KEY_BRACKETLEFT,
				KEY_BRACKETRIGHT
			]
		)
	):
		return true  # the campaign's gun keys: a round has its own four
	return _slot_key(game, me, code)


## The next controls of this machine's player get what was asked for since
## the last tick: one buy at a time, the gun, the reload, USE, the cycle.
static func take_pending(c: Game.Controls) -> void:
	c.buy = int(pending_buys.pop_front()) if not pending_buys.is_empty() else -1
	c.weapon = pending_weapon
	c.reload = pending_reload
	# Once each: a frame of several ticks hands them to the first only.
	c.use = pending_use
	c.cycle = pending_cycle
	pending_weapon = -1
	pending_reload = false
	pending_use = false
	pending_cycle = 0


## "+300" floating under the cash for a moment when it goes up.
static func _cash_gain(c: Canvas, game, st, me: Player) -> void:
	var cash := int(st.money[me.slot]) if me.slot < st.money.size() else 0
	if _cash_seen >= 0 and cash > _cash_seen:
		_gain = cash - _cash_seen
		_gain_until = game.clock + 1.6
	_cash_seen = cash
	if game.clock < _gain_until:
		var rise := int((1.6 - (_gain_until - game.clock)) * 6.0)
		HUD.text(c, "+%d" % _gain, 8, 26 - rise, "body", GREEN)


## Who downed this machine's player, with what.
static func _killed_line(c: Canvas, st, y: int) -> void:
	var row = st.killed_by.get(human)
	if not row is Array:
		return
	var line := "DOWNED BY %s  %s" % [String(row[0]), String(row[1])]
	if bool(row[2]):
		line += "  HEADSHOT"
	HUD.text(c, line, 160, y, "mini", OUTLAW_INK, true)
