## The team radio of the 5v5 rounds: short lines from this machine's
## teammates (bots and people alike) at the left of the view, worked out from
## what every copy of the game already holds, so it costs the server nothing
## and nothing new is carried. Looks only: it reads the game, never changes
## it (TacticalScreens.draw_view calls it each frame).
##
##   spotting   a teammate has a foe in front of them: "HOG 3: TWO ON B"
##   the bomb   planting, planted, dropped, being cut ("CUTTIN' THE FUSE")
##   hostages   a teammate carrying one out
##   hurt       a teammate's health falling under HURT
## Each speaker waits RADIO_GAP between lines and the team TEAM_GAP.
class_name TacticalRadio
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")

static var RADIO_GAP: float = ModeData.get_value("tactical_bot", "radio_gap", 6.0)
static var TEAM_GAP: float = ModeData.get_value("tactical_bot", "team_radio_gap", 2.5)
## Seconds a line stays up, the most shown, how often the team looks about
## for foes, how far and how wide a teammate sees (as the bots do), and the
## health a teammate calls out under.
const SHOW := 4.0
const MOST := 3
const LOOK_EVERY := .15
const SIGHT := 30.0
const VIEW_HALF := 1.0
const HURT := 40
const NUMBERS := ["", "ONE", "TWO", "THREE", "FOUR", "FIVE"]

## The game listened to (a new one starts the radio over), its lines [text,
## until], when each speaker and the team last spoke, when the next look
## about is, when each foe was last called, and what was seen last frame.
static var _game_id := -1
static var _lines: Array = []
static var _spoke := {}
static var _team_spoke := -99.0
static var _next_look := 0.0
static var _turn := 0
static var _called := {}
static var _was := {}


## Listens to this frame's game for this machine's team: new lines go up.
static func listen(game: Game, st: ModeFeature) -> void:
	if game.get_instance_id() != _game_id or game.clock < _team_spoke - 1.0:
		_game_id = game.get_instance_id()
		_lines = []
		_spoke = {}
		_team_spoke = -99.0
		_next_look = 0.0
		_called = {}
		_was = {}
	var me: Player = game.local_player
	if String(st.phase) != "live":
		_was = {}
		return
	if String(st.mode) == Modes.BOMB:
		_bomb_lines(game, st, me)
	else:
		_hostage_lines(game, st, me)
	for q: Player in game.players:
		if q.team != me.team or q == me:
			continue
		var was: int = _was.get("hp%d" % q.slot, q.health)
		if q.health > 0 and q.health < HURT and was >= HURT:
			_say(game, q, "I'M HIT BAD")
		_was["hp%d" % q.slot] = q.health
	if game.clock >= _next_look:
		_next_look = game.clock + LOOK_EVERY
		_spot(game, st, me)


static func _bomb_lines(game: Game, st: ModeFeature, me: Player) -> void:
	var bomb: Dictionary = st.bomb
	var state := str(bomb.get("state", ""))
	var was := str(_was.get("bomb", state))
	_was["bomb"] = state
	var attacking := TacticalMode.attacks(game, st, me)
	if attacking:
		var holder: int = bomb.get("slot", -1)
		var plant: float = bomb.get("plant", 0.0)
		if state == "carried" and plant > 0.0 and holder != me.slot:
			if not _was.get("planting", false):
				_say(game, _player(game, holder), "PLANTIN' IT, COVER ME")
			_was["planting"] = true
		else:
			_was["planting"] = false
		if state != was and state == "dropped":
			var bx: float = bomb.get("x", 0.0)
			var by: float = bomb.get("y", 0.0)
			_say(game, _nearest_mate(game, me, Vector2(bx, by)), "BOMB'S DOWN, GRAB IT")
		elif state != was and state == "planted":
			var by_slot: int = bomb.get("by", -1)
			_say(game, _player(game, by_slot), "IT'S IN ON %s. HOLD IT" % str(bomb.get("site", "")))
		return
	var cutter: int = bomb.get("defuser", -1)
	if state == "planted" and cutter >= 0 and cutter != me.slot:
		var told: int = _was.get("cutter", -1)
		if told != cutter:
			_say(game, _player(game, cutter), "CUTTIN' THE FUSE, COVER ME")
	_was["cutter"] = cutter if state == "planted" else -1


static func _hostage_lines(game: Game, st: ModeFeature, me: Player) -> void:
	for i in st.hostages.size():
		var h: Array = st.hostages[i]
		var carrier: int = h[3] if str(h[2]) == "carried" else -1
		var key := "hostage%d" % i
		var had: int = _was.get(key, carrier)
		_was[key] = carrier
		if carrier >= 0 and carrier != had and carrier != me.slot:
			var q := _player(game, carrier)
			if q != null and q.team == me.team:
				_say(game, q, "GOT ONE, BRINGIN' HIM OUT")


## A teammate sees foes it has not called lately: "TWO ON B", "ONE ON A".
## One teammate a look, in turn (a sight line is dear: a few a frame at most).
static func _spot(game: Game, _st: ModeFeature, me: Player) -> void:
	var count_players := game.players.size()
	for _step in count_players:
		_turn = (_turn + 1) % count_players
		var q: Player = game.players[_turn]
		if q.team != me.team or q == me or q.health <= 0:
			continue
		var seen: Array = []
		for foe: Player in game.players:
			if foe.team == me.team or foe.health <= 0:
				continue
			var called_at: float = _called.get(foe.slot, -99.0)
			if game.clock - called_at < RADIO_GAP:
				continue
			if _sees(game, q, foe):
				seen.append(foe)
		if seen.is_empty():
			return
		var first: Player = seen[0]
		var where := _place_name(game, first)
		var count: String = NUMBERS[mini(seen.size(), NUMBERS.size() - 1)]
		if _say(game, q, "%s %s" % [count, where] if where != "" else "%s SPOTTED" % count):
			for foe: Player in seen:
				_called[foe.slot] = game.clock
		return


static func _sees(game: Game, q: Player, foe: Player) -> bool:
	var dx := foe.x - q.x
	var dy := foe.y - q.y
	if dx * dx + dy * dy > SIGHT * SIGHT:
		return false
	if absf(Enemy.angle_delta(atan2(dy, dx), q.angle)) > VIEW_HALF:
		return false
	if TacticalUtility.smoked(game, q.x, q.y, foe.x, foe.y):
		return false
	return game.world.visible(q.x, q.y, foe.x, foe.y, q.eye, foe.eye - .1)


## "ON A" near a site, "MID" else (the map's mid hold), "" when neither.
static func _place_name(game: Game, foe: Player) -> String:
	var sites: Variant = game.world.tactical.get("sites", {})
	if sites is Dictionary:
		var by_name: Dictionary = sites
		for name: String in by_name:
			var box: Array = by_name[name]
			if box.size() >= 4:
				var centre := TacticalMode.box_centre(box)
				if centre.distance_to(Vector2(foe.x, foe.y)) < 8.0:
					return "ON " + name
	return ""


## A line from `q` (dropped when they or the team spoke too lately); true
## when it went up.
static func _say(game: Game, q: Player, text: String) -> bool:
	if q == null:
		return false
	if game.clock - _team_spoke < TEAM_GAP:
		return false
	var spoke_at: float = _spoke.get(q.slot, -99.0)
	if game.clock - spoke_at < RADIO_GAP:
		return false
	_spoke[q.slot] = game.clock
	_team_spoke = game.clock
	_lines.append(["%s: %s" % [Modes.tag(q), text], game.clock + SHOW])
	while _lines.size() > MOST:
		_lines.pop_front()
	return true


static func _player(game: Game, slot: int) -> Player:
	if slot < 0 or slot >= game.players.size():
		return null
	return game.players[slot]


static func _nearest_mate(game: Game, me: Player, at: Vector2) -> Player:
	var best: Player = null
	var near := INF
	for q: Player in game.players:
		if q.team != me.team or q == me or q.health <= 0:
			continue
		var d := at.distance_to(Vector2(q.x, q.y))
		if d < near:
			near = d
			best = q
	return best


## The lines up now, at the view's left under the BUY plate.
static func draw(c: Canvas, game: Game, st: ModeFeature) -> void:
	var y := 40
	var ink: Color = TacticalScreens.ink_for(st, game.local_player)
	for row: Array in _lines:
		var until: float = row[1]
		if until < game.clock:
			continue
		HUD.text(c, str(row[0]), 4, y, "mini", ink, false, true)
		y += 7


## The lines up now (tools/bot_check.gd).
static func lines(game: Game) -> Array:
	var out: Array = []
	for row: Array in _lines:
		var until: float = row[1]
		if until >= game.clock:
			out.append(str(row[0]))
	return out
