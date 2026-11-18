## The pieces of broken scenery (features/wreckage.gd): each sprite whose
## `solid` is "~<key>#<piece>" is drawn as that piece of WreckCuts' cut,
## standing at the sprite's (x, y, z), its middle, turned (and sized) by its
## `turn`, with its source's texture (a prop's baked texture, a picture, a
## tile) through wreck.gdshader, lit in its cell as a prop is. A node a piece,
## kept while the piece is shown and handed to the next one after; a mesh a
## cut piece and a material a source, made the first time one is seen. A
## piece's cut faces carry their raw material in their vertex colours
## (WreckFracture.finish). The one sprite "~~fine" carries the breaks' fine
## debris (`who`, a WreckDebris): drawn here as one MultiMesh of small boxes
## (wreck_fine.gdshader), each its colour, lit in its cell.
class_name WreckLayer3D
extends Node3D

## As far ahead as props are drawn.
const REACH := 32.0
## Spare nodes kept at most (each keeps its own material, OwnMaterial: a
## scene of 48 pieces would leave 48 spares after they went).
const SPARE := 8
## How far off a set piece's parts are still drawn.
const FAR := 90.0
## The sprite carrying the fine debris, and how many bits it draws at most.
const FINE := "~~fine"
const FINE_MOST := 256
## New piece meshes made in a frame at most.
const MESHES_FRAME := 8

var _assets: Assets
var _shader: Shader
var _meshes := {}
var _materials := {}
## sprite -> MeshInstance3D shown for it; the spare nodes.
var _shown := {}
var _spare: Array[MeshInstance3D] = []
## The fine debris: one MultiMesh of boxes, and its material.
var _fine: MultiMeshInstance3D
var _fine_material: ShaderMaterial
var _fine_buffer := PackedFloat32Array()
var _fine_version := -1
var _fine_layout := -1
## A piece of one triangle with a cut face, for the warm-up (warm_roots).
var _warm_piece: MeshInstance3D
## The props' models, whose textures a model's pieces share (the view sets
## it; pass 10: each was a second copy of the same picture).
var prop_models: PropModels


func _init(assets: Assets) -> void:
	_assets = assets
	_shader = load("res://src/view3d/wreck.gdshader")


## What the view's warm-up (WorldView3D.warm_up) draws for a frame, a speck
## in front of the eye, so the pieces' shader with its cut faces' vertex
## colours and the fine debris' are compiled before the first break, not in
## its frame (a cold shader cache: the browser, a phone's first run).
func warm_roots() -> Array[Node3D]:
	if _warm_piece == null:
		_warm_piece = title_piece()
		_warm_piece.visibility_range_end = REACH
		add_child(_warm_piece)
		_warm_piece.visible = false
		_show_fine(null, null)
	return [_warm_piece, _fine]


## A piece of one triangle with a cut face (the cut faces' vertex format),
## drawn with the pieces' shader: the warm-ups' (warm_roots, the title's).
func title_piece() -> MeshInstance3D:
	var cut := WreckCuts.Part.new()
	cut.verts = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1)])
	cut.normals = PackedVector3Array([Vector3(0, -1, 0), Vector3(0, -1, 0), Vector3(0, -1, 0)])
	cut.uvs = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	cut.colors = PackedColorArray([Color(0, 1, 0, 0), Color(0, 1, 0, 0), Color(1, 1, 1, 1)])
	cut.uv2s = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.mesh = _mesh_of(cut)
	var m := ShaderMaterial.new()
	m.shader = _shader
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	m.set_shader_parameter("baked", ImageTexture.create_from_image(white))
	node.material_override = m
	return node


## The fine debris' material (made once; the title's warm-up draws it).
func fine_material() -> ShaderMaterial:
	if _fine_material == null:
		_fine_material = ShaderMaterial.new()
		_fine_material.shader = load("res://src/view3d/wreck_fine.gdshader")
	return _fine_material


## The pieces shown now (what shots and fire mark: thing_marks.gd).
func shown() -> Array:
	return _shown.values()


static func takes(s: View.Sprite) -> bool:
	return s.solid.begins_with("~")


## Show these pieces and no others. Returns the materials made this frame
## (the view hands them its shader numbers).
func show_wrecks(list: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	var fine_shown := false
	var made_now := 0
	for item: Variant in list:
		var s: View.Sprite = item
		if s.solid == FINE:
			fine_shown = true
			if _show_fine(s.who as WreckDebris, level):
				fresh.append(_fine_material)
			continue
		var node: MeshInstance3D = _shown.get(s)
		if node == null or node.get_meta("solid", "") != s.solid:
			# A break's pieces are made a few a frame (the frame it breaks
			# would make them all); one not made yet shows the next frame.
			if not _meshes.has(s.solid):
				if made_now >= MESHES_FRAME:
					continue
				made_now += 1
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
			if node.get_meta("source", "") != source:
				node.set_meta("source", source)
				OwnMaterial.give(node, material)
			# A set piece's parts (a barn, a water tower: src/set_piece_mesh.gd)
			# stand big and are seen from far off.
			node.visibility_range_end = FAR if s.solid.contains("|sp") else REACH
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
			OwnMaterial.put(node, "tone", SpriteLayer3D.tone_at(level, s.x, s.y, false))
	if not fine_shown and _fine != null:
		_fine.multimesh.visible_instance_count = 0
	for s: View.Sprite in _shown.keys():
		if not seen.has(s):
			var idle: MeshInstance3D = _shown[s]
			_shown.erase(s)
			if _spare.size() >= SPARE:
				idle.queue_free()
				continue
			idle.visible = false
			idle.set_meta("solid", "")
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
	var mesh := _mesh_of(part)
	_meshes[solid] = mesh
	return mesh


## A piece's mesh, in Godot's axes.
func _mesh_of(part: WreckCuts.Part) -> ArrayMesh:
	var verts := part.shown
	var normals := part.shown_n
	if verts.size() != part.verts.size():
		verts = PackedVector3Array()
		normals = PackedVector3Array()
		for v: Vector3 in part.verts:
			verts.append(Vector3(v.x, v.z, v.y))
		for n: Vector3 in part.normals:
			normals.append(Vector3(n.x, n.z, n.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = part.uvs
	if part.colors.size() == part.verts.size():
		arrays[Mesh.ARRAY_COLOR] = part.colors
		arrays[Mesh.ARRAY_TEX_UV2] = part.uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _material(source: String) -> ShaderMaterial:
	var cached: Variant = _materials.get(source)
	if cached != null:
		var known: ShaderMaterial = cached
		return known
	var baked: Texture2D = null
	if source.begins_with("m:") and prop_models != null:
		if _assets.has_art("mesh_" + source.substr(2)):
			baked = prop_models.texture(source.substr(2))
	else:
		var image := WreckCuts.texture_image(_assets, source)
		if image != null:
			baked = ImageTexture.create_from_image(image)
	if baked == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("baked", baked)
	_materials[source] = m
	return m


## Draw the fine debris: each bit a box of its colour, lit in its cell (its
## light asked again only when it moves to another). True when its material
## was made now (the view hands it its shader numbers).
func _show_fine(debris: WreckDebris, level: LevelData) -> bool:
	var made := false
	if _fine == null:
		_fine = MultiMeshInstance3D.new()
		_fine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mm.mesh = box
		mm.instance_count = FINE_MOST
		mm.visible_instance_count = 0
		_fine.multimesh = mm
		_fine.material_override = fine_material()
		# Its bits are anywhere about the level: never culled as one box.
		_fine.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
		add_child(_fine)
		made = true
	var mm := _fine.multimesh
	if debris == null or level == null:
		# The warm-up's: one bit, drawn wherever the warm-up puts it.
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color.WHITE)
		mm.visible_instance_count = 1 if debris == null and level == null else 0
		_fine.visible = false
		return made
	_fine.visible = true
	if debris.version == _fine_version and mm.visible_instance_count > 0:
		return made
	_fine_version = debris.version
	# A bit came or went: all written again; else only those still moving
	# or shrinking (one lying still keeps what was written).
	var all := debris.layout != _fine_layout or mm.visible_instance_count == 0
	_fine_layout = debris.layout
	# One buffer for them all (12 floats of transform, 4 of colour, 4 of
	# light a bit), handed over at once.
	if _fine_buffer.size() != FINE_MOST * 20:
		_fine_buffer.resize(FINE_MOST * 20)
	var w := level.width
	var count := mini(debris.bits.size(), FINE_MOST)
	for i in count:
		var b: WreckDebris.Bit = debris.bits[i]
		if b.drawn and not all and b.age < b.life:
			continue
		var cell := clampi(int(b.p.y), 0, level.height - 1) * w + clampi(int(b.p.x), 0, w - 1)
		if cell != b.cell:
			b.cell = cell
			b.tone = SpriteLayer3D.tone_at(level, b.p.x, b.p.y, false)
		b.drawn = b.resting and b.age < b.life
		var turn := SolidLayer3D.godot_basis(WreckDebris.turn_of(b))
		var at := i * 20
		var o := Vector3(b.p.x, b.p.z + (b.size.z * .5 if b.resting else 0.0), b.p.y)
		_fine_buffer[at] = turn.x.x
		_fine_buffer[at + 1] = turn.y.x
		_fine_buffer[at + 2] = turn.z.x
		_fine_buffer[at + 3] = o.x
		_fine_buffer[at + 4] = turn.x.y
		_fine_buffer[at + 5] = turn.y.y
		_fine_buffer[at + 6] = turn.z.y
		_fine_buffer[at + 7] = o.y
		_fine_buffer[at + 8] = turn.x.z
		_fine_buffer[at + 9] = turn.y.z
		_fine_buffer[at + 10] = turn.z.z
		_fine_buffer[at + 11] = o.z
		_fine_buffer[at + 12] = b.colour.r
		_fine_buffer[at + 13] = b.colour.g
		_fine_buffer[at + 14] = b.colour.b
		_fine_buffer[at + 15] = 1.0
		_fine_buffer[at + 16] = b.tone.r
		_fine_buffer[at + 17] = b.tone.g
		_fine_buffer[at + 18] = b.tone.b
		_fine_buffer[at + 19] = b.tone.a
	if count > 0:
		mm.buffer = _fine_buffer
	mm.visible_instance_count = count
	return made
