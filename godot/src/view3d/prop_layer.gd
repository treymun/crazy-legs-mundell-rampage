## The modelled props of the 3D view: each sprite whose picture has a mesh
## (PropModels) is stood in the world as that prop's scene (PropView), where the sprite stood,
## turned to face the most open side (props stand against walls and fences).
## A prop whose picture changes (a breakable's broken picture) swaps meshes.
class_name PropLayer3D
extends Node3D

var models: PropModels
var _shader: Shader
var _materials: Dictionary = {}
## key (picture and place) -> PropView (scenes/props/<name>.tscn)
var _shown: Dictionary = {}
## place -> facing (radians about up), kept so a broken prop faces as it did
var _facing: Dictionary = {}
var _level: LevelData


func _init(p_models: PropModels) -> void:
	models = p_models
	_shader = load("res://src/view3d/prop.gdshader")


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
		_materials[name] = m
	return m


## Show these sprites (each with a mesh) and nothing else. Returns the
## materials made this frame (the view hands them its shader numbers).
func show_props(sprites: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	if level != _level:
		_level = level
		_facing.clear()
		for node: PropView in _shown.values():
			node.queue_free()
		_shown.clear()
	var seen := {}
	for s: View.Sprite in sprites:
		var name := models.name_of(s.image)
		var place := Vector3(snappedf(s.x, .01), snappedf(s.y, .01), snappedf(s.z, .01))
		var key := "%s@%s" % [s.image, place]
		seen[key] = true
		var node: PropView = _shown.get(key)
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
			var tall: float = dims[2]
			node.setup(material, 51.0 if tall > 2.7 else 32.0)
			node.stand(s.x, s.y, s.z, _turn(s, level, place), level)
			add_child(node)
			_shown[key] = node
		node.lean(s.tilt)
	for key: String in _shown.keys():
		if not seen.has(key):
			var old: PropView = _shown[key]
			old.queue_free()
			_shown.erase(key)
	return fresh


## Which way a prop faces: a board keeps its own axis; anything else turns
## its front (the model's +Z, map +y) toward the most open of eight ways.
func _turn(s: View.Sprite, level: LevelData, place: Vector3) -> float:
	if not is_nan(s.plane):
		return -s.plane
	var key := Vector2(place.x, place.y)
	if _facing.has(key):
		var faced: float = _facing[key]
		return faced
	var best := 0.0
	var best_open := -1.0
	for k in 8:
		var a := k * PI / 4.0
		var dx := sin(a)
		var dy := cos(a)
		var open := 0.0
		while open < 3.0:
			var x := s.x + dx * (open + .5)
			var y := s.y + dy * (open + .5)
			if x < 0 or y < 0 or x >= level.width or y >= level.height:
				break
			if level.solid[level.cell(x, y)] >= 0:
				break
			open += .25
		# Straight ways win a tie (the sprites were drawn square to the street).
		if open > best_open + (.01 if k % 2 == 0 else .3):
			best_open = open
			best = a
	_facing[key] = best
	return best
