## One modelled prop in the 3D view: the root of its scene
## (scenes/props/<name>.tscn, made by tools/art/build_prop_scenes.gd: this
## script over the prop's baked mesh from assets3d/props). It stands where the
## prop's sprite stood, turned as the layer says, lit by the level's light
## and tint in its cell, with its baked texture (`mesh_<name>`). Anything
## added under the model in the scene (a lamp, a flame) stands with it.
class_name PropView
extends Node3D

## The prop's name (meshes.json, town_<name> sprites, mesh_<name> texture).
@export var prop := ""

var _meshes: Array[MeshInstance3D] = []


## Give every part of the model `material`; the prop shows to `reach` cells.
func setup(material: ShaderMaterial, reach: float) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = reach
		_meshes.append(mesh)


## Stand at map (x, y), feet at z, turned `turn` about up, lit by `level`.
func stand(x: float, y: float, z: float, turn: float, level: LevelData) -> void:
	transform = Transform3D(Basis(Vector3.UP, turn), Vector3(x, z, y))
	var c := level.cell(clampf(x, 0.0, level.width - .01), clampf(y, 0.0, level.height - .01))
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	for mesh in _meshes:
		mesh.set_instance_shader_parameter("tone", tone)
