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
## A body at rest is drawn this much of its height: its cel was a flat
## picture a quarter of the body's height, and the model lying in full, its
## belly and boots up, read as a heap.
const FLAT := .5
## Steps a ragdoll first seen long dead takes at once (it starts on the floor
## lying on its back, RagdollRig.lying_points), after which it lies still: no
## hitch, no stir.
const SETTLE := 10

## The model's kind (actors.json, actor3d_<kind> looks).
@export var kind := ""

var models: ActorModels
## The dead body's ragdoll (null while alive or with a scripted fall); the
## layer keeps it while the body is out of sight.
var doll: Ragdoll
var _rig: RagdollRig
var _doll_clock := 0.0
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
var _shaded := []
## stem -> picture -> pose_of's answer (it parses the name each time).
static var _poses: Dictionary = {}
## VIEW DETAIL LOW (QUALITY LOW): bodies past LOD_NEAR cells from `lod_eye`
## (map x, y) are posed every other frame, past LOD_FAR every third
## (staggered), as a 160-wide picture cannot show the difference; INF: every
## body every frame. `draws` counts the view's frames (WorldView3D sets both).
const LOD_NEAR := 10.0
const LOD_FAR := 20.0
static var lod_eye := Vector3.INF
static var draws := 0


## Bind the kind's material and find the model's parts. False when the model
## has no animation (it cannot pose).
func setup(p_models: ActorModels) -> bool:
	models = p_models
	var material := models.material(kind)
	for child in find_children("*", "", true, false):
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = 32.0
			_meshes.append(mesh)
		elif child is Skeleton3D:
			_skeletons.append(child as Skeleton3D)
		elif child is AnimationPlayer and _player == null:
			_player = child as AnimationPlayer
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


## Shown again for another body: as one just made, its parts at rest.
func revive() -> void:
	_seeked = NAN
	_shaded = []
	_posed = -1
	_posed_dead = false
	_shown_alive = false
	_doll_clock = 0.0
	for skeleton in _skeletons:
		skeleton.reset_bone_poses()
	visible = true


## Stand where sprite `s` of enemy `e` stands, in its frame and look.
func show_as(s: View.Sprite, e: Enemy, level: LevelData, clock: float) -> void:
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
	if not e.alive and e.died_at >= 0.0 and _ragdolls(e):
		down = clampf((clock - e.died_at) / Enemy.DEATH_TIME, 0.0, 1.0)
		_flop(e, level, clock, Vector3(s.x, s.y, z))
		_shade(s, level, look, tint, down)
		return
	doll = null
	var turn := PI * .5 - e.angle
	var size := _size(e)
	if frame == "down":
		down = 1.0
	elif frame.begins_with("die_"):
		down = clampf((clock - e.died_at) / Enemy.DEATH_TIME, 0.0, 1.0)
	var info: Dictionary = models.kinds[kind]
	var flat_at: float = info.get("flat", FLAT)
	var flat := lerpf(1.0, flat_at, down * down) if not e.alive else 1.0
	transform = Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size * flat, size)), Vector3(s.x, z, s.y)
	)
	var tips: float = info.get("tips", 0.0)
	if tips > 0.0 and e.alive and frame != "down" and e.squash < 1.0:
		transform = transform * ActorView.tipped(acos(clampf(e.squash, 0.0, 1.0)), tips)
	var at := _time(frame, look, e, clock)
	if at != _seeked and (is_nan(_seeked) or _due(s)):
		_seeked = at
		_player.seek(at, true)
	_shown_alive = true
	_shade(s, level, look, tint, down)


## A body tipped over sideways by `lean` (radians; a cow going over and getting
## up, features/critters.gd: Enemy.squash is the lean's cosine), rolled about
## its long axis (the model's forward, +z) on the hooves on its left, `side`
## out from its middle (+x): she goes over onto the side she lies on `down`.
static func tipped(lean: float, side: float) -> Transform3D:
	var pivot := Vector3(side, 0.0, 0.0)
	var roll := Basis(Vector3(0.0, 0.0, 1.0), -lean)
	return Transform3D(roll, pivot - roll * pivot)


## Whether a body is posed again this frame (lod_eye: VIEW DETAIL LOW).
func _due(s: View.Sprite) -> bool:
	if lod_eye == Vector3.INF:
		return true
	var d := Vector2(s.x - lod_eye.x, s.y - lod_eye.y).length()
	if d < LOD_NEAR:
		return true
	var every := 2 if d < LOD_FAR else 3
	return (ActorView.draws + get_instance_id()) % every == 0


## The model's size for enemy `e` (its height against the model's canvas).
func _size(e: Enemy) -> float:
	var info: Dictionary = models.kinds[kind]
	var canvas: Array = info.get("canvas", [1.0, e.height])
	var tall: float = canvas[1]
	var fit: float = info.get("scale", 1.0)
	return e.height * e.variant / maxf(.1, tall) * fit


## Whether dead enemy `e` falls as a ragdoll: RAGDOLLS on, a model standing
## on two legs (RagdollRig), not a boss (its fall is a set piece of its own)
## and not a kind fit.json keeps off ("ragdoll": false).
func _ragdolls(e: Enemy) -> bool:
	if not View.ragdolls or Enemy.BOSS_TITLES.has(e.kind):
		return false
	var info: Dictionary = models.kinds[kind]
	if not info.get("ragdoll", true):
		return false
	if _rig == null:
		_rig = RagdollRig.of(kind, self, info)
	return _rig.ok


## The body as its ragdoll: started from the pose it died in (or lying on its
## back when first seen long dead), thrown by the kill, carried
## by play's body at `at` (map: x, y and the height it lies at), stepped and
## its parts posed from it.
func _flop(e: Enemy, level: LevelData, clock: float, at: Vector3) -> void:
	var up := maxf(0.0, at.z - level.floor_under(at.x, at.y, at.z + .05))
	if doll == null or doll.died_at != e.died_at:
		var size := _size(e)
		var turn := PI * .5 - e.angle
		var xf := Transform3D(
			Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(at.x, at.z, at.y)
		)
		var fresh := clock - e.died_at < .5
		# The pose it died in when this model showed it alive, else standing.
		var start := _rig.lying_points
		if fresh:
			start = _rig.posed_points(_skeletons[0]) if _shown_alive else _rig.points
		doll = Ragdoll.made(_rig, xf, start)
		doll.died_at = e.died_at
		doll.turn = turn
		doll.follow(at, up, 0.0)
		if fresh:
			var dice := RandomNumberGenerator.new()
			dice.seed = hash([e.kind, e.died_at, e.uid])
			doll.knock(e, dice)
		else:
			# Lying already: a few steps fit it to the floor, the rest as it is drawn.
			doll.settle(level, SETTLE, true)
		_doll_clock = clock
		_posed = -1
	var dt := clampf(clock - _doll_clock, 0.0, .1)
	_doll_clock = clock
	doll.follow(at, up, dt)
	doll.advance(level, dt)
	var xf := Transform3D(
		Basis(Vector3.UP, doll.turn).scaled(Vector3(doll.size, doll.size, doll.size)),
		Vector3(at.x, at.z, at.y)
	)
	var dead := clock - e.died_at > .2
	if doll.steps == _posed and xf == transform and dead == _posed_dead:
		return
	transform = xf
	_posed = doll.steps
	_posed_dead = dead
	_seeked = NAN
	var back := xf.affine_inverse()
	var model := PackedVector3Array()
	model.resize(doll.pos.size())
	for i in doll.pos.size():
		var p := doll.pos[i]
		model[i] = back * Vector3(p.x, p.z, p.y)
	for skeleton in _skeletons:
		_rig.pose(skeleton, model, dead)


## The model's light, wash, look and how fallen it is (the rim's shade).
func _shade(s: View.Sprite, level: LevelData, look: int, tint: Color, down: float) -> void:
	var c := level.cell(clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01))
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	var hurt := minf(.46, s.hurt / .18 * .44) if s.hurt > 0.0 else 0.0
	var wash := Color(tint.r, tint.g, tint.b, hurt)
	var now := [tone, wash, look, down]
	if now == _shaded:
		return
	_shaded = now
	for mesh in _meshes:
		mesh.set_instance_shader_parameter("tone", tone)
		mesh.set_instance_shader_parameter("wash", wash)
		mesh.set_instance_shader_parameter("look", look)
		mesh.set_instance_shader_parameter("fallen", down)


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
func _time(frame: String, look: int, e: Enemy, clock: float) -> float:
	var hurt := "hurt_" if look == 1 else ""
	if frame.begins_with("w") and frame.length() == 2:
		var first: Variant = models.key_time(kind, hurt + "w0")
		var last: Variant = models.key_time(kind, hurt + "w4")
		if first != null and last != null:
			var beat := fposmod(e.gait / (PI * .5), 4.0)
			var walk_at: float = first
			return walk_at + beat * ActorModels.KEY_TIME
	if frame.begins_with("die_"):
		var first: Variant = models.key_time(kind, "die_0")
		if first != null:
			var span := Enemy.DEATH_TIME
			var step := clampf((clock - e.died_at) / span * 5.0, 0.0, 5.0)
			var fall_at: float = first
			return fall_at + step * ActorModels.KEY_TIME
	for name: String in [hurt + frame, frame, hurt + "0", "0"]:
		var t: Variant = models.key_time(kind, name)
		if t != null:
			var key_at: float = t
			return key_at
	return 0.0
