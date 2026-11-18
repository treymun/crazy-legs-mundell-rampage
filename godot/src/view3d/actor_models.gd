## The enemies and bosses that have a rigged model for the 3D view
## (godot/assets3d/actors, made by tools/art/build_actor_meshes.gd): each
## kind's scene (mesh, skeleton, the action "poses"), which key of that action
## each frame is, and its baked looks (`actor3d_<kind>[_<look>]` in the art).
class_name ActorModels
extends RefCounted

const FOLDER := "res://assets3d/actors"
## Each kind's scene: an ActorView over its model (tools/art/build_actor_scenes.gd).
const SCENES := "res://scenes/actors"
## Blender's keys are a frame apart at 24 a second.
const KEY_TIME := 1.0 / 24.0
const LOOKS: Array[String] = ["", "hurt", "p2", "p3"]

## kind -> {frames: {name: key}, height, textures: [...], ...}, with fit.json's
## numbers for the kind merged in.
var kinds: Dictionary = {}
var _scenes: Dictionary = {}
## kind -> scene path asked for on the loader's threads (request), not yet taken.
var _asked: Dictionary = {}
var _has_scene: Dictionary = {}
var _materials: Dictionary = {}
## kind -> true once its model, looks and scene are here (has(); they stay).
var _ready: Dictionary = {}
## "kind:gear" -> [ArrayMesh, middle] (gear_mesh)
var _gear_meshes: Dictionary = {}
## "kind:gear" -> Array[String] of its bones (gear_bones)
var _gear_bones: Dictionary = {}
var _assets: Assets
var _shader: Shader


func _init(assets: Assets) -> void:
	_assets = assets
	_shader = load("res://src/view3d/actor.gdshader")
	var path := FOLDER.path_join("actors.json")
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			kinds = data
	# How each model is fitted to its old cels, by hand (actors.json is
	# written by tools/art/build_actor_meshes.gd): "scale" (its size against
	# the cel), "min_px" (no part thinner than that many of the view's
	# pixels), "light" (its looks' brightness against the cel's).
	var fit_path := FOLDER.path_join("fit.json")
	if FileAccess.file_exists(fit_path):
		var fit: Variant = JSON.parse_string(FileAccess.get_file_as_string(fit_path))
		if fit is Dictionary:
			var fits: Dictionary = fit
			for kind: String in fits:
				var info: Variant = kinds.get(kind)
				var own: Variant = fits[kind]
				if info is Dictionary and own is Dictionary:
					var entry: Dictionary = info
					var numbers: Dictionary = own
					entry.merge(numbers, true)


func has(kind: String) -> bool:
	if _ready.has(kind):
		return true
	if not kinds.has(kind) or not _assets.has_art("actor3d_" + kind):
		return false
	# A browser build fetches a chapter's models and looks after it starts:
	# till then its enemy is drawn as its sprite.
	if not _assets.kind_ready(kind):
		return false
	# Asked for every enemy's sprite every frame: ResourceLoader.exists once.
	var ok: Variant = _has_scene.get(kind)
	if ok == null:
		ok = ResourceLoader.exists(SCENES.path_join(kind + ".tscn"))
		_has_scene[kind] = ok
	if ok:
		# Here for good once here (asked for every enemy's sprite every frame).
		_ready[kind] = true
	return ok


## The kind's scene (an ActorView), or null when it has none. One asked for
## (request) is taken from the loader, waiting for it if it is not done.
func scene(kind: String) -> PackedScene:
	var cached: Variant = _scenes.get(kind)
	if cached == null:
		var path := SCENES.path_join(kind + ".tscn")
		if _asked.has(kind):
			_asked.erase(kind)
			cached = ResourceLoader.load_threaded_get(path)
		else:
			cached = load(path) if ResourceLoader.exists(path) else null
		_scenes[kind] = cached
	var packed: PackedScene = cached
	return packed


## Start loading the scenes of `wanted` kinds on the loader's threads (pass
## 10; PropModels.request): a level's first frame asks for its enemies'.
func request(wanted: Array[String]) -> void:
	for kind in wanted:
		if _scenes.has(kind) or _asked.has(kind) or not has(kind):
			continue
		var path := SCENES.path_join(kind + ".tscn")
		if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
			_asked[kind] = path


## The time in the action of frame `name` (null when the kind has none).
func key_time(kind: String, name: String) -> Variant:
	var frames: Dictionary = kinds[kind]["frames"]
	var key: Variant = frames.get(name)
	if key == null:
		return null
	var at: float = key
	return at * KEY_TIME


## The kind's material: its looks bound, ready for per-model numbers.
func material(kind: String) -> ShaderMaterial:
	var m: ShaderMaterial = _materials.get(kind)
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = _shader
	var plain := _texture("actor3d_" + kind)
	for look: String in LOOKS:
		var name := "actor3d_" + kind + ("" if look == "" else "_" + look)
		var tex := _texture(name) if _assets.has_art(name) else plain
		m.set_shader_parameter("look_" + ("plain" if look == "" else look), tex)
	var info: Dictionary = kinds[kind]
	var lit: bool = info.get("lit", false)
	m.set_shader_parameter("baked_light", lit)
	var min_px: float = info.get("min_px", 0.0)
	m.set_shader_parameter("min_px", min_px)
	var light: float = info.get("light", 1.0)
	m.set_shader_parameter("light", light)
	_materials[kind] = m
	return m


## The bones of gear `name` (actors.json "gear": bone -> gear, a boss's hat
## or armour that can be shot off: features/boss_gear.gd).
func gear_bones(kind: String, name: String) -> Array[String]:
	var key := kind + ":" + name
	var known: Variant = _gear_bones.get(key)
	if known != null:
		var bones: Array[String] = known
		return bones
	var out: Array[String] = []
	var info: Dictionary = kinds.get(kind, {})
	var gear: Dictionary = info.get("gear", {})
	for bone: String in gear:
		if str(gear[bone]) == name:
			out.append(bone)
	_gear_bones[key] = out
	return out


## Gear `name` of the kind's model as a mesh of its own, for the piece shot
## off: [ArrayMesh, its middle in the model's rest frame (model units)], the
## mesh's own vertices about that middle; [] when the kind has no such gear.
## Made once from the rest frame (the bind pose) of the scene's skinned mesh.
func gear_mesh(kind: String, name: String) -> Array:
	var key := kind + ":" + name
	var cached: Variant = _gear_meshes.get(key)
	if cached != null:
		var found: Array = cached
		return found
	var out: Array = []
	_gear_meshes[key] = out
	var bones := gear_bones(kind, name)
	var packed := scene(kind)
	if bones.is_empty() or packed == null:
		return out
	var root := packed.instantiate() as Node3D
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			_gear_tris(mi, surface, bones, root, verts, normals, uvs)
	root.free()
	if verts.is_empty():
		return out
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	var middle := box.get_center()
	for i in verts.size():
		verts[i] -= middle
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.append(mesh)
	out.append(middle)
	return out


## The triangles of one surface whose corners are all bound to `bones`, put
## where the rest frame has them: the skeleton's place under `root` times the
## bone's rest times its bind pose (how Godot skins a mesh).
func _gear_tris(
	mi: MeshInstance3D,
	surface: int,
	bones: Array[String],
	root: Node3D,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array
) -> void:
	var skin := mi.skin
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skeleton == null:
		return
	var place := _to_root(skeleton, root)
	var binds := {}
	for b in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(b))
		var bone := skeleton.find_bone(bone_name) if bone_name != "" else skin.get_bind_bone(b)
		if bone >= 0 and bones.has(skeleton.get_bone_name(bone)):
			binds[b] = (place * skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(b))
	if binds.is_empty():
		return
	var arrays := mi.mesh.surface_get_arrays(surface)
	var at: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normal: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := ids.size() / maxi(1, at.size())
	if per == 0 or index.is_empty():
		return
	# Each corner's strongest bind (the binding is rigid: one bone a part).
	var owner := PackedInt32Array()
	owner.resize(at.size())
	for v in at.size():
		var best := -1
		var most := -1.0
		for k in per:
			if weights[v * per + k] > most:
				most = weights[v * per + k]
				best = ids[v * per + k]
		owner[v] = best
	for t in range(0, index.size() - 2, 3):
		var a := index[t]
		var b := index[t + 1]
		var c := index[t + 2]
		if not (binds.has(owner[a]) and binds.has(owner[b]) and binds.has(owner[c])):
			continue
		for v: int in [a, b, c]:
			var m: Transform3D = binds[owner[v]]
			verts.append(m * at[v])
			normals.append((m.basis * normal[v]).normalized())
			uvs.append(uv[v])


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			t = (at as Node3D).transform * t
		at = at.get_parent()
	return t


func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for m: ShaderMaterial in _materials.values():
		out.append(m)
	return out


func _texture(name: String) -> ImageTexture:
	var a := _assets.art_for_texture(name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	return ImageTexture.create_from_image(
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	)
