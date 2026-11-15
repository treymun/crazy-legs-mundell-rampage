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

## The model's kind (actors.json, actor3d_<kind> looks).
@export var kind := ""

var models: ActorModels
var _player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _skeletons: Array[Skeleton3D] = []


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


## Stand where sprite `s` of enemy `e` stands, in its frame and look.
func show_as(s: View.Sprite, e: Enemy, level: LevelData, clock: float) -> void:
	var pose := ActorView.pose_of(s.image, Variants.stem(e.kind))
	var frame: String = pose[0]
	var look: int = pose[1]
	var tint: Color = pose[2]
	var z := s.z + (.07 if frame == "down" else 0.0)
	var turn := PI * .5 - e.angle
	var info: Dictionary = models.kinds[kind]
	var canvas: Array = info.get("canvas", [1.0, e.height])
	var tall: float = canvas[1]
	var size := e.height * e.variant / maxf(.1, tall)
	transform = Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(s.x, z, s.y)
	)
	_player.seek(_time(frame, look, e, clock), true)
	var c := level.cell(clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01))
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	var hurt := minf(.46, s.hurt / .18 * .44) if s.hurt > 0.0 else 0.0
	var down := 0.0
	if frame == "down":
		down = 1.0
	elif frame.begins_with("die_"):
		down = clampf((clock - e.died_at) / Enemy.DEATH_TIME, 0.0, 1.0)
	for mesh in _meshes:
		mesh.set_instance_shader_parameter("tone", tone)
		mesh.set_instance_shader_parameter("wash", Color(tint.r, tint.g, tint.b, hurt))
		mesh.set_instance_shader_parameter("look", look)
		mesh.set_instance_shader_parameter("fallen", down)


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
