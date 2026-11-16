## The pieces of broken scenery (features/wreckage.gd): each sprite whose
## `solid` is "~<key>#<piece>" is drawn as that piece of WreckCuts' cut,
## standing at the sprite's (x, y, z), its middle, turned (and sized) by its
## `turn`, with its source's texture (a prop's baked texture, a picture, a
## tile) through wreck.gdshader, lit in its cell as a prop is. A node a piece,
## kept while the piece is shown and handed to the next one after; a mesh a
## cut piece and a material a source, made the first time one is seen.
class_name WreckLayer3D
extends Node3D

## As far ahead as props are drawn.
const REACH := 32.0

var _assets: Assets
var _shader: Shader
var _meshes := {}
var _materials := {}
## sprite -> MeshInstance3D shown for it; the spare nodes.
var _shown := {}
var _spare: Array[MeshInstance3D] = []


func _init(assets: Assets) -> void:
	_assets = assets
	_shader = load("res://src/view3d/wreck.gdshader")


## The pieces shown now (what shots and fire mark: thing_marks.gd).
func shown() -> Array:
	return _shown.values()


## The materials the pieces shown now draw with (each once).
func live_materials() -> Array[ShaderMaterial]:
	var seen := {}
	var out: Array[ShaderMaterial] = []
	for node: MeshInstance3D in _shown.values():
		var m := node.material_override as ShaderMaterial
		if m != null and not seen.has(m):
			seen[m] = true
			out.append(m)
	return out


static func takes(s: View.Sprite) -> bool:
	return s.solid.begins_with("~")


## Show these pieces and no others. Returns the materials made this frame
## (the view hands them its shader numbers).
func show_wrecks(list: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for item: Variant in list:
		var s: View.Sprite = item
		var node: MeshInstance3D = _shown.get(s)
		if node == null or node.get_meta("solid", "") != s.solid:
			var mesh := _mesh(s.solid)
			if mesh == null:
				continue
			if node == null:
				node = _spare.pop_back() if not _spare.is_empty() else _node()
				_shown[s] = node
			var source := s.solid.substr(1).get_slice("|", 0)
			var had := _materials.size()
			var material := _material(source)
			if material == null:
				continue
			if _materials.size() > had:
				fresh.append(material)
			node.mesh = mesh
			node.material_override = material
			node.set_meta("solid", s.solid)
			node.set_meta("cell", -1)
			node.visible = true
			ThingMarks.clear(node)
		seen[s] = true
		node.transform = Transform3D(SolidLayer3D.godot_basis(s.turn), Vector3(s.x, s.z, s.y))
		var cell := level.cell(
			clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01)
		)
		if node.get_meta("cell", -1) != cell:
			node.set_meta("cell", cell)
			node.set_instance_shader_parameter(
				"tone", SpriteLayer3D.tone_at(level, s.x, s.y, false)
			)
	for s: View.Sprite in _shown.keys():
		if not seen.has(s):
			var idle: MeshInstance3D = _shown[s]
			idle.visible = false
			idle.set_meta("solid", "")
			_shown.erase(s)
			_spare.append(idle)
	return fresh


func _node() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = REACH
	add_child(node)
	return node


## The mesh of piece "~<key>#<i>": its faces, in Godot's axes (y up).
func _mesh(solid: String) -> ArrayMesh:
	var cached: Variant = _meshes.get(solid)
	if cached != null:
		var known: ArrayMesh = cached
		return known
	var hash_at := solid.rfind("#")
	var key := solid.substr(1, hash_at - 1)
	var index := solid.substr(hash_at + 1).to_int()
	var parts := WreckCuts.parts(_assets, key)
	if index < 0 or index >= parts.size():
		return null
	var part: WreckCuts.Part = parts[index]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for v: Vector3 in part.verts:
		verts.append(Vector3(v.x, v.z, v.y))
	for n: Vector3 in part.normals:
		normals.append(Vector3(n.x, n.z, n.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = part.uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[solid] = mesh
	return mesh


func _material(source: String) -> ShaderMaterial:
	var cached: Variant = _materials.get(source)
	if cached != null:
		var known: ShaderMaterial = cached
		return known
	var image := WreckCuts.texture_image(_assets, source)
	if image == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("baked", ImageTexture.create_from_image(image))
	_materials[source] = m
	return m
