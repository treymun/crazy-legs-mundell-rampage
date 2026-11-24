## Our own thrown shots drawn at our own time, and what they do when they
## land. A projectile gun's shot (the saw blade, the bowling ball, the
## dynamite crossbow's bolt...) and a stick of dynamite came into a client's
## copy a round trip and the playout after the press, from where our player
## stood back then, behind the drawn one, and blew up that much later too.
## Now, looks only, the host's game still the only truth:
##
## - at the press (net_shot_predict.gd shows the shot) a ghost of it flies
##   from where our screen shows us, along our aim, with the shot's own
##   speed, lift and fall, until it meets a wall, the floor or a body; a
##   stick of dynamite tumbles as the copy's would (Tumble.step) until its
##   fuse is out;
## - once the copy has its own (one of ours it had not seen) the oldest ghost
##   of that kind goes and the copy's shot is drawn as far on as our inputs
##   lead the copy (the ticks it has not played), so it carries on where the
##   ghost was; a stick's ghost stays the one drawn, the copy's hidden;
## - where the ghost (or the copy's shot drawn on) lands, a shot that blows
##   up blows up at once (`_boom`: the sound, the flash, the shake, the
##   fireball, scorch, grit and wreck bits of the looks features), and a
##   stick when its fuse is out; when the copy's own blast of it comes, the
##   game asks (game_combat.gd explode, `HandsWatch.blast_shown`) and its
##   looks are not shown again (`game.blast_quiet`); its hurt and breaks are
##   the copy's, as ever. One that strikes a body shows the hit mark;
## - a ghost the copy never matches (the host refused the shot) goes after
##   WAIT seconds, unseen if it had not landed yet.
##
## Each frame: begin() after the others are blended (net_blend.gd), end()
## after the frame (main.gd net_draw_begin / net_draw_end). A ghost is put in
## game.shots for the frame only (uid 0: nothing carried names it), and the
## copy's shots it stands for are taken out for the frame.
class_name NetOwnShots
extends RefCounted

## Off: our shots show when the copy plays them (net_feel `old`).
static var enabled := true
## Off: a blast shows when the copy plays it (net_feel `old`).
static var blasts := true
## Seconds a ghost waits for the copy's own shot.
const WAIT := 1.0
## Ticks at most a copy's shot is drawn ahead of it. (Shots that roll or
## rest, the bowling ball and the like, are drawn where the copy has them:
## their path is not a throw's.)
const MOST_AHEAD := 60
## The flight's steps (cells), as move_shot's.
const AHEAD_STEP := .09
## The copy's blast is the one we showed when it goes off this near it.
const BLAST_NEAR := 2.5
## Seconds a shown blast waits for the copy's.
const BLAST_WAIT := 3.0
## How a stick of dynamite leaves the hand (game_combat.gd throw_dynamite).
const TNT_REACH := .21
const TNT_SPEED := 6.1

## Ghosts: {"shot", "age", "hit", "tnt", "boomed", "uid"}.
var ghosts: Array = []
## Blasts shown: {"kind", "at" (Vector3), "age", "used"}.
var shown_blasts: Array = []
## For net_feel.gd and predict_check: ghosts made, matched, blasts shown.
var made := 0
var matched := 0
var boomed := 0
## The copy's own shots already matched, by uid.
var _seen := {}
## The copy's shots whose blast we showed, or whose ghost is drawn instead
## (a stick of dynamite): left out of the picture until they are gone.
var _hidden := {}
## The copy's shots whose hit mark we showed.
var _marked := {}
var _added: Array = []
## [shot, x, y, z] of the copy's shots drawn ahead, to put back.
var _moved: Array = []
## [index, shot] taken out of game.shots for the frame, in index order.
var _taken: Array = []
var _game: WeakRef = null
## Our own dice for the specks (never game.rng).
var _dice := RandomNumberGenerator.new()


## A projectile gun's shot shown at the press: its ghost leaves from `me`.
func launch(game: Game, me: Player, gun: int) -> void:
	if not enabled:
		return
	var how: Dictionary = Weapons.FIRING[gun]
	if str(how.get("fire", "")) != "projectile":
		return
	var speed: float = how["shot_speed"]
	var reach: float = how.get("shot_reach", .23)
	var base: float = (
		game.world.stand(me) if str(how.get("shot_from", "eye")) == "floor" else me.eye
	)
	var height: float = how.get("shot_height", 0.0)
	var lift: float = how.get("shot_lift", 0.0)
	var aimed: bool = how.get("shot_aimed", true)
	var aim := me.view_angle()
	var slope := (me.pitch + me.sway) / View.base_focal
	var kind := str(how["shot"])
	var s := GameState.Shot.new(
		me.x + cos(aim) * reach,
		me.y + sin(aim) * reach,
		base + height,
		cos(aim) * speed,
		sin(aim) * speed,
		(slope * speed + lift) if aimed else 0.0,
		kind
	)
	s.slot = me.slot
	ghosts.append({"shot": s, "age": 0.0, "hit": false, "tnt": false, "boomed": false})
	made += 1


## A lit stick let go at the press (the "throw" event), `fuse` seconds left.
func throw(game: Game, me: Player, fuse: float) -> void:
	if not enabled or fuse <= 0.0:
		return
	var aim := me.view_angle()
	var x := me.x + cos(aim) * TNT_REACH
	var y := me.y + sin(aim) * TNT_REACH
	if game.world.blocked(x, y, .05):
		x = me.x
		y = me.y
	var s := GameState.Shot.new(
		x,
		y,
		me.eye - .17,
		cos(aim) * TNT_SPEED,
		sin(aim) * TNT_SPEED,
		1.55 + me.pitch * .037,
		"tnt",
		fuse,
		false,
		0,
		5
	)
	s.slot = me.slot
	ghosts.append({"shot": s, "age": 0.0, "hit": false, "tnt": true, "boomed": false})
	made += 1


## The frame: ghosts flown on by `dt`, matched against the copy's new shots
## of ours, the rest put in the picture; the copy's own drawn `ahead` ticks on.
func begin(game: Game, me: Player, ahead: int, dt: float) -> void:
	_added.clear()
	_moved.clear()
	_taken.clear()
	if game == null or me == null:
		return
	if _game == null or _game.get_ref() != game:
		forget()
		_game = weakref(game)
	for b: Dictionary in shown_blasts.duplicate():
		var b_age: float = b["age"]
		b["age"] = b_age + dt
		if b_age + dt > BLAST_WAIT:
			shown_blasts.erase(b)
	var live := {}
	for i in game.shots.size():
		var s: GameState.Shot = game.shots[i]
		if s.enemy or s.slot != me.slot or s.uid <= 0:
			continue
		live[s.uid] = true
		if not _seen.has(s.uid):
			_seen[s.uid] = true
			_match(s)
		if _hidden.has(s.uid):
			_taken.append([i, s])
			continue
		if not enabled or s.resting or Shots.rolls(s.kind) or s.kind == "tnt":
			continue
		_moved.append([s, s.x, s.y, s.z])
		var struck := _fly(game, s, mini(ahead, MOST_AHEAD) * NetSync.STEP)
		if struck == null:
			continue
		if _explodes(s.kind):
			_boom(game, s.kind, s.x, s.y, s.z)
			_hidden[s.uid] = true
			_taken.append([i, s])
		elif not (struck is LevelData) and not _marked.has(s.uid):
			_marked[s.uid] = true
			_mark(game)
	for uid: int in _seen.keys():
		if not live.has(uid):
			_seen.erase(uid)
			_hidden.erase(uid)
			_marked.erase(uid)
	for g: Dictionary in ghosts.duplicate():
		_ghost(game, g, dt)
	for k in range(_taken.size() - 1, -1, -1):
		var row: Array = _taken[k]
		var at: int = row[0]
		game.shots.remove_at(at)


## Ghosts out of the picture, the copy's shots back where it has them.
func end(game: Game) -> void:
	if game != null:
		for s: GameState.Shot in _added:
			game.shots.erase(s)
		for row: Array in _taken:
			var at: int = row[0]
			var s: GameState.Shot = row[1]
			game.shots.insert(at, s)
	_added.clear()
	_taken.clear()
	for row: Array in _moved:
		var s: GameState.Shot = row[0]
		s.x = row[1]
		s.y = row[2]
		s.z = row[3]
	_moved.clear()


func forget() -> void:
	ghosts.clear()
	shown_blasts.clear()
	_seen.clear()
	_hidden.clear()
	_marked.clear()
	_added.clear()
	_moved.clear()
	_taken.clear()
	_game = null


## Asked by the copy's explode() for one of ours: true when we showed that
## blast already (near where it goes off), so its looks are not shown again.
func blast_shown(shot: GameState.Shot) -> bool:
	for b: Dictionary in shown_blasts:
		var at: Vector3 = b["at"]
		var used: bool = b["used"]
		var kind: String = b["kind"]
		if (
			not used
			and kind == shot.kind
			and Vector2(at.x - shot.x, at.y - shot.y).length() < BLAST_NEAR
		):
			b["used"] = true
			return true
	return false


## One ghost's frame: flown or tumbled on, landed, timed out, or drawn.
func _ghost(game: Game, g: Dictionary, dt: float) -> void:
	var age: float = g["age"]
	age += dt
	g["age"] = age
	var s: GameState.Shot = g["shot"]
	var tnt: bool = g["tnt"]
	var uid: int = g.get("uid", -1)
	if age > WAIT and uid < 0:
		ghosts.erase(g)  # never matched: the host did not throw it
		return
	if tnt:
		var gone: bool = g["boomed"]
		if gone:
			return  # gone up: kept till the copy's stick is named, to hide it
		s.life -= dt
		if s.life <= 0.0:
			_boom(game, "tnt", s.x, s.y, s.z)
			g["boomed"] = true
			if uid >= 0:
				ghosts.erase(g)
			return
		if not s.resting:
			var before := Vector2(s.x, s.y)
			if Tumble.step(game.world, s, Tumble.shot_feel("tnt"), dt) & Tumble.RESTED:
				s.resting = true
			s.travelled += before.distance_to(Vector2(s.x, s.y))
		game.shots.append(s)
		_added.append(s)
		return
	var hit: bool = g["hit"]
	if not hit:
		var struck := _fly(game, s, dt)
		if struck != null:
			hit = true
			g["hit"] = true
			if _explodes(s.kind):
				_boom(game, s.kind, s.x, s.y, s.z)
				g["boomed"] = true
			elif not (struck is LevelData):
				_mark(game)
				g["marked"] = true
	if not hit:
		game.shots.append(s)
		_added.append(s)


## The copy fired one of ours: the oldest ghost of its kind is it now.
func _match(s: GameState.Shot) -> void:
	for g: Dictionary in ghosts:
		var ghost: GameState.Shot = g["shot"]
		var named: int = g.get("uid", -1)
		var tnt: bool = g["tnt"]
		var gone: bool = g["boomed"]
		var marked: bool = g.get("marked", false)
		if ghost.kind != s.kind or named >= 0:
			continue
		matched += 1
		if tnt:
			_hidden[s.uid] = true  # the ghost is the stick drawn
			if gone:
				ghosts.erase(g)
			else:
				g["uid"] = s.uid
			return
		ghosts.erase(g)
		if gone:
			_hidden[s.uid] = true  # blown up on our screen already
		if marked:
			_marked[s.uid] = true
		return


static func _explodes(kind: String) -> bool:
	return Shots.explodes(kind) and not TacticalUtility.KINDS.has(kind)


## A blast's looks where ours went off, now (game_combat.gd explode's looks:
## none of its play): its sounds, flash, shake and duck, the blast drawn, its
## specks off our own dice, and the looks features' answers to it.
func _boom(game: Game, kind: String, x: float, y: float, z: float) -> void:
	if not blasts:
		return
	z = maxf(.07, z)
	var spec := Shots.blast(kind)
	var energy: bool = spec["energy"]
	if spec.has("also_sound"):
		game.sound_at(str(spec["also_sound"]), x, y, .9)
	var flash: float = spec["flash"]
	game.blast_flash = maxf(game.blast_flash, flash)
	var ear := game.local_player
	var near := Vector2(ear.x - x, ear.y - y).length()
	game.shake = minf(1.0, game.shake + maxf(0.0, 1.0 - near / 9.0) * (.45 if energy else .9))
	var duck_by: float = spec["duck"]
	game.duck = maxf(game.duck, duck_by)
	game.blasts.append(GameState.Blast.new(x, y, z, "energy" if energy else "fire"))
	game.sound_at(str(spec["cue"]), x, y)
	_specks(
		game, x, y, z, "plasma" if energy else "spark", 12 if energy else 23, 2.2 if energy else 3.3
	)
	_specks(game, x, y, z, "dust", 6 if energy else 16, 2.3)
	for id: String in ["debris", "weapon_fx", "gun_fx", "impacts", "rumble"]:
		var f: GameFeature = game.features.get(id)
		if f != null:
			f.call("_exploded", x, y, z, energy)
	var water: GameFeature = game.features.get("water")
	if water != null:
		water.call("_blast", x, y, z, energy)
	shown_blasts.append({"kind": kind, "at": Vector3(x, y, z), "age": 0.0, "used": false})
	boomed += 1


## The crosshair's hit mark (a thrown thing on a body; its tick and the
## blood are the copy's when it plays the hit).
static func _mark(game: Game) -> void:
	if not game.hit_feedback:
		return
	if game.clock >= game.hit_mark_until:
		game.hit_mark_kill = false
		game.hit_mark_head = false
		game.hit_mark_at = game.clock
	game.hit_mark_until = maxf(game.hit_mark_until, game.clock + .12)


## Specks off our own dice (burst()'s sums, never game.rng).
func _specks(
	game: Game, x: float, y: float, z: float, kind: String, count: int, speed: float
) -> void:
	for _i in count:
		var angle := _dice.randf() * TAU
		var v := _dice.randf_range(.24, speed)
		var up := _dice.randf_range(.2, speed * 1.3)
		game.specks.append(
			GameState.Speck.new(
				x, y, z, cos(angle) * v, sin(angle) * v, up, _dice.randf_range(.18, .68), kind
			)
		)


## `s` moved on `seconds` as a thrown thing flies (game_combat.gd move_shot's
## line and fall, no bounce, no wind). Null while it flies free; where it
## met something, what: the level (a wall, the floor) or the Enemy or Player
## it struck (it stops just short). Changes `s` itself: a ghost, or a copy's
## shot put back by end().
static func _fly(game: Game, s: GameState.Shot, seconds: float) -> Object:
	if seconds <= 0.0:
		return null
	var gravity := Shots.gravity(s.kind)
	var w: LevelData = game.world
	var distance := sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz) * seconds
	var steps := maxi(1, int(ceilf(distance / AHEAD_STEP)))
	var dt := seconds / steps
	var vz := s.vz
	var met: Object = null
	for _i in steps:
		var x := s.x + s.vx * dt
		var y := s.y + s.vy * dt
		var z := s.z + vz * dt
		vz -= dt * gravity
		if w.blocked(x, y, .045, z) or z < w.floor_under(x, y, s.z) + .045:
			met = w
			break
		var body := _body_at(game, x, y, z, s.slot)
		if body != null:
			met = body
			break
		if s.uid <= 0:
			s.travelled += sqrt((x - s.x) * (x - s.x) + (y - s.y) * (y - s.y))
		s.x = x
		s.y = y
		s.z = z
	if s.uid <= 0:
		s.vz = vz  # a ghost keeps falling; a copy's shot keeps the copy's speed
	return met


## A hand or another player our shot at (x, y, z) would strike, as this copy
## draws them (null: none).
static func _body_at(game: Game, x: float, y: float, z: float, slot: int) -> Object:
	var w: LevelData = game.world
	for e: Enemy in game.enemies:
		if not e.alive or e.brain == "bessie":
			continue
		var reach := e.radius + .06
		if absf(e.x - x) > reach or absf(e.y - y) > reach:
			continue
		var feet: float = e.z + w.stand(e)
		if Vector2(e.x - x, e.y - y).length() < reach and feet - .05 < z and z < feet + e.height:
			return e
	if game.players.size() > 1 and Modes.rules(game).bullets_hit_players():
		for q: Player in game.players:
			if q.slot == slot or q.health <= 0 or q.away:
				continue
			var ground: float = w.stand(q)
			if Vector2(q.x - x, q.y - y).length() < .3 and ground < z and z < q.eye + .12:
				return q
	return null
