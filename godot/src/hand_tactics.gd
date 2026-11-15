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


## Where a hand ducks (Enemy.take_cover): smart, a hidden spot right behind
## something solid where one is near; else Enemy.find_cover's.
static func cover(e: Enemy, game: GameWorld) -> Variant:
	if not smart(game):
		return e.find_cover(game)
	var p: Player = game.player
	var w: LevelData = game.world
	var away := atan2(e.y - p.y, e.x - p.x)
	var fallback: Variant = null
	var fallback_ring := 0.0
	for ring: float in [1.0, 1.7, 2.4, 3.1, 3.8]:
		if fallback != null and ring > fallback_ring + .8:
			# A ring further on than the open spot found: take that one.
			break
		for k in 12:
			# Away from the player first, round to the sides.
			var turn := ((k + 1) >> 1) * (1 if k % 2 else -1)
			var a := away + turn * TAU / 12.0
			var cx := e.x + cos(a) * ring
			var cy := e.y + sin(a) * ring
			if w.blocked(cx, cy, e.radius) or not w.visible(e.x, e.y, cx, cy):
				continue
			var head: float = w.elevation(cx, cy) + minf(.92, e.height * .72)
			if w.visible(p.x, p.y, cx, cy, p.eye, head):
				continue
			var to := Vector2(p.x - cx, p.y - cy).normalized()
			if w.blocked(cx + to.x * (e.radius + .45), cy + to.y * (e.radius + .45), .12):
				# Something solid between it and the player, right there.
				return Vector2(cx, cy)
			if fallback == null:
				fallback = Vector2(cx, cy)
				fallback_ring = ring
	return fallback


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
		e.take_cover(game)
		if e.cover != null:
			var spot: Array = e.cover
			var sx: float = spot[0]
			var sy: float = spot[1]
			m.cover_home = Vector2(sx, sy)
			e.cover = [sx, sy, game.clock + RELOAD + .4]
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
