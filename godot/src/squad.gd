## The county's hands as a squad (each hand's part here; who does what is
## handed out by features/squad_feature.gd every SQUAD_STEP seconds). A hand
## (Squad.hand: one of the county's own on two legs, not a boss, a bug or a
## gator) carries a Mind with its share of it:
##   - an idle activity before it notices anything (src/idle_life.gd), and a
##     fumble or a stun when it is startled out of it (startled());
##   - investigating a shot it heard but could not see (the feature hears
##     them): it comes to look, then looks about where the shot was;
##   - flanking: sent wide round the player along the flow field's rings
##     (steps equal from the player), then in from the side;
##   - pressing in while a friend keeps shooting;
##   - flushing a player who has gone to ground with a lobbed bottle or a
##     stick of dynamite (a wind-up facing the spot, its warning mark, a fuse);
##   - falling back to regroup when the squad is losing;
##   - searching where it last saw the player once the hunt runs out, and
##     giving up after a while (alerted off).
## How much of it a hand does follows DIFFICULTY (EASY barely coordinates,
## HOG WILD a lot). No sight lines but the flush's one: everything reads the
## hands' own last look (player_seen) and the flow field. Dice: game.rng.
## Barks (game.enemy_bark) are throttled per hand, per moment and overall.
class_name Squad
extends RefCounted

## Seconds a hand searches before it gives up, by difficulty.
const SEARCH := [6.0, 9.0, 13.0, 17.0]
## The stun of a hand hit from behind while it noticed nothing, by difficulty.
const SNEAK_STUN := [1.6, 1.3, 1.0, .8]
## How far round the player (radians) a flanker swings before it closes in.
const FLANK_SWING := 1.4
## Seconds between one bark of a moment and the next (any hand), and between
## any two barks at all.
const MOMENT_GAP := {
	"spot": 1.6,
	"lost": 5.0,
	"search": 6.0,
	"help": 4.0,
	"flank": 5.0,
	"cover": 4.0,
	"brawl": 5.0,
	"idle": 7.0,
	"surprised": 1.5,
	"hurt_bad": 3.0,
	"regroup": 8.0,
}
const ANY_GAP := .7
const OWN_GAP := 3.5


class Mind:
	## Its activity ("" none), its place for it and the thing it faces, and its
	## own offset in the activity's loop.
	var activity := ""
	var spot := Vector2.ZERO
	var focus := Vector2.ZERO
	var phase := 0.0
	## A shot it heard: [x, y, until].
	var investigate = null
	var looked := false
	## Searching after the hunt ran out: till when, round where, the spot it
	## is walking to and how long it looks about there.
	var search_until := 0.0
	var search_home := Vector2.ZERO
	var search_to := Vector2.ZERO
	var search_look := 0.0
	var search_walk := 0.0
	## Flanking: till when, which way round (+1, -1) and from what bearing.
	var flank_until := 0.0
	var flank_side := 1.0
	var flank_from := 0.0
	var press_until := 0.0
	## Falling back: [x, y, until].
	var regroup = null
	## A throw to flush the player out: when it lets go, and where to.
	var flush_at := 0.0
	var flush_to := Vector2.ZERO
	## What it was doing last tick, for the barks.
	var bark_next := 0.0
	var was_cover := false
	var was_fetching := false
	var was_brawling := false
	var said_hurt := false


## One of the county's hands the squad has a part for.
static func hand(e: Enemy) -> bool:
	return e.tactical() and Enemy.TURNS.has(e.kind) and not e.swims


## A bark for the voices (game.enemy_bark), unless one was just heard.
static func bark(e: Enemy, game, moment: String) -> void:
	var now: float = game.clock
	var m = e.mind
	if m != null and now < m.bark_next:
		return
	if now < float(game.bark_next.get(moment, 0.0)) or now < float(game.bark_next.get("", 0.0)):
		return
	game.bark_next[moment] = now + float(MOMENT_GAP.get(moment, 3.0))
	game.bark_next[""] = now + ANY_GAP
	if m != null:
		m.bark_next = now + OWN_GAP
	game.enemy_bark.emit(e, moment)


## Every tick of a hand: the barks for what it took up on its own (ducking
## into cover, running for help, a brawl, badly hurt).
static func watch(e: Enemy, game) -> void:
	var m = e.mind
	var ducking: bool = e.cover != null
	if ducking and not m.was_cover:
		bark(e, game, "cover")
	m.was_cover = ducking
	var fetching: bool = e.fetching != null
	if fetching and not m.was_fetching:
		bark(e, game, "help")
	m.was_fetching = fetching
	var brawling: bool = e.grudge != null
	if brawling and not m.was_brawling:
		bark(e, game, "brawl")
	m.was_brawling = brawling
	if not m.said_hurt and e.hp < e.max_hp * .25:
		m.said_hurt = true
		bark(e, game, "hurt_bad")


## It notices the player (Enemy.wake, before `alerted`): startled out of its
## activity it fumbles for its gun; hit from behind unaware it is stunned (a
## sneak attack). Either way the activity is over.
static func startled(e: Enemy, game) -> void:
	var m = e.mind
	var busy: bool = m.activity != "" and IdleLife.at_it(e)
	var was: String = m.activity
	m.activity = ""
	m.investigate = null
	m.search_until = 0.0
	var p = game.player
	if e.struck_at == game.clock and e.struck_at >= 0.0:
		var toward := atan2(p.y - e.y, p.x - e.x)
		if absf(Enemy.angle_delta(toward, e.angle)) > 1.75:
			e.stun = maxf(e.stun, float(SNEAK_STUN[clampi(game.difficulty, 0, 3)]))
			e.flinch = maxf(e.flinch, .5)
			e.cooldown = maxf(e.cooldown, 1.2)
			if game.barks.enabled:
				game.callout = "SNEAK ATTACK!"
				game.callout_until = game.clock + 1.6
			_spill(e, game, was)
			bark(e, game, "surprised")
			return
	if busy:
		e.cooldown = maxf(e.cooldown, 1.1)
		_spill(e, game, was)
		bark(e, game, "surprised")
	else:
		bark(e, game, "spot")


## Whatever it had in hand goes flying: the bottle, the cards, the feed.
static func _spill(e: Enemy, game, was: String) -> void:
	var floor_z: float = game.world.elevation(e.x, e.y)
	var what := "glass" if was == "drinking" else "dust"
	game.burst(e.x + cos(e.angle) * .3, e.y + sin(e.angle) * .3, floor_z + .9, what, 6, 1.3)
	game.sound_at("tosser_glass", e.x, e.y, .45)


## Not alerted: investigating a shot it heard, or busy at its activity. False
## leaves it to its patrol.
static func calm(e: Enemy, dt: float, game) -> bool:
	var m = e.mind
	if m.investigate != null:
		var heard: Array = m.investigate
		if game.clock > float(heard[2]):
			m.investigate = null
		else:
			var to := Vector2(float(heard[0]), float(heard[1]))
			var gap := to - Vector2(e.x, e.y)
			if gap.length() > 1.3:
				var lead := NAN
				var p = game.player
				if game.flow != null and to.distance_to(Vector2(p.x, p.y)) < 2.5:
					# The shot was the player's: come round by the open floor.
					lead = game.flow.heading(e.x, e.y)
				e.follow(dt, game, gap.angle() if is_nan(lead) else lead, .78)
				return true
			if not m.looked:
				m.looked = true
				bark(e, game, "search")
			e.angle += dt * (1.3 if int(game.clock * .5) % 2 else -1.3)
			return true
	if IdleLife.act(e, dt, game):
		if (
			game.clock > m.bark_next
			and absf(e.x - game.player.x) < 7.0
			and absf(e.y - game.player.y) < 7.0
		):
			bark(e, game, "idle")
			m.bark_next = maxf(m.bark_next, game.clock + 9.0 + m.phase)
		return true
	return false


## Alerted, its turn to move (after its attack, cover, help and brawls had
## theirs): falling back, a throw to flush the player out, flanking, pressing
## in, or searching once the hunt ran out. False leaves it to the usual chase.
static func move(e: Enemy, dt: float, game, can_see: bool, distance: float) -> bool:
	var m = e.mind
	var now: float = game.clock
	var p = game.player
	if m.regroup != null:
		var rally: Array = m.regroup
		if now > float(rally[2]):
			m.regroup = null
			e.hunt_until = now + 7.0
		else:
			var gap := Vector2(float(rally[0]) - e.x, float(rally[1]) - e.y)
			if gap.length() > .5:
				e.follow(dt, game, gap.angle(), 1.12)
			else:
				e.angle = atan2(p.y - e.y, p.x - e.x)
			return true
	if m.flush_at > 0.0:
		e.angle = (m.flush_to - Vector2(e.x, e.y)).angle()
		e.face_left = cos(e.angle) < -.24
		if now >= m.flush_at:
			m.flush_at = 0.0
			_flush(e, game)
		return true
	if now < m.flank_until:
		if _flank_step(e, dt, game):
			return true
		m.flank_until = 0.0
	if now < m.press_until and can_see and distance > 1.7:
		e.follow(dt, game, atan2(p.y - e.y, p.x - e.x), 1.15)
		return true
	if can_see or now < e.hunt_until or e.target == null:
		m.search_until = 0.0
		return false
	if m.search_until == 0.0:
		var spot: Array = e.target
		m.search_until = now + float(SEARCH[clampi(game.difficulty, 0, 3)])
		m.search_home = Vector2(float(spot[0]), float(spot[1]))
		m.search_to = m.search_home
		m.search_walk = now + 5.0
		m.search_look = 0.0
		m.looked = false
		bark(e, game, "lost")
	if now > m.search_until:
		# Nothing: back to whatever it was about.
		m.search_until = 0.0
		e.alerted = false
		e.target = null
		e.hunt_until = 0.0
		e.player_seen = false
		return true
	_search_step(e, dt, game)
	return true


## Looking about where it last saw the player: to a spot, a look round, then
## another spot near there (game.rng; one sight line a spot, so it never
## picks one through a wall).
static func _search_step(e: Enemy, dt: float, game) -> void:
	var m = e.mind
	var now: float = game.clock
	var gap: Vector2 = m.search_to - Vector2(e.x, e.y)
	if m.search_look <= 0.0 and gap.length() > .35 and now < m.search_walk:
		e.follow(dt, game, gap.angle(), .8)
		return
	if m.search_look <= 0.0:
		m.search_look = game.rng.uniform(1.1, 2.2)
		if not m.looked:
			m.looked = true
			bark(e, game, "search")
	m.search_look -= dt
	e.angle += dt * (1.6 if int(now * .7) % 2 else -1.6)
	if m.search_look > 0.0:
		return
	var a: float = game.rng.uniform(0.0, TAU)
	var r: float = game.rng.uniform(1.4, 3.2)
	var to: Vector2 = m.search_home + Vector2(cos(a), sin(a)) * r
	if (
		not game.world.blocked(to.x, to.y, e.radius)
		and game.world.visible(m.search_home.x, m.search_home.y, to.x, to.y)
	):
		m.search_to = to
	else:
		m.search_to = m.search_home
	m.search_walk = now + 4.0


## A step of a flank: round the player along the flow field, keeping about as
## many steps off as it is (wide while near, drawing in while far), the way
## it was sent round. False when it has swung far enough round, is near
## enough or off the field: the chase takes over and comes in from there.
static func _flank_step(e: Enemy, dt: float, game) -> bool:
	var f: FlowField = game.flow
	if f == null:
		return false
	var m = e.mind
	var cx := int(e.x)
	var cy := int(e.y)
	if cx < 0 or cy < 0 or cx >= f.width or cy >= f.height:
		return false
	var w := f.width
	var here := f.steps[cy * w + cx]
	if here >= FlowField.FAR or here <= 3:
		return false
	var p = game.player
	var rel := Vector2(e.x - p.x, e.y - p.y)
	if Enemy.angle_delta(rel.angle(), m.flank_from) * m.flank_side >= FLANK_SWING:
		return false
	var want := 1 if here < 5 else 0 if here < 8 else -1
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for n: Vector2i in FlowField.NEIGHBOURS:
		var nx := cx + n.x
		var ny := cy + n.y
		if nx < 0 or ny < 0 or nx >= f.width or ny >= f.height:
			continue
		var d := f.steps[ny * w + nx]
		if d >= FlowField.FAR:
			continue
		if n.x != 0 and n.y != 0:
			if f.steps[cy * w + nx] >= FlowField.FAR or f.steps[ny * w + cx] >= FlowField.FAR:
				continue
		var step := Vector2(n.x, n.y).normalized()
		var round_by: float = (rel.x * step.y - rel.y * step.x) * m.flank_side / rel.length()
		if round_by < .2:
			continue
		var score := round_by * 2.0 - absf(float(d - here - want))
		if score > best_score:
			best_score = score
			best = Vector2i(nx, ny)
	if best.x < 0:
		return false
	e.follow(dt, game, atan2(best.y + .5 - e.y, best.x + .5 - e.x), 1.05)
	return true


## Lets go of the throw: a bottle for the bottle-throwing kinds, else a lit
## stick of dynamite that lies burning a moment before it goes.
static func _flush(e: Enemy, game) -> void:
	var m = e.mind
	var to: Vector2 = m.flush_to
	var gap := to - Vector2(e.x, e.y)
	var distance := gap.length()
	var direction := gap.angle()
	var eye: float = game.world.elevation(e.x, e.y) + minf(.92, e.height * .72)
	var sx := e.x + cos(direction) * .34
	var sy := e.y + sin(direction) * .34
	if game.world.blocked(sx, sy, .045, eye):
		return
	var target_z: float = game.world.elevation(to.x, to.y)
	e.attacks += 1
	e.cooldown = maxf(e.cooldown, 1.4)
	if e.brain == "bottle_tosser":
		var flight := minf(1.32, maxf(.48, distance / 6.1))
		var speed := maxf(.45, (distance - .34) / flight)
		var shot := String(Enemy.DEFS[e.kind].get("shot", "fair_bottle"))
		var vz := (target_z + .06 - eye) / flight + 2.75 * flight
		game.launch(sx, sy, eye, direction, speed, shot, vz, true, 0, flight)
		game.sound_at("tosser_throw", e.x, e.y, .85)
		return
	var time := clampf(distance / 5.5, .55, 1.3)
	var vz2 := (target_z + .05 - eye) / time + .5 * Shots.gravity("tnt") * time
	game.launch(sx, sy, eye, direction, distance / time, "tnt", vz2, true, 0, time + 1.7)
	game.sound_at("fuse_hiss", e.x, e.y, .8)
