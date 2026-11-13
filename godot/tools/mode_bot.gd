## The bot that plays the other players in a game mode (src/modes/): the
## second to fourth player of `--players=<n>` in a real window (main.gd
## _tick_party) and the players of tools/mode_check.gd. It is
## tools/bot_pilot.gd, plus:
##   co-op   a partner down within REVIVE_FROM it goes to and holds USE over
##           (when nothing is after it); left more than FOLLOW behind the
##           first player it walks their flow field back to them;
##   versus  it hunts the nearest player it may hurt: walks their flow field
##           until it sees them, then turns, strafes and shoots.
## Always through its controls (as_controls), never the game's calls.
extends "res://tools/bot_pilot.gd"

const REVIVE_FROM := 14.0
const FOLLOW := 9.0


func steer(game: Game) -> Game.Controls:
	as_controls = true
	if Modes.is_versus(game):
		return _hunt(game)
	var c: Game.Controls = super.steer(game)
	if Modes.mode_of(game) != Modes.COOP:
		return c
	var p := game.player
	var down := _downed(game)
	# A partner down close by comes first, unless a hand is right on top of it.
	var pressed := foe != null and Vector2(foe.x - p.x, foe.y - p.y).length() < 3.0
	if down != null and (foe == null or Vector2(down.x - p.x, down.y - p.y).length() < 5.0):
		if pressed:
			return c
		var gap := Vector2(down.x - p.x, down.y - p.y).length()
		var want := atan2(down.y - p.y, down.x - p.x)
		if gap > 4.0:
			var h := down.flow.heading(p.x, p.y)
			want = h if not is_nan(h) else want
		c.turn = clampf(Enemy.angle_delta(want, p.angle), -.12, .12)
		c.forward = 1.0 if gap > .8 else 0.0
		c.running = gap > 3.0
		c.fire = false
		c.use = false
		c.hold = gap < CoopMode.REVIVE_REACH * .9
		return c
	var lead: Player = game.players[0]
	if foe == null and lead != p and lead.health > 0:
		var gap := Vector2(lead.x - p.x, lead.y - p.y).length()
		if gap > FOLLOW:
			var h := lead.flow.heading(p.x, p.y)
			var want := h if not is_nan(h) else atan2(lead.y - p.y, lead.x - p.x)
			c.turn = clampf(Enemy.angle_delta(want, p.angle), -.12, .12)
			c.forward = 1.0
			c.running = true
	return c


## The nearest partner down within REVIVE_FROM, or null.
func _downed(game: Game) -> Player:
	var p := game.player
	var best: Player = null
	var near := REVIVE_FROM
	for q: Player in game.players:
		if q == p or q.health > 0:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if d < near:
			near = d
			best = q
	return best


## Versus: after the nearest player it may hurt.
func _hunt(game: Game) -> Game.Controls:
	var c := Game.Controls.new()
	var p := game.player
	var rules := Modes.rules(game)
	var best: Player = null
	var seen := false
	var near := INF
	for q: Player in game.players:
		if q == p or q.health <= 0 or rules.hurt_scale(game, p, q, false) <= 0.0:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		var sees: bool = game.world.visible(p.x, p.y, q.x, q.y, p.eye, q.eye)
		# One in sight beats a nearer one behind a wall.
		if (sees and not seen) or (sees == seen and d < near):
			best = q
			near = d
			seen = sees
	foe = null
	if best == null:
		return c
	var want := atan2(best.y - p.y, best.x - p.x)
	if not seen:
		var h := best.flow.heading(p.x, p.y)
		want = h if not is_nan(h) else want
	var turn := Enemy.angle_delta(want, p.angle)
	c.turn = clampf(turn, -.12, .12)
	if seen:
		var target: float = game.world.elevation(best.x, best.y) + best.air + .62
		var slope := (target - p.eye) / maxf(.5, near)
		c.look = clampf(slope * Renderer.base_focal - p.pitch, -3.0, 3.0)
		c.fire = absf(turn) < .07
		c.forward = .6 if near > 5.0 else (-.4 if near < 2.0 else 0.0)
		c.strafe = 1.0 if fmod(game.clock + p.slot * 1.3, 2.4) < 1.2 else -1.0
	else:
		c.look = clampf(-p.pitch, -2.0, 2.0)
		c.forward = 1.0 if absf(turn) < .9 else .2
		c.running = true
	if game.armory.loaded[game.armory.active] == 0 and game.armory.reserve[game.armory.active] == 0:
		c.cycle = 1
	if stuck > .35 and not seen:
		c.jump = fmod(game.clock, .6) < .1
		c.forward = 1.0
	c.turn += turn_away
	turn_away = 0.0
	return c
