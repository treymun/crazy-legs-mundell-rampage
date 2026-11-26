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
##   fuse it had left (0 when the blast shows when the fuse is out);
## - kill (pass 13): the .38 at a hand two steps off, low on health and held
##   by a stun, to it drawn dead (net_kill_looks.gd);
## - reel: the same at a hand free to walk (no sure kill: its flinch held),
##   to it drawn dead;
## - finish: USE on a dazed hand in reach, to it drawn down at the blow (less
##   the move's own wind before the blow lands);
## - break: the .38 at a crate two and a half steps off, to it drawn broken.
## The pass 13 phases press later (PRESS_LATE): the copy is put back on the
## host's changes by its check, a part at a time, within about a second.
extends RefCounted

const PHASE := 5.0
const PHASES := ["scope", "bolt", "door", "flinch", "tnt", "kill", "reel", "finish", "break"]
const LATE := ["kill", "reel", "finish", "break"]
const PRESS_LATE := 2.2
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
## The crate the break phase shoots (its index), and those used.
var _piece := -1
var _broken := {}


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
			or d.bar_side != 0
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
	var press_at := PRESS_LATE if LATE.has(kind) else PRESS
	var c := Game.Controls.new()
	if at - dt_ms / 1000.0 <= 0.0:
		# The gun key, as main.gd hands it to the next tick (net_keys.gd).
		TacticalScreens.pending_weapon = {
			"scope": Weapons.HUNTER,
			"bolt": Weapons.CROSSBOW,
			"door": Weapons.REVOLVER,
			"flinch": Weapons.REVOLVER,
			"tnt": Weapons.DYNAMITE,
			"kill": Weapons.REVOLVER,
			"reel": Weapons.REVOLVER,
			"finish": Weapons.REVOLVER,
			"break": Weapons.REVOLVER,
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
		"break":
			if _piece >= 0:
				var bk: Object = copy.features.get("breakables")
				var list: Array = bk.get("pieces")
				var p: Object = list[_piece]
				var px: float = p.get("x")
				var py: float = p.get("y")
				var gap0 := maxf(.5, Vector2(px - me.x, py - me.y).length())
				want = atan2(py - me.y, px - me.x)
				var foot: float = copy.world.stand(p) + float(p.get("z"))
				var tall: float = p.get("height")
				pitch = (foot + tall * .5 - me.eye) / gap0 * View.base_focal
		"flinch", "kill", "reel", "finish":
			var man := _enemy(copy, _man)
			if man != null:
				var gap := maxf(.5, Vector2(man.x - me.x, man.y - me.y).length())
				want = atan2(man.y - me.y, man.x - me.x)
				pitch = (copy.world.stand(man) + man.height * .55 - me.eye) / gap * View.base_focal
	c.turn = angle_difference(me.angle, want)
	c.look = clampf(pitch - me.pitch, -6.0, 6.0)
	var pressing := at >= press_at and at - dt_ms / 1000.0 < press_at
	if kind == "tnt":
		c.fire = at >= PRESS and at < PRESS + HOLD
		if at >= PRESS + HOLD and at - dt_ms / 1000.0 < PRESS + HOLD:
			_press(kind, now_ms, copy)
			_expect = (me.armory.fuse_time() - HOLD) * 1000.0
	else:
		# Held a moment, as a finger does (a frame between ticks sends nothing).
		var down := at >= press_at and at < press_at + TAP
		match kind:
			"scope":
				c.alt_fire = down
			"door", "finish":
				if pressing:
					TacticalScreens.pending_use = true  # USE goes once (net_keys.gd)
			_:
				c.fire = down
	if pressing and kind != "tnt":
		_press(kind, now_ms, copy)
		if kind == "finish":
			var wind: float = Game.BrawlScript.FINISH["wind"]
			_expect = wind * 1000.0
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
		"kill", "reel", "finish":
			var man := _enemy(copy, _man)
			shown = man != null and not man.alive
		"break":
			if _piece >= 0:
				var bk: Object = copy.features.get("breakables")
				var list: Array = bk.get("pieces")
				var p: Object = list[_piece]
				var spec: Dictionary = p.get("spec")
				var board: Object = p.get("board")
				shown = board != null and str(board.get("image")) == str(spec["broken"])
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
		"break":
			_pick_piece(host, p)
		"flinch", "kill", "reel", "finish":
			var gap := .9 if kind == "finish" else 2.2
			var spot := Vector2(p.x, p.y) + Vector2(cos(p.angle), sin(p.angle)) * gap
			for k in 8:
				var a := p.angle + k * TAU / 8.0
				spot = Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * gap
				if not host.world.blocked(spot.x, spot.y, .4):
					break
			_man = -1
			for e: Enemy in host.enemies:
				if not (e.alive and e.hostile and e.hp > 40.0 and e.brain != "bessie"):
					continue
				if kind != "flinch" and (not HitZones.limbs(e) or HitZones.metal(e)):
					continue
				if kind != "flinch" and (e.kind == "tin_guard" or Variants.DOORS.has(e.kind)):
					continue
				e.x = spot.x
				e.y = spot.y
				e.dormant = false
				_man = e.uid
				if kind != "flinch":
					# Low on health; held still by a stun (but the reel's).
					e.hp = 8.0
					e.stun = 0.0 if kind == "reel" else 4.0
				break
			# Nobody else near to take the shot.
			for e: Enemy in host.enemies:
				if e.uid != _man and e.alive and Vector2(e.x - spot.x, e.y - spot.y).length() < 6.0:
					e.dormant = true


## The break phase's crate: the next one standing whole in nobody's way, our
## player put two and a half steps from it, its health down to a round's.
func _pick_piece(host: Game, p: Player) -> void:
	_piece = -1
	var bk: Object = host.features.get("breakables")
	if bk == null:
		return
	var list: Array = bk.get("pieces")
	for i in list.size():
		var q: Object = list[i]
		var spec: Dictionary = q.get("spec")
		var base: PackedFloat32Array = q.get("base")
		if _broken.has(i) or q.get("broken") or not base.is_empty() or q.get("board") == null:
			continue
		if spec.get("sign", false) or spec.has("blast") or str(spec.get("broken", "")) == "":
			continue
		var qx: float = q.get("x")
		var qy: float = q.get("y")
		for k in 16:
			var at := Vector2(qx, qy) + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * 2.5
			if host.world.blocked(at.x, at.y, .3) or not host.world.visible(at.x, at.y, qx, qy):
				continue
			_piece = i
			_broken[i] = true
			p.x = at.x
			p.y = at.y
			p.vx = 0.0
			p.vy = 0.0
			q.set("hp", 1.0)
			bk.set("net_version", int(bk.get("net_version")) + 1)
			for e: Enemy in host.enemies:
				if e.alive and Vector2(e.x - at.x, e.y - at.y).length() < 8.0:
					e.dormant = true
			return


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
