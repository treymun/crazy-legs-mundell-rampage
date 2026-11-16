## The kill feed of co-op, deathmatch, team deathmatch and a COUNTY RUN party
## (the 5v5 rounds keep their own, TacticalScreens): short lines down the
## view's left saying who put down what, who went down, who hauled whom up,
## who fragged whom, who walked in or out. Worked out on every machine from
## what its own game already holds (looks only, never carried, never saved):
## a hand's death with a player's own step or shot acting
## (`game.own_step`: their gun), and each player's health, frags and
## `away` watched from one tick to the next. A client's copy put back on a
## snapshot may skip or repeat a line; nothing in play hangs on it.
extends GameFeature

## Lines kept at once, and how long one stays (seconds of game clock).
const MOST := 5
const SECONDS := 5.0
## Where the lines go: down the view's left, under the drive plate (when
## driving: vehicle_hud.gd, 4,36 to 88,73) and under the objective pin's
## arrow and plate (game.pin_top + PIN_CLEAR at the lowest, its last frame's;
## the boss bar and the run plate are on the right), and above the revive
## line (y 116): BOTTOM the last line's top, fewer lines when the pin is low.
const X := 4
const TOP := 78
const PIN_CLEAR := 32
const BOTTOM := 106
const STEP := 7
## A few hands are better known by another name than their kind's.
const CALLED := {
	"alien": "GREY",
	"barker": "CARNY",
	"lantern": "LANTERN HAND",
	"yard_deputy": "DEPUTY",
	"pit_mechanic": "PIT CREW",
}
## Inks: a player's own line (theirs or about them) warm, the rest by kind.
const DOWN_INK := Color8(238, 104, 72)
const UP_INK := Color8(132, 206, 96)
const KILL_INK := Color8(236, 214, 170)
const BOSS_INK := Color8(250, 196, 92)

## [text, until (game clock), ink]
var rows: Array = []
## Each slot's [health > 0, away] as last seen.
var _seen: Array = []


func id() -> String:
	return "kill_feed"


func attach() -> void:
	tick_with(_tick)
	game.events.enemy_killed.connect(_killed)


## On for more than one player outside the 5v5 rounds.
func shown() -> bool:
	return game.players.size() > 1 and not Modes.is_tactical(game)


func _killed(e: Enemy) -> void:
	if not shown() or not game.own_step or e == null:
		return
	var p: Player = game.player
	var gun := str(Weapons.LABELS[p.armory.active]).split(" [")[0]
	var boss := Enemy.BOSS_TITLES.has(e.kind)
	add("%s  %s  %s" % [Modes.tag(p), gun, enemy_name(e)], BOSS_INK if boss else KILL_INK)


## What the feed calls a hand: a boss or tough guy by name, the rest by kind.
static func enemy_name(e: Enemy) -> String:
	var d: Dictionary = Enemy.DEFS.get(e.kind, {})
	if d.has("title"):
		return str(d["title"])
	if d.has("tough_title"):
		return str(d["tough_title"])
	var kind := Variants.stem(e.kind)
	return str(CALLED.get(kind, kind.replace("_", " ").to_upper()))


func add(text: String, ink: Color) -> void:
	rows.append([text, game.clock + SECONDS, ink])
	while rows.size() > MOST:
		rows.pop_front()


func _tick(_dt: float) -> void:
	if not shown():
		return
	var versus := Modes.is_versus(game)
	for p: Player in game.players:
		while _seen.size() <= p.slot:
			_seen.append([true, false])
		var was: Array = _seen[p.slot]
		var up := p.health > 0
		var was_up: bool = was[0]
		var was_away: bool = was[1]
		if p.away and not was_away:
			add("%s HEADED HOME" % Modes.tag(p), DOWN_INK)
		elif was_away and not p.away:
			add("%s ROLLED IN" % Modes.tag(p), UP_INK)
		elif was_up and not up and not p.away:
			add(_down_line(p, versus), DOWN_INK)
		elif up and not was_up and not versus and not p.away:
			add(_up_line(p), UP_INK)
		_seen[p.slot] = [up, p.away]
	var keep: Array = []
	for row: Array in rows:
		var until: float = row[1]
		if until > game.clock:
			keep.append(row)
	rows = keep


func _down_line(p: Player, versus: bool) -> String:
	var by := p.downed_by
	if versus:
		if by >= 0 and by != p.slot and by < game.players.size():
			var killer: Player = game.players[by]
			var gun := str(Weapons.LABELS[killer.armory.active]).split(" [")[0]
			return "%s  %s  %s" % [Modes.tag(killer), gun, Modes.tag(p)]
		return "%s CASHED OUT" % Modes.tag(p)
	if Modes.mode_of(game) == Modes.COOP and not Players.anyone_alive(game):
		return "%s WENT DOWN. THAT'S THE WHOLE POSSE" % Modes.tag(p)
	return "%s WENT DOWN" % Modes.tag(p)


## Back up: hauled up by the partner nearest (a revive is a partner holding
## USE right beside them), else crawled back in by themselves.
func _up_line(p: Player) -> String:
	for q: Player in game.players:
		if q != p and q.health > 0 and q.holding:
			if Vector2(q.x - p.x, q.y - p.y).length() < CoopMode.REVIVE_REACH + .2:
				return "%s HAULED %s UP" % [Modes.tag(q), Modes.tag(p)]
	return "%s DUSTED OFF AND CAME BACK" % Modes.tag(p)


func draw_view(c: Canvas) -> void:
	if not shown() or rows.is_empty() or game.map:
		return
	var y := top()
	var room := maxi(0, (BOTTOM - y) / STEP + 1)
	for i in range(maxi(0, rows.size() - room), rows.size()):
		var row: Array = rows[i]
		var ink: Color = row[2]
		HUD.text(c, str(row[0]), X, y, "mini", ink, false, true)
		y += STEP


## The first line's top: TOP, or lower when the objective pin hangs lower.
func top() -> int:
	return maxi(TOP, game.pin_top + PIN_CLEAR)
