## The enemies and bosses of the 3D view that have a rigged model
## (ActorModels): each sprite the game lists for an enemy (Renderer.Sprite
## `who`) is drawn as that enemy's model instead, facing the enemy's own
## heading, in the pose its sprite would show (the same frame: idle, a walk
## beat, aim, wind-up, fire, pain, recover, fidget, a step of its fall, down)
## and look (plain, hurt, a boss's phase), the walk and the fall moving
## smoothly between their frames.
class_name ActorLayer3D
extends Node3D

const HEADINGS: Array[String] = ["quarter_", "side_", "away_", "back_"]

var models: ActorModels
## enemy instance id -> [Node3D, AnimationPlayer, animation name, kind]
var _shown: Dictionary = {}


func _init(p_models: ActorModels) -> void:
	models = p_models


## The model kind an enemy is drawn with ("" when none).
func kind_of(e: Enemy) -> String:
	if models.has(e.kind):
		return e.kind
	var stem := Variants.stem(e.kind)
	return stem if models.has(stem) else ""


## Show these sprites (each an enemy's, with a model) and no others. Returns
## the materials first used this frame (the view hands them its numbers).
func show_actors(
	sprites: Array, level: LevelData, clock: float, lost: Dictionary
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for item: Variant in sprites:
		var s := item as Renderer.Sprite
		var e := s.who as Enemy
		var kind := kind_of(e)
		var id := e.get_instance_id()
		seen[id] = true
		var entry: Array = _shown.get(id, [])
		if entry.is_empty() or entry[3] != kind:
			if not entry.is_empty():
				(entry[0] as Node3D).queue_free()
			entry = _make(kind, fresh)
			if entry.is_empty():
				continue
			_shown[id] = entry
		_place(entry, s, e, level, clock)
		_limbs(entry, lost.get(e, []))
	for id: int in _shown.keys():
		if not seen.has(id):
			(_shown[id][0] as Node3D).queue_free()
			_shown.erase(id)
	return fresh


func _make(kind: String, fresh: Array[ShaderMaterial]) -> Array:
	var packed := models.scene(kind)
	if packed == null:
		return []
	var node := packed.instantiate() as Node3D
	var had := models.materials().size()
	var material := models.material(kind)
	if models.materials().size() > had:
		fresh.append(material)
	var player: AnimationPlayer = null
	for child in node.find_children("*", "", true, false):
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = 32.0
		elif child is AnimationPlayer:
			player = child as AnimationPlayer
	if player == null:
		node.queue_free()
		return []
	var names := player.get_animation_list()
	if names.is_empty():
		node.queue_free()
		return []
	player.play(names[0])
	player.pause()
	add_child(node)
	return [node, player, names[0], kind]


## Stand the model where the sprite stands, turned to the enemy's heading, in
## the sprite's frame and look.
func _place(entry: Array, s: Renderer.Sprite, e: Enemy, level: LevelData, clock: float) -> void:
	var node: Node3D = entry[0]
	var player: AnimationPlayer = entry[1]
	var kind: String = entry[3]
	var pose := _pose(s.image, Variants.stem(e.kind))
	var frame: String = pose[0]
	var look: int = pose[1]
	var tint: Color = pose[2]
	var z := s.z + (.07 if frame == "down" else 0.0)
	var turn := PI * .5 - e.angle
	var canvas: Array = models.kinds[kind].get("canvas", [1.0, e.height])
	var scale := e.height * e.variant / maxf(.1, float(canvas[1]))
	node.transform = Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(scale, scale, scale)), Vector3(s.x, z, s.y)
	)
	player.seek(_time(kind, frame, look, e, clock), true)
	var c := level.cell(clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01))
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	var hurt := minf(.46, s.hurt / .18 * .44) if s.hurt > 0.0 else 0.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.set_instance_shader_parameter("tone", tone)
		mesh.set_instance_shader_parameter("wash", Color(tint.r, tint.g, tint.b, hurt))
		mesh.set_instance_shader_parameter("look", look)


## Leave off what the body lost (Gore.lost): the head, or an arm (an arm or a
## hand thrown); a boot stays on. Runs after each pose (the pose sets every
## bone's scale again).
func _limbs(entry: Array, lost: Array) -> void:
	if lost.is_empty():
		return
	var piece: String = lost[0]
	var want := ""
	if piece == "head":
		want = "head"
	elif piece == "arm" or piece == "hand":
		want = "arm_" + String(lost[1])
	if want == "":
		return
	var labels: Dictionary = models.kinds[entry[3]].get("labels", {})
	var node: Node3D = entry[0]
	for child in node.find_children("*", "Skeleton3D", true, false):
		var skeleton := child as Skeleton3D
		for bone: String in labels:
			if labels[bone] == want:
				var i := skeleton.find_bone(bone)
				if i >= 0:
					skeleton.set_bone_pose_scale(i, Vector3(.001, .001, .001))


## [frame name, look, tint] from a sprite's picture name: `<stem>[_p2|_p3|
## _hurt][_<heading>]_<frame>[~r.g.b]`.
static func _pose(image: String, stem: String) -> Array:
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
func _time(kind: String, frame: String, look: int, e: Enemy, clock: float) -> float:
	var hurt := "hurt_" if look == 1 else ""
	if frame.begins_with("w") and frame.length() == 2:
		var first: Variant = models.key_time(kind, hurt + "w0")
		var last: Variant = models.key_time(kind, hurt + "w4")
		if first != null and last != null:
			var beat := fposmod(e.gait / (PI * .5), 4.0)
			return float(first) + beat * ActorModels.KEY_TIME
	if frame.begins_with("die_"):
		var first: Variant = models.key_time(kind, "die_0")
		if first != null:
			var span := Enemy.DEATH_TIME
			var step := clampf((clock - e.died_at) / span * 5.0, 0.0, 5.0)
			return float(first) + step * ActorModels.KEY_TIME
	for name: String in [hurt + frame, frame, hurt + "0", "0"]:
		var t: Variant = models.key_time(kind, name)
		if t != null:
			return float(t)
	return 0.0
