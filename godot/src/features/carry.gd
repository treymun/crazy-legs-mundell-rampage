## Picking things up and throwing them: USE takes up a loose thing the
## crosshair is on (a chair, a cooler, jugs of shine, a propane tank, a crate:
## data/tuning/carry.cfg names them) when there is nothing else to use there;
## the gun goes down and the thing is held up in front of the view. FIRE throws
## it, ALT FIRE (or USE again) sets it down. A thrown thing flies by tumble.gd:
## it tumbles, bounces off walls and floors, lands on decks and counters and
## comes to rest standing where it stopped (it can be taken up again there).
## What it strikes takes its weight in damage and a shove; a breakable
## (breakables.cfg) breaks by its own hp when it lands hard or strikes
## something, so a propane tank thrown into a crowd goes up. The county's
## brutes do it too now and then: one takes up a thing near it, holds it over
## its head a moment and heaves it at whoever it is after (game.rng).
##
## Play, the same everywhere: the things, where they are, who holds them and
## how they fly are this feature's variables (carried in snapshots; every
## machine's view follows `version`, _reconcile()). A breakable piece is the
## breakables feature's (lift(), set_down()); a board that never breaks is
## moved here. Off in the 5v5 and versus modes, the Crossroads, and with LIVE
## PROPS AND FIRE off (game.gd configure()).
extends GameFeature

const Breakables := preload("res://src/features/breakables.gd")
const Water := preload("res://src/features/water.gd")
const PATH := "res://data/tuning/carry.cfg"
const STAND := 0
const HELD := 1
const FLY := 2
const GONE := 3
## How a held thing sits before the eye (cells): how far out, to the right and
## below the eye its middle is, how big its biggest side is drawn (close and
## small reads as held in both hands), and how far it is turned round.
const HELD_OUT := .5
const HELD_SIDE := 0.0
const HELD_DROP := .2
const HELD_SIZE := .42
const HELD_TURN := 2.0


## Something a hand can take up, where it stands or flies.
class Thing:
	extends Tumble.Body
	## Its whole picture (carry.cfg's section), the board that shows it
	## standing (a town prop), or the breakable piece it is (-1: none), or its
	## sprite in game.props (-1: none).
	var image := ""
	var board: LevelData.Billboard = null
	var piece := -1
	var prop := -1
	var weight := 1.0
	var height := 1.0
	var state := STAND
	## Taken up at least once: it stands where `x`, `y` and `foot` say.
	var moved := false
	var foot := 0.0
	## Who holds it: a player's slot, or (by_enemy) an enemy's uid.
	var holder := -1
	var by_enemy := false
	## Who threw it: a player's slot (-1: an enemy, `thrower_uid`).
	var thrower := -1
	var thrower_uid := 0
	## What it struck last (an enemy uid, -1 - a player slot, -1000 - a piece),
	## never struck twice running.
	var last_hit := 0
	## Seconds an enemy holds it before the throw; the thrower's grace.
	var timer := 0.0
	## When a player took it up (a throw waits a moment after).
	var taken_at := 0.0
	## Seconds in the air, and the axis it tumbles about.
	var age := 0.0
	var axis_x := 0.0
	var axis_y := 1.0
	## Its own furniture base (a board's), freed when it is taken up.
	var base := PackedFloat32Array()


var things: Array = []
## The things held or flying (indices), so a tick looks at only those.
var active: Array = []
var on := true
## Counts every change of where things stand: each machine puts its view and
## its level in step when it moves (_reconcile).
var version := 0
## Counts every change to the things (and each tick one is held or flies):
## a host's NetTrack looks through NET_GUARDED only when it moved.
var net_version := 0
const NET_GUARDED := ["things", "active"]
var next_brute := 0.0
var _shown_version := -1
var _cfg: ConfigFile
var _specs := {}
var _feels := {}
var _brutes := {}
var _bk: Breakables


func id() -> String:
	return "carry"


func attach() -> void:
	_cfg = Tuning.file(PATH)
	for section: String in _cfg.get_sections():
		if section.begins_with("thing."):
			var spec := {}
			for key: String in _cfg.get_section_keys(section):
				spec[key] = _cfg.get_value(section, key)
			_specs[section.substr(6)] = spec
	for kind: Variant in _num_or("brutes", "kinds", []):
		_brutes[str(kind)] = true
	_bk = game.features.get("breakables")
	if _bk != null:
		_find()
	tick_with(_tick)


func _num(section: String, key: String) -> float:
	var v: float = _cfg.get_value(section, key, 0.0)
	return v


func _num_or(section: String, key: String, fallback: Variant) -> Variant:
	return _cfg.get_value(section, key, fallback)


## A thing's own section of carry.cfg (by its whole picture).
func _spec(image: String) -> Dictionary:
	var spec: Dictionary = _specs.get(image, {})
	return spec


## Whether things may be taken up here and now.
func allowed() -> bool:
	return on and not game.in_hub and not Modes.is_versus(game)


# ------------------------------------------------------------------ finding


## Every breakable piece and every board carry.cfg names that a hand could take
## up: loose, not lit, not a quest's, no taller than `tallest`.
func _find() -> void:
	var tallest := _num("all", "tallest")
	var boards := {}
	for i in _bk.pieces.size():
		var p: Breakables.Piece = _bk.pieces[i]
		if p.board != null:
			boards[p.board] = true
		if not _specs.has(p.image) or p.height > tallest or not _bk.liftable(i):
			continue
		var t := _thing(p.image, p.height)
		t.piece = i
		t.board = p.board
		if p.sprite != null:
			t.prop = game.props.find(p.sprite)
		things.append(t)
	var bases := {}
	for board: LevelData.Billboard in game.world.billboards:
		var base := _bk._base_under(board.x, board.y, board.z)
		if not base.is_empty():
			var had: int = bases.get(str(base), 0)
			bases[str(base)] = had + 1
	for board: LevelData.Billboard in game.world.billboards:
		if boards.has(board) or not _specs.has(board.image) or board.height > tallest:
			continue
		if board.signal_name != "" or board.glow or not is_nan(board.plane):
			continue
		var base := _bk._base_under(board.x, board.y, board.z)
		var on_base: int = bases.get(str(base), 0)
		if not base.is_empty() and (on_base > 1 or _bk._parts_floor(base)):
			continue
		var t := _thing(board.image, board.height)
		t.board = board
		t.base = base
		things.append(t)


func _thing(image: String, tall: float) -> Thing:
	var t := Thing.new()
	t.image = image
	t.height = tall
	t.weight = _spec(image).get("weight", 1.0)
	return t


func _feel(t: Thing) -> Tumble.Feel:
	var key := "%s:%.2f" % [t.image, t.height]
	var feel: Tumble.Feel = _feels.get(key)
	if feel == null:
		feel = Tumble.Feel.new(clampf(t.height * .28, .1, .26), .35, .3, 3.2)
		feel.lift = clampf(t.height * .35, .1, .42)
		feel.climb = .1
		feel.hard = 1.0
		feel.grip = .55
		_feels[key] = feel
	return feel


## Where a standing thing is now (a blast may have pushed a breakable).
func place_of(t: Thing) -> Vector3:
	if t.moved:
		return Vector3(t.x, t.y, t.foot)
	if t.piece >= 0:
		var p: Breakables.Piece = _bk.pieces[t.piece]
		return Vector3(p.x, p.y, game.world.elevation(p.x, p.y) + p.z)
	if t.prop >= 0:
		var s: View.Sprite = game.props[t.prop]
		return Vector3(s.x, s.y, s.z)
	return Vector3(t.board.x, t.board.y, game.world.elevation(t.board.x, t.board.y) + t.board.z)


## Whether a standing thing can be taken up (a breakable not broken).
func takeable(t: Thing) -> bool:
	if t.state != STAND:
		return false
	return t.piece < 0 or _bk.liftable(t.piece)


# --------------------------------------------------------------- the player


## What the player holds (an index into things), or -1.
func held_by(p: Player) -> int:
	for i: int in active:
		var t: Thing = things[i]
		if t.state == HELD and not t.by_enemy and t.holder == p.slot:
			return i
	return -1


## The loose thing the acting player's crosshair is on within reach, or -1.
func target() -> int:
	if not allowed() or things.is_empty():
		return -1
	var p := game.player
	var reach := _num("all", "reach")
	var cone := _num("all", "cone")
	var facing := Vector2.from_angle(p.view_angle())
	var stand: float = game.world.stand(p) + p.air
	var best := -1
	var best_off := INF
	for i in things.size():
		var t: Thing = things[i]
		if t.state != STAND:
			continue
		var at := place_of(t)
		var dx := at.x - p.x
		var dy := at.y - p.y
		if absf(dx) > reach or absf(dy) > reach:
			continue
		var d := sqrt(dx * dx + dy * dy)
		var along := dx * facing.x + dy * facing.y
		if d >= reach or (along <= d * cone and d > .45) or absf(at.z - stand) > 1.0:
			continue
		var off := acos(clampf(along / maxf(d, .001), -1.0, 1.0)) + d * .35
		if off < best_off and takeable(t):
			var mid := at.z + t.height * .5
			if game.world.visible(p.x, p.y, at.x, at.y, p.eye, mid):
				best = i
				best_off = off
	return best


## The USE prompt: what holding a thing lets the player do, or what they could
## take up when nothing else answers USE (`shown`, the game's own).
func prompt(shown: String) -> String:
	if held_by(game.player) >= 0:
		return "FIRE  THROW     ALT  SET DOWN"
	if shown != "" or game.armory.fuse > 0.0:
		return shown
	var i := target()
	if i < 0:
		return shown
	var t: Thing = things[i]
	return "E  PICK UP " + str(_spec(t.image).get("label", "IT"))


## USE: sets down what the player holds, or takes up the thing the crosshair
## is on when nothing else answers USE there. True when it did either.
func use() -> bool:
	var p := game.player
	var held := held_by(p)
	if held >= 0:
		_let_go(held, p, false)
		return true
	if game.armory.fuse > 0.0 or game.use_target() != null or game.portal_target() != null:
		return false
	if game.players.size() > 1 and ModeScreens.revive_prompt(game) != "":
		return false
	var i := target()
	if i < 0:
		return false
	_take(i, p)
	return true


func _take(i: int, p: Player) -> void:
	var t: Thing = things[i]
	var at := place_of(t)
	t.x = at.x
	t.y = at.y
	t.z = at.z + _feel(t).lift
	t.vx = 0.0
	t.vy = 0.0
	t.vz = 0.0
	t.rest = false
	t.state = HELD
	t.holder = p.slot
	t.by_enemy = false
	t.taken_at = game.clock
	t.moved = true
	if not active.has(i):
		active.append(i)
	p.armory.holstered = true
	p.scoped = false
	game.sound_at("bolt_lift", p.x, p.y, .6)
	_changed()


## The player's hands this tick while holding a thing: FIRE throws it, ALT
## FIRE sets it down, the gun stays down. True when they hold one (the gun
## does nothing then).
func hands(p: Player, fire: bool, alt: bool) -> bool:
	var i := held_by(p)
	if i < 0:
		return false
	p.armory.holstered = true
	p.scoped = false
	var t: Thing = things[i]
	if game.clock - t.taken_at < .25:
		return true
	if fire:
		if not _smash(i, p):
			_let_go(i, p, true)
	elif alt:
		_let_go(i, p, false)
	return true


## FIRE with one of the county's hands at arm's length in front: the thing
## is broken over his head instead of thrown ([smash]: a chair, a jug, a
## crate), and he is left reeling, open to a finisher (features/brawl.gd).
## A thing that never breaks drops at his feet. True when it was.
func _smash(i: int, p: Player) -> bool:
	var brawl: Object = game.features.get("brawl")
	if brawl == null:
		return false
	var found: Variant = brawl.call("target", p, _num("smash", "reach"), _num("smash", "cone"))
	if found == null:
		return false
	var e: Enemy = found
	var t: Thing = things[i]
	var aim := p.view_angle()
	var base: float = game.world.stand(e) + e.z
	game.hit_point = Vector3(e.x, e.y, base + e.height * e.variant * .9)
	game.hit_from = Vector2(p.x, p.y)
	e.hurt(
		_num("smash", "hit") + _num("smash", "per_weight") * t.weight,
		game,
		false,
		false,
		null,
		"smashed"
	)
	if e.alive:
		e.stun = maxf(e.stun, _num("smash", "stun"))
		e.windup = 0.0
		brawl.call("daze", e)
	game.sound_at(str(_spec(t.image).get("cue", "impact_wood")), e.x, e.y, 1.0)
	game.sound_at("brawl_punch", e.x, e.y, .8)
	t.x = e.x - cos(aim) * (e.radius + .1)
	t.y = e.y - sin(aim) * (e.radius + .1)
	t.z = base + e.height * .8
	p.armory.holstered = false
	p.armory.switch = .3
	p.armory.cooldown = maxf(p.armory.cooldown, .35)
	if t.piece >= 0 and _bk != null:
		var piece: Breakables.Piece = _bk.pieces[t.piece]
		t.state = GONE
		t.holder = -1
		_bk.strike(t.piece, piece.hp + 1.0, cos(aim), sin(aim))
		_changed()
		return true
	t.vx = cos(aim) * .6
	t.vy = sin(aim) * .6
	t.vz = .4
	_fly(t, p.slot, 0, -sin(aim), cos(aim))
	t.last_hit = e.uid
	_changed()
	return true


## Throw it (or set it down) from in front of the player's eye.
func _let_go(i: int, p: Player, throw: bool) -> void:
	var t: Thing = things[i]
	var aim := p.view_angle()
	var fx := cos(aim)
	var fy := sin(aim)
	var feel := _feel(t)
	var out := .3 + feel.radius
	t.x = p.x + fx * out
	t.y = p.y + fy * out
	t.z = maxf(p.eye - .35, Tumble.floor_at(game.world, t.x, t.y, p.eye) + feel.lift)
	if Tumble.blocks(game.world, t.x, t.y, t.z, feel):
		t.x = p.x
		t.y = p.y
	var speed := _num("all", "drop")
	var lift := .6
	if throw:
		speed = minf(_num("all", "speed_most"), _num("all", "speed") / sqrt(maxf(.2, t.weight)))
		lift = _num("all", "lift") + p.pitch * _num("all", "tilt") * speed / 6.0
	t.vx = fx * speed + p.vx * .5
	t.vy = fy * speed + p.vy * .5
	t.vz = lift
	_fly(t, p.slot, 0, -fy, fx)
	p.armory.holstered = false
	p.armory.switch = .3
	p.armory.cooldown = maxf(p.armory.cooldown, .35)
	game.sound_at("tnt_throw" if throw else "bolt_lift", p.x, p.y, .7 if throw else .45)
	if throw:
		game.disturb(t.x, t.y, 2.5, t.z)
	_changed()


func _fly(t: Thing, slot: int, uid: int, ax: float, ay: float) -> void:
	t.state = FLY
	t.holder = -1
	t.by_enemy = false
	t.thrower = slot
	t.thrower_uid = uid
	t.timer = _num("all", "grace")
	t.last_hit = 0
	t.age = 0.0
	t.rest = false
	var length := Vector2(ax, ay).length()
	t.axis_x = ax / maxf(.001, length)
	t.axis_y = ay / maxf(.001, length)
	var flying := 0
	for k: int in active:
		var other: Thing = things[k]
		flying += 1 if other.state == FLY else 0
	if flying > int(_num("all", "flying_most")):
		for k: int in active:
			var oldest: Thing = things[k]
			if oldest.state == FLY and oldest != t:
				_settle(oldest)
				break


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	if version != _shown_version:
		_reconcile()
	if not allowed():
		return
	if not _brutes.is_empty() and game.clock >= next_brute:
		next_brute = game.clock + _num("brutes", "every")
		_brutes_look()
	if active.is_empty():
		return
	for i: int in active.duplicate():
		var t: Thing = things[i]
		match t.state:
			HELD:
				_hold(t, dt)
			FLY:
				_flight(t, dt)
		if t.state == STAND or t.state == GONE:
			active.erase(i)
	net_version += 1


## Held up: it goes where its holder goes; dropped if they fall.
func _hold(t: Thing, dt: float) -> void:
	if t.by_enemy:
		var e := _enemy(t.holder)
		if e == null or not e.alive:
			t.vx = 0.0
			t.vy = 0.0
			t.vz = 0.0
			_fly(t, -1, t.holder, 1.0, 0.0)
			return
		t.x = e.x
		t.y = e.y
		t.z = game.world.stand(e) + e.height * .82 + _feel(t).lift
		t.timer -= dt
		if t.timer <= 0.0:
			_heave(t, e)
		return
	var p: Player = game.players[t.holder] if t.holder < game.players.size() else null
	if p == null or p.health <= 0:
		t.vx = 0.0
		t.vy = 0.0
		t.vz = 0.0
		_fly(t, -1, 0, 1.0, 0.0)
		if p != null:
			p.armory.holstered = false
		return
	var aim := p.view_angle()
	t.x = p.x + cos(aim) * .35
	t.y = p.y + sin(aim) * .35
	t.z = p.eye - .3


func _flight(t: Thing, dt: float) -> void:
	var feel := _feel(t)
	t.age += dt
	t.timer = maxf(0.0, t.timer - dt)
	var speed := Vector3(t.vx, t.vy, t.vz).length()
	var ax := t.vx
	var ay := t.vy
	var hit := Tumble.step(game.world, t, feel, dt)
	if speed >= _num("all", "hit_speed") and _strike(t, speed, ax, ay):
		return
	if hit & (Tumble.WALL | Tumble.FLOOR):
		game.sound_at(str(_spec(t.image).get("cue", "impact_wood")), t.x, t.y, .55)
		if hit & Tumble.FLOOR:
			# Into water: a splash (looks; the water feature's, if any).
			Water.splash_if(game, t.x, t.y, t.z, clampf(.6 + t.weight * .4, .8, 1.8))
		if _landed_hard(t, speed, ax, ay):
			return
	if hit & Tumble.RESTED:
		_settle(t)


## It struck a body or a breakable on the way: hurt it, shove it, bounce off.
func _strike(t: Thing, speed: float, ax: float, ay: float) -> bool:
	var feel := _feel(t)
	var amount := maxf(_num("all", "hit_least"), _num("all", "hit") * t.weight * speed)
	var push := minf(_num("all", "shove_most"), _num("all", "shove") * t.weight * speed)
	var way := Vector2(ax, ay).normalized()
	var struck := false
	if t.thrower >= 0 or t.thrower_uid == 0:
		for e: Enemy in game.enemies:
			if not e.alive or e.brain == "bessie" or e.uid == t.last_hit:
				continue
			if t.timer > 0.0 and e.uid == t.thrower_uid:
				continue
			if _touches(t, feel, e.x, e.y, e.radius, game.world.stand(e) + e.z, e.height):
				_hurt_enemy(t, e, amount, way * push)
				t.last_hit = e.uid
				struck = true
				break
	if not struck and t.thrower < 0 and t.thrower_uid != 0:
		for p: Player in game.players:
			if p.health <= 0 or t.last_hit == -1 - p.slot:
				continue
			var base: float = game.world.stand(p) + p.air
			if _touches(t, feel, p.x, p.y, .2, base, p.eye - base + .1):
				var harm := amount * _num("brutes", "harm")
				game.damage(harm, [t.x - ax, t.y - ay], "THROWN", p)
				p.vx += way.x * push * 6.0
				p.vy += way.y * push * 6.0
				t.last_hit = -1 - p.slot
				struck = true
				break
	if not struck and _bk != null:
		var j := _bk.touch(t.x, t.y, t.z, feel.radius)
		if j >= 0 and j != t.piece and t.last_hit != -1000 - j:
			_bk.strike(j, amount, way.x, way.y)
			t.last_hit = -1000 - j
			struck = true
	if not struck:
		return false
	game.sound_at(str(_spec(t.image).get("cue", "impact_wood")), t.x, t.y, .8)
	game.sound_at("body_thud", t.x, t.y, .5)
	t.vx = -t.vx * .25
	t.vy = -t.vy * .25
	t.vz = maxf(t.vz, .8)
	return _landed_hard(t, speed, ax, ay)


func _touches(
	t: Thing, feel: Tumble.Feel, x: float, y: float, r: float, base: float, tall: float
) -> bool:
	var reach := r + feel.radius + .05
	if absf(t.x - x) > reach or absf(t.y - y) > reach:
		return false
	if Vector2(t.x - x, t.y - y).length() > reach:
		return false
	return t.z + feel.radius > base and t.z - feel.radius < base + tall


func _hurt_enemy(t: Thing, e: Enemy, amount: float, push: Vector2) -> void:
	var thrower: Player = null
	if t.thrower >= 0 and t.thrower < game.players.size():
		thrower = game.players[t.thrower]
	var by: Enemy = null if thrower != null else _enemy(t.thrower_uid)
	if thrower != null:
		game.focus(thrower)
	e.hurt(amount, game, false, false, by, "thrown")
	if e.alive:
		game.move_actor(e, push.x, push.y, e.radius)
	game.focus(game.local_player)


## A breakable that landed or struck hard enough breaks where it is (an
## explosive goes up a moment later); true when it did.
func _landed_hard(t: Thing, speed: float, ax: float, ay: float) -> bool:
	if t.piece < 0 or speed < _num("all", "land_speed"):
		return false
	var p: Breakables.Piece = _bk.pieces[t.piece]
	var amount := _num("all", "land") * t.weight * speed
	if amount < p.hp:
		p.hp -= amount
		_bk.net_version += 1
		return false
	_settle(t)
	var way := Vector2(ax, ay).normalized()
	_bk.strike(t.piece, p.hp + 1.0, way.x, way.y)
	t.state = GONE
	_changed()
	return true


## At rest: it stands where it stopped, as the level's own thing again.
func _settle(t: Thing) -> void:
	var feel := _feel(t)
	t.state = STAND
	t.holder = -1
	t.by_enemy = false
	t.vx = 0.0
	t.vy = 0.0
	t.vz = 0.0
	t.rest = true
	t.foot = Tumble.floor_at(game.world, t.x, t.y, t.z - feel.lift + .05)
	t.moved = true
	_changed()


func _enemy(uid: int) -> Enemy:
	if uid == 0:
		return null
	for e: Enemy in game.enemies:
		if e.uid == uid:
			return e
	return null


# ------------------------------------------------------------------ brutes


## Each brute that sees whoever it is after may take up a thing near it.
func _brutes_look() -> void:
	var near := _num("brutes", "near")
	var far := _num("brutes", "far")
	var grab := _num("brutes", "grab")
	var heaviest := _num("brutes", "heaviest")
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile or e.dormant or not _brutes.has(e.brain):
			continue
		if e.see_time <= 0.0 or e.windup > 0.0 or _holding(e):
			continue
		var p: Player = e.hunted if e.hunted != null else game.local_player
		if p == null or p.health <= 0:
			continue
		var gap := Vector2(p.x - e.x, p.y - e.y).length()
		if gap < near or gap > far:
			continue
		var pick := -1
		var pick_d := grab
		for i in things.size():
			var t: Thing = things[i]
			if t.weight > heaviest or not takeable(t):
				continue
			var at := place_of(t)
			var d := Vector2(at.x - e.x, at.y - e.y).length()
			if d < pick_d and absf(at.z - game.world.stand(e)) < .5:
				pick = i
				pick_d = d
		if pick < 0 or game.rng.random() >= _num("brutes", "chance"):
			continue
		var t: Thing = things[pick]
		t.state = HELD
		t.by_enemy = true
		t.holder = e.uid
		t.timer = _num("brutes", "hold")
		t.moved = true
		t.rest = false
		e.cooldown = maxf(e.cooldown, t.timer + .4)
		if not active.has(pick):
			active.append(pick)
		game.sound_at("blow_grunt", e.x, e.y, .6)
		_changed()


func _holding(e: Enemy) -> bool:
	for i: int in active:
		var t: Thing = things[i]
		if t.state == HELD and t.by_enemy and t.holder == e.uid:
			return true
	return false


## The brute throws what it holds at whoever it is after, a little off.
func _heave(t: Thing, e: Enemy) -> void:
	var p: Player = e.hunted if e.hunted != null else game.local_player
	var miss := _num("brutes", "miss")
	var to := Vector3(p.x, p.y, p.eye - .4)
	to.x += game.rng.uniform(-miss, miss)
	to.y += game.rng.uniform(-miss, miss)
	var run := Vector2(to.x - t.x, to.y - t.y)
	var d := maxf(.5, run.length())
	var speed := _num("brutes", "speed") / sqrt(maxf(.4, t.weight))
	var flight := d / speed
	t.vx = run.x / d * speed
	t.vy = run.y / d * speed
	t.vz = (to.z - t.z) / flight + .5 * _feel(t).gravity * flight
	_fly(t, -1, e.uid, -t.vy, t.vx)
	e.angle = atan2(run.y, run.x)
	game.sound_at("chum_throw", e.x, e.y, .8)
	_changed()


# ----------------------------------------------------------- level and view


## Something moved: every machine puts its level and view in step.
func _changed() -> void:
	version += 1
	net_version += 1
	_reconcile()


## The level and the view as the things stand: one held or flying shows
## nothing where it stood (and its base is out of the way), one set down
## stands where it came to rest, a broken one is the breakables feature's.
func _reconcile() -> void:
	_shown_version = version
	for t: Thing in things:
		if not t.moved:
			continue
		var away := t.state == HELD or t.state == FLY
		if t.piece >= 0:
			var p: Breakables.Piece = _bk.pieces[t.piece]
			if p.broken:
				continue
			if away:
				if p.x > -32.0 or not p.base.is_empty():
					_bk.lift(t.piece)
				_show(t, "")
			elif t.state == STAND:
				var ground := game.world.elevation(t.x, t.y)
				if absf(p.x - t.x) > .001 or absf(p.y - t.y) > .001:
					_bk.set_down(t.piece, t.x, t.y, t.foot - ground)
				_show(t, t.image)
			continue
		if away or t.state == GONE:
			if not t.base.is_empty():
				_bk._free(t.base)
				t.base = PackedFloat32Array()
			_show(t, "")
		else:
			if t.board != null:
				t.board.x = t.x
				t.board.y = t.y
				t.board.z = t.foot - game.world.elevation(t.x, t.y)
			_show(t, t.image)
	game.fixed_sprites_key = []


func _show(t: Thing, image: String) -> void:
	if t.board != null:
		t.board.image = image
	if t.prop >= 0:
		var s: View.Sprite = game.props[t.prop]
		s.image = image
		if image != "":
			s.x = t.x
			s.y = t.y
			s.z = t.foot


func sprites() -> Array:
	var out: Array = []
	if version != _shown_version:
		_reconcile()
	for i: int in active:
		var t: Thing = things[i]
		if t.state == STAND or t.state == GONE:
			continue
		if t.state == HELD and not t.by_enemy:
			var held := _held_sprite(t)
			if held != null:
				out.append(held)
			continue
		var feel := _feel(t)
		if not game.in_view(t.x, t.y, t.height + .3):
			continue
		var s: View.Sprite = game.pooled(t.x, t.y, t.image, t.height, t.z - feel.lift)
		s.who = t
		s.face = 0.0
		if t.state == FLY:
			var turn := t.age * 7.0 / sqrt(maxf(.3, t.weight))
			s.turn = Basis(Vector3(t.axis_x, t.axis_y, 0.0), turn)
			s.spin = turn
		out.append(s)
	return out


## A thing held up in front of a player: its model (the 3D view's, by `who`)
## small and close, low before the eye, turned with the view so the one
## holding it sees it as its picture shows it; it bobs with the walk.
func _held_sprite(t: Thing) -> View.Sprite:
	if t.holder < 0 or t.holder >= game.players.size():
		return null
	var p: Player = game.players[t.holder]
	var a := p.view_angle()
	var fwd := Vector2.from_angle(a)
	var at := Vector2(p.x, p.y) + fwd * HELD_OUT + Vector2(-fwd.y, fwd.x) * HELD_SIDE
	var lift := minf(1.0, (game.clock - t.taken_at) / .2)
	var bob := sin(p.walk_phase * 2.0) * .012 * minf(1.0, p.motion) * game.bob_scale
	var art: Dictionary = game.art.art(t.image)
	var art_w: float = art["w"]
	var art_h: float = art["h"]
	# Its biggest side, tall or wide, drawn HELD_SIZE across.
	var tall := HELD_SIZE / maxf(1.0, art_w / maxf(1.0, art_h))
	var z := p.eye - HELD_DROP - (1.0 - lift) * .2 + bob - tall * .5
	var s: View.Sprite = game.pooled(at.x, at.y, t.image, tall, z)
	s.who = t
	s.face = 0.0
	# Its front (the model's +Z) back toward the eye, a little round.
	s.turn = Basis(Vector3(0.0, 0.0, 1.0), a + PI * .5 + HELD_TURN)
	return s


# -------------------------------------------------------------------- saves


func save() -> Dictionary:
	var rows: Array = []
	for i in things.size():
		var t: Thing = things[i]
		if not t.moved:
			continue
		var at := Vector3(t.x, t.y, t.foot)
		if t.state == HELD or t.state == FLY:
			at.z = Tumble.floor_at(game.world, t.x, t.y, t.z)
		rows.append(
			[
				i,
				1 if t.state == GONE else 0,
				snappedf(at.x, .01),
				snappedf(at.y, .01),
				snappedf(at.z, .01)
			]
		)
	return {} if rows.is_empty() else {"moved": rows}


func restore(state: Dictionary) -> void:
	for item: Variant in state.get("moved", []):
		if not item is Array:
			continue
		var row: Array = item
		var at: int = row[0]
		if row.size() != 5 or at < 0 or at >= things.size():
			continue
		var t: Thing = things[at]
		var gone: int = row[1]
		t.moved = true
		t.state = GONE if gone == 1 else STAND
		t.x = row[2]
		t.y = row[3]
		t.foot = row[4]
		t.rest = true
	active.clear()
	version += 1
	net_version += 1
	_reconcile()
