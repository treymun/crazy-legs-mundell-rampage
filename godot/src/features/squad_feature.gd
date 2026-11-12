## The county's hands working together (src/squad.gd has each hand's part,
## src/idle_life.gd what they do before they notice anything). On a chapter's
## first tick every hand gets a Mind and the level's own an activity from
## what stands near its place. Then: a shot heard but not seen sends the
## hands in earshot to look (SHOT_NOISE times HEARING); and every SQUAD_STEP
## seconds the hands hunting the player near by are a squad: one sent wide
## to flank, one pressing in while a friend shoots, a throw to flush a
## player gone to ground, a fall back to regroup when they are losing.
## Difficulty sets how much of that happens and how often (EASY: none of it
## but hearing and searching). Nothing saved: like cover and brawls it is the
## moment's tactics, and the activities come from the level again on load.
extends GameFeature

const SQUAD_STEP := .4
## How far out a shot is heard, as a share of the gun's own noise (the hands
## that can see it are woken by Weapons as before), by difficulty.
const HEARING := [.75, 1.1, 1.35, 1.6]
## A squad: the alerted hands within this of the player.
const NEAR := 18.0
## Flankers out at once; the chance one is sent at a step and the wait
## after; pressing in likewise; a throw's wait; by difficulty.
const FLANKERS := [0, 1, 1, 2]
const FLANK_CHANCE := [0.0, .4, .7, .95]
const FLANK_WAIT := [0.0, 7.0, 4.5, 2.5]
const PRESS_CHANCE := [0.0, .3, .6, .85]
const PRESS_WAIT := [0.0, 5.0, 3.5, 2.5]
const FLUSH_WAIT := [0.0, 14.0, 10.0, 7.0]
## Seconds unseen before a throw flushes the player, and its wind-up.
const GONE_TO_GROUND := 2.5
const FLUSH_WINDUP := .85

var started := false
var next_step := 0.0
var flank_next := 0.0
var press_next := 0.0
var flush_next := 0.0
var regroup_next := 0.0
var last_seen := 0.0
## Hands fallen lately: [when, x, y].
var losses: Array = []
## The hands at an activity (as of the last step), for their puffs and sparks.
var busy: Array = []


func id() -> String:
	return "squad"


func attach() -> void:
	game.ticked.connect(_tick)
	game.shot_fired.connect(_heard)
	game.enemy_killed.connect(_fell)


func _tick(_dt: float) -> void:
	if not started:
		started = true
		_start()
	if game.clock < next_step:
		return
	next_step = game.clock + SQUAD_STEP
	busy.clear()
	if game.players.size() == 1:
		_step(null)
		return
	# A squad for each player: the hands after them (Enemy.hunted).
	for q: Player in game.players:
		if q.health > 0:
			game.focus(q)
			_step(q)
	game.focus(game.local_player)


## Every hand a Mind, and the level's own still at their places an activity.
func _start() -> void:
	var about := IdleLife.things(game)
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		if not Squad.hand(e):
			continue
		e.mind = Squad.Mind.new()
		e.mind.phase = fmod(i * 1.37, 5.0)
		if i >= game.enemy_ids.size() or e.dormant or e.alerted or not e.alive:
			continue
		if not e.route.is_empty():
			continue
		var spec: Dictionary = game.level.enemies[i]
		var at := Vector2(float(spec["x"]), float(spec["y"]))
		var picked := IdleLife.pick(game, e, at, i, about)
		if picked.is_empty():
			continue
		e.mind.activity = String(picked[0])
		e.mind.spot = at
		e.mind.focus = picked[1]


func _heard(gun: int) -> void:
	if not started or gun < 0 or gun >= Weapons.SHOT_NOISE.size():
		return
	var p = game.player
	var reach: float = float(Weapons.SHOT_NOISE[gun]) * HEARING[clampi(game.difficulty, 0, 3)]
	for e: Enemy in game.enemies:
		if e.mind == null or e.alerted or e.dormant or not e.alive:
			continue
		var dx: float = e.x - p.x
		var dy: float = e.y - p.y
		if dx * dx + dy * dy < reach * reach:
			e.mind.investigate = [p.x, p.y, game.clock + 10.0]
			e.mind.looked = false


func _fell(e: Enemy) -> void:
	if e.mind != null:
		losses.append([game.clock, e.x, e.y])


## `only`: the hands after that player (null: all, with one player).
func _step(only: Player) -> void:
	var now: float = game.clock
	var p = game.player
	var group: Array = []
	var seers: Array = []
	for e: Enemy in game.enemies:
		if e.mind == null:
			if not e.alive or not Squad.hand(e):
				continue
			# Joined since the start (a posse partner, a boss's backup).
			e.mind = Squad.Mind.new()
		if not e.alive or e.dormant:
			continue
		if only != null and (e.hunted if e.hunted != null else game.players[0]) != only:
			continue
		if not e.alerted:
			if e.mind.activity != "":
				busy.append(e)
			continue
		var dx: float = e.x - p.x
		var dy: float = e.y - p.y
		if dx * dx + dy * dy > NEAR * NEAR:
			continue
		group.append(e)
		if e.player_seen:
			seers.append(e)
			last_seen = now
	if group.is_empty() or p.health <= 0:
		return
	var level := clampi(game.difficulty, 0, 3)
	if level == 0:
		return
	_regroup(group, now)
	_flank(group, now, level)
	_press(seers, now, level)
	_flush(group, now, level)


## Losing (two or more down lately and the rest hurt, or three down): the
## squad falls back on the one farthest from the player and comes on again
## together.
func _regroup(group: Array, now: float) -> void:
	var kept: Array = []
	for row: Array in losses:
		if now - float(row[0]) < 10.0:
			kept.append(row)
	losses = kept
	if now < regroup_next or group.size() < 2 or losses.size() < 2:
		return
	var health := 0.0
	for e: Enemy in group:
		health += e.hp / e.max_hp
	if losses.size() < 3 and health / group.size() > .65:
		return
	var p = game.player
	var rally: Enemy = null
	var far := -1.0
	for e: Enemy in group:
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d > far:
			far = d
			rally = e
	var away := Vector2(rally.x - p.x, rally.y - p.y).normalized()
	var at := Vector2(rally.x, rally.y) + away * 1.5
	if game.world.blocked(at.x, at.y, rally.radius):
		at = Vector2(rally.x, rally.y)
	for e: Enemy in group:
		if e.fetching == null and e.grudge == null:
			e.mind.regroup = [at.x, at.y, now + 3.2]
			e.mind.flank_until = 0.0
			e.cover = null
	Squad.bark(rally, game, "regroup")
	regroup_next = now + 25.0
	losses.clear()


## One sent wide round the player: one that cannot see them (they went
## round a building) before one that can, the farthest first; it goes the
## way away from the nearest friend.
func _flank(group: Array, now: float, level: int) -> void:
	if group.size() < 2 or now < flank_next:
		return
	var out := 0
	for e: Enemy in group:
		if e.mind.flank_until > now:
			out += 1
	if out >= FLANKERS[level]:
		return
	var p = game.player
	var pick: Enemy = null
	var best := -1.0
	for e: Enemy in group:
		var m = e.mind
		if (
			m.flank_until > now
			or m.press_until > now
			or m.regroup != null
			or m.flush_at > 0.0
			or e.cover != null
			or e.fetching != null
			or e.grudge != null
			or e.retreat != null
		):
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < 3.5 or d > 15.0:
			continue
		var score := d + (0.0 if e.player_seen else 20.0)
		if score > best:
			best = score
			pick = e
	flank_next = now + FLANK_WAIT[level]
	if pick == null or game.rng.random() >= FLANK_CHANCE[level]:
		return
	var mine := atan2(pick.y - p.y, pick.x - p.x)
	var nearest := INF
	var side := 1.0 if pick.flank >= 0.0 else -1.0
	for e: Enemy in group:
		if e == pick:
			continue
		var delta := Enemy.angle_delta(atan2(e.y - p.y, e.x - p.x), mine)
		if absf(delta) < nearest:
			nearest = absf(delta)
			side = -1.0 if delta > 0.0 else 1.0
	pick.mind.flank_from = mine
	pick.mind.flank_side = side
	pick.mind.flank_until = now + 8.0
	Squad.bark(pick, game, "flank")


## One keeps shooting while another closes in.
func _press(seers: Array, now: float, level: int) -> void:
	if seers.size() < 2 or now < press_next:
		return
	var shooter: Enemy = null
	for e: Enemy in seers:
		if e.windup > 0.0 or e.recovery > 0.0 or e.volley > 0:
			shooter = e
			break
	if shooter == null:
		return
	press_next = now + PRESS_WAIT[level]
	if game.rng.random() >= PRESS_CHANCE[level]:
		return
	var p = game.player
	for e: Enemy in seers:
		if e == shooter or e.mind.flank_until > now or e.mind.regroup != null:
			continue
		if Vector2(e.x - p.x, e.y - p.y).length() > 2.6 and e.retreat == null and e.cover == null:
			e.mind.press_until = now + 2.6
			return


## The player gone to ground near the squad: one lobs something at the spot
## (a bottle thrower its bottle; on HARD and HOG WILD any hand a stick of
## dynamite, out of doors), after a wind-up facing it with a warning mark.
func _flush(group: Array, now: float, level: int) -> void:
	if now < flush_next or now - last_seen < GONE_TO_GROUND:
		return
	var p = game.player
	var w = game.world
	for e: Enemy in group:
		var m = e.mind
		var bottle := e.brain == "bottle_tosser"
		if (
			not (bottle or level >= 2)
			or m.flank_until > now
			or m.regroup != null
			or e.windup > 0.0
			or e.cooldown > .3
			or e.stun > 0.0
		):
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < 3.5 or d > 9.0:
			continue
		var toward := Vector2(e.x - p.x, e.y - p.y) / d
		var to := Vector2(p.x, p.y) + toward * 1.0
		if w.blocked(to.x, to.y, .1):
			to = Vector2(p.x, p.y)
		if not bottle and (w.roof[w.cell(e.x, e.y)] != 0.0 or w.roof[w.cell(to.x, to.y)] != 0.0):
			continue
		var high: float = maxf(w.elevation(e.x, e.y), w.elevation(to.x, to.y)) + 1.9
		if not w.visible(e.x, e.y, to.x, to.y, high, high):
			continue
		m.flush_at = now + FLUSH_WINDUP
		m.flush_to = to
		game.sound_at("tosser_rattle" if bottle else "fuse_hiss", e.x, e.y, .8)
		flush_next = now + FLUSH_WAIT[level]
		return


func ground_marks() -> Array:
	var out: Array = []
	if not started:
		return out
	for e: Enemy in game.enemies:
		if e.mind != null and e.alive and e.mind.flush_at > 0.0:
			out.append(game._spot(e.mind.flush_to.x, e.mind.flush_to.y, 1.1, "warning"))
	for shot in game.shots:
		if shot.enemy and shot.kind == "tnt":
			out.append(game._spot(shot.x, shot.y, 2.0, "warning"))
	return out


## The activities' puffs and sparks: a smoker's smoke, a prober's and a
## tinkerer's sparks, on each one's own loop (no dice).
func sprites() -> Array:
	var out: Array = []
	for e: Enemy in busy:
		var m = e.mind
		if m.activity == "" or e.alerted or not e.alive:
			continue
		if not game.in_view(e.x, e.y, 1.0) or not IdleLife.at_it(e):
			continue
		var t: float = e.pose + m.phase
		var floor_z: float = game.world.elevation(e.x, e.y)
		match m.activity:
			"smoking":
				var puff := fmod(t, 4.6) - 3.9
				if puff > 0.0:
					var s: Renderer.Sprite = game.pooled(
						e.x + cos(e.angle) * .2,
						e.y + sin(e.angle) * .2,
						"fx_smoke_%d" % mini(3, int(puff * 6.0)),
						.16 + puff * .2,
						floor_z + e.height * .82 + puff * .5
					)
					s.translucent = true
					out.append(s)
			"probing", "tinkering":
				var spark := fmod(t, 2.6 if m.activity == "probing" else 3.1)
				if spark > 1.3 and spark < 1.75:
					var at: Vector2 = Vector2(e.x, e.y).lerp(m.focus, .6)
					var glint: Renderer.Sprite = game.pooled(
						at.x, at.y, "fx_sparks_%d" % (int(t * 12.0) % 3), .22, floor_z + .45
					)
					glint.glow = true
					out.append(glint)
	return out
