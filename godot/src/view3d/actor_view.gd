## One enemy or boss in the 3D view: the root of its scene
## (scenes/actors/<kind>.tscn, made by tools/art/build_actor_scenes.gd: this
## script over the kind's rigged model from assets3d/actors). It stands where
## the enemy's sprite stands, turned to the enemy's heading, in the pose the
## sprite would show (idle, a walk beat, aim, wind-up, fire, pain, recover,
## fidget, a step of its fall, down) and look (plain, hurt, a boss's phase),
## the walk and the fall moving smoothly between their frames, and leaves off
## what the body lost. Anything added under the model in the scene (a lamp, a
## glow) moves with it.
class_name ActorView
extends Node3D

const HEADINGS: Array[String] = ["quarter_", "side_", "away_", "back_"]
## How far a model shows (its parts' visibility_range_end, cells from the
## camera to its middle): the game lists bodies to 54 cells ahead.
const REACH := 32.0

## A body at rest is drawn this much of its height: its cel was a flat
## picture a quarter of the body's height, and the model lying in full, its
## belly and boots up, read as a heap.
const FLAT := .5
## Steps a ragdoll first seen long dead takes at once (it starts on the floor
## lying on its back, RagdollRig.lying_points), after which it lies still: no
## hitch, no stir.
const SETTLE := 10
## The model eases from the pose it was last shown in onto its ragdoll over
## HANDOVER seconds of its death (no pop where the animation lets go).
const HANDOVER := .12
## A boss's scripted fall (its set piece, boss_ending.gd's camera on it)
## hands over to its ragdoll this far through (pass 13): over its balance and
## going fast, it lands and settles as a body would, from the pose drawn and
## every part going on at the speed it was (nothing pops, nothing slides);
## that fall is not flattened. Not a boss whose body at rest is a cel of its
## own (the truck, the boat, Maw: fit.json "down_cel").
const BOSS_HANDOVER := .6
## The fastest a part goes on at the hand-over (map units a second).
const HANDOVER_FAST := 8.0
## How far its body may lie from the boss's spot (its scripted fall carries
## it a cell and more back; pulled to the spot it slid back across the floor).
const BOSS_SLACK := 3.0
## A boss's model eases from its scripted fall's pose onto its ragdoll over
## this long from the hand-over.
const BOSS_EASE := .22

## The model's kind (actors.json, actor3d_<kind> looks).
@export var kind := ""

## Knocked down with a gun in hand, how far ahead of the chest the gun hand
## holds it (shoulder widths).
const HELD_THRUST := 1.3

var models: ActorModels
## The dead body's ragdoll (null while alive or with a scripted fall); the
## layer keeps it while the body is out of sight.
var doll: Ragdoll
## A living body's hit reaction (pass 15, src/live_body.gd: its limbs as the
## rig's physics with muscles toward the pose drawn; null: the animation alone
## poses it), whether ActorLayer3D's budget lets it run one this frame, the
## hit last taken (Enemy.struck_at) and its clock.
var live: LiveBody
var live_ok := false
var _live_hit := -1.0
var _live_clock := 0.0
var _rig: RagdollRig
## Each held thing's bone and the hand bone it is held in (actors.json
## "rides": the Meshy models' guns), pairs: a blend keeps the thing in the
## hand (_keep_in_hand).
var _held_pairs := PackedInt32Array()
## A held thing's tail swung by a spring (actors.json "flop"; null if none).
var _tail: HeldTail
var _doll_clock := 0.0
## Where the living body was last drawn and when (map), and how fast it was
## going (smoothed): a body killed on the run falls on with it.
var _was_at := Vector3.INF
var _was_clock := 0.0
var _going := Vector3.ZERO
## A boss's scripted fall's points last drawn and the ones before (map), and
## the time between (its parts' speeds at the hand-over).
var _fall_now := PackedVector3Array()
var _fall_was := PackedVector3Array()
var _fall_at := -1.0
var _fall_dt := 0.0
## The bones' poses the ragdoll took over from (_capture), eased off over
## HANDOVER (empty: done).
var _hand_from: Array = []
## When and over how long it eases (HANDOVER from its death; a boss's from
## its hand-over).
var _hand_at := 0.0
var _hand_for := HANDOVER
## The ragdoll's step count and transform the parts were last posed for.
var _posed := -1
var _posed_dead := false
## Whether this model has been posed by its action (its parts are a real pose).
var _shown_alive := false
var _player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _skeletons: Array[Skeleton3D] = []
## The action time the parts were last posed at (NAN: posed otherwise, by
## the ragdoll), and the numbers last handed to the parts' shader: most
## bodies hold a frame for many draws, and each seek or shader number costs.
var _seeked := NAN
## A fallen boss's turn toward open floor, and the fall it was found for.
var _twist := 0.0
var _twist_for := -1.0
## kind -> where its body lies at the end of its fall (_lying_middle).
static var _lying := {}
## What _shade last handed the parts (false: nothing yet): kept as fields,
## not an array made and compared every frame (pass 15).
var _shaded := false
var _sh_tone := Color()
var _sh_wash := Color()
var _sh_look := 0
var _sh_down := 0.0
var _sh_tell := 0.0
var _sh_rim := Color()
var _sh_mode := 0
## Its own rim (ActorRim, pass 15): when it came up (-1: none), whether this
## body was shown without one, and the clock the body is shown at.
var rim_since := -1.0
var rim_off_seen := false
var shown_at := 0.0
## stem -> picture -> pose_of's answer (it parses the name each time).
static var _poses: Dictionary = {}
## Bodies past `lod_high` cells from `lod_eye` (map x, y), times their
## height, are posed every other frame (staggered): LOD_HIGH at the old
## focal length, so a body there is 14 of the view's pixels tall or less and
## its limbs move under half a pixel a frame (pass 10; further in HD or with
## a narrower FIELD OF VIEW). With VIEW
## DETAIL LOW (QUALITY LOW, `lod_low`) past LOD_NEAR every other frame and
## past LOD_FAR every third, as a 160-wide picture cannot show the
## difference. A change of action (aim, fire, pain, a fall) is posed at once
## whatever the distance. INF: every body every frame. `draws` counts the
## view's frames (WorldView3D sets all three).
const LOD_HIGH := 16.0
const LOD_NEAR := 10.0
const LOD_FAR := 20.0
static var lod_eye := Vector3.INF
static var lod_high := LOD_HIGH
static var lod_low := false
static var draws := 0
## Looks only (none of it touches play or game.rng): a jump between poses
## that are not neighbours in the action (idle to aim, aim to fire, a hit's
## pain, walking to standing, the fall's start) eases over BLEND seconds
## (BLEND_SNAP into fire and pain, which keep their punch) instead of
## snapping; the walk and the fall already run smoothly between their keys.
## A kind's fit.json "blend" sets its own (the hound's poses are far apart).
const BLEND := .13
const BLEND_SNAP := .06
## A hit rocks the body (rigid, about its feet) for FLINCH seconds by where
## it struck (Enemy.last_zone, last_side): a head shot snaps it back, the body
## rocks and twists, an arm turns the shoulders, a leg buckles it forward;
## sized by the hit, a boss less. Each hit's lean is dealt by dice of its own
## (the body's uid and the hit's time), so no two hits rock it the same way.
const FLINCH := .34
const FLINCH_RISE := .045
## A hit seen later than this (seconds) starts no live body (a body come into
## sight mid-reel), and a live body hands back over LIVE_EASE.
const LIVE_LATE := .15
const LIVE_EASE := .18
## A drunk (Variants.STUMBLE) or a player on shine past SHINE walks as a live
## body (src/active_body.gd) while near (ActorLayer3D's budget).
const SHINE := 62.0
const R_POINTS := RagdollRig.POINTS
## Standing at idle, a body breathes and sways a touch (its own phase).
const BREATH := .012
const SWAY := .011
## A scripted fall (RAGDOLLS off, or a kind with no ragdoll) is mirrored for
## about half the deaths and runs up to FALL_QUICK faster: dice of the death's own.
const FALL_QUICK := .18
## The frame group last sought (group_of): a new group blends.
var _group := ""
var _blend_at := -1.0
var _blend_for := BLEND
## Per skeleton: [positions, rotations, scales] of the pose blended from and to.
var _blend_from: Array = []
var _blend_to: Array = []
## The keys of the frame and look last posed (_keys): a motion's first key
## and a fall's (NAN: not one), the frame's own key and its blend group.
## Worked out when the frame changes, not each draw (each built key names).
var _keys_for := ""
var _keys_look := -1
var _run_at := NAN
var _die_at := NAN
var _key_at := 0.0
var _group_name := ""


## Bind the kind's material and find the model's parts. False when the model
## has no animation (it cannot pose).
func setup(p_models: ActorModels) -> bool:
	models = p_models
	var material := models.material(kind)
	for child in find_children("*", "", true, false):
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var own := OwnMaterial.give(mesh, material)
			if kind == "flagman" and mesh.name.begins_with("held_gear0"):
				own.set_shader_parameter("flag_cloth", true)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = REACH
			_meshes.append(mesh)
		elif child is Skeleton3D:
			_skeletons.append(child as Skeleton3D)
		elif child is AnimationPlayer and _player == null:
			_player = child as AnimationPlayer
	var entry: Dictionary = models.kinds.get(kind, {})
	var rides: Dictionary = entry.get("rides", {})
	if not _skeletons.is_empty():
		for held_name: String in rides:
			var seg: int = rides[held_name]
			var g := _skeletons[0].find_bone(held_name)
			var h := _skeletons[0].find_bone("hand_l" if seg == 3 else "hand_r")
			if g >= 0 and h >= 0:
				_held_pairs.append_array([g, h])
		_tail = HeldTail.made(self, _skeletons[0], entry)
	if _player == null or _player.get_animation_list().is_empty():
		return false
	_player.play(_player.get_animation_list()[0])
	_player.pause()
	return true


## Hidden and kept for reuse (ActorLayer3D.SPARE): its ragdoll stays with
## the layer.
func retire() -> void:
	visible = false
	doll = null
	live = null


## Shown again for another body: as one just made, its parts at rest.
func revive() -> void:
	_seeked = NAN
	_group = ""
	_blend_at = -1.0
	_shaded = false
	rim_since = -1.0
	rim_off_seen = false
	_posed = -1
	_posed_dead = false
	_shown_alive = false
	_doll_clock = 0.0
	_was_at = Vector3.INF
	_going = Vector3.ZERO
	_hand_from = []
	_fall_now = PackedVector3Array()
	_fall_was = PackedVector3Array()
	_fall_at = -1.0
	live = null
	_live_hit = -1.0
	if _tail != null:
		_tail.reset()
	for skeleton in _skeletons:
		skeleton.reset_bone_poses()
	visible = true


## Stand where sprite `s` of enemy `e` stands, in its frame and look.
func show_as(s: View.Sprite, e: Enemy, level: LevelData, clock: float) -> void:
	shown_at = clock
	var named := s.image
	if s.pose != "":
		# The model's own frame, with the picture's tint.
		var tilde := s.image.find("~")
		named = s.pose + (s.image.substr(tilde) if tilde >= 0 else "")
	var pose := ActorView.pose_cached(named, Variants.stem(e.kind))
	var frame: String = pose[0]
	var look: int = pose[1]
	var tint: Color = pose[2]
	var z := s.z + (.07 if frame == "down" else 0.0)
	var down := 0.0
	var info: Dictionary = models.kinds[kind]
	var tips: float = info.get("tips", 0.0)
	# A scripted fall's own dice: which way it goes and how quick.
	var death := hash([e.uid, e.died_at]) if not e.alive and e.died_at >= 0.0 else 0
	var span := Enemy.DEATH_TIME * (1.0 - FALL_QUICK * float((death >> 1) & 255) / 255.0)
	var boss := Enemy.BOSS_TITLES.has(e.kind)
	var dead := not e.alive and e.died_at >= 0.0
	var handed := (
		not boss
		or (doll != null and doll.died_at == e.died_at)
		or clock - e.died_at >= span * BOSS_HANDOVER
	)
	if dead and handed and _ragdolls(e):
		down = clampf((clock - e.died_at) / Enemy.DEATH_TIME, 0.0, 1.0)
		# (A beast or a boss lies at play's body's own height: lifted for the
		# lying cel, a small one was carried over its floor, a boss shook.)
		_flop(e, level, clock, Vector3(s.x, s.y, s.z if _rig is BeastRig or boss else z))
		_shade(s, level, look, tint, down)
		return
	doll = null
	if e.alive:
		_track(Vector3(s.x, s.y, z), clock)
		_live_begin(e, clock)
		_drunk_begin(e, clock)
	elif live != null:
		live = null
	var turn := PI * .5 - e.angle + _yaw()
	var size := _size(e)
	var mirror := 1.0
	if (death & 1) == 1 and tips == 0.0 and not info.get("down_cel", false):
		mirror = 1.0 if boss else -1.0
	if frame == "down":
		down = 1.0
	elif frame.begins_with("die_") and not ActorView.held(e):
		down = clampf((clock - e.died_at) / span, 0.0, 1.0)
	var flat_at: float = info.get("flat", FLAT)
	var flat := lerpf(1.0, flat_at, down * down) if not e.alive else 1.0
	var handing := boss and dead and _ragdolls(e)
	if handing:
		flat = 1.0
	if not e.alive and e.died_at >= 0.0 and Enemy.BOSS_TITLES.has(e.kind):
		# A boss twists as it goes down so it lies on open floor.
		var twist := _fall_twist(e, level, size, turn)
		turn += twist * down * down * (3.0 - 2.0 * down)
	transform = Transform3D(
		(
			Basis(Vector3.UP, turn).scaled(Vector3(size, size * flat, size))
			* Basis.from_scale(Vector3(mirror, 1.0, 1.0))
		),
		Vector3(s.x, z, s.y)
	)
	if tips > 0.0 and e.alive and frame != "down" and e.squash < 1.0:
		transform = transform * ActorView.tipped(acos(clampf(e.squash, 0.0, 1.0)), tips)
	elif e.alive and live == null:
		transform = transform * _lively(e, frame, clock)
	var at := _time(frame, look, e, clock, span)
	var group := _group_name
	if live != null and at == _seeked:
		# (The live body posed the bones last frame: the pose it aims at is
		# sought again.)
		_player.seek(at, true)
	if at != _seeked and (is_nan(_seeked) or group != _group or _due(s)):
		var blend := not is_nan(_seeked) and group != _group and _blends()
		if blend:
			_blend_from = _capture()
		_seeked = at
		_player.seek(at, true)
		if blend:
			_blend_to = _capture()
			_blend_at = clock
			var own: float = info.get("blend", BLEND)
			_blend_for = BLEND_SNAP if frame == "fire" or frame == "pain" else own
		else:
			_blend_at = -1.0
	_group = group
	if _blend_at >= 0.0:
		_blend(clock)
	if live != null:
		_live_step(e, level, clock, Vector3(s.x, s.y, s.z))
	elif e.alive and not _hand_from.is_empty():
		# Handed back from a live body: eased onto the animation.
		_ease_over(clampf((clock - _hand_at) / _hand_for, 0.0, 1.0))
	_shown_alive = true
	if _tail != null and e.alive:
		_tail.step(_skeletons[0], clock, e.uid)
	if handing and clock > _fall_at:
		# Where the scripted fall has each part now, for the hand-over.
		_fall_was = _fall_now
		_fall_dt = clock - _fall_at
		_fall_at = clock
		_fall_now = PackedVector3Array()
		for p in _rig.posed_points(_skeletons[0]):
			_fall_now.append(Ragdoll.to_map(transform, p))
	_shade(s, level, look, tint, down)


## A new hit on living `e` (Enemy.struck_at moved on): its live body
## begins (from the pose last drawn) or takes the hit on top, when the
## budget lets it (live_ok) and it has a rig; a live body the budget took
## away hands back to the animation.
func _live_begin(e: Enemy, clock: float) -> void:
	if not live_ok or not View.ragdolls or Enemy.BOSS_TITLES.has(e.kind):
		if live != null:
			_live_end(clock)
		_live_hit = e.struck_at
		return
	if e.struck_at <= _live_hit or e.struck_at < 0.0 or clock - e.struck_at > LIVE_LATE:
		_live_hit = maxf(_live_hit, e.struck_at)
		return
	_live_hit = e.struck_at
	if live == null:
		var info: Dictionary = models.kinds[kind]
		if not info.get("ragdoll", true) or not _shown_alive or _skeletons.is_empty():
			return
		if _rig == null:
			_rig = RagdollRig.of(kind, self, info)
		if not _rig.ok or _rig is BeastRig:
			return
		live = ActiveBody.made_active(_rig, transform, _rig.posed_points(_skeletons[0]))
		live.omega = Stagger.rate(e)
		live.dice.seed = hash([e.uid, e.struck_at, 7])
		_live_clock = clock
		_hand_from = []
	var note := Stagger.of(e)
	var j := Vector2.ZERO
	var hz := .6
	var lat := 0.0
	if not note.is_empty():
		var jx: float = note[Stagger.JX]
		var jy: float = note[Stagger.JY]
		j = Vector2(jx, jy)
		hz = note[Stagger.HZ]
		lat = note[Stagger.LAT]
	else:
		# No push of play's (a gun with no shove): a small one from the side
		# it faced the shot.
		var ahead := Vector2.from_angle(e.angle)
		j = ahead * (.5 if e.last_side == "back" else -.5)
	var zone := e.last_zone if e.last_zone != "" else "body"
	live.hit(j, hz, lat, zone, hash([e.uid, e.struck_at]))


## A drunk's walk (or a player's on shine) as a live body while the budget
## lets it (live_ok): started from the pose last drawn, with no hit.
func _drunk_begin(e: Enemy, clock: float) -> void:
	if live != null or not live_ok or not View.ragdolls or drunk_of(e) <= 0.0:
		return
	if not _shown_alive or _skeletons.is_empty() or Enemy.BOSS_TITLES.has(e.kind):
		return
	var info: Dictionary = models.kinds[kind]
	if not info.get("ragdoll", true):
		return
	if _rig == null:
		_rig = RagdollRig.of(kind, self, info)
	if not _rig.ok or _rig is BeastRig:
		return
	var act := ActiveBody.made_active(_rig, transform, _rig.posed_points(_skeletons[0]))
	act.omega = Stagger.rate(e)
	act.dice.seed = hash([e.uid, 11])
	act.drunk = drunk_of(e)
	live = act
	_live_clock = clock
	_hand_from = []


## How drunk `e` walks: 1 the drunk coot (Variants.STUMBLE), a player's
## stand-in on shine past SHINE by how far (ModeBodies' "shine" note), else 0.
static func drunk_of(e: Enemy) -> float:
	if Variants.STUMBLE.has(e.kind):
		return 1.0
	var shine: float = e.get_note("shine", 0.0)
	if shine <= SHINE:
		return 0.0
	return clampf((shine - SHINE) / (100.0 - SHINE) * 1.5, 0.0, 1.0)


## The live body this frame: the pose sought is its target, play's body and
## word (reeling, down) given, stepped, and the bones posed from it; done,
## it hands back to the animation (eased from its last pose).
func _live_step(e: Enemy, level: LevelData, clock: float, body: Vector3) -> void:
	var model := _rig.posed_points(_skeletons[0])
	var aim := PackedVector3Array()
	aim.resize(R_POINTS)
	for i in R_POINTS:
		aim[i] = Ragdoll.to_map(transform, model[i])
	var dt := clampf(clock - _live_clock, 0.0, .1)
	_live_clock = clock
	var steps := int(roundf(dt / Ragdoll.STEP))
	live.aim(aim, body, steps)
	var down := Stagger.down_of(e)
	var note := Stagger.of(e)
	var pitch: float = 0.0 if note.is_empty() else note[Stagger.PITCH]
	var pitched := pitch > .5
	var act := live as ActiveBody
	if act != null:
		act.stunned = e.stun > .05
		act.grab_point = BodyPlay.holding(e, clock)
		act.drunk = drunk_of(e) if live_ok else 0.0
	live.play_says(not note.is_empty(), 1 if down > 0.0 else -1 if down < 0.0 else 0, pitched)
	# Knocked down holding a gun (RagdollRig.holds), the gun hand thrusts it
	# out in front, clear of the folding legs and belly.
	for side in 2:
		if side < _rig.holds.size() and _rig.holds[side] == 1:
			var hand := RagdollRig.HAND_L if side == 0 else RagdollRig.HAND_R
			if down != 0.0:
				var chest := (aim[RagdollRig.SH_L] + aim[RagdollRig.SH_R]) * .5
				var ahead := (aim[RagdollRig.BELLY] - aim[RagdollRig.BACK]).normalized()
				var reach := aim[RagdollRig.SH_L].distance_to(aim[RagdollRig.SH_R])
				live.aim_override[hand] = chest + ahead * reach * HELD_THRUST
			else:
				live.aim_override[hand] = Vector3.INF
	live.advance(level, dt)
	var back := transform.affine_inverse()
	var alpha := live.alpha()
	var posed := PackedVector3Array()
	posed.resize(R_POINTS)
	for i in R_POINTS:
		var p := live.shown(i, alpha)
		posed[i] = back * Vector3(p.x, p.z, p.y)
	for skeleton in _skeletons:
		_rig.pose(skeleton, posed, false)
	if live.done():
		_live_end(clock)


## The live body lets go: the animation takes over, eased from its last pose.
func _live_end(clock: float) -> void:
	live = null
	_seeked = NAN
	_hand_from = _capture()
	_hand_at = clock
	_hand_for = LIVE_EASE


## A body tipped over sideways by `lean` (radians; a cow going over and getting
## up, features/critters.gd: Enemy.squash is the lean's cosine), rolled about
## its long axis (the model's forward, +z) on the hooves on its left, `side`
## out from its middle (+x): she goes over onto the side she lies on `down`.
static func tipped(lean: float, side: float) -> Transform3D:
	var pivot := Vector3(side, 0.0, 0.0)
	var roll := Basis(Vector3(0.0, 0.0, 1.0), -lean)
	return Transform3D(roll, pivot - roll * pivot)


## Whether a body is posed again this frame (lod_eye, lod_low).
func _due(s: View.Sprite) -> bool:
	if lod_eye == Vector3.INF:
		return true
	var d := Vector2(s.x - lod_eye.x, s.y - lod_eye.y).length()
	var every := 1
	if lod_low:
		if d >= LOD_NEAR:
			every = 2 if d < LOD_FAR else 3
	elif d >= lod_high * maxf(1.0, s.height):
		every = 2
	return every == 1 or (ActorView.draws + get_instance_id()) % every == 0


## How far the model is turned about its feet to face its heading (fit.json
## "yaw": the gator's model was built side on for its cels, head along +x
## turned toward the camera; it walked crabwise before pass 13).
func _yaw() -> float:
	var info: Dictionary = models.kinds[kind]
	var yaw: float = info.get("yaw", 0.0)
	return yaw


## The model's size for enemy `e` (its height against the model's canvas).
func _size(e: Enemy) -> float:
	var info: Dictionary = models.kinds[kind]
	var canvas: Array = info.get("canvas", [1.0, e.height])
	var tall: float = canvas[1]
	var fit: float = info.get("scale", 1.0)
	return e.height * e.variant / maxf(.1, tall) * fit


## Whether dead enemy `e` falls as a ragdoll: RAGDOLLS on, a model standing
## on two legs (RagdollRig) or a beast's (BeastRig), not a kind fit.json
## keeps off ("ragdoll": false); a boss from part way through its scripted
## fall (BOSS_HANDOVER), not one whose body at rest is a cel of its own nor
## one fit.json keeps to his scripted fall ("hand_over": false: the Copper
## Baron, on his back his great gut stood up and his bent legs propped him,
## reading as a man squatting; his set fall lays him out flat).
func _ragdolls(e: Enemy) -> bool:
	if not View.ragdolls:
		return false
	var info: Dictionary = models.kinds[kind]
	if not info.get("ragdoll", true):
		return false
	if (
		Enemy.BOSS_TITLES.has(e.kind)
		and (info.get("down_cel", false) or not info.get("hand_over", true))
	):
		return false
	if _rig == null:
		_rig = RagdollRig.of(kind, self, info)
	return _rig.ok


## How fast the living body goes (map units a second, smoothed over a few
## frames), from where it is drawn.
func _track(at: Vector3, clock: float) -> void:
	var dt := clock - _was_clock
	if _was_at != Vector3.INF and dt > 1e-4:
		var v := (at - _was_at) / dt
		if v.length() > 9.0:
			# A jump (put back, a teleport), not a run.
			v = Vector3.ZERO
		_going = _going.lerp(v, minf(1.0, dt * 12.0))
	if dt > 1e-4 or _was_at == Vector3.INF:
		_was_at = at
		_was_clock = clock


## The body as its ragdoll: started from the pose it died in (or lying on its
## back when first seen long dead), going as it went, struck by the kill,
## carried by play's body at `at` (map: x, y and the height it lies at),
## stepped and its parts posed from it, eased from its last pose at first.
func _flop(e: Enemy, level: LevelData, clock: float, at: Vector3) -> void:
	var up := maxf(0.0, at.z - level.floor_under(at.x, at.y, at.z + .05))
	if doll == null or doll.died_at != e.died_at:
		var size := _size(e)
		var turn := PI * .5 - e.angle + _yaw()
		var xf := Transform3D(
			Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(at.x, at.z, at.y)
		)
		var fresh := clock - e.died_at < .5
		# The pose it died in where this model showed it alive (as it was
		# drawn, its flinch and all), else standing.
		var start := _rig.lying()
		var from := xf
		_hand_from = []
		if fresh:
			start = _rig.standing()
			if _shown_alive:
				start = _rig.posed_points(_skeletons[0])
				from = transform
				_hand_from = _capture()
				_hand_at = e.died_at
				_hand_for = HANDOVER
				if Enemy.BOSS_TITLES.has(e.kind):
					_hand_at = clock
					_hand_for = BOSS_EASE
					# Posed under the turn its scripted fall had (its twist to
					# open floor): the pose eased from was the model's under it.
					var ahead := transform.basis.z
					turn = atan2(ahead.x, ahead.z)
		var was_live := live
		live = null
		if _rig is BeastRig:
			doll = BeastDoll.made_beast(_rig as BeastRig, from, start, kind)
		elif fresh and live_ok and not Enemy.BOSS_TITLES.has(e.kind):
			# Near enough (the live budget): he dies, not drops (src/dying_doll.gd).
			doll = DyingDoll.made_dying(_rig, from, start)
		else:
			doll = Ragdoll.made(_rig, from, start)
		doll.died_at = e.died_at
		doll.turn = turn
		doll.follow(at, up, 0.0)
		if fresh:
			var dice := RandomNumberGenerator.new()
			dice.seed = hash([e.kind, e.died_at, e.uid])
			doll.fit()
			if Enemy.BOSS_TITLES.has(e.kind) and _shown_alive:
				# A boss's scripted fall hands over: no blow, every part going
				# on as it went.
				doll.carry_on(_fall_speeds(doll.pos.size()))
				doll.slack = BOSS_SLACK
			else:
				if was_live != null and from == transform:
					# Going on as the live body went, every ball its own way.
					for i in mini(R_POINTS, doll.pos.size()):
						doll.add_speed(i, (was_live.pos[i] - was_live.old[i]) / Ragdoll.STEP)
				elif _shown_alive:
					doll.drift(Vector3(_going.x, _going.y, 0.0))
				doll.knock(e, dice)
				var dying := doll as DyingDoll
				if dying != null:
					dying.begin(e, hash([e.uid, e.died_at, 3]))
		else:
			# Lying already: a few steps fit it to the floor, the rest as it is drawn.
			doll.settle(level, SETTLE, true)
		_doll_clock = clock
		_posed = -1
	var dt := clampf(clock - _doll_clock, 0.0, .1)
	_doll_clock = clock
	var dying_now := doll as DyingDoll
	if dying_now != null and not live_ok:
		# (Out of the budget: the rest of the way a plain ragdoll.)
		dying_now.muscles = false
	doll.follow(at, up, dt)
	doll.advance(level, dt)
	var xf := Transform3D(
		Basis(Vector3.UP, doll.turn).scaled(Vector3(doll.size, doll.size, doll.size)),
		Vector3(at.x, at.z, at.y)
	)
	var dead := clock - e.died_at > .2
	# Drawn part way between its last two steps (smooth when the clock runs
	# slow); posed again only when that changes.
	var alpha := doll.alpha() if doll.awake else 1.0
	var mark := doll.steps * 64 + int(alpha * 63.0)
	var easing := not _hand_from.is_empty()
	if mark == _posed and xf == transform and dead == _posed_dead and not easing:
		return
	transform = xf
	_posed = mark
	_posed_dead = dead
	_seeked = NAN
	var back := xf.affine_inverse()
	var model := PackedVector3Array()
	model.resize(doll.pos.size())
	for i in doll.pos.size():
		var p := doll.shown(i, alpha)
		model[i] = back * Vector3(p.x, p.z, p.y)
	for skeleton in _skeletons:
		_rig.pose(skeleton, model, dead)
	if easing:
		_ease_over(clampf((clock - _hand_at) / _hand_for, 0.0, 1.0))


## Each part's speed in the scripted fall's last drawn step (map units a
## second, at most HANDOVER_FAST), `n` of them (none known: still).
func _fall_speeds(n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(n)
	if _fall_now.size() != n or _fall_was.size() != n or _fall_dt < 1e-4:
		return out
	for i in n:
		out[i] = ((_fall_now[i] - _fall_was[i]) / _fall_dt).limit_length(HANDOVER_FAST)
	return out


## The pose the ragdoll took over from (_hand_from) eased onto the one just
## posed: `k` 0 the old pose, 1 the ragdoll's (then the old one is let go).
func _ease_over(k: float) -> void:
	if k >= 1.0 or _hand_from.size() != _skeletons.size():
		_hand_from = []
		return
	k = k * k * (3.0 - 2.0 * k)
	for i in _skeletons.size():
		var skeleton := _skeletons[i]
		var from: Array = _hand_from[i]
		var at: PackedVector3Array = from[0]
		var turns: Array[Quaternion] = from[1]
		# (The pose eased to, for the held things' place in their hands.)
		var to_at := PackedVector3Array()
		var to_turn: Array[Quaternion] = []
		for b in skeleton.get_bone_count():
			to_at.append(skeleton.get_bone_pose_position(b))
			to_turn.append(skeleton.get_bone_pose_rotation(b))
		for b in mini(skeleton.get_bone_count(), at.size()):
			skeleton.set_bone_pose_position(b, at[b].lerp(skeleton.get_bone_pose_position(b), k))
			skeleton.set_bone_pose_rotation(
				b, turns[b].slerp(skeleton.get_bone_pose_rotation(b), k)
			)
		_keep_in_hand(skeleton, at, turns, to_at, to_turn, k)


## Each held thing put back in its hand: a blend lerps every bone apart, so
## a gun and the hand it is in drifted (through the body) between two keys or
## easing out of a living body. The thing's place in the hand goes from the
## one pose's to the other's by `k` (at 0 the pose blended from exactly, so
## the first draw of a blend does not jump).
func _keep_in_hand(
	skeleton: Skeleton3D,
	from_at: PackedVector3Array,
	from_turn: Array[Quaternion],
	to_at: PackedVector3Array,
	to_turn: Array[Quaternion],
	k: float
) -> void:
	var n := mini(mini(from_at.size(), to_at.size()), mini(from_turn.size(), to_turn.size()))
	for i in range(0, _held_pairs.size(), 2):
		var g := _held_pairs[i]
		var h := _held_pairs[i + 1]
		if g >= n or h >= n:
			continue
		var in_from := (
			Transform3D(Basis(from_turn[h]), from_at[h]).affine_inverse()
			* Transform3D(Basis(from_turn[g]), from_at[g])
		)
		var in_to := (
			Transform3D(Basis(to_turn[h]), to_at[h]).affine_inverse()
			* Transform3D(Basis(to_turn[g]), to_at[g])
		)
		var hand_now := Transform3D(
			Basis(skeleton.get_bone_pose_rotation(h)), skeleton.get_bone_pose_position(h)
		)
		var held := hand_now * in_from.interpolate_with(in_to, k)
		skeleton.set_bone_pose_position(g, held.origin)
		skeleton.set_bone_pose_rotation(g, held.basis.get_rotation_quaternion())


## The model's light, wash, look, how fallen it is (the rim's shade), a
## wind-up's amber (`tell`) and its own rim (ActorRim).
func _shade(s: View.Sprite, level: LevelData, look: int, tint: Color, down: float) -> void:
	var c := level.cell(clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01))
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	var hurt := minf(.46, s.hurt / .18 * .44) if s.hurt > 0.0 else 0.0
	var wash := Color(tint.r, tint.g, tint.b, hurt)
	var tell := 0.0 if hurt > 0.0 else s.tell
	var rim := ActorRim.quieted(ActorRim.of(self, s.who), hurt, s.tell)
	if (
		_shaded
		and tone == _sh_tone
		and wash == _sh_wash
		and look == _sh_look
		and down == _sh_down
		and tell == _sh_tell
		and rim == _sh_rim
		and ActorRim.mode == _sh_mode
	):
		return
	_shaded = true
	_sh_tone = tone
	_sh_wash = wash
	_sh_look = look
	_sh_down = down
	_sh_tell = tell
	_sh_rim = rim
	_sh_mode = ActorRim.mode
	for mesh in _meshes:
		OwnMaterial.put(mesh, "tone", tone)
		OwnMaterial.put(mesh, "wash", wash)
		OwnMaterial.put(mesh, "look", look)
		OwnMaterial.put(mesh, "fallen", down)
		OwnMaterial.put(mesh, "tell", tell)
		ActorRim.dress(mesh, rim, ActorRim.reach(s.who))


## Draw on these render layers only (the mirror's reflection: WorldView3D
## LAYER_REFLECTION, seen by the mirror's camera alone).
func set_layers(bits: int) -> void:
	for mesh in _meshes:
		mesh.layers = bits


## Leave off what the body lost (Gore.lost: [piece, side]): the head, or an
## arm (an arm or a hand thrown); a boot stays on. After each pose (a pose
## sets every bone's scale again).
func lose(lost: Array) -> void:
	if lost.is_empty():
		return
	var piece: String = lost[0]
	var want := ""
	if piece == "head":
		want = "head"
	elif piece == "arm" or piece == "hand":
		want = "arm_" + str(lost[1])
	if want == "":
		return
	var info: Dictionary = models.kinds[kind]
	var labels: Dictionary = info.get("labels", {})
	for skeleton in _skeletons:
		for bone: String in labels:
			if labels[bone] == want:
				var i := skeleton.find_bone(bone)
				if i >= 0:
					skeleton.set_bone_pose_scale(i, Vector3(.001, .001, .001))


## Leave off the gear the boss lost (features/boss_gear.gd: a hat, a badge,
## armour plates), each gear's bones shrunk away as a lost limb's are. After
## each pose.
func lose_gear(names: Array) -> void:
	for name: String in names:
		for bone: String in models.gear_bones(kind, name):
			for skeleton in _skeletons:
				var i := skeleton.find_bone(bone)
				if i >= 0:
					skeleton.set_bone_pose_scale(i, Vector3(.001, .001, .001))


## Whether `e` is alive and shown in a step of its fall it never took (a
## hand the hound drags down, features/hound.gd): that step's key, held.
static func held(e: Enemy) -> bool:
	return e.alive and e.died_at < 0.0


## pose_of, kept: the same picture always gives the same answer.
static func pose_cached(image: String, stem: String) -> Array:
	var by_image: Dictionary = _poses.get(stem, {})
	if by_image.is_empty():
		_poses[stem] = by_image
	var known: Variant = by_image.get(image)
	if known == null:
		known = ActorView.pose_of(image, stem)
		by_image[image] = known
	var pose: Array = known
	return pose


## [frame name, look, tint] from a sprite's picture name: `<stem>[_p2|_p3|
## _hurt][_<heading>]_<frame>[~r.g.b]`.
static func pose_of(image: String, stem: String) -> Array:
	var tint := Color(1, 1, 1)
	var base := image
	var tilde := base.find("~")
	if tilde >= 0:
		var parts := base.substr(tilde + 1).split(".")
		if parts.size() == 3:
			tint = Color(float(parts[0]) / 100.0, float(parts[1]) / 100.0, float(parts[2]) / 100.0)
		base = base.left(tilde)
	var rest := base.substr(stem.length() + 1) if base.begins_with(stem + "_") else base
	var look := 0
	if rest.begins_with("p2_"):
		look = 2
		rest = rest.substr(3)
	elif rest.begins_with("p3_"):
		look = 3
		rest = rest.substr(3)
	elif rest.begins_with("bare_"):
		rest = rest.substr(5)
	if rest.begins_with("hurt_"):
		look = 1
		rest = rest.substr(5)
	for heading: String in HEADINGS:
		if rest.begins_with(heading):
			rest = rest.substr(heading.length())
	if rest.begins_with("down"):
		rest = "down"
	return [rest, look, tint]


## Where in the kind's action this frame is. The walk runs smoothly through
## its four beats (and back to the first, `w4`) on the enemy's gait; a fall
## through its five steps to the body at rest on the time since it died.
func _time(frame: String, look: int, e: Enemy, clock: float, span: float) -> float:
	_keys(frame, look)
	if not is_nan(_run_at):
		# A motion of five keys in a row (the walk w0..w4; the hound's gallop,
		# trot, idle, shake and the rest, scripts/blender/actors_hound.py):
		# its four beats run on the gait, and a body that plays one through
		# once (the hound going down) is handed a gait short of the last key.
		var beat := fposmod(e.gait / (PI * .5), 4.0)
		return _run_at + beat * ActorModels.KEY_TIME
	# A boss's fall ends on its last step, the body lying where it went down:
	# its separate "down" key lies elsewhere, and running on into it slid the
	# body a cell and a half across the floor (pass 10, the boss endings).
	var boss := Enemy.BOSS_TITLES.has(e.kind)
	if not is_nan(_die_at) and not ActorView.held(e):
		var steps := 4.0 if boss else 5.0
		var step := clampf((clock - e.died_at) / span * steps, 0.0, steps)
		return _die_at + step * ActorModels.KEY_TIME
	if boss and frame == "down":
		var lying: Variant = models.key_time(kind, "die_4")
		if lying != null:
			var lying_at: float = lying
			return lying_at
	return _key_at


## The keys _time and the blend need for `frame` in `look`, when it changed.
func _keys(frame: String, look: int) -> void:
	if frame == _keys_for and look == _keys_look:
		return
	_keys_for = frame
	_keys_look = look
	var hurt := "hurt_" if look == 1 else ""
	_group_name = hurt + ActorView.group_of(frame)
	_run_at = NAN
	if ActorView.is_run(frame):
		var first: Variant = models.key_time(kind, hurt + frame[0] + "0")
		var last: Variant = models.key_time(kind, hurt + frame[0] + "4")
		if first != null and last != null:
			_run_at = first
	_die_at = NAN
	if frame.begins_with("die_"):
		var fall: Variant = models.key_time(kind, "die_0")
		if fall != null:
			_die_at = fall
	_key_at = 0.0
	for name: String in [hurt + frame, frame, hurt + "0", "0"]:
		var t: Variant = models.key_time(kind, name)
		if t != null:
			_key_at = t
			return


## Whether a frame is a beat of a motion of five keys (a letter and the
## beat: w0, r2; the hound's t3, k1 and the rest).
static func is_run(frame: String) -> bool:
	return frame.length() == 2 and frame[0] >= "a" and frame[0] <= "z" and frame[1].is_valid_int()


## The group a frame's keys belong to: the walk's beats, a motion's (the
## gallop, the hound's) and the fall's steps are one each (the action runs
## smoothly through them); any other frame is its own.
static func group_of(frame: String) -> String:
	if ActorView.is_run(frame):
		return frame[0]
	if frame.begins_with("die_") or frame == "down":
		return "die"
	return frame


## Whether this kind's poses blend: not the flapping bugs and saucers, whose
## few keys are the flap itself (no walk or fall in their action).
func _blends() -> bool:
	return models.key_time(kind, "die_0") != null or models.key_time(kind, "w0") != null


## Every bone's pose now: per skeleton [positions, rotations, scales].
func _capture() -> Array:
	var out: Array = []
	for skeleton in _skeletons:
		var n := skeleton.get_bone_count()
		var at := PackedVector3Array()
		var turns: Array[Quaternion] = []
		var sizes := PackedVector3Array()
		at.resize(n)
		turns.resize(n)
		sizes.resize(n)
		for b in n:
			at[b] = skeleton.get_bone_pose_position(b)
			turns[b] = skeleton.get_bone_pose_rotation(b)
			sizes[b] = skeleton.get_bone_pose_scale(b)
		out.append([at, turns, sizes])
	return out


## The pose part way from the one blended from to the one sought (eased), or
## the sought one once the blend is done.
func _blend(clock: float) -> void:
	var k := clampf((clock - _blend_at) / _blend_for, 0.0, 1.0)
	if k >= 1.0 or _blend_from.size() != _skeletons.size():
		k = 1.0
		_blend_at = -1.0
	k = k * k * (3.0 - 2.0 * k)
	for i in mini(_skeletons.size(), _blend_to.size()):
		var skeleton := _skeletons[i]
		var to: Array = _blend_to[i]
		var from: Array = _blend_from[i] if i < _blend_from.size() else to
		var at_a: PackedVector3Array = from[0]
		var at_b: PackedVector3Array = to[0]
		var turn_a: Array[Quaternion] = from[1]
		var turn_b: Array[Quaternion] = to[1]
		var size_a: PackedVector3Array = from[2]
		var size_b: PackedVector3Array = to[2]
		for b in mini(skeleton.get_bone_count(), mini(at_a.size(), at_b.size())):
			skeleton.set_bone_pose_position(b, at_a[b].lerp(at_b[b], k))
			skeleton.set_bone_pose_rotation(b, turn_a[b].slerp(turn_b[b], k))
			skeleton.set_bone_pose_scale(b, size_a[b].lerp(size_b[b], k))
		_keep_arm_lengths(skeleton, at_a, at_b, k)
		_keep_in_hand(skeleton, at_a, turn_a, at_b, turn_b, k)


## A flat skeleton's arm blended bone by bone shortens on a big swing (the
## elbow and the wrist each go straight from key to key: a forearm raised
## behind the head blending down to the hip passed through a tenth of its
## length). The elbow and the wrist are put back at the arm's own lengths
## (the two keys' lengths, blended) along where the blend put them.
func _keep_arm_lengths(
	skeleton: Skeleton3D, at_a: PackedVector3Array, at_b: PackedVector3Array, k: float
) -> void:
	for side: String in ["l", "r"]:
		var ua := skeleton.find_bone("upperarm_" + side)
		var fa := skeleton.find_bone("forearm_" + side)
		var hd := skeleton.find_bone("hand_" + side)
		if ua < 0 or fa < 0 or hd < 0 or maxi(ua, maxi(fa, hd)) >= mini(at_a.size(), at_b.size()):
			continue
		var top := skeleton.get_bone_parent(ua)
		if skeleton.get_bone_parent(fa) != top or skeleton.get_bone_parent(hd) != top:
			continue
		var len_u := lerpf(at_a[ua].distance_to(at_a[fa]), at_b[ua].distance_to(at_b[fa]), k)
		var len_f := lerpf(at_a[fa].distance_to(at_a[hd]), at_b[fa].distance_to(at_b[hd]), k)
		var sh := skeleton.get_bone_pose_position(ua)
		var el := skeleton.get_bone_pose_position(fa)
		var wr := skeleton.get_bone_pose_position(hd)
		if (el - sh).length() < 1e-4 or (wr - el).length() < 1e-4:
			continue
		var el2 := sh + (el - sh).normalized() * len_u
		var wr2 := el2 + (wr - el).normalized() * len_f
		skeleton.set_bone_pose_position(fa, el2)
		skeleton.set_bone_pose_position(hd, wr2)


## A living body's looks-only motion over its pose (model space, about its
## feet): a hit's flinch, or breathing and a sway while it stands idle.
func _lively(e: Enemy, frame: String, clock: float) -> Transform3D:
	var since := clock - e.struck_at
	if e.struck_at >= 0.0 and since >= 0.0 and since < FLINCH:
		return ActorView.flinch(e, since)
	if frame == "0":
		var phase := float(e.uid % 97) * .37
		var breath := sin(clock * 2.1 + phase)
		var sway := sin(clock * .83 + phase * 1.7)
		var basis := Basis(Vector3(0, 0, 1), sway * SWAY).scaled(
			Vector3(1.0, 1.0 + breath * BREATH, 1.0)
		)
		return Transform3D(basis, Vector3.ZERO)
	return Transform3D.IDENTITY


## The lean of a hit `since` seconds ago on `e` (model space: +z its front,
## +x its left, about its feet).
static func flinch(e: Enemy, since: float) -> Transform3D:
	var k := since / FLINCH_RISE
	if since > FLINCH_RISE:
		var left := 1.0 - (since - FLINCH_RISE) / (FLINCH - FLINCH_RISE)
		k = left * left
	var dice := hash([e.uid, e.struck_at])
	var d1 := float(dice & 1023) / 1023.0 - .5
	var d2 := float((dice >> 10) & 1023) / 1023.0 - .5
	var d3 := float((dice >> 20) & 1023) / 1023.0
	var boss := .4 if Enemy.BOSS_TITLES.has(e.kind) else 1.0
	var hard := clampf(e.struck_sum / 40.0, .45, 1.0) * boss * k
	var back := .1 + d3 * .06
	var roll := d1 * .06
	var twist := d2 * .2
	var dip := 0.0
	match e.last_zone:
		"head":
			back = .2 + d3 * .08
		"arms":
			back = .05
			twist = signf(d2 + .001) * (.22 + d3 * .1)
			roll = signf(d1 + .001) * .08
		"legs":
			back = -.12 - d3 * .06
			dip = .05
			roll = signf(d1 + .001) * .1
	if e.last_side == "back":
		back = -back
	var basis := (
		Basis(Vector3.UP, twist * hard)
		* Basis(Vector3(1, 0, 0), -back * hard)
		* Basis(Vector3(0, 0, 1), roll * hard)
	)
	return Transform3D(basis, Vector3(0, -dip * hard, 0))


## The middle of the body as drawn (the average of its bones, world space):
## the boss ending frames a fallen boss by it, whichever way it fell
## (boss_ending.gd). Its spot when it has no bones.
func body_middle() -> Vector3:
	var total := Vector3.ZERO
	var n := 0
	for skeleton in _skeletons:
		for i in skeleton.get_bone_count():
			total += skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
			n += 1
	return total / n if n > 0 else global_position


## How far a fallen boss turns as it goes down so the body lies on open floor,
## not through a wall, a deck or its own throne (Maw lay through her
## alcove's wall): its lying middle (measured once a kind) tried where it
## falls, then turned a quarter either way, then a half. Looks only, the same
## every time for the same fall.
func _fall_twist(e: Enemy, level: LevelData, size: float, turn: float) -> float:
	if _twist_for == e.died_at:
		return _twist
	_twist_for = e.died_at
	_twist = 0.0
	var lying := _lying_middle() * size
	if lying.length() < .2:
		return _twist
	var floor_z: float = level.stand(e)
	for extra: float in [0.0, PI * .5, -PI * .5, PI]:
		var off := Basis(Vector3.UP, turn + extra) * lying
		var open := true
		for k: float in [.5, 1.0, 1.45]:
			if level.blocked(e.x + off.x * k, e.y + off.z * k, .2, floor_z + .35):
				open = false
				break
		if open:
			_twist = extra
			break
	return _twist


## Where this kind's body lies at the end of its fall (its bones' middle on
## the last fall step), from its feet, unscaled: measured once a kind.
func _lying_middle() -> Vector3:
	if _lying.has(kind):
		var known: Vector3 = _lying[kind]
		return known
	var out := Vector3.ZERO
	var key: Variant = models.key_time(kind, "die_4")
	if key != null and _player != null and not _skeletons.is_empty() and is_inside_tree():
		var at: float = key
		_player.seek(at, true)
		var back := global_transform.affine_inverse()
		var n := 0
		for skeleton in _skeletons:
			for i in skeleton.get_bone_count():
				out += back * (skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
				n += 1
		out = out / maxf(1.0, n)
		out.y = 0.0
		_seeked = NAN  # posed again from its own time this frame
	_lying[kind] = out
	return out
