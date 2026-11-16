## The modelled props of the 3D view: each sprite whose picture has a mesh
## (PropModels) is stood in the world as that prop's scene (PropView), where the sprite stood,
## turned to face the most open side (props stand against walls and fences),
## scaled when the sprite was shown taller or shorter than its picture.
## A prop whose picture changes (a breakable's broken picture) swaps meshes;
## a quest station's (to do, done) shows the other look of its one model.
class_name PropLayer3D
extends Node3D

## How far the old pictures turned a model from face on (PropModels.facing).
const PICTURE_TURN := PropModels.PICTURE_TURN
## How many props out of view keep their marks, and how far a prop made
## again may be from where it went and keep its marks (cells).
const KEEP := 48
const REMADE := 1.6

var models: PropModels
var _shader: Shader
var _materials: Dictionary = {}
## key (picture and place) -> PropView (scenes/props/<name>.tscn)
var _shown: Dictionary = {}
## place -> facing (radians about up), kept so a broken prop faces as it did
var _facing: Dictionary = {}
var _level: LevelData
## The props made this frame (thing_marks.gd chars them at once).
var made: Array[PropView] = []
## Marks on props no longer shown, by key (thing_marks.gd), kept to KEEP.
var _kept := {}


func _init(p_models: PropModels) -> void:
	models = p_models
	_shader = load("res://src/view3d/prop.gdshader")


## The props shown now.
func shown() -> Array:
	return _shown.values()


## Every material the layer has made (the view shares its numbers with them).
func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for m: ShaderMaterial in _materials.values():
		out.append(m)
	return out


func _material(name: String) -> ShaderMaterial:
	var m: ShaderMaterial = _materials.get(name)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("baked", models.texture(name))
		# The wind sways it (effects.cfg [sway]; view_light's wind_now).
		var sway: float = Effects.SWAY.get(name, 0.0)
		if sway != 0.0 and models.sizes.has(name):
			var dims: Array = models.sizes[name]
			var wide: float = dims[0]
			var tall: float = dims[2]
			m.set_shader_parameter("sway_k", sway)
			m.set_shader_parameter("sway_size", Vector2(tall, wide))
		_materials[name] = m
	return m


## Show these sprites (each with a mesh) and nothing else. Returns the
## materials made this frame (the view hands them its shader numbers).
func show_props(sprites: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	made.clear()
	if level != _level:
		_level = level
		_facing.clear()
		_kept.clear()
		for node: PropView in _shown.values():
			node.queue_free()
		_shown.clear()
	var seen := {}
	var made_keys: Array[String] = []
	for s: View.Sprite in sprites:
		var name := models.name_of(s.image)
		var place := Vector3(snappedf(s.x, .01), snappedf(s.y, .01), snappedf(s.z, .01))
		var key := "%s@%s" % [s.image, place]
		# A thing on the move (thrown, held: features/carry.gd) keeps its model
		# by what it is, stood again each frame, tumbling by its turn; a prop a
		# boss arena flings or topples (View.Sprite.track) likewise.
		var loose := s.who != null and s.track == ""
		if loose:
			key = "%s#%d" % [s.image, s.who.get_instance_id()]
		elif s.track != "":
			key = "%s#%s" % [s.image, s.track]
		seen[key] = true
		var node: PropView = _shown.get(key)
		if node != null and loose:
			var model_size := models.scale_of(name, s.height)
			var model_dims: Array = models.sizes[name]
			var model_tall: float = model_dims[2]
			node.tumble(
				s.x, s.y, s.z, SolidLayer3D.godot_basis(s.turn), level, model_size, model_tall
			)
			continue
		if node == null:
			var packed := models.scene(name)
			if packed == null:
				continue
			node = packed.instantiate() as PropView
			if node == null:
				continue
			var had := _materials.size()
			var material := _material(name)
			if _materials.size() > had:
				fresh.append(material)
			var dims: Array = models.sizes[name]
			var size := models.scale_of(name, s.height)
			var tall: float = dims[2]
			node.setup(material, 51.0 if tall * size > 2.7 else 32.0)
			node.show_look(models.look_of(s.image))
			node.stand(s.x, s.y, s.z, _turn(s, level, place), level, size)
			add_child(node)
			_shown[key] = node
			made.append(node)
			made_keys.append(key)
			if loose:
				node.tumble(s.x, s.y, s.z, SolidLayer3D.godot_basis(s.turn), level, size, tall)
				continue
		if s.track != "":
			node.carry(s.x, s.y, s.z, SolidLayer3D.godot_basis(s.turn))
			if s.body:
				# A vehicle on the move is lit where it is (features/vehicles.gd).
				node.relight(s.x, s.y, level)
			continue
		node.lean(s.tilt)
	var gone: Array = []
	for key: String in _shown.keys():
		if not seen.has(key):
			var old: PropView = _shown[key]
			var marks := old.take_marks()
			if not marks.is_empty():
				gone.append([key, old.prop, old.position, marks])
			old.queue_free()
			_shown.erase(key)
	_pass_marks(made_keys, gone)
	return fresh


## Marks follow a prop that comes back into view (kept by its key) or one
## made again where it went (a car stood again at its next place, a thrown
## thing landing, a breakable showing its struck picture): the nearest gone
## prop of the same model within REMADE cells hands its marks on.
func _pass_marks(made_keys: Array[String], gone: Array) -> void:
	for i in made.size():
		var node := made[i]
		var key := made_keys[i]
		if _kept.has(key):
			var kept: Array = _kept[key]
			node.give_marks(kept)
			_kept.erase(key)
			continue
		var best := -1
		var best_d := REMADE
		for k in gone.size():
			var row: Array = gone[k]
			var at: Vector3 = row[2]
			var model: String = row[1]
			var d := at.distance_to(node.position)
			if model == node.prop and d < best_d:
				best = k
				best_d = d
		if best >= 0:
			var row: Array = gone[best]
			var marks: Array = row[3]
			node.give_marks(marks)
			gone.remove_at(best)
	for row: Array in gone:
		var key: String = row[0]
		_kept[key] = row[3]
	while _kept.size() > KEEP:
		_kept.erase(_kept.keys()[0])


## Which way a prop faces (PropModels.facing), kept for where it stands so a
## broken prop faces as the whole one did.
func _turn(s: View.Sprite, level: LevelData, place: Vector3) -> float:
	if not is_nan(s.plane) or not is_nan(s.face):
		return PropModels.facing(level, s.x, s.y, s.plane, s.face)
	var key := Vector2(place.x, place.y)
	if _facing.has(key):
		var faced: float = _facing[key]
		return faced
	var best := PropModels.facing(level, s.x, s.y, s.plane, s.face)
	_facing[key] = best
	return best
