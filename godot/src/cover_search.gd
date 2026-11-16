## Where a hand ducks (Enemy.take_cover), looked for a few spots a tick.
##
## The spots tried are the rings round the hand (SMART_RINGS on HANDS: SMART,
## NORMAL and up: a hidden spot right behind something solid, else the first
## hidden open one, HandTactics' rule; CLASSIC_RINGS otherwise: the first
## hidden one, headings least toward the player first). Each spot asks two
## sight lines, one of them from the player, and a search could ask sixty:
## up to 11 ms in one tick on the desktop, the worst tick a fight had (engine
## pass 6). Now all the hands together test at most EnemyLod.COVER_BUDGET
## spots a tick (enemies.cfg `cover_budget`; 0: no limit): a search that runs
## out goes on from where it stopped on the hand's next ticks
## (Enemy.cover_hunt, carried, so a copy of the game goes on the same), and
## the hand ducks when it ends, a few hundredths later. A spot that could no
## longer change the answer (open ground once an open spot is found) is
## passed over before its sight lines are asked. Dice: the two of
## take_cover, when the search ends.
class_name CoverSearch
extends RefCounted

## Why it wants cover: a duck (hurt, or after a shot), or a reload
## (HandTactics: the cover holds until the reload is done, and it comes back
## to the same spot).
const DUCK := 1
const RELOAD := 2
const SMART_RINGS := [1.0, 1.7, 2.4, 3.1, 3.8]
const CLASSIC_RINGS := [1.2, 2.0, 2.8, 3.6]
## A search left to go on: the hunt's slots.
const WHY := 0
const NEXT := 1
const FALL_X := 2
const FALL_Y := 3
const FALL_RING := 4
## What _search() answers while the tick's spots have run out.
const PENDING := Vector2.INF


## The whole search at once (Enemy.find_cover, HandTactics.cover, tools).
static func whole(e: Enemy, game: GameWorld, smart: bool) -> Variant:
	return _search(e, game, [DUCK, 0, 0.0, 0.0, -1.0], smart, null)


## A hand wants cover (take_cover, past its own tests): looked for now as far
## as this tick's spots go, the rest on its next ticks (go_on()).
static func want(e: Enemy, game: GameWorld, why: int) -> void:
	if not e.cover_hunt.is_empty():
		var was: int = e.cover_hunt[WHY]
		e.cover_hunt[WHY] = maxi(was, why)
		return
	e.cover_hunt = [why, 0, 0.0, 0.0, -1.0]
	go_on(e, game)


## Its search goes on (Enemy.tick, each tick while one is left); `budgeted`
## false: to its end now (tools).
static func go_on(e: Enemy, game: GameWorld, budgeted := true) -> void:
	if e.cover_hunt.is_empty():
		return
	if not e.alive or e.fetching != null or e.grudge != null:
		e.cover_hunt = []
		return
	var lod: EnemyLod = game.enemy_lod if budgeted and EnemyLod.COVER_BUDGET > 0 else null
	var found: Variant = _search(e, game, e.cover_hunt, HandTactics.smart(game), lod)
	if found is Vector2 and found == PENDING:
		return
	var why: int = e.cover_hunt[WHY]
	e.cover_hunt = []
	if found != null:
		var spot: Vector2 = found
		e.cover = [spot.x, spot.y, game.clock + game.rng.uniform(1.3, 2.4)]
		e.cover_ready = game.clock + game.rng.uniform(5.0, 8.0)
	if why == RELOAD and e.cover != null and e.mind != null:
		# Down behind it until the reload is done, and back there after.
		var c: Array = e.cover
		var sx: float = c[0]
		var sy: float = c[1]
		e.mind.cover_home = Vector2(sx, sy)
		e.cover = [sx, sy, e.mind.reload_until + .4]


## Tries the spots from hunt[NEXT] on; the spot, null (none), or PENDING when
## `lod`'s spots for this tick ran out first (hunt keeps where it got to).
static func _search(e: Enemy, game: GameWorld, hunt: Array, smart: bool, lod: EnemyLod) -> Variant:
	var p: Player = game.player
	var w: LevelData = game.world
	var away := atan2(e.y - p.y, e.x - p.x)
	var rings: Array = SMART_RINGS if smart else CLASSIC_RINGS
	var order := PackedInt32Array() if smart else _order(away)
	if lod != null and lod.cover_clock != game.clock:
		lod.cover_clock = game.clock
		lod.cover_left = EnemyLod.COVER_BUDGET
	var idx: int = hunt[NEXT]
	var total := rings.size() * 12
	while idx < total:
		var ring: float = rings[idx / 12]
		var fall_ring: float = hunt[FALL_RING]
		var fallen := fall_ring >= 0.0
		if fallen and ring > fall_ring + .8:
			# A ring further on than the open spot found: take that one.
			break
		var k := idx % 12
		var a := 0.0
		if smart:
			# Away from the player first, round to the sides.
			a = away + ((k + 1) >> 1) * (1 if k % 2 else -1) * TAU / 12.0
		else:
			a = order[k] * TAU / 12.0
		var cx := e.x + cos(a) * ring
		var cy := e.y + sin(a) * ring
		if w.blocked(cx, cy, e.radius):
			idx += 1
			continue
		var behind := false
		if smart:
			var to := Vector2(p.x - cx, p.y - cy).normalized()
			behind = w.blocked(cx + to.x * (e.radius + .45), cy + to.y * (e.radius + .45), .12)
			if fallen and not behind:
				# Open ground once an open spot is found: it could not be taken.
				idx += 1
				continue
		if lod != null:
			if lod.cover_left <= 0:
				hunt[NEXT] = idx
				return PENDING
			lod.cover_left -= 1
		idx += 1
		if not w.visible(e.x, e.y, cx, cy):
			continue
		var head: float = w.elevation(cx, cy) + minf(.92, e.height * .72)
		if w.visible(p.x, p.y, cx, cy, p.eye, head):
			continue
		if not smart or behind:
			# Something solid between it and the player, right there.
			return Vector2(cx, cy)
		if not fallen:
			hunt[FALL_X] = cx
			hunt[FALL_Y] = cy
			hunt[FALL_RING] = ring
	hunt[NEXT] = idx
	var kept: float = hunt[FALL_RING]
	if kept < 0.0:
		return null
	var fx: float = hunt[FALL_X]
	var fy: float = hunt[FALL_Y]
	return Vector2(fx, fy)


## The twelve headings least toward the player first (the first in heading
## order of those as little toward them): Enemy.find_cover's order.
static func _order(away: float) -> PackedInt32Array:
	var pairs: Array = []
	for k in 12:
		pairs.append([absf(Enemy.angle_delta(k * TAU / 12.0, away)), k])
	pairs.sort_custom(
		func(m: Array, n: Array) -> bool:
			var m0: float = m[0]
			var n0: float = n[0]
			var m1: int = m[1]
			var n1: int = n[1]
			return m0 < n0 or (m0 == n0 and m1 < n1)
	)
	var out := PackedInt32Array()
	for pair: Array in pairs:
		var k: int = pair[1]
		out.append(k)
	return out
