## The frame's sprites (Renderer.Sprite, from Game.sprites()) in the 3D view:
## one MultiMesh for the solid ones, one for the see-through ones (smoke,
## blasts, mist) drawn in list order. Pictures live in a texture array of
## SLOTS slots, kept by name, the least recently used given up for a new one.
class_name SpriteLayer3D
extends Node3D

const SLOTS := 160
const SLOT_SIZE := 256
const FLOATS := 20
const FLIP := 1
const GLOW := 4
const BODY := 8

var art: Texture2DArray
var solid: MultiMeshInstance3D
var clear: MultiMeshInstance3D
var solid_material: ShaderMaterial
var clear_material: ShaderMaterial
var _assets: Assets
var _slot_of := {}
var _slot_name: Array[String] = []
var _slot_used := PackedInt64Array()
var _slot_size: Array[Vector2i] = []
var _frame := 0
var _drop := {}
var _blank: Image


func _init(assets: Assets) -> void:
	_assets = assets
	_blank = Image.create_empty(SLOT_SIZE, SLOT_SIZE, false, Image.FORMAT_RGBA8)
	var blanks: Array[Image] = []
	for i in SLOTS:
		blanks.append(_blank)
	art = Texture2DArray.new()
	art.create_from_images(blanks)
	_slot_name.resize(SLOTS)
	_slot_used.resize(SLOTS)
	_slot_used.fill(-1)
	_slot_size.resize(SLOTS)
	var shader: Shader = load("res://src/view3d/sprite.gdshader")
	solid_material = ShaderMaterial.new()
	solid_material.shader = shader
	solid_material.set_shader_parameter("art", art)
	clear_material = ShaderMaterial.new()
	clear_material.shader = load("res://src/view3d/sprite_clear.gdshader")
	clear_material.set_shader_parameter("art", art)
	clear_material.render_priority = 1
	solid = _layer(solid_material)
	clear = _layer(clear_material)


func materials() -> Array[ShaderMaterial]:
	return [solid_material, clear_material]


func _layer(material: ShaderMaterial) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad()
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The instances move every frame: the box is set wide instead of worked out.
	node.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	add_child(node)
	return node


## A unit quad standing on its bottom edge: x -.5..5, y 0..1, uv top-left 0.
static func _quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(-.5, 0, 0), Vector3(-.5, 1, 0), Vector3(.5, 1, 0), Vector3(.5, 0, 0)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The slot holding `name`, uploading it if it is new.
func _slot(name: String) -> int:
	var slot: int = _slot_of.get(name, -1)
	if slot < 0:
		var oldest := _frame + 1
		for k in SLOTS:
			if _slot_used[k] < oldest:
				oldest = _slot_used[k]
				slot = k
		if _slot_name[slot] != "":
			_slot_of.erase(_slot_name[slot])
		var a := _assets.art(name)
		var w := int(a["w"])
		var h := int(a["h"])
		var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, a["data"])
		if w > SLOT_SIZE or h > SLOT_SIZE:
			var k := float(SLOT_SIZE) / maxf(w, h)
			w = maxi(1, int(w * k))
			h = maxi(1, int(h * k))
			image.resize(w, h, Image.INTERPOLATE_NEAREST)
		var page := _blank.duplicate() as Image
		page.blit_rect(image, Rect2i(0, 0, w, h), Vector2i.ZERO)
		RenderingServer.texture_2d_update(art.get_rid(), page, slot)
		_slot_name[slot] = name
		_slot_size[slot] = Vector2i(w, h)
		_slot_of[name] = slot
	_slot_used[slot] = _frame
	return slot


## How far a body's picture drops: its empty rows at the bottom, as a share
## of its height (RenderState.body_offset).
func _drop_of(name: String) -> float:
	var cached: Variant = _drop.get(name)
	if cached != null:
		return float(cached)
	var a := _assets.art(name)
	var w := int(a["w"])
	var h := int(a["h"])
	var data: PackedByteArray = a["data"]
	var last := -1
	for y in range(h - 1, -1, -1):
		var row := y * w * 4
		for x in w:
			if data[row + x * 4 + 3] > 100:
				last = y
				break
		if last >= 0:
			break
	var drop := float(h - 1 - last) / float(h) if last >= 0 else 0.0
	_drop[name] = drop
	return drop


## Lay out this frame's sprites. `eye` is the camera (x, y, z, angle).
func show_sprites(sprites: Array, level: LevelData, cam: Vector3, angle: float) -> void:
	_frame += 1
	var fx := cos(angle)
	var fy := sin(angle)
	var right := Vector3(-fy, 0.0, fx)
	var solid_buf := PackedFloat32Array()
	var clear_buf := PackedFloat32Array()
	var tints := level.tints
	var tint_max := maxi(0, tints.size() / 3 - 1)
	for item: Variant in sprites:
		var s := item as Renderer.Sprite
		if s == null or s.image == "":
			continue
		var dx := s.x - cam.x
		var dy := s.y - cam.y
		var ahead := dx * fx + dy * fy
		var limit := 51.0 if s.height > 2.7 else 32.0
		var board := not is_nan(s.plane)
		if not board and (ahead <= .13 or ahead >= limit):
			continue
		if board:
			var side := dx * sin(s.plane) - dy * cos(s.plane)
			if side <= .02 or ahead >= limit:
				continue
		var slot := _slot(s.image)
		var size := _slot_size[slot]
		var a := _assets.art(s.image)
		var width := s.height * float(a["w"]) / maxf(1.0, float(a["h"]))
		var axis := right
		if board:
			axis = Vector3(cos(s.plane), 0.0, sin(s.plane))
		var z := s.z
		if s.body:
			z -= s.height * _drop_of(s.image)
		var c := level.cell(
			clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01)
		)
		var area := 1 if s.glow else level.area[c]
		var ti := clampi(area, 0, tint_max) * 3
		var tint := Color(1, 1, 1)
		if tints.size() >= 3:
			tint = Color(tints[ti], tints[ti + 1], tints[ti + 2])
		var flags := (FLIP if s.flip else 0) | (GLOW if s.glow else 0) | (BODY if s.body else 0)
		var hurt := 0
		if s.hurt > 0.0:
			hurt = int(minf(.46, s.hurt / .18 * .44) * 100.0)
		var bx := axis * width
		var by := Vector3(0.0, s.height, 0.0)
		var bz := bx.cross(by).normalized()
		var row := PackedFloat32Array(
			[
				bx.x,
				by.x,
				bz.x,
				s.x,
				bx.y,
				by.y,
				bz.y,
				z,
				bx.z,
				by.z,
				bz.z,
				s.y,
				tint.r,
				tint.g,
				tint.b,
				level.light[c],
				float(slot),
				float(size.x),
				float(size.y),
				float(flags + hurt * 256)
			]
		)
		if s.translucent:
			clear_buf.append_array(row)
		else:
			solid_buf.append_array(row)
	_fill(solid, solid_buf)
	_fill(clear, clear_buf)


static func _fill(node: MultiMeshInstance3D, buf: PackedFloat32Array) -> void:
	var mm := node.multimesh
	var n := buf.size() / FLOATS
	if mm.instance_count < n:
		mm.instance_count = maxi(maxi(n, mm.instance_count * 2), 64)
	for i in n:
		var o := i * FLOATS
		var t := Transform3D(
			Vector3(buf[o], buf[o + 4], buf[o + 8]),
			Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
			Vector3(buf[o + 2], buf[o + 6], buf[o + 10]),
			Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15]))
		mm.set_instance_custom_data(i, Color(buf[o + 16], buf[o + 17], buf[o + 18], buf[o + 19]))
	mm.visible_instance_count = n
