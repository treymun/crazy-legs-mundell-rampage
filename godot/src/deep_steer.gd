## Deep water between a hand and the player it sees. A hand that cannot swim
## used to walk straight at a player across a channel and stand at the bank
## pushing into the water (can_walk will not let it in); now, while the
## straight line crosses deep water, it walks the flow field round instead
## (enemies.gd tick), which already keeps to dry ground. The line is sampled
## every half cell, each tick (nothing kept: a copy of the game rebuilt from a
## snapshot must step exactly as the host does).
class_name DeepSteer
extends RefCounted

const STEP := .5


static func across(game, e, p) -> bool:
	var w = game.world
	if w.deep_tile < 0 or e.swims or p == null:
		return false
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var length := sqrt(dx * dx + dy * dy)
	for k in range(1, int(length / STEP) + 1):
		var t := k * STEP / maxf(length, .001)
		if w.deep_at(e.x + dx * t, e.y + dy * t) and not w.over_deep(e.x + dx * t, e.y + dy * t):
			return true
	return false
