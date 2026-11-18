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
## Props gone out of view are kept hidden (parked) by key, at most PARK and
## `park_most` (the view's room in the shader instance buffer: a hidden part
## keeps its slot), and shown again as they were when they come back: making
## them again (scene, look, light) cost 7 or 8 props a frame while the
## view-bench turned (2026-11-17).
const PARK := 64
## A prop further from the eye (map x, y) than its reach (PropView.setup:
## its parts' visibility_range_end, to their middle) and half its own
## breadth and BEYOND more is not stood at all: it would not show. The game
## lists sprites to 51 cells ahead.
const BEYOND := 1.0

var models: PropModels
var _shader: Shader
var _materials: Dictionary = {}
## key ([picture, place], [picture, thing's id] or [picture, track]) ->
## PropView (scenes/props/<name>.tscn)
var _shown: Dictionary = {}
## key -> PropView out of view, hidden, the oldest first (PARK).
var _parked: Dictionary = {}
var park_most := PARK
## Props made from their scenes since the layer was made (view_perf_check).
var made_total := 0
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


## The model parts the layer holds, shown and parked (each a slot in the
## shader instance buffer).
func held() -> int:
	var n := 0
	for node: PropView in _shown.values():
		n += node.meshes().size()
	for node: PropView in _parked.values():
		n += node.meshes().size()
	return n


## How many props are parked (out of view, kept hidden).
func parked() -> int:
	return _parked.size()


## The materials the props shown now draw with (each once).
func live_materials() -> Array[ShaderMaterial]:
	var seen := {}
	var out: Array[ShaderMaterial] = []
	for node: PropView in _shown.values():
		var m := node.material
		if m != null and not seen.has(m):
			seen[m] = true
			out.append(m)
	return out


## Every material the layer has made (the view shares its numbers with them).
func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for m: ShaderMaterial in _materials.values():
		out.append(m)
	return out


## Load the models of the props the level stands (its billboards and props)
## and make their looks now, at its first frame, rather than as each first
## comes into view: the first of a model cost 5 to 7 ms there (its scene's
## first instance, its texture), and a turn towards a yard of them over
## 0.1 s (tools/hitch_bench.gd). Returns the materials made.
func warm(level: LevelData) -> Array[ShaderMaterial]:
	var pictures: Array[String] = []
	for board: LevelData.Billboard in level.billboards:
		pictures.append(board.image)
	for spec: Array in level.props:
		var row: Array = spec
		if not row.is_empty():
			pictures.append("prop_" + str(row[0]))
	var fresh: Array[ShaderMaterial] = []
	var done := {}
	for picture in pictures:
		var name := models.name_of(picture)
		if name == "" or done.has(name):
			continue
		done[name] = true
		var packed := models.scene(name)
		if packed == null:
			continue
		packed.instantiate().free()
		var had := _materials.size()
		var material := _material(name)
		if _materials.size() > had:
			fresh.append(material)
	return fresh


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
func show_props(sprites: Array, level: LevelData, eye := Vector3.INF) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	made.clear()
	if level != _level:
		_level = level
		_facing.clear()
		_kept.clear()
		for node: PropView in _shown.values():
			node.queue_free()
		_shown.clear()
		for node: PropView in _parked.values():
			node.queue_free()
		_parked.clear()
	var seen := {}
	var made_keys: Array = []
	for s: View.Sprite in sprites:
		var name := models.name_of(s.image)
		if eye.x != INF and _beyond(s, name, eye):
			continue
		# A thing on the move (thrown, held: features/carry.gd) keeps its model
		# by what it is, stood again each frame, tumbling by its turn; a prop a
		# boss arena flings or topples (View.Sprite.track) likewise.
		var loose := s.who != null and s.track == ""
		var key: Array
		if loose:
			key = [s.image, s.who.get_instance_id()]
		elif s.track != "":
			key = [s.image, s.track]
		else:
			key = [s.image, Vector3(snappedf(s.x, .01), snappedf(s.y, .01), snappedf(s.z, .01))]
		seen[key] = true
		var node: PropView = _shown.get(key)
		if node == null:
			node = _parked.get(key)
			if node != null:
				# Back in view: shown as it was, lit by its cell's light now.
				_parked.erase(key)
				node.visible = true
				node.light_again(level)
				_shown[key] = node
		if node != null and loose:
			var model_size := models.scale_of(name, s.height)
			var model_dims: Array = models.sizes[name]
			var model_tall: float = model_dims[2]
			node.tumble(
				s.x, s.y, s.z, SolidLayer3D.godot_basis(s.turn), level, model_size, model_tall
			)
			continue
		if node == null:
			var dims: Array = models.sizes[name]
			var size := models.scale_of(name, s.height)
			var tall: float = dims[2]
			var packed := models.scene(name)
			if packed == null:
				continue
			var place := Vector3(snappedf(s.x, .01), snappedf(s.y, .01), snappedf(s.z, .01))
			node = packed.instantiate() as PropView
			if node == null:
				continue
			made_total += 1
			var had := _materials.size()
			var material := _material(name)
			if _materials.size() > had:
				fresh.append(material)
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
	for key: Array in _shown.keys():
		if not seen.has(key):
			var old: PropView = _shown[key]
			_shown.erase(key)
			gone.append([key, old])
	_pass_marks(made_keys, gone)
	# The rest of those gone out of view are parked; the oldest parked go.
	for row: Array in gone:
		var key: Array = row[0]
		var old: PropView = row[1]
		old.visible = false
		_parked[key] = old
	while _parked.size() > maxi(0, park_most):
		var oldest: Array = _parked.keys()[0]
		var old: PropView = _parked[oldest]
		_parked.erase(oldest)
		var marks := old.take_marks()
		if not marks.is_empty():
			_kept[oldest] = marks
		old.queue_free()
	while _kept.size() > KEEP:
		_kept.erase(_kept.keys()[0])
	return fresh


## Whether sprite `s` (model `name`) stands too far from `eye` to show.
func _beyond(s: View.Sprite, name: String, eye: Vector3) -> bool:
	var dims: Array = models.sizes[name]
	var size := models.scale_of(name, s.height)
	var tall: float = dims[2]
	var wide: float = dims[0]
	var deep: float = dims[1]
	var reach := 51.0 if tall * size > 2.7 else 32.0
	var far := reach + Vector2(wide, deep).length() * size * .5 + BEYOND
	return Vector2(s.x - eye.x, s.y - eye.y).length_squared() > far * far


## Marks follow a prop made again where one went this frame (a car stood
## again at its next place, a thrown thing landing, a breakable showing its
## struck picture): the nearest one gone ([key, PropView] in `gone`) of the
## same model within REMADE cells with marks hands them on and is let go; and
## a prop made again after it left the park keeps the marks kept by its key.
## One that comes back from the park has kept its own.
func _pass_marks(made_keys: Array, gone: Array) -> void:
	for i in made.size():
		var node := made[i]
		var key: Array = made_keys[i]
		if _kept.has(key):
			var kept: Array = _kept[key]
			node.give_marks(kept)
			_kept.erase(key)
			continue
		var best := -1
		var best_d := REMADE
		for k in gone.size():
			var row: Array = gone[k]
			var old: PropView = row[1]
			var d := old.position.distance_to(node.position)
			if old.prop == node.prop and d < best_d and not old.take_marks().is_empty():
				best = k
				best_d = d
		if best >= 0:
			var row: Array = gone[best]
			var old: PropView = row[1]
			node.give_marks(old.take_marks())
			old.queue_free()
			gone.remove_at(best)


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
