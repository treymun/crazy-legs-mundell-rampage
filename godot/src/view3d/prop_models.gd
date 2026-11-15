## The props that have a mesh for the 3D view (godot/assets3d/props, made by
## tools/art/build_prop_meshes.gd): a sprite showing `town_<name>` is drawn as
## that mesh instead, with its baked texture `mesh_<name>` from the art.
class_name PropModels
extends RefCounted

const FOLDER := "res://assets3d/props"
## Each prop's scene: a PropView over its mesh (tools/art/build_prop_scenes.gd).
const SCENES := "res://scenes/props"

## name -> [width, depth, height, texture size]
var sizes: Dictionary = {}
var _meshes: Dictionary = {}
var _scenes: Dictionary = {}
var _textures: Dictionary = {}
var _assets: Assets


func _init(assets: Assets) -> void:
	_assets = assets
	var path := FOLDER.path_join("meshes.json")
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			sizes = data


## The prop name a sprite's picture stands for, or "" when it has no mesh.
func name_of(image: String) -> String:
	if not image.begins_with("town_"):
		return ""
	var name := image.substr(5)
	if not sizes.has(name) or not _assets.has_art("mesh_" + name):
		return ""
	return name if ResourceLoader.exists(SCENES.path_join(name + ".tscn")) else ""


## The prop's scene (a PropView), or null when it has none.
func scene(name: String) -> PackedScene:
	var cached: Variant = _scenes.get(name)
	if cached == null:
		var path := SCENES.path_join(name + ".tscn")
		cached = load(path) if ResourceLoader.exists(path) else null
		_scenes[name] = cached
	return cached as PackedScene


func mesh(name: String) -> Mesh:
	var cached: Variant = _meshes.get(name)
	if cached != null:
		return cached
	var found: Mesh = null
	var scene := load(FOLDER.path_join(name + ".glb")) as PackedScene
	if scene != null:
		var root := scene.instantiate()
		found = _first_mesh(root)
		root.free()
	_meshes[name] = found
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _first_mesh(child)
		if m != null:
			return m
	return null


func texture(name: String) -> ImageTexture:
	var cached: Variant = _textures.get(name)
	if cached != null:
		return cached
	var a := _assets.art("mesh_" + name)
	var image := Image.create_from_data(
		int(a["w"]), int(a["h"]), false, Image.FORMAT_RGBA8, a["data"]
	)
	var tex := ImageTexture.create_from_image(image)
	_textures[name] = tex
	return tex
