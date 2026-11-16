## The 5v5 bots' sense of the ground (tactical_bot.gd): where to fall back
## to out of a foe's sight, which boarded cover to shoot open for a shorter
## way, and keeping out of fire. Plain answers from the level as it stands;
## nothing here is part of a game's state.
class_name BotTactics
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")
const WallBreaks := preload("res://src/features/wall_breaks.gd")

## How far out it looks for cover (cells), and the fan of ways it tries,
## away from the foe and to either side.
const COVER_RINGS := [1.6, 2.8]
const COVER_WAYS := 7
const COVER_FAN := 2.4
## A board is worth shooting open when the way through it is this many steps
## shorter, and it stands within BOARD_NEAR cells in sight.
const BOARD_SAVES := 6
const BOARD_NEAR := 7.0
## Keeps this far (cells) outside a fire's edge.
const FIRE_MARGIN := .7


## The nearest open spot a short straight walk from `p` that foe `q` cannot
## see (INF when there is none in reach). Tries the ways away from the foe
## first; at most COVER_RINGS x COVER_WAYS spots, two sight lines each.
static func cover_spot(game: Game, p: Player, q: Player) -> Vector2:
	var w: LevelData = game.world
	var away := atan2(p.y - q.y, p.x - q.x)
	for r: float in COVER_RINGS:
		for i in COVER_WAYS:
			# 0, +1, -1, +2, -2 ... steps out from straight away.
			var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)
			var a := away + k * COVER_FAN / float(COVER_WAYS - 1)
			var s := Vector2(p.x + cos(a) * r, p.y + sin(a) * r)
			if w.blocked(s.x, s.y, .3) or w.deep_at(s.x, s.y):
				continue
			var floor_z := w.elevation(s.x, s.y)
			if absf(floor_z - w.elevation(p.x, p.y)) > .45:
				continue
			if not w.visible(p.x, p.y, s.x, s.y, p.eye, floor_z + .6):
				continue  # not a straight walk
			if w.visible(q.x, q.y, s.x, s.y, q.eye, floor_z + .9):
				continue  # still seen from there
			return s
	return Vector2.INF


## A whole boarded cover cell (wall_breaks' cover_boards that may open) in
## sight within BOARD_NEAR of `p` that, shot open, would make the way to
## `to` BOARD_SAVES steps shorter; (-1, -1) when there is none.
static func board_for(game: Game, p: Player, to: Vector2) -> Vector2i:
	var walls: WallBreaks = game.features.get("wall_breaks")
	if walls == null or walls.fences.is_empty():
		return Vector2i(-1, -1)
	var field := TacticalNav.field(game, to.x, to.y)
	if field == null:
		return Vector2i(-1, -1)
	var now := TacticalNav.steps(field, p.x, p.y)
	var best := Vector2i(-1, -1)
	var best_steps := now - BOARD_SAVES
	for f: WallBreaks.Fence in walls.fences.values():
		if f.stage >= 2 or not f.opens or str(f.spec.get("hit", "")) != "cover_boards_hit":
			continue
		var at := Vector2(f.cell.x + .5, f.cell.y + .5)
		var near := at.distance_to(Vector2(p.x, p.y))
		if near > BOARD_NEAR:
			continue
		# The cells either side of the fence's run.
		var side := Vector2(0, 1) if f.along_x else Vector2(1, 0)
		var a := at + side
		var b := at - side
		var mine := a if a.distance_to(Vector2(p.x, p.y)) < b.distance_to(Vector2(p.x, p.y)) else b
		var far := b if mine == a else a
		var through := int(near) + 1 + TacticalNav.steps(field, far.x, far.y)
		if through >= best_steps or TacticalNav.steps(field, mine.x, mine.y) == FlowField.FAR:
			continue
		if not game.world.visible(
			p.x, p.y, at.x, at.y, p.eye, game.world.elevation(at.x, at.y) + .5
		):
			continue
		best_steps = through
		best = f.cell
	return best


## Steps `c`'s walk out of and around the round's fires (TacticalUtility):
## inside a fire's reach plus FIRE_MARGIN it is pushed straight out.
static func keep_out_of_fire(_game: Game, st: ModeFeature, p: Player, c: Game.Controls) -> void:
	if st.fires.is_empty():
		return
	var push := Vector2.ZERO
	for fire: Array in st.fires:
		var fx: float = fire[0]
		var fy: float = fire[1]
		var out := Vector2(p.x - fx, p.y - fy)
		var reach := TacticalUtility.FIRE_RADIUS + FIRE_MARGIN
		var d := out.length()
		if d < reach:
			push += (out / maxf(d, .05)) * (1.0 - d / reach) * 2.0
	if push == Vector2.ZERO:
		return
	# Into the bot's own forward and strafe (strafe is to the right).
	var facing := Vector2(cos(p.angle), sin(p.angle))
	var right := Vector2(-facing.y, facing.x)
	c.forward = clampf(c.forward + push.dot(facing), -1.0, 1.0)
	c.strafe = clampf(c.strafe + push.dot(right), -1.0, 1.0)
	c.running = true
