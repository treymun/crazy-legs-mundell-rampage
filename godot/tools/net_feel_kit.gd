## net_feel.gd's `kit` scene: the things a player causes, each pressed again
## and again and timed from the press to the frame that first shows it, on a
## client of an online co-op Hickston (net_feel's own host). Phases of
## PHASE seconds in turn, set up on the host's game (our player's guns and
## place, a door shut, a hand stood in front):
##
## - scope: the hunting rifle's ALT FIRE, to the scope drawn up;
## - bolt: the dynamite crossbow into a wall, to its blast drawn (the flash);
##   counted as the press to the blast less the bolt's own flight
##   (`flight_ms`, the same both ways, worked out from the shot's speed);
## - door: USE on a shut door, to the door drawn moving;
## - flinch: the .38 at a hand two steps off, to its flinch drawn;
## - tnt: a stick held a moment and let go, to its blast drawn, less the
##   fuse it had left (0 when the blast shows when the fuse is out).
extends RefCounted

const PHASE := 5.0
const PHASES := ["scope", "bolt", "door", "flinch", "tnt"]
## Seconds into a phase the button goes down (the gun is up by then).
const PRESS := 1.2
## Seconds a press waits to be shown before it counts as missed.
const MISS := 1.5
const HOLD := .3
## A tap's length (seconds).
const TAP := .07

var slot := 1
var delays := {}
var missed := {}
var _t := 0.0
var _phase := -1
var _door := -1
var _door_spot := Vector2.ZERO
var _door_face := 0.0
var _wall := 0.0
var _man := -1
var _pressed := -1.0
var _waiting := ""
var _expect := 0.0
var _base := 0.0
var _flash_was := 0.0
var _ready := false


func _init() -> void:
	for k: String in PHASES:
		delays[k] = PackedFloat32Array()
		missed[k] = 0


## The kit and the door found on the host's game, once.
func setup(host: Game) -> void:
	if _ready or slot >= host.players.size():
		return
	_ready = true
	var p: Player = host.players[slot]
	var arms := p.armory
	for gun: int in [Weapons.REVOLVER, Weapons.HUNTER, Weapons.CROSSBOW, Weapons.DYNAMITE]:
		arms.owned[gun] = true
	arms.reserve[Weapons.HUNTER] = 60
	arms.reserve[Weapons.CROSSBOW] = 60
	arms.reserve[Weapons.REVOLVER] = 60
	for d_i in host.world.doors.size():
		var d: LevelData.Door = host.world.doors[d_i]
		var cell := Vector2i(d.x, d.y)
		if (
			d.key != ""
			or d.secret
			or d.blast_only
			or host.world.controlled_doors.has(cell)
			or host.world.crouch_doors.has(cell)
		):
			continue
		for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var at := d.center() + side * 1.1
			if not host.world.blocked(at.x, at.y, .3):
				_door = d_i
				_door_spot = at
				_door_face = atan2(-side.y, -side.x)
				return


## This frame's controls for our player (`me` as our screen draws it, led by
## the prediction), the phase's setup done on `host` when it begins.
func controls(host: Game, copy: Game, me: Player, dt_ms: float, now_ms: float) -> Game.Controls:
	setup(host)
	_t += dt_ms / 1000.0
	var phase := int(_t / PHASE) % PHASES.size()
	var at := fmod(_t, PHASE)
	if phase != _phase:
		_phase = phase
		_waiting = ""
		_begin(host, PHASES[phase])
	var kind: String = PHASES[phase]
	var c := Game.Controls.new()
	if at - dt_ms / 1000.0 <= 0.0:
		# The gun key, as main.gd hands it to the next tick (net_keys.gd).
		TacticalScreens.pending_weapon = {
			"scope": Weapons.HUNTER,
			"bolt": Weapons.CROSSBOW,
			"door": Weapons.REVOLVER,
			"flinch": Weapons.REVOLVER,
			"tnt": Weapons.DYNAMITE,
		}[kind]
	var want := me.angle
	var pitch := 0.0
	match kind:
		"bolt":
			want = _wall
		"tnt":
			want = _wall + PI
			pitch = 8.0
		"door":
			want = _door_face
		"flinch":
			var man := _enemy(copy, _man)
			if man != null:
				var gap := maxf(.5, Vector2(man.x - me.x, man.y - me.y).length())
				want = atan2(man.y - me.y, man.x - me.x)
				pitch = (copy.world.stand(man) + man.height * .55 - me.eye) / gap * View.base_focal
	c.turn = angle_difference(me.angle, want)
	c.look = clampf(pitch - me.pitch, -6.0, 6.0)
	var pressing := at >= PRESS and at - dt_ms / 1000.0 < PRESS
	if kind == "tnt":
		c.fire = at >= PRESS and at < PRESS + HOLD
		if at >= PRESS + HOLD and at - dt_ms / 1000.0 < PRESS + HOLD:
			_press(kind, now_ms, copy)
			_expect = (me.armory.fuse_time() - HOLD) * 1000.0
	else:
		# Held a moment, as a finger does (a frame between ticks sends nothing).
		var down := at >= PRESS and at < PRESS + TAP
		match kind:
			"scope":
				c.alt_fire = down
			"door":
				if pressing:
					TacticalScreens.pending_use = true  # USE goes once (net_keys.gd)
			_:
				c.fire = down
	if pressing and kind != "tnt":
		_press(kind, now_ms, copy)
		if kind == "bolt":
			var how: Dictionary = Weapons.FIRING[Weapons.CROSSBOW]
			var speed: float = how["shot_speed"]
			_expect = _wall_gap(copy, me, _wall) / speed * 1000.0
	return c


## The frame as drawn: whatever is awaited shown yet?
func observe(copy: Game, me: Player, now_ms: float) -> void:
	var flash := copy.blast_flash
	var rose := flash > _flash_was + .05
	_flash_was = flash
	if _waiting == "":
		return
	var shown := false
	match _waiting:
		"scope":
			shown = me.scoped
		"bolt", "tnt":
			shown = rose
		"door":
			if _door >= 0:
				var d: LevelData.Door = copy.world.doors[_door]
				shown = absf(d.progress - _base) > .005
		"flinch":
			var man := _enemy(copy, _man)
			shown = man != null and man.hit_flash > 0.0
	var waited := now_ms - _pressed
	if shown:
		var list: PackedFloat32Array = delays[_waiting]
		list.append(maxf(0.0, waited - _expect))
		delays[_waiting] = list
		_waiting = ""
	elif waited > MISS * 1000.0 + _expect:
		missed[_waiting] = int(missed[_waiting]) + 1
		_waiting = ""


func _press(kind: String, now_ms: float, copy: Game) -> void:
	_pressed = now_ms
	_waiting = kind
	_expect = 0.0
	if kind == "door" and _door >= 0:
		var d: LevelData.Door = copy.world.doors[_door]
		_base = d.progress


## A phase's setup on the host's game (carried to every copy).
func _begin(host: Game, kind: String) -> void:
	var p: Player = host.players[slot]
	p.scoped = false
	p.armory.loaded[Weapons.HUNTER] = Weapons.CAPACITY[Weapons.HUNTER]
	p.armory.loaded[Weapons.REVOLVER] = Weapons.CAPACITY[Weapons.REVOLVER]
	p.health = 100
	match kind:
		"bolt", "tnt":
			_wall = _wall_dir(host, p)
		"door":
			if _door >= 0:
				p.x = _door_spot.x
				p.y = _door_spot.y
				p.vx = 0.0
				p.vy = 0.0
				host.toggle_door(host.world.doors[_door], false)
				host.world.doors[_door].progress = 0.0
		"flinch":
			var spot := Vector2(p.x, p.y) + Vector2(cos(p.angle), sin(p.angle)) * 2.2
			for k in 8:
				var a := p.angle + k * TAU / 8.0
				spot = Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * 2.2
				if not host.world.blocked(spot.x, spot.y, .4):
					break
			_man = -1
			for e: Enemy in host.enemies:
				if e.alive and e.hostile and e.hp > 40.0 and e.brain != "bessie":
					e.x = spot.x
					e.y = spot.y
					e.dormant = false
					_man = e.uid
					break


static func _enemy(g: Game, uid: int) -> Enemy:
	for e: Enemy in g.enemies:
		if e.uid == uid:
			return e
	return null


## The direction from `p` with the nearest wall 2 to 6 cells off.
static func _wall_dir(g: Game, p: Player) -> float:
	for k in 32:
		var angle := k * TAU / 32.0
		var gap := _wall_gap(g, p, angle)
		if gap >= 2.0 and gap <= 6.0:
			return angle
	return 0.0


static func _wall_gap(g: Game, p: Player, angle: float) -> float:
	for step in range(1, 120):
		var d := step * .1
		if g.world.blocked(p.x + cos(angle) * d, p.y + sin(angle) * d, .05):
			return d
	return 12.0
