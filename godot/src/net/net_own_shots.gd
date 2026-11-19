## Our own thrown shots drawn at our own time. A projectile gun's shot (the
## saw blade, the bowling ball, the bottle rocket...) came into a client's
## copy a round trip and the playout after the press, from where our player
## stood back then, behind the drawn one: it showed late, from behind us.
## Now, looks only, the host's game still the only truth:
##
## - at the press (net_shot_predict.gd shows the shot) a ghost of it flies
##   from where our screen shows us, along our aim, with the shot's own
##   speed, lift and fall, until it meets a wall or the floor;
## - once the copy has its own (one of ours it had not seen), the oldest
##   ghost of that kind goes and the copy's shot is drawn as far on as our
##   inputs lead the copy (the ticks it has not played), so it carries on
##   where the ghost was;
## - a ghost the copy never matches (the host refused the shot) goes after
##   WAIT seconds.
##
## Each frame: begin() after the others are blended (net_blend.gd), end()
## after the frame (main.gd net_draw_begin / net_draw_end). A ghost is put in
## game.shots for the frame only (uid 0: nothing carried names it).
class_name NetOwnShots
extends RefCounted

## Off: our shots show when the copy plays them (net_feel `old`).
static var enabled := true
## Seconds a ghost waits for the copy's own shot.
const WAIT := 1.0
## Ticks at most a copy's shot is drawn ahead of it. (Shots that roll or
## rest, dynamite and the like, are drawn where the copy has them: their path
## is not a throw's.)
const MOST_AHEAD := 60
## The flight's steps (cells), as move_shot's.
const AHEAD_STEP := .09

## Ghosts: {"shot", "age", "hit"}.
var ghosts: Array = []
## The copy's own shots already matched, by uid.
var _seen := {}
var _added: Array = []
## [shot, x, y, z] of the copy's shots drawn ahead, to put back.
var _moved: Array = []
var _game: WeakRef = null
## For net_feel.gd: ghosts made, and matched by the copy's own.
var made := 0
var matched := 0


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
	ghosts.append({"shot": s, "age": 0.0, "hit": false})
	made += 1


## The frame: ghosts flown on by `dt`, matched against the copy's new shots
## of ours, the rest put in the picture; the copy's own drawn `ahead` ticks on.
func begin(game: Game, me: Player, ahead: int, dt: float) -> void:
	_added.clear()
	_moved.clear()
	if game == null or me == null:
		return
	if _game == null or _game.get_ref() != game:
		ghosts.clear()
		_seen.clear()
		_game = weakref(game)
	var live := {}
	for s: GameState.Shot in game.shots:
		if s.enemy or s.slot != me.slot or s.uid <= 0:
			continue
		live[s.uid] = true
		if not _seen.has(s.uid):
			_seen[s.uid] = true
			_match(s.kind)
		if enabled and not s.resting and not Shots.rolls(s.kind) and s.kind != "tnt":
			_moved.append([s, s.x, s.y, s.z])
			_fly(game, s, mini(ahead, MOST_AHEAD) * NetSync.STEP)
	for uid: int in _seen.keys():
		if not live.has(uid):
			_seen.erase(uid)
	for g: Dictionary in ghosts.duplicate():
		var age: float = g["age"]
		age += dt
		g["age"] = age
		var s: GameState.Shot = g["shot"]
		if age > WAIT:
			ghosts.erase(g)
			continue
		var hit: bool = g["hit"]
		if not hit and not _fly(game, s, dt):
			hit = true
			g["hit"] = true
		if not hit:
			game.shots.append(s)
			_added.append(s)


## Ghosts out of the picture, the copy's shots back where it has them.
func end(game: Game) -> void:
	if game != null:
		for s: GameState.Shot in _added:
			game.shots.erase(s)
	_added.clear()
	for row: Array in _moved:
		var s: GameState.Shot = row[0]
		s.x = row[1]
		s.y = row[2]
		s.z = row[3]
	_moved.clear()


func forget() -> void:
	ghosts.clear()
	_seen.clear()
	_added.clear()
	_moved.clear()
	_game = null


## The copy fired one of ours of `kind`: the oldest ghost of it goes.
func _match(kind: String) -> void:
	for g: Dictionary in ghosts:
		var s: GameState.Shot = g["shot"]
		if s.kind == kind:
			ghosts.erase(g)
			matched += 1
			return


## `s` moved on `seconds` as a thrown thing flies (game_combat.gd move_shot's
## line and fall, no bounce, no wind); false where it met a wall or the
## floor (it stops there). Changes `s` itself: a ghost, or a copy's shot
## put back by end().
static func _fly(game: Game, s: GameState.Shot, seconds: float) -> bool:
	if seconds <= 0.0:
		return true
	var gravity := Shots.gravity(s.kind)
	var w: LevelData = game.world
	var distance := sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz) * seconds
	var steps := maxi(1, int(ceilf(distance / AHEAD_STEP)))
	var dt := seconds / steps
	var vz := s.vz
	for _i in steps:
		var x := s.x + s.vx * dt
		var y := s.y + s.vy * dt
		var z := s.z + vz * dt
		vz -= dt * gravity
		if w.blocked(x, y, .045, z) or z < w.floor_under(x, y, s.z) + .045:
			return false
		if s.uid <= 0:
			s.travelled += sqrt((x - s.x) * (x - s.x) + (y - s.y) * (y - s.y))
		s.x = x
		s.y = y
		s.z = z
	if s.uid <= 0:
		s.vz = vz  # a ghost keeps falling; a copy's shot keeps the copy's speed
	return true
