## The boss fight's set pieces and looks (boss_kit.gd has the parts the fight
## itself calls; each boss's own moves are src/bosses/):
##   entrance     the first time a boss's fight begins (awake with the player in
##                its arena, or hurt), once a save: the world holds
##                BossKit.INTRO seconds while the view comes round and its name
##                comes down (BossKit.hold, draw_intro). Real play only
##                (game.lessons): tools, tours, benches and bots never get one.
##   telegraphs   while a boss winds up, a ring of warning marks round where it
##                aims closes in as the hit nears and its middle fills (not for
##                the foreman's saw lanes, the baron's outlets, Boggs's lanes or
##                Maw's own floor marks, which say it better), plus its
##                BossMoves.telegraph().
##   damage       smoke off a boss in phase 2, smoke and sparks in phase 3, plus
##                its BossMoves.looks().
##   backup       at phases 2 and 3, BACKUP[difficulty] of the chapter's own
##                kinds come out of the player's sight near the arena, already
##                after them (game.boss_backup; never Maw, who has her pods).
##                They join the enemies after the level's own, so the posse
##                feature saves them with its partners.
##   the fall     slow motion (game.slowmo), gibs, sparks and dust, bodies and
##                chunks thrown, a shower of the chapter's ammo and food
##                (game.rng: that is play), a cheer where no sting plays, and a
##                tally row: BOSS DOWN IN m:ss, from its entrance to its fall.
## Saved: when each boss's fight began and how long it took to put down.
## Looks use `dice`, never the game's rng.
extends GameFeature

## Real seconds of slow motion as a boss falls (game.SLOWMO_PACE is how slow).
const SLOWMO := 1.0
## How many come at each phase change, EASY .. HOG WILD, and how far off the
## player's facing (radians) a spot in plain view must be to count as unseen.
const BACKUP := [2, 3, 3, 4]
const BEHIND := 1.25
## The fewest and most pickups in a fallen boss's shower.
const LOOT := [4, 6]
const LOOT_FALLBACK := ["bullets", "shells", "rinds"]
## Warning marks round a ring, and how wide it starts and ends.
const RING_DOTS := 16
const RING_WIDE := 1.7
const RING_TIGHT := .5
## Bosses whose own marks are their warning.
const NO_RING := ["derby_champ", "maw", "foreman"]
## Names for the tally where a chapter has two.
const SHORT := {
	"boss": "SHERIFF",
	"jerry": "JERRY",
	"rudy": "RUDY",
	"foreman": "FOREMAN",
	"baron": "BARON",
	"swamp_king": "SWAMP KING",
	"derby_champ": "BOGGS",
	"maw": "MAW",
}
const SPECK_CAP := 200

## The level's bosses.
var bosses: Array = []
## kind -> the clock when its fight began; kind -> seconds it took to fall.
var met := {}
var down := {}
## A winding-up boss's instance id -> Vector2(its wind-up's length, last seen).
var windups := {}
var dice := RandomNumberGenerator.new()


func id() -> String:
	return "boss_fight"


func attach() -> void:
	dice.seed = 4977
	for e: Enemy in game.enemies:
		if BossKit.is_boss(e):
			bosses.append(e)
	game.ticked.connect(_tick)
	game.enemy_killed.connect(_killed)


func save() -> Dictionary:
	if met.is_empty() and down.is_empty():
		return {}
	return {"met": met.duplicate(), "down": down.duplicate()}


func restore(state: Dictionary) -> void:
	met = _times(state.get("met", {}))
	down = _times(state.get("down", {}))
	# The phase follows health, so a save needs no field for it; a boss loaded
	# past half is mad already (no second roar when next hit).
	for e: Enemy in bosses:
		e.boss_phase = BossKit.phase_of(e)
		if e.boss_phase >= 2 and e.brain != "maw":
			e.enraged = true


func _times(rows) -> Dictionary:
	var out := {}
	if rows is Dictionary:
		for key in rows:
			var value = rows[key]
			if Enemy.BOSS_TITLES.has(String(key)) and (value is float or value is int):
				out[String(key)] = maxf(0.0, float(value))
	return out


func tally_rows() -> Array:
	var kinds: Array = []
	for e: Enemy in bosses:
		if not kinds.has(e.kind):
			kinds.append(e.kind)
	var rows: Array = []
	for kind: String in kinds:
		if down.has(kind):
			var s := int(down[kind])
			var label := (
				"BOSS DOWN IN"
				if kinds.size() == 1
				else String(SHORT.get(kind, "BOSS")) + " DOWN IN"
			)
			rows.append([label, "%d:%02d" % [int(s / 60.0), s % 60]])
	return rows


# ------------------------------------------------------------------ the fight


func _tick(_dt: float) -> void:
	for e: Enemy in bosses:
		var key := e.get_instance_id()
		if e.windup > 0.0 and e.alive:
			var seen: Vector2 = windups.get(key, Vector2.ZERO)
			if seen == Vector2.ZERO or e.windup > seen.y + .0001:
				seen.x = e.windup
			seen.y = e.windup
			windups[key] = seen
		elif windups.has(key):
			windups.erase(key)
		if not met.has(e.kind) and _begins(e):
			_begin(e)


## Its fight is on: awake and the player in its arena, or already hurt.
func _begins(e: Enemy) -> bool:
	return (
		e.alive
		and e.alerted
		and not game.in_hub
		and game.slowmo <= 0.0
		and game.boss_hold <= 0.0
		and (e.hp < e.max_hp or BossKit.in_arena(game, e))
	)


func _begin(e: Enemy) -> void:
	met[e.kind] = game.clock
	BossKit.moves(e.kind).fight_start(e, game)
	if BossKit.intros_on(game) and game.player.health > 0:
		game.boss_hold = BossKit.INTRO
		game.boss_hold_for = BossKit.INTRO
		game.boss_hold_of = e
		game.boss_hold_armed = false
		game.shake = minf(1.0, game.shake + .3)
		game.sound.play("stamp_thud", 1.0)
	game.boss_intro.emit(e)


## Looks-only specks thrown from (x, y, z), off this feature's dice.
func sparks(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	for _i in count:
		if game.specks.size() >= SPECK_CAP:
			return
		var a := dice.randf() * TAU
		var v := dice.randf_range(.24, speed)
		game.specks.append(
			GameState.Speck.new(
				x,
				y,
				z,
				cos(a) * v,
				sin(a) * v,
				dice.randf_range(.2, speed * 1.3),
				dice.randf_range(.18, .68),
				kind
			)
		)


# ------------------------------------------------------------------ backup


## A boss reached `phase`: some of the chapter's own come for the player from
## out of sight near the arena. How many came.
func backup(e: Enemy, phase: int) -> int:
	if not game.boss_backup or e.brain == "maw" or game.in_hub:
		return 0
	var kinds := ordinary_kinds()
	if kinds.is_empty():
		return 0
	var p = game.player
	var made := 0
	for spot: Vector2 in hidden_spots(e, int(BACKUP[clampi(game.difficulty, 0, 3)])):
		var kind := String(kinds[(made + phase) % kinds.size()])
		var add := Enemy.new(kind, spot.x, spot.y, atan2(p.y - spot.y, p.x - spot.x))
		add.flank = .42 if made % 2 else -.42
		game.enemies.append(add)
		game.total_kills += 1
		add.wake(game, p.x, p.y)
		add.hunt_until = game.clock + 12.0
		add.cooldown = maxf(add.cooldown, 1.2)
		made += 1
	return made


## The hostile kinds the level itself has, bosses aside, in the order met.
func ordinary_kinds() -> Array:
	var kinds: Array = []
	for i in mini(game.enemy_ids.size(), game.enemies.size()):
		var o: Enemy = game.enemies[i]
		if o.hostile and not BossKit.is_boss(o) and not kinds.has(o.kind):
			kinds.append(o.kind)
	return kinds


## Up to `want` open spots near the boss out of the player's sight, that the
## enemies' paths reach, not on top of the player or of each other: first
## those behind something, then those behind the player's back. Rings out
## from the boss, beginning on its far side from the player.
func hidden_spots(e: Enemy, want: int) -> Array:
	var p = game.player
	var w: LevelData = game.world
	var away := atan2(e.y - p.y, e.x - p.x)
	var facing: float = p.view_angle()
	var out: Array = []
	for sweep in 2:
		for ring: float in [3.0, 4.0, 5.5, 7.0, 8.5, 10.0, 12.0, 14.0]:
			for k in 24:
				if out.size() >= want:
					return out
				var turn: int = int((k + 1) / 2.0) * (1 if k % 2 else -1)
				var a := away + turn * TAU / 24.0
				var at := Vector2(e.x + cos(a) * ring, e.y + sin(a) * ring)
				if not _spawnable(at, out):
					continue
				var seen: bool = w.visible(
					p.x, p.y, at.x, at.y, p.eye, w.elevation(at.x, at.y) + .9
				)
				if sweep == 0 and seen:
					continue
				if (
					sweep == 1
					and absf(Enemy.angle_delta(atan2(at.y - p.y, at.x - p.x), facing)) < BEHIND
				):
					continue
				out.append(at)
	return out


## Open floor a hand fits on that the enemies' paths reach from the player,
## not on top of them nor of a spot already taken.
func _spawnable(at: Vector2, taken: Array) -> bool:
	var p = game.player
	var w: LevelData = game.world
	if at.x < 1.0 or at.y < 1.0 or at.x >= w.width - 1 or at.y >= w.height - 1:
		return false
	if w.blocked(at.x, at.y, .4) or w.deep_at(at.x, at.y):
		return false
	if at.distance_to(Vector2(p.x, p.y)) < 4.5:
		return false
	var steps: int = game.flow.distance(at.x, at.y)
	if steps >= FlowField.FAR or steps < 4:
		return false
	for s: Vector2 in taken:
		if s.distance_to(at) < 1.2:
			return false
	return true


# ------------------------------------------------------------------ the fall


func _killed(e: Enemy) -> void:
	if not BossKit.is_boss(e):
		return
	if met.has(e.kind) and not down.has(e.kind):
		down[e.kind] = maxf(0.0, game.clock - float(met[e.kind]))
	game.slowmo = maxf(game.slowmo, SLOWMO)
	_blast(e)
	_loot(e)
	if e != game.finale and e != game.jerry:
		# The chapter's last boss and Jerry have their stings (game_world.gd).
		game.sound.play("crowd_cheer", .8)
	BossKit.moves(e.kind).dying(e, game)
	game.boss_down.emit(e, float(down.get(e.kind, 0.0)))


## Looks only: chunks, sparks and dust thrown wide, what lies near thrown again.
func _blast(e: Enemy) -> void:
	var floor_z: float = game.world.elevation(e.x, e.y)
	var mid: float = floor_z + e.z + e.height * .5
	if game.gore and e.brain != "derby_champ":
		game.gore_fx.burst(e)
	sparks(e.x, e.y, mid, "spark", 26, 3.2)
	sparks(e.x, e.y, floor_z + .2, "dust", 18, 2.4)
	sparks(e.x, e.y, mid, "chips", 12, 2.8)
	game.gore_fx.shove(e.x, e.y, 3.5, 4.5)
	var bodies = game.features.get("corpses")
	if bodies != null:
		bodies.shove(e.x, e.y, 3.5, 3.4)
	game.shake = 1.0
	game.blast_flash = maxf(game.blast_flash, .45)


## The shower of the chapter's ammo and food round where it fell (play: the
## game's rng). None with NO DROPS.
func _loot(e: Enemy) -> void:
	if game.supply_rule == 2:
		return
	var kinds := loot_kinds()
	var count: int = (
		LOOT[0] + mini(LOOT[1] - LOOT[0], int(game.rng.random() * (LOOT[1] - LOOT[0] + 1)))
	)
	for _i in count:
		var name := String(
			kinds[clampi(int(game.rng.random() * kinds.size()), 0, kinds.size() - 1)]
		)
		var spot = _loot_spot(e)
		if spot != null:
			game.add_pickup(name, spot.x, spot.y)


## The ammo and food the chapter's own pickups are, in the order the level lists them.
func loot_kinds() -> Array:
	var out: Array = []
	for row in game.level.pickups:
		var name := String(GameState.ALIAS.get(String(row[0]), String(row[0])))
		if (GameState.AMMO.has(name) or HUD.ITEMS.has(name)) and not out.has(name):
			out.append(name)
	return out if not out.is_empty() else LOOT_FALLBACK.duplicate()


## An open spot round the boss the player can walk to; out of deep water a
## step at a time toward the player when it fell in the lagoon.
func _loot_spot(e: Enemy) -> Variant:
	var w: LevelData = game.world
	for attempt in 6:
		var a: float = game.rng.random() * TAU
		var r: float = game.rng.uniform(.7, 1.6) + attempt * .4
		var at := Vector2(e.x + cos(a) * r, e.y + sin(a) * r)
		if _open(at) and w.visible(e.x, e.y, at.x, at.y):
			return at
	var p = game.player
	var toward := Vector2(p.x - e.x, p.y - e.y)
	var steps := int(toward.length() / .5)
	for k in steps:
		var at := Vector2(e.x, e.y) + toward.normalized() * (k * .5)
		if _open(at):
			return at
	return null


func _open(at: Vector2) -> bool:
	var w: LevelData = game.world
	return (
		at.x > 1.0
		and at.y > 1.0
		and at.x < w.width - 1
		and at.y < w.height - 1
		and not w.blocked(at.x, at.y, .2)
		and not w.deep_at(at.x, at.y)
	)


# ------------------------------------------------------------------ the picture


func ground_marks() -> Array:
	var out: Array = []
	for e: Enemy in bosses:
		if not e.alive or e.windup <= 0.0:
			continue
		if _rings(e):
			out.append_array(_ring(e))
		for thing in BossKit.moves(e.kind).telegraph(e, game):
			if thing is Renderer.GroundMark:
				out.append(thing)
	return out


## Whether the shared ring warns of this wind-up (its aim point is where the
## hit goes): not for the bosses that mark their own, nor the baron's outlets.
func _rings(e: Enemy) -> bool:
	if e.aim_mark == null or NO_RING.has(e.brain):
		return false
	return not (e.brain == "baron" and BaronMoves.outlets_next(e.attacks, e.enraged))


## Warning marks closing in round the aim point as the wind-up runs down, the
## middle filling.
func _ring(e: Enemy) -> Array:
	var out: Array = []
	var seen: Vector2 = windups.get(e.get_instance_id(), Vector2(e.windup, e.windup))
	var t := clampf(1.0 - e.windup / maxf(.05, seen.x), 0.0, 1.0)
	var mx := float(e.aim_mark[0])
	var my := float(e.aim_mark[1])
	var r := lerpf(RING_WIDE, RING_TIGHT, t)
	var dot := .16 + .06 * t
	var w: LevelData = game.world
	for k in RING_DOTS:
		var a := k * TAU / RING_DOTS + t * .9
		var x := mx + cos(a) * r
		var y := my + sin(a) * r
		if w.blocked(x, y, .05):
			continue
		out.append(
			Renderer.GroundMark.new(x, y, w.elevation(x, y) + .005, a, dot, dot, "mark_warning")
		)
	var fill := .12 + .42 * t
	out.append(
		Renderer.GroundMark.new(mx, my, w.elevation(mx, my) + .006, 0.0, fill, fill, "mark_slam")
	)
	return out


func sprites() -> Array:
	var out: Array = []
	for e: Enemy in bosses:
		if not e.alive or not game.in_view(e.x, e.y, 2.5):
			continue
		var moves := BossKit.moves(e.kind)
		if e.windup > 0.0:
			for thing in moves.telegraph(e, game):
				if thing is Renderer.Sprite:
					out.append(thing)
		if e.boss_phase >= 2:
			out.append_array(_damage(e))
		out.append_array(moves.looks(e, game))
	return out


## Smoke curling up off a boss past half, sparks too past a fifth: on the side
## the player sees, so the body never hides them.
func _damage(e: Enemy) -> Array:
	var out: Array = []
	var p = game.player
	var floor_z: float = game.world.elevation(e.x, e.y) + e.z
	var toward := atan2(p.y - e.y, p.x - e.x)
	var tall: float = e.height * e.variant
	var wisps := 3 if e.boss_phase == 2 else 5
	var base := float(e.get_instance_id() % 97) * .13
	for k in wisps:
		var age := fposmod(game.clock * .55 + float(k) / wisps + base, 1.0)
		var a := toward + (k - (wisps - 1) * .5) * .55
		var drift := age * .3
		var wisp := Renderer.Sprite.new(
			e.x + cos(a) * (e.radius + .05) + cos(a + 1.4) * drift,
			e.y + sin(a) * (e.radius + .05) + sin(a + 1.4) * drift,
			"fx_smoke_%d" % mini(3, int(age * 4.0)),
			.45 + age * .7,
			floor_z + tall * (.45 + age * .7)
		)
		# Thick low down, thinning as it rises.
		wisp.translucent = age > .35
		out.append(wisp)
	if e.boss_phase >= 3:
		for k in 3:
			var a: float = toward + sin(game.clock * 2.3 + k * 2.1) * .9
			var spark := Renderer.Sprite.new(
				e.x + cos(a) * (e.radius + .08),
				e.y + sin(a) * (e.radius + .08),
				"fx_sparks_%d" % ((int(game.clock * 12.0) + k * 2) % 3),
				.42,
				floor_z + tall * (.3 + .22 * k)
			)
			spark.glow = true
			out.append(spark)
	return out
