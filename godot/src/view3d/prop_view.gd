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
## Its model's material (setup()); each part draws with a copy of its own
## (OwnMaterial: its tone and marks are the copy's numbers).
var material: ShaderMaterial

var _meshes: Array[MeshInstance3D] = []
var _turn := 0.0
var _lean := 0.0
var _size := 1.0
## The cell its light was last taken from (relight()).
var _lit_cell := -1


## Give every part of the model `material`; the prop shows to `reach` cells.
func setup(p_material: ShaderMaterial, reach: float) -> void:
	material = p_material
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		OwnMaterial.give(mesh, material)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = reach
		_meshes.append(mesh)


## The model's parts (what shots and fire mark: thing_marks.gd).
func meshes() -> Array[MeshInstance3D]:
	return _meshes


## The marks on its parts, to keep while it is not shown (ThingMarks.saved).
func take_marks() -> Array:
	return ThingMarks.saved(_meshes)


## Put back marks it had (take_marks), or another of its model's.
func give_marks(saved: Array) -> void:
	ThingMarks.restore(_meshes, saved)


## Show one look of a model that holds several (a quest station's mesh
## nodes `look_off` and `look_on`): the one named, every other hidden. A
## model without looks shows whole.
func show_look(look: String) -> void:
	for child in find_children("look_*", "Node3D", true, false):
		(child as Node3D).visible = child.name == "look_" + look


## Stand at map (x, y), feet at z, turned `turn` about up and `size` times its
## own size, lit by `level`.
func stand(x: float, y: float, z: float, turn: float, level: LevelData, size := 1.0) -> void:
	_turn = turn
	_lean = 0.0
	_size = size
	transform = Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), Vector3(x, z, y))
	_light(level.cell(clampf(x, 0.0, level.width - .01), clampf(y, 0.0, level.height - .01)), level)


## Lit by cell c's light and tint.
func _light(c: int, level: LevelData) -> void:
	_lit_cell = c
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	for mesh in _meshes:
		OwnMaterial.put(mesh, "tone", tone)


## Lit again by its cell's light and tint now (shown again after it was out
## of view: a lamp may have gone out meanwhile).
func light_again(level: LevelData) -> void:
	if _lit_cell >= 0 and _lit_cell < level.light.size():
		_light(_lit_cell, level)


## Turned by `turn` (Godot's axes) about its middle, its feet at z when it
## stands upright: a thing thrown and tumbling (features/carry.gd). `tall` is
## the model's own height.
func tumble(
	x: float, y: float, z: float, turn: Basis, level: LevelData, size: float, tall: float
) -> void:
	stand(x, y, z, _turn, level, size)
	var b := (turn * Basis(Vector3.UP, _turn)).scaled(Vector3.ONE * size)
	var middle := Vector3(x, z + tall * size * .5, y)
	transform = Transform3D(b, middle - b * Vector3(0.0, tall * .5, 0.0))


## Moved to map (x, y), feet at z, still turned the way it first stood and
## then by `tumble` (Godot axes) about its feet: a prop on the move
## (View.Sprite.track). Its light stays the cell's it was first stood in.
func carry(x: float, y: float, z: float, tumble: Basis) -> void:
	transform = Transform3D(
		(tumble * Basis(Vector3.UP, _turn)).scaled(Vector3.ONE * _size), Vector3(x, z, y)
	)


## Lit again by the cell it is in now when that changed (a vehicle driving
## from the sun into a shed: View.Sprite.body on a track).
func relight(x: float, y: float, level: LevelData) -> void:
	var c := level.cell(clampf(x, 0.0, level.width - .01), clampf(y, 0.0, level.height - .01))
	if c != _lit_cell:
		_light(c, level)


## Lean back about its feet by `tilt` radians, away from its front (a range
## dummy rocking on its post: View.Sprite.tilt).
func lean(tilt: float) -> void:
	if tilt == _lean:
		return
	_lean = tilt
	basis = (Basis(Vector3.UP, _turn) * Basis(Vector3.RIGHT, -tilt)).scaled(Vector3.ONE * _size)
