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
## A pickup's slab (slab_layer.gd): in the dark it takes the moon's rim.
const ITEM := 32
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
## picture -> its size (w, h), asked for every sprite every frame.
var _sizes := {}
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
	# Room for every row at once (each put() grew the arrays by one row).
	solid_buf.resize(sprites.size() * FLOATS)
	clear_buf.resize(sprites.size() * FLOATS)
	var rows := Vector2i.ZERO
	var across := Vector3(-sin(angle), 0.0, cos(angle))
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
			_row(clear_buf, rows.y, s, level, across)
			rows.y += 1
		else:
			_row(solid_buf, rows.x, s, level, across)
			rows.x += 1
	solid_buf.resize(rows.x * FLOATS)
	clear_buf.resize(rows.y * FLOATS)
	fill(solid, solid_buf)
	fill(clear, clear_buf)


## The player as the mirror shows them (only the mirror's camera sees it).
func show_reflection(sprite: View.Sprite, level: LevelData, angle: float) -> void:
	var buf := PackedFloat32Array()
	if sprite != null and sprite.image != "":
		buf.resize(FLOATS)
		_row(buf, 0, sprite, level, Vector3(-sin(angle), 0.0, cos(angle)))
	fill(reflection, buf)


## One instance's 20 numbers, row `at` of `buf`: its transform (a billboard's
## width along the view's right, `across`, a board's along its own axis),
## its tint and light, its art slot and size, its flags and hit wash. The
## calls a row made (the slot, the tone, put_at) are written out here: a row
## for every sprite every frame, hundreds of them in a busy moment (pass 10).
func _row(
	buf: PackedFloat32Array, at: int, s: View.Sprite, level: LevelData, across: Vector3
) -> void:
	var board := not is_nan(s.plane)
	var image := s.image
	var slot: int = _slot_of.get(image, -1)
	if slot < 0:
		slot = _slot(image)
	else:
		_slot_used[slot] = _frame
	var size := _slot_size[slot]
	var art_size: Variant = _sizes.get(image)
	if art_size == null:
		var a := _assets.art(image)
		var w: int = a["w"]
		var h: int = a["h"]
		art_size = Vector2(w, h)
		# A picture still coming (a blank stand-in) is asked again next time.
		if _assets.art_ready(image):
			_sizes[image] = art_size
	var art_wh: Vector2 = art_size
	var width := s.height * art_wh.x / maxf(1.0, art_wh.y)
	var axis := across
	if board:
		axis = Vector3(cos(s.plane), 0.0, sin(s.plane))
	var z := s.z
	if s.body:
		z -= s.height * _drop_of(image)
	# tone_at(level, s.x, s.y, s.glow), written out.
	var c := (
		int(clampf(s.y, 0.0, level.height - .01)) * level.width
		+ int(clampf(s.x, 0.0, level.width - .01))
	)
	var tints := level.tints
	var light: float = level.light[c]
	var tint := Color(1, 1, 1, light)
	if tints.size() >= 3:
		var ti := clampi(1 if s.glow else level.area[c], 0, maxi(0, tints.size() / 3 - 1)) * 3
		tint = Color(tints[ti], tints[ti + 1], tints[ti + 2], light)
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
	# put_at(buf, at, bx, by, bz, origin, tint, art), written out.
	var k := at * FLOATS
	buf[k] = bx.x
	buf[k + 1] = by.x
	buf[k + 2] = bz.x
	buf[k + 3] = s.x
	buf[k + 4] = bx.y
	buf[k + 5] = by.y
	buf[k + 6] = bz.y
	buf[k + 7] = z
	buf[k + 8] = bx.z
	buf[k + 9] = by.z
	buf[k + 10] = bz.z
	buf[k + 11] = s.y
	buf[k + 12] = tint.r
	buf[k + 13] = tint.g
	buf[k + 14] = tint.b
	buf[k + 15] = tint.a
	buf[k + 16] = slot
	buf[k + 17] = size.x
	buf[k + 18] = size.y
	buf[k + 19] = flags + hurt * 256 + spin * SPIN_ONE


## Lay out this frame's wall marks (View.WallMark: a square of half side
## `radius` on the wall along (ux, uy)) and ground marks (View.GroundMark:
## a rectangle at z, `reach` along `angle` and `width` across, both halves),
## as far as the old renderer drew them (15 and 26 cells).
func show_marks(walls: Array, grounds: Array, cam: Vector3, angle: float) -> void:
	var fx := cos(angle)
	var fy := sin(angle)
	var buf := PackedFloat32Array()
	# Room for every mark at once (put() grew it a row at a time).
	buf.resize((walls.size() + grounds.size()) * FLOATS)
	var n := 0
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
		put_at(
			buf,
			n,
			bx,
			by,
			bz,
			Vector3(m.x, m.z - m.radius, m.y),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(float(slot), float(size.x), float(size.y), 0.0)
		)
		n += 1
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
		put_at(
			buf,
			n,
			bx,
			by,
			Vector3(0.0, 1.0, 0.0),
			at,
			Color(1.0, 1.0, 1.0, 1.0),
			Color(float(slot), float(size.x), float(size.y), 1.0)
		)
		n += 1
	buf.resize(n * FLOATS)
	fill(marks, buf)


## Add one instance's FLOATS numbers to `buf` in the MultiMesh's layout: the
## basis columns bx, by, bz and the origin as a 3x4 matrix by rows, the
## colour, the custom data. (Written in place: a Packed array made from a
## list of twenty numbers for each sprite cost more than the rest of a row.)
static func put(
	buf: PackedFloat32Array, bx: Vector3, by: Vector3, bz: Vector3, o: Vector3, c: Color, d: Color
) -> void:
	var at := buf.size() / FLOATS
	buf.resize(buf.size() + FLOATS)
	put_at(buf, at, bx, by, bz, o, c, d)


## put() into row `at` of a buffer already that long.
static func put_at(
	buf: PackedFloat32Array,
	at: int,
	bx: Vector3,
	by: Vector3,
	bz: Vector3,
	o: Vector3,
	c: Color,
	d: Color
) -> void:
	var i := at * FLOATS
	buf[i] = bx.x
	buf[i + 1] = by.x
	buf[i + 2] = bz.x
	buf[i + 3] = o.x
	buf[i + 4] = bx.y
	buf[i + 5] = by.y
	buf[i + 6] = bz.y
	buf[i + 7] = o.y
	buf[i + 8] = bx.z
	buf[i + 9] = by.z
	buf[i + 10] = bz.z
	buf[i + 11] = o.z
	buf[i + 12] = c.r
	buf[i + 13] = c.g
	buf[i + 14] = c.b
	buf[i + 15] = c.a
	buf[i + 16] = d.r
	buf[i + 17] = d.g
	buf[i + 18] = d.b
	buf[i + 19] = d.a


## Hand `buf` (FLOATS numbers an instance, in the MultiMesh's own layout: a
## 3x4 transform by rows, the colour, the custom data) to the node's
## MultiMesh in one call, instead of three calls an instance.
static func fill(node: MultiMeshInstance3D, buf: PackedFloat32Array) -> void:
	var mm := node.multimesh
	var n := buf.size() / FLOATS
	if mm.instance_count < n:
		mm.instance_count = maxi(maxi(n, mm.instance_count * 2), 64)
	if n > 0:
		# The buffer must cover every instance; those past n are not drawn.
		buf.resize(mm.instance_count * FLOATS)
		RenderingServer.multimesh_set_buffer(mm.get_rid(), buf)
		buf.resize(n * FLOATS)
	mm.visible_instance_count = n
