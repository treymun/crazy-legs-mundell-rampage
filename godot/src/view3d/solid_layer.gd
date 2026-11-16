## The solid bodies of the 3D view: sprites with `solid` set (a bowling pin,
## a bowling ball) drawn as real meshes turned by their own turn, one
## MultiMesh a kind, lit, tinted, fogged and paletted as the sprites
## (solid.gdshader). The meshes are built here at start: a pin turned on a
## lathe from a real pin's profile (foot, belly, neck with its two red
## stripes, head), a ball with its three finger holes. A mesh is in cells, in
## Godot's axes (y up): a pin stands on its foot at the origin, the ball's
## middle is at the origin.
##
## Each face carries its material in UV.x (solid.gdshader's PAINT). The newer
## kinds (solid_kit.gd: horseshoes, skee-ball, bottles, the dunk tank, the
## fair's and the trophy shack's) carry their own colour and are built the
## first time one is seen.
class_name SolidLayer3D
extends Node3D

## Materials (solid.gdshader's PAINT).
const WHITE := 0
const RED := 1
const BAND := 2
const BALL := 3
const HOLE := 4
const SWIRL := 5
## A pin's profile from its foot: [height, radius, material of the band up to
## the next ring] (cells; a real pin is 15 inches, 4.77 across the belly).
const PIN := [
	[0.0, .0, WHITE],
	[0.0, .028, WHITE],
	[.021, .044, WHITE],
	[.062, .061, WHITE],
	[.125, .066, WHITE],
	[.188, .058, WHITE],
	[.229, .044, WHITE],
	[.246, .036, RED],
	[.258, .032, WHITE],
	[.266, .029, RED],
	[.278, .026, WHITE],
	[.3, .027, WHITE],
	[.33, .032, WHITE],
	[.362, .035, WHITE],
	[.394, .031, WHITE],
	[.411, .019, WHITE],
	[.417, .0, WHITE],
]
## The pin drawn this much stouter than a real one, as the old picture of it
## was (its body is a real pin's: range_pin_physics.gd).
const CHUNK := 1.12
## Sides round a pin, and the ball's slices and stacks.
const PIN_SIDES := 12
const BALL_R := .118
const BALL_SLICES := 18
const BALL_STACKS := 12
## The finger holes: directions from the ball's middle (unit), and how far
## round each reaches (the cosine of its half angle).
const HOLES := [Vector3(0.0, 0.0, 1.0), Vector3(.34, .2, .92), Vector3(-.3, .25, .92)]
const HOLE_REACH := .955
## As far ahead as sprites are drawn.
const REACH := 32.0
const BEHIND := -.6

var material: ShaderMaterial
var _meshes := {}
var _shown := {}


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://src/view3d/solid.gdshader")
	_meshes["pin"] = pin_mesh()
	_meshes["ball"] = ball_mesh()


static func takes(s: View.Sprite) -> bool:
	return s.solid != ""


## Show these sprites (each with `solid`) seen from `cam` looking along
## `angle`; `everywhere` keeps those behind the eye (for the mirror).
func show_solids(
	list: Array, level: LevelData, cam: Vector3, angle: float, everywhere := false
) -> void:
	var fx := cos(angle)
	var fy := sin(angle)
	var rows := {}
	for item: Variant in list:
		var s: View.Sprite = item
		if not _meshes.has(s.solid):
			# The midway games', the fair's and the trophies' (solid_kit.gd), built
			# the first time one is seen.
			var made := SolidKit.mesh_of(s.solid)
			if made == null:
				continue
			_meshes[s.solid] = made
		var ahead := (s.x - cam.x) * fx + (s.y - cam.y) * fy
		if ahead >= REACH or (ahead <= BEHIND and not everywhere):
			continue
		var g := godot_basis(s.turn)
		var tone := SpriteLayer3D.tone_at(level, s.x, s.y, s.glow)
		var buf: PackedFloat32Array = rows.get(s.solid, PackedFloat32Array())
		SpriteLayer3D.put(
			buf,
			g.x,
			g.y,
			g.z,
			Vector3(s.x, s.z, s.y),
			tone,
			Color(0.0, 0.0, 0.0, float(SpriteLayer3D.GLOW if s.glow else 0))
		)
		rows[s.solid] = buf
	for kind: String in rows:
		var node: MultiMeshInstance3D = _shown.get(kind)
		if node == null:
			var mesh: ArrayMesh = _meshes[kind]
			node = _layer(mesh)
			_shown[kind] = node
		var filled: PackedFloat32Array = rows[kind]
		SpriteLayer3D.fill(node, filled)
	for kind: String in _shown:
		if not rows.has(kind):
			var idle: MultiMeshInstance3D = _shown[kind]
			idle.multimesh.visible_instance_count = 0


## A turn in map axes (x, y across, z up) as one in Godot's (y up): the same
## turn seen with y and z swapped.
static func godot_basis(m: Basis) -> Basis:
	return Basis(_swap(m.x), _swap(m.z), _swap(m.y))


static func _swap(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, v.y)


func _layer(mesh: ArrayMesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	add_child(node)
	return node


## The pin: its profile turned round the y axis, each band its material,
## smooth normals round and along (from the profile's slope).
static func pin_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in PIN.size() - 1:
		var lo: Array = PIN[i]
		var hi: Array = PIN[i + 1]
		var y0: float = lo[0]
		var r0: float = lo[1] * CHUNK
		var y1: float = hi[0]
		var r1: float = hi[1] * CHUNK
		var paint: int = lo[2]
		var n0 := _profile_normal(i)
		var n1 := _profile_normal(i + 1)
		for k in PIN_SIDES:
			var a0 := k * TAU / PIN_SIDES
			var a1 := (k + 1) * TAU / PIN_SIDES
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var q00 := Vector3(cos(a0) * n0.x, n0.y, sin(a0) * n0.x)
			var q01 := Vector3(cos(a1) * n0.x, n0.y, sin(a1) * n0.x)
			var q10 := Vector3(cos(a0) * n1.x, n1.y, sin(a0) * n1.x)
			var q11 := Vector3(cos(a1) * n1.x, n1.y, sin(a1) * n1.x)
			var uv := Vector2(paint, 0.0)
			# Outward faces, wound clockwise seen from outside (Godot's front).
			for v: Array in [
				[p00, q00], [p11, q11], [p10, q10], [p00, q00], [p01, q01], [p11, q11]
			]:
				var pv: Vector3 = v[0]
				var nv: Vector3 = v[1]
				verts.append(pv)
				normals.append(nv)
				uvs.append(uv)
	return _mesh(verts, normals, uvs)


## The outward normal of the pin's side at profile ring `i` (x: out, y: up).
static func _profile_normal(i: int) -> Vector2:
	var prev: Array = PIN[maxi(0, i - 1)]
	var next: Array = PIN[mini(PIN.size() - 1, i + 1)]
	var dy: float = next[0] - prev[0]
	var dr: float = next[1] - prev[1]
	var n := Vector2(dy, -dr)
	if n.length_squared() < 1e-10:
		return Vector2(0.0, 1.0 if i > PIN.size() / 2 else -1.0)
	return n.normalized()


## The ball: a sphere, its finger holes dark, a swirl through its colour.
static func ball_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in BALL_STACKS:
		var t0 := PI * j / BALL_STACKS
		var t1 := PI * (j + 1) / BALL_STACKS
		for k in BALL_SLICES:
			var a0 := TAU * k / BALL_SLICES
			var a1 := TAU * (k + 1) / BALL_SLICES
			var n00 := _sphere(t0, a0)
			var n01 := _sphere(t0, a1)
			var n10 := _sphere(t1, a0)
			var n11 := _sphere(t1, a1)
			var mid := (n00 + n01 + n10 + n11).normalized()
			var paint := BALL
			for hole: Vector3 in HOLES:
				if mid.dot(hole.normalized()) > HOLE_REACH:
					paint = HOLE
			if paint == BALL and sin(mid.x * 9.0 + mid.y * 5.0) * cos(mid.z * 7.0) > .55:
				paint = SWIRL
			var uv := Vector2(paint, 0.0)
			for n: Vector3 in [n00, n11, n01, n00, n10, n11]:
				verts.append(n * BALL_R)
				normals.append(n)
				uvs.append(uv)
	return _mesh(verts, normals, uvs)


static func _sphere(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))


static func _mesh(
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
