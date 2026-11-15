## The pickups of the 3D view: each sprite showing an `item_*` picture is
## drawn as that picture's slab (PickupModels) where the sprite stood, the
## same height off the floor and the same size from the front. One MultiMesh
## per picture; the art comes from the sprites' texture array (SpriteLayer3D
## slots), so the light, tint, fog and palette are the sprites' own
## (pickup.gdshader).
##
## Looks only: each pickup turns slowly on the game clock (the bob is the
## sprite's, game_view.gd). EASY ON THE EYES (View.world_motion) slows the
## turn (REDUCED) or stops it (STILL), where a pickup faces the eye as the
## sprite did.
class_name PickupLayer3D
extends Node3D

## Radians a second at full motion (about one turn in seven seconds).
const TURN := .9
## How fast each EASY ON THE EYES step turns (FULL, REDUCED, STILL).
const MOTION := [1.0, .4, 0.0]
## As far ahead as the sprite was drawn (sprite_layer.gd), and how far behind
## the eye a slab's near side may still reach into the view.
const REACH := 32.0
const BEHIND := -.3

var models: PickupModels
var material: ShaderMaterial
var _sprites: SpriteLayer3D
## image -> MultiMeshInstance3D
var _shown: Dictionary = {}


func _init(p_models: PickupModels, sprites: SpriteLayer3D) -> void:
	models = p_models
	_sprites = sprites
	material = ShaderMaterial.new()
	material.shader = load("res://src/view3d/pickup.gdshader")
	material.set_shader_parameter("art", sprites.art)


## True when sprite `s` is drawn here (a pickup's picture with a mesh).
func takes(s: View.Sprite) -> bool:
	return (
		PickupModels.is_pickup(s.image)
		and is_nan(s.plane)
		and not s.translucent
		and models.mesh(s.image) != null
	)


## Show these sprites (each one `takes`) and no other pickups, seen from
## `cam` looking along `angle`; `everywhere` keeps the ones behind the eye
## (the mirror may show them). Call after SpriteLayer3D.show_sprites.
func show_pickups(
	list: Array,
	level: LevelData,
	cam: Vector3,
	angle: float,
	clock: float,
	motion: int,
	everywhere := false
) -> void:
	var fx := cos(angle)
	var fy := sin(angle)
	var speed: float = MOTION[clampi(motion, 0, 2)]
	# STILL: the front (+Z) toward the eye, square to the view as the sprite.
	var facing := atan2(-fx, -fy)
	var rows := {}
	for item: Variant in list:
		var s: View.Sprite = item
		var ahead := (s.x - cam.x) * fx + (s.y - cam.y) * fy
		if ahead >= REACH or (ahead <= BEHIND and not everywhere):
			continue
		var turn := facing
		if speed > 0.0:
			turn = fposmod(clock * TURN * speed + s.x * 1.7 + s.y * 2.3, TAU)
		var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * s.height)
		var tone := SpriteLayer3D.tone_at(level, s.x, s.y, s.glow)
		var slot := _sprites.slot(s.image)
		var size := _sprites.slot_size(slot)
		var flags := SpriteLayer3D.GLOW if s.glow else 0
		var buf: PackedFloat32Array = rows.get(s.image, PackedFloat32Array())
		buf.append_array(
			PackedFloat32Array(
				[
					basis.x.x,
					basis.y.x,
					basis.z.x,
					s.x,
					basis.x.y,
					basis.y.y,
					basis.z.y,
					s.z,
					basis.x.z,
					basis.y.z,
					basis.z.z,
					s.y,
					tone.r,
					tone.g,
					tone.b,
					tone.a,
					float(slot),
					float(size.x),
					float(size.y),
					float(flags)
				]
			)
		)
		rows[s.image] = buf
	for image: String in rows:
		var node: MultiMeshInstance3D = _shown.get(image)
		if node == null:
			node = _layer(models.mesh(image))
			_shown[image] = node
		var filled: PackedFloat32Array = rows[image]
		SpriteLayer3D.fill(node, filled)
	for image: String in _shown:
		if not rows.has(image):
			var idle: MultiMeshInstance3D = _shown[image]
			idle.multimesh.visible_instance_count = 0


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
	# The pickups are spread over the level: the box is set wide.
	node.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	add_child(node)
	return node
