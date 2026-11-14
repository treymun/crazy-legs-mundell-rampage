## COUNTY RUN's spawner (CLAUDE.md "County Run"): enemies keep coming
## whatever the player does (kills and level ups never change it), more and
## tougher the longer the run, with a short lull now and then and an elite
## every so often. Each comes in at a reachable spot out of the player's
## sight, `near` to `far` cells off and within `steps_most` flow-field steps,
## so the horde walks to them and they have time to react; the number alive
## is capped. A hand left far off or stuck where nobody sees it comes back
## in at a fresh spot; old bodies go (the newest stay). Numbers: county.json
## "spawn"; the mix: the map's "pool" ([kind, from minute, weight]) and
## "elites". Dice: the game's rng.
class_name CountySpawner
extends RefCounted

## How many open spots are tried for one spawn.
const TRIES := 28
## Spots worked out at the start, kept here per level (the cells don't move),
## and every cell the player's start walks to (cell -> true).
static var _spots := {}
static var _reach := {}


static func begin(game, f) -> void:
	var s := CountyData.section("spawn")
	f.next_spawn = 1.5
	f.next_elite = float(s.get("elite_from", 80.0))
	f.next_lull = float(s.get("lull_every", 95.0))
	f.lull_until = -1.0
	f.spawned = 0
	f.elites = 0
	spots(game)


## The open, dry ground a body fits on that walks to the player's start
## (each cell's middle), worked out once for a level.
static func spots(game) -> Array:
	var w: LevelData = game.world
	# (By level only: a window shot out or a fence knocked down changes little.)
	var key := String(game.level.id)
	if _spots.has(key):
		return _spots[key]
	var start := Vector2i(int(game.level.spawn[0]), int(game.level.spawn[1]))
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + n
			if reached.has(next) or next.x < 1 or next.y < 1:
				continue
			if next.x >= w.width - 1 or next.y >= w.height - 1:
				continue
			if w.blocked(next.x + .5, next.y + .5, .2) or w.deep_at(next.x + .5, next.y + .5):
				continue
			reached[next] = true
			queue.append(next)
	_reach[key] = reached
	var out: Array = []
	for at: Vector2i in queue:
		var x := at.x + .5
		var y := at.y + .5
		if w.blocked(x, y, .42):
			continue
		if w.surface_sound(int(w.floor_tile[w.cell(x, y)])) == "water":
			continue
		if w.deep_at(x, y) or _by_deep(w, x, y):
			continue
		out.append(Vector2(x, y))
	_spots[key] = out
	return out


## A whole number 0..n-1 off the game's dice.
static func roll(game, n: int) -> int:
	return clampi(int(game.rng.random() * n), 0, maxi(0, n - 1))


## Whether cell (x, y) walks to the player's start (worked out with spots()).
static func reached(game, x: float, y: float) -> bool:
	spots(game)
	var key := String(game.level.id)
	return (_reach.get(key, {}) as Dictionary).has(Vector2i(int(x), int(y)))


static func minutes(f) -> float:
	return f.run_time / 60.0


## How many county hands may be up at once now.
static func cap(f) -> int:
	var s := CountyData.section("spawn")
	var most := roundi(
		float(s.get("cap_start", 12)) + float(s.get("cap_per_minute", 2.4)) * minutes(f)
	)
	return roundi(mini(int(s.get("cap_most", 38)), most) * _pressure(f))


## The map's own pressure (county.json maps "pressure"): the cap and the rate
## times this (the bayou's shallows slow the player, so it eases off a little).
static func _pressure(f) -> float:
	return float(CountyData.map(f.map_id).get("pressure", 1.0))


static func alive(game) -> int:
	var n := 0
	for e: Enemy in game.enemies:
		if e.hostile and e.hp > 0.0:
			n += 1
	return n


static func tick(game, f, _dt: float) -> void:
	var s := CountyData.section("spawn")
	var t: float = f.run_time
	if t >= f.next_lull:
		f.lull_until = t + float(s.get("lull_for", 11.0))
		f.next_lull = t + float(s.get("lull_every", 95.0))
		Modes.say(game, "A LULL. RELOAD AND GRAB THAT XP.", 2.4)
	_keep_hunting(game, f)
	_prune(game, f)
	if t < f.lull_until:
		return
	var most := roundi(cap(f) * CountyCoop.cap_scale(game))
	if t >= f.next_elite and alive(game) < most + 2:
		f.next_elite = t + float(s.get("elite_every", 52.0))
		_elite(game, f)
	if t < f.next_spawn:
		return
	var every := maxf(
		float(s.get("every_least", .42)),
		float(s.get("every_start", 2.3)) + float(s.get("every_per_minute", -.16)) * minutes(f)
	)
	f.next_spawn = t + every / maxf(.2, _pressure(f)) / CountyCoop.cap_scale(game)
	var room := most - alive(game)
	if room <= 0:
		return
	var group := mini(room, 1 + roll(game, maxi(1, int(s.get("group_most", 3)))))
	var at = spot(game, f)
	if at == null:
		return
	for k in group:
		var kind := pick_kind(game, f)
		var place: Vector2 = at if k == 0 else _beside(game, at, k)
		spawn(game, f, kind, place.x, place.y, false)


## A kind from the map's pool, weighted, among those due by now.
static func pick_kind(game, f) -> String:
	var pool: Array = CountyData.map(f.map_id).get("pool", [["billy", 0, 1]])
	var due: Array = []
	var total := 0.0
	var m := minutes(f)
	for row in pool:
		if (
			row is Array
			and row.size() >= 3
			and float(row[1]) <= m
			and Enemy.DEFS.has(String(row[0]))
		):
			# The heavier ones come on stronger as the minutes pass.
			var weight := float(row[2]) * (1.0 + maxf(0.0, m - float(row[1])) * .06)
			due.append([String(row[0]), weight])
			total += weight
	if due.is_empty():
		return "billy"
	var roll: float = game.rng.random() * total
	for row: Array in due:
		roll -= float(row[1])
		if roll <= 0.0:
			return String(row[0])
	return String(due[0][0])


static func _elite(game, f) -> void:
	var kinds: Array = CountyData.map(f.map_id).get("elites", ["big_billy"])
	var ok: Array = []
	for k in kinds:
		if Enemy.DEFS.has(String(k)):
			ok.append(String(k))
	if ok.is_empty():
		return
	var at = spot(game, f)
	if at == null:
		return
	var kind := String(ok[f.elites % ok.size()])
	var e := spawn(game, f, kind, at.x, at.y, true)
	f.elites += 1
	Modes.say(
		game,
		(
			"ELITE COMIN': %s"
			% String(Enemy.DEFS[kind].get("tough_title", kind.to_upper().replace("_", " ")))
		),
		2.6
	)
	game.sound.play("whistle", .8)
	e.cooldown = 1.0


## A county hand comes in at (x, y), hunting the player. An elite has its
## health raised and drops more XP (county_orbs.gd reads `elite`).
static func spawn(game, f, kind: String, x: float, y: float, elite: bool) -> Enemy:
	var p: Player = game.player
	var e := Enemy.new(kind, x, y, atan2(p.y - y, p.x - x))
	var s := CountyData.section("spawn")
	var m := minutes(f)
	var tough := (
		1.0
		+ (
			maxf(0.0, m - float(s.get("health_from_minute", 5.0)))
			* float(s.get("health_per_minute", .045))
		)
	)
	tough = minf(float(s.get("health_most", 2.2)), tough)
	if elite:
		tough *= 1.6
	tough *= CountyCoop.tough_scale(game)
	e.hp *= tough
	e.max_hp = e.hp
	if elite:
		e.county_elite = true
	e.floor_z = game.world.elevation(x, y)
	game.enemies.append(e)
	game.total_kills += 1
	f.spawned += 1
	e.wake(game, p.x, p.y)
	e.hunt_until = game.clock + 9999.0
	e.county_watch = [x, y, f.run_time, f.run_time]
	return e


## Where the next one comes in: a spot `near`..`far` off, out of sight, that
## the flow field walks to the player within `steps_most`; failing that, one
## out of sight anywhere in the band; null when there is none.
static func spot(game, _f) -> Variant:
	var s := CountyData.section("spawn")
	var list := spots(game)
	if list.is_empty():
		return null
	var p: Player = game.player
	var near := float(s.get("near", 11.0))
	var far := float(s.get("far", 26.0))
	var most := int(s.get("steps_most", 40))
	var fallback = null
	var w: LevelData = game.world
	for k in TRIES:
		# A cell in the ring round the player, then the tests.
		var a: float = game.rng.random() * TAU
		var r: float = near + game.rng.random() * (far - near)
		var at := Vector2(floorf(p.x + cos(a) * r) + .5, floorf(p.y + sin(a) * r) + .5)
		if not reached(game, at.x, at.y) or w.blocked(at.x, at.y, .42) or w.deep_at(at.x, at.y):
			continue
		var d := at.distance_to(Vector2(p.x, p.y))
		if d < near or d > far:
			continue
		var floor_z: float = game.world.elevation(at.x, at.y)
		if game.world.visible(p.x, p.y, at.x, at.y, p.eye, floor_z + .9):
			continue
		if _by_deep(w, at.x, at.y):
			continue
		var steps: int = game.flow.distance(at.x, at.y) if game.flow != null else FlowField.FAR
		if steps <= most:
			return at
		if fallback == null and steps < FlowField.FAR:
			fallback = at
	return fallback


## A cell beside deep water (the hands' steering presses into it there).
static func _by_deep(w: LevelData, x: float, y: float) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if w.deep_at(x + dx, y + dy):
				return true
	return false


static func _beside(game, at: Vector2, k: int) -> Vector2:
	for reach: float in [.9, 1.4]:
		var a := k * 2.1 + .4
		var x := at.x + cos(a) * reach
		var y := at.y + sin(a) * reach
		if (
			not game.world.blocked(x, y, .32)
			and not _by_deep(game.world, x, y)
			and reached(game, x, y)
		):
			return Vector2(x, y)
	return at


## Every county hand stays on the hunt; one far off or stuck out of sight for
## a while comes back in nearer.
static func _keep_hunting(game, f) -> void:
	var p: Player = game.player
	var party := CountyCoop.party(game)
	var after := float(CountyData.number("spawn", "recycle_after", 9.0))
	var far := float(CountyData.number("spawn", "far", 26.0)) + 8.0
	for e: Enemy in game.enemies:
		if not e.hostile or e.hp <= 0.0:
			continue
		# A party: each hand after the player it hunts (Players.hunted).
		if party:
			p = Players.hunted(game, e)
		if not e.alerted:
			e.wake(game, p.x, p.y)
		e.hunt_until = maxf(e.hunt_until, game.clock + 9.0)
		# Further off, it heads for the next cell along the flow field
		# rather than straight at the player: one that sees the player across
		# deep water or a fence would walk into it and stand there.
		e.target = [p.x, p.y]
		var flow: FlowField = p.flow if party else game.flow
		if flow != null and Vector2(e.x - p.x, e.y - p.y).length() > 5.0:
			var way: Vector2 = flow.waypoint(e.x, e.y, 1, [], e.floor_z)
			if way != Vector2(e.x, e.y):
				e.target = [way.x, way.y]
		var w: Array = e.county_watch
		if w.is_empty():
			w = [e.x, e.y, f.run_time, f.run_time]
		if Vector2(e.x, e.y).distance_to(Vector2(float(w[0]), float(w[1]))) > .8:
			w[0] = e.x
			w[1] = e.y
			w[2] = f.run_time
		if e.player_seen:
			w[3] = f.run_time
		e.county_watch = w
		var gone := Vector2(e.x, e.y).distance_to(Vector2(p.x, p.y)) > far
		var stuck: bool = f.run_time - float(w[2]) > after
		var unseen: bool = f.run_time - float(w[3]) > after * .5 and not e.player_seen
		# One that sees the player but has stood stuck far longer, out of its
		# reach and out of the view (a bank of deep water between them) goes too.
		var wedged: bool = (
			f.run_time - float(w[2]) > after * 1.5
			and Vector2(e.x - p.x, e.y - p.y).length() > float(Enemy.REACH.get(e.kind, 2.0)) + 2.0
			and (not _ahead(p, e.x, e.y) or f.run_time - float(w[2]) > after * 2.5)
		)
		if (gone or stuck) and (unseen or wedged):
			var at = spot(game, f)
			if at != null:
				e.x = at.x
				e.y = at.y
				e.floor_z = game.world.elevation(at.x, at.y)
				e.windup = 0.0
				e.retreat = null
				e.cover = null
				e.county_watch = [e.x, e.y, f.run_time, f.run_time]


## Whether (x, y) is within 60 degrees of where `p` faces (play's own test of
## "in front of the player", never the renderer's, which only looks).
static func _ahead(p: Player, x: float, y: float) -> bool:
	var to := Vector2(x - p.x, y - p.y)
	if to.length() < .01:
		return true
	return to.normalized().dot(Vector2(cos(p.angle), sin(p.angle))) > .5


## Bodies past `corpses_kept` go, oldest first (a long run would otherwise
## carry thousands of them through every loop over the enemies).
static func _prune(game, _f) -> void:
	var kept := int(CountyData.number("spawn", "corpses_kept", 36))
	var dead: Array = []
	for e: Enemy in game.enemies:
		if e.hp <= 0.0:
			dead.append(e)
	if dead.size() <= kept:
		return
	dead.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.died_at < b.died_at)
	var drop := {}
	for i in dead.size() - kept:
		drop[dead[i]] = true
	var left: Array = []
	for e: Enemy in game.enemies:
		if not drop.has(e):
			left.append(e)
	game.enemies = left
