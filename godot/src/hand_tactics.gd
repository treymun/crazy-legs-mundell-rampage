## The county's hands using the 3D world (setting HANDS: SMART, NORMAL and
## up; CLASSIC and EASY fight as they always did, but for ladders):
##   - a hand after the player takes a ladder where its flow field leads up
##     or down one (src/climbing.gd; every setting, or a roof is a safe spot);
##   - cover is a spot hidden from the player right behind something solid (a
##     wall, a car, a crate, a deck's edge) where there is one, not just out
##     of sight in the open; it ducks there more often after a shot, the
##     harder it is;
##   - a ranged hand that has fired its MAGAZINE reloads (a breath it cannot
##     shoot) and ducks into cover to do it;
##   - in cover, a ranged hand ready to shoot steps out to the side to where
##     it sees the player (peeks), fires, and goes back to the same spot;
##   - a closed door between it and where it last saw the player, within
##     reach, it kicks open (not a locked, secret, powder or remote one, nor
##     a hatch);
##   - up on a roof or a loft over the player, close, with the way down long
##     (or a brawler who sees them), it drops off the edge (Climbing falls it).
## Numbers by difficulty: data/tuning/difficulty.cfg [hands]; the rest in
## modes.cfg [hand_tactics]. Dice: none but the classic duck's one roll.
## Nothing saved: the Mind holds it, carried online like the squad's.
class_name HandTactics
extends RefCounted

static var DUCK: Array = Difficulty.table("hands", "duck_chance")
static var PEEK: Array = Difficulty.table("hands", "peek_wait")
static var KICK: Array = Difficulty.table("hands", "kick_doors")
static var MAGAZINE: Array = Difficulty.table("hands", "magazine")
static var DROP_MAX: Array = Difficulty.table("hands", "drop_max")
static var RELOAD: float = ModeData.get_value("hand_tactics", "reload", 1.8)
static var PEEK_OUT: float = ModeData.get_value("hand_tactics", "peek_out", .8)
static var KICK_WINDUP: float = ModeData.get_value("hand_tactics", "kick_windup", .45)
## The classic chance of ducking after a shot.
const CLASSIC_DUCK := .3


## Whether the hands fight smart in this game (HANDS: SMART, not EASY).
static func smart(game: GameWorld) -> bool:
	return game.smart_hands > 0 and game.difficulty > 0


## The chance a ranged hand ducks into cover after a shot.
static func duck(game: GameWorld) -> float:
	if not smart(game):
		return CLASSIC_DUCK
	var chance: float = DUCK[clampi(game.difficulty, 0, 3)]
	return chance


## Where a hand ducks (Enemy.take_cover), all at once: smart, a hidden spot
## right behind something solid where one is near; else Enemy.find_cover's.
## (Play looks a few spots a tick: src/cover_search.gd.)
static func cover(e: Enemy, game: GameWorld) -> Variant:
	return CoverSearch.whole(e, game, smart(game))


## An alerted hand's turn before it attacks or chases (Enemy.tick): a ladder,
## a kick, a reload, a peek, a drop. True when it took the tick.
static func step(e: Enemy, dt: float, game: Game, can_see: bool, distance: float) -> bool:
	if e.windup > 0.0 or e.stun > 0.0 or not e.hostile:
		return false
	var p: Player = game.player
	var w: LevelData = game.world
	var lost: bool = not can_see or (w.geo != null and w.apart(e, p))
	if lost and Climbing.hand_takes_ladder(e, game):
		return true
	if e.mind == null:
		return false
	var level := clampi(game.difficulty, 0, 3)
	var kick: float = KICK[level]
	var kicks: bool = smart(game) and kick > 0.0
	if not smart(game):
		return false
	var m: Squad.Mind = e.mind
	var now: float = game.clock
	if m.kick_at > 0.0:
		return _kick(game, m)
	if e.attacks != m.seen_attacks:
		_shot_off(e, game, m, level)
	if e.cover != null and Enemy.RANGED.has(e.kind) and _peek(e, dt, game, m, level):
		return true
	if lost and kicks and now >= m.kick_next and e.target != null:
		m.kick_next = now + .25
		var door := _door_ahead(e, game)
		if door != null:
			m.kick_door = Vector2i(door.x, door.y)
			m.kick_at = now + KICK_WINDUP
			e.angle = atan2(door.y + .5 - e.y, door.x + .5 - e.x)
			e.face_left = cos(e.angle) < -.24
			return true
	return _drop(e, dt, game, can_see, distance, level)


## It fired: count the round; a ranged hand that has shot its magazine
## reloads under cover; one that peeked goes back to its spot.
static func _shot_off(e: Enemy, game: Game, m: Squad.Mind, level: int) -> void:
	m.seen_attacks = e.attacks
	if not Enemy.RANGED.has(e.kind):
		return
	m.since_reload += 1
	var magazine: int = MAGAZINE[level]
	if magazine > 0 and m.since_reload >= magazine:
		m.since_reload = 0
		m.reload_until = game.clock + RELOAD
		e.cooldown = maxf(e.cooldown, RELOAD)
		game.sound_at("reload", e.x, e.y, .6)
		e.cover_ready = 0.0
		# (Down behind it till the reload is done: CoverSearch, when it ends.)
		e.take_cover(game, CoverSearch.RELOAD)
		return
	if m.cover_home.distance_to(Vector2(e.x, e.y)) > 3.0:
		m.cover_home = Vector2.INF
	if m.cover_home != Vector2.INF and e.cover == null:
		# Back behind the same thing after a shot from a peek.
		e.cover = [m.cover_home.x, m.cover_home.y, game.clock + 1.2 + PEEK_OUT]


## In cover and ready to shoot: out to the side where it sees the player.
static func _peek(e: Enemy, dt: float, game: Game, m: Squad.Mind, level: int) -> bool:
	var spot: Array = e.cover
	var cx: float = spot[0]
	var cy: float = spot[1]
	var now: float = game.clock
	m.cover_home = Vector2(cx, cy)
	if now < m.reload_until or e.cooldown > .15:
		m.peek_to = Vector2.INF
		return false
	if m.peek_to == Vector2.INF:
		if now < m.peek_next or Vector2(e.x - cx, e.y - cy).length() > .3:
			return false
		var wait: float = PEEK[level]
		m.peek_next = now + maxf(.3, wait)
		var found: Variant = _peek_spot(e, game, m, Vector2(cx, cy))
		if found == null:
			return false
		m.peek_to = found
	if e.player_seen or Vector2(e.x - m.peek_to.x, e.y - m.peek_to.y).length() < .15:
		# Out: shoot from here (the chase and the attack take over).
		m.peek_to = Vector2.INF
		e.cover = null
		return false
	e.follow(dt, game, atan2(m.peek_to.y - e.y, m.peek_to.x - e.x), 1.0)
	return true


## A spot a step to either side of its cover from which it sees the player.
static func _peek_spot(e: Enemy, game: Game, m: Squad.Mind, at: Vector2) -> Variant:
	var p: Player = game.player
	var w: LevelData = game.world
	var to := Vector2(p.x - at.x, p.y - at.y).normalized()
	var side := Vector2(-to.y, to.x)
	for s: float in [m.peek_side, -m.peek_side]:
		for reach: float in [PEEK_OUT, PEEK_OUT * 1.5]:
			var q := at + side * s * reach
			if w.blocked(q.x, q.y, e.radius) or not w.visible(at.x, at.y, q.x, q.y):
				continue
			var head: float = w.elevation(q.x, q.y) + minf(.92, e.height * .72)
			if w.visible(p.x, p.y, q.x, q.y, p.eye, head):
				m.peek_side = s
				return q
	return null


## A closed door within reach between it and where it last saw the player
## (or where its flow field leads), that a kick opens: not locked, secret,
## powder, remote or a hatch.
static func _door_ahead(e: Enemy, game: Game) -> LevelData.Door:
	var w: LevelData = game.world
	var spot: Array = e.target
	var tx: float = spot[0]
	var ty: float = spot[1]
	var at := Vector2(e.x, e.y)
	var toward := atan2(ty - e.y, tx - e.x)
	var lead: float = NAN if game.flow == null else game.flow.heading(e.x, e.y, e.floor_z)
	for door: LevelData.Door in w.near_doors.get(Vector2i(int(e.x), int(e.y)), []):
		if door.opened or door.progress > .05 or door.secret or door.blast_only:
			continue
		if door.bar_side != 0:
			continue  # a barred shortcut (pass 15) is the player's
		if door.key != "" or w.controlled_doors.has(Vector2i(door.x, door.y)):
			continue
		if w.crouch_doors.has(Vector2i(door.x, door.y)):
			continue
		var c := door.center()
		var gap := at.distance_to(c)
		if gap > 1.4 or Vector2(tx, ty).distance_to(at) < gap:
			continue
		var way := (c - at).angle()
		if (
			absf(Enemy.angle_delta(way, toward)) < 1.0
			or (not is_nan(lead) and absf(Enemy.angle_delta(way, lead)) < .8)
		):
			return door
	return null


## The kick lands: the door bangs open (a thump and the door's own sound).
static func _kick(game: Game, m: Squad.Mind) -> bool:
	if game.clock < m.kick_at:
		return true
	m.kick_at = 0.0
	m.kick_next = game.clock + 1.0
	for door: LevelData.Door in game.world.doors:
		if Vector2i(door.x, door.y) == m.kick_door and not door.opened:
			game.sound_at("brawl_punch", door.x + .5, door.y + .5, .9)
			game.toggle_door(door, true)
			game.shake = minf(1.0, game.shake + .08)
	m.kick_door = Vector2i(-1, -1)
	return false


## Up over the player and close, the way down long (or a brawler who sees
## them): off the edge toward them.
static func _drop(
	e: Enemy, dt: float, game: Game, can_see: bool, distance: float, level: int
) -> bool:
	var w: LevelData = game.world
	if w.geo == null or distance > 7.0 or e.ladder >= 0:
		return false
	var p: Player = game.player
	var high: float = e.floor_z - w.stand(p)
	var most: float = DROP_MAX[level]
	if high < 1.0 or high > most:
		return false
	var melee := not Enemy.RANGED.has(e.kind)
	var way: int = game.flow.distance(e.x, e.y, e.floor_z) if game.flow != null else FlowField.FAR
	if not (way > distance * 2.0 + 3.0 or (melee and can_see)):
		return false
	e.follow(dt, game, atan2(p.y - e.y, p.x - e.x), 1.0)
	return true


# ---------------------------------------------------------------------------
# The classic tactics every HANDS setting has (moved out of enemies.gd; the
# hand's tick calls them): fetching help, a brawl with one of its own, holding
# cover, and swinging out from a friend's heels.


## Badly hurt: run for a friend who has not seen the fight yet and bring
## them back; with nobody near, just back off as before.
static func fetch_help(e: Enemy, game: GameWorld) -> bool:
	var best: Enemy = null
	var near := 12.0
	for other: Enemy in game.enemies:
		if (
			other != e
			and other.alive
			and other.tactical()
			and not other.alerted
			and not other.dormant
		):
			var d := sqrt(pow(other.x - e.x, 2) + pow(other.y - e.y, 2))
			if d < near:
				near = d
				best = other
	if best == null:
		return false
	e.fetching = best
	e.fetch_until = game.clock + 7.0
	e.cover = null
	return true


## A brawl with one of its own: close in and swing until one drops or it cools off.
static func brawl(e: Enemy, dt: float, game: GameWorld) -> bool:
	if not e.grudge.alive or game.clock > e.grudge_until:
		e.grudge = null
		return false
	var gap := sqrt(pow(e.grudge.x - e.x, 2) + pow(e.grudge.y - e.y, 2))
	var heading := atan2(e.grudge.y - e.y, e.grudge.x - e.x)
	if gap > e.radius + e.grudge.radius + .25:
		e.follow(dt, game, heading, 1.08)
		return true
	e.angle = heading
	e.face_left = cos(heading) < 0.0
	if e.cooldown <= 0.0:
		e.cooldown = game.rng.uniform(.75, 1.15)
		game.sound_at("brawl_punch", e.x, e.y, .8)
		e.grudge.hurt(game.rng.uniform(8.0, 13.0), game, false, false, e)
	return true


## Running for a friend: once close, it hollers and both come back for the player.
static func fetch(e: Enemy, dt: float, game: GameWorld, p: Player) -> bool:
	if not e.fetching.alive or e.fetching.alerted or game.clock > e.fetch_until:
		e.fetching = null
		return false
	var gap := sqrt(pow(e.fetching.x - e.x, 2) + pow(e.fetching.y - e.y, 2))
	if gap < 2.4 or game.world.visible(e.x, e.y, e.fetching.x, e.fetching.y) and gap < 4.0:
		var friend := e.fetching
		e.fetching = null
		friend.wake(game, p.x, p.y)
		game.sound_at(str(Enemy.AWAKE.get(e.kind, "billy_alert")), e.x, e.y, .85)
		e.hunt_until = game.clock + 9.0
		return false
	e.follow(dt, game, atan2(e.fetching.y - e.y, e.fetching.x - e.x), 1.12)
	return true


## Ducked out of sight: get there, keep low a moment, then come back out.
static func hold_cover(
	e: Enemy, dt: float, game: GameWorld, can_see: bool, direction: float
) -> bool:
	var until: float = e.cover[2]
	if game.clock > until:
		e.cover = null
		return false
	var cx: float = e.cover[0]
	var cy: float = e.cover[1]
	var gap := sqrt(pow(cx - e.x, 2) + pow(cy - e.y, 2))
	if gap > .25:
		e.follow(dt, game, atan2(cy - e.y, cx - e.x), 1.1)
		return true
	if can_see:
		# The player came round: no use hiding here.
		e.cover = null
		return false
	e.angle = direction
	return true


## Which way to swing out so as not to close in on a friend's heels: toward
## the side away from the nearest friend also coming in (0: no one close).
static func spread_side(e: Enemy, game: GameWorld) -> float:
	if game.clock < e.spread_next:
		return e.spread
	e.spread_next = game.clock + .3
	e.spread = 0.0
	var p: Player = game.player
	var best := 2.2
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.alerted or not other.hostile:
			continue
		var d := sqrt(pow(other.x - e.x, 2) + pow(other.y - e.y, 2))
		if d < best:
			best = d
			var ax: float = e.x - p.x
			var ay: float = e.y - p.y
			var bx: float = other.x - p.x
			var by: float = other.y - p.y
			e.spread = .55 if ax * by - ay * bx > 0.0 else -.55
	return e.spread
