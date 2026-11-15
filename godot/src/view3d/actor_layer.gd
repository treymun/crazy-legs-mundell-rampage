## The enemies and bosses of the 3D view that have a rigged model
## (ActorModels): each sprite the game lists for an enemy (View.Sprite
## `who`) is drawn as that enemy's scene instead (ActorView,
## scenes/actors/<kind>.tscn), which poses itself from the sprite.
class_name ActorLayer3D
extends Node3D

var models: ActorModels
## enemy instance id -> ActorView
var _shown: Dictionary = {}
## The player's reflection (only the mirror's camera sees it), or null.
var _mirrored: ActorView
## "enemy instance id:gear" -> the piece of gear shot off (show_gear)
var _pieces: Dictionary = {}


func _init(p_models: ActorModels) -> void:
	models = p_models


## The model kind an enemy is drawn with ("" when none).
func kind_of(e: Enemy) -> String:
	if models.has(e.kind):
		return e.kind
	var stem := Variants.stem(e.kind)
	return stem if models.has(stem) else ""


## Whether enemy `e`'s sprite `s` is drawn as its model. A kind whose body at
## rest is a build of its own that the model's parts cannot make (fit.json
## "down_cel": the derby champ's burnt-out wreck, the swamp king's sunk boat)
## keeps its cel for that.
func takes(s: View.Sprite, e: Enemy) -> bool:
	var kind := kind_of(e)
	if kind == "":
		return false
	var info: Dictionary = models.kinds[kind]
	var own_cel: bool = info.get("down_cel", false)
	if own_cel and ActorView.pose_of(s.image, Variants.stem(e.kind))[0] == "down":
		return false
	return true


## Show these sprites (each an enemy's, with a model) and no others. Returns
## the materials first used this frame (the view hands them its numbers).
func show_actors(
	sprites: Array, level: LevelData, clock: float, lost: Dictionary, gear_lost := {}
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		var kind := kind_of(e)
		var id := e.get_instance_id()
		seen[id] = true
		var view: ActorView = _shown.get(id)
		if view == null or view.kind != kind:
			if view != null:
				view.queue_free()
			_shown.erase(id)
			view = _make(kind, fresh)
			if view == null:
				continue
			_shown[id] = view
		view.show_as(s, e, level, clock)
		var gone: Array = lost.get(e, [])
		view.lose(gone)
		var shed: Array = gear_lost.get(e, [])
		if not shed.is_empty():
			view.lose_gear(shed)
	for id: int in _shown.keys():
		if not seen.has(id):
			var old: ActorView = _shown[id]
			old.queue_free()
			_shown.erase(id)
	return fresh


## Show the player's reflection `s` as its model on render layers `bits`
## (the mirror's camera's alone), or none (null, or a body with no model).
## Returns the material when first used this frame.
func show_reflection(
	s: View.Sprite, level: LevelData, clock: float, bits: int
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var e: Enemy = null
	if s != null and s.who is Enemy:
		e = s.who as Enemy
	var kind := kind_of(e) if e != null else ""
	if kind == "" or (_mirrored != null and _mirrored.kind != kind):
		if _mirrored != null:
			_mirrored.queue_free()
			_mirrored = null
	if kind == "":
		return fresh
	if _mirrored == null:
		_mirrored = _make(kind, fresh)
		if _mirrored == null:
			return fresh
		_mirrored.set_layers(bits)
	_mirrored.show_as(s, e, level, clock)
	return fresh


## Show these sprites (View.Sprite.gear: a boss's gear shot off, flying or
## lying) as that gear's part of the boss's model, and no other such pieces.
## Returns the materials first used this frame.
func show_gear(sprites: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		var kind := kind_of(e)
		if kind == "":
			continue
		var key := "%d:%s" % [e.get_instance_id(), s.gear]
		seen[key] = true
		var node: MeshInstance3D = _pieces.get(key)
		if node == null:
			var made := models.gear_mesh(kind, s.gear)
			if made.is_empty():
				continue
			var had := models.materials().size()
			node = MeshInstance3D.new()
			node.mesh = made[0]
			node.material_override = models.material(kind)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 32.0
			if models.materials().size() > had:
				fresh.append(models.material(kind))
			add_child(node)
			_pieces[key] = node
		var info: Dictionary = models.kinds[kind]
		var canvas: Array = info.get("canvas", [1.0, e.height])
		var tall: float = canvas[1]
		var fit: float = info.get("scale", 1.0)
		var size := e.height * e.variant / maxf(.1, tall) * fit
		node.transform = Transform3D(
			SolidLayer3D.godot_basis(s.turn).scaled(Vector3.ONE * size), Vector3(s.x, s.z, s.y)
		)
		var c := level.cell(
			clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01)
		)
		var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
		var tone := Color(1, 1, 1, level.light[c])
		if level.tints.size() >= 3:
			tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
		node.set_instance_shader_parameter("tone", tone)
		node.set_instance_shader_parameter("look", e.boss_phase if e.boss_phase >= 2 else 0)
	for key: String in _pieces.keys():
		if not seen.has(key):
			var old: MeshInstance3D = _pieces[key]
			old.queue_free()
			_pieces.erase(key)
	return fresh


func _make(kind: String, fresh: Array[ShaderMaterial]) -> ActorView:
	var packed := models.scene(kind)
	if packed == null:
		return null
	var had := models.materials().size()
	var view := packed.instantiate() as ActorView
	if view == null:
		return null
	if not view.setup(models):
		view.free()
		return null
	if models.materials().size() > had:
		fresh.append(models.material(kind))
	add_child(view)
	return view
