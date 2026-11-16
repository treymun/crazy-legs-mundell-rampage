## The gun's weight and the view's jolts, on springs that overshoot a little
## and settle: the gun trails a turn and leans off a strafe (sway), kicks back
## and springs home after a shot (each gun's recoil, retreat, view_rise, settle
## and spring_damp in weapons.cfg), dips when the player lands (the view drops
## with it), and a blow staggers the view away from where it came from and
## shoves the gun; walking, the eye settles a touch as each boot comes down (a
## real drop of the 3D eye, with the old horizon bob). Looks only: no dice,
## never saved, the aim never moves.
##
## VIEW BOB scales the sway and the landing (off: none); SCREEN SHAKE scales
## the blows (off: none). The kick of a shot is the gun's own and always shows.
extends GameFeature

## The springs are stepped no coarser than this.
const STEP := 1.0 / 240.0
## A spring settles (to a fiftieth) in about 4 / (damping x angular speed):
## a gun's `settle` gives its spring's speed.
const SETTLE_K := 1.41
## How far (cells) the eye drops on a full landing and on the heaviest blow.
const LAND_DROP := .05
const HIT_DROP := .035
## How far (cells) the eye settles as a boot comes down at a full walk.
const STEP_DROP := .018
## The heaviest blow's jolt: the view's turn (radians) and tilt (pixels), and
## the gun's shove (pixels).
const HIT_YAW := .045
const HIT_PITCH := 5.0
const HIT_SHOVE := 8.0
## A spring given a push of size A at speed w peaks near A when pushed A * w * this.
const PUSH := 1.5

## The gun's sway and the shove of blows (screen pixels), and their speeds.
var sway := Vector2.ZERO
var sway_v := Vector2.ZERO
var jolt := Vector2.ZERO
var jolt_v := Vector2.ZERO
## The kick, in parts of the gun's recoil, and its speed.
var kick := 0.0
var kick_v := 0.0
## The view: yaw (radians), pitch (pixels), eye drop (cells), and speeds.
var view := Vector3.ZERO
var view_v := Vector3.ZERO
var _age := 1.0
var _gun := -1
var _fall := 0.0
var _blow := 0.0


func id() -> String:
	return "feel"


func attach() -> void:
	game.events.player_hurt.connect(_hurt)
	tick_with(_tick)


func _hurt(amount: float, _cause: String) -> void:
	if not game.acting_local():
		return
	_blow = maxf(_blow, amount)


func _tick(dt: float) -> void:
	if dt <= 0.0:
		return
	var p := game.player
	var arms := game.armory
	var cfg: Dictionary = Weapons.SWAY
	var bob: float = game.bob_scale
	var shake: float = game.shake_scale
	var hz: float = cfg.get("hz", 5.5)
	var w_sway := TAU * hz
	var z_sway: float = cfg.get("damp", .5)
	var gun: int = arms.active
	if gun != _gun:
		_gun = gun
		kick = 0.0
		kick_v = 0.0
	elif arms.shot_age < _age:
		# A shot, a throw or a swing: the gun jumps back and springs home.
		var recoil: float = arms.recoil
		kick = maxf(kick, 0.0) * .5 + recoil
		kick_v = 0.0
	_age = arms.shot_age
	# The sway's aim: behind a turn and away from a strafe, as far as the limit.
	var limit: float = cfg.get("limit", 10.0)
	var side_speed: float = -sin(p.angle) * p.vx + cos(p.angle) * p.vy
	var turn_k: float = cfg.get("turn", 4.0)
	var strafe_k: float = cfg.get("strafe", 1.4)
	var want := Vector2(
		clampf(-game.feel_turn / dt * turn_k - side_speed * strafe_k, -limit, limit) * bob, 0.0
	)
	if game.feel_landed:
		if _fall < -2.0:
			game.sound.play("land_thump", clampf(-_fall / 5.0, .35, .9))
		var hard := clampf(-_fall / 2.7, .4, 1.6) * bob
		var land_k: float = cfg.get("land", 6.0)
		sway_v.y += land_k * hard * w_sway * PUSH
		view_v.z += LAND_DROP * hard * w_sway * PUSH
	_fall = p.vertical_speed
	if _blow > 0.0:
		_staggered(_blow, shake, w_sway)
		_blow = 0.0
	var settle: Variant = Weapons.SETTLE[gun]
	var settle_time: float = settle if settle != null else .2
	var w_kick := TAU * SETTLE_K / maxf(.05, settle_time)
	var firing: Dictionary = Weapons.FIRING[gun]
	var z_kick: float = firing.get("spring_damp", cfg.get("spring_damp", .42))
	var n := maxi(1, ceili(dt / STEP))
	var h := dt / n
	for _k in n:
		sway_v += (-w_sway * w_sway * (sway - want) - 2.0 * z_sway * w_sway * sway_v) * h
		sway += sway_v * h
		jolt_v += (-w_sway * w_sway * jolt - 2.0 * z_sway * w_sway * jolt_v) * h
		jolt += jolt_v * h
		view_v += (-w_sway * w_sway * view - 2.0 * z_sway * w_sway * view_v) * h
		view += view_v * h
		kick_v += (-w_kick * w_kick * kick - 2.0 * z_kick * w_kick * kick_v) * h
		kick += kick_v * h
	var back: Variant = Weapons.RETREAT[gun]
	var rise: Variant = Weapons.VIEW_RISE[gun]
	var back_k: float = back if back != null else 0
	var rise_k: float = rise if rise != null else 0
	p.weapon_lag = sway + jolt + Vector2(kick * back_k, -kick * rise_k)
	game.view_kick = view + Vector3(0.0, 0.0, _plant(p, bob))


## The eye settling a touch as each boot comes down (the steps are at whole
## turns of walk_phase / PI, as the footstep sounds are), sharp at the plant and
## gone mid-stride; nothing in the air, standing still or with VIEW BOB off.
func _plant(p: Player, bob: float) -> float:
	if p.air > 0.0 or p.health <= 0 or bob <= 0.0:
		return 0.0
	var lift := 1.0 - absf(sin(p.walk_phase))
	return lift * lift * p.motion * STEP_DROP * bob


## A blow of `amount`: the view turns and tilts away from where it came from
## (game.damage_feedback's heading, set as the blow landed), the eye sags and
## the gun is shoved the same way.
func _staggered(amount: float, shake: float, w: float) -> void:
	var heavy := clampf(amount / 30.0, .25, 1.0) * shake
	if heavy <= 0.0:
		return
	var turn := PI
	var feedback: Variant = game.damage_feedback
	if feedback != null and feedback[0] != null:
		var from_angle: float = feedback[0]
		turn = fposmod(from_angle - game.player.view_angle() + PI, TAU) - PI
	else:
		# From nowhere in particular (a fall, steam underfoot): a sag, no turn.
		turn = PI * .5 if int(game.clock * 10.0) % 2 else -PI * .5
		heavy *= .5
	view_v.x += -sin(turn) * HIT_YAW * heavy * w * PUSH
	view_v.y += cos(turn) * HIT_PITCH * heavy * w * PUSH
	view_v.z += HIT_DROP * heavy * w * PUSH
	jolt_v.x += -sin(turn) * HIT_SHOVE * heavy * w * PUSH
	jolt_v.y += HIT_SHOVE * .6 * heavy * w * PUSH
