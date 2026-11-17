## The junk bench's screen (src/bench_mods.gd, features/bench.gd): Mundell's
## pegboard over the view, a gun a row hung on its pegs, a hand-lettered tag
## for each of its mods with the price in marker, the scrap in the coffee can.
## This machine's player's only; play goes on under it (online and alone
## alike), the player standing still while it is up.
##
## Walk keys (or the arrows, the stick) pick a tag, FIRE or ENTER tapes it on,
## USE or ESC shuts it; a click or tap on a tag picks and buys it. A buy goes
## out with the next controls (Controls.buy: take_pending), so every copy of
## a networked game, and a replay, buys alike. It shuts by itself when its
## player walks off from the bench or goes down (settle).
##
## The pictures are tools/art/build_bench_art.gd's: bench_board (the board,
## its tape and can), bench_tag_<short> (each mod's tag, lettered),
## bench_gun_<gun>(_bare) (the guns on their pegs), bench_stamp (ON, over the
## price of a mod had).
class_name BenchScreen
extends RefCounted

## The board on the view, the rows' and tags' places on it.
const PANEL := Rect2i(6, 3, 308, 144)
const ROW_TOP := 24
const ROW_H := 20
const TAG_X := [62, 184]
const TAG := Vector2i(118, 19)
## The guns down the board, in this order (bench.cfg's mods by their gun).
const GUNS := ["revolver", "shotgun", "rifle", "crossbow", "tnt"]
const MARKER := Color8(46, 30, 22)
const RED := Color8(170, 36, 26)
const CHALK := Color8(246, 226, 120)
const DIM := Color8(54, 40, 30)

static var open := false
static var row := 0
static var column := 0
static var note := ""
static var note_until := 0.0
static var pending_buys: Array = []
static var _set_last := false
## The controls held last frame (forward, strafe, fire, use), for presses.
static var _held := [true, true, true, true]
static var _zones: Array = []


static func reset() -> void:
	open = false
	pending_buys = []
	_set_last = false
	note = ""


## The bench asked for by this machine's player (game.bench_asked): up.
static func show(game: Game) -> void:
	open = true
	_held = [true, true, true, true]
	note = ""
	_place_cursor(game)


## Every frame: the bench asked for, or shut when its player has walked off.
static func settle(game: Game) -> void:
	if game == null:
		open = false
		return
	if game.bench_asked:
		game.bench_asked = false
		show(game)
	if not open:
		return
	var bench: Game.BenchScript = game.features.get("bench")
	var me := game.local_player
	if bench == null or not bench.near_bench(me) or game.showing_tally or game.defeated():
		open = false


## The mods on the board's row r, tag c: its id ("" none).
static func mod_at(r: int, c: int) -> String:
	var gun: String = GUNS[clampi(r, 0, GUNS.size() - 1)]
	var found: Array = []
	for id: String in BenchMods.ids():
		if str(BenchMods.mod(id)["gun"]) == gun:
			found.append(id)
	return str(found[c]) if c < found.size() else ""


static func _place_cursor(game: Game) -> void:
	# The gun in hand's row, if it has one.
	var gun: String = Weapons.NAMES[game.local_player.armory.active]
	var at := GUNS.find(gun)
	if at >= 0:
		row = at
	column = clampi(column, 0, 1)


## This machine's controls while the board is up: the walk keys pick, FIRE
## buys, USE shuts; then the player stands still.
static func steer(game: Game, c: Game.Controls) -> void:
	var now := [absf(c.forward) > .5, absf(c.strafe) > .5, c.fire, c.hold or c.use]
	if now[0] and not _held[0]:
		_move(0, -1 if c.forward > 0.0 else 1)
	if now[1] and not _held[1]:
		_move(1 if c.strafe > 0.0 else -1, 0)
	if now[2] and not _held[2]:
		_buy(game)
	if now[3] and not _held[3]:
		open = false
	_held = now
	c.forward = 0.0
	c.strafe = 0.0
	c.turn = 0.0
	c.look = 0.0
	c.fire = false
	c.alt_fire = false
	c.jump = false
	c.use = false
	c.hold = false


static func _move(dx: int, dy: int) -> void:
	row = posmod(row + dy, GUNS.size())
	column = posmod(column + dx, 2)


## A key while the board is up: true when it was the board's.
static func key(game: Game, code: int) -> bool:
	if not open:
		return false
	match code:
		KEY_ESCAPE, KEY_TAB:
			open = false
		KEY_UP:
			_move(0, -1)
		KEY_DOWN:
			_move(0, 1)
		KEY_LEFT:
			_move(-1, 0)
		KEY_RIGHT:
			_move(1, 0)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_buy(game)
		_:
			return false
	return true


static func _buy(game: Game) -> void:
	var id := mod_at(row, column)
	if id == "":
		return
	var index := BenchMods.ids().find(id)
	var said := BenchMods.why_not(game.local_player, index)
	if said == "" and not pending_buys.has(index):
		pending_buys.append(index)
		game.sound.play("menu_accept", .6)
		_say(game, "TAPIN' IT ON...")
	else:
		game.sound.play("menu_back", .5)
		_say(game, said)


static func _say(game: Game, text: String) -> void:
	note = text
	note_until = game.clock + 2.2


## The next controls carry a buy asked for since the last tick (one a tick).
static func take_pending(c: Game.Controls) -> void:
	if not pending_buys.is_empty():
		c.buy = pending_buys.pop_front()
		_set_last = true
	elif _set_last:
		c.buy = -1
		_set_last = false


## The pointer over the board picks the tag under it.
static func hover(at: Vector2i) -> void:
	var hit := _zone_at(at)
	if hit.size() == 2:
		row = hit[0]
		column = hit[1]


## A click or tap: a tag buys, off the board shuts it. True when it was the board's.
static func tap(game: Game, at: Vector2i) -> bool:
	if not open:
		return false
	var hit := _zone_at(at)
	if hit.size() == 2:
		row = hit[0]
		column = hit[1]
		_buy(game)
	elif not PANEL.has_point(at):
		open = false
	return true


static func _zone_at(at: Vector2i) -> Array:
	for z: Array in _zones:
		var r: Rect2i = z[0]
		if r.has_point(at):
			return [z[1], z[2]]
	return []


# ------------------------------------------------------------------ drawing


static func draw(c: Canvas, game: Game) -> void:
	if not open:
		return
	_zones = []
	var art := game.art
	var me := game.local_player
	var arm := me.armory
	var px := PANEL.position.x
	var py := PANEL.position.y
	_blit(c, art, "bench_board", px, py)
	# The scrap in the coffee can, in marker on its label.
	_marker(c, str(arm.scrap), px + 286, py + 12, RED, true)
	for r in GUNS.size():
		var gun: String = GUNS[r]
		var slot := Weapons.NAMES.find(gun)
		var y := py + ROW_TOP + r * ROW_H
		var have: bool = arm.owned[slot]
		_gun(c, game, gun, px + 8, y, have)
		for k in 2:
			var id := mod_at(r, k)
			if id == "":
				continue
			var m: Dictionary = BenchMods.mod(id)
			var tag_x: int = TAG_X[k]
			var x := px + tag_x
			var picked := r == row and k == column
			var lift := -1 if picked else 0
			var taped := arm.mods.has(id)
			var price: int = m["price"]
			var dim := not taped and (not have or arm.scrap < price)
			_tag(c, art, str(m["short"]), x, y + lift, dim)
			if taped:
				_blit(c, art, "bench_stamp", x + TAG.x - 19, y + lift - 1)
			else:
				_marker(c, str(price), x + TAG.x - 10, y + lift + 2, RED if not dim else DIM, true)
			if picked:
				_chalk_box(c, Rect2i(x - 2, y + lift - 2, TAG.x + 4, TAG.y + 4))
			_zones.append([Rect2i(x, y, TAG.x, TAG.y), r, k])
	# The tape strip along the bottom: what the tag picked does, or why not.
	var id_now := mod_at(row, column)
	var foot := ""
	var ink := MARKER
	if note_until > game.clock and note != "":
		foot = note
		ink = RED
	elif id_now != "":
		var m_now: Dictionary = BenchMods.mod(id_now)
		var why := BenchMods.why_not(me, BenchMods.ids().find(id_now))
		foot = str(m_now["label"]) + ": " + str(m_now["line"])
		if why != "" and not arm.mods.has(id_now):
			foot = why
			ink = RED
	HUD.text(c, foot, px + PANEL.size.x / 2, py + 132, "body", ink, true, false)
	HUD.text(
		c,
		"FIRE: TAPE IT ON   USE: DONE",
		px + PANEL.size.x / 2,
		py + PANEL.size.y + 2,
		"mini",
		HUD.AMBER,
		true,
		true
	)


static func _blit(c: Canvas, art: Assets, name: String, x: int, y: int) -> void:
	if not art.has_art(name):
		return
	var a := art.art(name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	c.blit_rgba(data, w, h, x, y, "bench|" + name)


static func _tag(c: Canvas, art: Assets, short: String, x: int, y: int, dim: bool) -> void:
	var name := "bench_tag_%s%s" % [short, "_dim" if dim else ""]
	if art.has_art(name):
		_blit(c, art, name, x, y)
	else:
		c.fill_rect(x, y, TAG.x, TAG.y, Color8(200, 170, 110))
		HUD.text(c, short.to_upper(), x + 30, y + 6, "body", MARKER, false, false)


## The gun hung on its pegs (whitewash outline when not had yet), its name below.
static func _gun(c: Canvas, game: Game, gun: String, x: int, y: int, have: bool) -> void:
	var name := ("bench_gun_%s" if have else "bench_gun_%s_bare") % gun
	_blit(c, game.art, name, x - 1, y - 1)


## Numbers in marker: each figure a pixel up or down, a darker bleed under it.
static func _marker(c: Canvas, text: String, x: int, y: int, ink: Color, center := false) -> void:
	var width := PixelType.text_width(text, "body")
	var at := x - width / 2 if center else x
	for i in text.length():
		var ch := text[i]
		var lift := ((hash(text) >> i) & 1) - ((hash(ch) >> 3) & 1)
		HUD.text(c, ch, at + 1, y + lift + 1, "body", ink.darkened(.45), false, false)
		HUD.text(c, ch, at, y + lift, "body", ink, false, false)
		at += PixelType.text_width(ch, "body") + 1


## A chalk line round the tag picked, a little rough.
static func _chalk_box(c: Canvas, r: Rect2i) -> void:
	c.fill_rect(r.position.x + 1, r.position.y, r.size.x - 2, 1, CHALK)
	c.fill_rect(r.position.x, r.end.y - 1, r.size.x - 3, 1, CHALK)
	c.fill_rect(r.position.x, r.position.y + 1, 1, r.size.y - 2, CHALK)
	c.fill_rect(r.end.x - 1, r.position.y + 2, 1, r.size.y - 3, CHALK)
