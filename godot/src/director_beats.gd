## The fight-rhythm director's choices (pass 15; features/director.gd keeps
## the beats). Which of a chapter's hands it may hold back (never one anything
## names or stands by), how many of each district's it holds (game.rng, once,
## on the chapter's first tick), the extra hands set beside them, and which
## held ones come in a peak. Plain functions of the game: no state here.
class_name DirectorBeats
extends RefCounted

## A held hand's extra stands this far out from it at most.
const BESIDE := [1.1, 1.6, 2.2]
## No hand within this of a level's exchange (hands talking at a spot).
const EXCHANGE_CLEAR := 4.0
## Farther than this (cells) from every player a hand counts as out of sight.
const SIGHT_FAR := 36.0
## A peak's spot keeps this far (each way, cells) from a door's middle.
const DOOR_CLEAR := 1.6


## The indexes in game.enemies the director must never hold: every hand a
## trigger wakes or waits on, the partner pairs, the station's wave, the
## patrols, hands whose id anything else in the level uses, the bosses and
## the rescue's cast, the tough guy, the critters, the swimmers and lurkers.
static func named(game: Game) -> Dictionary:
	var level := game.level
	var ids := {}
	for trigger: Dictionary in level.triggers:
		var when: Dictionary = trigger.get("when", {})
		for id: Variant in when.get("down", []):
			ids[str(id)] = true
		for action: Dictionary in trigger.get("do", []):
			for id: Variant in action.get("wake", []):
				ids[str(id)] = true
	for pair: Array in level.partners:
		ids[str(pair[0])] = true
		ids[str(pair[1])] = true
	for exchange: LevelData.Exchange in level.exchanges:
		ids[exchange.id] = true
	for door: LevelData.Door in level.doors:
		if door.id != "":
			ids[door.id] = true
	var out := {}
	for i in game.enemy_ids.size():
		if ids.has(str(game.enemy_ids[i])):
			out[i] = true
	for index: int in level.reinforcements:
		out[index] = true
	for key: int in level.patrols:
		out[key] = true
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		if e == game.boss or e == game.jerry or e == game.bessie or e == game.finale:
			out[i] = true
		elif not e.hostile or Enemy.BOSS_TITLES.has(e.kind) or e.swims:
			out[i] = true
		else:
			var def: Dictionary = Enemy.DEFS[e.kind]
			if def.has("tough_title") or def.get("lurks", false) or not e.route.is_empty():
				out[i] = true
	return out


## Whether hand `e` may be held: alive and awake, not named, away from the
## start, the bosses and the exchanges, and out of every player's sight.
static func may_hold(game: Game, e: Enemy, start: Vector2, bosses: Array) -> bool:
	if not e.alive or e.alerted:
		return false
	var at := Vector2(e.x, e.y)
	if at.distance_to(start) < DirectorData.num("start_clear"):
		return false
	var clear := DirectorData.num("boss_clear")
	for b: Vector2 in bosses:
		if at.distance_to(b) < clear:
			return false
	for exchange: LevelData.Exchange in game.level.exchanges:
		if at.distance_to(Vector2(exchange.x, exchange.y)) < EXCHANGE_CLEAR:
			return false
	return not seen(game, e)


## Whether any player up can see hand `e`.
static func seen(game: Game, e: Enemy) -> bool:
	for q: Player in game.players:
		if q.health <= 0:
			continue
		var dx := e.x - q.x
		var dy := e.y - q.y
		# Past SIGHT_FAR a hand is a speck at 320 wide: not tested (a sight
		# line across the map is the costliest thing asked here).
		if dx * dx + dy * dy < SIGHT_FAR * SIGHT_FAR and game.world.visible(q.x, q.y, e.x, e.y):
			return true
	return false


## Where the bosses and the chapter's last boss stand (and the boss's
## district: no hand in it is held).
static func boss_spots(game: Game) -> Array:
	var out: Array = []
	for e: Enemy in game.enemies:
		if e.hostile and (Enemy.BOSS_TITLES.has(e.kind) or e == game.finale):
			out.append(Vector2(e.x, e.y))
	return out


static func district_at(game: Game, x: float, y: float) -> int:
	var level := game.level
	var cx := clampi(int(x), 0, level.width - 1)
	var cy := clampi(int(y), 0, level.height - 1)
	if level.area.is_empty():
		return 0
	return level.area[cy * level.width + cx]


## The hands to hold, as indexes into game.enemies: in each district
## `hold_share` of the hands it may hold (at least one where it has three or
## more), picked with game.rng from those. Districts in index order, each
## district's hands in their order before the dice (the same on every machine).
static func pick_holds(game: Game, named_set: Dictionary) -> Array:
	var start := Vector2(float(game.level.spawn[0]), float(game.level.spawn[1]))
	var bosses := boss_spots(game)
	var boss_districts := {}
	for b: Vector2 in bosses:
		boss_districts[district_at(game, b.x, b.y)] = true
	var by_district := {}
	var counts := {}
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		if not e.hostile or BossKit.is_boss(e):
			continue
		var d := district_at(game, e.x, e.y)
		var had: int = counts.get(d, 0)
		counts[d] = had + 1
		if named_set.has(i) or boss_districts.has(d) or not may_hold(game, e, start, bosses):
			continue
		if not by_district.has(d):
			by_district[d] = []
		var list: Array = by_district[d]
		list.append(i)
	var share := DirectorData.at("hold_share", game.difficulty)
	var keys: Array = by_district.keys()
	keys.sort()
	var out: Array = []
	for d: int in keys:
		var list: Array = by_district[d]
		var count: int = counts[d]
		var want := roundi(share * count)
		if want == 0 and count >= 3:
			want = 1
		want = mini(want, list.size())
		# A partial shuffle: the first `want` picked by game.rng.
		for k in want:
			var j := k + int(game.rng.random() * (list.size() - k))
			var was: int = list[k]
			list[k] = list[j]
			list[j] = was
			out.append(list[k])
	out.sort()
	return out


## Extra hands beside held ones: `extra_share` of the district's hands,
## beside its held ones in turn, of their kind, held as well. Each joins
## game.enemies after everything else (the posse feature saves them with the
## rest that joined). Their indexes.
static func add_extras(game: Game, held: Array) -> Array:
	var share := DirectorData.at("extra_share", game.difficulty)
	if share <= 0.0 or held.is_empty():
		return []
	var by_district := {}
	var counts := {}
	for i in game.enemy_ids.size():
		var e: Enemy = game.enemies[i]
		if e.hostile and not BossKit.is_boss(e):
			var d := district_at(game, e.x, e.y)
			var had: int = counts.get(d, 0)
			counts[d] = had + 1
	for index: int in held:
		var e: Enemy = game.enemies[index]
		var d := district_at(game, e.x, e.y)
		if not by_district.has(d):
			by_district[d] = []
		var list: Array = by_district[d]
		list.append(index)
	var keys: Array = by_district.keys()
	keys.sort()
	var out: Array = []
	for d: int in keys:
		var anchors: Array = by_district[d]
		var count: int = counts.get(d, 0)
		var want := roundi(share * count)
		for k in want:
			var anchor: Enemy = game.enemies[anchors[k % anchors.size()]]
			var found: Variant = _beside(game, anchor, k)
			if found == null:
				continue
			var spot: Vector2 = found
			var add := Enemy.new(anchor.kind, spot.x, spot.y, anchor.angle + .6 * (k + 1))
			add.flank = -anchor.flank
			add.floor_z = anchor.floor_z
			add.dormant = true
			out.append(game.enemies.size())
			game.enemies.append(add)
			game.total_kills += 1
	return out


## An open spot near `anchor` a body fits in, round from a turn `k` sets.
static func _beside(game: Game, anchor: Enemy, k: int) -> Variant:
	for reach: float in BESIDE:
		for n in 8:
			var a := (n + k * 3) * TAU / 8.0 + .4
			var x := anchor.x + cos(a) * reach
			var y := anchor.y + sin(a) * reach
			if game.world.blocked(x, y, anchor.radius + .05) or by_door(game.world, Vector2(x, y)):
				continue
			if absf(game.world.elevation(x, y) - game.world.elevation(anchor.x, anchor.y)) > .2:
				continue
			if not game.world.visible(anchor.x, anchor.y, x, y):
				continue
			return Vector2(x, y)
	return null


## The held hands that come in a peak now: those within `peak_reach` cells
## of `p` (the party's player it comes for), nearest first (ties by index),
## the chapter's first peak `peak_first` at most and each after one more, up
## to `peak_group_most` (the crowds grow through a chapter).
static func peak_group(game: Game, held: Array, p: Player, done := 0) -> Array:
	var reach := DirectorData.at("peak_reach", game.difficulty)
	var first := roundi(DirectorData.at("peak_first", game.difficulty))
	var most := mini(first + done, roundi(DirectorData.at("peak_group_most", game.difficulty)))
	var near: Array = []
	for index: int in held:
		var e: Enemy = game.enemies[index]
		if e.hp <= 0.0:
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d <= reach:
			near.append([d, index])
	near.sort()
	var out: Array = []
	for pair: Array in near:
		if out.size() >= most:
			break
		out.append(pair[1])
	return out


## Up to `want` open spots `peak_spot` cells out from `p`, out of every
## player's sight, on their floor, that the hands' paths reach (within
## `peak_steps` steps), apart from each other: the way a peak's hands come
## in from. Rings out from where `p` looks, either side by turns.
static func spots(game: Game, p: Player, want: int) -> Array:
	var w: LevelData = game.world
	var ring: Array = DirectorData.value("peak_spot", [8.0, 15.0])
	var near: float = ring[0]
	var far: float = ring[1]
	var steps_most := roundi(DirectorData.num("peak_steps"))
	var facing: float = p.view_angle()
	var out: Array = []
	var r := near
	while r <= far and out.size() < want:
		for k in 24:
			if out.size() >= want:
				break
			var turn: int = int((k + 1) / 2.0) * (1 if k % 2 else -1)
			var a := facing + turn * TAU / 24.0
			var at := Vector2(p.x + cos(a) * r, p.y + sin(a) * r)
			if _spot_ok(game, w, p, at, out, steps_most):
				out.append(at)
		r += 1.5
	game.focus(game.local_player)
	return out


static func _spot_ok(
	game: Game, w: LevelData, p: Player, at: Vector2, taken: Array, steps_most: int
) -> bool:
	if at.x < 1.0 or at.y < 1.0 or at.x >= w.width - 1 or at.y >= w.height - 1:
		return false
	if w.blocked(at.x, at.y, .4) or w.deep_at(at.x, at.y):
		return false
	if absf(w.elevation(at.x, at.y) - p.floor_z) > .5:
		return false
	for s: Vector2 in taken:
		if s.distance_to(at) < 1.3:
			return false
	if by_door(w, at):
		return false
	for q: Player in game.players:
		if q.health > 0 and w.visible(q.x, q.y, at.x, at.y, q.eye, w.elevation(at.x, at.y) + .9):
			return false
	if game.players.size() > 1:
		game.focus(p)
	var steps: int = game.flow.distance(at.x, at.y)
	return steps < FlowField.FAR and steps >= 5 and steps <= steps_most


## Whether `at` is in or by a doorway: no hand of the director's is put there
## (one left standing in a door's cell when its hunt runs out keeps the door
## shut on the player).
static func by_door(w: LevelData, at: Vector2) -> bool:
	for door: LevelData.Door in w.doors:
		if absf(door.x + .5 - at.x) < DOOR_CLEAR and absf(door.y + .5 - at.y) < DOOR_CLEAR:
			return true
	return false


## The held hands within `reach` steps of the party (a trigger's alert).
static func within(game: Game, held: Array, reach: int) -> Array:
	var out: Array = []
	for index: int in held:
		var e: Enemy = game.enemies[index]
		if e.hp > 0.0 and steps_to(game, e) <= reach:
			out.append(index)
	game.focus(game.local_player)
	return out


## The steps by the way from the nearest player up to hand `e` (FlowField.FAR:
## none reaches it), each player's own flow field. With more than one player
## the acting player is moved: the caller puts the local one back.
static func steps_to(game: Game, e: Enemy) -> int:
	if game.players.size() == 1:
		return game.flow.distance(e.x, e.y)
	var best := FlowField.FAR
	for q: Player in game.players:
		if q.health > 0:
			game.focus(q)
			best = mini(best, game.flow.distance(e.x, e.y))
	return best
