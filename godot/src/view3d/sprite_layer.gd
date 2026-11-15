## The frame's sprites (View.Sprite, from Game.sprites()) in the 3D view:
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
const BOARD := 16
## The flags' word also holds the hurt wash (x 256) and a billboard's turn
## (x SPIN_ONE, in SPINS steps): sprite_body.gdshaderinc's numbers.
const SPIN_ONE := 65536
const SPINS := 32

var art: Texture2DArray
var solid: MultiMeshInstance3D
var clear: MultiMeshInstance3D
var marks: MultiMeshInstance3D
## The player's reflection: on its own layer, which only the mirror's camera sees.
var reflection: MultiMeshInstance3D
var solid_material: ShaderMaterial
var clear_material: ShaderMaterial
var mark_material: ShaderMaterial
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
	mark_material = ShaderMaterial.new()
	mark_material.shader = load("res://src/view3d/mark.gdshader")
	mark_material.set_shader_parameter("art", art)
	mark_material.render_priority = 0
	solid = _layer(solid_material)
	clear = _layer(clear_material)
	marks = _layer(mark_material)
	reflection = _layer(solid_material)
	reflection.layers = 2


func materials() -> Array[ShaderMaterial]:
	return [solid_material, clear_material, mark_material]


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


## The art slot showing `name` this frame (call after show_sprites) and its
## picture's size in the slot: for the slabs' meshes (SlabLayer3D).
func slot(name: String) -> int:
	return _slot(name)


func slot_size(k: int) -> Vector2i:
	return _slot_size[k]


## The tint of the area at map (x, y) (rgb; a glowing sprite's is area 1's)
## and the cell's light (a), as a sprite there is lit.
static func tone_at(level: LevelData, x: float, y: float, glow: bool) -> Color:
	var c := level.cell(clampf(x, 0.0, level.width - .01), clampf(y, 0.0, level.height - .01))
	var tints := level.tints
	var area := 1 if glow else level.area[c]
	var ti := clampi(area, 0, maxi(0, tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if tints.size() >= 3:
		tone = Color(tints[ti], tints[ti + 1], tints[ti + 2], level.light[c])
	return tone


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
		var w: int = a["w"]
		var h: int = a["h"]
		var pixels: PackedByteArray = a["data"]
		var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels)
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
		var known: float = cached
		return known
	var a := _assets.art(name)
	var w: int = a["w"]
	var h: int = a["h"]
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


## Lay out this frame's sprites as seen from `cam` looking along `angle`.
## `everywhere` keeps the ones behind the eye too (a mirror may show them).
func show_sprites(
	sprites: Array, level: LevelData, cam: Vector3, angle: float, everywhere := false
) -> void:
	_frame += 1
	var fx := cos(angle)
	var fy := sin(angle)
	var solid_buf := PackedFloat32Array()
	var clear_buf := PackedFloat32Array()
	for item: Variant in sprites:
		if not item is View.Sprite:
			continue
		var s: View.Sprite = item
		if s.image == "":
			continue
		var dx := s.x - cam.x
		var dy := s.y - cam.y
		var ahead := dx * fx + dy * fy
		var limit := 51.0 if s.height > 2.7 else 32.0
		var board := not is_nan(s.plane)
		if not everywhere:
			if not board and (ahead <= .13 or ahead >= limit):
				continue
			if board and ahead >= limit:
				continue
		if board and dx * sin(s.plane) - dy * cos(s.plane) <= .02 and not everywhere:
			continue
		if s.translucent:
			clear_buf.append_array(_row(s, level, angle))
		else:
			solid_buf.append_array(_row(s, level, angle))
	fill(solid, solid_buf)
	fill(clear, clear_buf)


## The player as the mirror shows them (only the mirror's camera sees it).
func show_reflection(sprite: View.Sprite, level: LevelData, angle: float) -> void:
	var buf := PackedFloat32Array()
	if sprite != null and sprite.image != "":
		buf = _row(sprite, level, angle)
	fill(reflection, buf)


## One instance's 20 numbers: its transform (a billboard's width along the
## view's right, a board's along its own axis), its tint and light, its art
## slot and size, its flags and hit wash.
func _row(s: View.Sprite, level: LevelData, angle: float) -> PackedFloat32Array:
	var board := not is_nan(s.plane)
	var slot := _slot(s.image)
	var size := _slot_size[slot]
	var a := _assets.art(s.image)
	var art_w: float = a["w"]
	var art_h: float = a["h"]
	var width := s.height * art_w / maxf(1.0, art_h)
	var axis := Vector3(-sin(angle), 0.0, cos(angle))
	if board:
		axis = Vector3(cos(s.plane), 0.0, sin(s.plane))
	var z := s.z
	if s.body:
		z -= s.height * _drop_of(s.image)
	var tint := tone_at(level, s.x, s.y, s.glow)
	var flags := (
		(FLIP if s.flip else 0)
		| (GLOW if s.glow else 0)
		| (BODY if s.body else 0)
		| (BOARD if board else 0)
	)
	var hurt := 0
	if s.hurt > 0.0:
		hurt = int(minf(.46, s.hurt / .18 * .44) * 100.0)
	# A billboard turned over: SPINS steps of a turn (sprite_body.gdshaderinc).
	var spin := 0
	if s.spin != 0.0 and not board:
		spin = posmod(roundi(s.spin / TAU * SPINS), SPINS)
	var bx := axis * width
	var by := Vector3(0.0, s.height, 0.0)
	var bz := bx.cross(by).normalized()
	return PackedFloat32Array(
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
			tint.a,
			float(slot),
			float(size.x),
			float(size.y),
			float(flags + hurt * 256 + spin * SPIN_ONE)
		]
	)


## Lay out this frame's wall marks (View.WallMark: a square of half side
## `radius` on the wall along (ux, uy)) and ground marks (View.GroundMark:
## a rectangle at z, `reach` along `angle` and `width` across, both halves),
## as far as the old renderer drew them (15 and 26 cells).
func show_marks(walls: Array, grounds: Array, cam: Vector3, angle: float) -> void:
	var fx := cos(angle)
	var fy := sin(angle)
	var buf := PackedFloat32Array()
	for item: Variant in walls:
		if not item is View.WallMark:
			continue
		var m: View.WallMark = item
		var d := (m.x - cam.x) * fx + (m.y - cam.y) * fy
		if d <= .19 or d >= 15.0:
			continue
		var slot := _slot(m.image)
		var size := _slot_size[slot]
		var bx := Vector3(m.ux, 0.0, m.uy) * (2.0 * m.radius)
		var by := Vector3(0.0, 2.0 * m.radius, 0.0)
		var bz := Vector3(-m.uy, 0.0, m.ux)
		buf.append_array(
			PackedFloat32Array(
				[
					bx.x,
					by.x,
					bz.x,
					m.x,
					bx.y,
					by.y,
					bz.y,
					m.z - m.radius,
					bx.z,
					by.z,
					bz.z,
					m.y,
					1.0,
					1.0,
					1.0,
					1.0,
					float(slot),
					float(size.x),
					float(size.y),
					0.0
				]
			)
		)
	for item: Variant in grounds:
		if not item is View.GroundMark:
			continue
		var g: View.GroundMark = item
		if cam.z <= g.z + .015:
			continue
		if Vector2(g.x - cam.x, g.y - cam.y).length() > 26.0:
			continue
		var slot := _slot(g.image)
		var size := _slot_size[slot]
		var dir := Vector3(cos(g.angle), 0.0, sin(g.angle))
		var across := Vector3(-sin(g.angle), 0.0, cos(g.angle))
		var bx := dir * (2.0 * g.reach)
		var by := across * (-2.0 * g.width)
		var at := Vector3(g.x, g.z, g.y) + across * g.width
		if g.gx != 0.0 or g.gy != 0.0:
			# On a slope: the rectangle tilted onto it (Godot y is up, z is map y).
			bx.y = g.gx * bx.x + g.gy * bx.z
			by.y = g.gx * by.x + g.gy * by.z
			at.y += g.gx * (at.x - g.x) + g.gy * (at.z - g.y)
		buf.append_array(
			PackedFloat32Array(
				[
					bx.x,
					by.x,
					0.0,
					at.x,
					bx.y,
					by.y,
					1.0,
					at.y,
					bx.z,
					by.z,
					0.0,
					at.z,
					1.0,
					1.0,
					1.0,
					1.0,
					float(slot),
					float(size.x),
					float(size.y),
					1.0
				]
			)
		)
	fill(marks, buf)


static func fill(node: MultiMeshInstance3D, buf: PackedFloat32Array) -> void:
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
