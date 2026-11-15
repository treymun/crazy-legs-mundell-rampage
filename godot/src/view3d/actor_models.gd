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

## kind -> {frames: {name: key}, height, textures: [...], ...}
var kinds: Dictionary = {}
var _scenes: Dictionary = {}
var _materials: Dictionary = {}
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


func has(kind: String) -> bool:
	return (
		kinds.has(kind)
		and _assets.has_art("actor3d_" + kind)
		and ResourceLoader.exists(SCENES.path_join(kind + ".tscn"))
	)


## The kind's scene (an ActorView), or null when it has none.
func scene(kind: String) -> PackedScene:
	var cached: Variant = _scenes.get(kind)
	if cached == null:
		var path := SCENES.path_join(kind + ".tscn")
		cached = load(path) if ResourceLoader.exists(path) else null
		_scenes[kind] = cached
	var packed: PackedScene = cached
	return packed


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
	_materials[kind] = m
	return m


func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for m: ShaderMaterial in _materials.values():
		out.append(m)
	return out


func _texture(name: String) -> ImageTexture:
	var a := _assets.art(name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	return ImageTexture.create_from_image(
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	)
